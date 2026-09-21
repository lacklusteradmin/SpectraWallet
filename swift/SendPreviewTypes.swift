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
    /// The composer's quote is bound to a concrete wallet, holding and network.
    private var slot: String?
    private var quote: OwnedSendPreview?

    func apply(_ quote: OwnedSendPreview?, forChainNamed chainName: String) {
        slot = Self.slot(forChainNamed: chainName)
        self.quote = quote?.chainId == slot ? quote : nil
    }

    /// A preview asked for by another chain than it was made for is none.
    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        guard let slot, slot == Self.slot(forChainNamed: chainName) else { return nil }
        return quote?.preview
    }

    func ownedQuote(walletId: String, holdingKey: String) -> OwnedSendPreview? {
        guard let quote, quote.walletId == walletId, quote.holdingKey == holdingKey else { return nil }
        return quote
    }

    func clearPreview(forChainNamed chainName: String) {
        if slot == Self.slot(forChainNamed: chainName) { resetAll() }
    }

    /// The estimated network fee in the preview chain's native units.
    func estimatedFee(forChainNamed chainName: String) -> Double? {
        taggedPreview(forChainNamed: chainName)?.estimatedNetworkFee
    }

    /// Never share a preview between a mainnet and its testnets.
    static func slot(forChainNamed chainName: String) -> String? {
        Chain(displayName: chainName)?.id
    }

    func resetAll() {
        slot = nil
        quote = nil
    }

    /// Clear the preview unless it is `slot`'s.
    func resetAll(exceptSlot slot: String) {
        if self.slot != slot { resetAll() }
    }
}
