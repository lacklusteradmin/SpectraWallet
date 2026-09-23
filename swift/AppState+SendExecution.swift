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
        guard sendArtifact == nil, !isSending else { return }
        do {
            let input = try currentSendReviewInput()
            await sendSession.load(operation: .build, prepare: {
                let artifact = try await self.bridge.buildOwnedSend(input: input)
                guard try self.currentSendReviewInput() == input else {
                    throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        AppLocalization.string("Send inputs changed. Build the transaction again.")])
                }
                return artifact
            }, endpoints: {
                let choices = try await self.bridge.sendEndpoints(chainId: $0)
                guard try self.currentSendReviewInput() == input else {
                    throw NSError(domain: "Send", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        AppLocalization.string("Send inputs changed. Build the transaction again.")])
                }
                return choices
            })
        } catch { sendError = error.localizedDescription }
    }

    /// Localize the immutable build-time advisories for both new and resumed sends.
    var pendingHighRiskSendReasons: [String] {
        guard let artifact = sendArtifact else { return [] }
        var reasons = highRiskSendMessages(artifact.review.warnings)
            + evmRecipientMessages(artifact.review.recipientWarnings)
        if artifact.review.requiresSelfSendConfirmation {
            reasons.append(AppLocalization.string("This destination belongs to your wallet. Confirm intentional self-send."))
        }
        let network = Chain(id: artifact.chainId)?.displayName ?? artifact.chainId
        reasons.insert("\(artifact.amount) \(artifact.asset) → \(artifact.recipient) (\(network))", at: 0)
        return reasons
    }

    var stagedSendRequiresPassword: Bool {
        guard let artifact = sendArtifact else { return false }
        return self.bridge.walletSecretState(walletId: artifact.walletId)?.isSealed ?? true
    }

    func signPreparedSend(password: String?) async {
        await sendSession.sign(password: password, authenticate: {
            await self.authenticateForSensitiveAction(.send, reason: AppLocalization.string("Authorize transaction signing"))
        }, sign: { try await self.bridge.signSend(id: $0, reviewDigest: $1, password: $2) })
    }

    func broadcastPreparedSend() async {
        let session = sendSession.id
        guard let submitted = await sendSession.broadcast(submit: {
            try await self.bridge.broadcastSend(id: $0, endpoints: $1)
        }) else { return }
        await refreshTransactionProjection()
        guard sendSession.isCurrent(session) else { return }
        if let transaction = stagedSendTransaction,
           submitted.attempts.contains(where: { $0.outcome == .accepted }) {
            noteSendBroadcastQueued(for: transaction)
            startSendLiveActivity(for: transaction)
            requestTransactionStatusNotificationPermission()
            await runPostSendRefreshActions(for: transaction.chainName)
        }
    }

    func loadSavedSends() async {
        let session = sendSession.id
        do {
            let artifacts = try await self.bridge.listSends()
            guard sendSession.isCurrent(session) else { return }
            savedSendArtifacts = artifacts
        } catch { if sendSession.isCurrent(session) { sendError = error.localizedDescription } }
    }

    @discardableResult
    func resumeSend(id: String) async -> Bool {
        invalidateSendSession()
        return await sendSession.load(operation: .resume,
            prepare: { try await self.bridge.inspectSend(id: id) },
            endpoints: { try await self.bridge.sendEndpoints(chainId: $0) })
    }

    func invalidateSendSession() {
        sendSession.reset()
        sendPreviewRequestId = UUID()
        sendDestinationProbeRequestId = UUID()
        preparingChains = []
        isCheckingSendDestinationBalance = false
        isPreparingReplacementContext = false
        clearHighRiskSendConfirmation()
        clearSendVerificationNotice()
    }
}
