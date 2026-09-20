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
    /// A stored envelope could not be opened. The value is there; reporting it
    /// as missing would make a wallet with signing material read as watch-only.
    case openFailed(String)
}

extension KeychainStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingValue: return "No value is stored for this item."
        case .invalidEncoding: return "The stored value is not valid UTF-8."
        case .masterKeyUnavailable(let detail): return "The seed encryption key is unavailable: \(detail)"
        case .sealFailed(let detail): return "The seed could not be encrypted: \(detail)"
        case .openFailed(let detail): return "The stored secret could not be decrypted: \(detail)"
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
    /// `missingValue` only when the Keychain holds nothing under `account`. A
    /// failed read — the device locked, an entitlement missing — throws what
    /// the Keychain threw.
    func loadValue(for account: String) throws -> String {
        guard let data = try loadData(for: account) else { throw StoreError.missingValue }
        guard let value = String(data: data, encoding: .utf8) else { throw StoreError.invalidEncoding }
        return value
    }
    func loadData(for account: String) throws -> Data? { try keychain.getData(account) }
    func deleteValue(for account: String) throws { try keychain.remove(account) }
    func deleteAllValues() throws { try keychain.removeAll() }
}
/// The bucket core keeps a sealed wallet's salt and password verifier in.
///
/// Neither is secret alone, so they sit beside rather than inside the sealed
/// material. Reads and writes throw: `is_sealed` is answered by the verifier's
/// presence, so a read failure reported as "nothing stored" would tell core a
/// sealed wallet is not sealed. The service name predates this use.
enum SecureStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.pricing")
    static func save(_ value: String, for account: String) throws { try storage.save(value, for: account) }
    static func loadValue(for account: String) throws -> String { try storage.loadValue(for: account) }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
}
/// Seals signing material — a seed phrase or a raw private key — under a
/// device master key before it reaches the Keychain.
///
/// Only seeds went through this. A private key, which signs exactly as a seed
/// does, reached the Keychain as core handed it over — base64 of the key when
/// the wallet has no password, which is the key to anyone who reads the item.
private enum SigningMaterialEnvelope {
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
    /// Seals `material` for storage. Failing to encrypt is a failure to
    /// store — there is no plaintext fallback.
    static func encode(_ material: String) throws -> Data {
        let key = try masterKeyForSealing()
        do { return try encryptSeedEnvelope(plaintext: material, masterKeyBytes: key) } catch {
            throw KeychainStoreError.sealFailed(String(describing: error))
        }
    }
    /// Open a stored envelope without creating a master key.
    /// Unreadable material throws; it must not be interpreted as absent.
    static func decode(_ data: Data) throws -> String {
        guard let key = try storedMasterKey() else {
            throw KeychainStoreError.masterKeyUnavailable("no master key is stored for a sealed value")
        }
        do { return try decryptSeedEnvelope(data: data, masterKeyBytes: key) } catch {
            throw KeychainStoreError.openFailed(String(describing: error))
        }
    }
}
enum SecureSeedStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed")
    static func save(_ value: String, for account: String) throws { try storage.saveData(SigningMaterialEnvelope.encode(value), for: account) }
    static func loadValue(for account: String) throws -> String {
        guard let data = try storage.loadData(for: account) else { throw KeychainStoreError.missingValue }
        return try SigningMaterialEnvelope.decode(data)
    }
    static func loadData(for account: String) throws -> Data? { try storage.loadData(for: account) }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
    static func deleteAllValues() throws { try storage.deleteAllValues() }
}
enum SecurePrivateKeyStore {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.privatekey")
    static func save(_ value: String, for account: String) throws { try storage.saveData(SigningMaterialEnvelope.encode(value), for: account) }
    static func loadValue(for account: String) throws -> String {
        guard let data = try storage.loadData(for: account) else { throw KeychainStoreError.missingValue }
        return try SigningMaterialEnvelope.decode(data)
    }
    static func loadData(for account: String) throws -> Data? { try storage.loadData(for: account) }
    static func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
    static func deleteAllValues() throws { try storage.deleteAllValues() }
}

final class SpectraSecretStoreAdapter: SecretStore, @unchecked Sendable {
    /// Register the Keychain-backed secret store synchronously before launch
    /// work. Propagate errors: every operation on signing material requires
    /// this adapter to be registered successfully.
    @MainActor
    static func registerWithBridge(_ bridge: WalletServiceBridge) throws {
        try bridge.registerSecretStore(SpectraSecretStoreAdapter())
    }

    /// `NotFound` only for a value that is not there. Everything else — a
    /// locked device, an envelope that will not open — is the store failing,
    /// and core refuses rather than reading it as absence.
    func loadSecret(kind: SecretClass, key: String) throws -> String {
        do {
            switch kind {
            case .seed: return try SecureSeedStore.loadValue(for: key)
            case .privateKey: return try SecurePrivateKeyStore.loadValue(for: key)
            case .generic: return try SecureStore.loadValue(for: key)
            }
        } catch KeychainStoreError.missingValue {
            throw SecretStoreError.NotFound
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
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
            case .generic: try SecureStore.deleteValue(for: key)
            }
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
        }
    }
}
