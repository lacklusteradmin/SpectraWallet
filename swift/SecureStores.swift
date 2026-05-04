import Foundation
import KeychainAccess
enum KeychainStoreError: Error, Equatable {
    case missingValue
    case invalidEncoding
}

private struct KeychainBackedSecureStore: @unchecked Sendable {
    private let keychain: Keychain
    typealias StoreError = KeychainStoreError
    init(service: String) {
        keychain = Keychain(service: service).accessibility(.whenPasscodeSetThisDeviceOnly)
    }
    func save(_ value: String, for account: String) throws { try saveData(Data(value.utf8), for: account) }
    func saveData(_ data: Data, for account: String) throws { try keychain.set(data, key: account) }
    func loadValue(for account: String) throws -> String {
        guard let data = try loadData(for: account) else { throw StoreError.missingValue }
        guard let value = String(data: data, encoding: .utf8) else { throw StoreError.invalidEncoding }
        return value
    }
    func loadData(for account: String) throws -> Data? { try keychain.getData(account) }
    func deleteValue(for account: String) throws { try keychain.remove(account) }
    func deleteAllValues() throws { try keychain.removeAll() }
}
private enum SecureRandom {
    static func data(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return Data((0..<length).map { _ in UInt8.random(in: .min ... .max) }) }
        return Data(bytes)
    }
}
enum SecureStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.pricing")
    static func save(_ value: String, for account: String) { try? storage.save(value, for: account) }
    static func saveData(_ data: Data, for account: String) { try? storage.saveData(data, for: account) }
    static func loadValue(for account: String) -> String { (try? storage.loadValue(for: account)) ?? "" }
    static func loadData(for account: String) -> Data? { try? storage.loadData(for: account) }
    static func deleteValue(for account: String) { try? storage.deleteValue(for: account) }
    static func deleteAllValues() { try? storage.deleteAllValues() }
}
private enum SeedMaterialEnvelope {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.masterkey")
    private static let masterKeyAccount = "seed.material.masterkey"
    private static func masterKeyBytes() -> Data {
        if let storedData = (try? storage.loadData(for: masterKeyAccount)) ?? nil, storedData.count == 32 { return storedData }
        let generated = SecureRandom.data(length: 32)
        try? storage.saveData(generated, for: masterKeyAccount)
        return generated
    }
    static func encode(_ seedPhrase: String) -> Data {
        let key = masterKeyBytes()
        guard let encrypted = try? encryptSeedEnvelope(plaintext: seedPhrase, masterKeyBytes: key) else { return Data(seedPhrase.utf8) }
        return encrypted
    }
    static func decode(_ data: Data) -> String? {
        let key = masterKeyBytes()
        return try? decryptSeedEnvelope(data: data, masterKeyBytes: key)
    }
}
enum SecureSeedStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed")
    static func save(_ value: String, for account: String) throws { try storage.saveData(SeedMaterialEnvelope.encode(value), for: account) }
    static func loadValue(for account: String) throws -> String {
        guard let data = try storage.loadData(for: account), let value = SeedMaterialEnvelope.decode(data) else {
            throw KeychainBackedSecureStore.StoreError.missingValue
        }
        return value
    }
    static func loadData(for account: String) throws -> Data? { try storage.loadData(for: account) }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
    static func deleteAllValues() throws { try storage.deleteAllValues() }
}
enum SecureSeedPasswordStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.password")
    static func save(_ password: String, for account: String) throws {
        let normalized = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try deleteValue(for: account)
            return
        }
        let verifierData = try createPasswordVerifier(password: normalized)
        try storage.saveData(verifierData, for: account)
    }
    static func hasPassword(for account: String) -> Bool { (try? storage.loadData(for: account)) != nil }
    static func verify(_ password: String, for account: String) -> Bool {
        let normalized = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let data = try? storage.loadData(for: account) else { return false }
        return verifyPasswordVerifier(password: normalized, verifierData: data)
    }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
    static func deleteAllValues() throws { try storage.deleteAllValues() }
}
enum SecurePrivateKeyStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.privatekey")
    static func save(_ value: String, for account: String) { try? storage.save(value, for: account) }
    static func loadValue(for account: String) -> String { (try? storage.loadValue(for: account)) ?? "" }
    static func deleteValue(for account: String) { try? storage.deleteValue(for: account) }
    static func deleteAllValues() { try? storage.deleteAllValues() }
}

final class SpectraSecretStoreAdapter: SecretStore, @unchecked Sendable {
    static func registerWithBridge() {
        let adapter = SpectraSecretStoreAdapter()
        Task {
            try? await WalletServiceBridge.shared.registerSecretStore(adapter)
        }
    }

    func loadSecret(kind: SecretClass, key: String) throws -> String {
        switch kind {
        case .seed:
            do {
                return try SecureSeedStore.loadValue(for: key)
            } catch KeychainStoreError.missingValue {
                throw SecretStoreError.NotFound
            } catch {
                throw SecretStoreError.Backend(message: String(describing: error))
            }
        case .privateKey:
            let value = SecurePrivateKeyStore.loadValue(for: key)
            if value.isEmpty { throw SecretStoreError.NotFound }
            return value
        case .generic:
            let value = SecureStore.loadValue(for: key)
            if value.isEmpty { throw SecretStoreError.NotFound }
            return value
        }
    }

    func saveSecret(kind: SecretClass, key: String, value: String) throws {
        switch kind {
        case .seed:
            do { try SecureSeedStore.save(value, for: key) } catch { throw SecretStoreError.Backend(message: String(describing: error)) }
        case .privateKey:
            SecurePrivateKeyStore.save(value, for: key)
        case .generic:
            SecureStore.save(value, for: key)
        }
    }

    func deleteSecret(kind: SecretClass, key: String) throws {
        switch kind {
        case .seed:
            do { try SecureSeedStore.deleteValue(for: key) } catch { throw SecretStoreError.Backend(message: String(describing: error)) }
        case .privateKey:
            SecurePrivateKeyStore.deleteValue(for: key)
        case .generic:
            SecureStore.deleteValue(for: key)
        }
    }

    func listKeys(kind: SecretClass, prefixFilter: String) throws -> [String] {
        return []
    }
}
