import XCTest
@testable import Spectra

@MainActor
final class SolanaBalanceServiceTests: XCTestCase {
    private let validAddress = "11111111111111111111111111111111"

    func testMintAddressContainsStablecoinMappings() {
        XCTAssertEqual(SolanaBalanceService.mintAddress(for: "USDT"), SolanaBalanceService.usdtMintAddress)
        XCTAssertEqual(SolanaBalanceService.mintAddress(for: "USDC"), SolanaBalanceService.usdcMintAddress)
        XCTAssertNil(SolanaBalanceService.mintAddress(for: "UNKNOWN"))
    }

    func testAddressValidatorAcceptsBasicMainnetShape() {
        XCTAssertTrue(SolanaBalanceService.isValidAddress(validAddress))
    }
}
