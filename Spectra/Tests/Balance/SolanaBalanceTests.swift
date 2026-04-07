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

    func testFetchBalanceRejectsInvalidAddress() async {
        do {
            _ = try await SolanaBalanceService.fetchBalance(for: "invalid-sol-address")
            XCTFail("Expected invalidAddress error")
        } catch let error as SolanaBalanceServiceError {
            XCTAssertEqual(error.errorDescription, SolanaBalanceServiceError.invalidAddress.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testFetchPortfolioRejectsInvalidAddress() async {
        do {
            _ = try await SolanaBalanceService.fetchPortfolio(for: "invalid-sol-address")
            XCTFail("Expected invalidAddress error")
        } catch let error as SolanaBalanceServiceError {
            XCTAssertEqual(error.errorDescription, SolanaBalanceServiceError.invalidAddress.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testAddressValidatorAcceptsBasicMainnetShape() {
        XCTAssertTrue(SolanaBalanceService.isValidAddress(validAddress))
    }
}
