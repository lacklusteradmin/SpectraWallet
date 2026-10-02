import Foundation
import Security
import Testing
@testable import Spectra

/// These read and write the real Keychain, and share its device wrapping key.
@Suite(.serialized)
struct SecureSeedStoreTests {
    /// The Keychain item as stored, read beside the store rather than through it.
    private func storedBytes(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return result as? Data
    }
    private let adapter = SpectraSecretStoreAdapter()

    /// A missing value reaches core as not found, in every class; anything
    /// else a read throws is a failure, not an absence.
    @Test func missingValuesReportNotFound() {
        let account = "test.missing.\(UUID().uuidString)"
        for kind in [SecretClass.seed, .privateKey, .generic, .deviceKey] {
            #expect(throws: SecretStoreError.NotFound) { try adapter.loadSecret(kind: kind, key: account) }
        }
    }
    // Writes use `try`, not `try?`: a store that fails to write must fail the
    // test rather than let the assertions below pass on stale or absent data.
    @Test func eachClassRoundTripsInItsOwnService() throws {
        let account = "test.roundtrip.\(UUID().uuidString)"
        let services: [(SecretClass, String)] = [
            (.seed, "com.spectra.seed"), (.privateKey, "com.spectra.privatekey"),
            (.generic, "com.spectra.wallet"), (.deviceKey, "com.spectra.seed.masterkey"),
        ]
        for (kind, service) in services {
            try adapter.saveSecret(kind: kind, key: account, value: "sealed by core")
            defer { try? adapter.deleteSecret(kind: kind, key: account) }
            #expect(try adapter.loadSecret(kind: kind, key: account) == "sealed by core")
            #expect(try storedBytes(service: service, account: account) == Data("sealed by core".utf8))
        }
    }
    @Test func deletedValueIsGoneAndReportsNotFound() throws {
        let account = "test.deleted.\(UUID().uuidString)"
        try adapter.saveSecret(kind: .seed, key: account, value: "sealed by core")
        try adapter.deleteSecret(kind: .seed, key: account)
        #expect(try storedBytes(service: "com.spectra.seed", account: account) == nil)
        #expect(throws: SecretStoreError.NotFound) { try adapter.loadSecret(kind: .seed, key: account) }
        try adapter.deleteSecret(kind: .seed, key: account)
    }

    /// The device key is wrapped to the enclave key — an ECIES blob (ephemeral
    /// point, ciphertext, tag), never the raw key — and unwraps to itself.
    @Test func theDeviceKeyIsWrappedToAKeychainKey() throws {
        let key = Data((0..<32).map { UInt8($0) })
        let wrapped = try adapter.wrapDeviceKey(key: key)
        #expect(wrapped.first == 0x04, "an uncompressed ephemeral P-256 point leads the blob")
        #expect(wrapped.count > 65 + 16, "a raw key is shorter than a wrapped one")
        #expect(wrapped.range(of: key) == nil)
        #expect(try adapter.unwrapDeviceKey(wrapped: wrapped) == key)
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: DeviceKeyWrapping.tag,
        ]
        #expect(SecItemCopyMatching(keyQuery as CFDictionary, nil) == errSecSuccess, "the wrapping key is a Keychain key, not data")
    }
    /// A blob that does not unwrap is an error, never an empty key.
    @Test func aCorruptWrappedKeyIsAnError() throws {
        _ = try adapter.wrapDeviceKey(key: Data(count: 32))
        #expect(throws: SecretStoreError.self) { try adapter.unwrapDeviceKey(wrapped: Data([0x04, 1, 2, 3])) }
    }
}
