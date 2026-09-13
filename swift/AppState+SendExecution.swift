import Foundation

extension AppState {
    func submitSend() async {
        let destinationInput = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let walletID = sendWalletID
        let holdingKey = sendHoldingKey
        let amountInput = sendAmount
        let walletSnapshot = wallets.first { $0.id == walletID }
        let holdingSnapshot = walletSnapshot?.holdings.first { $0.holdingKey == holdingKey }
        // Core reads the wallet, the holding, the registry and the token
        // preferences itself. This used to hand it `walletFound`, `assetFound`,
        // the balance, whether the chain is EVM and whether the asset is
        // sendable on Solana or NEAR — five answers about core's own state,
        // trusted on the funds path.
        let preflight: SendSubmitPreflightPlan
        do {
            preflight = try await WalletServiceBridge.shared.sendSubmitPreflight(
                walletID: walletID, holdingKey: holdingKey,
                destinationAddress: destinationInput, amountInput: amountInput)
        } catch {
            sendError = error.localizedDescription
            return
        }
        guard let wallet = walletSnapshot, let holding = holdingSnapshot else {
            sendError = "Select an asset"
            return
        }
        var destinationAddress = preflight.normalizedDestinationAddress
        var usedENSResolution = false
        let amount = preflight.amount
        let amountStr = preflight.amountStr
        do {
            do {
                let review = reviewedSendDestination
                let expected = review.flatMap { $0.input == destinationInput && $0.chain == holding.chainName ? $0.address : nil }
                let resolved = try await resolveSendDestination(input: destinationInput, for: holding.chainName, expectedAddress: expected)
                if resolved.usedEns && expected == nil {
                    sendError = "Review the resolved recipient address before sending."
                    return
                }
                destinationAddress = resolved.address
                usedENSResolution = resolved.usedEns
                if usedENSResolution { sendDestinationInfoMessage = "Resolved ENS \(destinationInput) to \(destinationAddress)." }
            } catch {
                bypassHighRiskSendConfirmation = false
                sendError = (error as? LocalizedError)?.errorDescription ?? "Enter a valid \(holding.chainName) destination."
                return
            }
        }
        if !bypassHighRiskSendConfirmation {
            var highRiskReasons = await evaluateHighRiskSendReasons(
                wallet: wallet, holding: holding, amount: amount, destinationAddress: destinationAddress,
                destinationInput: destinationInput, usedENSResolution: usedENSResolution
            )
            // Core returns nothing for a chain that is not EVM, so the caller
            // no longer has to check first.
            highRiskReasons += await evmRecipientPreflightReasons(
                holding: holding, destinationAddress: destinationAddress)
            if !highRiskReasons.isEmpty {
                pendingHighRiskSendReasons = highRiskReasons
                isShowingHighRiskSendConfirmation = true
                sendError = nil
                return
            }
        } else {
            bypassHighRiskSendConfirmation = false
        }
        if await requiresSelfSendConfirmation(
            wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount
        ) {
            return
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction send") else { return }
        guard !sendingChains.contains(holding.chainName) else { return }
        sendingChains.insert(holding.chainName)
        defer { sendingChains.remove(holding.chainName) }
        do {
            if let error = customEvmFeeValidationError ?? evmNonceValidationError {
                sendError = error
                return
            }
            let nonce = try explicitEvmNonce().map(Int64.init)
            let fees = customEvmFeeConfiguration()
            let overrides = nonce == nil && fees == nil ? nil : EvmSendOverridesInput(
                nonce: nonce, customFees: fees, gasLimit: nil, calldataHex: nil,
                signOnly: nil, accessListJson: nil)
            let result = try await WalletServiceBridge.shared.executeOwnedSend(
                walletID: wallet.id, holdingKey: holding.holdingKey, amount: amountStr,
                destination: destinationAddress, overrides: overrides)
            await refreshTransactionProjection()
            lastSentTransaction = transactions.first {
                $0.transactionHash == result.transactionHash && $0.walletID == wallet.id
            }
            if let transaction = lastSentTransaction { noteSendBroadcastQueued(for: transaction) }
            requestTransactionStatusNotificationPermission()
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { self.sendPreviewStore.clearPreview(forChainNamed: holding.chainName) }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: error.localizedDescription)
        }
    }
}
