import Foundation

/// Raw form identity, including invalid edits that may parse to the same nil value.
struct SendPreviewInputSnapshot: Equatable {
    let walletId: String
    let holdingKey: String
    let amount: String
    let destination: String
    let nonceEnabled: Bool
    let nonce: String
    let feesEnabled: Bool
    let maxFee: String
    let priorityFee: String
}

extension AppState {
    var sendPreviewInputSnapshot: SendPreviewInputSnapshot {
        SendPreviewInputSnapshot(walletId: sendWalletId, holdingKey: sendHoldingKey,
            amount: sendPreviewAmountInput, destination: sendAddress,
            nonceEnabled: evmManualNonceEnabled, nonce: evmManualNonce,
            feesEnabled: useCustomEvmFees, maxFee: customEvmMaxFeeGwei,
            priorityFee: customEvmPriorityFeeGwei)
    }

    func isCurrentSendPreview(requestId: UUID, input: SendPreviewInputSnapshot) -> Bool {
        !Task.isCancelled && sendPreviewRequestId == requestId && sendPreviewInputSnapshot == input
    }

    func adoptSendPreviewResult(_ result: Result<SendPreview?, Error>, requestId: UUID,
                               input: SendPreviewInputSnapshot, chainName: String) {
        guard isCurrentSendPreview(requestId: requestId, input: input) else { return }
        switch result {
        case .success(let preview):
            sendPreviewStore.apply(preview, forChainNamed: chainName)
            sendError = nil
            clearSendVerificationNotice()
        case .failure(let error):
            guard !isCancelledRequest(error) else { return }
            sendPreviewStore.clearPreview(forChainNamed: chainName)
            sendError = error.localizedDescription
        }
    }

    /// Every completion, including errors and loading cleanup, belongs to one request.
    func refreshSendPreview() async {
        let requestId = UUID()
        sendPreviewRequestId = requestId
        let input = sendPreviewInputSnapshot
        guard let coin = selectedSendCoin else {
            preparingChains = []
            sendDestinationProbeRequestId = UUID()
            sendPreviewStore.resetAll()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        let slot = SendPreviewStore.slot(forChainNamed: coin.chainName) ?? coin.chainName
        preparingChains = [slot]
        defer { if sendPreviewRequestId == requestId { preparingChains = [] } }
        do {
            // Capture and validate all inputs before the first suspension.
            let nonce = try explicitEvmNonce().map(Int64.init)
            let fees = customEvmFeeConfiguration()
            if let error = customEvmFeeValidationError {
                throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            await refreshSendDestinationRiskWarning(for: coin)
            guard isCurrentSendPreview(requestId: requestId, input: input) else { return }
            sendPreviewStore.resetAll(exceptSlot: slot)
            let preview = try await self.bridge.previewOwnedSend(
                walletId: input.walletId, holdingKey: input.holdingKey, amount: input.amount,
                destination: input.destination, explicitNonce: nonce, customFees: fees)
            adoptSendPreviewResult(.success(preview), requestId: requestId, input: input, chainName: coin.chainName)
        } catch {
            adoptSendPreviewResult(.failure(error), requestId: requestId, input: input, chainName: coin.chainName)
        }
    }
}
