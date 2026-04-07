import XCTest
@testable import Spectra

final class SecureSeedStoreTests: XCTestCase {
    func testLoadMissingSeedThrows() {
        let account = "test.seed.missing.1"
        try? SecureSeedStore.deleteValue(for: account)
        XCTAssertThrowsError(try SecureSeedStore.loadValue(for: account))
    }

    func testSaveThenLoadRoundTripsSeed() {
        let account = "test.seed.roundtrip.1"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"

        try? SecureSeedStore.save(seed, for: account)
        defer { try? SecureSeedStore.deleteValue(for: account) }

        XCTAssertEqual((try? SecureSeedStore.loadValue(for: account)), seed)
    }

    func testSeedStorageDoesNotPersistPlaintextUTF8Payload() {
        let account = "test.seed.encrypted.1"
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"

        try? SecureSeedStore.save(seed, for: account)
        defer { try? SecureSeedStore.deleteValue(for: account) }

        let storedData = try? SecureSeedStore.loadData(for: account)
        XCTAssertNotNil(storedData)
        XCTAssertNotEqual(storedData, Data(seed.utf8))
        XCTAssertFalse(String(data: storedData ?? Data(), encoding: .utf8) == seed)
    }

    func testSavingPasswordVerifierAllowsVerification() {
        let account = "test.seed.password.1"
        let password = "correct horse battery staple"

        try? SecureSeedPasswordStore.deleteValue(for: account)
        try? SecureSeedPasswordStore.save(password, for: account)
        defer { try? SecureSeedPasswordStore.deleteValue(for: account) }

        XCTAssertTrue(SecureSeedPasswordStore.hasPassword(for: account))
        XCTAssertTrue(SecureSeedPasswordStore.verify(password, for: account))
        XCTAssertFalse(SecureSeedPasswordStore.verify("wrong password", for: account))
    }

    func testEmptyPasswordDeletesPasswordVerifier() {
        let account = "test.seed.password.2"

        try? SecureSeedPasswordStore.save("temporary", for: account)
        try? SecureSeedPasswordStore.save("", for: account)

        XCTAssertFalse(SecureSeedPasswordStore.hasPassword(for: account))
    }
}
