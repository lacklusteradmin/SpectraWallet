import Foundation

/// The app's one chain type.
///
/// `Chain` is generated from `registry::Chain`, which is declared in the order
/// of `core/data/chains.toml`. Everything a call site used to read off a
/// hand-written Swift enum — the string id, the display name, the native
/// symbol, whether the chain is EVM — is a column of that catalog and is read
/// from it here.
extension Chain: Identifiable {
    /// Every chain, in catalog order.
    static let all: [Chain] = identities.map(\.chain)

    /// Only the chains that are not testnets. Ordered as the catalog is.
    static let mainnets: [Chain] = identities.filter { !$0.isTestnet }.map(\.chain)

    /// The chains the staking tab lists. Was `StakingSupportedChain`, a
    /// seven-case enum with a display-name switch and an id switch over facts
    /// this table already held — the fifth Swift enum to restate the chain
    /// list, and the one the earlier sweep missed because it is scoped to one
    /// tab rather than to the app.
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
    /// Which `TokenHostingChain` this chain is, if it can host known tokens.
    var tokenHostingChain: TokenHostingChain? { identity?.tokenHostingChain }
    var sendExecutionShape: SendExecutionShape? { identity?.sendExecutionShape }
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

    /// True when this chain's family offers more than one network.
    var hasNetworkChoice: Bool { networkChoices.count > 1 }

    /// This chain's catalog row. `nil` only if the enum and the catalog have
    /// drifted, which core's `chain_order_matches_the_catalog` fails on.
    var entry: ChainEntry? { Self.entryByChain[self] }

    /// The chain's own ticker — `ARB` on Arbitrum.
    var symbol: String { entry?.symbol ?? "" }
    /// The asset fees are paid in — `ETH` on Arbitrum. Distinct from `symbol`
    /// on every L2, and it is this one that says whether a holding is native.
    var gasTokenSymbol: String { entry?.gasTokenSymbol ?? "" }

    /// The chain's native asset decimals, from the catalog.
    var nativeDecimals: UInt32 { entry?.nativeDecimals ?? 8 }

    /// A terse example of what an address on this chain looks like, or "" for
    /// a chain the catalog has no example for.
    var addressPrefixHint: String { entry?.addressPrefixHint ?? "" }
    var isEVM: Bool { identity?.isEvm ?? false }
    var searchKeywords: [String] { entry?.searchKeywords ?? [] }

    /// The catalog's default BIP-32 path for account 0. Empty for chains that
    /// have no path at all — Monero derives from the seed directly.
    @MainActor var defaultDerivationPath: String {
        CachedCoreHelpers.chainDerivationPath(chainName: displayName)
    }

    /// Whether this chain's addresses are its own rather than another chain's.
    ///
    /// The EVM family shares one derived address, filed under Ethereum's slot,
    /// so `Arbitrum` answers `false` here while `Ethereum` and
    /// `Ethereum Classic` answer `true`. Anything that indexes addresses per
    /// chain — keypools, owned-address registration — wants the owners.
    var ownsItsAddressSlot: Bool { addressSlot == id }

    /// Which history-record shape this chain's diagnostics screen reads.
    var diagnosticsShape: DiagnosticsShape { identity?.diagnosticsShape ?? .simple }

    init?(id: String) {
        guard let chain = Self.chainByID[id] else { return nil }
        self = chain
    }

    init?(displayName: String) {
        guard let chain = Self.chainByName[displayName] else { return nil }
        self = chain
    }
}
