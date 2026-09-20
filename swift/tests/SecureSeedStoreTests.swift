import XCTest
@testable import Spectra
final class SecureSeedStoreTests: XCTestCase {
    func testLoadMissingSeedThrows() {
        let account = "test.seed.missing.\(UUID().uuidString)"
        try? SecureSeedStore.deleteValue(for: account)
        XCTAssertThrowsError(try SecureSeedStore.loadValue(for: account))
    }
    // Writes use `try`, not `try?`: a store that fails to write must fail the
    // test rather than let the assertions below pass on stale or absent data.
    func testSaveThenLoadRoundTripsSeed() throws {
        let account = "test.seed.roundtrip.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SecureSeedStore.save(seed, for: account)
        defer { try? SecureSeedStore.deleteValue(for: account) }
        XCTAssertEqual(try SecureSeedStore.loadValue(for: account), seed)
    }
    func testSeedStorageDoesNotPersistPlaintextUTF8Payload() throws {
        let account = "test.seed.encrypted.\(UUID().uuidString)"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SecureSeedStore.save(seed, for: account)
        defer { try? SecureSeedStore.deleteValue(for: account) }
        let storedData = try XCTUnwrap(SecureSeedStore.loadData(for: account))
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
        try SecurePrivateKeyStore.save(key, for: account)
        defer { try? SecurePrivateKeyStore.deleteValue(for: account) }
        XCTAssertEqual(try SecurePrivateKeyStore.loadValue(for: account), key)
    }
    /// A private key signs exactly as a seed does, so it is sealed the same way
    /// rather than written as the string that was pasted.
    func testPrivateKeyStorageDoesNotPersistPlaintext() throws {
        let account = "test.privatekey.encrypted.\(UUID().uuidString)"
        let key = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        try SecurePrivateKeyStore.save(key, for: account)
        defer { try? SecurePrivateKeyStore.deleteValue(for: account) }
        let storedData = try XCTUnwrap(SecurePrivateKeyStore.loadData(for: account))
        XCTAssertNil(storedData.range(of: Data(key.utf8)), "the key is stored in the clear")
        XCTAssertNil(storedData.range(of: Data(key.prefix(16).utf8)), "part of the key is stored in the clear")
    }
    /// A missing key is `missingValue`, which the adapter reports to core as
    /// not found. Anything else a read throws is a failure, not an absence.
    func testMissingPrivateKeyReportsMissing() {
        let account = "test.privatekey.missing.\(UUID().uuidString)"
        try? SecurePrivateKeyStore.deleteValue(for: account)
        XCTAssertThrowsError(try SecurePrivateKeyStore.loadValue(for: account)) { error in
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
        try SecureSeedStore.save("abandon abandon abandon abandon abandon about", for: account)
        try SecureSeedStore.deleteValue(for: account)
        XCTAssertNil(try SecureSeedStore.loadData(for: account))
        XCTAssertThrowsError(try SecureSeedStore.loadValue(for: account)) { error in
            XCTAssertEqual(error as? KeychainStoreError, .missingValue)
        }
    }
}
