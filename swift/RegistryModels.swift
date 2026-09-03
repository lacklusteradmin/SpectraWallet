import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
struct WalletChainID: Hashable, Codable, Identifiable, Comparable {
    let rawValue: String
    static func == (lhs: WalletChainID, rhs: WalletChainID) -> Bool { lhs.rawValue == rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
    var id: String { rawValue }
    var displayName: String { Self.displayNameByID[rawValue] ?? rawValue }
    init(rawValue: String) { self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    init?(_ chainNameOrID: String) {
        let trimmed = chainNameOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.init(rawValue: coreResolveChainId(input: trimmed))
    }
    static func resolved(_ chainNameOrID: String) -> WalletChainID {
        WalletChainID(chainNameOrID) ?? WalletChainID(rawValue: chainNameOrID)
    }
    static func < (lhs: WalletChainID, rhs: WalletChainID) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
    private static let displayNameByID: [String: String] = Dictionary(
        uniqueKeysWithValues: listAllChains()
            .filter { !$0.name.isEmpty }
            .map { ($0.id.lowercased(), $0.name) }
    )
}
typealias TokenHostingChain = CoreTokenHostingChain
// Deliberately **not** `RawRepresentable`, though it has a `rawValue`.
//
// `RawRepresentable` supplies default `==` and `hash(into:)` that route through
// `rawValue`, and those defaults win over the conformance UniFFI generates. That
// was harmless while `rawValue` was a self-contained switch and fatal the moment
// it read a table keyed by this enum: `chainByHosting`'s own initializer hashed
// its keys, which called `rawValue`, which waited on the `dispatch_once` it was
// inside. The app trapped in `_dispatch_once_wait` before the first frame.
//
// Dropping the conformance keeps every `.rawValue` call site working and leaves
// hashing to the generated `Hashable`.
extension CoreTokenHostingChain: CaseIterable, Codable, Identifiable {
    // The mapping is the registry's. `chain_name` and `from_chain_name` in
    // `wallet_domain.rs` already collapsed four Rust copies of it into one, and
    // this file held three more — an eighteen-arm `init?(rawValue:)`, an
    // eighteen-arm `rawValue` and an eighteen-entry `allCases`, for an enum core
    // owns. They are a column of `core_chain_identities` now, so adding a chain
    // that hosts tokens is a registry edit and nothing here changes.
    private static let chainByHosting: [CoreTokenHostingChain: Chain] = Dictionary(
        uniqueKeysWithValues: Chain.all.compactMap { chain in
            chain.tokenHostingChain.map { ($0, chain) }
        })
    private static let hostingByName: [String: CoreTokenHostingChain] = Dictionary(
        uniqueKeysWithValues: chainByHosting.map { ($0.value.displayName, $0.key) })
    public init?(rawValue: String) {
        guard let hosting = Self.hostingByName[rawValue] else { return nil }
        self = hosting
    }
    public var rawValue: String { chain?.displayName ?? "" }

    /// The registry chain this hosting chain is. Every fact about it —
    /// display name, id, colour — comes from here rather than a switch.
    public var chain: Chain? { Self.chainByHosting[self] }
    /// In catalog order, which is the order every other chain list in the app
    /// uses. The hand-written array this replaces had its own ordering.
    public static var allCases: [CoreTokenHostingChain] { Chain.all.compactMap(\.tokenHostingChain) }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let v = CoreTokenHostingChain(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown TokenHostingChain: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var id: String { rawValue }
    var tokenStandard: String {
        Self.chainEntryByName[rawValue.lowercased()]?.tokenStandard ?? ""
    }
    var filterDisplayName: String { "\(rawValue) (\(tokenStandard))" }
    var slug: String {
        switch self {
        case .bnb: return "bnb"
        default: return rawValue.lowercased()
        }
    }
    var contractAddressPrompt: String {
        Self.chainEntryByName[rawValue.lowercased()]?.contractAddressPrompt ?? "Contract Address"
    }
    static func forChainName(_ chainName: String) -> TokenHostingChain? {
        let normalized = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        return byNormalizedName[normalized.lowercased()]
    }
    private static let byNormalizedName: [String: TokenHostingChain] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.rawValue.lowercased(), $0) }
    )
    private static let chainEntryByName: [String: ChainEntry] = {
        var dict: [String: ChainEntry] = [:]
        for entry in listAllChains() where !entry.tokenStandard.isEmpty {
            dict[entry.name.lowercased()] = entry
        }
        return dict
    }()
}
struct ChainRegistryEntry: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let color: Color
    let assetName: String
    let derivationPath: [ChainDerivationPathEntry]
    var assetIdentifier: String { Coin.iconIdentifier(symbol: symbol, chainName: name) }
    var nativeIconDescriptor: NativeChainIconDescriptor {
        NativeChainIconDescriptor(
            registryID: id, title: name, symbol: symbol, chainName: name, color: color, assetName: assetName
        )
    }
    static let all: [ChainRegistryEntry] = {
        listAllChains()
            .filter { !$0.name.isEmpty }
            .map { chain in
                ChainRegistryEntry(
                    id: chain.id, name: chain.name, symbol: chain.symbol,
                    color: RegistryColorLookup.color(named: chain.color), assetName: chain.assetName,
                    derivationPath: chain.derivationPath
                )
            }
    }()
    private static let entriesByLowercasedID: [String: ChainRegistryEntry] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id.lowercased(), $0) })
    static func entry(id: String) -> ChainRegistryEntry? {
        entriesByLowercasedID[id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}
struct TokenVisualRegistryEntry: Identifiable {
    let title: String
    let symbol: String
    let referenceChain: TokenHostingChain
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
    static func entry(matchingAssetIdentifier assetIdentifier: String) -> TokenVisualRegistryEntry? {
        let normalized = assetIdentifier.lowercased()
        return assetIdentifierFragments.first { normalized.contains($0.fragment) }?.entry
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
nonisolated extension CoreTokenPreferenceEntry: Identifiable {
    /// A token *is* its contract on its chain. The id was a stored UUID string,
    /// regenerated whenever an entry was rebuilt.
    public var id: String { "\(token.chain)|\(token.contract)" }
    /// The chain enum, where the registry has one for this chain.
    var hostingChain: TokenHostingChain? { TokenHostingChain.forChainName(token.chain) }
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
    private static let nativeIconAssetNameByAssetIdentifier: [String: String] = {
        var result: [String: String] = [:]
        for entry in listAllChains() where !entry.assetName.isEmpty && !entry.name.isEmpty {
            let key = iconIdentifier(symbol: entry.symbol, chainName: entry.name)
            result[key] = entry.assetName
        }
        return result
    }()
    static func nativeIconAssetName(forAssetIdentifier assetIdentifier: String) -> String? {
        nativeIconAssetNameByAssetIdentifier[assetIdentifier]
    }
    static func nativeChainIconDescriptor(forAssetIdentifier assetIdentifier: String) -> NativeChainIconDescriptor? {
        nativeChainIconDescriptorByAssetIdentifier[assetIdentifier]
    }
    static func nativeChainIconDescriptor(chainName: String) -> NativeChainIconDescriptor? {
        let normalizedChainName = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedChainName.isEmpty else { return nil }
        let canonicalChainName = coreCanonicalChainComponent(chainName: normalizedChainName, symbol: "")
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
            if normalizedChainName.isEmpty { return true }
            return descriptor.chainName.caseInsensitiveCompare(normalizedChainName) == .orderedSame
                || descriptor.title.caseInsensitiveCompare(normalizedChainName) == .orderedSame
        }
    }
    static func nativeChainBadge(chainName: String) -> (assetIdentifier: String?, color: Color)? {
        guard let descriptor = nativeChainIconDescriptor(chainName: chainName) else { return nil }
        return (descriptor.assetIdentifier, descriptor.color)
    }
    static func iconIdentifier(symbol: String, chainName: String, contractAddress: String? = nil, tokenStandard: String = "Native")
        -> String
    {
        coreIconIdentifier(
            symbol: symbol, chainName: chainName, contractAddress: contractAddress, tokenStandard: tokenStandard)
    }
    static func normalizedIconIdentifier(_ identifier: String) -> String {
        coreNormalizedIconIdentifier(identifier: identifier)
    }
    /// A coin's colour, from whichever catalog vouches for it.
    ///
    /// Four hardcoded symbols stood between these two lookups. `MATIC` is in
    /// neither catalog since POL replaced it; `ARB` could never be reached,
    /// because the chain descriptor above matches Arbitrum first; and `TRX`
    /// and `USDT` restated the colour the catalog already gives, `red` and
    /// `green`. Four arms, none of them doing anything the catalogs do not.
    static func displayColor(for symbol: String) -> Color {
        if let nativeDescriptor = nativeChainIconDescriptor(symbol: symbol) { return nativeDescriptor.color }
        if let tokenEntry = TokenVisualRegistryEntry.entry(symbol: symbol) { return tokenEntry.color }
        return .gray
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

// MARK: ─ (merged from ChainBackendModels.swift)

struct ChainBroadcastProviderOption: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
}
