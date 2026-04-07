import XCTest
@testable import Spectra

@MainActor
final class SuiBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "0x" + String(repeating: "1", count: 64)

    func testFetchBalanceUsesJSONRPCBalanceResult() async throws {
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: "https://fullnode.mainnet.sui.io:443",
            object: [
                "jsonrpc": "2.0",
                "id": 1,
                "result": ["totalBalance": "1500000000"]
            ]
        )

        let balance = try await SuiBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 1.5, accuracy: 0.0000001)
    }

    func testFetchBalanceRejectsInvalidAddress() async {
        do {
            _ = try await SuiBalanceService.fetchBalance(for: "not-sui")
            XCTFail("Expected invalidAddress error")
        } catch let error as SuiBalanceServiceError {
            XCTAssertEqual(error.errorDescription, SuiBalanceServiceError.invalidAddress.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }
}
