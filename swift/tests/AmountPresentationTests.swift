import XCTest
@testable import Spectra

@MainActor
final class AmountPresentationTests: XCTestCase {
    func testUnavailableMetadataDoesNotInventAmountOrValue() {
        let display = AmountPresentation(assetPrecision: nil, valuation: nil, selectedFiatCurrency: .eur)
        XCTAssertEqual(display.formattedAssetAmountValue("1", deploymentId: "ethereum:native"), "—")
        XCTAssertNil(display.formattedFiatIfAvailable(nil))
        XCTAssertNil(display.formattedFiatIfAvailable(.infinity))
        XCTAssertEqual(display.formattedFiat(nil), "—")
    }

    func testCompactAmountsCutAndDetailedAmountsKeepEveryDigit() {
        let display = AmountPresentation(
            assetPrecision: AssetPrecisionCatalog(byDeploymentId: ["bitcoin:native": 8, "ethereum:native": 18], unknownDecimals: 18),
            valuation: nil, selectedFiatCurrency: .usd)
        let transaction = TransactionRecord(id: "detail", deploymentId: "bitcoin:native", kind: .receive,
            status: .confirmed, walletName: "Main", assetDisplayName: "Bitcoin", symbol: "BTC",
            chainId: "bitcoin", amount: "1234.12345678", address: "address")
        XCTAssertNotEqual(display.formattedTransactionAmount(transaction), display.formattedTransactionDetailAmount(transaction))
        XCTAssertTrue(display.formattedTransactionDetailAmount(transaction).contains("12345678"))
        XCTAssertTrue(display.formattedAssetAmountValue("0.000000000000000001", deploymentId: "ethereum:native").hasPrefix("<"))
    }

    /// Past what a compact row shows, an amount is cut: a balance never reads
    /// as more than is held.
    func testCompactAmountsNeverRoundUp() {
        let text = formatAssetAmount(amount: "0.999999999", assetDecimals: 8)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.value.hasPrefix("1") ?? true, "rounded up to \(text?.value ?? "")")
    }
}
