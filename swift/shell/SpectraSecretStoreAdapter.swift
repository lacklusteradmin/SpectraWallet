import Foundation

final class SpectraSecretStoreAdapter: SecretStoreImpl, @unchecked Sendable {
    nonisolated override init(noPointer: SecretStoreImpl.NoPointer) {
        super.init(noPointer: noPointer)
    }
    nonisolated required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }
    static func registerWithBridge() {
        let adapter = SpectraSecretStoreAdapter(noPointer: .init())
        Task {
            try? await WalletServiceBridge.shared.registerSecretStore(adapter)
        }
    }

    nonisolated override func loadSecret(kind: SecretClass, key: String) throws -> String {
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

    nonisolated override func saveSecret(kind: SecretClass, key: String, value: String) throws {
        switch kind {
        case .seed:
            do { try SecureSeedStore.save(value, for: key) }
            catch { throw SecretStoreError.Backend(message: String(describing: error)) }
        case .privateKey:
            SecurePrivateKeyStore.save(value, for: key)
        case .generic:
            SecureStore.save(value, for: key)
        }
    }

    nonisolated override func deleteSecret(kind: SecretClass, key: String) throws {
        switch kind {
        case .seed:
            do { try SecureSeedStore.deleteValue(for: key) }
            catch { throw SecretStoreError.Backend(message: String(describing: error)) }
        case .privateKey:
            SecurePrivateKeyStore.deleteValue(for: key)
        case .generic:
            SecureStore.deleteValue(for: key)
        }
    }

    nonisolated override func listKeys(kind: SecretClass, prefixFilter: String) throws -> [String] {
        // No current caller in Rust needs enumeration; the KeychainAccess wrapper
        // hides the underlying keychain handle, so wiring allKeys() up would mean
        // exposing private state for a feature nobody uses yet. Return empty for
        // now — when a caller arrives, add allAccounts() to SecureStores and plumb
        // it through here.
        return []
    }
}
