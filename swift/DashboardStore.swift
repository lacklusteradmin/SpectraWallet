import Foundation
import SwiftUI
extension AppState {
    static let pinnedDashboardAssetSymbolsDefaultsKey = "dashboardPinnedAssetSymbols"
    private var defaultPinnedDashboardAssetSymbols: [String] { ["BTC", "ETH", "USDT", "USDC"] }
    private static let dashboardPinPrototypes: [Coin] = {
        let allChains = listAllChains()
        let chainNameById = Dictionary(uniqueKeysWithValues: allChains.map { ($0.id, $0.name) })
        var coins = allChains
            .filter { !$0.nativeAssetName.isEmpty && $0.category != "testnet" }
            .map { chain in
                Coin.makeCustom(
                    name: chain.nativeAssetName, symbol: chain.gasTokenSymbol,
                    coinGeckoId: chain.nativeCoingeckoId, chainName: chain.name,
                    tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 0)
            }
        for token in listTokens(chainId: "") where token.tags.contains("stablecoin") && token.enabled {
            let chainName = chainNameById[token.chain] ?? token.chain
            coins.append(Coin.makeCustom(
                name: token.name, symbol: token.symbol,
                coinGeckoId: token.coingeckoId, chainName: chainName,
                tokenStandard: token.tokenStandard,
                contractAddress: token.contract.isEmpty ? nil : token.contract,
                amount: 0, priceUsd: 0))
        }
        return coins
    }()
    private var dashboardPinPrototypes: [Coin] { Self.dashboardPinPrototypes }
    var pinnedDashboardAssetSymbols: [String] {
        cachedPinnedDashboardAssetSymbols.isEmpty
            ? defaultPinnedDashboardAssetSymbols
            : cachedPinnedDashboardAssetSymbols
    }
    var dashboardPinnedAssetPricingPrototypes: [Coin] {
        var grouped: [String: Coin] = [:]
        var order: [String] = []
        for symbol in pinnedDashboardAssetSymbols {
            guard let prototype = dashboardPinnedAssetPrototype(symbol: symbol) else { continue }
            guard grouped[prototype.holdingKey] == nil else { continue }
            grouped[prototype.holdingKey] = prototype
            order.append(prototype.holdingKey)
        }
        return order.compactMap { grouped[$0] }
    }
    var availableDashboardPinOptions: [DashboardPinOption] { cachedAvailableDashboardPinOptions }
    func isDashboardAssetPinned(_ symbol: String) -> Bool { pinnedDashboardAssetSymbols.contains(symbol.uppercased()) }
    func setDashboardAssetPinned(_ isPinned: Bool, symbol: String) {
        let normalized = symbol.uppercased()
        var symbols = pinnedDashboardAssetSymbols
        if isPinned {
            if !symbols.contains(normalized) { symbols.append(normalized) }
        } else {
            symbols.removeAll { $0 == normalized }
        }
        setPinnedDashboardAssets(symbols)
    }
    func resetPinnedDashboardAssets() {
        setPinnedDashboardAssets([])
    }
    private func dashboardAssetGroupingKey(for coin: Coin) -> String {
        CachedCoreHelpers.dashboardAssetGroupingKey(
            chainIdentity: runtimeChainIdentity(for: coin.chainName),
            coinGeckoId: coin.coinGeckoId,
            symbol: coin.symbol
        )
    }
    private func prototypeCoinForTrackedEntry(_ entry: TokenPreferenceEntry) -> Coin {
        let price: Double = CachedCoreHelpers.stablecoinFallbackPriceUsd(symbol: entry.symbol)
        return CoreCoin(
            id: UUID().uuidString, name: entry.name, symbol: entry.symbol, coinGeckoId: entry.coinGeckoId,
            chainName: entry.chain.rawValue, tokenStandard: entry.tokenStandard, contractAddress: entry.contractAddress,
            amount: 0, priceUsd: price)
    }
    private func dashboardPinnedAssetPrototype(symbol: String) -> Coin? {
        let normalizedSymbol = symbol.uppercased()
        if let existing = cachedIncludedPortfolioHoldingsBySymbol[normalizedSymbol]?.first {
            return CoreCoin(
                id: UUID().uuidString,
                name: existing.name,
                symbol: existing.symbol,
                coinGeckoId: existing.coinGeckoId,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: 0,
                priceUsd: existing.priceUsd
            )
        }
        if let trackedEntry = cachedResolvedTokenPreferencesBySymbol[normalizedSymbol]?.first {
            return prototypeCoinForTrackedEntry(trackedEntry)
        }
        return dashboardPinPrototypes.first(where: { $0.symbol.uppercased() == normalizedSymbol })
    }
    var dashboardAssetGroups: [DashboardAssetGroup] { cachedDashboardAssetGroups }
    func dashboardSupportedTokenEntries(symbol: String) -> [TokenPreferenceEntry] {
        cachedDashboardSupportedTokenEntriesBySymbol[symbol.uppercased()] ?? []
    }
    func rebuildDashboardDerivedState() { batchCacheUpdates { _rebuildDashboardDerivedStateBody() } }
    private func _rebuildDashboardDerivedStateBody() {
        let includedHoldings = cachedIncludedPortfolioHoldings
        let holdingsBySymbol = cachedIncludedPortfolioHoldingsBySymbol
        let trackedEntriesBySymbol = cachedResolvedTokenPreferencesBySymbol
        let prototypeBySymbol = Dictionary(
            dashboardPinPrototypes.map { ($0.symbol.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let storedPinnedSymbols = pinnedDashboardAssetSymbols
        let availableSymbols = Array(
            Set(
                defaultPinnedDashboardAssetSymbols
                    + dashboardPinPrototypes.map { $0.symbol.uppercased() }
                    + Array(holdingsBySymbol.keys)
                    + Array(trackedEntriesBySymbol.keys)
            )
        ).sorted()
        let optionBySymbol = Dictionary(
            uniqueKeysWithValues: availableSymbols.compactMap { symbol in
                dashboardPinOptionUncached(
                    for: symbol, portfolioCoins: holdingsBySymbol[symbol] ?? [], trackedEntries: trackedEntriesBySymbol[symbol] ?? [],
                    prototype: prototypeBySymbol[symbol]
                ).map { (symbol, $0) }
            }
        )
        cachedDashboardPinOptionBySymbol = optionBySymbol
        cachedAvailableDashboardPinOptions = availableSymbols.compactMap { optionBySymbol[$0] }
        cachedDashboardSupportedTokenEntriesBySymbol = Dictionary(
            uniqueKeysWithValues: trackedEntriesBySymbol.map { symbol, entries in
                (symbol, coreDashboardSupportedTokenEntries(entries: entries))
            }
        )
        let positiveCoins = includedHoldings.filter { $0.amount > 0 }
        var grouped: [String: [Coin]] = [:]
        var order: [String] = []
        for coin in positiveCoins {
            let key = dashboardAssetGroupingKey(for: coin)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(coin)
        }
        var groups: [DashboardAssetGroup] = order.compactMap { key -> DashboardAssetGroup? in
            guard let coins = grouped[key], !coins.isEmpty else { return nil }
            var chainGrouped: [String: Coin] = [:]
            for coin in coins {
                let normalizedContract =
                    normalizeDashboardContractAddress(
                        contractAddress: coin.contractAddress, chainName: coin.chainName, tokenStandard: coin.tokenStandard
                    ) ?? "native"
                let chainKey =
                    "\(runtimeChainIdentity(for: coin.chainName).lowercased())|\(coin.tokenStandard.lowercased())|\(normalizedContract)"
                if let existing = chainGrouped[chainKey] {
                    chainGrouped[chainKey] = CoreCoin(
                        id: existing.id,
                        name: existing.name,
                        symbol: existing.symbol,
                        coinGeckoId: existing.coinGeckoId,
                        chainName: existing.chainName,
                        tokenStandard: existing.tokenStandard,
                        contractAddress: existing.contractAddress,
                        amount: existing.amount + coin.amount,
                        priceUsd: coin.priceUsd
                    )
                } else {
                    chainGrouped[chainKey] = coin
                }
            }
            let chainEntries = chainGrouped.values.map { DashboardAssetChainEntry(coin: $0, valueUSD: currentValueIfAvailable(for: $0)) }
                .sorted {
                    let lhsValue = $0.valueUSD ?? -1
                    let rhsValue = $1.valueUSD ?? -1
                    if abs(lhsValue - rhsValue) > 0.000001 { return lhsValue > rhsValue }
                    return $0.coin.chainName.localizedCaseInsensitiveCompare($1.coin.chainName) == .orderedAscending
                }
            guard let representativeCoin = chainEntries.first?.coin else { return nil }
            let totalAmount = coins.reduce(0) { $0 + $1.amount }
            let totalValueUSD: Double? =
                chainEntries.allSatisfy({ $0.valueUSD != nil }) ? chainEntries.compactMap(\.valueUSD).reduce(0, +) : nil
            let isPinned = storedPinnedSymbols.contains(representativeCoin.symbol.uppercased())
            return DashboardAssetGroup(
                id: key, representativeCoin: representativeCoin, totalAmount: totalAmount, totalValueUSD: totalValueUSD,
                chainEntries: chainEntries, isPinned: isPinned
            )
        }
        let existingPinnedSymbols = Set(groups.map { $0.symbol.uppercased() })
        for symbol in storedPinnedSymbols where !existingPinnedSymbols.contains(symbol) {
            var prototype: Coin? = holdingsBySymbol[symbol]?.first
            if prototype == nil, let entry = trackedEntriesBySymbol[symbol]?.first {
                prototype = prototypeCoinForTrackedEntry(entry)
            }
            if prototype == nil { prototype = prototypeBySymbol[symbol] }
            guard let prototype else { continue }
            groups.append(
                DashboardAssetGroup(
                    id: "pinned:\(symbol.lowercased())", representativeCoin: prototype, totalAmount: 0, totalValueUSD: 0, chainEntries: [],
                    isPinned: true
                )
            )
        }
        let pinnedOrder = Dictionary(uniqueKeysWithValues: storedPinnedSymbols.enumerated().map { ($1, $0) })
        cachedDashboardAssetGroups = groups.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.isPinned, rhs.isPinned {
                return (pinnedOrder[lhs.symbol.uppercased()] ?? Int.max) < (pinnedOrder[rhs.symbol.uppercased()] ?? Int.max)
            }
            let lhsValue = lhs.totalValueUSD ?? -1
            let rhsValue = rhs.totalValueUSD ?? -1
            if abs(lhsValue - rhsValue) > 0.000001 { return lhsValue > rhsValue }
            return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
        }
    }
    private func dashboardPinOptionUncached(
        for symbol: String, portfolioCoins: [Coin], trackedEntries: [TokenPreferenceEntry], prototype: Coin?
    ) -> DashboardPinOption? {
        let normalizedSymbol = symbol.uppercased()
        if let representativeCoin = portfolioCoins.first {
            let chainNames = Array(Set(portfolioCoins.map(\.chainName) + trackedEntries.map(\.chain.rawValue))).sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol, name: representativeCoin.name,
                subtitle: chainNames.isEmpty ? representativeCoin.chainName : chainNames.joined(separator: ", "),
                assetIdentifier: representativeCoin.iconIdentifier
            )
        }
        if let representativeEntry = trackedEntries.first {
            let chainNames = Array(Set(trackedEntries.map(\.chain.rawValue))).sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol, name: representativeEntry.name, subtitle: chainNames.joined(separator: ", "),
                assetIdentifier: Coin.iconIdentifier(
                    symbol: representativeEntry.symbol, chainName: representativeEntry.chain.rawValue,
                    contractAddress: representativeEntry.contractAddress, tokenStandard: representativeEntry.tokenStandard
                )
            )
        }
        if let prototype {
            return DashboardPinOption(
                symbol: normalizedSymbol, name: prototype.name, subtitle: prototype.chainName, assetIdentifier: prototype.iconIdentifier
            )
        }
        return nil
    }
    var appNoticeItems: [AppNoticeItem] {
        let commonCopy = CommonLocalizationContent.current
        var notices: [AppNoticeItem] = []
        if let quoteRefreshError = quoteRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines), !quoteRefreshError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Pricing Notice"), message: quoteRefreshError, severity: .warning,
                    systemImage: "dollarsign.circle"
                )
            )
        }
        if let fiatRatesRefreshError = fiatRatesRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines),
            !fiatRatesRefreshError.isEmpty
        {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Fiat Rates Degraded Mode"), message: fiatRatesRefreshError, severity: .warning,
                    systemImage: "antenna.radiowaves.left.and.right.slash"
                )
            )
        }
        notices.append(
            contentsOf: chainDegradedBanners.map { banner in
                AppNoticeItem(
                    title: localizedStoreFormat("%@ Degraded Mode", banner.chainName), message: banner.message, severity: .warning,
                    systemImage: "antenna.radiowaves.left.and.right.slash", timestamp: banner.lastGoodSyncAt
                )
            })
        if let importError = importError?.trimmingCharacters(in: .whitespacesAndNewlines), !importError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.walletImportErrorTitle, message: importError, severity: .error,
                    systemImage: "square.and.arrow.down.badge.exclamationmark"
                )
            )
        }
        if let sendError = sendError?.trimmingCharacters(in: .whitespacesAndNewlines), !sendError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.sendErrorTitle, message: sendError, severity: .error, systemImage: "paperplane.circle"
                )
            )
        }
        if let appLockError = appLockError?.trimmingCharacters(in: .whitespacesAndNewlines), !appLockError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.securityNoticeTitle, message: appLockError, severity: .error,
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
            )
        }
        if let tronLastSendErrorDetails = tronLastSendErrorDetails?.trimmingCharacters(in: .whitespacesAndNewlines),
            !tronLastSendErrorDetails.isEmpty
        {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.tronSendDiagnosticTitle, message: tronLastSendErrorDetails, severity: .error,
                    systemImage: "bolt.trianglebadge.exclamationmark", timestamp: tronLastSendErrorAt
                )
            )
        }
        return notices
    }
}
