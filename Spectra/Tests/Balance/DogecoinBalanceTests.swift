import XCTest
@testable import Spectra

@MainActor
final class DogecoinBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L"

    func testFetchBalanceUsesBlockcypherPayload() async throws {
        let url = "https://api.blockcypher.com/v1/doge/main/addrs/\(validAddress)/balance"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: ["final_balance": 1_250_000_000]
        )

        let balance = try await DogecoinBalanceService.fetchBalance(for: validAddress)
        XCTAssertEqual(balance, 12.5, accuracy: 0.0000001)
    }
}
