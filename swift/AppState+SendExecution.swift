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
        return SendReviewInput(walletId: sendFlow.walletId, holdingKey: sendFlow.holdingKey,
            amount: sendFlow.amount, destination: sendFlow.address, overrides: overrides)
    }

    func submitSend() async {
        guard sendFlow.artifact == nil, !sendFlow.isBusy else { return }
        do {
            let input = try currentSendReviewInput()
            await sendFlow.session.load(operation: .build, prepare: {
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
        } catch { sendFlow.error = error.localizedDescription }
    }

    /// Localize the immutable build-time advisories for both new and resumed sends.
    var pendingHighRiskSendReasons: [String] {
        guard let artifact = sendFlow.artifact else { return [] }
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
        guard let artifact = sendFlow.artifact else { return false }
        // An unknown wallet asks for a password rather than signing without one.
        return cachedWalletById[artifact.walletId]?.signing.requiresPassword ?? true
    }

    func signPreparedSend(password: String?) async {
        await sendFlow.session.sign(password: password, authenticate: {
            await self.authenticateForSensitiveAction(.send, reason: AppLocalization.string("Authorize transaction signing"))
        }, sign: { try await self.bridge.signSend(id: $0, reviewDigest: $1, password: $2) })
    }

    func broadcastPreparedSend() async {
        guard let submitted = await sendFlow.session.broadcast(submit: {
            try await self.bridge.broadcastSend(id: $0, endpoints: $1)
        }) else { return }
        await handleBroadcastCompletion(submitted)
    }

    /// Application completion is independent of the originating form's lifetime.
    func handleBroadcastCompletion(_ submitted: SendArtifact) async {
        await refreshTransactionProjection()
        // Resolve the completed operation by its own ID, never the current
        // composer or the bounded history summary.
        if let transaction = try? await bridge.transaction(id: submitted.id),
           submitted.attempts.contains(where: { $0.outcome == .accepted }) {
            noteSendBroadcastQueued(for: transaction)
            startSendLiveActivity(for: transaction)
            requestTransactionStatusNotificationPermission()
            await runPostSendRefreshActions(for: transaction.chainId)
        }
    }

    func loadSavedSends() async {
        let session = sendFlow.session.id
        do {
            let artifacts = try await self.bridge.listSends()
            guard sendFlow.session.isCurrent(session) else { return }
            sendFlow.savedArtifacts = artifacts
        } catch { if sendFlow.session.isCurrent(session) { sendFlow.error = error.localizedDescription } }
    }

    @discardableResult
    func resumeSend(id: String) async -> Bool {
        sendFlow.invalidateSession()
        return await sendFlow.session.load(operation: .resume,
            prepare: { try await self.bridge.inspectSend(id: id) },
            endpoints: { try await self.bridge.sendEndpoints(chainId: $0) })
    }

}
