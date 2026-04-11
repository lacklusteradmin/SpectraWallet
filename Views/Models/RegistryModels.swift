import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WalletChainID: Hashable, Codable, Identifiable, Comparable {
    let rawValue: String

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        Self.displayNameByID[rawValue] ?? rawValue
    }

    nonisolated init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated init?(_ chainNameOrID: String) {
        let normalized = chainNameOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let resolved = Self.lookupByNormalizedAlias[normalized.lowercased()] {
            self.init(rawValue: resolved)
        } else {
            self.init(rawValue: Self.fallbackRawValue(for: normalized))
        }
    }

    nonisolated static func < (lhs: WalletChainID, rhs: WalletChainID) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    nonisolated private static func fallbackRawValue(for chainNameOrID: String) -> String {
        let normalized = chainNameOrID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let collapsed = normalized.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    nonisolated(unsafe) private static let chainWikiEntries: [ChainWikiEntry] = StaticContentCatalog.loadResource("ChainWikiEntries", as: [ChainWikiEntry].self) ?? []

    nonisolated(unsafe) private static let displayNameByID: [String: String] = Dictionary(
        uniqueKeysWithValues: chainWikiEntries.map { ($0.id.lowercased(), $0.name) }
    )

    nonisolated(unsafe) private static let lookupByNormalizedAlias: [String: String] = {
        var entries: [String: String] = [:]
        for entry in chainWikiEntries {
            entries[entry.id.lowercased()] = entry.id
            entries[entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.id
            entries[entry.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.id
        }
        return entries
    }()
}

enum TokenTrackingChain: String, CaseIterable, Codable, Identifiable {
    case ethereum = "Ethereum"
    case arbitrum = "Arbitrum"
    case optimism = "Optimism"
    case bnb = "BNB Chain"
    case avalanche = "Avalanche"
    case hyperliquid = "Hyperliquid"
    case solana = "Solana"
    case sui = "Sui"
    case aptos = "Aptos"
    case ton = "TON"
    case near = "NEAR"
    case tron = "Tron"

    var id: String { rawValue }

    var tokenStandard: String {
        switch self {
        case .ethereum:
            return "ERC-20"
        case .arbitrum:
            return "ERC-20"
        case .optimism:
            return "ERC-20"
        case .bnb:
            return "BEP-20"
        case .avalanche:
            return "ARC-20"
        case .hyperliquid:
            return "ERC-20"
        case .solana:
            return "SPL"
        case .sui:
            return "Coin Standard"
        case .aptos:
            return "Fungible Asset"
        case .ton:
            return "Jetton"
        case .near:
            return "NEP-141"
        case .tron:
            return "TRC-20"
        }
    }

    var filterDisplayName: String {
        "\(rawValue) (\(tokenStandard))"
    }

    var contractAddressPrompt: String {
        switch self {
        case .solana:
            return "Mint Address"
        case .sui:
            return "Coin Standard Type"
        case .aptos:
            return "Fungible Asset Metadata or Package Address"
        case .ton:
            return "Jetton Master Address"
        case .near:
            return "Contract Account ID"
        default:
            return "Contract Address"
        }
    }

    static func forChainName(_ chainName: String) -> TokenTrackingChain? {
        let normalized = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        return byNormalizedName[normalized.lowercased()]
    }

    private static let byNormalizedName: [String: TokenTrackingChain] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.rawValue.lowercased(), $0) }
    )
}

private struct ChainRegistryVisualMetadata {
    let mark: String
    let color: Color
    let assetName: String

    static let byID: [String: ChainRegistryVisualMetadata] = ChainVisualRegistryCatalog.loadEntries().mapValues {
        ChainRegistryVisualMetadata(mark: $0.mark, color: $0.color, assetName: $0.assetName)
    }
}

