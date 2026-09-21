import Foundation

extension AppState {
    private func currentSendReviewInput() throws -> SendReviewInput {
        if let error = customEvmFeeValidationError ?? evmNonceValidationError {
            throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        let nonce = try explicitEvmNonce().map(Int64.init)
        let fees = customEvmFeeConfiguration()
        let overrides = nonce == nil && fees == nil ? nil : EvmSendOverridesInput(
            nonce: nonce, customFees: fees, gasLimit: nil, calldataHex: nil,
            signOnly: nil, accessListJson: nil)
        return SendReviewInput(walletId: sendWalletId, holdingKey: sendHoldingKey,
            amount: sendAmount, destination: sendAddress, overrides: overrides)
    }

    func submitSend() async {
        guard pendingSendReview == nil else { return }
        do {
            let input = try currentSendReviewInput()
            let review = try await self.bridge.reviewOwnedSend(input: input)
            guard try currentSendReviewInput() == input else {
                sendError = AppLocalization.string("Send inputs changed. Review the transaction again.")
                return
            }
            var reasons = highRiskSendMessages(review.warnings) + evmRecipientMessages(review.recipientWarnings)
            if review.requiresSelfSendConfirmation {
                reasons.append(AppLocalization.string("This destination belongs to your wallet. Confirm intentional self-send."))
            }
            let network = Chain(id: review.request.chainId)?.displayName ?? review.request.chainId
            reasons.insert("\(review.request.amountStr) → \(review.request.toAddress) (\(network))", at: 0)
            if let preview = review.preview {
                // `String(Double)` printed the fee as Swift spells a double —
                // `2.1e-05 ETH` for a small one — beside a review the user is
                // about to confirm.
                if let chain = Chain(id: review.request.chainId) {
                    reasons.append(AppLocalization.format("Estimated network fee: %@", formattedNetworkFee(preview.estimatedNetworkFee, chain: chain)))
                }
            }
            pendingSendReview = review
            pendingHighRiskSendReasons = reasons
            isShowingHighRiskSendConfirmation = true
            sendError = nil
        } catch { sendError = error.localizedDescription }
    }

    func submitReviewedSend(_ review: OwnedSendReview, password: String?) async {
        let chainName = Chain(id: review.request.chainId)?.displayName ?? review.request.chainId
        guard !sendingChains.contains(chainName) else { return }
        sendingChains.insert(chainName)
        defer { sendingChains.remove(chainName) }
        guard await authenticateForSensitiveAction(.send, reason: AppLocalization.string("Authorize transaction send")) else { return }
        do {
            let result = try await self.bridge.executeOwnedSend(
                reviewId: review.id, input: currentSendReviewInput(), password: password)
            await refreshTransactionProjection()
            lastSentTransaction = transactions.first {
                $0.transactionHash == result.transactionHash && $0.walletId == review.request.walletId
            }
            if let transaction = lastSentTransaction {
                noteSendBroadcastQueued(for: transaction)
                startSendLiveActivity(for: transaction)
            }
            requestTransactionStatusNotificationPermission()
            await runPostSendRefreshActions(for: chainName)
            resetSendComposerState { self.sendPreviewStore.clearPreview(forChainNamed: chainName) }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: chainName, message: error.localizedDescription)
        }
    }
}
