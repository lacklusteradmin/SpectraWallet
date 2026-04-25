import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
struct WalletChainID: Hashable, Codable, Identifiable, Comparable {
    let rawValue: String
    nonisolated var id: String { rawValue }
    nonisolated var displayName: String { Self.displayNameByID[rawValue] ?? rawValue }
    nonisolated init(rawValue: String) { self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    nonisolated init?(_ chainNameOrID: String) {
        let normalized = chainNameOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let resolved = Self.lookupByNormalizedAlias[normalized.lowercased()] {
            self.init(rawValue: resolved)
        } else {
            self.init(rawValue: Self.fallbackRawValue(for: normalized))
        }
    }
    nonisolated static func resolved(_ chainNameOrID: String) -> WalletChainID {
        WalletChainID(chainNameOrID) ?? WalletChainID(rawValue: chainNameOrID)
    }
    nonisolated static func < (lhs: WalletChainID, rhs: WalletChainID) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
    nonisolated private static func fallbackRawValue(for chainNameOrID: String) -> String {
        let normalized = chainNameOrID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let collapsed = normalized.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    nonisolated private static let chainWikiEntries: [ChainWikiEntry] =
        StaticContentCatalog.loadResource("ChainWikiEntries", as: [ChainWikiEntry].self) ?? []
    nonisolated private static let displayNameByID: [String: String] = Dictionary(
        uniqueKeysWithValues: chainWikiEntries.map { ($0.id.lowercased(), $0.name) }
    )
    nonisolated private static let lookupByNormalizedAlias: [String: String] = {
        var entries: [String: String] = [:]
        for entry in chainWikiEntries {
            entries[entry.id.lowercased()] = entry.id
            entries[entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.id
            entries[entry.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.id
        }
        return entries
    }()
}
typealias TokenTrackingChain = CoreTokenTrackingChain
extension CoreTokenTrackingChain: RawRepresentable, CaseIterable, Codable, Identifiable {
    public typealias RawValue = String
    public init?(rawValue: String) {
        switch rawValue {
        case "Ethereum": self = .ethereum
        case "Arbitrum": self = .arbitrum
        case "Optimism": self = .optimism
        case "BNB Chain": self = .bnb
        case "Avalanche": self = .avalanche
        case "Hyperliquid": self = .hyperliquid
        case "Polygon": self = .polygon
        case "Base": self = .base
        case "Linea": self = .linea
        case "Scroll": self = .scroll
        case "Blast": self = .blast
        case "Mantle": self = .mantle
        case "Solana": self = .solana
        case "Sui": self = .sui
        case "Aptos": self = .aptos
        case "TON": self = .ton
        case "NEAR": self = .near
        case "Tron": self = .tron
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .ethereum: return "Ethereum"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .bnb: return "BNB Chain"
        case .avalanche: return "Avalanche"
        case .hyperliquid: return "Hyperliquid"
        case .polygon: return "Polygon"
        case .base: return "Base"
        case .linea: return "Linea"
        case .scroll: return "Scroll"
        case .blast: return "Blast"
        case .mantle: return "Mantle"
        case .solana: return "Solana"
        case .sui: return "Sui"
        case .aptos: return "Aptos"
        case .ton: return "TON"
        case .near: return "NEAR"
        case .tron: return "Tron"
        }
    }
    public static var allCases: [CoreTokenTrackingChain] {
        [.ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid, .polygon, .base, .linea, .scroll, .blast, .mantle,
         .solana, .sui, .aptos, .ton, .near, .tron]
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let v = CoreTokenTrackingChain(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown TokenTrackingChain: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var id: String { rawValue }
    var tokenStandard: String {
        switch self {
        case .ethereum, .arbitrum, .optimism, .hyperliquid, .polygon, .base, .linea, .scroll, .blast, .mantle: return "ERC-20"
        case .bnb: return "BEP-20"
        case .avalanche: return "ARC-20"
        case .solana: return "SPL"
        case .sui: return "Coin Standard"
        case .aptos: return "Fungible Asset"
        case .ton: return "Jetton"
        case .near: return "NEP-141"
        case .tron: return "TRC-20"
        }
    }
    var filterDisplayName: String { "\(rawValue) (\(tokenStandard))" }
    var slug: String {
        switch self {
        case .bnb: return "bnb"
        default: return rawValue.lowercased()
        }
    }
    var contractAddressPrompt: String {
        switch self {
        case .solana: return "Mint Address"
        case .sui: return "Coin Standard Type"
        case .aptos: return "Fungible Asset Metadata or Package Address"
        case .ton: return "Jetton Master Address"
        case .near: return "Contract Account ID"
        default: return "Contract Address"
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
    let color: Color
    let assetName: String
    static let byID: [String: ChainRegistryVisualMetadata] = ChainVisualRegistryCatalog.loadEntries().mapValues {
        ChainRegistryVisualMetadata(color: $0.color, assetName: $0.assetName)
    }
}
struct ChainRegistryEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
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
    var assetIdentifier: String { Coin.iconIdentifier(symbol: symbol, chainName: name) }
    var nativeIconDescriptor: NativeChainIconDescriptor {
        NativeChainIconDescriptor(
            registryID: id, title: name, symbol: symbol, chainName: name, color: color, assetName: assetName
        )
    }
    private static var cachedAllByLocalization: [String: [ChainRegistryEntry]] = [:]
    private static var cachedEntriesByLowercasedID: [String: [String: ChainRegistryEntry]] = [:]
    static var all: [ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedAllByLocalization[cacheKey] { return cachedEntries }
        let entries: [ChainRegistryEntry] = ChainWikiEntry.all.compactMap { wiki in
            guard let visual = ChainRegistryVisualMetadata.byID[wiki.id] else { return nil }
            return ChainRegistryEntry(
                id: wiki.id, name: wiki.name, symbol: wiki.symbol, color: visual.color, assetName: visual.assetName,
                family: wiki.family, consensus: wiki.consensus, stateModel: wiki.stateModel, primaryUse: wiki.primaryUse,
                slip44CoinType: wiki.slip44CoinType, derivationPath: wiki.derivationPath,
                alternateDerivationPath: wiki.alternateDerivationPath, totalCirculationModel: wiki.totalCirculationModel,
                notableDetails: wiki.notableDetails
            )
        }
        cachedAllByLocalization[cacheKey] = entries
        cachedEntriesByLowercasedID[cacheKey] = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.lowercased(), $0) })
        return entries
    }
    private static var entriesByLowercasedID: [String: ChainRegistryEntry] {
        let cacheKey = AppLocalization.preferredLocalizationIdentifiers().joined(separator: "|")
        if let cachedEntries = cachedEntriesByLowercasedID[cacheKey] { return cachedEntries }
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
    let color: Color
    let assetName: String
    var id: String { symbol }
    var assetIdentifier: String {
        Coin.iconIdentifier(symbol: symbol, chainName: referenceChain.rawValue, tokenStandard: referenceChain.tokenStandard)
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
    // Memoize the substring-match lookup — can't be replaced with a dict
    // because the match is `contains`, not exact. Called per `CoinBadge`
    // body eval from `tokenIconAssetName`, so caching it means the O(n)
    // scan fires at most once per unique assetIdentifier.
    nonisolated(unsafe) private static var cachedMatchingEntries: [String: TokenVisualRegistryEntry?] = [:]
    static func entry(matchingAssetIdentifier assetIdentifier: String) -> TokenVisualRegistryEntry? {
        let normalized = assetIdentifier.lowercased()
        if let cached = cachedMatchingEntries[normalized] { return cached }
        let result = assetIdentifierFragments.first { normalized.contains($0.fragment) }?.entry
        cachedMatchingEntries[normalized] = result
        return result
    }
}
typealias TokenPreferenceCategory = CoreTokenPreferenceCategory
extension CoreTokenPreferenceCategory: RawRepresentable, CaseIterable, Codable, Identifiable {
    public typealias RawValue = String
    public init?(rawValue: String) {
        switch rawValue {
        case "stablecoin": self = .stablecoin
        case "meme": self = .meme
        case "custom": self = .custom
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .stablecoin: return "stablecoin";
        case .meme: return "meme";
        case .custom: return "custom"
        }
    }
    public static var allCases: [CoreTokenPreferenceCategory] { [.stablecoin, .meme, .custom] }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let v = CoreTokenPreferenceCategory(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown TokenPreferenceCategory: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
    public var id: String { rawValue }
}

typealias TokenPreferenceEntry = CoreTokenPreferenceEntry
nonisolated extension CoreTokenPreferenceEntry: Identifiable, Codable {
    // Legacy UUID-style id initializer & convenience matching Swift-era struct.
    init(
        id: UUID = UUID(), chain: TokenTrackingChain, name: String, symbol: String, tokenStandard: String, contractAddress: String,
        coinGeckoId: String, decimals: Int, displayDecimals: Int? = nil, category: TokenPreferenceCategory,
        isBuiltIn: Bool, isEnabled: Bool
    ) {
        self.init(
            id: id.uuidString, chain: chain, name: name, symbol: symbol, tokenStandard: tokenStandard,
            contractAddress: contractAddress, coinGeckoId: coinGeckoId,
            decimals: Int32(decimals), displayDecimals: displayDecimals.map(Int32.init),
            category: category, isBuiltIn: isBuiltIn, isEnabled: isEnabled
        )
    }
    private enum CodingKeys: String, CodingKey {
        case id, chain, name, symbol, tokenStandard, contractAddress, coinGeckoId, decimals, displayDecimals, category,
            isBuiltIn, isEnabled
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try c.decode(String.self, forKey: .id)
        self.init(
            id: rawID,
            chain: try c.decode(CoreTokenTrackingChain.self, forKey: .chain),
            name: try c.decode(String.self, forKey: .name),
            symbol: try c.decode(String.self, forKey: .symbol),
            tokenStandard: try c.decode(String.self, forKey: .tokenStandard),
            contractAddress: try c.decode(String.self, forKey: .contractAddress),
            coinGeckoId: try c.decode(String.self, forKey: .coinGeckoId),
            decimals: try c.decode(Int32.self, forKey: .decimals),
            displayDecimals: try c.decodeIfPresent(Int32.self, forKey: .displayDecimals),
            category: try c.decode(CoreTokenPreferenceCategory.self, forKey: .category),
            isBuiltIn: try c.decode(Bool.self, forKey: .isBuiltIn),
            isEnabled: try c.decode(Bool.self, forKey: .isEnabled)
        )
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(chain, forKey: .chain)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(tokenStandard, forKey: .tokenStandard)
        try c.encode(contractAddress, forKey: .contractAddress)
        try c.encode(coinGeckoId, forKey: .coinGeckoId)
        try c.encode(decimals, forKey: .decimals)
        try c.encodeIfPresent(displayDecimals, forKey: .displayDecimals)
        try c.encode(category, forKey: .category)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        try c.encode(isEnabled, forKey: .isEnabled)
    }
}
struct ChainTokenRegistryEntry: Identifiable, Equatable {
    let chain: TokenTrackingChain
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let coinGeckoId: String
    let decimals: Int
    let displayDecimals: Int?
    let category: TokenPreferenceCategory
    let isBuiltIn: Bool
    let isEnabledByDefault: Bool
    var id: String {
        Coin.iconIdentifier(
            symbol: symbol, chainName: chain.rawValue, contractAddress: contractAddress, tokenStandard: tokenStandard
        )
    }
    init(
        chain: TokenTrackingChain, name: String, symbol: String, tokenStandard: String, contractAddress: String,
        coinGeckoId: String, decimals: Int, displayDecimals: Int? = nil, category: TokenPreferenceCategory, isBuiltIn: Bool,
        isEnabledByDefault: Bool
    ) {
        self.chain = chain
        self.name = name
        self.symbol = symbol
        self.tokenStandard = tokenStandard
        self.contractAddress = contractAddress
        self.coinGeckoId = coinGeckoId
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
        coinGeckoId = tokenPreferenceEntry.coinGeckoId
        decimals = Int(tokenPreferenceEntry.decimals)
        displayDecimals = tokenPreferenceEntry.displayDecimals.map(Int.init)
        category = tokenPreferenceEntry.category
        isBuiltIn = tokenPreferenceEntry.isBuiltIn
        isEnabledByDefault = tokenPreferenceEntry.isEnabled
    }
    var tokenPreferenceEntry: TokenPreferenceEntry {
        TokenPreferenceEntry(
            chain: chain, name: name, symbol: symbol, tokenStandard: tokenStandard, contractAddress: contractAddress,
            coinGeckoId: coinGeckoId, decimals: decimals, displayDecimals: displayDecimals, category: category,
            isBuiltIn: isBuiltIn, isEnabled: isEnabledByDefault
        )
    }
}
struct NativeChainIconDescriptor: Identifiable {
    let registryID: String
    let title: String
    let symbol: String
    let chainName: String
    let color: Color
    let assetName: String
    var id: String { assetIdentifier }
    var assetIdentifier: String { Coin.iconIdentifier(symbol: symbol, chainName: chainName) }
}
extension Coin {
    static let nativeChainIconDescriptors: [NativeChainIconDescriptor] = ChainRegistryEntry.all.map(\.nativeIconDescriptor)
    // Per-key indexes to turn O(n) linear scans into O(1) dictionary lookups.
    // Hot path: `CoinBadge.body` calls these 2-3× per cell × N visible cells.
    private static let nativeChainIconDescriptorByAssetIdentifier: [String: NativeChainIconDescriptor] =
        Dictionary(
            nativeChainIconDescriptors.map { ($0.assetIdentifier, $0) },
            uniquingKeysWith: { first, _ in first })
    // These caches survive the app lifetime — all inputs are pure data.
    nonisolated(unsafe) private static var cachedCanonicalChainComponents: [String: String] = [:]
    nonisolated(unsafe) private static var cachedIconIdentifiers: [String: String] = [:]
    nonisolated(unsafe) private static var cachedNormalizedIconIdentifiers: [String: String] = [:]
    nonisolated(unsafe) private static var cachedChainNameDescriptors: [String: NativeChainIconDescriptor?] = [:]
    nonisolated(unsafe) private static var cachedSymbolDescriptors: [String: NativeChainIconDescriptor?] = [:]
    static func nativeChainIconDescriptor(forAssetIdentifier assetIdentifier: String) -> NativeChainIconDescriptor? {
        nativeChainIconDescriptorByAssetIdentifier[assetIdentifier]
    }
    static func nativeChainIconDescriptor(chainName: String) -> NativeChainIconDescriptor? {
        let normalizedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChainName.isEmpty else { return nil }
        if let cached = cachedChainNameDescriptors[normalizedChainName] { return cached }
        let canonicalChainName: String = {
            if let cached = cachedCanonicalChainComponents[normalizedChainName] { return cached }
            let value = corePlanCanonicalChainComponent(chainName: normalizedChainName, symbol: "")
            cachedCanonicalChainComponents[normalizedChainName] = value
            return value
        }()
        let descriptor = nativeChainIconDescriptors.first { descriptor in
            descriptor.registryID.caseInsensitiveCompare(canonicalChainName) == .orderedSame
                || descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
        cachedChainNameDescriptors[normalizedChainName] = descriptor
        return descriptor
    }
    static func nativeChainIconDescriptor(symbol: String, chainName: String? = nil) -> NativeChainIconDescriptor? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChainName = chainName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cacheKey = "\(normalizedSymbol)|\(normalizedChainName)"
        if let cached = cachedSymbolDescriptors[cacheKey] { return cached }
        let descriptor = nativeChainIconDescriptors.first { descriptor in
            let symbolMatches = descriptor.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame
            guard symbolMatches else { return false }
            if normalizedChainName.isEmpty { return true }
            return descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
        cachedSymbolDescriptors[cacheKey] = descriptor
        return descriptor
    }
    static func nativeChainBadge(chainName: String) -> (assetIdentifier: String?, color: Color)? {
        guard let descriptor = nativeChainIconDescriptor(chainName: chainName) else { return nil }
        return (descriptor.assetIdentifier, descriptor.color)
    }
    static func iconIdentifier(symbol: String, chainName: String, contractAddress: String? = nil, tokenStandard: String = "Native")
        -> String
    {
        let cacheKey = "\(symbol)|\(chainName)|\(contractAddress ?? "")|\(tokenStandard)"
        if let cached = cachedIconIdentifiers[cacheKey] { return cached }
        let value = corePlanIconIdentifier(
            symbol: symbol, chainName: chainName, contractAddress: contractAddress, tokenStandard: tokenStandard)
        cachedIconIdentifiers[cacheKey] = value
        return value
    }
    static func normalizedIconIdentifier(_ identifier: String) -> String {
        if let cached = cachedNormalizedIconIdentifiers[identifier] { return cached }
        let value = corePlanNormalizedIconIdentifier(identifier: identifier)
        cachedNormalizedIconIdentifiers[identifier] = value
        return value
    }
    static func displayColor(for symbol: String) -> Color {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) { return nativeDescriptor.color }
        switch symbol {
        case "MATIC": return .indigo
        case "TRX": return .red
        case "ARB": return .cyan
        case "USDT": return .green
        default:
            if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) { return tokenEntry.color }
            return .gray
        }
    }
    var iconIdentifier: String {
        Self.iconIdentifier(symbol: symbol, chainName: chainName, contractAddress: contractAddress, tokenStandard: tokenStandard)
    }
    @MainActor init(snapshot: PersistedCoin) {
        self = Coin.makeCustom(
            name: snapshot.name, symbol: snapshot.symbol, coinGeckoId: snapshot.coinGeckoId,
            chainName: snapshot.chainName, tokenStandard: snapshot.tokenStandard, contractAddress: snapshot.contractAddress,
            amount: snapshot.amount, priceUsd: snapshot.priceUsd
        )
    }
    var persistedSnapshot: PersistedCoin {
        PersistedCoin(
            name: name, symbol: symbol, coinGeckoId: coinGeckoId, chainName: chainName,
            tokenStandard: tokenStandard, contractAddress: contractAddress, amount: amount, priceUsd: priceUsd
        )
    }
}
