import Foundation

private func evmSendOverrides(nonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> EvmSendOverridesInput? {
    let customDTO: EvmCustomFeeConfiguration? = customFees.map {
        EvmCustomFeeConfiguration(maxFeePerGasGwei: $0.maxFeePerGasGwei, maxPriorityFeePerGasGwei: $0.maxPriorityFeePerGasGwei)
    }
    if nonce == nil && customDTO == nil { return nil }
    return EvmSendOverridesInput(nonce: nonce.map(Int64.init), customFees: customDTO, gasLimit: nil, calldataHex: nil, signOnly: nil, accessListJson: nil)
}

private func ethereumSendResult(from typed: EvmSendResultDecoded) -> EthereumSendResult {
    let preview = EthereumSendPreview(
        nonce: typed.nonce, gasLimit: typed.gasLimit, maxFeePerGasGwei: 0, maxPriorityFeePerGasGwei: 0, estimatedNetworkFee: 0,
        spendableBalance: nil, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil,
        maxSendable: nil
    )
    return EthereumSendResult(
        fromAddress: "", transactionHash: typed.txid, rawTransactionHex: typed.rawTxHex, preview: preview, verificationStatus: .verified
    )
}

// MARK: - AppState send execution

extension AppState {
    func submitSend() async {
        let destinationInput = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let walletIndex = wallets.firstIndex(where: { $0.id == sendWalletID })
        let holdingIndex = walletIndex.flatMap { index in
            wallets[index].holdings.firstIndex(where: { $0.holdingKey == sendHoldingKey })
        }
        // Core reads the wallet, the holding, the registry and the token
        // preferences itself. This used to hand it `walletFound`, `assetFound`,
        // the balance, whether the chain is EVM and whether the asset is
        // sendable on Solana or NEAR — five answers about core's own state,
        // trusted on the funds path.
        let preflight: SendSubmitPreflightPlan
        do {
            preflight = try await WalletServiceBridge.shared.sendSubmitPreflight(
                walletID: sendWalletID, holdingKey: sendHoldingKey,
                destinationAddress: destinationInput, amountInput: sendAmount)
        } catch {
            sendError = error.localizedDescription
            return
        }
        guard let walletIndex, let holdingIndex else {
            sendError = "Select an asset"
            return
        }
        let wallet = wallets[walletIndex]
        let holding = wallet.holdings[holdingIndex]
        var destinationAddress = preflight.normalizedDestinationAddress
        var usedENSResolution = false
        let amount = preflight.amount
        let amountStr = preflight.amountStr
        // Every holding on an EVM chain routes to "ethereum", token or not, so
        // this is the same question `isEVMChain` used to ask — from the route.
        if preflight.submitKind == "ethereum" {
            do {
                let resolvedDestination = try await resolveEVMRecipientAddress(input: destinationInput, for: holding.chainName)
                destinationAddress = resolvedDestination.address
                usedENSResolution = resolvedDestination.usedENS
                if usedENSResolution { sendDestinationInfoMessage = "Resolved ENS \(destinationInput) to \(destinationAddress)." }
            } catch {
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
        // Every chain whose send is the plain shape — one native asset, a fee
        // the preview supplies, an address and path the generic resolvers know
        // — goes through one call. Ten arms used to state this, each carrying
        // the same four constants that are now `Chain::send_execution_shape`.
        //
        // Which chains those are is `Chain::uses_generic_send_submit`. Two
        // lists of names stood here re-deciding it, with identical bodies, and
        // a twelfth chain joining the shared path had to be added to whichever
        // of the two the author happened to be looking at.
        if preflight.usesGenericSubmit {
            await submitNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress,
                amount: amount, amountStr: amountStr)
            return
        }
        if preflight.submitKind == "icp" {
            guard !sendingChains.contains(holding.chainName) else { return }
            if sendPreviewStore.icpSendPreview == nil { await refreshSendPreview(forChainNamed: "Internet Computer") }
            guard wallets.contains(where: { $0.id == wallet.id }), let sourceAddress = resolvedICPAddress(for: wallet)
            else {
                sendError = "Unable to resolve this wallet's ICP address."
                return
            }
            let privateKey = storedPrivateKey(for: wallet.id)
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            guard privateKey != nil || seedPhrase != nil else {
                sendError = "This wallet's signing secret is unavailable."
                return
            }
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.icp.id, chainName: "Internet Computer",
                        derivationPath: wallet.seedDerivationPaths.path(for: .icp),
                        seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                    payloadFormat: result.payloadFormat,
                    clearPreview: { self.sendPreviewStore.icpSendPreview = nil })
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if preflight.submitKind == "bitcoin" {
            guard amount > 0 else {
                sendError = "Enter a valid amount"
                return
            }
            guard !sendingChains.contains(holding.chainName) else { return }
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            do {
                guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                    sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = resolvedBitcoinAddress(for: wallet) else {
                    sendError = "Unable to resolve this wallet's Bitcoin address from the seed phrase."
                    return
                }
                if sendPreviewStore.bitcoinSendPreview == nil { await refreshBitcoinSendPreview() }
                let feeRateSvB: Double = Double(sendPreviewStore.bitcoinSendPreview?.estimatedFeeRateSatVb ?? 10)
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.bitcoin.id, chainName: "Bitcoin",
                        derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateSvB, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                    payloadFormat: result.payloadFormat,
                    clearPreview: { self.sendPreviewStore.bitcoinSendPreview = nil })
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if preflight.submitKind == "dogecoin" {
            guard !sendingChains.contains(holding.chainName) else { return }
            guard let dogecoinAmount = parseDogecoinAmountInput(sendAmount) else {
                sendError = "Enter a valid DOGE amount with up to 8 decimal places."
                return
            }
            guard isValidDogecoinAddressForPolicy(destinationAddress, wallet: wallet) else {
                sendError = CommonLocalization.invalidDestinationAddressPrompt("Dogecoin")
                return
            }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard resolvedDogecoinAddress(for: wallet) != nil else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address from the seed phrase."
                return
            }
            appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send initiated.")
            if sendPreviewStore.dogecoinSendPreview == nil { await refreshDogecoinSendPreview() }
            if let dogecoinSendPreview = sendPreviewStore.dogecoinSendPreview, dogecoinAmount > dogecoinSendPreview.maxSendableDoge {
                sendError =
                    "Insufficient DOGE for amount plus network fee (max sendable ~\(String(format: "%.6f", dogecoinSendPreview.maxSendableDoge)) DOGE)."
                return
            }
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            guard let sourceAddress = resolvedDogecoinAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address."
                return
            }
            do {
                let feeRateDogePerKb = sendPreviewStore.dogecoinSendPreview?.estimatedFeeRateDogePerKb ?? 0.01
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.dogecoin.id, chainName: "Dogecoin",
                        derivationPath: walletDerivationPath(for: wallet, chain: .dogecoin),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: dogecoinAmount, amountStr: sendAmount,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateDogePerKb, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: dogecoinAmount, address: destinationAddress,
                        transactionHash: result.transactionHash,
                        feePriorityRaw: feePriorityOption(for: "Dogecoin").rawValue,
                        confirmationCount: 0,
                        dogecoinEstimatedFeeRateDogePerKb: sendPreviewStore.dogecoinSendPreview?.estimatedFeeRateDogePerKb,
                        usedChangeOutput: sendPreviewStore.dogecoinSendPreview?.usesChangeOutput, sourceAddress: sourceAddress,
                        signedTransactionPayload: result.rebroadcastPayload,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                clearSendVerificationNotice()
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: result.transactionHash)
                await refreshDogecoinTransactions()
                await refreshPendingTransactions(chainName: "Dogecoin")
                updateSendVerificationNoticeForLastSentTransaction()
                resetSendComposerState {
                    self.sendPreviewStore.dogecoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE send failed: \(error.localizedDescription)")
                noteSendBroadcastFailure(for: holding.chainName, message: error.localizedDescription)
            }
            return
        }
        if preflight.submitKind == "tron" {
            guard !sendingChains.contains(holding.chainName) else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            guard let sourceAddress = resolvedTronAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Tron signing address."
                return
            }
            if sendPreviewStore.tronSendPreview == nil { await refreshTronSendPreview() }
            guard let preview = sendPreviewStore.tronSendPreview else {
                sendError = sendError ?? "Unable to estimate Tron network fee."
                return
            }
            if let err = validateSendBalance(
                amount: amount, networkFee: preview.estimatedNetworkFee, holdingBalance: holding.amount,
                isNativeAsset: holding.symbol == "TRX", symbol: holding.symbol,
                nativeSymbol: "TRX", nativeBalance: wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount,
                feeDecimals: 6, chainLabel: "Tron"
            ) {
                sendError = err; return
            }
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            do {
                let contractAddress: String? = (holding.symbol == "TRX") ? nil : holding.contractAddress
                let tokenDecimals: UInt32? = (contractAddress != nil) ? 6 : nil
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.tron.id, chainName: "Tron", derivationPath: wallet.seedDerivationPaths.path(for: .tron),
                        seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                    payloadFormat: result.payloadFormat,
                    clearPreview: {
                        self.sendPreviewStore.tronSendPreview = nil
                        self.tronLastSendErrorDetails = nil
                        self.tronLastSendErrorAt = nil
                    })
            } catch {
                let message = userFacingTronSendError(error, symbol: holding.symbol)
                sendError = message
                recordTronSendDiagnosticError(message)
                noteSendBroadcastFailure(for: holding.chainName, message: message)
            }
            return
        }
        // Core already routed this send in the preflight above; asking the
        // question a second time on this side is how the two could disagree.
        if preflight.submitKind == "solana" {
            guard !sendingChains.contains(holding.chainName) else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = resolvedSolanaAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Solana signing address from the seed phrase."
                return
            }
            if sendPreviewStore.solanaSendPreview == nil { await refreshSendPreview(forChainNamed: "Solana") }
            guard let preview = sendPreviewStore.solanaSendPreview else {
                sendError = sendError ?? "Unable to estimate Solana network fee."
                return
            }
            if let err = validateSendBalance(
                amount: amount, networkFee: preview.estimatedNetworkFee, holdingBalance: holding.amount,
                isNativeAsset: holding.symbol == "SOL", symbol: holding.symbol,
                nativeSymbol: "SOL",
                nativeBalance: wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount,
                feeDecimals: 6, chainLabel: "Solana"
            ) {
                sendError = err; return
            }
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            do {
                let contractAddress: String?
                let tokenDecimals: UInt32?
                if holding.symbol == "SOL" {
                    contractAddress = nil
                    tokenDecimals = nil
                } else {
                    let solanaTokenMetadataByMint = solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol),
                        let tokenMetadata = solanaTokenMetadataByMint[mintAddress]
                    else {
                        sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    contractAddress = mintAddress
                    tokenDecimals = UInt32(tokenMetadata.decimals)
                }
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.solana.id, chainName: "Solana",
                        derivationPath: walletDerivationPath(for: wallet, chain: .solana),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                    payloadFormat: result.payloadFormat,
                    clearPreview: { self.sendPreviewStore.solanaSendPreview = nil })
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        // Monero is the plain shape plus a priority, and it signs from a
        // stored view key rather than a derivation path.
        if preflight.submitKind == "monero" {
            await submitNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress,
                amount: amount, amountStr: amountStr, moneroPriority: 2)
            return
        }
        // A NEP-141 the user does not track routes nowhere, and core says so
        // in `submitKind`. This used to check the chain, the standard and the
        // contract on its own — so a token core had refused to route was sent
        // anyway. Native NEAR is caught above, which is what `symbol` excludes.
        if preflight.submitKind == "near", holding.symbol != "NEAR",
            let contractAddress = holding.contractAddress
        {
            guard !sendingChains.contains(holding.chainName) else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."; return
            }
            guard let sourceAddress = resolvedNearAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."; return
            }
            let nearNativeBalance = wallet.holdings.first(where: { $0.chainName == "NEAR" && $0.symbol == "NEAR" })?.amount ?? 0
            if nearNativeBalance < 0.001 {
                sendError = "Insufficient NEAR balance to cover the network fee for this \(holding.symbol) transfer."; return
            }
            let tokenPref = (cachedTokenPreferencesByChain[.near] ?? []).first {
                $0.contractAddress.lowercased() == contractAddress.lowercased()
            }
            let decimals = min(Int(tokenPref?.decimals ?? 6), 18)
            sendingChains.insert(holding.chainName)
            defer { sendingChains.remove(holding.chainName) }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: Chain.near.id, chainName: "NEAR", derivationPath: walletDerivationPath(for: wallet, chain: .near),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: contractAddress, tokenDecimals: UInt32(decimals), feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                    payloadFormat: result.payloadFormat,
                    clearPreview: { self.sendPreviewStore.nearSendPreview = nil })
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        // `submitKind` is "ethereum" for every EVM chain and every token on
        // one — the route core computed, not `isEVMChain` asked again.
        if preflight.submitKind == "ethereum" {
            guard evmChainContext(for: holding.chainName) != nil else {
                sendError = "\(holding.chainName) native sending is not enabled yet."
                return
            }
            guard !sendingChains.contains("Ethereum") else { return }
            guard !activeEthereumSendWalletIDs.contains(wallet.id) else {
                sendError = "An \(holding.chainName) send is already in progress for this wallet."
                return
            }
            if customEthereumNonceValidationError != nil {
                sendError = customEthereumNonceValidationError
                return
            }
            if holding.symbol != "ETH" && holding.symbol != "BNB", amount <= 0 {
                sendError = "Enter a valid amount"
                return
            }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            let nativeSymbol = preflight.nativeEvmSymbol ?? "ETH"
            let nativeBalance =
                wallet.holdings.first(where: { $0.chainName == holding.chainName && $0.symbol == nativeSymbol })?.amount ?? 0
            if sendPreviewStore.ethereumSendPreview == nil { await refreshEthereumSendPreview() }
            guard let preview = sendPreviewStore.ethereumSendPreview else {
                sendError = sendError ?? "Unable to estimate \(holding.chainName) network fee."
                return
            }
            if let err = validateSendBalance(
                amount: amount, networkFee: preview.estimatedNetworkFee,
                holdingBalance: preflight.isNativeEvmAsset ? nativeBalance : holding.amount,
                isNativeAsset: preflight.isNativeEvmAsset, symbol: preflight.isNativeEvmAsset ? nativeSymbol : holding.symbol,
                nativeSymbol: nativeSymbol, nativeBalance: nativeBalance,
                feeDecimals: 6, chainLabel: nil
            ) {
                sendError = err; return
            }
            sendingChains.insert("Ethereum")
            activeEthereumSendWalletIDs.insert(wallet.id)
            defer {
                sendingChains.remove("Ethereum")
                activeEthereumSendWalletIDs.remove(wallet.id)
            }
            do {
                if customEthereumFeeValidationError != nil {
                    sendError = customEthereumFeeValidationError
                    return
                }
                let customFees = customEthereumFeeConfiguration()
                let explicitNonce = explicitEthereumNonce()
                let evmDerivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: holding.chainName) ?? .ethereum
                let spectraEvmChainId = Chain(displayName: holding.chainName)?.id
                let evmOverrides = evmSendOverrides(nonce: explicitNonce, customFees: customFees)
                let rustSupportsChain = spectraEvmChainId != nil
                guard rustSupportsChain, let chainId = spectraEvmChainId else {
                    sendError = "\(holding.symbol) transfers on \(holding.chainName) are not enabled yet."
                    return
                }
                guard let sourceAddress = resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                    sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                    return
                }
                let contractAddress: String?
                let tokenDecimals: UInt32?
                if preflight.isNativeEvmAsset {
                    contractAddress = nil
                    tokenDecimals = nil
                } else if let token = supportedEVMToken(for: holding) {
                    contractAddress = token.contractAddress
                    tokenDecimals = UInt32(token.decimals)
                } else {
                    sendError = "\(holding.symbol) transfers on \(holding.chainName) are not enabled yet."
                    return
                }
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: chainId, chainName: holding.chainName,
                        derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain),
                        seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount, amountStr: amountStr,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: evmOverrides, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let fallbackNonce = explicitNonce.map(Int64.init) ?? sendPreviewStore.ethereumSendPreview?.nonce ?? 0
                let typed = result.evm ?? EvmSendResultDecoded(txid: "", rawTxHex: "", nonce: fallbackNonce, gasLimit: 0)
                let evmResult = ethereumSendResult(from: typed)
                await recordSuccessfulBroadcast(
                    wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                    transactionHash: result.transactionHash, signedPayload: evmResult.rawTransactionHex,
                    payloadFormat: "evm.raw_hex", ethereumNonce: Int(evmResult.preview.nonce),
                    verificationStatus: evmResult.verificationStatus)
            } catch {
                sendError = mapEthereumSendError(error)
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        sendError = "\(holding.chainName) native sending is not enabled yet."
    }

    /// Store a broadcast that succeeded and reset the composer.
    ///
    /// This tail was written out eight times, six of them byte-identical: build
    /// the record, decorate it, store it, refresh, clear that chain's preview.
    /// Dogecoin is the one arm that genuinely differs — it runs its own refresh
    /// sequence rather than `runPostSendRefreshActions` — and keeps its copy.
    private func recordSuccessfulBroadcast(
        wallet: ImportedWallet, holding: Coin, destinationAddress: String, amount: Double,
        transactionHash: String?, signedPayload: String?, payloadFormat: String?,
        ethereumNonce: Int? = nil,
        verificationStatus: SendBroadcastVerificationStatus = .verified,
        clearPreview: (() -> Void)? = nil
    ) async {
        let transaction = decoratePendingSendTransaction(
            TransactionRecord(
                walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                transactionHash: transactionHash, ethereumNonce: ethereumNonce,
                signedTransactionPayload: signedPayload, signedTransactionPayloadFormat: payloadFormat
            ), holding: holding)
        recordPendingSentTransaction(transaction)
        await runPostSendRefreshActions(for: holding.chainName, verificationStatus: verificationStatus)
        resetSendComposerState(afterSend: clearPreview)
    }

    /// Sign and broadcast a native send on a chain whose request is the plain
    /// shape: one asset, one fee, an address and path the generic resolvers
    /// know.
    ///
    /// This merges `submitSimpleNativeChainSend` and `submitUTXOSatChainSend`,
    /// which differed only in how the fee entered the request and in three
    /// per-chain constants. Those are `Chain::send_execution_shape` now, so
    /// the ten call sites that carried them inline are one dispatch.
    private func submitNativeChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, amountStr: String,
        moneroPriority: UInt32? = nil
    ) async {
        let chainName = holding.chainName
        let symbol = holding.symbol
        // A chain with no registry row cannot be sent on; the guard below on the
        // chain id would refuse it anyway, and this refuses it first.
        guard let shape = Chain(displayName: chainName)?.sendExecutionShape else {
            sendError = "\(chainName) native sending is not enabled yet."
            return
        }
        guard amount > 0 else { sendError = "Enter a valid amount"; return }
        guard !sendingChains.contains(chainName) else { return }
        guard let chainID = Chain(displayName: chainName)?.id, !chainID.isEmpty else { return }

        let seedPhrase = storedSeedPhrase(for: wallet.id)
        let privateKey = shape.supportsPrivateKey ? storedPrivateKey(for: wallet.id) : nil
        let isMonero = chainName == "Monero"
        if !isMonero {
            if shape.supportsPrivateKey {
                guard seedPhrase != nil || privateKey != nil else {
                    sendError = "This wallet's signing key is unavailable."
                    return
                }
            } else {
                guard seedPhrase != nil else { sendError = "This wallet's seed phrase is unavailable."; return }
            }
        }
        guard let sourceAddress = resolvedAddress(for: wallet, chainName: chainName) else {
            sendError = "Unable to resolve this wallet's \(symbol) signing address."
            return
        }
        if sendPreviewStore.estimatedFee(forChainNamed: chainName) == nil {
            await refreshSendPreview(forChainNamed: chainName)
        }
        let previewFee = sendPreviewStore.estimatedFee(forChainNamed: chainName)
        guard let fee = previewFee ?? (shape.feeFallback > 0 ? shape.feeFallback : nil) else {
            sendError = sendError ?? "Unable to estimate \(chainName) network fee."
            return
        }
        if let err = validateSendBalance(
            amount: amount, networkFee: fee, holdingBalance: holding.amount,
            isNativeAsset: true, symbol: symbol, nativeSymbol: nil, nativeBalance: nil,
            feeDecimals: Int(shape.feeDecimals), chainLabel: nil
        ) {
            sendError = err
            return
        }
        // Monero has no derivation chain: it signs from stored key material,
        // not a path, and the arm this replaced passed an empty string. Every
        // other routed chain resolves one, so a missing path there is a real
        // failure rather than something to send blank.
        let derivationPath =
            seedDerivationChain(for: chainName)
            .map { walletDerivationPath(for: wallet, chain: $0) }
        guard let derivationPath = derivationPath ?? (isMonero ? "" : nil) else {
            sendError = "Unable to resolve this wallet's \(symbol) derivation path."
            return
        }
        sendingChains.insert(chainName)
        defer { sendingChains.remove(chainName) }
        do {
            let result = try await WalletServiceBridge.shared.executeSend(
                SendExecutionRequest(
                    chainId: chainID, chainName: chainName,
                    derivationPath: derivationPath,
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress,
                    toAddress: destinationAddress, amount: amount, amountStr: amountStr,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil,
                    feeSat: shape.feeField == .feeSats ? UInt64(fee * 1e8) : nil,
                    gasBudget: shape.feeField == .gasBudget ? fee : nil,
                    feeAmount: shape.feeField == .feeAmount ? fee : nil,
                    evmOverrides: nil, moneroPriority: moneroPriority,
                    derivationOverrides: wallet.derivationOverrides
                ))
            await recordSuccessfulBroadcast(
                wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount,
                transactionHash: result.transactionHash, signedPayload: result.rebroadcastPayload,
                payloadFormat: result.payloadFormat,
                clearPreview: { self.sendPreviewStore.clearPreview(forChainNamed: chainName) })
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }
    }
}
