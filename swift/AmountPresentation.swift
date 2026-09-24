import Foundation

/// A render-time value over core projections. No storage, services or side
/// effects, and no money arithmetic: amounts arrive as exact decimals and
/// every fiat figure arrives in the display currency, both from core.
@MainActor
struct AmountPresentation {
    let assetPrecision: AssetPrecisionCatalog?
    let valuation: PortfolioValuation?
    /// The currency the fiat figures are in when core has not valued anything
    /// yet — the user's selection.
    let selectedFiatCurrency: FiatCurrency

    private var currency: FiatCurrency { valuation?.currency ?? selectedFiatCurrency }

    // MARK: - Fiat

    /// A display-currency figure, or "—" when core has none.
    func formattedFiat(_ value: Double?, currency explicit: FiatCurrency? = nil) -> String {
        formattedFiatIfAvailable(value, currency: explicit) ?? "—"
    }
    func formattedFiatIfAvailable(_ value: Double?, currency explicit: FiatCurrency? = nil) -> String? {
        guard let value, value.isFinite else { return nil }
        let currency = explicit ?? currency
        let formatter = AmountFormatters.shared.fiatFormatter(for: currency)
        let minimumVisible = currency.displayRules.minimumVisible
        if value > 0, value < minimumVisible, let threshold = formatter.string(from: NSNumber(value: minimumVisible)) {
            return "<\(threshold)"
        }
        return formatter.string(from: NSNumber(value: value))
    }
    func formattedQuotedTotal(_ total: QuotedTotal?) -> String {
        guard let total, let fiat = total.fiatTotal else { return "—" }
        let amount = formattedFiat(fiat)
        guard total.unpricedCount > 0 else { return amount }
        return amount + " · " + AppLocalization.format("%lld without a price", total.unpricedCount)
    }
    func formattedWalletTotal(walletId: String) -> String {
        formattedQuotedTotal(valuation?.wallets[walletId])
    }
    /// What a wallet's holding is worth, as core valued it.
    func holdingValue(walletId: String, coin: Coin) -> Double? {
        valuation?.holdingValues[walletId]?[coin.id]
    }
    /// One unit of a held asset, as core priced it.
    func price(of coin: Coin) -> Double? { valuation?.prices[coin.id] }
    /// A price alert's target, as core converted it.
    func alertTarget(_ alert: PriceAlertRule) -> Double? { valuation?.alertTargets[alert.id] }

    // MARK: - Asset amounts

    /// An exact decimal with this locale's decimal separator. No grouping, and
    /// no digit is added or dropped.
    static func localizedDecimal(_ text: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
    }
    /// The amount alone, as a compact row shows it: core picks the places
    /// and cuts, never rounds up.
    func formattedAssetAmountValue(_ amount: String, deploymentId: String?) -> String {
        guard let decimals = supportedDecimalPlaces(deploymentId: deploymentId),
              let text = formatAssetAmount(amount: amount, assetDecimals: UInt32(decimals))
        else { return "—" }
        let value = Self.localizedDecimal(text.value)
        return text.belowThreshold ? "<" + value : value
    }
    func formattedAssetAmount(_ amount: String, symbol: String, deploymentId: String?) -> String {
        "\(formattedAssetAmountValue(amount, deploymentId: deploymentId)) \(symbol)"
    }
    func formattedTransactionAmount(_ transaction: TransactionRecord) -> String {
        formattedAssetAmount(transaction.amount, symbol: transaction.symbol, deploymentId: transaction.deploymentId)
    }
    /// Every digit the record holds.
    func formattedTransactionDetailAmount(_ transaction: TransactionRecord) -> String {
        "\(Self.localizedDecimal(transaction.amount)) \(transaction.symbol)"
    }

    // MARK: - Network fees

    /// A fee in the chain's gas token, exactly as core stated it.
    func formattedNetworkFee(_ fee: String, chain: Chain) -> String {
        "\(Self.localizedDecimal(fee)) \(chain.gasTokenSymbol)"
    }
    /// The fee with its display-currency value beside it, when core had one.
    func formattedNetworkFee(_ fee: String, value: Double?, chain: Chain) -> String {
        let native = formattedNetworkFee(fee, chain: chain)
        guard let fiat = formattedFiatIfAvailable(value) else { return native }
        return "\(native) (~\(fiat))"
    }
    /// A gas price in gwei: a rate, not an amount of anything held.
    func formattedGasPrice(gwei: Double, chain: Chain) -> String {
        let formatter = AmountFormatters.shared.decimalFormatter(maximumFractionDigits: Int(chain.nativeDecimals))
        return "\(formatter.string(from: NSNumber(value: gwei)) ?? "") gwei"
    }

    // MARK: - Transaction detail rows

    func receiptEffectiveGasPriceText(for transaction: TransactionRecord) -> String? {
        guard let gwei = transaction.receiptEffectiveGasPriceGwei, let chain = transaction.chain else { return nil }
        return formattedGasPrice(gwei: gwei, chain: chain)
    }
    func receiptNetworkFeeText(for transaction: TransactionRecord) -> String? {
        guard let fee = transaction.receiptNetworkFee, let chain = transaction.chain else { return nil }
        return formattedNetworkFee(fee, chain: chain)
    }
    func confirmedNetworkFeeText(for transaction: TransactionRecord) -> String? {
        guard let fee = transaction.confirmedNetworkFee, let chain = transaction.chain else { return nil }
        return formattedNetworkFee(fee, chain: chain)
    }
    func storedFeeRateText(for transaction: TransactionRecord) -> String? {
        if let description = transaction.feeRateDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        guard let rate = transaction.estimatedFeeRatePerKb, let chain = transaction.chain else { return nil }
        let formatter = AmountFormatters.shared.decimalFormatter(maximumFractionDigits: Int(chain.nativeDecimals))
        return "\(formatter.string(from: NSNumber(value: rate)) ?? "") \(chain.gasTokenSymbol)/KB"
    }
    func historyMetadataText(for transaction: TransactionRecord) -> String? {
        var parts: [String] = []
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
        case .chainProviders(let chainId): return AppLocalization.format("%@ providers", Chain.displayName(forId: chainId))
        case .internal, nil: return nil
        }
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
    private var cachedDecimalFormatters: [Int: NumberFormatter] = [:]
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
    func decimalFormatter(maximumFractionDigits: Int) -> NumberFormatter {
        if let formatter = cachedDecimalFormatters[maximumFractionDigits] { return formatter }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        cachedDecimalFormatters[maximumFractionDigits] = formatter
        return formatter
    }
}
