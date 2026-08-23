import Foundation

/// The per-chain facts an EVM send needs, sourced from the registry.
///
/// This was an enum with a case per chain and five switches over it —
/// `displayName`, `tokenTrackingChain`, `expectedChainID`, the derivation path
/// and `isEthereumFamily`. It covered 15 of the 23 EVM mainnets, so
/// `isEVMChain` answered *false* for Sei, Celo, Cronos, opBNB, zkSync Era,
/// Sonic, Berachain, Unichain, Ink and X Layer, and every EVM path skipped
/// them without saying so.
///
/// It is a struct now, built from `coreEvmChainContext`. Adding an EVM chain is
/// a registry edit and nothing here changes. The named statics are kept so the
/// existing `EVMChainContext.arbitrum` call sites read the same.
struct EVMChainContext: Equatable {
    let displayName: String
    /// EIP-155 chain id, checked against what the RPC reports before signing.
    let expectedChainID: Int
    /// BIP-44 coin type: 60 for the Ethereum family, 61 for Ethereum Classic.
    let coinType: UInt32
    let isEthereumFamily: Bool
    let isEthereumMainnet: Bool

    /// `nil` when the chain is not an EVM chain the registry knows.
    init?(chainName: String) {
        guard let info = coreEvmChainContext(chainName: chainName) else { return nil }
        displayName = info.displayName
        expectedChainID = Int(info.chainId)
        coinType = info.coinType
        isEthereumFamily = info.isEthereumFamily
        isEthereumMainnet = info.isEthereumMainnet
    }

    // Fifteen `static var <chain>: EVMChainContext` accessors stood here,
    // "kept so the existing `EVMChainContext.arbitrum` call sites read the
    // same". Those call sites are gone — two test assertions were the only
    // readers left, and they name the chain themselves now. A per-chain
    // accessor on a type whose whole point is that it is built from the
    // registry is the shape this file's own header describes as the bug.

    var tokenTrackingChain: TokenTrackingChain? { TokenTrackingChain.forChainName(displayName) }
    var defaultDerivationPath: String { derivationPath(account: 0) }
    func derivationPath(account: UInt32) -> String { "m/44\'/\(coinType)\'/\(account)\'/0/0" }
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
}

// Send preview types are now UniFFI-generated from Rust (core/src/wallet_core.rs).
// Swift owns only the send *result* types (not yet lifted) + chain-specific enums used by the UI.

struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}

enum LitecoinChangeStrategy: String, CaseIterable, Identifiable {
    case derivedChange
    case reuseSourceAddress
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .derivedChange: return "Derived change address"
        case .reuseSourceAddress: return "Reuse source address"
        }
    }
}
enum SolanaDerivationPreference {
    case standard
    case legacy
}

// MARK: - EVM address utilities (moved from Send/Engines/EVM/)

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid EVM address."
        case .invalidResponse: return "Unexpected response from EVM provider."
        case .rpcFailure(let detail): return detail
        }
    }
}
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard AddressValidation.isValid(normalized, kind: "evm") else { throw EthereumWalletEngineError.invalidAddress }
    return normalized
}
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}

@MainActor
@Observable
final class SendPreviewStore {
    var ethereumSendPreview: EthereumSendPreview?
    var bitcoinSendPreview: BitcoinSendPreview?
    var bitcoinCashSendPreview: BitcoinSendPreview?
    var bitcoinSVSendPreview: BitcoinSendPreview?
    var litecoinSendPreview: BitcoinSendPreview?
    var dogecoinSendPreview: DogecoinSendPreview?
    var tronSendPreview: TronSendPreview?
    var solanaSendPreview: SolanaSendPreview?
    var xrpSendPreview: XrpSendPreview?
    var stellarSendPreview: StellarSendPreview?
    var moneroSendPreview: MoneroSendPreview?
    var cardanoSendPreview: CardanoSendPreview?
    var suiSendPreview: SuiSendPreview?
    var aptosSendPreview: AptosSendPreview?
    var tonSendPreview: TonSendPreview?
    var icpSendPreview: IcpSendPreview?
    var nearSendPreview: NearSendPreview?
    var polkadotSendPreview: PolkadotSendPreview?

