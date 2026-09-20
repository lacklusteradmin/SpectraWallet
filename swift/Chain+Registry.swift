import Foundation

/// `Chain` is generated from `registry::Chain` in `core/data/chains.toml` order.
/// Its identity, display name, symbol, and capabilities come from that catalog.
extension Chain: Identifiable {
    /// Every chain, in catalog order.
    static let all: [Chain] = identities.map(\.chain)

    /// Only the chains that are not testnets. Ordered as the catalog is.
    static let mainnets: [Chain] = identities.filter { !$0.isTestnet }.map(\.chain)

    /// Chains with staking support, as declared by the registry.
    static let stakingChains: [Chain] = identities.filter(\.supportsStaking).map(\.chain)

    private static let identities: [ChainIdentity] = coreChainIdentities()
    private static let identityByChain: [Chain: ChainIdentity] = Dictionary(
        uniqueKeysWithValues: identities.map { ($0.chain, $0) })
    private static let chainByID: [String: Chain] = Dictionary(
        uniqueKeysWithValues: identities.map { ($0.id, $0.chain) })
    private static let chainByName: [String: Chain] = Dictionary(
        uniqueKeysWithValues: identities.map { ($0.name, $0.chain) })
    private static let entryByChain: [Chain: ChainEntry] = {
        let byID = Dictionary(uniqueKeysWithValues: listAllChains().map { ($0.id, $0) })
        return identities.reduce(into: [:]) { out, identity in
            if let entry = byID[identity.id] { out[identity.chain] = entry }
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
    /// Which endpoint slot this chain's supplemental explorer endpoints go in.
    var supplementalEndpointSlot: AppCoreEndpointSlot {
        identity?.supplementalEndpointSlot ?? .explorer
    }
    /// Which `TokenHostingChain` this chain is, if it can host known tokens.
    var tokenHostingChain: TokenHostingChain? { identity?.tokenHostingChain }
    var sendExecutionShape: SendExecutionShape? { identity?.sendExecutionShape }
    /// How core moves a send here, which is what the send card says it does.
    var sendBroadcastMode: SendBroadcastMode? { identity?.sendBroadcastMode }
    /// Core's sends here go through the configured backend, which is what the
    /// backend URL and key settings are for.
    var sendsThroughBackend: Bool { sendBroadcastMode == .preparesWithBackend }
    /// This chain's history needs the Etherscan key.
    var needsEtherscanAPIKey: Bool { identity?.needsEtherscanApiKey ?? false }
    /// The JSON-RPC method that answers "is this node alive", or nil when this
    /// chain's endpoints are checked over plain HTTP.
    var rpcHealthMethod: String? { identity?.rpcHealthMethod }
    var pendingStatusPoll: PendingStatusPoll? { identity?.pendingStatusPoll }
    /// Which chain's derivation path this chain reuses, as a display name.
    var seedDerivationChain: String? { identity?.seedDerivationChain }
    /// The EVM chain whose derivation this chain reuses.
    var evmSeedDerivationChain: String? { identity?.evmSeedDerivationChain }
    /// The mainnet this chain belongs to, or itself.
    var mainnetCounterpart: Chain { identity?.mainnetCounterpart ?? self }
    /// Where a configured derivation path for this chain is stored. Testnets
    /// share their mainnet's slot, which is what that says.
    var seedDerivationPathKey: String { mainnetCounterpart.id }
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
    /// a testnet answers with its mainnet's path, which is the one it derives
    /// on. Empty for chains that have no path at all — Monero derives from the
    /// seed directly.
    ///
    /// Was a second resolver in Swift that picked the default entry, replaced
    /// `{account}` and checked for `m/` itself, and answered "" for every
    /// testnet because the catalog lists their paths on the mainnet.
    var defaultDerivationPath: String {
        (try? appCoreResolveDerivationPath(chain: displayName, derivationPath: "")) ?? ""
    }

    init?(id: String) {
        guard let chain = Self.chainByID[id] else { return nil }
        self = chain
    }

    init?(displayName: String) {
        guard let chain = Self.chainByName[displayName] else { return nil }
        self = chain
    }
}
