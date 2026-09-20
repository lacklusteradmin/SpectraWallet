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
    /// The composer's preview, keyed by mainnet id. Refresh names the holding's
    /// chain while review names its resolved network; both map to the same key.
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

    /// The estimated network fee in the preview chain's native units.
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