    /// Store a freshly fetched preview under its chain, or clear it.
    ///
    /// The per-chain `applyPreview` closures each did this for one chain, with
    /// an `if case` that had to match the tag by hand.
    func apply(_ preview: SendPreview?, forChainNamed chainName: String) {
        switch chainName {
        case "Bitcoin": bitcoinSendPreview = preview.flatMap { if case .utxo(let p) = $0 { p } else { nil } }
        case "Bitcoin Cash": bitcoinCashSendPreview = preview.flatMap { if case .utxo(let p) = $0 { p } else { nil } }
        case "Bitcoin SV": bitcoinSVSendPreview = preview.flatMap { if case .utxo(let p) = $0 { p } else { nil } }
        case "Litecoin": litecoinSendPreview = preview.flatMap { if case .utxo(let p) = $0 { p } else { nil } }
        case "Dogecoin": dogecoinSendPreview = preview.flatMap { if case .dogecoin(let p) = $0 { p } else { nil } }
        case "Tron": tronSendPreview = preview.flatMap { if case .tron(let p) = $0 { p } else { nil } }
        case "Solana": solanaSendPreview = preview.flatMap { if case .solana(let p) = $0 { p } else { nil } }
        case "XRP Ledger": xrpSendPreview = preview.flatMap { if case .xrp(let p) = $0 { p } else { nil } }
        case "Stellar": stellarSendPreview = preview.flatMap { if case .stellar(let p) = $0 { p } else { nil } }
        case "Monero": moneroSendPreview = preview.flatMap { if case .monero(let p) = $0 { p } else { nil } }
        case "Cardano": cardanoSendPreview = preview.flatMap { if case .cardano(let p) = $0 { p } else { nil } }
        case "Sui": suiSendPreview = preview.flatMap { if case .sui(let p) = $0 { p } else { nil } }
        case "Aptos": aptosSendPreview = preview.flatMap { if case .aptos(let p) = $0 { p } else { nil } }
        case "TON": tonSendPreview = preview.flatMap { if case .ton(let p) = $0 { p } else { nil } }
        case "Internet Computer": icpSendPreview = preview.flatMap { if case .icp(let p) = $0 { p } else { nil } }
        case "NEAR": nearSendPreview = preview.flatMap { if case .near(let p) = $0 { p } else { nil } }
        case "Polkadot": polkadotSendPreview = preview.flatMap { if case .polkadot(let p) = $0 { p } else { nil } }
        default:
            guard (Chain(displayName: chainName)?.isEVM ?? false) else { return }
            ethereumSendPreview = preview.flatMap { if case .ethereum(let p) = $0 { p } else { nil } }
        }
    }
    /// Same, for the narrower enum the simple-chain refresher returns.
    func apply(_ preview: SimpleChainPreview?, forChainNamed chainName: String) {
        switch preview {
        case .solana(let p): solanaSendPreview = p
        case .xrp(let p): xrpSendPreview = p
        case .stellar(let p): stellarSendPreview = p
        case .monero(let p): moneroSendPreview = p
        case .cardano(let p): cardanoSendPreview = p
        case .sui(let p): suiSendPreview = p
        case .aptos(let p): aptosSendPreview = p
        case .ton(let p): tonSendPreview = p
        case .icp(let p): icpSendPreview = p
        case .near(let p): nearSendPreview = p
        case .polkadot(let p): polkadotSendPreview = p
        case .none: clearPreview(forChainNamed: chainName)
        }
    }
    func clearPreview(forChainNamed chainName: String) { apply(nil as SendPreview?, forChainNamed: chainName) }

    /// The estimated network fee a chain's preview reports, in its own units.
    ///
    /// Every preview record carries one; they used to spell it
    /// `estimatedNetworkFeeSui`, `…Apt`, `…Ton` and so on, so a caller that
    /// only wanted "the fee" had to know which chain it was asking about.
    /// The field is `estimatedNetworkFee` on all of them now.
    func estimatedFee(forChainNamed chainName: String) -> Double? {
        switch taggedPreview(forChainNamed: chainName) {
        case .utxo(let p): return p.estimatedNetworkFee
        case .dogecoin(let p): return p.estimatedNetworkFee
        case .tron(let p): return p.estimatedNetworkFee
        case .solana(let p): return p.estimatedNetworkFee
        case .xrp(let p): return p.estimatedNetworkFee
        case .stellar(let p): return p.estimatedNetworkFee
        case .monero(let p): return p.estimatedNetworkFee
        case .cardano(let p): return p.estimatedNetworkFee
        case .sui(let p): return p.estimatedNetworkFee
        case .aptos(let p): return p.estimatedNetworkFee
        case .ton(let p): return p.estimatedNetworkFee
        case .icp(let p): return p.estimatedNetworkFee
        case .near(let p): return p.estimatedNetworkFee
        case .polkadot(let p): return p.estimatedNetworkFee
        case .ethereum(let p): return p.estimatedNetworkFee
        case .none: return nil
        }
    }

