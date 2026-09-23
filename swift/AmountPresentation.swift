import Foundation

/// A render-time value over core projections. No storage, services or side effects.
@MainActor
struct AmountPresentation {
    let selectedFiatCurrency: FiatCurrency
    let fiatRatesFromUSD: [String: Double]
    let livePrices: [String: Double]
    let unpricedChainNames: Set<String>
    let assetPrecision: AssetPrecisionCatalog?
    let portfolioValuation: PortfolioValuation?

    func convertUSDToSelectedFiatIfAvailable(_ amountUSD: Double) -> Double? {
        guard amountUSD.isFinite, let rate = fiatRateIfAvailable(for: selectedFiatCurrency) else { return nil }
        let value = amountUSD * rate
        return value.isFinite ? value : nil
    }
    func formattedFiatAmount(fromUSD amountUSD: Double) -> String {
        formattedFiatAmountIfAvailable(fromUSD: amountUSD) ?? "—"
    }
    func formattedFiatAmountIfAvailable(fromUSD amountUSD: Double) -> String? {
        guard amountUSD.isFinite else { return nil }
        if selectedFiatCurrency == .usd { return formatFiatAmount(amount: amountUSD, currency: .usd) }
        guard let converted = convertUSDToSelectedFiatIfAvailable(amountUSD) else { return nil }
        return formatFiatAmount(amount: converted, currency: selectedFiatCurrency)
    }
    func formattedFiatAmountOrUnavailable(fromUSD amountUSD: Double?) -> String {
        guard let amountUSD else { return "—" }
        return formattedFiatAmountIfAvailable(fromUSD: amountUSD) ?? "—"
    }
    private func formatFiatAmount(amount: Double, currency: FiatCurrency) -> String {
        let formatter = AmountFormatters.shared.fiatFormatter(for: currency)
        // Memoized: this runs on every fiat render, thousands of times on the
        // dashboard.
        let minimumVisibleAmount = currency.displayRules.minimumVisible
        if amount > 0, amount < minimumVisibleAmount, let thresholdString = formatter.string(from: NSNumber(value: minimumVisibleAmount)) {
            return "<\(thresholdString)"
        }
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    /// Price `amount` using this holding's asset quote and the display currency.
    func formattedFiatAmount(_ amount: Double, of coin: Coin) -> String? {
        guard let price = currentPriceIfAvailable(for: coin) else { return nil }
        return formattedFiatAmountIfAvailable(fromUSD: amount * price)
    }
    /// Compact rows opt into the shared display style. Details use full asset
    /// precision and signing renders the exact artifact amount.
    /// The amount alone, at the asset's own precision.
    ///
    /// Callers that render the symbol in a separate label — the send Live
    /// Activity does — need the value without it, and the rounding rules are
    /// the same either way.
    func formattedAssetAmountValue(_ amount: Double, deploymentId: String?) -> String {
        guard let decimals = supportedDecimalPlaces(deploymentId: deploymentId) else { return "—" }
        return formattedAmountValue(amount, assetDecimals: UInt32(decimals))
    }
    /// An amount at the places core picks for it on an asset with
    /// `assetDecimals` of its own, trailing zeros trimmed.
    func formattedAmountValue(_ amount: Double, assetDecimals: UInt32) -> String {
        let display = formattingAssetAmountDisplay(amount: amount, assetDecimals: assetDecimals)
        let places = Int(display.places)
        if display.belowThreshold {
            let thresholdFormatter = AmountFormatters.shared.decimalFormatter(
                minimumFractionDigits: places, maximumFractionDigits: places, usesGroupingSeparator: false
            )
            return "<" + (thresholdFormatter.string(from: NSNumber(value: display.threshold)) ?? "")
        }
        let formatter = AmountFormatters.shared.decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: places, usesGroupingSeparator: false
        )
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    func formattedAssetAmount(_ amount: Double, symbol: String, deploymentId: String?) -> String {
        "\(formattedAssetAmountValue(amount, deploymentId: deploymentId)) \(symbol)"
    }

    func formattedTransactionAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedAssetAmount(transaction.amount, symbol: transaction.symbol, deploymentId: transaction.deploymentId)
    }
    func formattedTransactionDetailAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedTransactionDetailAssetAmount(
            transaction.amount, symbol: transaction.symbol, deploymentId: transaction.deploymentId
        )
    }
    func currentValueIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        guard let price = currentPriceIfAvailable(for: coin) else { return nil }
        return coin.amount * price
    }
    func formattedQuotedTotal(_ total: QuotedTotal?) -> String {
        guard let total, let fiat = total.fiatTotal else { return "—" }
        let amount = formatFiatAmount(amount: fiat, currency: portfolioValuation?.currency ?? selectedFiatCurrency)
        guard total.unpricedCount > 0 else { return amount }
        return amount + " · " + AppLocalization.format("%lld without a price", total.unpricedCount)
    }
    func formattedWalletTotal(walletId: String) -> String {
        formattedQuotedTotal(portfolioValuation?.wallets[walletId])
    }
    func currentPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin), let price = livePrices[coin.holdingKey], price.isFinite, price > 0 else { return nil }
        return price
    }
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd { return 1 }
        guard let rate = fiatRatesFromUSD[currency.code], rate.isFinite, rate > 0 else { return nil }
        return rate
    }
    /// Hot path — called per coin during portfolio totals and per row in the
    /// dashboard. Core hands over the whole unpriced set when the selection
    /// changes, so this is a set lookup rather than a memoized FFI call whose
    /// key had to carry every network mode that could affect the answer.
    func isPricedChain(_ chainName: String) -> Bool {
        !unpricedChainNames.contains(chainName)
    }
    func isPricedAsset(_ coin: Coin) -> Bool { isPricedChain(coin.chainName) }
    // MARK: - Network fees

    /// Format a network fee in the chain's gas token using core's display precision.
    func formattedNetworkFee(_ fee: Double, chain: Chain) -> String {
        "\(formattedAmountValue(fee, assetDecimals: chain.nativeDecimals)) \(chain.gasTokenSymbol)"
    }
    /// The fee with its fiat value beside it when the network's own gas asset
    /// has a quote.
    ///
    /// Priced by the network's native deployment, which is what quotes are
    /// keyed by. It priced "the first holding whose symbol is the gas token's",
    /// so an Arbitrum fee took whichever `ETH` came first in the portfolio,
    /// and a testnet fee could take a mainnet price.
    func formattedNetworkFeeWithFiat(_ fee: Double, chain: Chain) -> String {
        let native = formattedNetworkFee(fee, chain: chain)
        guard isPricedChain(chain.displayName),
            let deploymentId = chain.entry?.nativeDeploymentId,
            let price = livePrices[deploymentId],
            let fiat = formattedFiatAmountIfAvailable(fromUSD: fee * price)
        else { return native }
        return "\(native) (~\(fiat))"
    }
    /// A gas price in gwei. Capped by the chain's native decimals like any
    /// amount of it: the unit changes the number, not how many places it needs.
    func formattedGasPrice(gwei: Double, chain: Chain) -> String {
        "\(formattedAmountValue(gwei, assetDecimals: chain.nativeDecimals)) gwei"
    }

    // MARK: - Transaction detail rows

    func receiptEffectiveGasPriceText(for transaction: TransactionRecord) -> String? {
        guard let gwei = transaction.receiptEffectiveGasPriceGwei, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return formattedGasPrice(gwei: gwei, chain: chain)
    }
    func receiptNetworkFeeText(for transaction: TransactionRecord) -> String? {
        guard let fee = transaction.receiptNetworkFee, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return formattedNetworkFee(fee, chain: chain)
    }
    func confirmedNetworkFeeText(for transaction: TransactionRecord) -> String? {
        guard let fee = transaction.confirmedNetworkFee, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return formattedNetworkFee(fee, chain: chain)
    }
    func storedFeeRateText(for transaction: TransactionRecord) -> String? {
        if let description = transaction.feeRateDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        guard let rate = transaction.estimatedFeeRatePerKb, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return "\(formattedNetworkFee(rate, chain: chain))/KB"
    }
    func historyMetadataText(for transaction: TransactionRecord) -> String? {
        var parts: [String] = []
        if let priority = transaction.storedFeePriorityText { parts.append("Fee \(priority)") }
        if let rate = storedFeeRateText(for: transaction) { parts.append(rate) }
        if let usedChangeOutput = transaction.usedChangeOutput, transaction.kind == .send {
            parts.append(AppLocalization.string(usedChangeOutput ? "change output" : "no change output"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    /// What the detail sheet names as the record's history source. Core says
    /// what the stored id means; the sentence around a chain's providers is
    /// this app's to translate, and Spectra's own reader is not named at all.
    func historySourceText(for transaction: TransactionRecord) -> String? {
        switch transaction.transactionHistorySource.flatMap({ historySource(source: $0) }) {
        case .provider(let name): return name
        case .chainProviders(let chainName): return AppLocalization.format("%@ providers", chainName)
        case .internal, nil: return nil
        }
    }

    private func formattedTransactionDetailAssetAmount(_ amount: Double, symbol: String, deploymentId: String?) -> String {
        guard let supportedDecimals = supportedDecimalPlaces(deploymentId: deploymentId) else { return "—" }
        let formatter = AmountFormatters.shared.decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: supportedDecimals, usesGroupingSeparator: false
        )
        let formattedValue = formatter.string(from: NSNumber(value: amount)) ?? ""
        return "\(formattedValue) \(symbol)"
    }
    private func supportedDecimalPlaces(deploymentId: String?) -> Int? {
        guard let assetPrecision else { return nil }
        return Int(deploymentId.flatMap { assetPrecision.byDeploymentId[$0] } ?? assetPrecision.unknownDecimals)
    }

}

/// Native formatter reuse does not require constructing AppState or opening core.
@MainActor
private final class AmountFormatters {
    static let shared = AmountFormatters()
    private var cachedCurrencyFormatters: [FiatCurrency: NumberFormatter] = [:]
    private var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    func fiatFormatter(for currency: FiatCurrency) -> NumberFormatter {
        if let formatter = cachedCurrencyFormatters[currency] { return formatter }
        let rules = currency.displayRules
        let decimals = Int(rules.decimals)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = rules.code
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        cachedCurrencyFormatters[currency] = formatter
        return formatter
    }
    func decimalFormatter(minimumFractionDigits: Int, maximumFractionDigits: Int, usesGroupingSeparator: Bool) -> NumberFormatter {
        let key = "\(minimumFractionDigits):\(maximumFractionDigits):\(usesGroupingSeparator)"
        if let formatter = cachedDecimalFormatters[key] { return formatter }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = usesGroupingSeparator
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        cachedDecimalFormatters[key] = formatter
        return formatter
    }
}
