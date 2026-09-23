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
        SendPreviewInputSnapshot(walletId: sendFlow.walletId, holdingKey: sendFlow.holdingKey,
            amount: sendPreviewAmountInput, destination: sendFlow.address,
            nonceEnabled: sendFlow.evmManualNonceEnabled, nonce: sendFlow.evmManualNonce,
            feesEnabled: sendFlow.useCustomEvmFees, maxFee: sendFlow.customEvmMaxFeeGwei,
            priorityFee: sendFlow.customEvmPriorityFeeGwei)
    }

    func isCurrentSendPreview(requestId: UUID, input: SendPreviewInputSnapshot) -> Bool {
        !Task.isCancelled && sendFlow.previewRequestId == requestId && sendPreviewInputSnapshot == input
    }

    func adoptSendPreviewResult(_ result: Result<OwnedSendPreview?, Error>, requestId: UUID,
                               input: SendPreviewInputSnapshot, chainName: String) {
        guard isCurrentSendPreview(requestId: requestId, input: input) else { return }
        switch result {
        case .success(let preview):
            sendFlow.previewStore.apply(preview, forChainNamed: chainName)
            sendFlow.error = nil
            sendFlow.clearVerificationNotice()
        case .failure(let error):
            guard !isCancelledRequest(error) else { return }
            sendFlow.previewStore.clearPreview(forChainNamed: chainName)
            sendFlow.error = error.localizedDescription
        }
    }

    /// Every completion, including errors and loading cleanup, belongs to one request.
    func refreshSendPreview() async {
        let requestId = UUID()
        sendFlow.previewRequestId = requestId
        let input = sendPreviewInputSnapshot
        guard let coin = selectedSendCoin else {
            sendFlow.preparingChains = []
            sendFlow.destinationProbeRequestId = UUID()
            sendFlow.previewStore.resetAll()
            sendFlow.destinationRiskWarning = nil
            sendFlow.destinationInfoMessage = nil
            sendFlow.isCheckingDestination = false
            return
        }
        let slot = SendPreviewStore.slot(forChainNamed: coin.chainName) ?? coin.chainName
        sendFlow.preparingChains = [slot]
        defer { if sendFlow.previewRequestId == requestId { sendFlow.preparingChains = [] } }
        do {
            // Capture and validate all inputs before the first suspension.
            let nonce = try explicitEvmNonce().map(Int64.init)
            let fees = customEvmFeeConfiguration()
            if let error = customEvmFeeValidationError {
                throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            await refreshSendDestinationRiskWarning(for: coin)
            guard isCurrentSendPreview(requestId: requestId, input: input) else { return }
            sendFlow.previewStore.resetAll(exceptSlot: slot)
            let preview = try await self.bridge.previewOwnedSend(
                walletId: input.walletId, holdingKey: input.holdingKey, amount: input.amount,
                destination: input.destination, explicitNonce: nonce, customFees: fees)
            adoptSendPreviewResult(.success(preview), requestId: requestId, input: input, chainName: coin.chainName)
        } catch {
            adoptSendPreviewResult(.failure(error), requestId: requestId, input: input, chainName: coin.chainName)
        }
    }
}
