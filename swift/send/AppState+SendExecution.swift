import Foundation

// MARK: - Pure JSON helpers (no store state)

func rustField(_ key: String, from json: String) -> String {
    extractJsonStringField(json: json, key: key)
}

private func evmOverridesJSONFragment(nonce: Int?, customFees: EthereumCustomFeeConfiguration?) -> String {
    let customDTO: EvmCustomFeeConfiguration? = customFees.map {
        EvmCustomFeeConfiguration(maxFeePerGasGwei: $0.maxFeePerGasGwei, maxPriorityFeePerGasGwei: $0.maxPriorityFeePerGasGwei)
    }
    return buildEvmOverridesJsonFragment(nonce: nonce.map(Int64.init), customFees: customDTO)
}

private func decodeEvmSendResult(_ json: String, fallbackNonce: Int64) -> EthereumSendResult {
    let d = decodeEvmSendResult(json: json, fallbackNonce: fallbackNonce)
    let preview = EthereumSendPreview(
        nonce: d.nonce, gasLimit: d.gasLimit, maxFeePerGasGwei: 0, maxPriorityFeePerGasGwei: 0, estimatedNetworkFeeEth: 0, spendableBalance: nil, feeRateDescription: nil, estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: nil
    )
    return EthereumSendResult(
        fromAddress: "", transactionHash: d.txid, rawTransactionHex: d.rawTxHex, preview: preview, verificationStatus: .verified
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
            walletIndex.map { wallets[$0].holdings[holdingIndex] }}
        let preflight: WalletRustSendSubmitPreflightPlan
        do {
            preflight = try WalletRustAppCoreBridge.planSendSubmitPreflight(
                WalletRustSendSubmitPreflightRequest(
                    walletFound: walletIndex != nil, assetFound: holdingIndex != nil, destinationAddress: destinationInput, amountInput: sendAmount, availableBalance: selectedCoin?.amount ?? 0, asset: selectedCoin.map {
                        WalletRustSendAssetRoutingInput(
                            chainName: $0.chainName, symbol: $0.symbol, isEvmChain: isEVMChain($0.chainName), supportsSolanaSendCoin: isSupportedSolanaSendCoin($0), supportsNearTokenSend: isSupportedNearTokenSend($0)
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
            guard !isSendingSui else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedSuiAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Sui signing address from the seed phrase."; return }
            if suiSendPreview == nil { await refreshSuiSendPreview() }
            guard let preview = suiSendPreview else { sendError = sendError ?? "Unable to estimate Sui network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeSui, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "SUI", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            if requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
            isSendingSui = true
            defer { isSendingSui = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.sui, chainName: "Sui", derivationPath: walletDerivationPath(for: wallet, chain: .sui),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: preview.estimatedNetworkFeeSui, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.suiSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Aptos", holding.symbol == "APT" {
            guard !isSendingAptos else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedAptosAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Aptos signing address from the seed phrase."; return }
            if aptosSendPreview == nil { await refreshAptosSendPreview() }
            guard let preview = aptosSendPreview else { sendError = sendError ?? "Unable to estimate Aptos network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeApt, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "APT", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            if requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
            isSendingAptos = true
            defer { isSendingAptos = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.aptos, chainName: "Aptos", derivationPath: walletDerivationPath(for: wallet, chain: .aptos),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.aptosSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "TON", holding.symbol == "TON" {
            guard !isSendingTON else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedTONAddress(for: wallet) else { sendError = "Unable to resolve this wallet's TON signing address from the seed phrase."; return }
            if tonSendPreview == nil { await refreshTonSendPreview() }
            guard let preview = tonSendPreview else { sendError = sendError ?? "Unable to estimate TON network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeTon, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "TON", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            if requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
            isSendingTON = true
            defer { isSendingTON = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.ton, chainName: "TON", derivationPath: walletDerivationPath(for: wallet, chain: .ton),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.tonSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Internet Computer", holding.symbol == "ICP" {
            guard !isSendingICP else { return }
            if icpSendPreview == nil { await refreshIcpSendPreview() }
            guard let walletIndex = wallets.firstIndex(where: { $0.id == wallet.id }), let sourceAddress = resolvedICPAddress(for: wallet) else {
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
            isSendingICP = true
            defer { isSendingICP = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.icp, chainName: "Internet Computer", derivationPath: wallet.seedDerivationPaths.internetComputer,
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.icpSendPreview = nil
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
            }}
        if !bypassHighRiskSendConfirmation {
            var highRiskReasons = evaluateHighRiskSendReasons(
                wallet: wallet, holding: holding, amount: amount, destinationAddress: destinationAddress, destinationInput: destinationInput, usedENSResolution: usedENSResolution
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
        } else { bypassHighRiskSendConfirmation = false }
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
            guard !isSendingBitcoin else { return }
            isSendingBitcoin = true
            defer { isSendingBitcoin = false }
            do {
                guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                    sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = resolvedBitcoinAddress(for: wallet) else {
                    sendError = "Unable to resolve this wallet's Bitcoin address from the seed phrase."
                    return
                }
                if bitcoinSendPreview == nil { await refreshBitcoinSendPreview() }
                let feeRateSvB: Double = Double(bitcoinSendPreview?.estimatedFeeRateSatVb ?? 10)
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.bitcoin, chainName: "Bitcoin", derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateSvB, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.bitcoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "BCH", holding.chainName == "Bitcoin Cash" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinCash, chainName: "Bitcoin Cash", chain: .bitcoinCash, isSendingPath: \.isSendingBitcoinCash, symbol: "BCH", feeFallback: 0.00001, resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, getPreview: { self.bitcoinCashSendPreview }, refreshPreview: { await self.refreshBitcoinCashSendPreview() }, clearPreview: { self.bitcoinCashSendPreview = nil }
            )
            return
        }
        if holding.symbol == "BSV", holding.chainName == "Bitcoin SV" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinSv, chainName: "Bitcoin SV", chain: .bitcoinSV, isSendingPath: \.isSendingBitcoinSV, symbol: "BSV", feeFallback: 0.00001, resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, getPreview: { self.bitcoinSVSendPreview }, refreshPreview: { await self.refreshBitcoinSVSendPreview() }, clearPreview: { self.bitcoinSVSendPreview = nil }
            )
            return
        }
        if holding.symbol == "LTC", holding.chainName == "Litecoin" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.litecoin, chainName: "Litecoin", chain: .litecoin, isSendingPath: \.isSendingLitecoin, symbol: "LTC", feeFallback: 0.0001, resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, getPreview: { self.litecoinSendPreview }, refreshPreview: { await self.refreshLitecoinSendPreview() }, clearPreview: { self.litecoinSendPreview = nil }
            )
            return
        }
        if holding.symbol == "DOGE", holding.chainName == "Dogecoin" {
            guard !isSendingDogecoin else { return }
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
            if dogecoinSendPreview == nil { await refreshDogecoinSendPreview() }
            if let dogecoinSendPreview = dogecoinSendPreview, dogecoinAmount > dogecoinSendPreview.maxSendableDoge {
                sendError = "Insufficient DOGE for amount plus network fee (max sendable ~\(String(format: "%.6f", dogecoinSendPreview.maxSendableDoge)) DOGE)."
                return
            }
            isSendingDogecoin = true
            defer { isSendingDogecoin = false }
            guard let sourceAddress = resolvedDogecoinAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Dogecoin signing address."
                return
            }
            do {
                let feeRateDogePerKb = dogecoinSendPreview?.estimatedFeeRateDogePerKb ?? 0.01
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.dogecoin, chainName: "Dogecoin", derivationPath: walletDerivationPath(for: wallet, chain: .dogecoin),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: dogecoinAmount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: feeRateDogePerKb, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: dogecoinAmount, address: destinationAddress, transactionHash: result.transactionHash, dogecoinConfirmations: 0, dogecoinFeePriorityRaw: dogecoinFeePriority.rawValue, dogecoinEstimatedFeeRateDogePerKb: dogecoinSendPreview?.estimatedFeeRateDogePerKb, dogecoinUsedChangeOutput: dogecoinSendPreview?.usesChangeOutput, sourceAddress: sourceAddress, dogecoinRawTransactionHex: result.resultJson, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                clearSendVerificationNotice()
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: result.transactionHash)
                await refreshDogecoinTransactions()
                await refreshPendingDogecoinTransactions()
                updateSendVerificationNoticeForLastSentTransaction()
                resetSendComposerState {
                    self.dogecoinSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE send failed: \(error.localizedDescription)")
                noteSendBroadcastFailure(for: holding.chainName, message: error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Tron", holding.symbol == "TRX" || holding.symbol == "USDT" {
            guard !isSendingTron else { return }
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
            if tronSendPreview == nil { await refreshTronSendPreview() }
            guard let preview = tronSendPreview else {
                sendError = sendError ?? "Unable to estimate Tron network fee."
                return
            }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeTrx, holdingBalance: holding.amount,
                    isNativeAsset: holding.symbol == "TRX", symbol: holding.symbol,
                    nativeSymbol: "TRX", nativeBalance: wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount,
                    feeDecimals: 6, chainLabel: "Tron"
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingTron = true
            defer { isSendingTron = false }
            do {
                let contractAddress: String? = (holding.symbol == "TRX") ? nil : holding.contractAddress
                let tokenDecimals: UInt32? = (contractAddress != nil) ? 6 : nil
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.tron, chainName: "Tron", derivationPath: wallet.seedDerivationPaths.tron,
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: "tron.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.tronSendPreview = nil
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
            guard !isSendingSolana else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = resolvedSolanaAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Solana signing address from the seed phrase."
                return
            }
            if solanaSendPreview == nil { await refreshSolanaSendPreview() }
            guard let preview = solanaSendPreview else {
                sendError = sendError ?? "Unable to estimate Solana network fee."
                return
            }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeSol, holdingBalance: holding.amount,
                    isNativeAsset: holding.symbol == "SOL", symbol: holding.symbol,
                    nativeSymbol: "SOL", nativeBalance: wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount,
                    feeDecimals: 6, chainLabel: "Solana"
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingSolana = true
            defer { isSendingSolana = false }
            do {
                let contractAddress: String?
                let tokenDecimals: UInt32?
                if holding.symbol == "SOL" {
                    contractAddress = nil
                    tokenDecimals = nil
                } else {
                    let solanaTokenMetadataByMint = solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol), let tokenMetadata = solanaTokenMetadataByMint[mintAddress] else {
                        sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    contractAddress = mintAddress
                    tokenDecimals = UInt32(tokenMetadata.decimals)
                }
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.solana, chainName: "Solana", derivationPath: walletDerivationPath(for: wallet, chain: .solana),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: "solana.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.solanaSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "XRP Ledger", holding.symbol == "XRP" {
            guard !isSendingXRP else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."; return
            }
            guard let sourceAddress = resolvedXRPAddress(for: wallet) else { sendError = "Unable to resolve this wallet's XRP signing address."; return }
            if xrpSendPreview == nil { await refreshXrpSendPreview() }
            guard let preview = xrpSendPreview else { sendError = sendError ?? "Unable to estimate XRP network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeXrp, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "XRP", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingXRP = true
            defer { isSendingXRP = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.xrp, chainName: "XRP Ledger", derivationPath: walletDerivationPath(for: wallet, chain: .xrp),
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.xrpSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Stellar", holding.symbol == "XLM" {
            guard !isSendingStellar else { return }
            let seedPhrase = storedSeedPhrase(for: wallet.id)
            let privateKey = storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                sendError = "This wallet's signing key is unavailable."; return
            }
            guard let sourceAddress = resolvedStellarAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Stellar signing address."; return }
            if stellarSendPreview == nil { await refreshStellarSendPreview() }
            guard let preview = stellarSendPreview else { sendError = sendError ?? "Unable to estimate Stellar network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeXlm, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "XLM", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 7, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingStellar = true
            defer { isSendingStellar = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.stellar, chainName: "Stellar", derivationPath: wallet.seedDerivationPaths.stellar,
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.stellarSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Monero", holding.symbol == "XMR" {
            guard !isSendingMonero else { return }
            guard let sourceAddress = resolvedMoneroAddress(for: wallet) else {
                sendError = "Unable to resolve this wallet's Monero address."
                return
            }
            if moneroSendPreview == nil { await refreshMoneroSendPreview() }
            guard let preview = moneroSendPreview else {
                sendError = sendError ?? "Unable to estimate Monero network fee."
                return
            }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeXmr, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "XMR", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingMonero = true
            defer { isSendingMonero = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.monero, chainName: "Monero", derivationPath: "",
                    seedPhrase: nil, privateKeyHex: "unused", fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: 2
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.moneroSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Cardano", holding.symbol == "ADA" {
            guard !isSendingCardano else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedCardanoAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Cardano signing address from the seed phrase."; return }
            if cardanoSendPreview == nil { await refreshCardanoSendPreview() }
            guard let preview = cardanoSendPreview else { sendError = sendError ?? "Unable to estimate Cardano network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeAda, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "ADA", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingCardano = true
            defer { isSendingCardano = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.cardano, chainName: "Cardano", derivationPath: walletDerivationPath(for: wallet, chain: .cardano),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: preview.estimatedNetworkFeeAda, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.cardanoSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "NEAR", holding.symbol == "NEAR" {
            guard !isSendingNear else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedNearAddress(for: wallet) else { sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."; return }
            if nearSendPreview == nil { await refreshNearSendPreview() }
            guard let preview = nearSendPreview else { sendError = sendError ?? "Unable to estimate NEAR network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeNear, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "NEAR", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            if requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
            isSendingNear = true
            defer { isSendingNear = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.near, chainName: "NEAR", derivationPath: walletDerivationPath(for: wallet, chain: .near),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.nearSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "NEAR", holding.tokenStandard == "NEP-141", let contractAddress = holding.contractAddress {
            guard !isSendingNear else { return }
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
            isSendingNear = true
            defer { isSendingNear = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.near, chainName: "NEAR", derivationPath: walletDerivationPath(for: wallet, chain: .near),
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: contractAddress, tokenDecimals: UInt32(decimals), feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState {
                    self.nearSendPreview = nil
                }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.chainName == "Polkadot", holding.symbol == "DOT" {
            guard !isSendingPolkadot else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedPolkadotAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Polkadot signing address from the seed phrase."; return }
            if polkadotSendPreview == nil { await refreshPolkadotSendPreview() }
            guard let preview = polkadotSendPreview else { sendError = sendError ?? "Unable to estimate Polkadot network fee."; return }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeDot, holdingBalance: holding.amount,
                    isNativeAsset: true, symbol: "DOT", nativeSymbol: nil, nativeBalance: nil,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingPolkadot = true
            defer { isSendingPolkadot = false }
            do {
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: SpectraChainID.polkadot, chainName: "Polkadot", derivationPath: wallet.seedDerivationPaths.polkadot,
                    seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
                ))
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                resetSendComposerState { self.polkadotSendPreview = nil }
            } catch {
                sendError = error.localizedDescription
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        if isEVMChain(holding.chainName) {
            guard evmChainContext(for: holding.chainName) != nil else {
                sendError = "\(holding.chainName) native sending is not enabled yet."
                return
            }
            guard !isSendingEthereum else { return }
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
            let nativeBalance = wallet.holdings.first(where: { $0.chainName == holding.chainName && $0.symbol == nativeSymbol })?.amount ?? 0
            if ethereumSendPreview == nil { await refreshEthereumSendPreview() }
            guard let preview = ethereumSendPreview else {
                sendError = sendError ?? "Unable to estimate \(holding.chainName) network fee."
                return
            }
            do {
                try coreValidateSendBalance(request: SendBalanceValidationRequest(
                    amount: amount, networkFee: preview.estimatedNetworkFeeEth, holdingBalance: preflight.isNativeEvmAsset ? nativeBalance : holding.amount,
                    isNativeAsset: preflight.isNativeEvmAsset, symbol: preflight.isNativeEvmAsset ? nativeSymbol : holding.symbol,
                    nativeSymbol: nativeSymbol, nativeBalance: nativeBalance,
                    feeDecimals: 6, chainLabel: nil
                ))
            } catch { sendError = error.localizedDescription; return }
            isSendingEthereum = true
            activeEthereumSendWalletIDs.insert(wallet.id)
            defer {
                isSendingEthereum = false
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
                let overridesFragment = evmOverridesJSONFragment(nonce: explicitNonce, customFees: customFees)
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
                let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                    chainId: chainId, chainName: holding.chainName, derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain),
                    seedPhrase: seedPhrase, privateKeyHex: privateKey, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                    contractAddress: contractAddress, tokenDecimals: tokenDecimals, feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil, evmOverridesFragment: overridesFragment, moneroPriority: nil
                ))
                let evmResult = decodeEvmSendResult(
                    result.resultJson, fallbackNonce: explicitNonce.map(Int64.init) ?? ethereumSendPreview?.nonce ?? 0
                )
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, ethereumNonce: Int(evmResult.preview.nonce), signedTransactionPayload: evmResult.rawTransactionHex, signedTransactionPayloadFormat: "evm.raw_hex"
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

    @MainActor private func submitUTXOSatChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, chainId: UInt32, chainName: String, chain: SeedDerivationChain, isSendingPath: ReferenceWritableKeyPath<AppState, Bool>, symbol: String, feeFallback: Double, resolveAddress: @escaping (ImportedWallet) -> String?, getPreview: @escaping () -> BitcoinSendPreview?, refreshPreview: @escaping () async -> Void, clearPreview: @escaping () -> Void
    ) async {
        guard amount > 0 else { sendError = "Enter a valid amount"; return }
        guard !self[keyPath: isSendingPath] else { return }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolveAddress(wallet) else { sendError = "Unable to resolve this wallet's \(symbol) address from the seed phrase."; return }
            if getPreview() == nil { await refreshPreview() }
            if let preview = getPreview() {
                do {
                    try coreValidateSendBalance(request: SendBalanceValidationRequest(
                        amount: amount, networkFee: preview.estimatedNetworkFeeBtc, holdingBalance: holding.amount,
                        isNativeAsset: true, symbol: symbol, nativeSymbol: nil, nativeBalance: nil,
                        feeDecimals: 8, chainLabel: nil
                    ))
                } catch { sendError = error.localizedDescription; return }
            }
            let amountSat = UInt64(amount * 1e8)
            let feeSat = UInt64((getPreview()?.estimatedNetworkFeeBtc ?? feeFallback) * 1e8)
            let result = try await WalletServiceBridge.shared.executeSend(SendExecutionRequest(
                chainId: chainId, chainName: chainName, derivationPath: walletDerivationPath(for: wallet, chain: chain),
                seedPhrase: seedPhrase, privateKeyHex: nil, fromAddress: sourceAddress, toAddress: destinationAddress, amount: amount,
                contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: feeSat, gasBudget: nil, feeAmount: nil, evmOverridesFragment: nil, moneroPriority: nil
            ))
            let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, signedTransactionPayload: result.resultJson, signedTransactionPayloadFormat: result.payloadFormat
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}
}
