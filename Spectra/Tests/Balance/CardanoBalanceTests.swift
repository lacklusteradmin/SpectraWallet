import XCTest
@testable import Spectra

@MainActor
final class CardanoBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "addr1qy8ac7qqy0vtulyl7wntmsxc6wex80gvcyjy33qffrhm7sh927ysx5sftuw0dlft05dz3c7revpf7jx0xnlcjz3g69mq4afdhv"
    private let stakeAddress = "stake1u9h927ysx5sftuw0dlft05dz3c7revpf7jx0xnlcjz3g6smjnft8"

    func testFetchBalanceUsesStakeAccountBalanceWhenAvailable() async throws {
        let addressInfoURL = "https://api.koios.rest/api/v1/address_info"
        let accountInfoURL = "https://api.koios.rest/api/v1/account_info"
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: addressInfoURL,
            object: [[
                "balance": "1000000",
                "stake_address": stakeAddress
            ]]
        )
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: accountInfoURL,
            object: [[
                "total_balance": "4567000"
            ]]
        )

        let balance = try await CardanoBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 4.567, accuracy: 0.0000001)
    }

    func testFetchBalanceRejectsInvalidAddress() async {
        do {
            _ = try await CardanoBalanceService.fetchBalance(for: "not-cardano")
            XCTFail("Expected invalidAddress error")
        } catch let error as CardanoBalanceServiceError {
            XCTAssertEqual(error.errorDescription, CardanoBalanceServiceError.invalidAddress.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testFetchHistoryAcceptsAlternateHashAndTimestampFields() async throws {
        let addressInfoURL = "https://api.koios.rest/api/v1/address_info"
        let addressTransactionsURL = "https://api.koios.rest/api/v1/address_txs"
        let txInfoURL = "https://api.koios.rest/api/v1/tx_info"
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: addressInfoURL,
            object: [[
                "balance": "1000000"
            ]]
        )
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: addressTransactionsURL,
            object: [[
                "hash": "def456",
                "tx_timestamp": "2024-05-01T12:34:56Z"
            ]]
        )
        try await testNetworkClient.enqueueJSONResponse(
            method: "POST",
            url: txInfoURL,
            object: [[
                "tx_hash": "def456",
                "tx_timestamp": "2024-05-01T12:34:56Z",
                "inputs": [[
                    "value": "3000000",
                    "payment_addr": ["bech32": "addr1senderexample"]
                ]],
                "outputs": [[
                    "value": "3000000",
                    "payment_addr": ["bech32": validAddress]
                ]]
            ]]
        )

        let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: validAddress, limit: 20)

        XCTAssertNil(result.diagnostics.error)
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots.first?.transactionHash, "def456")
        guard let firstAmount = result.snapshots.first?.amount else {
            XCTFail("Expected amount in first snapshot")
            return
        }
        XCTAssertEqual(firstAmount, 3.0, accuracy: 0.0000001)
        XCTAssertEqual(result.snapshots.first?.counterpartyAddress, "addr1senderexample")
    }
}
