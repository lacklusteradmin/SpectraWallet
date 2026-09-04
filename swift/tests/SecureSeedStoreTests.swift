import XCTest
@testable import Spectra
final class SecureSeedStoreTests: XCTestCase {
    func testLoadMissingSeedThrows() {
        let account = "test.seed.missing.1"
        try? SecureSeedStore.deleteValue(for: account)
        XCTAssertThrowsError(try SecureSeedStore.loadValue(for: account))
    }
    // Writes use `try`, not `try?`: a store that fails to write must fail the
    // test rather than let the assertions below pass on stale or absent data.
    func testSaveThenLoadRoundTripsSeed() throws {
        let account = "test.seed.roundtrip.1"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        try SecureSeedStore.save(seed, for: account)
        defer { try? SecureSeedStore.deleteValue(for: account) }
        XCTAssertEqual(try SecureSeedStore.loadValue(for: account), seed)
    }
    func testSeedStorageDoesNotPersistPlaintextUTF8Payload() throws {
        let account = "test.seed.encrypted.1"
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
        let account = "test.privatekey.roundtrip.1"
        let key = String(repeating: "ab", count: 32)
        try SecurePrivateKeyStore.save(key, for: account)
        defer { try? SecurePrivateKeyStore.deleteValue(for: account) }
        XCTAssertEqual(SecurePrivateKeyStore.loadValue(for: account), key)
    }
    func testDeletedSeedIsNotReadableAndReportsMissing() throws {
        let account = "test.seed.deleted.1"
        try SecureSeedStore.save("abandon abandon abandon abandon abandon about", for: account)
        try SecureSeedStore.deleteValue(for: account)
        XCTAssertNil(try SecureSeedStore.loadData(for: account))
        XCTAssertThrowsError(try SecureSeedStore.loadValue(for: account)) { error in
            XCTAssertEqual(error as? KeychainStoreError, .missingValue)
        }
    }
}
