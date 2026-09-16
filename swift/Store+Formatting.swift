import Foundation

// Formatting, fiat conversion and localization — one topic: how numbers
// and text are rendered. Conventions live in AGENTS.md.

func localizedStoreString(_ key: String) -> String {
    AppLocalization.string(key)
}


@MainActor
extension AppState {
    func convertUSDToSelectedFiat(_ amountUSD: Double) -> Double { amountUSD * fiatRate(for: selectedFiatCurrency) }
    func convertUSDToSelectedFiatIfAvailable(_ amountUSD: Double) -> Double? {
        guard let rate = fiatRateIfAvailable(for: selectedFiatCurrency) else { return nil }
        return amountUSD * rate
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
        // Memoized: this runs on every fiat render, thousands of times on the
        // dashboard.
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
    /// Core decides how many places this amount deserves; the formatter renders
    /// them and trims the trailing zeros.
    /// The amount alone, at the asset's own precision.
    ///
    /// Callers that render the symbol in a separate label — the send Live
    /// Activity does — need the value without it, and the rounding rules are
    /// the same either way.
    func formattedAssetAmountValue(_ amount: Double, deploymentID: String?) -> String {
        formattedAmountValue(amount, assetDecimals: UInt32(supportedDecimalPlaces(deploymentID: deploymentID)))
    }
    /// An amount at the places core picks for it on an asset with
    /// `assetDecimals` of its own, trailing zeros trimmed.
    func formattedAmountValue(_ amount: Double, assetDecimals: UInt32) -> String {
        let display = formattingAssetAmountDisplay(amount: amount, assetDecimals: assetDecimals)
        let places = Int(display.places)
        if display.belowThreshold {
            let thresholdFormatter = decimalFormatter(
                minimumFractionDigits: places, maximumFractionDigits: places, usesGroupingSeparator: false
            )
            return "<" + (thresholdFormatter.string(from: NSNumber(value: display.threshold)) ?? "")
        }
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: places, usesGroupingSeparator: false
        )
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
    func formattedAssetAmount(_ amount: Double, symbol: String, deploymentID: String?) -> String {
        "\(formattedAssetAmountValue(amount, deploymentID: deploymentID)) \(symbol)"
    }

    /// The asset's own decimals — the contract's, the mint's, or the chain's
    /// `native_decimals` — paired with the amount, which is what decides how
    /// many of them are worth printing.
    func assetAmountDisplay(_ amount: Double, deploymentID: String?) -> AssetAmountDisplay {
        formattingAssetAmountDisplay(
            amount: amount, assetDecimals: UInt32(supportedDecimalPlaces(deploymentID: deploymentID)))
    }
    func formattedTransactionAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedAssetAmount(transaction.amount, symbol: transaction.symbol, deploymentID: transaction.deploymentID)
    }
    func formattedTransactionDetailAmount(_ transaction: TransactionRecord) -> String? {
        guard transaction.amount.isFinite, transaction.amount >= 0 else { return nil }
        return formattedTransactionDetailAssetAmount(
            transaction.amount, symbol: transaction.symbol, deploymentID: transaction.deploymentID
        )
    }
    func currentValue(for coin: Coin) -> Double { coin.amount * currentPrice(for: coin) }
    func currentValueIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        guard let price = currentPriceIfAvailable(for: coin) else { return nil }
        return coin.amount * price
    }
    /// A total and what it could not include.
    ///
    /// Holdings nobody quoted are left out and counted, not folded in at zero
    /// and not at a made-up dollar: a price the feed did not give is not a
    /// price, and a total that quietly contains one cannot be told apart from a
    /// total that does not.
    struct QuotedTotal: Equatable {
        let total: Double
        let unpricedCount: Int
        var isComplete: Bool { unpricedCount == 0 }
    }
    func quotedTotal(for coins: [Coin]) -> QuotedTotal {
        var total: Double = 0
        var unpriced = 0
        for coin in coins where coin.amount > 0 {
            if let value = currentValueIfAvailable(for: coin) {
                total += value
            } else if isPricedAsset(coin) {
                // A chain the app never prices — a testnet — is not a hole in
                // the total; a chain it does price but has no quote for is.
                unpriced += 1
            }
        }
        return QuotedTotal(total: total, unpricedCount: unpriced)
    }
    func assetIdentityKey(for coin: Coin) -> String { coin.holdingKey }
    /// Hot path — called per coin during portfolio totals and per row in the
    /// dashboard. Core hands over the whole unpriced set when the selection
    /// changes, so this is a set lookup rather than a memoized FFI call whose
    /// key had to carry every network mode that could affect the answer.
    func isPricedChain(_ chainName: String) -> Bool {
        !unpricedChainNames.contains(chainName)
    }
    func isPricedAsset(_ coin: Coin) -> Bool { isPricedChain(coin.chainName) }
    /// The history list the UI renders, as core normalizes it.
    func rebuildNormalizedHistoryIndex() async throws {
        let entries = try await WalletServiceBridge.shared.normalizedHistory(
            unknownLabel: localizedStoreString("Unknown"))
        normalizedHistoryIndex = entries.compactMap { entry in
            guard let kind = TransactionKind(rawValue: entry.kind),
                let status = TransactionStatus(rawValue: entry.status)
            else { return nil }
            return NormalizedHistoryEntry(
                id: entry.id, transactionID: entry.transactionId, dedupeKey: entry.dedupeKey,
                createdAt: Date(timeIntervalSince1970: entry.createdAtUnix), kind: kind,
                status: status, walletName: entry.walletName, assetDisplayName: entry.assetDisplayName,
                symbol: entry.symbol, chainName: entry.chainName, address: entry.address,
                transactionHash: entry.transactionHash, sourceTag: entry.sourceTag,
                providerCount: Int(entry.providerCount), searchIndex: entry.searchIndex)
        }
    }
    /// Adopt the views of the transaction store that the UI renders.
    ///
    /// Core derives them from its own records; this caches the answers, which
    /// is what `dashboardAssetGroups` already does. `cachedTransactionByID` is
    /// an index into the projection, so it stays local.
    func rebuildTransactionDerivedState() async {
        cachedTransactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        do {
            let sends = try await WalletServiceBridge.shared.replaceableSends()
            let earliest = try await WalletServiceBridge.shared.earliestTransactionDates()
            try await rebuildNormalizedHistoryIndex()
            replaceableSends = sends
            cachedFirstActivityDateByWalletID = Dictionary(
                uniqueKeysWithValues: earliest.map {
                    ($0.walletId, Date(timeIntervalSince1970: $0.earliestCreatedAtUnix))
                })
            historyReadError = nil
        } catch {
            historyReadError = localizedStoreString("Unable to read transaction history. Existing records have been kept.")
        }
    }

    // MARK: - Network fees

    /// A network fee in the chain's gas token, at the places core picks for
    /// that amount.
    ///
    /// Fees were `%.6f`, `%.8f`, `%.2f gwei` and `%.\(feeDecimals ?? 6)f` across
    /// the send screen, its confirmation step and the transaction sheet — a
    /// different count per screen for one number, and `"%.8f ETH"` for the fee
    /// of every EVM chain whatever its gas token. Core's amount rule already
    /// answers how many places a number deserves on an asset; a fee is an amount
    /// of the chain's native asset.
    func formattedNetworkFee(_ fee: Double, chain: Chain) -> String {
        "\(formattedAmountValue(fee, assetDecimals: chain.nativeDecimals)) \(chain.gasTokenSymbol)"
    }
    /// The fee with its fiat value beside it when there is a quote.
    func formattedNetworkFeeWithFiat(_ fee: Double, chain: Chain) -> String {
        let native = formattedNetworkFee(fee, chain: chain)
        guard let fiat = formattedFiatAmount(fromNative: fee, symbol: chain.gasTokenSymbol) else { return native }
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
        guard let fee = transaction.dogecoinConfirmedNetworkFeeDoge, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return formattedNetworkFee(fee, chain: chain)
    }
    func storedFeeRateText(for transaction: TransactionRecord) -> String? {
        if let description = transaction.feeRateDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        guard let rate = transaction.dogecoinEstimatedFeeRateDogePerKb, let chain = Chain(displayName: transaction.chainName) else { return nil }
        return "\(formattedNetworkFee(rate, chain: chain))/KB"
    }
    func historyMetadataText(for transaction: TransactionRecord) -> String? {
        var parts: [String] = []
        if let priority = transaction.storedFeePriorityText { parts.append("Fee \(priority)") }
        if let rate = storedFeeRateText(for: transaction) { parts.append(rate) }
        if let confirmations = transaction.storedConfirmationCountText { parts.append(confirmations) }
        if let usedChangeOutput = transaction.usedChangeOutput, transaction.kind == .send {
            parts.append(usedChangeOutput ? "change output" : "no change output")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    /// What the detail sheet names as the record's history source. Core says
    /// what the stored id means; the sentence around a chain's providers is
    /// this app's to translate, and Spectra's own reader is not named at all.
    func historySourceText(for transaction: TransactionRecord) -> String? {
        switch transaction.transactionHistorySource.flatMap({ coreHistorySource(source: $0) }) {
        case .provider(let name): return name
        case .chainProviders(let chainName): return AppLocalization.format("%@ providers", chainName)
        case .internal, nil: return nil
        }
    }

    private func formattedTransactionDetailAssetAmount(_ amount: Double, symbol: String, deploymentID: String?) -> String {
        let supportedDecimals = supportedDecimalPlaces(deploymentID: deploymentID)
        let formatter = decimalFormatter(
            minimumFractionDigits: 0, maximumFractionDigits: supportedDecimals, usesGroupingSeparator: false
        )
        let formattedValue = formatter.string(from: NSNumber(value: amount)) ?? ""
        return "\(formattedValue) \(symbol)"
    }
    private func supportedDecimalPlaces(deploymentID: String?) -> Int {
        let customDecimals = deploymentID.flatMap { cachedTokenPreferenceByDeploymentID[$0]?.token.decimals }
        return Int(tokenDisplayDecimals(deploymentId: deploymentID, customDecimals: customDecimals))
    }

}

func evmRecipientMessages(_ warnings: [EvmRecipientPreflightWarning]) -> [String] {
    return warnings.compactMap { w -> String? in
        switch w.code {
        case "recipient_is_contract":
            return AppLocalization.format(
                "Recipient is a smart contract on %@. Confirm it can receive %@ safely.", w.chainName ?? "", w.symbol ?? "")
        case "recipient_code_unknown":
            return AppLocalization.format(
                "Could not verify recipient contract state on %@. Review destination carefully.", w.chainName ?? "")
        case "token_contract_missing":
            return AppLocalization.format(
                "Token contract %@ appears missing on %@. This may be a wrong-network token selection.",
                w.tokenSymbol ?? "", w.chainName ?? "")
        case "token_code_unknown":
            return AppLocalization.format(
                "Could not verify %@ contract bytecode on %@.", w.tokenSymbol ?? "", w.chainName ?? "")
        default: return nil
        }
    }
}
func highRiskSendMessages(_ warnings: [HighRiskSendWarning]) -> [String] {
    return warnings.compactMap { w -> String? in
        switch w.code {
        case "invalid_format": return AppLocalization.format("The destination address format does not match %@.", w.chain ?? "")
        case "new_address": return localizedStoreString("This is a new destination address with no prior history in this wallet.")
        case "ens_resolved":
            return AppLocalization.format(
                "ENS name '%@' resolved to %@. Confirm this resolved address before sending.", w.name ?? "", w.address ?? "")
        case "large_send":
            let formatted = (Double(w.percent ?? 0) / 100.0).formatted(.percent.precision(.fractionLength(0)))
            return AppLocalization.format("This send is %@ of your %@ balance.", formatted, w.symbol ?? "")
        case "non_evm_on_evm":
            return AppLocalization.format("Destination appears to be a non-EVM address while sending on %@.", w.chain ?? "")
        case "ens_off_ethereum":
            return AppLocalization.format(
                "ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", w.chain ?? "")
        case "eth_on_utxo":
            return AppLocalization.format("Destination appears to be an Ethereum-style address while sending on %@.", w.chain ?? "")
        case "non_tron": return localizedStoreString("Destination appears to be non-Tron format while sending on Tron.")
        case "non_solana": return localizedStoreString("Destination appears to be non-Solana format while sending on Solana.")
        case "non_xrp": return localizedStoreString("Destination appears to be non-XRP format while sending on XRP Ledger.")
        case "non_monero": return localizedStoreString("Destination appears to be non-Monero format while sending on Monero.")
        case "chain_mismatch": return localizedStoreString("Wallet-chain context mismatch detected for this send.")
        default: return nil
        }
    }
}
