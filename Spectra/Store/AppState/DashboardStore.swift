import Foundation
import SwiftUI
import Combine

extension WalletStore {
    var cachedPinnedDashboardAssetSymbols: [String] {
        get { dashboardState.pinnedAssetSymbols }
        set { dashboardState.pinnedAssetSymbols = newValue }
    }

    var cachedDashboardPinOptionBySymbol: [String: DashboardPinOption] {
        get { dashboardState.pinOptionBySymbol }
        set { dashboardState.pinOptionBySymbol = newValue }
    }

    var cachedAvailableDashboardPinOptions: [DashboardPinOption] {
        get { dashboardState.availablePinOptions }
        set { dashboardState.availablePinOptions = newValue }
    }

    var cachedDashboardAssetGroups: [DashboardAssetGroup] {
        get { dashboardState.assetGroups }
        set { dashboardState.assetGroups = newValue }
    }

    var cachedDashboardRelevantPriceKeys: Set<String> {
        get { dashboardState.relevantPriceKeys }
        set { dashboardState.relevantPriceKeys = newValue }
    }

    var cachedDashboardSupportedTokenEntriesBySymbol: [String: [TokenPreferenceEntry]] {
        get { dashboardState.supportedTokenEntriesBySymbol }
        set { dashboardState.supportedTokenEntriesBySymbol = newValue }
    }

    fileprivate static let pinnedDashboardAssetSymbolsDefaultsKey = "dashboardPinnedAssetSymbols"

    private var defaultPinnedDashboardAssetSymbols: [String] {
        ["BTC", "ETH", "USDT", "USDC"]
    }

