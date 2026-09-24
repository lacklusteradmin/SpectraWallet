import Foundation
import KeychainAccess
import Security
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
/// Wraps the envelope's master key with a P-256 key held by the Secure Enclave.
///
/// The master key used to sit in the Keychain beside the material it seals,
/// under the same access class, so whoever could read one item could read the
/// other and the envelope added nothing. Now the Keychain holds only the master
/// key encrypted to an enclave key that cannot leave this device's Secure
/// Enclave: a copied Keychain opens nothing, and using the key needs this
/// device, unlocked with a passcode set. It asks for no user presence, so
/// background work that derives from a seed is unaffected.
///
/// The simulator has no enclave. There the wrapping key is a software key: the
/// logic is exercised, the hardware protection is not.
private enum MasterKeyWrapping {
    private static let tag = Data("com.spectra.seed.masterkey.wrapping".utf8)
    private static let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

    /// Encrypt a new master key to the enclave key, creating that key on first use.
    static func wrap(_ masterKey: Data) throws -> Data {
        let privateKey = try wrappingKey(createIfMissing: true)
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeychainStoreError.masterKeyUnavailable("the wrapping key has no public key")
        }
        var error: Unmanaged<CFError>?
        guard let wrapped = SecKeyCreateEncryptedData(publicKey, algorithm, masterKey as CFData, &error) as Data? else {
            throw KeychainStoreError.masterKeyUnavailable(describe(error))
        }
        return wrapped
    }

    /// Decrypt a stored master key. Never creates a wrapping key: a wrapped key
    /// whose wrapping key is gone is unreadable, not absent.
    static func unwrap(_ wrapped: Data) throws -> Data {
        let privateKey = try wrappingKey(createIfMissing: false)
        var error: Unmanaged<CFError>?
        guard let masterKey = SecKeyCreateDecryptedData(privateKey, algorithm, wrapped as CFData, &error) as Data? else {
            throw KeychainStoreError.masterKeyUnavailable(describe(error))
        }
        return masterKey
    }

    private static func wrappingKey(createIfMissing: Bool) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item { return item as! SecKey }
        guard status == errSecItemNotFound else {
            throw KeychainStoreError.masterKeyUnavailable("the wrapping key could not be read (\(status))")
        }
        guard createIfMissing else {
            throw KeychainStoreError.masterKeyUnavailable("no wrapping key is stored for a wrapped master key")
        }
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
        ]
        #if targetEnvironment(simulator)
            privateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        #else
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
            var accessError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .privateKeyUsage, &accessError)
            else { throw KeychainStoreError.masterKeyUnavailable(describe(accessError)) }
            privateAttributes[kSecAttrAccessControl as String] = access
        #endif
        attributes[kSecPrivateKeyAttrs as String] = privateAttributes
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeychainStoreError.masterKeyUnavailable(describe(error))
        }
        return key
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown Security framework error"
    }
}

/// Seals signing material — a seed phrase or a raw private key — under a
/// device master key before it reaches the Keychain. The master key itself is
/// stored only wrapped by `MasterKeyWrapping`.
private enum SigningMaterialEnvelope {
    private static let storage = KeychainBackedSecureStore(service: "com.spectra.seed.masterkey")
    private static let wrappedMasterKeyAccount = "seed.material.masterkey.wrapped"
    /// The stored master key, unwrapped, or nil when the Keychain holds none yet.
    ///
    /// A read or unwrap *failure* throws rather than reporting "absent". Callers
    /// create a key when one is absent, so answering "absent" for a key that is
    /// merely unreadable right now would replace the key every existing seed is
    /// sealed under. A key of the wrong shape is present, not absent: core's
    /// envelope refuses to seal or open with it, so it is never replaced here.
    private static func storedMasterKey() throws -> Data? {
        let wrapped: Data?
        do { wrapped = try storage.loadData(for: wrappedMasterKeyAccount) } catch {
            throw KeychainStoreError.masterKeyUnavailable(String(describing: error))
        }
        return try wrapped.map(MasterKeyWrapping.unwrap)
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
        let wrapped = try MasterKeyWrapping.wrap(generated)
        do { try storage.saveData(wrapped, for: wrappedMasterKeyAccount) } catch {
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
/// Signing material in the Keychain, sealed by `SigningMaterialEnvelope`. A
/// seed phrase and a raw private key sign alike, so they are stored alike;
/// only the Keychain service tells them apart.
struct SealedSigningStore {
    static let seeds = SealedSigningStore(service: "com.spectra.seed")
    static let privateKeys = SealedSigningStore(service: "com.spectra.privatekey")
    private let storage: KeychainBackedSecureStore
    private init(service: String) { storage = KeychainBackedSecureStore(service: service) }
    func save(_ value: String, for account: String) throws { try storage.saveData(SigningMaterialEnvelope.encode(value), for: account) }
    func loadValue(for account: String) throws -> String {
        guard let data = try storage.loadData(for: account) else { throw KeychainStoreError.missingValue }
        return try SigningMaterialEnvelope.decode(data)
    }
    func deleteValue(for account: String) throws { try storage.deleteValue(for: account) }
}

final class SpectraSecretStoreAdapter: SecretStore, @unchecked Sendable {
    /// `NotFound` only for a value that is not there. Everything else — a
    /// locked device, an envelope that will not open — is the store failing,
    /// and core refuses rather than reading it as absence.
    func loadSecret(kind: SecretClass, key: String) throws -> String {
        do {
            switch kind {
            case .seed: return try SealedSigningStore.seeds.loadValue(for: key)
            case .privateKey: return try SealedSigningStore.privateKeys.loadValue(for: key)
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
            case .seed: try SealedSigningStore.seeds.save(value, for: key)
            case .privateKey: try SealedSigningStore.privateKeys.save(value, for: key)
            case .generic: try SecureStore.save(value, for: key)
            }
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
        }
    }
    func deleteSecret(kind: SecretClass, key: String) throws {
        do {
            switch kind {
            case .seed: try SealedSigningStore.seeds.deleteValue(for: key)
            case .privateKey: try SealedSigningStore.privateKeys.deleteValue(for: key)
            case .generic: try SecureStore.deleteValue(for: key)
            }
        } catch {
            throw SecretStoreError.Backend(message: String(describing: error))
        }
    }
}
