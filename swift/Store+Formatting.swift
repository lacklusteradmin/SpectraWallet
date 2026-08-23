import Foundation

// Formatting, fiat conversion and localization — one topic: how numbers
// and text are rendered. Conventions live in AGENTS.md.

func localizedStoreString(_ key: String) -> String {
    AppLocalization.string(key)
}

func localizedStoreFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}

@MainActor
extension AppState {
    func convertUSDToSelectedFiat(_ amountUSD: Double) -> Double { amountUSD * fiatRate(for: selectedFiatCurrency) }
    func convertUSDToSelectedFiatIfAvailable(_ amountUSD: Double) -> Double? {
        guard let rate = fiatRateIfAvailable(for: selectedFiatCurrency) else { return nil }
        return amountUSD * rate
    }
    func convertSelectedFiatToUSD(_ amountInSelectedFiat: Double) -> Double {
        let rate = fiatRate(for: selectedFiatCurrency)
        guard rate > 0 else { return amountInSelectedFiat }
        return amountInSelectedFiat / rate
    }
    func formattedFiatAmount(fromUSD amountUSD: Double) -> String {
        formatFiatAmount(amount: convertUSDToSelectedFiat(amountUSD), currency: selectedFiatCurrency)
    }
    func formattedFiatAmountIfAvailable(fromUSD amountUSD: Double) -> String? {
        if selectedFiatCurrency == .usd { return formatFiatAmount(amount: amountUSD, currency: .usd) }
        guard let converted = convertUSDToSelectedFiatIfAvailable(amountUSD) else { return nil }
        return formatFiatAmount(amount: converted, currency: selectedFiatCurrency)
    }
    func formattedFiatAmountOrZero(fromUSD amountUSD: Double?) -> String { formattedFiatAmount(fromUSD: amountUSD ?? 0) }
    func formattedFiatAmountOrUnavailable(fromUSD amountUSD: Double?) -> String {
        guard let amountUSD else { return "—" }
        return formattedFiatAmountIfAvailable(fromUSD: amountUSD) ?? "—"
    }
    /// Memoized accessor for the Rust-side fiat formatting rules. Pure,
    /// input-only function on the Rust side, so we can cache forever.
    private func fiatAmountRules(for currency: FiatCurrency) -> FiatAmountRules {
        let key = currency.rawValue
        if let cached = cachedFiatAmountRules[key] { return cached }
        let rules = formattingFiatAmountRules(currencyCode: key)
        cachedFiatAmountRules[key] = rules
        return rules
    }
    private func fiatFormatter(for currency: FiatCurrency) -> NumberFormatter {
        let key = currency.rawValue
        if let formatter = cachedCurrencyFormatters[key] { return formatter }
        let rules = fiatAmountRules(for: currency)
        let decimals = Int(rules.decimals)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        cachedCurrencyFormatters[key] = formatter
        return formatter
    }
    private func decimalFormatter(minimumFractionDigits: Int, maximumFractionDigits: Int, usesGroupingSeparator: Bool) -> NumberFormatter {
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
    private func formatFiatAmount(amount: Double, currency: FiatCurrency) -> String {
        let formatter = fiatFormatter(for: currency)
        // Previously called `formattingFiatAmountRules` again here on every
        // fiat render (thousands of times on the dashboard). Read from the
        // memoized cache instead.
        let minimumVisibleAmount = fiatAmountRules(for: currency).minimumVisible
        if amount > 0, amount < minimumVisibleAmount, let thresholdString = formatter.string(from: NSNumber(value: minimumVisibleAmount)) {
            return "<\(thresholdString)"
        }
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    func formattedFiatAmount(fromNative amount: Double, symbol: String) -> String? {
        guard let coin = portfolio.first(where: { $0.symbol == symbol }) else { return nil }
        guard let price = currentPriceIfAvailable(for: coin) else { return nil }
        let amountUSD = amount * price
        return formattedFiatAmountIfAvailable(fromUSD: amountUSD)
    }
    func formattedAssetAmount(_ amount: Double, symbol: String, chainName: String) -> String {
        // One FFI call (memoized) instead of two: `supportedDecimalPlaces`
        // and `displayDecimalPlaces` both hit the same Rust helper, so read
        // it once and reuse both fields.
        let resolution = assetDecimalsResolution(symbol: symbol, chainName: chainName)
        let supportedDecimals = Int(resolution.supported)
        let visibleDecimals = min(Int(resolution.display), supportedDecimals)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: visibleDecimals, usesGroupingSeparator: false
        )
        if amount > 0, visibleDecimals > 0 {
            let threshold = assetMinimumVisibleAmount(visibleDecimals: UInt32(visibleDecimals))
            if amount < threshold {
                let thresholdFormatter = decimalFormatter(
                    minimumFractionDigits: visibleDecimals, maximumFractionDigits: visibleDecimals, usesGroupingSeparator: false
                )
                let thresholdText = thresholdFormatter.string(from: NSNumber(value: threshold)) ?? ""
                return "<\(thresholdText) \(symbol)"
            }
        }
        let formattedValue = formatter.string(from: NSNumber(value: amount)) ?? ""
        return "\(formattedValue) \(symbol)"
    }
    func formattedTransactionAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedAssetAmount(transaction.amount, symbol: transaction.symbol, chainName: transaction.chainName)
    }
    func formattedTransactionDetailAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedTransactionDetailAssetAmount(
            transaction.amount, symbol: transaction.symbol, chainName: transaction.chainName
        )
    }
    func supportedAssetDecimals(symbol: String, chainName: String) -> Int { supportedDecimalPlaces(for: symbol, chainName: chainName) }
    func displayAssetDecimals(symbol: String, chainName: String) -> Int { displayDecimalPlaces(for: symbol, chainName: chainName) }
    func assetDisplayDecimalPlaces(for chainName: String) -> Int {
        let settingsKey = nativeAssetDisplaySettingsKey(for: chainName)
        let defaultValue = defaultAssetDisplayDecimalsByChain()[settingsKey] ?? 3
        return assetDisplayDecimalsByChain[settingsKey].map { min(max($0, 0), 30) } ?? defaultValue
    }
    func setAssetDisplayDecimalPlaces(_ decimals: Int, for chainName: String) {
        let settingsKey = nativeAssetDisplaySettingsKey(for: chainName)
        assetDisplayDecimalsByChain[settingsKey] = min(max(decimals, 0), 30)
    }
    func currentValue(for coin: Coin) -> Double { coin.amount * currentPrice(for: coin) }
    func currentValueIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        guard let price = currentOrFallbackPriceIfAvailable(for: coin) else { return nil }
        return coin.amount * price
    }
    func currentTotal(for wallet: ImportedWallet) -> Double {
        wallet.holdings.reduce(0) { $0 + currentValue(for: $1) }
    }
    func currentTotalIfAvailable(for wallet: ImportedWallet) -> Double? { sumLiveQuotedValues(for: wallet.holdings) }
    func sumLiveQuotedValues(for coins: [Coin]) -> Double? {
        var total: Double = 0
        var sawQuotedCoin = false
        for coin in coins where coin.amount > 0 {
            guard let value = currentValueIfAvailable(for: coin) else { return nil }
            total += value
            sawQuotedCoin = true
        }
        return sawQuotedCoin ? total : 0
    }
    func runtimeChainIdentity(for chainName: String) -> String { displayChainTitle(for: chainName) }
    func assetIdentityKey(for coin: Coin) -> String { "\(runtimeChainIdentity(for: coin.chainName))|\(coin.symbol)" }
    /// Hot path — called per coin during portfolio totals and per row in the
    /// dashboard. Core hands over the whole unpriced set when the selection
    /// changes, so this is a set lookup rather than a memoized FFI call whose
    /// key had to carry every network mode that could affect the answer.
    func isPricedChain(_ chainName: String) -> Bool {
        !unpricedChainNames.contains(chainName)
    }
    func isPricedAsset(_ coin: Coin) -> Bool { isPricedChain(coin.chainName) }
    /// The history list the UI renders, as core normalizes it.
    ///
    /// This used to convert the projection into a `NormalizeHistoryRequest` —
    /// core's own records, reshaped — and hand them back. It also hashed them
    /// first, through a second FFI call, so this side could decide whether the
    /// round trip was worth making. Core decides that where the data is.
    func rebuildNormalizedHistoryIndex() async {
        // Nothing to normalize, and no reason to read the store to find out.
        if transactions.isEmpty {
            if !normalizedHistoryIndex.isEmpty { normalizedHistoryIndex = [] }
            return
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let entries = await WalletServiceBridge.shared.normalizedHistory(
            unknownLabel: localizedStoreString("Unknown"))
        normalizedHistoryIndex = entries.compactMap { entry in
            guard let transactionID = UUID(uuidString: entry.transactionId),
                let kind = TransactionKind(rawValue: entry.kind),
                let status = TransactionStatus(rawValue: entry.status)
            else { return nil }
            return NormalizedHistoryEntry(
                id: entry.id, transactionID: transactionID, dedupeKey: entry.dedupeKey,
                createdAt: Date(timeIntervalSince1970: entry.createdAtUnix), kind: kind,
                status: status, walletName: entry.walletName, assetName: entry.assetName,
                symbol: entry.symbol, chainName: entry.chainName, address: entry.address,
                transactionHash: entry.transactionHash, sourceTag: entry.sourceTag,
                providerCount: Int(entry.providerCount), searchIndex: entry.searchIndex)
        }
        recordPerformanceSample(
            "rebuild_normalized_history_index", startedAt: startedAt,
            metadata: "transactions=\(transactions.count) normalized=\(normalizedHistoryIndex.count)")
    }
    /// Adopt the views of the transaction store that the UI renders.
    ///
    /// Core derives them from its own records; this caches the answers, which
    /// is what `dashboardAssetGroups` already does. `cachedTransactionByID` is
    /// an index into the projection, so it stays local.
    func rebuildTransactionDerivedState() async {
        cachedTransactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let earliest = await WalletServiceBridge.shared.earliestTransactionDates()
        cachedFirstActivityDateByWalletID = Dictionary(
            uniqueKeysWithValues: earliest.map {
                ($0.walletId, Date(timeIntervalSince1970: $0.earliestCreatedAtUnix))
            })
        await rebuildNormalizedHistoryIndex()
    }
    /// Drop transactions whose wallet is gone. Core answers which those are,
    /// from the wallets and the records it holds.
    func pruneTransactionsForActiveWallets() async {
        let kept = Set(await WalletServiceBridge.shared.activeWalletTransactionIDs())
        let droppedIDs = transactions.filter { !kept.contains($0.id.uuidString) }.map(\.id)
        guard !droppedIDs.isEmpty else { return }
        removeTransactions(withIDs: droppedIDs)
    }
    private func formattedTransactionDetailAssetAmount(_ amount: Double, symbol: String, chainName: String) -> String {
        let supportedDecimals = supportedDecimalPlaces(for: symbol, chainName: chainName)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: supportedDecimals, usesGroupingSeparator: false
        )
        let formattedValue = formatter.string(from: NSNumber(value: amount)) ?? ""
        return "\(formattedValue) \(symbol)"
    }
    func tokenPreferenceLookupKey(chainName: String, symbol: String) -> String {
        let cacheKey = "\(chainName)|\(symbol)"
        if let cached = cachedTokenPreferenceLookupKeys[cacheKey] { return cached }
        let value = formattingTokenPreferenceLookupKey(chainName: chainName, symbol: symbol)
        cachedTokenPreferenceLookupKeys[cacheKey] = value
        return value
    }
    private func supportedDecimalPlaces(for symbol: String, chainName: String) -> Int {
        Int(assetDecimalsResolution(symbol: symbol, chainName: chainName).supported)
    }
    private func displayDecimalPlaces(for symbol: String, chainName: String) -> Int {
        Int(assetDecimalsResolution(symbol: symbol, chainName: chainName).display)
    }
    /// Memoized wrapper over the Rust `formattingResolveAssetDecimals` FFI.
    /// Invalidated by `assetDisplayDecimalsByChain.didSet` (display prefs
    /// change) and `tokenPreferences.didSet` (custom token decimals change).
    func assetDecimalsResolution(symbol: String, chainName: String) -> (supported: UInt32, display: UInt32) {
        let cacheKey = "\(chainName)|\(symbol)"
        if let cached = cachedAssetDecimalsResolutions[cacheKey] { return cached }
        let assetDisplay = UInt32(min(max(assetDisplayDecimalPlaces(for: chainName), 0), 30))
        let tokenOverride = cachedTokenPreferenceByChainAndSymbol[tokenPreferenceLookupKey(chainName: chainName, symbol: symbol)].map {
            entry in
            TokenPreferenceOverride(
                chainName: chainName, symbol: symbol,
                decimals: UInt32(max(0, entry.decimals)),
                displayDecimals: entry.displayDecimals.map { UInt32(max(0, $0)) }
            )
        }
        let result = formattingResolveAssetDecimals(
            request: AssetDecimalsRequest(
                chainName: chainName, symbol: symbol,
                assetDisplayDecimals: assetDisplay,
                tokenOverride: tokenOverride
            ))
        let pair: (supported: UInt32, display: UInt32) = (result.supported, result.display)
        cachedAssetDecimalsResolutions[cacheKey] = pair
        return pair
    }
    /// The smallest amount that still shows at `visibleDecimals` places.
    ///
    /// Was an FFI call — `10^-n`, crossed the boundary and memoized on this
    /// side. A rule core owns is worth a call; an exponent is not.
    private func assetMinimumVisibleAmount(visibleDecimals: UInt32) -> Double {
        visibleDecimals == 0 ? 0 : pow(10, -Double(visibleDecimals))
    }
    func defaultAssetDisplayDecimalsByChain(defaultValue: Int = 3) -> [String: Int] {
        let normalized = UInt32(min(max(defaultValue, 0), 30))
        return CachedCoreHelpers.defaultAssetDisplayDecimalsByChain(defaultValue: normalized).mapValues { Int($0) }
    }
    private func nativeAssetDisplaySettingsKey(for chainName: String) -> String {
        CachedCoreHelpers.nativeAssetDisplaySettingsKey(chainName: chainName)
    }
}