    private var dashboardPinPrototypes: [Coin] {
        [
            Coin(name: "Bitcoin", symbol: "BTC", marketDataID: "1", coinGeckoID: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "B", color: .orange),
            Coin(name: "Bitcoin Cash", symbol: "BCH", marketDataID: "1831", coinGeckoID: "bitcoin-cash", chainName: "Bitcoin Cash", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "BC", color: .orange),
            Coin(name: "Bitcoin SV", symbol: "BSV", marketDataID: "3602", coinGeckoID: "bitcoin-cash-sv", chainName: "Bitcoin SV", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "BS", color: .orange),
            Coin(name: "Litecoin", symbol: "LTC", marketDataID: "2", coinGeckoID: "litecoin", chainName: "Litecoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "L", color: .gray),
            Coin(name: "Dogecoin", symbol: "DOGE", marketDataID: "74", coinGeckoID: "dogecoin", chainName: "Dogecoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "D", color: .brown),
            Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Ethereum", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "E", color: .blue),
            Coin(name: "Ethereum Classic", symbol: "ETC", marketDataID: "1321", coinGeckoID: "ethereum-classic", chainName: "Ethereum Classic", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "EC", color: .green),
            Coin(name: "Arbitrum", symbol: "ARB", marketDataID: "0", coinGeckoID: "arbitrum", chainName: "Arbitrum", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "AR", color: .cyan),
            Coin(name: "Optimism", symbol: "OP", marketDataID: "0", coinGeckoID: "optimism", chainName: "Optimism", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "OP", color: .red),
            Coin(name: "BNB Chain", symbol: "BNB", marketDataID: "1839", coinGeckoID: "binancecoin", chainName: "BNB Chain", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "BN", color: .yellow),
            Coin(name: "Avalanche", symbol: "AVAX", marketDataID: "5805", coinGeckoID: "avalanche-2", chainName: "Avalanche", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "AV", color: .red),
            Coin(name: "Hyperliquid", symbol: "HYPE", marketDataID: "0", coinGeckoID: "", chainName: "Hyperliquid", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "HY", color: .mint),
            Coin(name: "Solana", symbol: "SOL", marketDataID: "5426", coinGeckoID: "solana", chainName: "Solana", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "S", color: .purple),
            Coin(name: "Cardano", symbol: "ADA", marketDataID: "2010", coinGeckoID: "cardano", chainName: "Cardano", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "A", color: .blue),
            Coin(name: "Tron", symbol: "TRX", marketDataID: "1958", coinGeckoID: "tron", chainName: "Tron", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "T", color: .red),
            Coin(name: "XRP Ledger", symbol: "XRP", marketDataID: "52", coinGeckoID: "ripple", chainName: "XRP Ledger", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "X", color: .cyan),
            Coin(name: "Monero", symbol: "XMR", marketDataID: "328", coinGeckoID: "monero", chainName: "Monero", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "M", color: .orange),
            Coin(name: "Sui", symbol: "SUI", marketDataID: "20947", coinGeckoID: "sui", chainName: "Sui", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "S", color: .mint),
            Coin(name: "Aptos", symbol: "APT", marketDataID: "21794", coinGeckoID: "aptos", chainName: "Aptos", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "AP", color: .cyan),
            Coin(name: "Internet Computer", symbol: "ICP", marketDataID: "2416", coinGeckoID: "internet-computer", chainName: "Internet Computer", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "IC", color: .indigo),
            Coin(name: "NEAR Protocol", symbol: "NEAR", marketDataID: "6535", coinGeckoID: "near", chainName: "NEAR", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "N", color: .indigo),
            Coin(name: "Polkadot", symbol: "DOT", marketDataID: "6636", coinGeckoID: "polkadot", chainName: "Polkadot", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "P", color: .pink),
            Coin(name: "Stellar", symbol: "XLM", marketDataID: "512", coinGeckoID: "stellar", chainName: "Stellar", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "XL", color: .teal),
            Coin(name: "Tether USD", symbol: "USDT", marketDataID: "825", coinGeckoID: "tether", chainName: "Ethereum", tokenStandard: "ERC-20", contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7", amount: 0, priceUSD: 1, mark: "T", color: .green),
            Coin(name: "USD Coin", symbol: "USDC", marketDataID: "3408", coinGeckoID: "usd-coin", chainName: "Ethereum", tokenStandard: "ERC-20", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", amount: 0, priceUSD: 1, mark: "U", color: .blue)
        ]
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

        return order.compactMap { grouped[$0] }
    }

    var availableDashboardPinOptions: [DashboardPinOption] {
        cachedAvailableDashboardPinOptions
    }

    func isDashboardAssetPinned(_ symbol: String) -> Bool {
        pinnedDashboardAssetSymbols.contains(symbol.uppercased())
    }

    func setDashboardAssetPinned(_ isPinned: Bool, symbol: String) {
        let normalized = symbol.uppercased()
        var symbols = pinnedDashboardAssetSymbols
        if isPinned {
            if !symbols.contains(normalized) {
                symbols.append(normalized)
            }
        } else {
            symbols.removeAll { $0 == normalized }
        }
        UserDefaults.standard.set(symbols, forKey: Self.pinnedDashboardAssetSymbolsDefaultsKey)
        rebuildDashboardDerivedState()
    }

    func resetPinnedDashboardAssets() {
        UserDefaults.standard.removeObject(forKey: Self.pinnedDashboardAssetSymbolsDefaultsKey)
        rebuildDashboardDerivedState()
    }

    private func dashboardAssetGroupingKey(for coin: Coin) -> String {
        let normalizedCoinGeckoID = coin.coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let chainIdentity = runtimeChainIdentity(for: coin.chainName).lowercased()
        if !normalizedCoinGeckoID.isEmpty {
            return "chain:\(chainIdentity)|cg:\(normalizedCoinGeckoID)"
        }
        return "chain:\(chainIdentity)|symbol:\(coin.symbol.lowercased())"
    }

    private func dashboardPinnedAssetPrototype(symbol: String) -> Coin? {
        let normalizedSymbol = symbol.uppercased()
        if let existing = cachedIncludedPortfolioHoldingsBySymbol[normalizedSymbol]?.first {
            return Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: 0,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        }
        if let trackedEntry = cachedResolvedTokenPreferencesBySymbol[normalizedSymbol]?.first {
            return Coin(
                name: trackedEntry.name,
                symbol: trackedEntry.symbol,
                marketDataID: trackedEntry.marketDataID,
                coinGeckoID: trackedEntry.coinGeckoID,
                chainName: trackedEntry.chain.rawValue,
                tokenStandard: trackedEntry.tokenStandard,
                contractAddress: trackedEntry.contractAddress,
                amount: 0,
                priceUSD: trackedEntry.symbol == "USDC" || trackedEntry.symbol == "USDT" || trackedEntry.symbol == "FDUSD" || trackedEntry.symbol == "TUSD" ? 1 : 0,
                mark: Coin.displayMark(for: trackedEntry.symbol),
                color: Coin.displayColor(for: trackedEntry.symbol)
            )
        }
        return dashboardPinPrototypes.first(where: { $0.symbol.uppercased() == normalizedSymbol })
    }

    var dashboardAssetGroups: [DashboardAssetGroup] {
        cachedDashboardAssetGroups
    }

    func dashboardSupportedTokenEntries(symbol: String) -> [TokenPreferenceEntry] {
        cachedDashboardSupportedTokenEntriesBySymbol[symbol.uppercased()] ?? []
    }

    func rebuildDashboardDerivedState() {
        let includedHoldings = cachedIncludedPortfolioHoldings
        let holdingsBySymbol = cachedIncludedPortfolioHoldingsBySymbol
        let trackedEntriesBySymbol = cachedResolvedTokenPreferencesBySymbol
        let prototypeBySymbol = Dictionary(uniqueKeysWithValues: dashboardPinPrototypes.map { ($0.symbol.uppercased(), $0) })

        let storedPinnedSymbols: [String]
        storedPinnedSymbols = (UserDefaults.standard.stringArray(forKey: Self.pinnedDashboardAssetSymbolsDefaultsKey) ?? defaultPinnedDashboardAssetSymbols)
            .map { $0.uppercased() }
            .filter { !$0.isEmpty }
        cachedPinnedDashboardAssetSymbols = storedPinnedSymbols

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
                    for: symbol,
                    portfolioCoins: holdingsBySymbol[symbol] ?? [],
                    trackedEntries: trackedEntriesBySymbol[symbol] ?? [],
                    prototype: prototypeBySymbol[symbol]
                ).map { (symbol, $0) }
            }
        )
        cachedDashboardPinOptionBySymbol = optionBySymbol
        cachedAvailableDashboardPinOptions = availableSymbols.compactMap { optionBySymbol[$0] }
        cachedDashboardRelevantPriceKeys = Set(
            includedHoldings
                .filter(isPricedAsset)
                .map(assetIdentityKey)
        )
        cachedDashboardSupportedTokenEntriesBySymbol = Dictionary(
            uniqueKeysWithValues: trackedEntriesBySymbol.map { symbol, entries in
                let supportedEntries = uniqueDashboardSupportedTokenEntries(from: entries)
                return (symbol, supportedEntries)
            }
        )

        let positiveCoins = includedHoldings
            .filter { $0.amount > 0 }

        var grouped: [String: [Coin]] = [:]
        var order: [String] = []
        for coin in positiveCoins {
            let key = dashboardAssetGroupingKey(for: coin)
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(coin)
        }

        var groups: [DashboardAssetGroup] = order.compactMap { key -> DashboardAssetGroup? in
            guard let coins = grouped[key], !coins.isEmpty else { return nil }
            var chainGrouped: [String: Coin] = [:]
            for coin in coins {
                let normalizedContract = DashboardAssetIdentity.normalizedContractAddress(
                    coin.contractAddress,
                    chainName: coin.chainName,
                    tokenStandard: coin.tokenStandard
                ) ?? "native"
                let chainKey = "\(runtimeChainIdentity(for: coin.chainName).lowercased())|\(coin.tokenStandard.lowercased())|\(normalizedContract)"
                if let existing = chainGrouped[chainKey] {
                    chainGrouped[chainKey] = Coin(
                        name: existing.name,
                        symbol: existing.symbol,
                        marketDataID: existing.marketDataID,
                        coinGeckoID: existing.coinGeckoID,
                        chainName: existing.chainName,
                        tokenStandard: existing.tokenStandard,
                        contractAddress: existing.contractAddress,
                        amount: existing.amount + coin.amount,
                        priceUSD: coin.priceUSD,
                        mark: existing.mark,
                        color: existing.color
                    )
                } else {
                    chainGrouped[chainKey] = coin
                }
            }

            let chainEntries = chainGrouped.values
                .map { DashboardAssetChainEntry(coin: $0, valueUSD: currentValueIfAvailable(for: $0)) }
                .sorted {
                    let lhsValue = $0.valueUSD ?? -1
                    let rhsValue = $1.valueUSD ?? -1
                    if abs(lhsValue - rhsValue) > 0.000001 {
                        return lhsValue > rhsValue
                    }
                    return $0.coin.chainName.localizedCaseInsensitiveCompare($1.coin.chainName) == .orderedAscending
                }
            guard let representativeCoin = chainEntries.first?.coin else { return nil }
            let totalAmount = coins.reduce(0) { $0 + $1.amount }
            let totalValueUSD: Double? = chainEntries.allSatisfy({ $0.valueUSD != nil })
                ? chainEntries.compactMap(\.valueUSD).reduce(0, +)
                : nil
            let isPinned = storedPinnedSymbols.contains(representativeCoin.symbol.uppercased())
            return DashboardAssetGroup(
                id: key,
                representativeCoin: representativeCoin,
                totalAmount: totalAmount,
                totalValueUSD: totalValueUSD,
                chainEntries: chainEntries,
                isPinned: isPinned
            )
        }

        let existingPinnedSymbols = Set(groups.map { $0.symbol.uppercased() })
        for symbol in storedPinnedSymbols where !existingPinnedSymbols.contains(symbol) {
            let prototype = holdingsBySymbol[symbol]?.first
                ?? trackedEntriesBySymbol[symbol]?.first.map {
                    Coin(
                        name: $0.name,
                        symbol: $0.symbol,
                        marketDataID: $0.marketDataID,
                        coinGeckoID: $0.coinGeckoID,
                        chainName: $0.chain.rawValue,
                        tokenStandard: $0.tokenStandard,
                        contractAddress: $0.contractAddress,
                        amount: 0,
                        priceUSD: $0.symbol == "USDC" || $0.symbol == "USDT" || $0.symbol == "FDUSD" || $0.symbol == "TUSD" ? 1 : 0,
                        mark: Coin.displayMark(for: $0.symbol),
                        color: Coin.displayColor(for: $0.symbol)
                    )
                }
                ?? prototypeBySymbol[symbol]
            guard let prototype else { continue }
            groups.append(
                DashboardAssetGroup(
                    id: "pinned:\(symbol.lowercased())",
                    representativeCoin: prototype,
                    totalAmount: 0,
                    totalValueUSD: 0,
                    chainEntries: [],
                    isPinned: true
                )
            )
        }

        let pinnedOrder = Dictionary(uniqueKeysWithValues: storedPinnedSymbols.enumerated().map { ($1, $0) })
        cachedDashboardAssetGroups = groups.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.isPinned, rhs.isPinned {
                return (pinnedOrder[lhs.symbol.uppercased()] ?? Int.max) < (pinnedOrder[rhs.symbol.uppercased()] ?? Int.max)
            }
            let lhsValue = lhs.totalValueUSD ?? -1
            let rhsValue = rhs.totalValueUSD ?? -1
            if abs(lhsValue - rhsValue) > 0.000001 {
                return lhsValue > rhsValue
            }
            return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
        }
    }

