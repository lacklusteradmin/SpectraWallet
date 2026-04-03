import Foundation

@MainActor
extension WalletStore {
    func convertUSDToSelectedFiat(_ amountUSD: Double) -> Double {
        amountUSD * fiatRate(for: selectedFiatCurrency)
    }

    func convertUSDToSelectedFiatIfAvailable(_ amountUSD: Double) -> Double? {
        guard let rate = fiatRateIfAvailable(for: selectedFiatCurrency) else {
            return nil
        }
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
        if selectedFiatCurrency == .usd {
            return formatFiatAmount(amount: amountUSD, currency: .usd)
        }
        guard let converted = convertUSDToSelectedFiatIfAvailable(amountUSD) else {
            return nil
        }
        return formatFiatAmount(amount: converted, currency: selectedFiatCurrency)
    }

    func formattedFiatAmountOrZero(fromUSD amountUSD: Double?) -> String {
        formattedFiatAmount(fromUSD: amountUSD ?? 0)
    }

    func formattedFiatAmountOrUnavailable(fromUSD amountUSD: Double?) -> String {
        guard let amountUSD else { return "—" }
        return formattedFiatAmountIfAvailable(fromUSD: amountUSD) ?? "—"
    }

    private func fiatFormatter(for currency: FiatCurrency) -> NumberFormatter {
        let key = currency.rawValue
        if let formatter = cachedCurrencyFormatters[key] {
            return formatter
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = currency == .jpy ? 0 : 2
        formatter.maximumFractionDigits = currency == .jpy ? 0 : 2
        cachedCurrencyFormatters[key] = formatter
        return formatter
    }

    private func decimalFormatter(
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        usesGroupingSeparator: Bool
    ) -> NumberFormatter {
        let key = "\(minimumFractionDigits):\(maximumFractionDigits):\(usesGroupingSeparator)"
        if let formatter = cachedDecimalFormatters[key] {
            return formatter
        }

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
        let minimumVisibleAmount = currency == .jpy ? 1.0 : 0.01
        if amount > 0, amount < minimumVisibleAmount,
           let thresholdString = formatter.string(from: NSNumber(value: minimumVisibleAmount)) {
            return "<\(thresholdString)"
        }
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
            minimumFractionDigits: 0,
            maximumFractionDigits: visibleDecimals,
            usesGroupingSeparator: false
        )

        if amount > 0, visibleDecimals > 0 {
            let threshold = pow(10.0, Double(-visibleDecimals))
            if amount < threshold {
                let thresholdFormatter = decimalFormatter(
                    minimumFractionDigits: visibleDecimals,
                    maximumFractionDigits: visibleDecimals,
                    usesGroupingSeparator: false
                )
                let thresholdText = thresholdFormatter.string(from: NSNumber(value: threshold))
                    ?? String(format: "%.\(visibleDecimals)f", threshold)
                return "<\(thresholdText) \(symbol)"
            }
        }

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
            transaction.amount,
            symbol: transaction.symbol,
            chainName: transaction.chainName
        )
    }

    func supportedAssetDecimals(symbol: String, chainName: String) -> Int {
        supportedDecimalPlaces(for: symbol, chainName: chainName)
    }

    func displayAssetDecimals(symbol: String, chainName: String) -> Int {
        displayDecimalPlaces(for: symbol, chainName: chainName)
    }

    func assetDisplayDecimalPlaces(for chainName: String) -> Int {
        let settingsKey = nativeAssetDisplaySettingsKey(for: chainName)
        let defaultValue = defaultAssetDisplayDecimalsByChain()[settingsKey] ?? 3
        return assetDisplayDecimalsByChain[settingsKey].map { min(max($0, 0), 30) } ?? defaultValue
    }

    func setAssetDisplayDecimalPlaces(_ decimals: Int, for chainName: String) {
        let settingsKey = nativeAssetDisplaySettingsKey(for: chainName)
        assetDisplayDecimalsByChain[settingsKey] = min(max(decimals, 0), 30)
    }

    func currentValue(for coin: Coin) -> Double {
        coin.amount * currentPrice(for: coin)
    }

    func currentValueIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else {
            return nil
        }
        guard let price = currentOrFallbackPriceIfAvailable(for: coin) else {
            return nil
        }
        return coin.amount * price
    }

    func currentTotal(for wallet: ImportedWallet) -> Double {
        wallet.holdings.reduce(0) { $0 + currentValue(for: $1) }
    }

    func currentTotalIfAvailable(for wallet: ImportedWallet) -> Double? {
        sumLiveQuotedValues(for: wallet.holdings)
    }

    func sumLiveQuotedValues(for coins: [Coin]) -> Double? {
        var total: Double = 0
        var sawQuotedCoin = false
        for coin in coins where coin.amount > 0 {
            guard let value = currentValueIfAvailable(for: coin) else {
                return nil
            }
            total += value
            sawQuotedCoin = true
        }
        return sawQuotedCoin ? total : 0
    }

    func runtimeChainIdentity(for chainName: String) -> String {
        displayChainTitle(for: chainName)
    }

    func assetIdentityKey(for coin: Coin) -> String {
        "\(runtimeChainIdentity(for: coin.chainName))|\(coin.symbol)"
    }

    func isPricedChain(_ chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin":
            return bitcoinNetworkMode == .mainnet
        case "Ethereum":
            return ethereumNetworkMode == .mainnet
        case "Dogecoin":
            return true
        default:
            return true
        }
    }

    func isPricedAsset(_ coin: Coin) -> Bool {
        isPricedChain(coin.chainName)
    }

    private func normalizedHistoryInputSignature(walletByID: [UUID: ImportedWallet]) -> Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        for transaction in transactions {
            hasher.combine(transaction.id)
            hasher.combine(transaction.walletID)
            hasher.combine(transaction.kind.rawValue)
            hasher.combine(transaction.status.rawValue)
            hasher.combine(transaction.chainName)
            hasher.combine(transaction.symbol)
            hasher.combine(transaction.transactionHash ?? "")
            hasher.combine(transaction.createdAt.timeIntervalSinceReferenceDate.bitPattern)
        }

        for walletID in walletByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let wallet = walletByID[walletID] else { continue }
            hasher.combine(walletID)
            hasher.combine(wallet.selectedChain)
        }

        return hasher.finalize()
    }

    func rebuildNormalizedHistoryIndex() {
        let walletByID = cachedWalletByID.isEmpty
            ? Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
            : cachedWalletByID
        let inputSignature = normalizedHistoryInputSignature(walletByID: walletByID)
        guard transactionState.lastNormalizedHistorySignature != inputSignature else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        var groupedByDedupeKey: [String: [NormalizedHistoryEntry]] = [:]
        for transaction in transactions {
            guard let walletID = transaction.walletID,
                  let wallet = walletByID[walletID],
                  wallet.selectedChain == transaction.chainName else {
                continue
            }
            let entry = normalizedHistoryEntry(for: transaction)
            groupedByDedupeKey[entry.dedupeKey, default: []].append(entry)
        }

        let deduped = groupedByDedupeKey.values.compactMap { entries -> NormalizedHistoryEntry? in
            guard !entries.isEmpty else { return nil }
            let providerSet = Set(entries.map(\.sourceTag))
            let providerCount = max(1, providerSet.count)
            let best = entries.max { lhs, rhs in
                let lhsStatusRank = normalizedStatusRank(lhs.status)
                let rhsStatusRank = normalizedStatusRank(rhs.status)
                if lhsStatusRank != rhsStatusRank {
                    return lhsStatusRank < rhsStatusRank
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.transactionID.uuidString < rhs.transactionID.uuidString
            }
            guard let best else { return nil }
            return NormalizedHistoryEntry(
                id: best.id,
                transactionID: best.transactionID,
                dedupeKey: best.dedupeKey,
                createdAt: best.createdAt,
                kind: best.kind,
                status: best.status,
                walletName: best.walletName,
                assetName: best.assetName,
                symbol: best.symbol,
                chainName: best.chainName,
                address: best.address,
                transactionHash: best.transactionHash,
                sourceTag: best.sourceTag,
                providerCount: providerCount,
                searchIndex: best.searchIndex
            )
        }

        normalizedHistoryIndex = deduped.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
        transactionState.lastNormalizedHistorySignature = inputSignature
        recordPerformanceSample(
            "rebuild_normalized_history_index",
            startedAt: startedAt,
            metadata: "transactions=\(transactions.count) normalized=\(normalizedHistoryIndex.count)"
        )
    }

    func rebuildTransactionDerivedState() {
        cachedTransactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        var earliestTransactionDateByWalletID: [UUID: Date] = [:]
        for transaction in transactions {
            guard let walletID = transaction.walletID else { continue }
            if let currentEarliest = earliestTransactionDateByWalletID[walletID] {
                if transaction.createdAt < currentEarliest {
                    earliestTransactionDateByWalletID[walletID] = transaction.createdAt
                }
            } else {
                earliestTransactionDateByWalletID[walletID] = transaction.createdAt
            }
        }
        cachedFirstActivityDateByWalletID = earliestTransactionDateByWalletID
        rebuildNormalizedHistoryIndex()
    }

    func pruneTransactionsForActiveWallets() {
        let walletByID = cachedWalletByID.isEmpty
            ? Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
            : cachedWalletByID
        let filtered = transactions.filter { transaction in
            guard let walletID = transaction.walletID,
                  let wallet = walletByID[walletID] else {
                return false
            }
            return wallet.selectedChain == transaction.chainName
        }
        guard filtered.count != transactions.count else { return }
        transactions = filtered.sorted { $0.createdAt > $1.createdAt }
    }

    private func formattedTransactionDetailAssetAmount(_ amount: Double, symbol: String, chainName: String) -> String {
        let supportedDecimals = supportedDecimalPlaces(for: symbol, chainName: chainName)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0,
            maximumFractionDigits: supportedDecimals,
            usesGroupingSeparator: false
        )

        let formattedValue = formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.\(supportedDecimals)f", amount)
        return "\(formattedValue) \(symbol)"
    }

    func tokenPreferenceLookupKey(chainName: String, symbol: String) -> String {
        let normalizedChain = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(normalizedChain)|\(normalizedSymbol)"
    }

    private func supportedDecimalPlaces(for symbol: String, chainName: String) -> Int {
        if let trackedToken = cachedTokenPreferenceByChainAndSymbol[tokenPreferenceLookupKey(chainName: chainName, symbol: symbol)] {
            return trackedToken.decimals
        }

        switch chainName {
        case "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin":
            return 8
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return 18
        case "Tron", "Cardano", "XRP Ledger":
            return 6
        case "Solana", "Sui":
            return 9
        case "Aptos":
            return 8
        case "TON":
            return 9
        case "Monero":
            return 12
        case "NEAR":
            return 24
        case "Polkadot":
            return 10
        default:
            return 6
        }
    }

    private func displayDecimalPlaces(for symbol: String, chainName: String) -> Int {
        if let trackedToken = cachedTokenPreferenceByChainAndSymbol[tokenPreferenceLookupKey(chainName: chainName, symbol: symbol)] {
            let defaultDisplay = min(assetDisplayDecimalPlaces(for: chainName), trackedToken.decimals)
            return min(max(trackedToken.displayDecimals ?? defaultDisplay, 0), trackedToken.decimals)
        }
        return assetDisplayDecimalPlaces(for: chainName)
    }

    func defaultAssetDisplayDecimalsByChain(defaultValue: Int = 3) -> [String: Int] {
        let normalized = min(max(defaultValue, 0), 30)
        return [
            "Bitcoin": normalized,
            "Bitcoin Cash": normalized,
            "Bitcoin SV": normalized,
            "Litecoin": normalized,
            "Dogecoin": normalized,
            "Ethereum": normalized,
            "Ethereum Classic": normalized,
            "Arbitrum": normalized,
            "Optimism": normalized,
            "BNB Chain": normalized,
            "Avalanche": normalized,
            "Hyperliquid": normalized,
            "Tron": normalized,
            "Solana": normalized,
            "Cardano": normalized,
            "XRP Ledger": normalized,
            "Monero": normalized,
            "Sui": normalized,
            "Aptos": normalized,
            "TON": normalized,
            "NEAR": normalized,
            "Polkadot": normalized,
        ]
    }

    private func nativeAssetDisplaySettingsKey(for chainName: String) -> String {
        switch chainName {
        case "Ethereum", "Arbitrum", "Optimism":
            return "Ethereum"
        default:
            return chainName
        }
    }

    private func normalizedHistoryEntry(for transaction: TransactionRecord) -> NormalizedHistoryEntry {
        let walletKey = transaction.walletID?.uuidString.lowercased() ?? "unknown-wallet"
        let normalizedChain = transaction.chainName.lowercased()
        let normalizedSymbol = transaction.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dedupeKey: String
        let stableID: String
        if let transactionHash = transaction.transactionHash?.lowercased(), !transactionHash.isEmpty {
            dedupeKey = "\(walletKey)|\(normalizedChain)|\(normalizedSymbol)|\(transactionHash)"
            stableID = dedupeKey
        } else {
            dedupeKey = "local|\(walletKey)|\(transaction.id.uuidString.lowercased())"
            stableID = "local|\(walletKey)|\(transaction.id.uuidString.lowercased())"
        }

        let sourceTag = normalizedHistorySourceTag(transaction.transactionHistorySource)
        let searchIndex = [
            transaction.walletName,
            transaction.assetName,
            transaction.symbol,
            transaction.chainName,
            transaction.address,
            transaction.transactionHash ?? "",
            sourceTag
        ]
            .joined(separator: " ")
            .lowercased()

        return NormalizedHistoryEntry(
            id: stableID,
            transactionID: transaction.id,
            dedupeKey: dedupeKey,
            createdAt: transaction.createdAt,
            kind: transaction.kind,
            status: transaction.status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            sourceTag: sourceTag,
            providerCount: 1,
            searchIndex: searchIndex
        )
    }

    private func normalizedStatusRank(_ status: TransactionStatus) -> Int {
        switch status {
        case .confirmed: return 3
        case .pending: return 2
        case .failed: return 1
        }
    }

    private func normalizedHistorySourceTag(_ rawSource: String?) -> String {
        let trimmed = rawSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !trimmed.isEmpty else { return localizedStoreString("Unknown") }
        switch trimmed {
        case "esplora": return "Esplora"
        case "litecoinspace": return "LitecoinSpace"
        case "blockchair": return "Blockchair"
        case "blockcypher": return "BlockCypher"
        case "dogecoin.providers": return "DOGE Providers"
        case "rpc": return "RPC"
        case "etherscan": return "Etherscan"
        case "blockscout": return "Blockscout"
        case "ethplorer": return "Ethplorer"
        case "none": return localizedStoreString("Unknown")
        default: return trimmed.capitalized
        }
    }
}