struct ChainRegistryEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let mark: String
    let color: Color
    let assetName: String
    let family: String
    let consensus: String
    let stateModel: String
    let primaryUse: String
    let slip44CoinType: String
    let derivationPath: String
    let alternateDerivationPath: String?
    let totalCirculationModel: String
    let notableDetails: [String]

    var assetIdentifier: String {
        Coin.iconIdentifier(symbol: symbol, chainName: name)
    }

    var nativeIconDescriptor: NativeChainIconDescriptor {
        NativeChainIconDescriptor(
            registryID: id,
            title: name,
            symbol: symbol,
            chainName: name,
            mark: mark,
            color: color,
            assetName: assetName
        )
    }

    private static var cachedAllByLocalization: [String: [ChainRegistryEntry]] = [:]
    private static var cachedEntriesByLowercasedID: [String: [String: ChainRegistryEntry]] = [:]

    static var all: [ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedAllByLocalization[cacheKey] {
            return cachedEntries
        }

        let entries: [ChainRegistryEntry] = ChainWikiEntry.all.compactMap { wiki in
            guard let visual = ChainRegistryVisualMetadata.byID[wiki.id] else { return nil }
            return ChainRegistryEntry(
                id: wiki.id,
                name: wiki.name,
                symbol: wiki.symbol,
                mark: visual.mark,
                color: visual.color,
                assetName: visual.assetName,
                family: wiki.family,
                consensus: wiki.consensus,
                stateModel: wiki.stateModel,
                primaryUse: wiki.primaryUse,
                slip44CoinType: wiki.slip44CoinType,
                derivationPath: wiki.derivationPath,
                alternateDerivationPath: wiki.alternateDerivationPath,
                totalCirculationModel: wiki.totalCirculationModel,
                notableDetails: wiki.notableDetails
            )
        }
        cachedAllByLocalization[cacheKey] = entries
        cachedEntriesByLowercasedID[cacheKey] = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.lowercased(), $0) })
        return entries
    }

    private static var entriesByLowercasedID: [String: ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedEntriesByLowercasedID[cacheKey] {
            return cachedEntries
        }
        _ = all
        return cachedEntriesByLowercasedID[cacheKey] ?? [:]
    }

    static func entry(id: String) -> ChainRegistryEntry? {
        entriesByLowercasedID[id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}

struct TokenVisualRegistryEntry: Identifiable {
    let title: String
    let symbol: String
    let referenceChain: TokenTrackingChain
    let mark: String
    let color: Color
    let assetName: String

    var id: String { symbol }

    var assetIdentifier: String {
        Coin.iconIdentifier(
            symbol: symbol,
            chainName: referenceChain.rawValue,
            tokenStandard: referenceChain.tokenStandard
        )
    }

    static let all: [TokenVisualRegistryEntry] = TokenVisualRegistryCatalog.loadEntries()
    private static let entriesByLowercasedSymbol: [String: TokenVisualRegistryEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.symbol.lowercased(), $0) }
    )
    private static let assetIdentifierFragments: [(fragment: String, entry: TokenVisualRegistryEntry)] = all.map {
        (":\($0.symbol.lowercased())", $0)
    }

    static func entry(symbol: String) -> TokenVisualRegistryEntry? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entriesByLowercasedSymbol[normalized]
    }

    static func entry(matchingAssetIdentifier assetIdentifier: String) -> TokenVisualRegistryEntry? {
        let normalized = assetIdentifier.lowercased()
        return assetIdentifierFragments.first { normalized.contains($0.fragment) }?.entry
    }
}

enum TokenPreferenceCategory: String, CaseIterable, Codable, Identifiable {
    case stablecoin
    case meme
    case custom

    var id: String { rawValue }
}

struct TokenPreferenceEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let chain: TokenTrackingChain
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let marketDataID: String
    let coinGeckoID: String
    var decimals: Int
    var displayDecimals: Int?
    let category: TokenPreferenceCategory
    let isBuiltIn: Bool
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        chain: TokenTrackingChain,
        name: String,
        symbol: String,
        tokenStandard: String,
        contractAddress: String,
        marketDataID: String,
        coinGeckoID: String,
        decimals: Int,
        displayDecimals: Int? = nil,
        category: TokenPreferenceCategory,
        isBuiltIn: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.chain = chain
        self.name = name
        self.symbol = symbol
        self.tokenStandard = tokenStandard
        self.contractAddress = contractAddress
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
        self.decimals = decimals
        self.displayDecimals = displayDecimals
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }
}

struct ChainTokenRegistryEntry: Identifiable, Equatable {
    let chain: TokenTrackingChain
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let marketDataID: String
    let coinGeckoID: String
    let decimals: Int
    let displayDecimals: Int?
    let category: TokenPreferenceCategory
    let isBuiltIn: Bool
    let isEnabledByDefault: Bool

    var id: String {
        Coin.iconIdentifier(
            symbol: symbol,
            chainName: chain.rawValue,
            contractAddress: contractAddress,
            tokenStandard: tokenStandard
        )
    }

