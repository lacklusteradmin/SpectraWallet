import Foundation

// MARK: - Pure JSON helpers (no store state)

func rustField(_ key: String, from json: String) -> String {
    extractJsonStringField(json: json, key: key)
}

private func ethToWeiString(_ eth: Double) -> String { amountToRawUnitsString(amount: eth, decimals: 18) }

private func tokenAmountToRawString(_ amount: Double, decimals: Int) -> String {
    amountToRawUnitsString(amount: amount, decimals: UInt32(decimals))
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
                            chainName: $0.chainName, symbol: $0.symbol, isEVMChain: isEVMChain($0.chainName), supportsSolanaSendCoin: isSupportedSolanaSendCoin($0), supportsNearTokenSend: isSupportedNearTokenSend($0)
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
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeSui, symbol: "SUI", isSendingPath: \.isSendingSui, chainId: SpectraChainID.sui, chain: .sui, derivationPath: walletDerivationPath(for: wallet, chain: .sui), sendChain: .sui, checkSelfSend: true, buildJSON: { priv, pub in buildSuiSendPayload(from: sourceAddress, to: destinationAddress, amountSui: amount, gasBudgetSui: preview.estimatedNetworkFeeSui, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.suiSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "Aptos", holding.symbol == "APT" {
            guard !isSendingAptos else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedAptosAddress(for: wallet) else { sendError = "Unable to resolve this wallet's Aptos signing address from the seed phrase."; return }
            if aptosSendPreview == nil { await refreshAptosSendPreview() }
            guard let preview = aptosSendPreview else { sendError = sendError ?? "Unable to estimate Aptos network fee."; return }
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeApt, symbol: "APT", isSendingPath: \.isSendingAptos, chainId: SpectraChainID.aptos, chain: .aptos, derivationPath: walletDerivationPath(for: wallet, chain: .aptos), sendChain: .aptos, checkSelfSend: true, buildJSON: { priv, pub in buildAptosSendPayload(from: sourceAddress, to: destinationAddress, amountApt: amount, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.aptosSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "TON", holding.symbol == "TON" {
            guard !isSendingTON else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedTONAddress(for: wallet) else { sendError = "Unable to resolve this wallet's TON signing address from the seed phrase."; return }
            if tonSendPreview == nil { await refreshTonSendPreview() }
            guard let preview = tonSendPreview else { sendError = sendError ?? "Unable to estimate TON network fee."; return }
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeTon, symbol: "TON", isSendingPath: \.isSendingTON, chainId: SpectraChainID.ton, chain: .ton, derivationPath: walletDerivationPath(for: wallet, chain: .ton), sendChain: .ton, checkSelfSend: true, buildJSON: { priv, pub in buildTonSendPayload(from: sourceAddress, to: destinationAddress, amountTon: amount, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.tonSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
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
                let resultJSON: String
                if let seedPhrase {
                    resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.icp, seedPhrase: seedPhrase, chain: .internetComputer, derivationPath: wallet.seedDerivationPaths.internetComputer
                    ) { privKeyHex, pubKeyHex in
                        buildIcpSendPayload(from: sourceAddress, to: destinationAddress, amountIcp: amount, privateKeyHex: privKeyHex, publicKeyHex: pubKeyHex)
                    }
                } else if let privateKey {
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    let paramsJson = buildIcpSendPayload(from: sourceAddress, to: destinationAddress, amountIcp: amount, privateKeyHex: normalizedPriv, publicKeyHex: nil)
                    resultJSON = try await WalletServiceBridge.shared.signAndSend(
                        chainId: SpectraChainID.icp, paramsJson: paramsJson
                    )
                } else { throw NSError(domain: "ICPSend", code: 1, userInfo: [NSLocalizedDescriptionKey: "This wallet seed phrase cannot derive a valid ICP signer."]) }
                let icpOutcome = classifySendBroadcastResult(chain: .icp, resultJson: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: icpOutcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: icpOutcome.payloadFormat
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
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.bitcoin, seedPhrase: seedPhrase, chain: .bitcoin, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin)
                ) { privKeyHex, _ in
                    buildBtcSendPayload(from: sourceAddress, to: destinationAddress, amountBtc: amount, feeRateSvb: feeRateSvB, privateKeyHex: privKeyHex)
                }
                let btcOutcome = classifySendBroadcastResult(chain: .bitcoin, resultJson: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: btcOutcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: btcOutcome.payloadFormat
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
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinCash, chain: .bitcoinCash, isSendingPath: \.isSendingBitcoinCash, symbol: "BCH", feeFallback: 0.00001, sendChain: .bitcoinCash, resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, getPreview: { self.bitcoinCashSendPreview }, refreshPreview: { await self.refreshBitcoinCashSendPreview() }, clearPreview: { self.bitcoinCashSendPreview = nil }
            )
            return
        }
        if holding.symbol == "BSV", holding.chainName == "Bitcoin SV" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.bitcoinSv, chain: .bitcoinSV, isSendingPath: \.isSendingBitcoinSV, symbol: "BSV", feeFallback: 0.00001, sendChain: .bitcoinSv, resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, getPreview: { self.bitcoinSVSendPreview }, refreshPreview: { await self.refreshBitcoinSVSendPreview() }, clearPreview: { self.bitcoinSVSendPreview = nil }
            )
            return
        }
        if holding.symbol == "LTC", holding.chainName == "Litecoin" {
            await submitUTXOSatChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, chainId: SpectraChainID.litecoin, chain: .litecoin, isSendingPath: \.isSendingLitecoin, symbol: "LTC", feeFallback: 0.0001, sendChain: .litecoin, resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, getPreview: { self.litecoinSendPreview }, refreshPreview: { await self.refreshLitecoinSendPreview() }, clearPreview: { self.litecoinSendPreview = nil }
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
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.dogecoin, seedPhrase: seedPhrase, chain: .dogecoin, derivationPath: walletDerivationPath(for: wallet, chain: .dogecoin)
                ) { privKeyHex, _ in
                    buildDogeSendPayload(from: sourceAddress, to: destinationAddress, amountDoge: dogecoinAmount, feeRateDogePerKb: feeRateDogePerKb, privateKeyHex: privKeyHex)
                }
                let dogeOutcome = classifySendBroadcastResult(chain: .dogecoin, resultJson: resultJSON)
                let txid = dogeOutcome.transactionHash
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: dogecoinAmount, address: destinationAddress, transactionHash: txid, dogecoinConfirmations: 0, dogecoinFeePriorityRaw: dogecoinFeePriority.rawValue, dogecoinEstimatedFeeRateDogePerKb: dogecoinSendPreview?.estimatedFeeRateDogePerKb, dogecoinUsedChangeOutput: dogecoinSendPreview?.usesChangeOutput, sourceAddress: sourceAddress, dogecoinRawTransactionHex: resultJSON, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: dogeOutcome.payloadFormat
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                clearSendVerificationNotice()
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: txid)
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
            if holding.symbol == "TRX" {
                let totalCost = amount + preview.estimatedNetworkFeeTrx
                if totalCost > holding.amount {
                    sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: "TRX", totalNeeded: totalCost, decimals: 6)
                    return
                }
            } else {
                let trxBalance = wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount ?? 0
                if preview.estimatedNetworkFeeTrx > trxBalance {
                    sendError = coreInsufficientNativeForFeeMessage(nativeSymbol: "TRX", fee: preview.estimatedNetworkFeeTrx, decimals: 6, chainLabel: "Tron")
                    return
                }}
            isSendingTron = true
            defer { isSendingTron = false }
            do {
                let sendResult: TronSendResult
                if holding.symbol == "TRX", let seedPhrase {
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                        chainId: SpectraChainID.tron, seedPhrase: seedPhrase, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        buildTronNativeSendPayload(from: sourceAddress, to: destinationAddress, amountTrx: amount, privateKeyHex: privKeyHex)
                    }
                    sendResult = TronSendResult(
                        transactionHash: classifySendBroadcastResult(chain: .tron, resultJson: resultJSON).transactionHash, estimatedNetworkFeeTrx: tronSendPreview?.estimatedNetworkFeeTrx ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                    )
                } else if let seedPhrase, let contract = holding.contractAddress {
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.tron, seedPhrase: seedPhrase, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        buildTronTokenSendPayload(from: sourceAddress, contract: contract, to: destinationAddress, amount: amount, decimals: 6, privateKeyHex: privKeyHex)
                    }
                    sendResult = TronSendResult(
                        transactionHash: classifySendBroadcastResult(chain: .tron, resultJson: resultJSON).transactionHash, estimatedNetworkFeeTrx: tronSendPreview?.estimatedNetworkFeeTrx ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                    )
                } else if let privateKey {
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    if holding.symbol == "TRX" {
                        let paramsJson = buildTronNativeSendPayload(from: sourceAddress, to: destinationAddress, amountTrx: amount, privateKeyHex: normalizedPriv)
                        let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                            chainId: SpectraChainID.tron, paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: classifySendBroadcastResult(chain: .tron, resultJson: resultJSON).transactionHash, estimatedNetworkFeeTrx: tronSendPreview?.estimatedNetworkFeeTrx ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                        )
                    } else if let contract = holding.contractAddress {
                        let paramsJson = buildTronTokenSendPayload(from: sourceAddress, contract: contract, to: destinationAddress, amount: amount, decimals: 6, privateKeyHex: normalizedPriv)
                        let resultJSON = try await WalletServiceBridge.shared.signAndSendToken(
                            chainId: SpectraChainID.tron, paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: classifySendBroadcastResult(chain: .tron, resultJson: resultJSON).transactionHash, estimatedNetworkFeeTrx: tronSendPreview?.estimatedNetworkFeeTrx ?? 0, signedTransactionJSON: resultJSON, verificationStatus: .verified
                        )
                    } else {
                        sendError = "Unsupported Tron asset for private-key send."
                        return
                    }
                } else {
                    sendError = "This wallet's signing key is unavailable."
                    return
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: sendResult.transactionHash, signedTransactionPayload: sendResult.signedTransactionJSON, signedTransactionPayloadFormat: "tron.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
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
            if holding.symbol == "SOL" {
                let totalCost = amount + preview.estimatedNetworkFeeSol
                if totalCost > holding.amount {
                    sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: "SOL", totalNeeded: totalCost, decimals: 6)
                    return
                }
            } else {
                if amount > holding.amount {
                    sendError = "Insufficient \(holding.symbol) balance for this transfer."
                    return
                }
                let solBalance = wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount ?? 0
                if preview.estimatedNetworkFeeSol > solBalance {
                    sendError = coreInsufficientNativeForFeeMessage(nativeSymbol: "SOL", fee: preview.estimatedNetworkFeeSol, decimals: 6, chainLabel: "Solana")
                    return
                }}
            isSendingSolana = true
            defer { isSendingSolana = false }
            do {
                let sendResult: SolanaSendResult
                if holding.symbol == "SOL" {
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.solana, seedPhrase: seedPhrase, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        buildSolanaNativeSendPayload(fromPubkeyHex: pubKeyHex, to: destinationAddress, amountSol: amount, privateKeyHex: privKeyHex)
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: classifySendBroadcastResult(chain: .solana, resultJson: resultJSON).transactionHash, estimatedNetworkFeeSol: solanaSendPreview?.estimatedNetworkFeeSol ?? 0, signedTransactionBase64: resultJSON, verificationStatus: .verified
                    )
                } else {
                    let solanaTokenMetadataByMint = solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol), let tokenMetadata = solanaTokenMetadataByMint[mintAddress] else {
                        sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    let decimals = tokenMetadata.decimals
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.solana, seedPhrase: seedPhrase, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        let pk = pubKeyHex ?? ""
                        return buildSolanaTokenSendPayload(fromPubkeyHex: pk, mint: mintAddress, to: destinationAddress, amount: amount, decimals: UInt32(decimals), privateKeyHex: privKeyHex)
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: classifySendBroadcastResult(chain: .solana, resultJson: resultJSON).transactionHash, estimatedNetworkFeeSol: solanaSendPreview?.estimatedNetworkFeeSol ?? 0, signedTransactionBase64: resultJSON, verificationStatus: .verified
                    )
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: sendResult.transactionHash, signedTransactionPayload: sendResult.signedTransactionBase64, signedTransactionPayloadFormat: "solana.rust_json"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
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
            await submitDualKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeXrp, symbol: "XRP", feeDecimals: 6, isSendingPath: \.isSendingXRP, chainId: SpectraChainID.xrp, chain: .xrp, derivationPath: walletDerivationPath(for: wallet, chain: .xrp), sendChain: .xrp, buildSeedJSON: { priv, pub in buildXrpSendPayload(from: sourceAddress, to: destinationAddress, amountXrp: amount, privateKeyHex: priv, publicKeyHex: pub) }, buildPrivKeyJSON: { priv in buildXrpSendPayload(from: sourceAddress, to: destinationAddress, amountXrp: amount, privateKeyHex: priv, publicKeyHex: nil) }, clearPreview: { self.xrpSendPreview = nil }, seedPhrase: seedPhrase, privateKey: privateKey, sourceAddress: sourceAddress
            )
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
            await submitDualKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeXlm, symbol: "XLM", feeDecimals: 7, isSendingPath: \.isSendingStellar, chainId: SpectraChainID.stellar, chain: .stellar, derivationPath: wallet.seedDerivationPaths.stellar, sendChain: .stellar, buildSeedJSON: { priv, pub in buildStellarSendPayload(from: sourceAddress, to: destinationAddress, amountXlm: amount, privateKeyHex: priv, publicKeyHex: pub) }, buildPrivKeyJSON: { priv in buildStellarSendPayload(from: sourceAddress, to: destinationAddress, amountXlm: amount, privateKeyHex: priv, publicKeyHex: nil) }, clearPreview: { self.stellarSendPreview = nil }, seedPhrase: seedPhrase, privateKey: privateKey, sourceAddress: sourceAddress
            )
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
            let totalCost = amount + preview.estimatedNetworkFeeXmr
            if totalCost > holding.amount {
                sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: "XMR", totalNeeded: totalCost, decimals: 6)
                return
            }
            isSendingMonero = true
            defer { isSendingMonero = false }
            do {
                let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                    chainId: SpectraChainID.monero, paramsJson: buildMoneroSendPayload(to: destinationAddress, amountXmr: amount, priority: 2)
                )
                let moneroOutcome = classifySendBroadcastResult(chain: .monero, resultJson: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: moneroOutcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: moneroOutcome.payloadFormat
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
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeAda, symbol: "ADA", isSendingPath: \.isSendingCardano, chainId: SpectraChainID.cardano, chain: .cardano, derivationPath: walletDerivationPath(for: wallet, chain: .cardano), sendChain: .cardano, buildJSON: { priv, pub in buildCardanoSendPayload(from: sourceAddress, to: destinationAddress, amountAda: amount, feeAda: preview.estimatedNetworkFeeAda, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.cardanoSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if holding.chainName == "NEAR", holding.symbol == "NEAR" {
            guard !isSendingNear else { return }
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { sendError = "This wallet's seed phrase is unavailable."; return }
            guard let sourceAddress = resolvedNearAddress(for: wallet) else { sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."; return }
            if nearSendPreview == nil { await refreshNearSendPreview() }
            guard let preview = nearSendPreview else { sendError = sendError ?? "Unable to estimate NEAR network fee."; return }
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeNear, symbol: "NEAR", isSendingPath: \.isSendingNear, chainId: SpectraChainID.near, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near), sendChain: .near, buildJSON: { priv, pub in buildNearSendPayload(from: sourceAddress, to: destinationAddress, amountNear: amount, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.nearSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
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
                let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                    chainId: SpectraChainID.near, seedPhrase: seedPhrase, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near)
                ) { privKeyHex, pubKeyHex in
                    let pub = pubKeyHex ?? ""
                    return buildNearTokenSendPayload(from: sourceAddress, contract: contractAddress, to: destinationAddress, amount: amount, decimals: UInt32(decimals), privateKeyHex: privKeyHex, publicKeyHex: pub)
                }
                let nearTokenOutcome = classifySendBroadcastResult(chain: .near, resultJson: resultJSON)
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: nearTokenOutcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: nearTokenOutcome.payloadFormat
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
            await submitSeedPubKeyChainSend(
                holding: holding, wallet: wallet, destinationAddress: destinationAddress, amount: amount, networkFee: preview.estimatedNetworkFeeDot, symbol: "DOT", isSendingPath: \.isSendingPolkadot, chainId: SpectraChainID.polkadot, chain: .polkadot, derivationPath: wallet.seedDerivationPaths.polkadot, sendChain: .polkadot, buildJSON: { priv, pub in buildPolkadotSendPayload(from: sourceAddress, to: destinationAddress, amountDot: amount, privateKeyHex: priv, publicKeyHex: pub) }, clearPreview: { self.polkadotSendPreview = nil }, seedPhrase: seedPhrase, sourceAddress: sourceAddress
            )
            return
        }
        if isEVMChain(holding.chainName) {
            guard let chain = evmChainContext(for: holding.chainName) else {
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
            if preflight.isNativeEvmAsset {
                let totalCost = amount + preview.estimatedNetworkFeeEth
                if totalCost > nativeBalance {
                    sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: nativeSymbol, totalNeeded: totalCost, decimals: 6)
                    return
                }
            } else if preview.estimatedNetworkFeeEth > nativeBalance {
                sendError = coreInsufficientNativeForFeeMessage(nativeSymbol: nativeSymbol, fee: preview.estimatedNetworkFeeEth, decimals: 6, chainLabel: nil)
                return
            }
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
                let result: EthereumSendResult
                let spectraEvmChainId = SpectraChainID.id(for: holding.chainName)
                let overridesFragment = evmOverridesJSONFragment(nonce: explicitNonce, customFees: customFees)
                let rustSupportsChain = spectraEvmChainId != nil
                if preflight.isNativeEvmAsset && rustSupportsChain, let chainId = spectraEvmChainId {
                    let valueWei = ethToWeiString(amount)
                    guard let sourceAddress = resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                            chainId: chainId, seedPhrase: seedPhrase, chain: evmDerivationChain, derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            buildEvmNativeSendPayload(fromAddress: sourceAddress, toAddress: destinationAddress, valueWei: valueWei, privateKeyHex: privKeyHex, overridesFragment: overridesFragment)
                        }
                    } else if let privateKey {
                        let payload = buildEvmNativeSendPayload(fromAddress: sourceAddress, toAddress: destinationAddress, valueWei: valueWei, privateKeyHex: privateKey, overridesFragment: overridesFragment)
                        resultJSON = try await WalletServiceBridge.shared.signAndSend(chainId: chainId, paramsJson: payload)
                    } else {
                        sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = decodeEvmSendResult(
                        resultJSON, fallbackNonce: explicitNonce.map(Int64.init) ?? ethereumSendPreview?.nonce ?? 0
                    )
                } else if let token = supportedEVMToken(for: holding), rustSupportsChain, let chainId = spectraEvmChainId {
                    guard let sourceAddress = resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let amountRaw = tokenAmountToRawString(amount, decimals: token.decimals)
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                            chainId: chainId, seedPhrase: seedPhrase, chain: evmDerivationChain, derivationPath: walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            buildEvmTokenSendPayload(fromAddress: sourceAddress, contractAddress: token.contractAddress, toAddress: destinationAddress, amountRaw: amountRaw, privateKeyHex: privKeyHex, overridesFragment: overridesFragment)
                        }
                    } else if let privateKey {
                        let payload = buildEvmTokenSendPayload(fromAddress: sourceAddress, contractAddress: token.contractAddress, toAddress: destinationAddress, amountRaw: amountRaw, privateKeyHex: privateKey, overridesFragment: overridesFragment)
                        resultJSON = try await WalletServiceBridge.shared.signAndSendToken(chainId: chainId, paramsJson: payload)
                    } else {
                        sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = decodeEvmSendResult(
                        resultJSON, fallbackNonce: explicitNonce.map(Int64.init) ?? ethereumSendPreview?.nonce ?? 0
                    )
                } else {
                    sendError = "\(holding.symbol) transfers on \(holding.chainName) are not enabled yet."
                    return
                }
                let transaction = decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: result.transactionHash, ethereumNonce: Int(result.preview.nonce), signedTransactionPayload: result.rawTransactionHex, signedTransactionPayloadFormat: "evm.raw_hex"
                ), holding: holding)
                recordPendingSentTransaction(transaction)
                await runPostSendRefreshActions(for: holding.chainName, verificationStatus: result.verificationStatus)
                resetSendComposerState()
            } catch {
                sendError = mapEthereumSendError(error)
                noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
            }
            return
        }
        sendError = "\(holding.chainName) native sending is not enabled yet."
    }

    @MainActor private func submitSeedPubKeyChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, networkFee: Double, symbol: String, isSendingPath: ReferenceWritableKeyPath<AppState, Bool>, chainId: UInt32, chain: SeedDerivationChain, derivationPath: String, sendChain: SendChain, checkSelfSend: Bool = false, buildJSON: @escaping (String, String) -> String, clearPreview: @escaping () -> Void, seedPhrase: String, sourceAddress: String
    ) async {
        let totalCost = amount + networkFee
        if totalCost > holding.amount {
            sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: symbol, totalNeeded: totalCost, decimals: 6)
            return
        }
        if checkSelfSend && requiresSelfSendConfirmation(wallet: wallet, holding: holding, destinationAddress: destinationAddress, amount: amount) { return }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) { priv, pub in buildJSON(priv, pub) }
            let outcome = classifySendBroadcastResult(chain: sendChain, resultJson: resultJSON)
            let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: outcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: outcome.payloadFormat
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}

    @MainActor private func submitDualKeyChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, networkFee: Double, symbol: String, feeDecimals: UInt32, isSendingPath: ReferenceWritableKeyPath<AppState, Bool>, chainId: UInt32, chain: SeedDerivationChain, derivationPath: String, sendChain: SendChain, buildSeedJSON: @escaping (String, String) -> String, buildPrivKeyJSON: @escaping (String) -> String, clearPreview: @escaping () -> Void, seedPhrase: String?, privateKey: String?, sourceAddress: String
    ) async {
        let totalCost = amount + networkFee
        if totalCost > holding.amount {
            sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: symbol, totalNeeded: totalCost, decimals: feeDecimals)
            return
        }
        self[keyPath: isSendingPath] = true
        defer { self[keyPath: isSendingPath] = false }
        do {
            let signedPayload: String
            if let seedPhrase {
                signedPayload = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) { priv, pub in buildSeedJSON(priv, pub) }
            } else if let privateKey {
                let norm = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                signedPayload = try await WalletServiceBridge.shared.signAndSend(chainId: chainId, paramsJson: buildPrivKeyJSON(norm))
            } else {
                sendError = "This wallet's signing key is unavailable."
                return
            }
            let outcome = classifySendBroadcastResult(chain: sendChain, resultJson: signedPayload)
            let transaction = decoratePendingSendTransaction(TransactionRecord(
                walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: outcome.transactionHash, signedTransactionPayload: signedPayload, signedTransactionPayloadFormat: outcome.payloadFormat
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}

    @MainActor private func submitUTXOSatChainSend(
        holding: Coin, wallet: ImportedWallet, destinationAddress: String, amount: Double, chainId: UInt32, chain: SeedDerivationChain, isSendingPath: ReferenceWritableKeyPath<AppState, Bool>, symbol: String, feeFallback: Double, sendChain: SendChain, resolveAddress: @escaping (ImportedWallet) -> String?, getPreview: @escaping () -> BitcoinSendPreview?, refreshPreview: @escaping () async -> Void, clearPreview: @escaping () -> Void
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
                let totalCost = amount + preview.estimatedNetworkFeeBtc
                if totalCost > holding.amount {
                    sendError = coreInsufficientFundsForAmountPlusFeeMessage(symbol: symbol, totalNeeded: totalCost, decimals: 8)
                    return
                }}
            let amountSat = UInt64(amount * 1e8)
            let feeSat = UInt64((getPreview()?.estimatedNetworkFeeBtc ?? feeFallback) * 1e8)
            let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: chain, derivationPath: walletDerivationPath(for: wallet, chain: chain)
            ) { privKeyHex, _ in
                buildUtxoSatSendPayload(fromAddress: sourceAddress, toAddress: destinationAddress, amountSat: amountSat, feeSat: feeSat, privateKeyHex: privKeyHex)
            }
            let outcome = classifySendBroadcastResult(chain: sendChain, resultJson: resultJSON)
            let transaction = decoratePendingSendTransaction(TransactionRecord( walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: holding.name, symbol: holding.symbol, chainName: holding.chainName, amount: amount, address: destinationAddress, transactionHash: outcome.transactionHash, signedTransactionPayload: resultJSON, signedTransactionPayloadFormat: outcome.payloadFormat
            ), holding: holding)
            recordPendingSentTransaction(transaction)
            await runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
            resetSendComposerState { clearPreview() }
        } catch {
            sendError = error.localizedDescription
            noteSendBroadcastFailure(for: holding.chainName, message: sendError ?? error.localizedDescription)
        }}
}
