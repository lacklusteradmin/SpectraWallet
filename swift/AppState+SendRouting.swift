import Foundation
extension AppState {
    private enum SendPreviewKind: String {
        case bitcoin
        case bitcoinCash
        case bitcoinSV
        case litecoin
        case ethereum
        case dogecoin
        case tron
        case solana
        case xrp
        case stellar
        case monero
        case cardano
        case sui
        case aptos
        case ton
        case icp
        case near
        case polkadot
    }
    func refreshSendPreview() async {
        guard let selectedSendCoin = selectedSendCoin else {
            resetAllSendPreviews()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        await refreshSendDestinationRiskWarning(for: selectedSendCoin)
        let activePreview = await plannedPreviewKind(for: selectedSendCoin)
        resetInactiveSendPreviews(
            exceptChainNamed: activePreview == nil ? nil : selectedSendCoin.chainName)
        switch activePreview {
        case .bitcoin: await refreshBitcoinSendPreview()
        case .bitcoinCash: await refreshBitcoinCashSendPreview()
        case .bitcoinSV: await refreshBitcoinSVSendPreview()
        case .litecoin: await refreshLitecoinSendPreview()
        case .ethereum: await refreshEthereumSendPreview()
        case .dogecoin: await refreshDogecoinSendPreview()
        case .tron: await refreshTronSendPreview()
        // Eleven arms stood here and every one of them said "the chain this
        // coin is on", spelled out. They are the chains core previews through
        // one entry point, which is what `Chain::simple_preview_chain` names.
        case .some: await refreshSendPreview(forChainNamed: selectedSendCoin.chainName)
        case nil: break
        }
    }
    /// Which preview this holding needs, as core routes it.
    private func plannedPreviewKind(for coin: Coin) async -> SendPreviewKind? {
        let plan = await WalletServiceBridge.shared.sendAssetRouting(
            walletID: sendWalletID, holdingKey: coin.holdingKey)
        guard let previewKind = plan?.previewKind else { return nil }
        return SendPreviewKind(rawValue: previewKind)
    }
    private func resetAllSendPreviews() {
        sendPreviewStore.resetAll()
        preparingChains = []
    }
    /// Clear the previews and the "preparing" flags for every chain but the
    /// one being previewed.
    ///
    /// Fifty-four lines and fourteen chain names before, which is
    /// `SendPreviewStore`'s field list and `preparingChains`' contents written
    /// out a second and third time. Both are keyed by the preview *slot* — the
    /// EVM family shares Ethereum's — so that is what is kept.
    private func resetInactiveSendPreviews(exceptChainNamed activeChainName: String?) {
        let slot = activeChainName.flatMap { SendPreviewStore.previewSlot(forChainNamed: $0) }
        sendPreviewStore.resetAll(exceptChainNamed: slot)
        preparingChains = slot.map { preparingChains.intersection([$0]) } ?? []
    }
}
