import Foundation
import XCTest
@testable import Spectra

@MainActor
final class LitecoinBalanceServiceTests: SpectraNetworkTestCase {
    @MainActor
    func testFetchesBalanceFromMockedLitecoinspaceResponse() async throws {
        let address = "ltc1qmockaddress"
        let url = "https://litecoinspace.org/api/address/\(address)"

        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "chain_stats": [
                    "funded_txo_sum": 200_000_000,
                    "spent_txo_sum": 50_000_000,
                    "tx_count": 2,
                ],
                "mempool_stats": [
                    "funded_txo_sum": 0,
                    "spent_txo_sum": 0,
                    "tx_count": 0,
                ],
            ]
        )

        let balance = try await LitecoinBalanceService.fetchBalance(for: address)
        XCTAssertEqual(balance, 1.5, accuracy: 0.0000001)
    }

    @MainActor
    func testFallsBackToBlockcypherWhenLitecoinspaceFails() async throws {
        let address = "ltc1qfallback"
        let primaryURL = "https://litecoinspace.org/api/address/\(address)"
        let fallbackURL = "https://api.blockcypher.com/v1/ltc/main/addrs/\(address)/balance"

        await testNetworkClient.enqueueFailure(url: primaryURL, code: .timedOut)
        try await testNetworkClient.enqueueJSONResponse(
            url: fallbackURL,
            object: [
                "final_balance": 75_000_000,
                "n_tx": 1,
            ]
        )

        let balance = try await LitecoinBalanceService.fetchBalance(for: address)
        XCTAssertEqual(balance, 0.75, accuracy: 0.0000001)
    }
}
