import Foundation
import XCTest
@testable import Spectra

@MainActor
final class BitcoinBalanceServiceTests: SpectraNetworkTestCase {
    @MainActor
    func testFetchesBalanceFromMockedBlockstreamResponse() async throws {
        let address = "bc1qmockaddress"
        let url = "https://blockstream.info/api/address/\(address)"

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

        let balance = try await BitcoinBalanceService.fetchBalance(for: address, networkMode: .mainnet)
        XCTAssertEqual(balance, 1.5, accuracy: 0.0000001)
    }

    @MainActor
    func testReportsDeterministicFailuresFromQueuedStub() async {
        let address = "bc1qfailure"
        let url = "https://blockstream.info/api/address/\(address)"
        await testNetworkClient.enqueueFailure(url: url, code: .timedOut)
        await assertThrowsURLErrorCode(.timedOut) {
            _ = try await BitcoinBalanceService.fetchBalance(for: address, networkMode: .mainnet)
        }
    }

    @MainActor
    func testFallsBackToMempoolWhenBlockstreamFails() async throws {
        let address = "bc1qfallback"
        let blockstreamURL = "https://blockstream.info/api/address/\(address)"
        let mempoolURL = "https://mempool.space/api/address/\(address)"

        await testNetworkClient.enqueueFailure(url: blockstreamURL, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: mempoolURL,
            object: [
                "chain_stats": [
                    "funded_txo_sum": 125_000_000,
                    "spent_txo_sum": 25_000_000,
                    "tx_count": 3,
                ],
                "mempool_stats": [
                    "funded_txo_sum": 0,
                    "spent_txo_sum": 0,
                    "tx_count": 0,
                ],
            ]
        )

        let balance = try await BitcoinBalanceService.fetchBalance(for: address, networkMode: .mainnet)
        XCTAssertEqual(balance, 1.0, accuracy: 0.0000001)
    }
}

@MainActor
final class BitcoinCashBalanceServiceTests: SpectraNetworkTestCase {
    func testFetchTransactionStatusFromMockedBlockchairTransaction() async throws {
        let txid = "bchtesttxid"
        let url = "https://api.blockchair.com/bitcoin-cash/dashboards/transaction/\(txid)"

        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "data": [
                    txid: [
                        "transaction": [
                            "block_id": 123_456,
                            "hash": txid,
                            "time": "2024-01-01 00:00:00",
                        ],
                        "inputs": [],
                        "outputs": [],
                    ],
                ],
            ]
        )

        let status = try await BitcoinCashBalanceService.fetchTransactionStatus(txid: txid)
        XCTAssertTrue(status.confirmed)
        XCTAssertEqual(status.blockHeight, 123_456)
    }
}
