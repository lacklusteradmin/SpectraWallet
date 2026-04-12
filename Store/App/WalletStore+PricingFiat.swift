import Foundation
import SwiftUI
import os

@MainActor
extension WalletStore {
    // MARK: - Pricing and Fiat Conversion
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
                WalletServiceBridge.PriceRequestCoinInput(
                    holdingKey: coin.holdingKey,
                    symbol: coin.symbol,
                    coinGeckoId: coin.coinGeckoID
                )
            }
            let fetchedPrices = try await WalletServiceBridge.shared.fetchPricesViaRust(
                provider: pricingProvider.rawValue,
                coins: rustInputs,
                apiKey: coinGeckoAPIKey
            )
            guard !fetchedPrices.isEmpty else {
                quoteRefreshError = localizedStoreFormat("%@ returned no supported asset quotes", pricingProvider.rawValue)
                return false
            }

            var updatedPrices = livePrices
            var sawMeaningfulPriceChange = false
            for (key, value) in fetchedPrices {
                if updatedPrices[key] != value {
                    updatedPrices[key] = value
                    sawMeaningfulPriceChange = true
                }
            }
            if sawMeaningfulPriceChange {
                livePrices = updatedPrices
            }
            quoteRefreshError = nil
            didUpdatePrices = sawMeaningfulPriceChange
        } catch {
            quoteRefreshError = localizedStoreFormat("%@ pricing unavailable", pricingProvider.rawValue)
        }

        if didUpdatePrices {
            evaluatePriceAlerts()
        }
        return didUpdatePrices
    }

    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        if !force, selectedFiatCurrency == .usd {
            return
        }
        if !force,
           let lastFiatRatesRefreshAt,
           Date().timeIntervalSince(lastFiatRatesRefreshAt) < Self.fiatRatesRefreshInterval {
            return
        }
        await refreshFiatExchangeRates()
    }

    func refreshFiatExchangeRates() async {
        do {
            var rates: [String: Double] = [FiatCurrency.usd.rawValue: 1.0]
            let fetchedRates = try await WalletServiceBridge.shared.fetchFiatRatesViaRust(
                provider: fiatRateProvider.rawValue,
                currencies: FiatCurrency.allCases.map(\.rawValue)
            )
            for currency in FiatCurrency.allCases where currency != .usd {
                if let rate = fetchedRates[currency.rawValue], rate > 0 {
                    rates[currency.rawValue] = rate
                } else if let existingRate = fiatRatesFromUSD[currency.rawValue], existingRate > 0 {
                    rates[currency.rawValue] = existingRate
                }
            }
            fiatRatesFromUSD = rates
            UserDefaults.standard.set(rates, forKey: Self.fiatRatesFromUSDDefaultsKey)
            fiatRatesRefreshError = nil
            lastFiatRatesRefreshAt = Date()
        } catch {
            if fiatRatesFromUSD.isEmpty {
                fiatRatesFromUSD = [FiatCurrency.usd.rawValue: 1.0]
            } else {
                fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
            }
            fiatRatesRefreshError = localizedStoreFormat("%@ fiat exchange rates are unavailable. Using the last successful rates.", fiatRateProvider.rawValue)
        }
    }
    
    func activePriceKey(for coin: Coin) -> String {
        assetIdentityKey(for: coin)
    }
    
    // Calculates the sum of all coins
    var totalBalance: Double {
        portfolio.reduce(0) { $0 + currentValue(for: $1) }
    }

    var totalBalanceIfAvailable: Double? {
        sumLiveQuotedValues(for: portfolio)
    }

    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: UUID) {
        guard let walletIndex = wallets.firstIndex(where: { $0.id == walletID }) else { return }
        let wallet = wallets[walletIndex]
        wallets[walletIndex] = ImportedWallet(
            id: wallet.id,
            name: wallet.name,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: wallet.holdings,
            includeInPortfolioTotal: isIncluded
        )
        resetLargeMovementAlertBaseline()
    }

    var hasDogecoinWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Dogecoin"
                && {
                    guard let address = wallet.dogecoinAddress else { return false }
                    return isValidDogecoinAddressForPolicy(address, networkMode: wallet.dogecoinNetworkMode)
                }()
        }
    }

    var hasEthereumWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Ethereum"
                && resolvedEthereumAddress(for: wallet) != nil
        }
    }

    var hasLitecoinWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Litecoin"
                && resolvedLitecoinAddress(for: wallet) != nil
        }
    }

    var hasBNBWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "BNB Chain"
                && resolvedEVMAddress(for: wallet, chainName: "BNB Chain") != nil
        }
    }

    var hasArbitrumWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Arbitrum"
                && resolvedEVMAddress(for: wallet, chainName: "Arbitrum") != nil
        }
    }

    var hasOptimismWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Optimism"
                && resolvedEVMAddress(for: wallet, chainName: "Optimism") != nil
        }
    }

    var hasAvalancheWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Avalanche"
                && resolvedEVMAddress(for: wallet, chainName: "Avalanche") != nil
        }
    }

    var hasMoneroWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Monero"
                && resolvedMoneroAddress(for: wallet) != nil
        }
    }

    var hasCardanoWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Cardano"
                && resolvedCardanoAddress(for: wallet) != nil
        }
    }

    var hasSuiWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Sui"
                && resolvedSuiAddress(for: wallet) != nil
        }
    }

    var hasBitcoinWallets: Bool {
        wallets.contains { wallet in
            guard wallet.selectedChain == "Bitcoin" else { return false }
            if let seedPhrase = storedSeedPhrase(for: wallet.id),
               !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if let address = wallet.bitcoinAddress,
               AddressValidation.isValidBitcoinAddress(address, networkMode: wallet.bitcoinNetworkMode) {
                return true
            }
            if let xpub = wallet.bitcoinXPub,
               (xpub.hasPrefix("xpub") || xpub.hasPrefix("ypub") || xpub.hasPrefix("zpub")) {
                return true
            }
            return false
        }
    }

    var hasBitcoinCashWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Bitcoin Cash"
                && resolvedBitcoinCashAddress(for: wallet) != nil
        }
    }

    var hasBitcoinSVWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Bitcoin SV"
                && resolvedBitcoinSVAddress(for: wallet) != nil
        }
    }


    // Core chain refresh — balance portion is now Rust-driven via BalanceRefreshEngine.
    // History refreshes remain Swift-driven via per-chain descriptors.
    func refreshChainBalances(
        includeHistoryRefreshes: Bool = true,
        historyRefreshInterval: TimeInterval = 120,
        forceChainRefresh: Bool = true
    ) async {
        _ = forceChainRefresh  // Rust always fetches fresh data
        guard !isRefreshingChainBalances else { return }
        isRefreshingChainBalances = true
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        // isRefreshingChainBalances is cleared by WalletBalanceObserver.onRefreshCycleComplete
        if includeHistoryRefreshes {
            await runHistoryRefreshes(for: refreshableChainIDs, interval: historyRefreshInterval)
        }
    }

    func withBalanceRefreshWindow(_ operation: () async -> Void) async {
        let previousState = allowsBalanceNetworkRefresh
        allowsBalanceNetworkRefresh = true
        defer { allowsBalanceNetworkRefresh = previousState }
        await operation()
    }

    func refreshWalletBalance(_ walletID: UUID) async {
        await withBalanceRefreshWindow {
            try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        }
    }

    func collectLimitedConcurrentIndexedResults<Item, Value>(
        from items: [Item],
        maxConcurrent: Int = 4,
        operation: @escaping (Item) async -> (Int, Value?)
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
                if let value {
                    results[index] = value
                }

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
            }
        }
    }

    func shouldRefreshChainBalances(now: Date = Date()) -> Bool {
        guard !isRefreshingChainBalances else { return false }
        guard let lastChainBalanceRefreshAt else { return true }
        return now.timeIntervalSince(lastChainBalanceRefreshAt) >= 30
    }

#if DEBUG
    func logBalanceTelemetry(
        source: String,
        chainName: String,
        wallet: ImportedWallet,
        holdings: [Coin]
    ) {
        let nonZeroAssets = holdings.reduce(into: 0) { partialResult, coin in
            if abs(coin.amount) > 0 {
                partialResult += 1
            }
        }
        let totalUnits = holdings.reduce(0) { $0 + $1.amount }
        balanceTelemetryLogger.debug(
            """
            balance_update source=\(source, privacy: .public) \
            chain=\(chainName, privacy: .public) \
            wallet_id=\(wallet.id.uuidString, privacy: .public) \
            wallet_name=\(wallet.name, privacy: .public) \
            non_zero_assets=\(nonZeroAssets, privacy: .public) \
            total_units=\(totalUnits, privacy: .public)
            """
        )
        appendOperationalLog(
            .debug,
            category: "Balance Telemetry",
            message: "Balance updated",
            chainName: chainName,
            walletID: wallet.id,
            source: source,
            metadata: "non_zero_assets=\(nonZeroAssets), total_units=\(totalUnits)"
        )
    }
#endif
    
    // BTC balance refresh pipeline with seed-based primary source and safe fallbacks.
}
