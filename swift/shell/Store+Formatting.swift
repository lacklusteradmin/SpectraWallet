import Foundation

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
    func formattedFiatAmount(fromUSD amountUSD: Double) -> String { formatFiatAmount(amount: convertUSDToSelectedFiat(amountUSD), currency: selectedFiatCurrency) }
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
    private func fiatFormatter(for currency: FiatCurrency) -> NumberFormatter {
        let key = currency.rawValue
        if let formatter = cachedCurrencyFormatters[key] { return formatter }
        let rules = formattingFiatAmountRules(currencyCode: currency.rawValue)
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
        let minimumVisibleAmount = formattingFiatAmountRules(currencyCode: currency.rawValue).minimumVisible
        if amount > 0, amount < minimumVisibleAmount, let thresholdString = formatter.string(from: NSNumber(value: minimumVisibleAmount)) { return "<\(thresholdString)" }
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency.rawValue) \(String(format: "%.2f", amount))"
    }
    func formattedFiatAmount(fromNative amount: Double, symbol: String) -> String? {
        guard let coin = portfolio.first(where: { $0.symbol == symbol }) else { return nil }
        guard let price = currentPriceIfAvailable(for: coin) else { return nil }
        let amountUSD = amount * price
        return formattedFiatAmountIfAvailable(fromUSD: amountUSD)
    }
    func formattedAssetAmount(_ amount: Double, symbol: String, chainName: String) -> String {
        let supportedDecimals = supportedDecimalPlaces(for: symbol, chainName: chainName)
        let visibleDecimals = min(displayDecimalPlaces(for: symbol, chainName: chainName), supportedDecimals)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: visibleDecimals, usesGroupingSeparator: false
        )
        if amount > 0, visibleDecimals > 0 {
            let threshold = formattingAssetMinimumVisibleAmount(visibleDecimals: UInt32(visibleDecimals))
            if amount < threshold {
                let thresholdFormatter = decimalFormatter(
                    minimumFractionDigits: visibleDecimals, maximumFractionDigits: visibleDecimals, usesGroupingSeparator: false
                )
                let thresholdText = thresholdFormatter.string(from: NSNumber(value: threshold))
                    ?? String(format: "%.\(visibleDecimals)f", threshold)
                return "<\(thresholdText) \(symbol)"
            }}
        let formattedValue = formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.\(visibleDecimals)f", amount)
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
        wallet.holdings.reduce(0) { $0 + currentValue(for: $1) }}
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
    func isPricedChain(_ chainName: String) -> Bool {
        corePlanPricedChain(
            chainName: chainName, bitcoinNetworkModeRaw: bitcoinNetworkMode.rawValue, ethereumNetworkModeRaw: ethereumNetworkMode.rawValue
        )
    }
    func isPricedAsset(_ coin: Coin) -> Bool { isPricedChain(coin.chainName) }
    private func walletChainInputs(from walletByID: [String: ImportedWallet]) -> [WalletChainInput] {
        walletByID.map { WalletChainInput(walletId: $0.key, selectedChain: $0.value.selectedChain) }
    }
    func rebuildNormalizedHistoryIndex() {
        let walletByID = cachedWalletByID.isEmpty ? Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) }) : cachedWalletByID
        let signatureInputs = transactions.map { transaction in
            NormalizedHistorySignatureTransaction(
                id: transaction.id.uuidString, walletId: transaction.walletID, kind: transaction.kind.rawValue, status: transaction.status.rawValue, chainName: transaction.chainName, symbol: transaction.symbol, transactionHash: transaction.transactionHash, createdAtUnix: transaction.createdAt.timeIntervalSince1970
            )
        }
        let inputSignature = Int(corePlanNormalizedHistorySignature(
            transactions: signatureInputs, wallets: walletChainInputs(from: walletByID)
        ))
        guard lastNormalizedHistorySignature != inputSignature else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let normalizedEntries = rebuildNormalizedHistoryIndexUsingRust(walletByID: walletByID)
        normalizedHistoryIndex = normalizedEntries
        lastNormalizedHistorySignature = inputSignature
        recordPerformanceSample(
            "rebuild_normalized_history_index", startedAt: startedAt, metadata: "transactions=\(transactions.count) normalized=\(normalizedHistoryIndex.count)"
        )
    }
    func rebuildTransactionDerivedState() {
        cachedTransactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let earliestInputs = transactions.map { TransactionEarliestInput(walletId: $0.walletID, createdAtUnix: $0.createdAt.timeIntervalSince1970) }
        let earliestPairs = corePlanEarliestTransactionDates(transactions: earliestInputs)
        cachedFirstActivityDateByWalletID = Dictionary(uniqueKeysWithValues: earliestPairs.map { ($0.walletId, Date(timeIntervalSince1970: $0.earliestCreatedAtUnix)) })
        rebuildNormalizedHistoryIndex()
    }
    func pruneTransactionsForActiveWallets() {
        let walletByID = cachedWalletByID.isEmpty ? Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) }) : cachedWalletByID
        let activityInputs = transactions.map { TransactionActivityInput(id: $0.id.uuidString, walletId: $0.walletID, chainName: $0.chainName) }
        let keptIDStrings = Set(
            corePlanActiveWalletTransactionIds(
                transactions: activityInputs, wallets: walletChainInputs(from: walletByID)
            )
        )
        let filtered = transactions.filter { keptIDStrings.contains($0.id.uuidString) }
        guard filtered.count != transactions.count else { return }
        setTransactions(filtered.sorted { $0.createdAt > $1.createdAt })}
    private func formattedTransactionDetailAssetAmount(_ amount: Double, symbol: String, chainName: String) -> String {
        let supportedDecimals = supportedDecimalPlaces(for: symbol, chainName: chainName)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: supportedDecimals, usesGroupingSeparator: false
        )
        let formattedValue = formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.\(supportedDecimals)f", amount)
        return "\(formattedValue) \(symbol)"
    }
    func tokenPreferenceLookupKey(chainName: String, symbol: String) -> String {
        formattingTokenPreferenceLookupKey(chainName: chainName, symbol: symbol)
    }
    private func supportedDecimalPlaces(for symbol: String, chainName: String) -> Int {
        Int(rustAssetDecimalsResolution(symbol: symbol, chainName: chainName).supported)
    }
    private func displayDecimalPlaces(for symbol: String, chainName: String) -> Int {
        Int(rustAssetDecimalsResolution(symbol: symbol, chainName: chainName).display)
    }
    private func rustAssetDecimalsResolution(symbol: String, chainName: String) -> (supported: UInt32, display: UInt32) {
        let assetDisplay = UInt32(min(max(assetDisplayDecimalPlaces(for: chainName), 0), 30))
        let tokenOverride = cachedTokenPreferenceByChainAndSymbol[tokenPreferenceLookupKey(chainName: chainName, symbol: symbol)].map { entry in
            TokenPreferenceOverride(
                chainName: chainName, symbol: symbol,
                decimals: UInt32(max(0, entry.decimals)),
                displayDecimals: entry.displayDecimals.map { UInt32(max(0, $0)) }
            )
        }
        let result = formattingResolveAssetDecimals(request: AssetDecimalsRequest(
            chainName: chainName, symbol: symbol,
            assetDisplayDecimals: assetDisplay,
            tokenOverride: tokenOverride
        ))
        return (result.supported, result.display)
    }
    func defaultAssetDisplayDecimalsByChain(defaultValue: Int = 3) -> [String: Int] {
        let normalized = UInt32(min(max(defaultValue, 0), 30))
        return formattingDefaultAssetDisplayDecimalsByChain(defaultValue: normalized).mapValues { Int($0) }
    }
    private func nativeAssetDisplaySettingsKey(for chainName: String) -> String {
        formattingNativeAssetDisplaySettingsKey(chainName: chainName)
    }
    private func rebuildNormalizedHistoryIndexUsingRust(walletByID: [String: ImportedWallet]) -> [NormalizedHistoryEntry] {
        let request = NormalizeHistoryRequest(
            wallets: walletByID.map {
                HistoryWallet(
                    walletId: $0.key.lowercased(), selectedChain: $0.value.selectedChain
                )
            }, transactions: transactions.map {
                HistoryTransaction(
                    id: $0.id.uuidString.lowercased(), walletId: $0.walletID?.lowercased(), kind: $0.kind.rawValue, status: $0.status.rawValue, walletName: $0.walletName, assetName: $0.assetName, symbol: $0.symbol, chainName: $0.chainName, address: $0.address, transactionHash: $0.transactionHash, transactionHistorySource: $0.transactionHistorySource, createdAtUnix: $0.createdAt.timeIntervalSince1970
                )
            }, unknownLabel: localizedStoreString("Unknown")
        )
        let entries = coreNormalizeHistory(request: request)
        return entries.compactMap { entry in
            guard let transactionID = UUID(uuidString: entry.transactionId), let kind = TransactionKind(rawValue: entry.kind), let status = TransactionStatus(rawValue: entry.status) else { return nil }
            return NormalizedHistoryEntry(
                id: entry.id, transactionID: transactionID, dedupeKey: entry.dedupeKey, createdAt: Date(timeIntervalSince1970: entry.createdAtUnix), kind: kind, status: status, walletName: entry.walletName, assetName: entry.assetName, symbol: entry.symbol, chainName: entry.chainName, address: entry.address, transactionHash: entry.transactionHash, sourceTag: entry.sourceTag, providerCount: Int(entry.providerCount), searchIndex: entry.searchIndex
            )
        }
    }
}
