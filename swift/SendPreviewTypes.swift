import Foundation

/// The per-chain facts an EVM send needs, sourced from the registry.
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

    var tokenHostingChain: TokenHostingChain? { TokenHostingChain.forChainName(displayName) }
    var defaultDerivationPath: String { derivationPath(account: 0) }
    func derivationPath(account: UInt32) -> String { "m/44\'/\(coinType)\'/\(account)\'/0/0" }
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
}

// Send preview types are now UniFFI-generated from Rust (core/src/wallet_core.rs).
// Swift owns only the send *result* types (not yet lifted) + chain-specific enums used by the UI.

struct EvmSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EvmSendPreview
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

extension SendPreview {
    /// The same preview, under the tag `SendPreviewStore` keys on.
    init(simple: SimpleChainPreview) {
        switch simple {
        case .solana(let p): self = .solana(preview: p)
        case .xrp(let p): self = .xrp(preview: p)
        case .stellar(let p): self = .stellar(preview: p)
        case .monero(let p): self = .monero(preview: p)
        case .cardano(let p): self = .cardano(preview: p)
        case .sui(let p): self = .sui(preview: p)
        case .aptos(let p): self = .aptos(preview: p)
        case .ton(let p): self = .ton(preview: p)
        case .icp(let p): self = .icp(preview: p)
        case .near(let p): self = .near(preview: p)
        case .polkadot(let p): self = .polkadot(preview: p)
        }
    }

    /// The estimated network fee, whichever shape the preview is.
    ///
    /// Every preview record carries one — the tags differ, the field does not.
    var estimatedNetworkFee: Double {
        switch self {
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
        }
    }
}

@MainActor
@Observable
final class SendPreviewStore {
    /// Every chain's latest preview, keyed by preview slot.
    ///
    /// The slot comes from `previewSlot(forChainNamed:)`, which asks the
    /// registry, so the EVM family shares Ethereum's without anyone naming its
    /// members.
    private(set) var previewBySlot: [String: SendPreview] = [:]

