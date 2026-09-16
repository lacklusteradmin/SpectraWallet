import Foundation
import KeychainAccess
enum KeychainStoreError: Error, Equatable {
    case missingValue
    case invalidEncoding
    /// The seed master key could not be read, created, or persisted. No seed
    /// may be written while this is true: an envelope sealed under a key that
    /// never reached the Keychain cannot be opened again after a relaunch.
    case masterKeyUnavailable(String)
    /// Envelope encryption failed. Storing the seed regardless would mean
    /// storing it in plaintext.
    case sealFailed(String)
}

extension KeychainStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingValue: return "No value is stored for this item."
        case .invalidEncoding: return "The stored value is not valid UTF-8."
        case .masterKeyUnavailable(let detail): return "The seed encryption key is unavailable: \(detail)"
        case .sealFailed(let detail): return "The seed could not be encrypted: \(detail)"
        }
    }
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
enum SecureStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.pricing")
    // Writes throw so a caller cannot be told a value was stored when it was
    // not. Only `SpectraSecretStoreAdapter` reaches these, and core does not
    // drive the adapter's generic bucket today — core's `wallet_secrets`
    // sealing path, which is what puts a salt and verifier in it, is the CLI's
    // alone. Throwing is what keeps that true if core ever does.
    static func save(_ value: String, for account: String) throws { try storage.save(value, for: account) }
    static func saveData(_ data: Data, for account: String) throws { try storage.saveData(data, for: account) }
    static func loadValue(for account: String) -> String { (try? storage.loadValue(for: account)) ?? "" }
    static func loadData(for account: String) -> Data? { try? storage.loadData(for: account) }
    static func deleteValue(for account: String) { try? storage.deleteValue(for: account) }
    static func deleteAllValues() { try? storage.deleteAllValues() }
}
private enum SeedMaterialEnvelope {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.masterkey")
    private static let masterKeyAccount = "seed.material.masterkey"
    /// The stored master key, or nil when the Keychain holds none yet.
    ///
    /// A read *failure* throws rather than reporting "absent". Callers create a
    /// key when one is absent, so answering "absent" for a key that is merely
    /// unreadable right now would overwrite the key every existing seed is
    /// sealed under. A stored key of the wrong shape is present, not absent:
    /// it is returned, and core's envelope refuses to seal or open with it, so
    /// it is never replaced here either.
    private static func storedMasterKey() throws -> Data? {
        do { return try storage.loadData(for: masterKeyAccount) } catch {
            throw KeychainStoreError.masterKeyUnavailable(String(describing: error))
        }
    }
    /// The master key to seal with, creating and persisting one on first use.
    ///
    /// Core mints it: the length is the envelope's and the bytes come from the
    /// OS generator, and a generator failure is an error rather than a
    /// fallback. Throws rather than handing back a key that was not written: a
    /// seed sealed under an unpersisted key is unreadable on the next launch,
    /// so the seed must not be stored at all in that case.
    private static func masterKeyForSealing() throws -> Data {
        if let existing = try storedMasterKey() { return existing }
        let generated: Data
        do { generated = try newSeedEnvelopeMasterKey() } catch {
            throw KeychainStoreError.masterKeyUnavailable(String(describing: error))
        }
        do { try storage.saveData(generated, for: masterKeyAccount) } catch {
            throw KeychainStoreError.masterKeyUnavailable(String(describing: error))
        }
        return generated
    }
    /// Seals `seedPhrase` for storage. Failing to encrypt is a failure to
    /// store — there is no plaintext fallback.
    static func encode(_ seedPhrase: String) throws -> Data {
        let key = try masterKeyForSealing()
        do { return try encryptSeedEnvelope(plaintext: seedPhrase, masterKeyBytes: key) } catch {
            throw KeychainStoreError.sealFailed(String(describing: error))
        }
    }
    /// Opens a stored envelope. Unlike `encode`, this never creates a master
    /// key: no key means nothing was ever sealed, and a read must not write.
    static func decode(_ data: Data) -> String? {
        guard let key = (try? storedMasterKey()) ?? nil else { return nil }
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
enum SecurePrivateKeyStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.privatekey")
    static func save(_ value: String, for account: String) throws { try storage.save(value, for: account) }
    static func loadValue(for account: String) -> String { (try? storage.loadValue(for: account)) ?? "" }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
    static func deleteAllValues() throws { try storage.deleteAllValues() }
}

final class SpectraSecretStoreAdapter: SecretStore, @unchecked Sendable {
    /// Hands core the keychain-backed secret store.
    ///
    /// Awaited rather than fired into a detached task, and throwing rather
    /// than `try?`: everything core does with a seed or a private key reads
    /// through this adapter, so anything running before the registration
    /// lands finds no store at all. The detached task let launch continue
    /// into state reload while registration was still in flight, and the
    /// swallowed error left a permanent failure looking like an unopenable
    /// wallet with nothing in the logs to say why.
    static func registerWithBridge() async throws {
        try await WalletServiceBridge.shared.registerSecretStore(SpectraSecretStoreAdapter())
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
        do {
            switch kind {
            case .seed: try SecureSeedStore.save(value, for: key)
            case .privateKey: try SecurePrivateKeyStore.save(value, for: key)
            case .generic: try SecureStore.save(value, for: key)
            }
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
        }
    }
    func deleteSecret(kind: SecretClass, key: String) throws {
        do {
            switch kind {
            case .seed: try SecureSeedStore.deleteValue(for: key)
            case .privateKey: try SecurePrivateKeyStore.deleteValue(for: key)
            case .generic: SecureStore.deleteValue(for: key)
            }
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
        }
    }
    func listKeys(kind: SecretClass, prefixFilter: String) throws -> [String] {
        return []
    }
}