    private func dashboardPinOptionUncached(
        for symbol: String,
        portfolioCoins: [Coin],
        trackedEntries: [TokenPreferenceEntry],
        prototype: Coin?
    ) -> DashboardPinOption? {
        let normalizedSymbol = symbol.uppercased()

        if let representativeCoin = portfolioCoins.first {
            let chainNames = Array(Set(portfolioCoins.map(\.chainName) + trackedEntries.map(\.chain.rawValue)))
                .sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol,
                name: representativeCoin.name,
                subtitle: chainNames.isEmpty ? representativeCoin.chainName : chainNames.joined(separator: ", "),
                assetIdentifier: representativeCoin.iconIdentifier,
                mark: representativeCoin.mark,
                color: representativeCoin.color
            )
        }

        if let representativeEntry = trackedEntries.first {
            let chainNames = Array(Set(trackedEntries.map(\.chain.rawValue))).sorted()
            return DashboardPinOption(
                symbol: normalizedSymbol,
                name: representativeEntry.name,
                subtitle: chainNames.joined(separator: ", "),
                assetIdentifier: Coin.iconIdentifier(
                    symbol: representativeEntry.symbol,
                    chainName: representativeEntry.chain.rawValue,
                    contractAddress: representativeEntry.contractAddress,
                    tokenStandard: representativeEntry.tokenStandard
                ),
                mark: Coin.displayMark(for: representativeEntry.symbol),
                color: Coin.displayColor(for: representativeEntry.symbol)
            )
        }

