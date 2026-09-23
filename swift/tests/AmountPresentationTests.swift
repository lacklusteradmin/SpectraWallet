import XCTest
@testable import Spectra

@MainActor
final class AmountPresentationTests: XCTestCase {
    func testUnavailableMetadataDoesNotInventAmountOrExchangeRate() {
        let display = AmountPresentation(selectedFiatCurrency: .eur, fiatRatesFromUSD: [:], livePrices: [:],
            unpricedChainNames: [], assetPrecision: nil, portfolioValuation: nil)
        XCTAssertEqual(display.formattedAssetAmountValue(1, deploymentId: "ethereum:native"), "—")
        XCTAssertNil(display.formattedFiatAmountIfAvailable(fromUSD: 10))
        XCTAssertNil(display.convertUSDToSelectedFiatIfAvailable(.infinity))
    }

    func testCompactAndDetailedAmountsRemainDifferentWithoutAnAppState() {
        let display = AmountPresentation(selectedFiatCurrency: .usd, fiatRatesFromUSD: [:], livePrices: [:],
            unpricedChainNames: [], assetPrecision: AssetPrecisionCatalog(byDeploymentId: ["bitcoin:native": 8], unknownDecimals: 18),
            portfolioValuation: nil)
        let transaction = TransactionRecord(id: "detail", deploymentId: "bitcoin:native", kind: .receive,
            status: .confirmed, walletName: "Main", assetDisplayName: "Bitcoin", symbol: "BTC",
            chainName: "Bitcoin", amount: 1234.12345678, address: "address")
        XCTAssertNotEqual(display.formattedTransactionAmount(transaction), display.formattedTransactionDetailAmount(transaction))
        XCTAssertTrue(display.formattedTransactionDetailAmount(transaction)?.contains("12345678") == true)
        XCTAssertTrue(display.formattedAmountValue(1e-18, assetDecimals: 18).hasPrefix("<"))
    }

}
