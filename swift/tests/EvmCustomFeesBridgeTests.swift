import XCTest
@testable import Spectra

final class EvmCustomFeesBridgeTests: XCTestCase {
    func testParsedFeesCrossTheBinding() throws {
        let fees = try parseEvmCustomFees(maxFeeGweiRaw: " 30.25 ", priorityFeeGweiRaw: "1")
        XCTAssertEqual(fees.maxFeePerGasGwei, 30.25)
        XCTAssertEqual(fees.maxPriorityFeePerGasGwei, 1)
    }

    func testFeeRefusalsCrossAsTypedErrors() {
        for (max, priority, expected) in [
            ("inf", "1", EvmCustomFeeError.InvalidMaxFee),
            ("30", "NaN", EvmCustomFeeError.InvalidPriorityFee),
            ("1", "2", EvmCustomFeeError.MaxBelowPriority)
        ] {
            XCTAssertThrowsError(try parseEvmCustomFees(maxFeeGweiRaw: max, priorityFeeGweiRaw: priority)) { error in
                guard let actual = error as? EvmCustomFeeError else {
                    return XCTFail("Expected a typed fee error, got \(error)")
                }
                switch (actual, expected) {
                case (.InvalidMaxFee, .InvalidMaxFee), (.InvalidPriorityFee, .InvalidPriorityFee),
                     (.MaxBelowPriority, .MaxBelowPriority): break
                default: XCTFail("Wrong fee refusal: \(actual)")
                }
            }
        }
    }
}
