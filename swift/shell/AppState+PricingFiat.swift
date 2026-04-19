import Foundation
import SwiftUI
import os
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
                provider: pricingProvider.rawValue, coins: rustInputs, apiKey: coinGeckoAPIKey
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
        if didUpdatePrices { evaluatePriceAlerts() }
        return didUpdatePrices
    }
    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        if !force, selectedFiatCurrency == .usd { return }
        if !force, let lastFiatRatesRefreshAt, Date().timeIntervalSince(lastFiatRatesRefreshAt) < Self.fiatRatesRefreshInterval { return }
        await refreshFiatExchangeRates()
    }
    func refreshFiatExchangeRates() async {
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
            if fiatRatesFromUSD.isEmpty { fiatRatesFromUSD = [FiatCurrency.usd.rawValue: 1.0] } else { fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0 }
            fiatRatesRefreshError = localizedStoreFormat("%@ fiat exchange rates are unavailable. Using the last successful rates.", fiatRateProvider.rawValue)
        }}
    func activePriceKey(for coin: Coin) -> String { assetIdentityKey(for: coin) }
    var totalBalance: Double {
        portfolio.reduce(0) { $0 + currentValue(for: $1) }}
    var totalBalanceIfAvailable: Double? { sumLiveQuotedValues(for: portfolio) }
    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: String) {
        guard let walletIndex = wallets.firstIndex(where: { $0.id == walletID }) else { return }
        let wallet = wallets[walletIndex]
        wallets[walletIndex] = ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: wallet.holdings, includeInPortfolioTotal: isIncluded
        )
        resetLargeMovementAlertBaseline()
    }
    func hasWalletForChain(_ chainName: String) -> Bool {
        let eligibilityInputs: [WalletChainEligibilityInput] = wallets.map { wallet in
            let hasSeedPhrase: Bool = (storedSeedPhrase(for: wallet.id)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            let bitcoinAddressIsValid: Bool = wallet.bitcoinAddress.map { AddressValidation.isValid($0, kind: "bitcoin", networkMode: wallet.bitcoinNetworkMode.rawValue) } ?? false
            return WalletChainEligibilityInput(
                walletId: wallet.id, selectedChain: wallet.selectedChain, hasSeedPhrase: hasSeedPhrase, bitcoinAddress: wallet.bitcoinAddress, bitcoinAddressIsValid: bitcoinAddressIsValid, bitcoinXpub: wallet.bitcoinXpub, resolvedAddressForChain: resolvedAddress(for: wallet, chainName: chainName)
            )
        }
        return corePlanHasWalletForChain(chainName: chainName, wallets: eligibilityInputs)
    }
    func refreshChainBalances(includeHistoryRefreshes: Bool = true, historyRefreshInterval: TimeInterval = 120, forceChainRefresh: Bool = true) async {
        _ = forceChainRefresh  // Rust always fetches fresh data
        guard !isRefreshingChainBalances else { return }
        isRefreshingChainBalances = true
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        if includeHistoryRefreshes { await runHistoryRefreshes(for: refreshableChainIDs, interval: historyRefreshInterval) }}
    func withBalanceRefreshWindow(_ operation: () async -> Void) async {
        let previousState = allowsBalanceNetworkRefresh
        allowsBalanceNetworkRefresh = true
        defer { allowsBalanceNetworkRefresh = previousState }
        await operation()
    }
    func refreshWalletBalance(_ walletID: String) async {
        await withBalanceRefreshWindow {
            try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        }}
    func collectLimitedConcurrentIndexedResults<Item, Value>(
        from items: [Item], maxConcurrent: Int = 4, operation: @escaping (Item) async -> (Int, Value?)
    ) async -> [Int: Value] {
        guard !items.isEmpty else { return [:] }
        let concurrencyLimit = max(1, min(maxConcurrent, items.count))
        return await withTaskGroup(of: (Int, Value?).self, returning: [Int: Value].self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<concurrencyLimit {
                guard let item = iterator.next() else { break }
                group.addTask {
                    await operation(item)
                }}
            var results: [Int: Value] = [:]
            while let (index, value) = await group.next() {
                if let value { results[index] = value }
                if let item = iterator.next() {
                    group.addTask {
                        await operation(item)
                    }}}
            return results
        }}
    func scheduleImportedWalletRefresh(_ createdWallets: [ImportedWallet]) {
        guard !createdWallets.isEmpty else {
            resetLargeMovementAlertBaseline()
            return
        }
        let importedChains = Set(createdWallets.compactMap { WalletChainID($0.selectedChain) })
        importRefreshTask?.cancel()
        importRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.withBalanceRefreshWindow {
                await self.refreshImportedWalletBalances(forChains: Set(importedChains.map(\.displayName)))
                _ = await self.refreshLivePrices()
            }
            await MainActor.run {
                self.resetLargeMovementAlertBaseline()
                self.importRefreshTask = nil
            }}}
    func shouldRefreshChainBalances(now: Date = Date()) -> Bool {
        guard !isRefreshingChainBalances else { return false }
        guard let lastChainBalanceRefreshAt else { return true }
        return now.timeIntervalSince(lastChainBalanceRefreshAt) >= 30
    }
#if DEBUG
    func logBalanceTelemetry(source: String, chainName: String, wallet: ImportedWallet, holdings: [Coin]) {
        let nonZeroAssets = holdings.reduce(into: 0) { partialResult, coin in
            if abs(coin.amount) > 0 { partialResult += 1 }}
        let totalUnits = holdings.reduce(0) { $0 + $1.amount }
        balanceTelemetryLogger.debug(
            """
            balance_update source=\(source, privacy: .public) \
            chain=\(chainName, privacy: .public) \
            wallet_id=\(wallet.id, privacy: .public) \
            wallet_name=\(wallet.name, privacy: .public) \
            non_zero_assets=\(nonZeroAssets, privacy: .public) \
            total_units=\(totalUnits, privacy: .public)
            """
        )
        appendOperationalLog(
            .debug, category: "Balance Telemetry", message: "Balance updated", chainName: chainName, walletID: wallet.id, source: source, metadata: "non_zero_assets=\(nonZeroAssets), total_units=\(totalUnits)"
        )
    }
#endif
}
enum PricingProvider: String, CaseIterable, Identifiable {
    case coinGecko = "CoinGecko"
    case binance = "Binance Public API"
    case coinbaseExchange = "Coinbase Exchange API"
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
