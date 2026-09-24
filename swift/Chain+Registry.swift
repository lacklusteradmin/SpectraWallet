import Foundation

/// `Chain` is generated from `registry::Chain` in `core/data/chains.toml` order.
/// Its identity, display name, symbol, and capabilities come from that catalog.
extension Chain: Identifiable {
    /// Every chain, in catalog order.
    static let all: [Chain] = identities.map(\.chain)

    /// Only the chains that are not testnets. Ordered as the catalog is.
    static let mainnets: [Chain] = identities.filter { !$0.isTestnet }.map(\.chain)

    /// Chains that can hold tracked tokens, in catalog order.
    static let tokenHostingChains: [Chain] = all.filter(\.hostsTokens)

    /// Chains with staking support, as declared by the registry.
    static let stakingChains: [Chain] = identities.filter(\.supportsStaking).map(\.chain)

    private static let identities: [ChainIdentity] = chainIdentities()
    private static let identityByChain: [Chain: ChainIdentity] = Dictionary(
        uniqueKeysWithValues: identities.map { ($0.chain, $0) })
    private static let chainById: [String: Chain] = Dictionary(
        uniqueKeysWithValues: identities.map { ($0.id, $0.chain) })
    private static let entryByChain: [Chain: ChainEntry] = {
        let byId = Dictionary(uniqueKeysWithValues: listAllChains().map { ($0.id, $0) })
        return identities.reduce(into: [:]) { out, identity in
            if let entry = byId[identity.id] { out[identity.chain] = entry }
        }
    }()

    private var identity: ChainIdentity? { Self.identityByChain[self] }

    /// The catalog's stable `id` — `"bitcoin"`, `"bitcoin-cash"`, `"bnb"`.
    /// This is what crosses the FFI boundary and what endpoint tables key on.
    public var id: String { identity?.id ?? "" }

    /// The catalog's `name` — `"Bitcoin Cash"`, `"XRP Ledger"`, `"BNB Chain"`.
    /// One spelling per chain: the registry has a test that says so.
    var displayName: String { identity?.name ?? "" }

    var isTestnet: Bool { identity?.isTestnet ?? false }

    // ── Columns of the identity table ─────────────────────────────────────

    /// Which chain's slot this chain's address is stored under. The EVM family
    /// shares Ethereum's.
    var addressSlot: String { identity?.addressSlot ?? "" }
    /// The address format family validation dispatches on.
    var addressValidationKind: String { identity?.addressValidationKind ?? "" }
    /// HD discovery walks this chain's addresses past the last used one.
    var supportsDeepUTXODiscovery: Bool { identity?.supportsDeepUtxoDiscovery ?? false }
    /// A watch-only import can carry addresses for this chain.
    var supportsWatchOnlyImport: Bool { identity?.supportsWatchOnlyImport ?? false }

    /// A private key alone yields an address on this chain.
    var derivesFromPrivateKey: Bool { identity?.derivesFromPrivateKey ?? false }
    /// The chain has protocol-native staking the staking tab can drive.
    var supportsStaking: Bool { identity?.supportsStaking ?? false }
    /// The send screen has a network card to show for this chain.
    var hasSendPreview: Bool { identity?.hasSendPreview ?? false }
    /// The chain can hold tracked tokens.
    var hostsTokens: Bool { identity?.hostsTokens ?? false }
    /// How core moves a send here, which is what the send card says it does.
    var sendBroadcastMode: SendBroadcastMode? { identity?.sendBroadcastMode }
    /// The mainnet this chain belongs to, or itself.
    var mainnetCounterpart: Chain { identity?.mainnetCounterpart ?? self }
    /// Paths are stored under the concrete network ID.
    var seedDerivationPathKey: String { id }
    /// The networks this chain's family offers, mainnet first.
    var networkChoices: [NetworkChoice] { identity?.networkChoices ?? [] }

    /// This chain's catalog row. `nil` only if the enum and the catalog have
    /// drifted, which core's `chain_order_matches_the_catalog` fails on.
    var entry: ChainEntry? { Self.entryByChain[self] }

    /// The network’s native token symbol, derived by core.
    var gasTokenSymbol: String { entry?.gasTokenSymbol ?? "" }

    /// The chain's native asset decimals, from the catalog.
    var nativeDecimals: UInt32 { entry?.nativeDecimals ?? 8 }

    /// A terse example of what an address on this chain looks like, or "" for
    /// a chain the catalog has no example for.
    var addressPrefixHint: String { entry?.addressPrefixHint ?? "" }
    var isEVM: Bool { identity?.isEvm ?? false }
    var searchKeywords: [String] { entry?.searchKeywords ?? [] }

    /// The catalog's default BIP-32 path for account 0, as core resolves it:
    /// each network supplies its own path. Empty for chains with no path —
    /// Monero derives from the seed directly.
    ///
    var defaultDerivationPath: String {
        (try? resolveDerivationPath(chainId: id, derivationPath: "")) ?? ""
    }

    init?(id: String) {
        guard let chain = Self.chainById[id] else { return nil }
        self = chain
    }

    /// The display name for a chain id. Identity crosses the boundary as the
    /// id; this is only for text a person reads. An unknown id shows as itself.
    static func displayName(forId id: String) -> String {
        Chain(id: id)?.displayName ?? id
    }
}