        if let prototype {
            return DashboardPinOption(
                symbol: normalizedSymbol,
                name: prototype.name,
                subtitle: prototype.chainName,
                assetIdentifier: prototype.iconIdentifier,
                mark: prototype.mark,
                color: prototype.color
            )
        }

        return nil
    }

    private func uniqueDashboardSupportedTokenEntries(from entries: [TokenPreferenceEntry]) -> [TokenPreferenceEntry] {
        var seenKeys = Set<String>()
        return entries
            .filter { !$0.contractAddress.isEmpty }
            .sorted {
                $0.chain.rawValue.localizedCaseInsensitiveCompare($1.chain.rawValue) == .orderedAscending
            }
            .filter { entry in
                let key = "\(entry.chain.rawValue.lowercased())|\(entry.contractAddress.lowercased())"
                return seenKeys.insert(key).inserted
            }
    }

    var appNoticeItems: [AppNoticeItem] {
        let commonCopy = CommonLocalizationContent.current
        var notices: [AppNoticeItem] = []

        if let quoteRefreshError = quoteRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quoteRefreshError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Pricing Notice"),
                    message: quoteRefreshError,
                    severity: .warning,
                    systemImage: "dollarsign.circle"
                )
            )
        }

        if let fiatRatesRefreshError = fiatRatesRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fiatRatesRefreshError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Fiat Rates Degraded Mode"),
                    message: fiatRatesRefreshError,
                    severity: .warning,
                    systemImage: "antenna.radiowaves.left.and.right.slash"
                )
            )
        }

        notices.append(contentsOf: chainDegradedBanners.map { banner in
            AppNoticeItem(
                title: localizedStoreFormat("%@ Degraded Mode", banner.chainName),
                message: banner.message,
                severity: .warning,
                systemImage: "antenna.radiowaves.left.and.right.slash",
                timestamp: banner.lastGoodSyncAt
            )
        })

        if let importError = importError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !importError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.walletImportErrorTitle,
                    message: importError,
                    severity: .error,
                    systemImage: "square.and.arrow.down.badge.exclamationmark"
                )
            )
        }

        if let sendError = sendError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sendError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.sendErrorTitle,
                    message: sendError,
                    severity: .error,
                    systemImage: "paperplane.circle"
                )
            )
        }

        if let appLockError = appLockError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appLockError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.securityNoticeTitle,
                    message: appLockError,
                    severity: .error,
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
            )
        }

        if let tronLastSendErrorDetails = tronLastSendErrorDetails?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tronLastSendErrorDetails.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.tronSendDiagnosticTitle,
                    message: tronLastSendErrorDetails,
                    severity: .error,
                    systemImage: "bolt.trianglebadge.exclamationmark",
                    timestamp: tronLastSendErrorAt
                )
            )
        }

        return notices
    }
}