    init(
        chain: TokenTrackingChain,
        name: String,
        symbol: String,
        tokenStandard: String,
        contractAddress: String,
        marketDataID: String,
        coinGeckoID: String,
        decimals: Int,
        displayDecimals: Int? = nil,
        category: TokenPreferenceCategory,
        isBuiltIn: Bool,
        isEnabledByDefault: Bool
    ) {
        self.chain = chain
        self.name = name
        self.symbol = symbol
        self.tokenStandard = tokenStandard
        self.contractAddress = contractAddress
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
        self.decimals = decimals
        self.displayDecimals = displayDecimals
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.isEnabledByDefault = isEnabledByDefault
    }

    init(tokenPreferenceEntry: TokenPreferenceEntry) {
        chain = tokenPreferenceEntry.chain
        name = tokenPreferenceEntry.name
        symbol = tokenPreferenceEntry.symbol
        tokenStandard = tokenPreferenceEntry.tokenStandard
        contractAddress = tokenPreferenceEntry.contractAddress
        marketDataID = tokenPreferenceEntry.marketDataID
        coinGeckoID = tokenPreferenceEntry.coinGeckoID
        decimals = tokenPreferenceEntry.decimals
        displayDecimals = tokenPreferenceEntry.displayDecimals
        category = tokenPreferenceEntry.category
        isBuiltIn = tokenPreferenceEntry.isBuiltIn
        isEnabledByDefault = tokenPreferenceEntry.isEnabled
    }

    var tokenPreferenceEntry: TokenPreferenceEntry {
        TokenPreferenceEntry(
            chain: chain,
            name: name,
            symbol: symbol,
            tokenStandard: tokenStandard,
            contractAddress: contractAddress,
            marketDataID: marketDataID,
            coinGeckoID: coinGeckoID,
            decimals: decimals,
            displayDecimals: displayDecimals,
            category: category,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabledByDefault
        )
    }
}

struct NativeChainIconDescriptor: Identifiable {
    let registryID: String
    let title: String
    let symbol: String
    let chainName: String
    let mark: String
    let color: Color
    let assetName: String

    var id: String { assetIdentifier }
    var assetIdentifier: String {
        Coin.iconIdentifier(symbol: symbol, chainName: chainName)
    }
}

extension Coin {
    static let nativeChainIconDescriptors: [NativeChainIconDescriptor] = ChainRegistryEntry.all.map(\.nativeIconDescriptor)

    static func nativeChainIconDescriptor(forAssetIdentifier assetIdentifier: String) -> NativeChainIconDescriptor? {
        nativeChainIconDescriptors.first { $0.assetIdentifier == assetIdentifier }
    }

    static func nativeChainIconDescriptor(chainName: String) -> NativeChainIconDescriptor? {
        let normalizedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChainName.isEmpty else { return nil }
        let canonicalChainName = canonicalChainComponent(chainName: normalizedChainName, symbol: "")

        return nativeChainIconDescriptors.first { descriptor in
            descriptor.registryID.caseInsensitiveCompare(canonicalChainName) == .orderedSame
                || descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
    }

    static func nativeChainIconDescriptor(symbol: String, chainName: String? = nil) -> NativeChainIconDescriptor? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChainName = chainName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return nativeChainIconDescriptors.first { descriptor in
            let symbolMatches = descriptor.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame
            guard symbolMatches else { return false }

            if normalizedChainName.isEmpty {
                return true
            }

            return descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
    }

    static func nativeChainBadge(chainName: String) -> (assetIdentifier: String?, mark: String, color: Color)? {
        guard let descriptor = nativeChainIconDescriptor(chainName: chainName) else { return nil }
        return (descriptor.assetIdentifier, descriptor.mark, descriptor.color)
    }

    static func iconIdentifier(
        symbol: String,
        chainName: String,
        contractAddress: String? = nil,
        tokenStandard: String = "Native"
    ) -> String {
        let normalizedSymbol = symbol.lowercased()
        let trimmedContract = contractAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedChain = canonicalChainComponent(chainName: chainName, symbol: symbol)

        if !trimmedContract.isEmpty {
            return "token:\(normalizedChain):\(normalizedSymbol):\(trimmedContract.lowercased())"
        }

        let isNativeToken = tokenStandard.caseInsensitiveCompare("Native") == .orderedSame || tokenStandard.isEmpty
        let namespace = isNativeToken ? "native" : "asset"
        return "\(namespace):\(normalizedChain):\(normalizedSymbol)"
    }

    static func normalizedIconIdentifier(_ identifier: String) -> String {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedIdentifier.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3 else { return trimmedIdentifier }

        let namespace = components[0]
        let chainComponent = components[1]
        let symbolComponent = components[2]
        let canonicalChain = canonicalChainComponent(chainName: chainComponent, symbol: symbolComponent)
        var normalizedComponents = components
        normalizedComponents[1] = canonicalChain
        normalizedComponents[2] = symbolComponent.lowercased()
        if normalizedComponents.count >= 4 {
            normalizedComponents[3] = normalizedComponents[3].lowercased()
        }

        switch namespace {
        case "native", "asset", "token":
            normalizedComponents[0] = namespace
            return normalizedComponents.joined(separator: ":")
        default:
            return trimmedIdentifier
        }
    }

    private static func canonicalChainComponent(chainName: String, symbol: String) -> String {
        let normalizedChainName = chainName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let knownAliases: [String: String] = [
            "bitcoin": "bitcoin",
            "bitcoin cash": "bitcoin-cash",
            "bitcoin sv": "bitcoin-sv",
            "litecoin": "litecoin",
            "dogecoin": "dogecoin",
            "ethereum": "ethereum",
            "ethereum classic": "ethereum-classic",
            "arbitrum": "arbitrum",
            "optimism": "optimism",
            "bnb chain": "bnb",
            "avalanche": "avalanche",
            "hyperliquid": "hyperliquid",
            "tron": "tron",
            "solana": "solana",
            "stellar": "stellar",
            "cardano": "cardano",
            "xrp ledger": "xrp",
            "monero": "monero",
            "sui": "sui",
            "aptos": "aptos",
            "ton": "ton",
            "internet computer": "internet-computer",
            "near": "near",
            "polkadot": "polkadot"
        ]

        if let knownAlias = knownAliases[normalizedChainName] {
            return knownAlias
        }

        if let localizedMatch = ChainRegistryEntry.all.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedChainName
        }) {
            return localizedMatch.id
        }

