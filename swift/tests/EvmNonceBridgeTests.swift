import XCTest
@testable import Spectra

final class EvmNonceBridgeTests: XCTestCase {
    func testNonceCrossesBindingWithoutInt32Truncation() throws {
        XCTAssertEqual(try parseEvmNonce(raw: " 0012 "), 12)
        XCTAssertEqual(try parseEvmNonce(raw: "2147483648"), 2_147_483_648)
        XCTAssertEqual(try parseEvmNonce(raw: "9223372036854775807"), Int64.max)
    }

    func testInvalidManualNonceThrowsInsteadOfReturningAutomaticNonce() {
        for (raw, expected) in [(" ", EvmNonceError.Empty), ("-1", .InvalidInteger),
                                ("+1", .InvalidInteger), ("9223372036854775808", .TooLarge)] {
            XCTAssertThrowsError(try parseEvmNonce(raw: raw)) { error in
                switch (error as? EvmNonceError, expected) {
                case (.Empty?, .Empty), (.InvalidInteger?, .InvalidInteger), (.TooLarge?, .TooLarge): break
                default: XCTFail("Unexpected nonce error: \(error)")
                }
            }
        }
    }
}
