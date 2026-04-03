import Foundation
import CryptoKit
import KeychainAccess
import CommonCrypto

private struct KeychainBackedSecureStore {
    private let keychain: Keychain

    enum StoreError: Error {
        case missingValue
        case invalidEncoding
    }

    init(service: String) {
        keychain = Keychain(service: service)
            .accessibility(.whenPasscodeSetThisDeviceOnly)
    }

    func save(_ value: String, for account: String) throws {
        try saveData(Data(value.utf8), for: account)
    }

    func saveData(_ data: Data, for account: String) throws {
        try keychain.set(data, key: account)
    }

    func loadValue(for account: String) throws -> String {
        guard let data = try loadData(for: account) else {
            throw StoreError.missingValue
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidEncoding
        }
        return value
    }

    func loadData(for account: String) throws -> Data? {
        try keychain.getData(account)
    }

    func deleteValue(for account: String) throws {
        try keychain.remove(account)
    }

    func deleteAllValues() throws {
        try keychain.removeAll()
    }
}

private enum SecureRandom {
    static func data(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return Data((0..<length).map { _ in UInt8.random(in: .min ... .max) })
        }
        return Data(bytes)
    }
}

// Stores non-seed sensitive secrets (API keys, encoded snapshots) in the Keychain.
// This storage is reset by the in-app hard reset flow and is scoped to this app service.
enum SecureStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.pricing")

    static func save(_ value: String, for account: String) {
        try? storage.save(value, for: account)
    }

    static func saveData(_ data: Data, for account: String) {
        try? storage.saveData(data, for: account)
    }

    static func loadValue(for account: String) -> String {
        (try? storage.loadValue(for: account)) ?? ""
    }

    static func loadData(for account: String) -> Data? {
        try? storage.loadData(for: account)
    }

    static func deleteValue(for account: String) {
        try? storage.deleteValue(for: account)
    }

    static func deleteAllValues() {
        try? storage.deleteAllValues()
    }
}

private enum SeedMaterialEnvelope {
    private struct Envelope: Codable {
        let version: Int
        let ciphertext: Data
        let nonce: Data
    }

    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.masterkey")
    private static let currentVersion = 1
    private static let masterKeyAccount = "seed.material.masterkey"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func masterKey() -> SymmetricKey {
        if let storedData = (try? storage.loadData(for: masterKeyAccount)) ?? nil,
           storedData.count == 32 {
            return SymmetricKey(data: storedData)
        }
        let generated = SecureRandom.data(length: 32)
        try? storage.saveData(generated, for: masterKeyAccount)
        return SymmetricKey(data: generated)
    }

    static func encode(_ seedPhrase: String) -> Data {
        let key = masterKey()
        guard let sealedBox = try? AES.GCM.seal(Data(seedPhrase.utf8), using: key) else {
            return Data(seedPhrase.utf8)
        }
        let envelope = Envelope(
            version: currentVersion,
            ciphertext: sealedBox.ciphertext + sealedBox.tag,
            nonce: Data(sealedBox.nonce)
        )
        return (try? encoder.encode(envelope)) ?? Data(seedPhrase.utf8)
    }

    static func decode(_ data: Data) -> String? {
        if let envelope = try? decoder.decode(Envelope.self, from: data),
           envelope.version == currentVersion {
            guard envelope.nonce.count == 12, envelope.ciphertext.count >= 16 else {
                return nil
            }
            let ciphertext = envelope.ciphertext.dropLast(16)
            let tag = envelope.ciphertext.suffix(16)
            guard let nonce = try? AES.GCM.Nonce(data: envelope.nonce),
                  let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
                  let plaintext = try? AES.GCM.open(sealedBox, using: masterKey()) else {
                return nil
            }
            return String(data: plaintext, encoding: .utf8)
        }
        return nil
    }
}

// Stores seed phrases in a dedicated Keychain service, separated from generic secure values.
// Keeping seed material isolated makes reset/audit paths explicit and easier to validate.
enum SecureSeedStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed")

    static func save(_ value: String, for account: String) throws {
        try storage.saveData(SeedMaterialEnvelope.encode(value), for: account)
    }

    static func loadValue(for account: String) throws -> String {
        guard let data = try storage.loadData(for: account),
              let value = SeedMaterialEnvelope.decode(data) else {
            throw KeychainBackedSecureStore.StoreError.missingValue
        }
        return value
    }

    static func loadData(for account: String) throws -> Data? {
        try storage.loadData(for: account)
    }

    static func deleteValue(for account: String) throws {
        try storage.deleteValue(for: account)
    }

    static func deleteAllValues() throws {
        try storage.deleteAllValues()
    }
}

enum SecureSeedPasswordStore {
    private struct PasswordVerifierEnvelope: Codable {
        let version: Int
        let salt: Data
        let rounds: Int
        let digest: Data
    }

    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.password")
    private static let currentVersion = 1
    private static let defaultRounds = 210_000
    private static let derivedKeyLength = 32
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func normalizedPassword(_ password: String) -> String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func randomSalt(length: Int = 16) -> Data {
        SecureRandom.data(length: length)
    }

    private static func deriveDigest(password: String, salt: Data, rounds: Int) -> Data {
        let passwordData = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: derivedKeyLength)
        let status = salt.withUnsafeBytes { saltBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else {
            return Data()
        }
        return Data(derived)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func save(_ password: String, for account: String) throws {
        let normalized = normalizedPassword(password)
        guard !normalized.isEmpty else {
            try deleteValue(for: account)
            return
        }

        let salt = randomSalt()
        let digest = deriveDigest(password: normalized, salt: salt, rounds: defaultRounds)
        let envelope = PasswordVerifierEnvelope(
            version: currentVersion,
            salt: salt,
            rounds: defaultRounds,
            digest: digest
        )
        try storage.saveData(try encoder.encode(envelope), for: account)
    }

    static func hasPassword(for account: String) -> Bool {
        (try? storage.loadData(for: account)) != nil
    }

    static func verify(_ password: String, for account: String) -> Bool {
        let normalized = normalizedPassword(password)
        guard !normalized.isEmpty,
              let data = try? storage.loadData(for: account),
              let envelope = try? decoder.decode(PasswordVerifierEnvelope.self, from: data),
              envelope.version == currentVersion else {
            return false
        }

        let candidate = deriveDigest(password: normalized, salt: envelope.salt, rounds: envelope.rounds)
        return constantTimeEquals(candidate, envelope.digest)
    }

    static func deleteValue(for account: String) throws {
        try storage.deleteValue(for: account)
    }

    static func deleteAllValues() throws {
        try storage.deleteAllValues()
    }
}

// Stores imported raw private keys in an isolated Keychain service.
// This keeps private-key-only wallets separate from mnemonic-backed wallets.
enum SecurePrivateKeyStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.privatekey")

    static func save(_ value: String, for account: String) {
        try? storage.save(value, for: account)
    }

    static func loadValue(for account: String) -> String {
        (try? storage.loadValue(for: account)) ?? ""
    }

    static func deleteValue(for account: String) {
        try? storage.deleteValue(for: account)
    }

    static func deleteAllValues() {
        try? storage.deleteAllValues()
    }
}
