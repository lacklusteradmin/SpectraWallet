import XCTest
@testable import Spectra

@MainActor
final class MoneroBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "4" + String(repeating: "A", count: 94)

    override func resetTestState() async throws {
        UserDefaults.standard.removeObject(forKey: MoneroBalanceService.backendBaseURLDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MoneroBalanceService.backendAPIKeyDefaultsKey)
    }

    func testFetchBalanceUsesPrimaryBackend() async throws {
        let url = "https://monerolws1.edge.app/v1/monero/balance?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(url: url, object: ["balanceXMR": 4.2])

        let balance = try await MoneroBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 4.2, accuracy: 0.0000001)
    }

    func testFetchBalanceFallsBackToSecondaryBackend() async throws {
        let primaryURL = "https://monerolws1.edge.app/v1/monero/balance?address=\(validAddress)"
        let secondaryURL = "https://monerolws2.edge.app/v1/monero/balance?address=\(validAddress)"

        await testNetworkClient.enqueueResponse(url: primaryURL, statusCode: 503, body: Data("{}".utf8))
        try await testNetworkClient.enqueueJSONResponse(url: secondaryURL, object: ["balanceXMR": 1.75])

        let balance = try await MoneroBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 1.75, accuracy: 0.0000001)
    }
}
