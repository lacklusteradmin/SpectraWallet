import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
typealias TokenHostingChain = CoreTokenHostingChain
// Do not add `RawRepresentable`: its default equality and hashing use
// `rawValue`, which reads a table keyed by this enum. That recurses during
// table initialization. Keep the generated `Hashable` conformance.
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
    /// Chains in catalog order.
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
    var tokenStandard: String { chain?.entry?.tokenStandard ?? "" }
    var filterDisplayName: String { "\(rawValue) (\(tokenStandard))" }
    var contractAddressPrompt: String { chain?.entry?.contractAddressPrompt ?? "Contract Address" }
    static func forChainName(_ chainName: String) -> TokenHostingChain? {
        let normalized = chainName.trimmingCharacters(in: .whitespacesAndNewlines)
        return byNormalizedName[normalized.lowercased()]
    }
    private static let byNormalizedName: [String: TokenHostingChain] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.rawValue.lowercased(), $0) }
    )
}
typealias TokenPreferenceEntry = CoreTokenPreferenceEntry
nonisolated extension CoreTokenPreferenceEntry: Identifiable {
    /// A token's identity is its contract on its chain.
    public var id: String { "\(token.chain)|\(token.contract)" }
    /// The chain enum, where the registry has one for this chain.
    var hostingChain: TokenHostingChain? { TokenHostingChain.forChainName(token.chain) }
}

extension Coin {
    /// A chain's network artwork and catalog colour.
    static func nativeChainBadge(chainName: String) -> (artworkName: String?, color: Color)? {
        guard let chain = Chain(displayName: chainName), let entry = chain.entry else { return nil }
        return (coreNetworkArtworkName(networkId: chain.id), entry.color.color)
    }
    /// A symbol's colour: the first chain in the catalog that pays fees in it,
    /// then the built-in token that has it, then grey.
    private static let colorsBySymbol: [String: Color] = {
        var colors: [String: Color] = [:]
        for entry in Chain.all.compactMap(\.entry) where colors[entry.gasTokenSymbol.lowercased()] == nil {
            colors[entry.gasTokenSymbol.lowercased()] = entry.color.color
        }
        for token in listAllBuiltinTokens() where colors[token.symbol.lowercased()] == nil {
            if let color = token.color { colors[token.symbol.lowercased()] = color.color }
        }
        return colors
    }()
    static func displayColor(for symbol: String) -> Color {
        colorsBySymbol[symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? .gray
    }
    var artworkName: String { coreHoldingArtworkName(holding: self) }

}
