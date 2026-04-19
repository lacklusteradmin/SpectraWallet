import Foundation
import SwiftUI
import Combine
extension AppState {
    static let pinnedDashboardAssetSymbolsDefaultsKey = "dashboardPinnedAssetSymbols"
    private var defaultPinnedDashboardAssetSymbols: [String] { ["BTC", "ETH", "USDT", "USDC"] }
    private static let dashboardPinPrototypeSpecs: [(String, String, String, String, String, String, String?, Double, Double, String, Color)] = [
        ("Bitcoin", "BTC", "1", "bitcoin", "Bitcoin", "Native", nil, 0, 0, "B", .orange),
        ("Bitcoin Cash", "BCH", "1831", "bitcoin-cash", "Bitcoin Cash", "Native", nil, 0, 0, "BC", .orange),
        ("Bitcoin SV", "BSV", "3602", "bitcoin-cash-sv", "Bitcoin SV", "Native", nil, 0, 0, "BS", .orange),
        ("Litecoin", "LTC", "2", "litecoin", "Litecoin", "Native", nil, 0, 0, "L", .gray),
        ("Dogecoin", "DOGE", "74", "dogecoin", "Dogecoin", "Native", nil, 0, 0, "D", .brown),
        ("Ethereum", "ETH", "1027", "ethereum", "Ethereum", "Native", nil, 0, 0, "E", .blue),
        ("Ethereum Classic", "ETC", "1321", "ethereum-classic", "Ethereum Classic", "Native", nil, 0, 0, "EC", .green),
        ("Arbitrum", "ARB", "0", "arbitrum", "Arbitrum", "Native", nil, 0, 0, "AR", .cyan),
        ("Optimism", "OP", "0", "optimism", "Optimism", "Native", nil, 0, 0, "OP", .red),
        ("BNB Chain", "BNB", "1839", "binancecoin", "BNB Chain", "Native", nil, 0, 0, "BN", .yellow),
        ("Avalanche", "AVAX", "5805", "avalanche-2", "Avalanche", "Native", nil, 0, 0, "AV", .red),
        ("Hyperliquid", "HYPE", "0", "", "Hyperliquid", "Native", nil, 0, 0, "HY", .mint),
        ("Solana", "SOL", "5426", "solana", "Solana", "Native", nil, 0, 0, "S", .purple),
        ("Cardano", "ADA", "2010", "cardano", "Cardano", "Native", nil, 0, 0, "A", .blue),
        ("Tron", "TRX", "1958", "tron", "Tron", "Native", nil, 0, 0, "T", .red),
        ("XRP Ledger", "XRP", "52", "ripple", "XRP Ledger", "Native", nil, 0, 0, "X", .cyan),
        ("Monero", "XMR", "328", "monero", "Monero", "Native", nil, 0, 0, "M", .orange),
        ("Sui", "SUI", "20947", "sui", "Sui", "Native", nil, 0, 0, "S", .mint),
        ("Aptos", "APT", "21794", "aptos", "Aptos", "Native", nil, 0, 0, "AP", .cyan),
        ("Internet Computer", "ICP", "2416", "internet-computer", "Internet Computer", "Native", nil, 0, 0, "IC", .indigo),
        ("NEAR Protocol", "NEAR", "6535", "near", "NEAR", "Native", nil, 0, 0, "N", .indigo),
        ("Polkadot", "DOT", "6636", "polkadot", "Polkadot", "Native", nil, 0, 0, "P", .pink),
        ("Stellar", "XLM", "512", "stellar", "Stellar", "Native", nil, 0, 0, "XL", .teal),
        ("Tether USD", "USDT", "825", "tether", "Ethereum", "ERC-20", "0xdAC17F958D2ee523a2206206994597C13D831ec7", 0, 1, "T", .green),
        ("USD Coin", "USDC", "3408", "usd-coin", "Ethereum", "ERC-20", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 0, 1, "U", .blue)
    ]
    private var dashboardPinPrototypes: [Coin] {
        Self.dashboardPinPrototypeSpecs.map { spec in
            Coin.makeCustom(name: spec.0, symbol: spec.1, marketDataId: spec.2, coinGeckoId: spec.3, chainName: spec.4, tokenStandard: spec.5, contractAddress: spec.6, amount: spec.7, priceUsd: spec.8, mark: spec.9, color: spec.10)
        }
    }
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
        return order.compactMap { grouped[$0] }}
    var availableDashboardPinOptions: [DashboardPinOption] { cachedAvailableDashboardPinOptions }
    func isDashboardAssetPinned(_ symbol: String) -> Bool { pinnedDashboardAssetSymbols.contains(symbol.uppercased()) }
    func setDashboardAssetPinned(_ isPinned: Bool, symbol: String) {
        let normalized = symbol.uppercased()
        var symbols = pinnedDashboardAssetSymbols
        if isPinned {
            if !symbols.contains(normalized) { symbols.append(normalized) }
        } else {
            symbols.removeAll { $0 == normalized }}
        cachedPinnedDashboardAssetSymbols = symbols
        persistAppSettings()
        rebuildDashboardDerivedState()
    }
    func resetPinnedDashboardAssets() {
        cachedPinnedDashboardAssetSymbols = []
        persistAppSettings()
        rebuildDashboardDerivedState()
    }
    private func dashboardAssetGroupingKey(for coin: Coin) -> String {
        formattingDashboardAssetGroupingKey(
            chainIdentity: runtimeChainIdentity(for: coin.chainName),
            coinGeckoId: coin.coinGeckoId,
            symbol: coin.symbol
        )
    }
    private func prototypeCoinForTrackedEntry(_ entry: TokenPreferenceEntry) -> Coin {
        let price: Double = formattingStablecoinFallbackPriceUsd(symbol: entry.symbol)
        let contractAddress: String? = entry.contractAddress
        let mark: String = Coin.displayMark(for: entry.symbol)
        let name: String = entry.name
        let symbol: String = entry.symbol
        let marketDataIdValue: String = entry.marketDataId
        let coinGeckoIdValue: String = entry.coinGeckoId
        let chainName: String = entry.chain.rawValue
        let tokenStandard: String = entry.tokenStandard
        var coin = CoreCoin(id: UUID().uuidString, name: name, symbol: symbol, marketDataId: marketDataIdValue, coinGeckoId: coinGeckoIdValue, chainName: chainName, tokenStandard: tokenStandard, contractAddress: contractAddress, amount: 0, priceUsd: price, mark: mark)
        coin.color = Coin.displayColor(for: entry.symbol)
        return coin
    }
    private func dashboardPinnedAssetPrototype(symbol: String) -> Coin? {
        let normalizedSymbol = symbol.uppercased()
        if let existing = cachedIncludedPortfolioHoldingsBySymbol[normalizedSymbol]?.first {
            let existingColor = existing.color
            var coin = CoreCoin(
                id: UUID().uuidString,
                name: existing.name,
                symbol: existing.symbol,
                marketDataId: existing.marketDataId,
                coinGeckoId: existing.coinGeckoId,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: 0 as Double,
                priceUsd: existing.priceUsd,
                mark: existing.mark
            )
            coin.color = existingColor
            return coin
        }
        if let trackedEntry = cachedResolvedTokenPreferencesBySymbol[normalizedSymbol]?.first {
            return prototypeCoinForTrackedEntry(trackedEntry)
        }
        return dashboardPinPrototypes.first(where: { $0.symbol.uppercased() == normalizedSymbol })
    }
    var dashboardAssetGroups: [DashboardAssetGroup] { cachedDashboardAssetGroups }
    func dashboardSupportedTokenEntries(symbol: String) -> [TokenPreferenceEntry] { cachedDashboardSupportedTokenEntriesBySymbol[symbol.uppercased()] ?? [] }
    func rebuildDashboardDerivedState() { batchCacheUpdates { _rebuildDashboardDerivedStateBody() } }
    private func _rebuildDashboardDerivedStateBody() {
        let includedHoldings = cachedIncludedPortfolioHoldings
        let holdingsBySymbol = cachedIncludedPortfolioHoldingsBySymbol
        let trackedEntriesBySymbol = cachedResolvedTokenPreferencesBySymbol
        let prototypeBySymbol = Dictionary(uniqueKeysWithValues: dashboardPinPrototypes.map { ($0.symbol.uppercased(), $0) })
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
                    for: symbol, portfolioCoins: holdingsBySymbol[symbol] ?? [], trackedEntries: trackedEntriesBySymbol[symbol] ?? [], prototype: prototypeBySymbol[symbol]
                ).map { (symbol, $0) }}
        )
        cachedDashboardPinOptionBySymbol = optionBySymbol
        cachedAvailableDashboardPinOptions = availableSymbols.compactMap { optionBySymbol[$0] }
        cachedDashboardRelevantPriceKeys = Set(
            includedHoldings.filter(isPricedAsset).map(assetIdentityKey)
        )
        cachedDashboardSupportedTokenEntriesBySymbol = Dictionary(
            uniqueKeysWithValues: trackedEntriesBySymbol.map { symbol, entries in
                (symbol, corePlanDashboardSupportedTokenEntries(entries: entries))
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
                let normalizedContract = normalizeDashboardContractAddress(
                    contractAddress: coin.contractAddress, chainName: coin.chainName, tokenStandard: coin.tokenStandard
                ) ?? "native"
                let chainKey = "\(runtimeChainIdentity(for: coin.chainName).lowercased())|\(coin.tokenStandard.lowercased())|\(normalizedContract)"
                if let existing = chainGrouped[chainKey] {
                    let existingColor = existing.color
                    var merged = CoreCoin(
                        id: existing.id,
                        name: existing.name,
                        symbol: existing.symbol,
                        marketDataId: existing.marketDataId,
                        coinGeckoId: existing.coinGeckoId,
                        chainName: existing.chainName,
                        tokenStandard: existing.tokenStandard,
                        contractAddress: existing.contractAddress,
                        amount: existing.amount + coin.amount,
                        priceUsd: coin.priceUsd,
                        mark: existing.mark
                    )
                    merged.color = existingColor
                    chainGrouped[chainKey] = merged
                } else { chainGrouped[chainKey] = coin }}
            let chainEntries = chainGrouped.values.map { DashboardAssetChainEntry(coin: $0, valueUSD: currentValueIfAvailable(for: $0)) }
                .sorted {
                    let lhsValue = $0.valueUSD ?? -1
                    let rhsValue = $1.valueUSD ?? -1
                    if abs(lhsValue - rhsValue) > 0.000001 { return lhsValue > rhsValue }
                    return $0.coin.chainName.localizedCaseInsensitiveCompare($1.coin.chainName) == .orderedAscending
                }
            guard let representativeCoin = chainEntries.first?.coin else { return nil }
            let totalAmount = coins.reduce(0) { $0 + $1.amount }
            let totalValueUSD: Double? = chainEntries.allSatisfy({ $0.valueUSD != nil }) ? chainEntries.compactMap(\.valueUSD).reduce(0, +) : nil
            let isPinned = storedPinnedSymbols.contains(representativeCoin.symbol.uppercased())
            return DashboardAssetGroup(
                id: key, representativeCoin: representativeCoin, totalAmount: totalAmount, totalValueUSD: totalValueUSD, chainEntries: chainEntries, isPinned: isPinned
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
                    id: "pinned:\(symbol.lowercased())", representativeCoin: prototype, totalAmount: 0, totalValueUSD: 0, chainEntries: [], isPinned: true
                )
            )
        }
        let pinnedOrder = Dictionary(uniqueKeysWithValues: storedPinnedSymbols.enumerated().map { ($1, $0) })
        cachedDashboardAssetGroups = groups.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.isPinned, rhs.isPinned { return (pinnedOrder[lhs.symbol.uppercased()] ?? Int.max) < (pinnedOrder[rhs.symbol.uppercased()] ?? Int.max) }
            let lhsValue = lhs.totalValueUSD ?? -1
            let rhsValue = rhs.totalValueUSD ?? -1
            if abs(lhsValue - rhsValue) > 0.000001 { return lhsValue > rhsValue }
            return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
        }}
    private func dashboardPinOptionUncached(
        for symbol: String, portfolioCoins: [Coin], trackedEntries: [TokenPreferenceEntry], prototype: Coin? ) -> DashboardPinOption? {
        let normalizedSymbol = symbol.uppercased()
        if let representativeCoin = portfolioCoins.first {
            let chainNames = Array(Set(portfolioCoins.map(\.chainName) + trackedEntries.map(\.chain.rawValue))).sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol, name: representativeCoin.name, subtitle: chainNames.isEmpty ? representativeCoin.chainName : chainNames.joined(separator: ", "), assetIdentifier: representativeCoin.iconIdentifier, mark: representativeCoin.mark
            )
        }
        if let representativeEntry = trackedEntries.first {
            let chainNames = Array(Set(trackedEntries.map(\.chain.rawValue))).sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol, name: representativeEntry.name, subtitle: chainNames.joined(separator: ", "), assetIdentifier: Coin.iconIdentifier(
                    symbol: representativeEntry.symbol, chainName: representativeEntry.chain.rawValue, contractAddress: representativeEntry.contractAddress, tokenStandard: representativeEntry.tokenStandard
                ), mark: Coin.displayMark(for: representativeEntry.symbol)
            )
        }
        if let prototype {
            return DashboardPinOption(
                symbol: normalizedSymbol, name: prototype.name, subtitle: prototype.chainName, assetIdentifier: prototype.iconIdentifier, mark: prototype.mark
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
                    title: localizedStoreString("Pricing Notice"), message: quoteRefreshError, severity: .warning, systemImage: "dollarsign.circle"
                )
            )
        }
        if let fiatRatesRefreshError = fiatRatesRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines), !fiatRatesRefreshError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Fiat Rates Degraded Mode"), message: fiatRatesRefreshError, severity: .warning, systemImage: "antenna.radiowaves.left.and.right.slash"
                )
            )
        }
        notices.append(contentsOf: chainDegradedBanners.map { banner in
            AppNoticeItem(
                title: localizedStoreFormat("%@ Degraded Mode", banner.chainName), message: banner.message, severity: .warning, systemImage: "antenna.radiowaves.left.and.right.slash", timestamp: banner.lastGoodSyncAt
            )
        })
        if let importError = importError?.trimmingCharacters(in: .whitespacesAndNewlines), !importError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.walletImportErrorTitle, message: importError, severity: .error, systemImage: "square.and.arrow.down.badge.exclamationmark"
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
                    title: commonCopy.securityNoticeTitle, message: appLockError, severity: .error, systemImage: "lock.trianglebadge.exclamationmark"
                )
            )
        }
        if let tronLastSendErrorDetails = tronLastSendErrorDetails?.trimmingCharacters(in: .whitespacesAndNewlines), !tronLastSendErrorDetails.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.tronSendDiagnosticTitle, message: tronLastSendErrorDetails, severity: .error, systemImage: "bolt.trianglebadge.exclamationmark", timestamp: tronLastSendErrorAt
                )
            )
        }
        return notices
    }
}
