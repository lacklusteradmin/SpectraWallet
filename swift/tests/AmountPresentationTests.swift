import Foundation
import Testing
@testable import Spectra

@MainActor
struct AmountPresentationTests {
    @Test func unavailableMetadataDoesNotInventAmountOrValue() {
        let display = AmountPresentation(assetPrecision: nil, valuation: nil, selectedFiatCurrency: .eur)
        #expect(display.formattedAssetAmountValue("1", deploymentId: "ethereum:native") == "—")
        #expect(display.formattedFiatIfAvailable(nil) == nil)
        #expect(display.formattedFiatIfAvailable(.infinity) == nil)
        #expect(display.formattedFiat(nil) == "—")
    }

    @Test func compactAmountsCutAndDetailedAmountsKeepEveryDigit() {
        let display = AmountPresentation(
            assetPrecision: AssetPrecisionCatalog(byDeploymentId: ["bitcoin:native": 8, "ethereum:native": 18], unknownDecimals: 18),
            valuation: nil, selectedFiatCurrency: .usd)
        let transaction = TransactionRecord(id: "detail", deploymentId: "bitcoin:native", kind: .receive,
            status: .confirmed, walletName: "Main", assetDisplayName: "Bitcoin", symbol: "BTC",
            chainId: Chain.bitcoin, amount: "1234.12345678", address: "address")
        #expect(display.formattedTransactionAmount(transaction) != display.formattedTransactionDetailAmount(transaction))
        #expect(display.formattedTransactionDetailAmount(transaction).contains("12345678"))
        #expect(display.formattedAssetAmountValue("0.000000000000000001", deploymentId: "ethereum:native").hasPrefix("<"))
    }

    /// Past what a compact row shows, an amount is cut: a balance never reads
    /// as more than is held.
    @Test func compactAmountsNeverRoundUp() {
        let text = formatAssetAmount(amount: "0.999999999", assetDecimals: 8)
        #expect(text != nil)
        #expect(text?.value.hasPrefix("1") == false, "rounded up to \(text?.value ?? "")")
    }
}
