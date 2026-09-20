import Foundation

/// Raw form identity, including invalid edits that may parse to the same nil value.
struct SendPreviewInputSnapshot: Equatable {
    let walletID: String
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
        SendPreviewInputSnapshot(walletID: sendWalletID, holdingKey: sendHoldingKey,
            amount: sendPreviewAmountInput, destination: sendAddress,
            nonceEnabled: evmManualNonceEnabled, nonce: evmManualNonce,
            feesEnabled: useCustomEvmFees, maxFee: customEvmMaxFeeGwei,
            priorityFee: customEvmPriorityFeeGwei)
    }

    func isCurrentSendPreview(requestID: UUID, input: SendPreviewInputSnapshot) -> Bool {
        !Task.isCancelled && sendPreviewRequestID == requestID && sendPreviewInputSnapshot == input
    }

    func adoptSendPreviewResult(_ result: Result<SendPreview?, Error>, requestID: UUID,
                               input: SendPreviewInputSnapshot, chainName: String) {
        guard isCurrentSendPreview(requestID: requestID, input: input) else { return }
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
        let requestID = UUID()
        sendPreviewRequestID = requestID
        let input = sendPreviewInputSnapshot
        guard let coin = selectedSendCoin else {
            preparingChains = []
            sendDestinationProbeRequestID = UUID()
            sendPreviewStore.resetAll()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        let slot = SendPreviewStore.slot(forChainNamed: coin.chainName) ?? coin.chainName
        preparingChains = [slot]
        defer { if sendPreviewRequestID == requestID { preparingChains = [] } }
        do {
            // Capture and validate all inputs before the first suspension.
            let nonce = try explicitEvmNonce().map(Int64.init)
            let fees = customEvmFeeConfiguration()
            if let error = customEvmFeeValidationError {
                throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            await refreshSendDestinationRiskWarning(for: coin)
            guard isCurrentSendPreview(requestID: requestID, input: input) else { return }
            sendPreviewStore.resetAll(exceptSlot: slot)
            let preview = try await WalletServiceBridge.shared.previewOwnedSend(
                walletID: input.walletID, holdingKey: input.holdingKey, amount: input.amount,
                destination: input.destination, explicitNonce: nonce, customFees: fees)
            adoptSendPreviewResult(.success(preview), requestID: requestID, input: input, chainName: coin.chainName)
        } catch {
            adoptSendPreviewResult(.failure(error), requestID: requestID, input: input, chainName: coin.chainName)
        }
    }
}
