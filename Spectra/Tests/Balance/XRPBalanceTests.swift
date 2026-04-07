import XCTest
@testable import Spectra

@MainActor
final class XRPBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"

    func testFetchBalanceUsesXRPSCANWhenAvailable() async throws {
        let url = "https://api.xrpscan.com/api/v1/account/\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(url: url, object: ["xrpBalance": "42.5"])

        let balance = try await XRPBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 42.5, accuracy: 0.0000001)
    }

    func testFetchBalanceFallsBackToRippleRPCWhenXRPSCANFails() async throws {
        let xrpscanURL = "https://api.xrpscan.com/api/v1/account/\(validAddress)"
        let rippleS1URL = "https://s1.ripple.com:51234/"
        await testNetworkClient.enqueueFailure(url: xrpscanURL, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: rippleS1URL,
            object: [
                "result": [
                    "account_data": ["Balance": "2500000"]
                ]
            ]
        )

        let balance = try await XRPBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 2.5, accuracy: 0.0000001)
    }
}
