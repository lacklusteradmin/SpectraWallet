import Foundation
import SwiftUI
@MainActor
extension AppState {
    @discardableResult
    func refreshLivePrices() async -> Bool {
        guard !isRefreshingLivePrices else { return false }
        isRefreshingLivePrices = true
        defer {
            isRefreshingLivePrices = false
            lastLivePriceRefreshAt = Date()
        }
        var didUpdatePrices = false
        let requestedCoins = priceRequestCoins
        guard !requestedCoins.isEmpty else {
            quoteRefreshError = nil
            return false
        }
        do {
            let rustInputs = requestedCoins.map { coin in
                PriceRequestCoin(
                    holdingKey: coin.holdingKey, symbol: coin.symbol, coinGeckoId: coin.coinGeckoId
                )
            }
            let fetchedPrices = try await WalletServiceBridge.shared.fetchPricesViaRust(
                provider: pricingProvider.rawValue, coins: rustInputs
            )
            guard !fetchedPrices.isEmpty else {
                quoteRefreshError = localizedStoreFormat("%@ returned no supported asset quotes", pricingProvider.rawValue)
                return false
            }
            let outcome = priceMergeLiveUpdates(existing: livePrices, fetched: fetchedPrices)
            if outcome.hadMeaningfulChange { livePrices = outcome.updatedPrices }
            quoteRefreshError = nil
            didUpdatePrices = outcome.hadMeaningfulChange
        } catch {
            quoteRefreshError = localizedStoreFormat("%@ pricing unavailable", pricingProvider.rawValue)
        }
        if didUpdatePrices { await evaluatePriceAlerts() }
        return didUpdatePrices
    }
    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        if !force, selectedFiatCurrency == .usd { return }
        if !force, let lastFiatRatesRefreshAt,
            Date().timeIntervalSince(lastFiatRatesRefreshAt) < Self.fiatRatesRefreshInterval
        { return }
        // After a failed attempt, hold off before retrying. Without this gate a
        // degraded provider was hit on every maintenance tick + every foreground
        // path because `lastFiatRatesRefreshAt` is only stamped on success.
        if !force, let lastFiatRatesAttemptAt, fiatRatesRefreshError != nil,
            Date().timeIntervalSince(lastFiatRatesAttemptAt) < Self.fiatRatesRetryBackoff
        { return }
        await refreshFiatExchangeRates()
    }
    func refreshFiatExchangeRates() async {
        guard !isRefreshingFiatRates else { return }
        isRefreshingFiatRates = true
        defer {
            isRefreshingFiatRates = false
            lastFiatRatesAttemptAt = Date()
        }
        do {
            let fetchedRates = try await WalletServiceBridge.shared.fetchFiatRatesViaRust(
                provider: fiatRateProvider.rawValue, currencies: FiatCurrency.allCases.map(\.rawValue)
            )
            let rates = priceMergeFiatRateUpdates(
                fetched: fetchedRates, existing: fiatRatesFromUSD,
                currencies: FiatCurrency.allCases.map(\.rawValue),
                baseCurrency: FiatCurrency.usd.rawValue
            )
            fiatRatesFromUSD = rates
            persistCodableToSQLite(rates, key: Self.fiatRatesFromUSDDefaultsKey)
            fiatRatesRefreshError = nil
            lastFiatRatesRefreshAt = Date()
        } catch {
            if fiatRatesFromUSD.isEmpty {
                fiatRatesFromUSD = [FiatCurrency.usd.rawValue: 1.0]
            } else {
                fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
            }
            fiatRatesRefreshError = localizedStoreFormat(
                "%@ fiat exchange rates are unavailable. Using the last successful rates.", fiatRateProvider.rawValue)
        }
    }
    func activePriceKey(for coin: Coin) -> String { assetIdentityKey(for: coin) }
    var totalBalance: Double {
        portfolio.reduce(0) { $0 + currentValue(for: $1) }
    }
    // ── Fiat currency (core-owned) ────────────────────────────────────────

    /// Load core's state and mirror it. Call once at launch.
    func loadCoreOwnedState() async {
        let epoch = beginCoreStateRead()
        guard let state = try? await WalletServiceBridge.shared.openState() else { return }
        applyCoreState(state, epoch: epoch)
    }

    /// Send the currency change to core and mirror the result.
    ///
    /// Core decides — it normalizes the code and reports whether anything
    /// actually changed, so the rate refresh only runs on a real change.
    func setFiatCurrency(_ currency: FiatCurrency) async {
        let epoch = beginCoreStateRead()
        guard
            let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                .setFiatCurrency(fiatCurrencyCode: currency.rawValue))
        else { return }
        applyCoreState(transition.state, epoch: epoch)
        guard transition.events.contains(where: { $0.kind == "fiatCurrencyChanged" }) else { return }
        await refreshFiatExchangeRatesIfNeeded(force: true)
    }

    var totalBalanceIfAvailable: Double? { sumLiveQuotedValues(for: portfolio) }
    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: String) {
        guard var wallet = wallets.first(where: { $0.id == walletID }) else { return }
        wallet.includeInPortfolioTotal = isIncluded
        recordWalletDetached(wallet)
        resetLargeMovementAlertBaseline()
    }
    func hasWalletForChain(_ chainName: String) -> Bool {
        let eligibilityInputs: [WalletChainEligibilityInput] = wallets.map { wallet in
            let hasSeedPhrase: Bool = (storedSeedPhrase(for: wallet.id)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            let bitcoinAddressIsValid: Bool =
                wallet.bitcoinAddress.map {
                    AddressValidation.isValid(
                        $0,
                        kind: coreAddressValidationKind(
                            chainId: walletNetworkChainID(for: wallet, family: "bitcoin")))
                } ?? false
            return WalletChainEligibilityInput(
                walletId: wallet.id, selectedChain: wallet.selectedChain, hasSeedPhrase: hasSeedPhrase,
                bitcoinAddress: wallet.bitcoinAddress, bitcoinAddressIsValid: bitcoinAddressIsValid, bitcoinXpub: wallet.bitcoinXpub,
                resolvedAddressForChain: resolvedAddress(for: wallet, chainName: chainName)
            )
        }
        return coreHasWalletForChain(chainName: chainName, wallets: eligibilityInputs)
    }
    func refreshChainBalances(
        includeHistoryRefreshes: Bool = true, historyRefreshInterval: TimeInterval = 120, forceChainRefresh: Bool = true
    ) async {
        _ = forceChainRefresh  // Rust always fetches fresh data
        guard !isRefreshingChainBalances else { return }
        isRefreshingChainBalances = true
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        if includeHistoryRefreshes { await runHistoryRefreshes(for: refreshableChainIDs, interval: historyRefreshInterval) }
    }
    func withBalanceRefreshWindow(_ operation: () async -> Void) async {
        let previousState = allowsBalanceNetworkRefresh
        allowsBalanceNetworkRefresh = true
        defer { allowsBalanceNetworkRefresh = previousState }
        await operation()
    }
    func refreshWalletBalance(_ walletID: String) async {
        await withBalanceRefreshWindow {
            try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        }
    }
    func collectLimitedConcurrentIndexedResults<Item: Sendable, Value: Sendable>(
        from items: [Item], maxConcurrent: Int = 4, operation: @escaping @Sendable (Item) async -> (Int, Value?)
    ) async -> [Int: Value] {
        guard !items.isEmpty else { return [:] }
        let concurrencyLimit = max(1, min(maxConcurrent, items.count))
        return await withTaskGroup(of: (Int, Value?).self, returning: [Int: Value].self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<concurrencyLimit {
                guard let item = iterator.next() else { break }
                group.addTask {
                    await operation(item)
                }
            }
            var results: [Int: Value] = [:]
            while let (index, value) = await group.next() {
                if let value { results[index] = value }
                if let item = iterator.next() {
                    group.addTask {
                        await operation(item)
                    }
                }
            }
            return results
        }
    }
    func scheduleImportedWalletRefresh(_ createdWallets: [ImportedWallet]) {
        guard !createdWallets.isEmpty else {
            resetLargeMovementAlertBaseline()
            return
        }
        importRefreshTask?.cancel()
        importRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.withBalanceRefreshWindow {
                await self.refreshBalances()
                _ = await self.refreshLivePrices()
            }
            await MainActor.run {
                self.resetLargeMovementAlertBaseline()
                self.importRefreshTask = nil
            }
        }
    }
    func shouldRefreshChainBalances(now: Date = Date()) -> Bool {
        guard !isRefreshingChainBalances else { return false }
        guard let lastChainBalanceRefreshAt else { return true }
        return now.timeIntervalSince(lastChainBalanceRefreshAt) >= 30
    }
    #if DEBUG
        func logBalanceTelemetry(source: String, chainName: String, wallet: ImportedWallet, holdings: [Coin]) {
            let nonZeroAssets = holdings.reduce(into: 0) { partialResult, coin in
                if abs(coin.amount) > 0 { partialResult += 1 }
            }
            let totalUnits = holdings.reduce(0) { $0 + $1.amount }
            appendOperationalLog(
                .debug, category: "Balance Telemetry", message: "Balance updated", chainName: chainName, walletID: wallet.id,
                source: source, metadata: "non_zero_assets=\(nonZeroAssets), total_units=\(totalUnits)"
            )
        }
    #endif
}
enum PricingProvider: String, CaseIterable, Identifiable {
    case coinGecko = "CoinGecko"
    case coinPaprika = "CoinPaprika"
    case coinLore = "CoinLore"
    var id: String { rawValue }
}
enum FiatRateProvider: String, CaseIterable, Identifiable {
    case openER = "Open ER"
    case exchangeRateHost = "ExchangeRate.host"
    case frankfurter = "Frankfurter API"
    case fawazAhmed = "Fawaz Ahmed Currency API"
    var id: String { rawValue }
}
enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cny = "CNY"
    case inr = "INR"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case brl = "BRL"
    case sgd = "SGD"
    case aed = "AED"
    var id: String { rawValue }
    var iconName: String? {
        switch self {
        case .usd: return "fiaticon/usd"
        case .eur: return "fiaticon/eur"
        case .gbp: return "fiaticon/gbp"
        case .cny: return "fiaticon/cny"
        default: return nil
        }
    }
    var displayName: String {
        switch self {
        case .usd: return "US Dollar (USD)"
        case .eur: return "Euro (EUR)"
        case .gbp: return "British Pound (GBP)"
        case .jpy: return "Japanese Yen (JPY)"
        case .cny: return "Chinese Yuan (CNY)"
        case .inr: return "Indian Rupee (INR)"
        case .cad: return "Canadian Dollar (CAD)"
        case .aud: return "Australian Dollar (AUD)"
        case .chf: return "Swiss Franc (CHF)"
        case .brl: return "Brazilian Real (BRL)"
        case .sgd: return "Singapore Dollar (SGD)"
        case .aed: return "UAE Dirham (AED)"
        }
    }
}
