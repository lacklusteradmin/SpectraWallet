import Security
import XCTest
@testable import Spectra
final class SecureSeedStoreTests: XCTestCase {
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
    func testLoadMissingSeedThrows() {
        let account = "test.seed.missing.\(UUID().uuidString)"
        try? SealedSigningStore.seeds.deleteValue(for: account)
        XCTAssertThrowsError(try SealedSigningStore.seeds.loadValue(for: account))
    }
    // Writes use `try`, not `try?`: a store that fails to write must fail the
    // test rather than let the assertions below pass on stale or absent data.
    func testSaveThenLoadRoundTripsSeed() throws {
        let account = "test.seed.roundtrip.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SealedSigningStore.seeds.save(seed, for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        XCTAssertEqual(try SealedSigningStore.seeds.loadValue(for: account), seed)
    }
    func testSeedStorageDoesNotPersistPlaintextUTF8Payload() throws {
        let account = "test.seed.encrypted.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SealedSigningStore.seeds.save(seed, for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        let storedData = try XCTUnwrap(storedBytes(service: "com.spectra.seed", account: account))
        XCTAssertNotEqual(storedData, Data(seed.utf8))
        XCTAssertFalse(String(data: storedData, encoding: .utf8) == seed)
        // A plaintext fallback would put every seed word in the stored bytes.
        // Assert on the words themselves, not just on inequality with the exact
        // UTF-8 payload, so a partial downgrade cannot pass either.
        for word in seed.split(separator: " ") {
            XCTAssertFalse(storedData.range(of: Data(word.utf8)) != nil, "seed word \(word) appears in stored bytes")
        }
    }
    func testPrivateKeySaveThenLoadRoundTrips() throws {
        let account = "test.privatekey.roundtrip.\(UUID().uuidString)"
        let key = String(repeating: "ab", count: 32)
        try SealedSigningStore.privateKeys.save(key, for: account)
        defer { try? SealedSigningStore.privateKeys.deleteValue(for: account) }
        XCTAssertEqual(try SealedSigningStore.privateKeys.loadValue(for: account), key)
    }
    /// A private key signs exactly as a seed does, so it is sealed the same way
    /// rather than written as the string that was pasted.
    func testPrivateKeyStorageDoesNotPersistPlaintext() throws {
        let account = "test.privatekey.encrypted.\(UUID().uuidString)"
        let key = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        try SealedSigningStore.privateKeys.save(key, for: account)
        defer { try? SealedSigningStore.privateKeys.deleteValue(for: account) }
        let storedData = try XCTUnwrap(storedBytes(service: "com.spectra.privatekey", account: account))
        XCTAssertNil(storedData.range(of: Data(key.utf8)), "the key is stored in the clear")
        XCTAssertNil(storedData.range(of: Data(key.prefix(16).utf8)), "part of the key is stored in the clear")
    }
    /// A missing key is `missingValue`, which the adapter reports to core as
    /// not found. Anything else a read throws is a failure, not an absence.
    func testMissingPrivateKeyReportsMissing() {
        let account = "test.privatekey.missing.\(UUID().uuidString)"
        try? SealedSigningStore.privateKeys.deleteValue(for: account)
        XCTAssertThrowsError(try SealedSigningStore.privateKeys.loadValue(for: account)) { error in
            XCTAssertEqual(error as? KeychainStoreError, .missingValue)
        }
        XCTAssertThrowsError(try SpectraSecretStoreAdapter().loadSecret(kind: .privateKey, key: account)) { error in
            guard case SecretStoreError.NotFound = error else {
                return XCTFail("a missing key reached core as \(error)")
            }
        }
    }
    func testDeletedSeedIsNotReadableAndReportsMissing() throws {
        let account = "test.seed.deleted.\(UUID().uuidString)"
        try SealedSigningStore.seeds.save("abandon abandon abandon abandon abandon about", for: account)
        try SealedSigningStore.seeds.deleteValue(for: account)
        XCTAssertNil(try storedBytes(service: "com.spectra.seed", account: account))
        XCTAssertThrowsError(try SealedSigningStore.seeds.loadValue(for: account)) { error in
            XCTAssertEqual(error as? KeychainStoreError, .missingValue)
        }
    }

    /// The master key reaches the Keychain only encrypted to the wrapping key
    /// — an ECIES blob (ephemeral point, ciphertext, tag), never the raw key.
    func testTheMasterKeyIsStoredOnlyWrapped() throws {
        let account = "test.seed.wrapped.\(UUID().uuidString)"
        try SealedSigningStore.seeds.save("abandon ability able about above absent absorb abstract absurd abuse access accident", for: account)
        defer { try? SealedSigningStore.seeds.deleteValue(for: account) }
        let wrapped = try XCTUnwrap(storedBytes(service: "com.spectra.seed.masterkey", account: "seed.material.masterkey.wrapped"))
        XCTAssertEqual(wrapped.first, 0x04, "an uncompressed ephemeral P-256 point leads the blob")
        XCTAssertGreaterThan(wrapped.count, 65 + 16, "a raw master key is shorter than a wrapped one")
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data("com.spectra.seed.masterkey.wrapping".utf8),
        ]
        XCTAssertEqual(SecItemCopyMatching(keyQuery as CFDictionary, nil), errSecSuccess, "the wrapping key is a Keychain key, not data")
    }
}
