import Foundation

// Preview types are UniFFI-generated from `core/src/send/`. What is left here
// is the send *result* types and the chain-specific enums the UI switches on.


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

extension SendPreview {
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
        case .bittensor(let p): return p.estimatedNetworkFee
        case .ethereum(let p): return p.estimatedNetworkFee
        }
    }
}

@MainActor
@Observable
final class SendPreviewStore {
    /// Every chain's latest preview, keyed by the chain's mainnet id.
    ///
    /// The mainnet because the two writers name one chain two ways: a refresh
    /// names the holding's chain ("Bitcoin"), a review names the network it
    /// resolved ("Bitcoin Testnet4"), and they must land in one slot. The EVM
    /// family used to share Ethereum's slot instead, read back through nine
    /// typed accessors that spelled out "Ethereum", "XRP Ledger", "TON" and six
    /// more. The composer is on one chain at a time, so the sharing bought
    /// nothing but those names — and put a testnet review beside its mainnet
    /// refresh in two different slots.
    private(set) var previewBySlot: [String: SendPreview] = [:]

    func apply(_ preview: SendPreview?, forChainNamed chainName: String) {
        guard let slot = Self.slot(forChainNamed: chainName) else { return }
        previewBySlot[slot] = preview
    }

    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        Self.slot(forChainNamed: chainName).flatMap { previewBySlot[$0] }
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

    /// The slot a chain's preview is stored under: its mainnet's registry id.
    static func slot(forChainNamed chainName: String) -> String? {
        Chain(displayName: chainName)?.mainnetCounterpart.id
    }

    func resetAll() { previewBySlot.removeAll() }

    /// Clear every chain's preview but the one in `slot`.
    func resetAll(exceptSlot slot: String) {
        previewBySlot = previewBySlot.filter { $0.key == slot }
    }
}