    func apply(_ preview: SendPreview?, forChainNamed chainName: String) {
        guard let slot = Self.previewSlot(forChainNamed: chainName) else { return }
        previewBySlot[slot] = preview
    }

    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        Self.previewSlot(forChainNamed: chainName).flatMap { previewBySlot[$0] }
    }

    /// A simple-chain preview arrives under its own tag; store it under the
    /// same slot as any other. The eleven-arm switch this replaces assigned to
    /// one of eleven fields, which is the field list written out a fifth time.
    func apply(_ preview: SimpleChainPreview?, forChainNamed chainName: String) {
        apply(preview.map(SendPreview.init(simple:)), forChainNamed: chainName)
    }

    func clearPreview(forChainNamed chainName: String) { apply(nil as SendPreview?, forChainNamed: chainName) }

    /// The estimated network fee a chain's preview reports, in its own units.
    ///
    /// Every preview record carries one; they used to spell it
    /// `estimatedNetworkFeeSui`, `…Apt`, `…Ton` and so on, so a caller that
    /// only wanted "the fee" had to know which chain it was asking about.
    func estimatedFee(forChainNamed chainName: String) -> Double? {
        taggedPreview(forChainNamed: chainName)?.estimatedNetworkFee
    }

    /// Which chain's preview slot `chainName` writes to — itself, or Ethereum
    /// for the EVM family, which shares one.
    static func previewSlot(forChainNamed chainName: String) -> String? {
        guard let chain = Chain(displayName: chainName) else { return nil }
        return chain.isEVM ? "Ethereum" : chainName
    }

    func resetAll() { previewBySlot.removeAll() }

    /// Clear every chain's preview but one.
    func resetAll(exceptChainNamed chainName: String?) {
        let kept = chainName.flatMap { Self.previewSlot(forChainNamed: $0) }
        previewBySlot = previewBySlot.filter { $0.key == kept }
    }

    // Typed accessors, for the six chains a caller reads a chain-specific
    // field off: Ethereum's nonce and gas, Bitcoin's sat/vB rate, Dogecoin's
    // max-sendable and change flag, Monero's priority label, Sui's gas budget,
    // Aptos's max gas, TON's sequence. Everything else goes through
    // `estimatedFee(forChainNamed:)`, which is why there are seven of these
    // rather than eighteen.
    var evmSendPreview: EvmSendPreview? {
        get { if case .ethereum(let p) = previewBySlot["Ethereum"] { p } else { nil } }
        set { previewBySlot["Ethereum"] = newValue.map { .ethereum(preview: $0) } }
    }
    var bitcoinSendPreview: BitcoinSendPreview? {
        get { if case .utxo(let p) = previewBySlot["Bitcoin"] { p } else { nil } }
        set { previewBySlot["Bitcoin"] = newValue.map { .utxo(preview: $0) } }
    }
    var bitcoinCashSendPreview: BitcoinSendPreview? {
        get { if case .utxo(let p) = previewBySlot["Bitcoin Cash"] { p } else { nil } }
        set { previewBySlot["Bitcoin Cash"] = newValue.map { .utxo(preview: $0) } }
    }
    var bitcoinSVSendPreview: BitcoinSendPreview? {
        get { if case .utxo(let p) = previewBySlot["Bitcoin SV"] { p } else { nil } }
        set { previewBySlot["Bitcoin SV"] = newValue.map { .utxo(preview: $0) } }
    }
    var litecoinSendPreview: BitcoinSendPreview? {
        get { if case .utxo(let p) = previewBySlot["Litecoin"] { p } else { nil } }
        set { previewBySlot["Litecoin"] = newValue.map { .utxo(preview: $0) } }
    }
    var dogecoinSendPreview: DogecoinSendPreview? {
        get { if case .dogecoin(let p) = previewBySlot["Dogecoin"] { p } else { nil } }
        set { previewBySlot["Dogecoin"] = newValue.map { .dogecoin(preview: $0) } }
    }
    var tronSendPreview: TronSendPreview? {
        get { if case .tron(let p) = previewBySlot["Tron"] { p } else { nil } }
        set { previewBySlot["Tron"] = newValue.map { .tron(preview: $0) } }
    }
    var solanaSendPreview: SolanaSendPreview? {
        get { if case .solana(let p) = previewBySlot["Solana"] { p } else { nil } }
        set { previewBySlot["Solana"] = newValue.map { .solana(preview: $0) } }
    }
    var xrpSendPreview: XrpSendPreview? {
        get { if case .xrp(let p) = previewBySlot["XRP Ledger"] { p } else { nil } }
        set { previewBySlot["XRP Ledger"] = newValue.map { .xrp(preview: $0) } }
    }
    var stellarSendPreview: StellarSendPreview? {
        get { if case .stellar(let p) = previewBySlot["Stellar"] { p } else { nil } }
        set { previewBySlot["Stellar"] = newValue.map { .stellar(preview: $0) } }
    }
    var moneroSendPreview: MoneroSendPreview? {
        get { if case .monero(let p) = previewBySlot["Monero"] { p } else { nil } }
        set { previewBySlot["Monero"] = newValue.map { .monero(preview: $0) } }
    }
    var cardanoSendPreview: CardanoSendPreview? {
        get { if case .cardano(let p) = previewBySlot["Cardano"] { p } else { nil } }
        set { previewBySlot["Cardano"] = newValue.map { .cardano(preview: $0) } }
    }
    var suiSendPreview: SuiSendPreview? {
        get { if case .sui(let p) = previewBySlot["Sui"] { p } else { nil } }
        set { previewBySlot["Sui"] = newValue.map { .sui(preview: $0) } }
    }
    var aptosSendPreview: AptosSendPreview? {
        get { if case .aptos(let p) = previewBySlot["Aptos"] { p } else { nil } }
        set { previewBySlot["Aptos"] = newValue.map { .aptos(preview: $0) } }
    }
    var tonSendPreview: TonSendPreview? {
        get { if case .ton(let p) = previewBySlot["TON"] { p } else { nil } }
        set { previewBySlot["TON"] = newValue.map { .ton(preview: $0) } }
    }
}
