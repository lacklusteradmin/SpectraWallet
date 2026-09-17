import Foundation

// Preview types are UniFFI-generated from `core/src/send/`. What is left here
// is the composer's hold on the latest one and the fee every preview reports.

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    var errorDescription: String? { AppLocalization.string("Invalid EVM address.") }
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
    /// The composer's preview, and the chain it is for, as the chain's mainnet
    /// id.
    ///
    /// The mainnet because the two writers name one chain two ways: a refresh
    /// names the holding's chain ("Bitcoin"), a review names the network it
    /// resolved ("Bitcoin Testnet4"), and they must agree. This was a
    /// dictionary with a slot per chain, and every refresh emptied all but
    /// one: the composer is on one chain at a time.
    private var slot: String?
    private var preview: SendPreview?

    func apply(_ preview: SendPreview?, forChainNamed chainName: String) {
        slot = Self.slot(forChainNamed: chainName)
        self.preview = slot == nil ? nil : preview
    }

    /// A preview asked for by another chain than it was made for is none.
    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        guard let slot, slot == Self.slot(forChainNamed: chainName) else { return nil }
        return preview
    }

    func clearPreview(forChainNamed chainName: String) {
        if slot == Self.slot(forChainNamed: chainName) { resetAll() }
    }

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

    func resetAll() {
        slot = nil
        preview = nil
    }

    /// Clear the preview unless it is `slot`'s.
    func resetAll(exceptSlot slot: String) {
        if self.slot != slot { resetAll() }
    }
}
