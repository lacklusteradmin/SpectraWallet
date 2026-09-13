import Foundation

extension AppState {
    /// Only request coalescing and stale-view protection live here. Core owns
    /// asset routing, source identity, precision and protocol fee estimation.
    func refreshSendPreview() async {
        guard let coin = selectedSendCoin else {
            sendPreviewStore.resetAll()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        let slot = SendPreviewStore.previewSlot(forChainNamed: coin.chainName) ?? coin.chainName
        guard !preparingChains.contains(slot) else {
            pendingSendPreviewRefreshChains.insert(slot)
            return
        }
        preparingChains.insert(slot)
        defer {
            preparingChains.remove(slot)
            if pendingSendPreviewRefreshChains.remove(slot) != nil {
                Task { @MainActor [weak self] in await self?.refreshSendPreview() }
            }
        }
        let walletID = sendWalletID
        let amount = sendPreviewAmountInput
        let destination = sendAddress
        let nonceInput = evmManualNonce
        let fees = customEvmFeeConfiguration()
        let nonceEnabled = evmManualNonceEnabled
        await refreshSendDestinationRiskWarning(for: coin)
        sendPreviewStore.resetAll(exceptChainNamed: slot)
        do {
            let preview = try await WalletServiceBridge.shared.previewOwnedSend(
                walletID: walletID, holdingKey: coin.holdingKey, amount: amount,
                destination: destination, explicitNonce: try explicitEvmNonce().map(Int64.init),
                customFees: fees)
            guard sendWalletID == walletID, sendPreviewAmountInput == amount,
                sendAddress == destination, selectedSendCoin?.holdingKey == coin.holdingKey,
                evmManualNonce == nonceInput, evmManualNonceEnabled == nonceEnabled,
                customEvmFeeConfiguration() == fees else { return }
            sendPreviewStore.apply(preview, forChainNamed: coin.chainName)
            sendError = nil
            clearSendVerificationNotice()
        } catch {
            guard !isCancelledRequest(error), sendWalletID == walletID,
                sendPreviewAmountInput == amount, sendAddress == destination,
                selectedSendCoin?.holdingKey == coin.holdingKey else { return }
            sendPreviewStore.clearPreview(forChainNamed: coin.chainName)
            sendError = error.localizedDescription
        }
    }
}
