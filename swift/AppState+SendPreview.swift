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
                               input: SendPreviewInputSnapshot) {
        guard isCurrentSendPreview(requestId: requestId, input: input) else { return }
        switch result {
        case .success(let preview):
            sendFlow.previewStore.apply(preview)
            sendFlow.error = nil
            sendFlow.clearVerificationNotice()
            adoptRecipientCheck(preview?.recipient)
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            sendFlow.previewStore.reset()
            sendFlow.error = error.localizedDescription
        }
    }

    /// Core checks the destination beside the quote; this only words it.
    private func adoptRecipientCheck(_ check: RecipientCheck?) {
        guard let check, let coin = selectedSendCoin else { return }
        switch check {
        case .checked(let activity):
            let messages = chainRiskProbeMessages(chainName: coin.chainName, symbol: coin.symbol, activity: activity)
            sendFlow.destinationRiskWarning = messages.warning
            sendFlow.destinationInfoMessage = messages.info
        case .unavailable:
            sendFlow.destinationInfoMessage = localizedStoreString("Unable to verify this address's activity. Try again later.")
        }
    }

    /// Every completion, including errors and loading cleanup, belongs to one
    /// request. Core quotes and checks the recipient in the same call.
    func refreshSendPreview() async {
        let requestId = UUID()
        sendFlow.previewRequestId = requestId
        let input = sendPreviewInputSnapshot
        sendFlow.destinationRiskWarning = nil
        sendFlow.destinationInfoMessage = nil
        guard selectedSendCoin != nil else {
            sendFlow.isPreparingPreview = false
            sendFlow.previewStore.reset()
            return
        }
        sendFlow.isPreparingPreview = true
        defer { if sendFlow.previewRequestId == requestId { sendFlow.isPreparingPreview = false } }
        do {
            // Capture and validate all inputs before the first suspension.
            let nonce = try explicitEvmNonce().map(Int64.init)
            let fees = customEvmFeeConfiguration()
            if let error = customEvmFeeValidationError {
                throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            let preview = try await self.bridge.ready().previewOwnedSend(
                walletId: input.walletId, holdingKey: input.holdingKey, amount: input.amount,
                destination: input.destination, explicitNonce: nonce, customFees: fees)
            adoptSendPreviewResult(.success(preview), requestId: requestId, input: input)
        } catch {
            adoptSendPreviewResult(.failure(error), requestId: requestId, input: input)
        }
    }
}