    /// The preview to hand Rust for `chainName`, tagged with its shape.
    ///
    /// Rust used to receive all eighteen previews and select one by matching on
    /// the chain name — a match that carried its own EVM chain list and had
    /// gone stale. Tagging at the source means only the relevant preview
    /// crosses the FFI, and EVM membership is asked of the registry.
    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        switch chainName {
        case "Bitcoin": return bitcoinSendPreview.map { .utxo(preview: $0) }
        case "Bitcoin Cash": return bitcoinCashSendPreview.map { .utxo(preview: $0) }
        case "Bitcoin SV": return bitcoinSVSendPreview.map { .utxo(preview: $0) }
        case "Litecoin": return litecoinSendPreview.map { .utxo(preview: $0) }
        case "Dogecoin": return dogecoinSendPreview.map { .dogecoin(preview: $0) }
        case "Tron": return tronSendPreview.map { .tron(preview: $0) }
        case "Solana": return solanaSendPreview.map { .solana(preview: $0) }
        case "XRP Ledger": return xrpSendPreview.map { .xrp(preview: $0) }
        case "Stellar": return stellarSendPreview.map { .stellar(preview: $0) }
        case "Monero": return moneroSendPreview.map { .monero(preview: $0) }
        case "Cardano": return cardanoSendPreview.map { .cardano(preview: $0) }
        case "Sui": return suiSendPreview.map { .sui(preview: $0) }
        case "Aptos": return aptosSendPreview.map { .aptos(preview: $0) }
        case "TON": return tonSendPreview.map { .ton(preview: $0) }
        case "Internet Computer": return icpSendPreview.map { .icp(preview: $0) }
        case "NEAR": return nearSendPreview.map { .near(preview: $0) }
        case "Polkadot": return polkadotSendPreview.map { .polkadot(preview: $0) }
        default:
            // Every EVM chain shares one preview. Asking the registry rather
            // than listing them is what fixes Base, Polygon, Linea, Scroll,
            // Blast, Mantle and the newer rollups, which the old name match
            // never reached.
            guard (Chain(displayName: chainName)?.isEVM ?? false) else { return nil }
            return ethereumSendPreview.map { .ethereum(preview: $0) }
        }
    }

    /// Which chain's preview slot `chainName` writes to — itself, or Ethereum
    /// for the EVM family, which shares one. The same rule `apply` and
    /// `taggedPreview` dispatch on, named so callers can ask for it.
    static func previewSlot(forChainNamed chainName: String) -> String? {
        guard let chain = Chain(displayName: chainName) else { return nil }
        return chain.isEVM ? "Ethereum" : chainName
    }

    /// Clear every chain's preview but one.
    ///
    /// Was eighteen `if activePreview != .x { store.xSendPreview = nil }` blocks
    /// in `AppState+SendRouting`, which is this store's field list written out a
    /// second time — and written in terms of a preview *kind* while the store
    /// keys on a chain, so the EVM family's shared slot had to be reasoned
    /// about at every site. Keeping one and resetting the rest is the same
    /// thing said once.
    func resetAll(exceptChainNamed chainName: String?) {
        let kept = chainName.flatMap { taggedPreview(forChainNamed: $0) }
        resetAll()
        if let kept, let chainName { apply(kept, forChainNamed: chainName) }
    }

    func resetAll() {
        ethereumSendPreview = nil
        bitcoinSendPreview = nil
        bitcoinCashSendPreview = nil
        bitcoinSVSendPreview = nil
        litecoinSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        stellarSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        aptosSendPreview = nil
        tonSendPreview = nil
        icpSendPreview = nil
        nearSendPreview = nil
        polkadotSendPreview = nil
    }
}
