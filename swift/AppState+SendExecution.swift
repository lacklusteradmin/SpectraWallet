import Foundation

private func evmSendOverrides(nonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> EvmSendOverridesInput? {
    let customDTO: EvmCustomFeeConfiguration? = customFees.map {
        EvmCustomFeeConfiguration(maxFeePerGasGwei: $0.maxFeePerGasGwei, maxPriorityFeePerGasGwei: $0.maxPriorityFeePerGasGwei)
    }
    if nonce == nil && customDTO == nil { return nil }
    return EvmSendOverridesInput(nonce: nonce.map(Int64.init), customFees: customDTO)
}

private func ethereumSendResult(from typed: EvmSendResultDecoded) -> EthereumSendResult {
    let preview = EthereumSendPreview(
        nonce: typed.nonce, gasLimit: typed.gasLimit, maxFeePerGasGwei: 0, maxPriorityFeePerGasGwei: 0, estimatedNetworkFeeEth: 0,
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
        let selectedCoin = holdingIndex.flatMap { holdingIndex in
            walletIndex.map { wallets[$0].holdings[holdingIndex] }
        }
        let preflight: SendSubmitPreflightPlan
        do {
            preflight = try corePlanSendSubmitPreflight(
                request: SendSubmitPreflightRequest(
                    walletFound: walletIndex != nil, assetFound: holdingIndex != nil, destinationAddress: destinationInput,
                    amountInput: sendAmount, availableBalance: selectedCoin?.amount ?? 0,
                    asset: selectedCoin.map {
                        SendAssetRoutingInput(
                            chainName: $0.chainName, symbol: $0.symbol, isEvmChain: isEVMChain($0.chainName),
                            supportsSolanaSendCoin: isSupportedSolanaSendCoin($0), supportsNearTokenSend: isSupportedNearTokenSend($0)
                        )
                    }
                )
            )
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
        if holding.chainName == "Sui", holding.symbol == "SUI" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.sui, chainName: "Sui", symbol: "SUI",
                feeDecimals: 6, checkSelfSend: true, supportsPrivateKey: false, gasBudgetFromFee: true,
                resolveAddress: { self.resolvedSuiAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .sui) },
                getPreviewFee: { self.sendPreviewStore.suiSendPreview?.estimatedNetworkFeeSui },
                refreshPreview: { await self.refreshSuiSendPreview() },
                clearPreview: { self.sendPreviewStore.suiSendPreview = nil }
            )
            return
        }
        if holding.chainName == "Aptos", holding.symbol == "APT" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.aptos, chainName: "Aptos", symbol: "APT",
                feeDecimals: 6, checkSelfSend: true, supportsPrivateKey: false,
                resolveAddress: { self.resolvedAptosAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .aptos) },
                getPreviewFee: { self.sendPreviewStore.aptosSendPreview?.estimatedNetworkFeeApt },
                refreshPreview: { await self.refreshAptosSendPreview() },
                clearPreview: { self.sendPreviewStore.aptosSendPreview = nil }
            )
            return
        }
        if holding.chainName == "TON", holding.symbol == "TON" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.ton, chainName: "TON", symbol: "TON",
                feeDecimals: 6, checkSelfSend: true, supportsPrivateKey: false,
                resolveAddress: { self.resolvedTONAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .ton) },
                getPreviewFee: { self.sendPreviewStore.tonSendPreview?.estimatedNetworkFeeTon },
                refreshPreview: { await self.refreshTonSendPreview() },
                clearPreview: { self.sendPreviewStore.tonSendPreview = nil }
            )
            return
        }
        if holding.chainName == "Internet Computer", holding.symbol == "ICP" {
            guard !sendingChains.contains("Internet Computer") else { return }
            if sendPreviewStore.icpSendPreview == nil { await refreshIcpSendPreview() }
            guard let walletIndex = wallets.firstIndex(where: { $0.id == wallet.id }), let sourceAddress = resolvedICPAddress(for: wallet)
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
            if requiresSelfSendConfirmation(
                wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount
            ) {
                return
            }
            sendingChains.insert("Internet Computer")
            defer { sendingChains.remove("Internet Computer") }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: SpectraChainID.icp, chainName: "Internet Computer",
                        derivationPath: wallet.seedDerivationPaths.internetComputer,
                        seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.sendPreviewStore.icpSendPreview = nil
                    self.wallets[walletIndex] = self.wallets[walletIndex]
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if isEVMChain(holding.chainName) {
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
            var highRiskReasons = evaluateHighRiskSendReasons(
                wallet: wallet, holding: holding, amount: amount, destinationAddress: destinationAddress,
                destinationInput: destinationInput, usedENSResolution: usedENSResolution
            )
            if let chain = evmChainContext(for: holding.chainName) {
                let preflightReasons = await evmRecipientPreflightReasons(
                    holding: holding, chain: chain, destinationAddress: destinationAddress
                )
                highRiskReasons.append(contentsOf: preflightReasons)
            }
            if !highRiskReasons.isEmpty {
                pendingHighRiskSendReasons = highRiskReasons
                isShowingHighRiskSendConfirmation = true
                sendError = nil
                return
            }
        } else {
            bypassHighRiskSendConfirmation = false
        }
        if requiresSelfSendConfirmation(
            wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount
        ) {
            return
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction send") else { return }
        if holding.symbol == "BTC" {
            guard amount > 0 else {
                sendError = "Enter a valid amount"
                return
            }
            guard !sendingChains.contains("Bitcoin") else { return }
            sendingChains.insert("Bitcoin")
            defer { sendingChains.remove("Bitcoin") }
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
                        chainId: SpectraChainID.bitcoin, chainName: "Bitcoin",
                        derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateSvB, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.sendPreviewStore.bitcoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "BCH", holding.chainName == "Bitcoin Cash" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.bitcoinCash, chainName: "Bitcoin Cash", chain: .bitcoinCash,
                symbol: "BCH", feeFallback: 0.00001, resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) },
                getPreview: { self.sendPreviewStore.bitcoinCashSendPreview }, refreshPreview: { await self.refreshBitcoinCashSendPreview() },
                clearPreview: { self.sendPreviewStore.bitcoinCashSendPreview = nil }
            )
            return
        }
        if holding.symbol == "BSV", holding.chainName == "Bitcoin SV" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinSv,
                chainName: "Bitcoin SV", chain: .bitcoinSV, symbol: "BSV", feeFallback: 0.00001,
                resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, getPreview: { self.sendPreviewStore.bitcoinSVSendPreview },
                refreshPreview: { await self.refreshBitcoinSVSendPreview() }, clearPreview: { self.sendPreviewStore.bitcoinSVSendPreview = nil }
            )
            return
        }
        if holding.symbol == "LTC", holding.chainName == "Litecoin" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.litecoin,
                chainName: "Litecoin", chain: .litecoin, symbol: "LTC", feeFallback: 0.0001,
                resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, getPreview: { self.sendPreviewStore.litecoinSendPreview },
                refreshPreview: { await self.refreshLitecoinSendPreview() }, clearPreview: { self.sendPreviewStore.litecoinSendPreview = nil }
            )
            return
        }
        if holding.symbol == "DOGE", holding.chainName == "Dogecoin" {
            guard !sendingChains.contains("Dogecoin") else { return }
            guard let dogecoinAmount = parseDogecoinAmountInput(sendAmount) else {
                sendError = "Enter a valid DOGE amount with up to 8 decimal places."
                return
            }
            guard isValidDogecoinAddressForPolicy(destinationAddress, networkMode: dogecoinNetworkMode(for: wallet)) else {
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
            sendingChains.insert("Dogecoin")
            defer { sendingChains.remove("Dogecoin") }
            guard let sourceAddress = resolvedDogecoinAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address."
                return
            }
            do {
                let feeRateDogePerKb = sendPreviewStore.dogecoinSendPreview?.estimatedFeeRateDogePerKb ?? 0.01
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: SpectraChainID.dogecoin, chainName: "Dogecoin",
                        derivationPath: walletDerivationPath(for: wallet, chain: .dogecoin),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: dogecoinAmount,
                        contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateDogePerKb, feeSat: nil, gasBudget: nil, feeAmount: nil,
                        evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: dogecoinAmount, address: destinationAddress,
                        transactionHash: result.transactionHash,
                        feePriorityRaw: dogecoinFeePriority.rawValue,
                        confirmationCount: 0,
                        dogecoinEstimatedFeeRateDogePerKb: sendPreviewStore.dogecoinSendPreview?.estimatedFeeRateDogePerKb,
                        usedChangeOutput: sendPreviewStore.dogecoinSendPreview?.usesChangeOutput, sourceAddress: sourceAddress,
                        signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                clearSendVerificationNotice()
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: result.transactionHash)
                await refreshDogecoinTransactions()
                await refreshPendingDogecoinTransactions()
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
        if holding.chainName == "Tron", holding.symbol == "TRX" || holding.symbol == "USDT" {
            guard !sendingChains.contains("Tron") else { return }
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
                amount: amount, networkFee: preview.estimatedNetworkFeeTrx, holdingBalance: holding.amount,
                isNativeAsset: holding.symbol == "TRX", symbol: holding.symbol,
                nativeSymbol: "TRX", nativeBalance: wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount,
                feeDecimals: 6, chainLabel: "Tron"
            ) {
                sendError = err; return
            }
            sendingChains.insert("Tron")
            defer { sendingChains.remove("Tron") }
            do {
                let contractAddress: String? = (holding.symbol == "TRX") ? nil : holding.contractAddress
                let tokenDecimals: UInt32? = (contractAddress != nil) ? 6 : nil
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: SpectraChainID.tron, chainName: "Tron", derivationPath: wallet.seedDerivationPaths.tron,
                        seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.sendPreviewStore.tronSendPreview = nil
                    self.tronLastSendErrorDetails = nil
                    self.tronLastSendErrorAt = nil
                }
            } catch {
                let message = userFacingTronSendError(error, symbol: holding.symbol)
                sendError = message
                recordTronSendDiagnosticError(message)
                noteSendBroadcastFailure(for: holding.chainName, message: message)
            }
            return
        }
        if isSupportedSolanaSendCoin(holding) {
            guard !sendingChains.contains("Solana") else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = resolvedSolanaAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Solana signing address from the seed phrase."
                return
            }
            if sendPreviewStore.solanaSendPreview == nil { await refreshSolanaSendPreview() }
            guard let preview = sendPreviewStore.solanaSendPreview else {
                sendError = sendError ?? "Unable to estimate Solana network fee."
                return
            }
            if let err = validateSendBalance(
                amount: amount, networkFee: preview.estimatedNetworkFeeSol, holdingBalance: holding.amount,
                isNativeAsset: holding.symbol == "SOL", symbol: holding.symbol,
                nativeSymbol: "SOL",
                nativeBalance: wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount,
                feeDecimals: 6, chainLabel: "Solana"
            ) {
                sendError = err; return
            }
            sendingChains.insert("Solana")
            defer { sendingChains.remove("Solana") }
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
                        chainId: SpectraChainID.solana, chainName: "Solana",
                        derivationPath: walletDerivationPath(for: wallet, chain: .solana),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.sendPreviewStore.solanaSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "XRP Ledger", holding.symbol == "XRP" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.xrp, chainName: "XRP Ledger", symbol: "XRP",
                feeDecimals: 6, supportsPrivateKey: true,
                resolveAddress: { self.resolvedXRPAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .xrp) },
                getPreviewFee: { self.sendPreviewStore.xrpSendPreview?.estimatedNetworkFeeXrp },
                refreshPreview: { await self.refreshXrpSendPreview() },
                clearPreview: { self.sendPreviewStore.xrpSendPreview = nil }
            )
            return
        }
        if holding.chainName == "Stellar", holding.symbol == "XLM" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.stellar, chainName: "Stellar", symbol: "XLM",
                feeDecimals: 7, supportsPrivateKey: true,
                resolveAddress: { self.resolvedStellarAddress(for: $0) },
                derivationPath: { $0.seedDerivationPaths.stellar },
                getPreviewFee: { self.sendPreviewStore.stellarSendPreview?.estimatedNetworkFeeXlm },
                refreshPreview: { await self.refreshStellarSendPreview() },
                clearPreview: { self.sendPreviewStore.stellarSendPreview = nil }
            )
            return
        }
        if holding.chainName == "Monero", holding.symbol == "XMR" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.monero, chainName: "Monero", symbol: "XMR",
                feeDecimals: 6, supportsPrivateKey: false, moneroPriority: 2,
                resolveAddress: { self.resolvedMoneroAddress(for: $0) },
                derivationPath: { _ in "" },
                getPreviewFee: { self.sendPreviewStore.moneroSendPreview?.estimatedNetworkFeeXmr },
                refreshPreview: { await self.refreshMoneroSendPreview() },
                clearPreview: { self.sendPreviewStore.moneroSendPreview = nil }
            )
            return
        }
        if holding.chainName == "Cardano", holding.symbol == "ADA" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.cardano, chainName: "Cardano", symbol: "ADA",
                feeDecimals: 6, supportsPrivateKey: false, feeAmountFromFee: true,
                resolveAddress: { self.resolvedCardanoAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .cardano) },
                getPreviewFee: { self.sendPreviewStore.cardanoSendPreview?.estimatedNetworkFeeAda },
                refreshPreview: { await self.refreshCardanoSendPreview() },
                clearPreview: { self.sendPreviewStore.cardanoSendPreview = nil }
            )
            return
        }
        if holding.chainName == "NEAR", holding.symbol == "NEAR" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.near, chainName: "NEAR", symbol: "NEAR",
                feeDecimals: 6, checkSelfSend: true, supportsPrivateKey: false,
                resolveAddress: { self.resolvedNearAddress(for: $0) },
                derivationPath: { self.walletDerivationPath(for: $0, chain: .near) },
                getPreviewFee: { self.sendPreviewStore.nearSendPreview?.estimatedNetworkFeeNear },
                refreshPreview: { await self.refreshNearSendPreview() },
                clearPreview: { self.sendPreviewStore.nearSendPreview = nil }
            )
            return
        }
        if holding.chainName == "NEAR", holding.tokenStandard == "NEP-141", let contractAddress = holding.contractAddress {
            guard !sendingChains.contains("NEAR") else { return }
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
            sendingChains.insert("NEAR")
            defer { sendingChains.remove("NEAR") }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(
                    SendExecutionRequest(
                        chainId: SpectraChainID.near, chainName: "NEAR", derivationPath: walletDerivationPath(for: wallet, chain: .near),
                        seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress,
                        amount: amount,
                        contractAddress: contractAddress, tokenDecimals: UInt32(decimals), feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                        signedTransactionPayloadFormat: result.payloadFormat
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.sendPreviewStore.nearSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Polkadot", holding.symbol == "DOT" {
            await submitSimpleNativeChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount,
                chainId: SpectraChainID.polkadot, chainName: "Polkadot", symbol: "DOT",
                feeDecimals: 6, supportsPrivateKey: false,
                resolveAddress: { self.resolvedPolkadotAddress(for: $0) },
                derivationPath: { $0.seedDerivationPaths.polkadot },
                getPreviewFee: { self.sendPreviewStore.polkadotSendPreview?.estimatedNetworkFeeDot },
                refreshPreview: { await self.refreshPolkadotSendPreview() },
                clearPreview: { self.sendPreviewStore.polkadotSendPreview = nil }
            )
            return
        }
        if isEVMChain(holding.chainName) {
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
                amount: amount, networkFee: preview.estimatedNetworkFeeEth,
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
                let spectraEvmChainId = SpectraChainID.id(for: holding.chainName)
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
                        amount: amount,
                        contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil,
                        feeAmount: nil, evmOverrides: evmOverrides, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                    ))
                let fallbackNonce = explicitNonce.map(Int64.init) ?? sendPreviewStore.ethereumSendPreview?.nonce ?? 0
                let typed = result.evm ?? EvmSendResultDecoded(txid: "", rawTxHex: "", nonce: fallbackNonce, gasLimit: 0)
                let evmResult = ethereumSendResult(from: typed)
                let transaction = decoratePendingSendTransaction(
                    TransactionRecord(
                        walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                        symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                        transactionHash: result.transactionHash, ethereumNonce: Int(evmResult.preview.nonce),
                        signedTransactionPayload: evmResult.rawTransactionHex, signedTransactionPayloadFormat: "evm.raw_hex"
                    ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: evmResult.verificationStatus)
                resetSendComposerState()
            } catch {
                sendError = mapEthereumSendError(error)
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        sendError = "\(holding.chainName) native sending is not enabled yet."
    }

    @MainActor private func submitSimpleNativeChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double,
        chainId: UInt32, chainName: String, symbol: String,
        feeDecimals: UInt32, checkSelfSend: Bool = false, supportsPrivateKey: Bool,
        gasBudgetFromFee: Bool = false, feeAmountFromFee: Bool = false, moneroPriority: UInt32? = nil,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        derivationPath: @escaping (ImportedWallet) -> String,
        getPreviewFee: @escaping () -> Double?,
        refreshPreview: @escaping () async -> Void,
        clearPreview: @escaping () -> Void
    ) async {
        guard !sendingChains.contains(chainName) else { return }
        let isMonero = moneroPriority != nil
        let seedPhrase = isMonero ? nil : storedSeedPhrase(for: wallet.id)
        let privateKey = supportsPrivateKey ? storedPrivateKey(for: wallet.id) : (isMonero ? "unused" : nil)
        if !isMonero {
            if supportsPrivateKey {
                guard seedPhrase != nil || privateKey != nil else { sendError = "This wallet's signing key is unavailable."; return }
            } else {
                guard seedPhrase != nil else { sendError = "This wallet's seed phrase is unavailable."; return }
            }
        }
        guard let sourceAddress = resolveAddress(wallet) else {
            sendError = "Unable to resolve this wallet's \(symbol) signing address."
            return
        }
        if getPreviewFee() == nil { await refreshPreview() }
        guard let fee = getPreviewFee() else { sendError = sendError ?? "Unable to estimate \(chainName) network fee."; return }
        if let err = validateSendBalance(
            amount: amount, networkFee: fee, holdingBalance: holding.amount,
            isNativeAsset: true, symbol: symbol, nativeSymbol: nil, nativeBalance: nil,
            feeDecimals: Int(feeDecimals), chainLabel: nil
        ) {
            sendError = err; return
        }
        if checkSelfSend,
            requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount)
        {
            return
        }
        sendingChains.insert(chainName)
        defer { sendingChains.remove(chainName) }
        do {
            let result = try await WalletServiceBridge.shared.executeSend(
                SendExecutionRequest(
                    chainId: chainId, chainName: chainName, derivationPath: derivationPath(wallet),
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress,
                    amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil,
                    gasBudget: gasBudgetFromFee ? fee : nil, feeAmount: feeAmountFromFee ? fee : nil,
                    evmOverrides: nil, moneroPriority: moneroPriority, derivationOverrides: wallet.derivationOverrides
                ))
            let transaction = decoratePendingSendTransaction(
                TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                    symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                    transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                    signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }
    }

    @MainActor private func submitUTXOSatChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, chainId: UInt32, chainName: String,
        chain: SeedDerivationChain, symbol: String, feeFallback: Double,
        resolveAddress: @escaping (ImportedWallet) -> String?, getPreview: @escaping () -> BitcoinSendPreview?,
        refreshPreview: @escaping () async -> Void, clearPreview: @escaping () -> Void
    ) async {
        guard amount > 0 else { sendError = "Enter a valid amount"; return }
        guard !sendingChains.contains(chainName) else { return }
        sendingChains.insert(chainName)
        defer { sendingChains.remove(chainName) }
        do {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolveAddress(wallet) else {
                sendError = "Unable to resolve this wallet's \(symbol) address from the seed phrase."; return
            }
            if getPreview() == nil { await refreshPreview() }
            if let preview = getPreview() {
                if let err = validateSendBalance(
                    amount: amount, networkFee: preview.estimatedNetworkFeeBtc, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: symbol, nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 8, chainLabel: nil
                ) {
                    sendError = err; return
                }
            }
            let feeSat = UInt64((getPreview()?.estimatedNetworkFeeBtc ?? feeFallback) * 1e8)
            let result = try await WalletServiceBridge.shared.executeSend(
                SendExecutionRequest(
                    chainId: chainId, chainName: chainName, derivationPath: walletDerivationPath(for: wallet, chain: chain),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: feeSat, gasBudget: nil, feeAmount: nil,
                    evmOverrides: nil, moneroPriority: nil, derivationOverrides: wallet.derivationOverrides
                ))
            let transaction = decoratePendingSendTransaction(
                TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name,
                    symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress,
                    transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson,
                    signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }
    }
}
