import XCTest
@testable import Spectra

@MainActor
final class DogecoinBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L"

    override func resetTestState() async throws {
        DogecoinBalanceService.resetProviderReliability()
    }

    func testFetchBalanceUsesDogechainPayload() async throws {
        let url = "https://dogechain.info/api/v1/address/balance/\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: ["confirmed_balance": "12.5"]
        )

        let balance = try await DogecoinBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 12.5, accuracy: 0.0000001)
    }

    func testFetchBalanceFallsBackToBlockcypherWhenDogechainFails() async throws {
        let dogechainURL = "https://dogechain.info/api/v1/address/balance/\(validAddress)"
        let blockcypherURL = "https://api.blockcypher.com/v1/doge/main/addrs/\(validAddress)/balance"

        await testNetworkClient.enqueueFailure(url: dogechainURL, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: blockcypherURL,
            object: ["final_balance": 250_000_000]
        )

        let balance = try await DogecoinBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 2.5, accuracy: 0.0000001)
    }
}