        let nativeSymbolAliases: [String: String] = [
            "BTC": "bitcoin",
            "BCH": "bitcoin-cash",
            "BSV": "bitcoin-sv",
            "LTC": "litecoin",
            "DOGE": "dogecoin",
            "ETH": "ethereum",
            "ETC": "ethereum-classic",
            "ARB": "arbitrum",
            "OP": "optimism",
            "BNB": "bnb",
            "AVAX": "avalanche",
            "HYPE": "hyperliquid",
            "TRX": "tron",
            "SOL": "solana",
            "XLM": "stellar",
            "ADA": "cardano",
            "XRP": "xrp",
            "XMR": "monero",
            "SUI": "sui",
            "APT": "aptos",
            "TON": "ton",
            "ICP": "internet-computer",
            "NEAR": "near",
            "DOT": "polkadot"
        ]

        if let nativeSymbolAlias = nativeSymbolAliases[normalizedSymbol] {
            return nativeSymbolAlias
        }

        return normalizedChainName.replacingOccurrences(of: " ", with: "-")
    }

    static func displayMark(for symbol: String) -> String {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) {
            return nativeDescriptor.mark
        }

        switch symbol {
        case "MATIC":
            return "P"
        case "ARB":
            return "AR"
        case "TRX", "USDT":
            return "T"
        default:
            if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) {
                return tokenEntry.mark
            }
            return String(symbol.prefix(2)).uppercased()
        }
    }
    
    static func displayColor(for symbol: String) -> Color {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) {
            return nativeDescriptor.color
        }

        switch symbol {
        case "MATIC":
            return .indigo
        case "TRX":
            return .red
        case "ARB":
            return .cyan
        case "USDT":
            return .green
        default:
            if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) {
                return tokenEntry.color
            }
            return .gray
        }
    }

    var iconIdentifier: String {
        Self.iconIdentifier(
            symbol: symbol,
            chainName: chainName,
            contractAddress: contractAddress,
            tokenStandard: tokenStandard
        )
    }

    @MainActor init(snapshot: PersistedCoin) {
        self.init(
            name: snapshot.name,
            symbol: snapshot.symbol,
            marketDataID: snapshot.marketDataID,
            coinGeckoID: snapshot.coinGeckoID,
            chainName: snapshot.chainName,
            tokenStandard: snapshot.tokenStandard,
            contractAddress: snapshot.contractAddress,
            amount: snapshot.amount,
            priceUSD: snapshot.priceUSD,
            mark: Self.displayMark(for: snapshot.symbol),
            color: Self.displayColor(for: snapshot.symbol)
        )
    }
    
    var persistedSnapshot: PersistedCoin {
        PersistedCoin(
            name: name,
            symbol: symbol,
            marketDataID: marketDataID,
            coinGeckoID: coinGeckoID,
            chainName: chainName,
            tokenStandard: tokenStandard,
            contractAddress: contractAddress,
            amount: amount,
            priceUSD: priceUSD
        )
    }
}
