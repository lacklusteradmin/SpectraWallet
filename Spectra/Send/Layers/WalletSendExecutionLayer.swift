import Foundation

extension WalletSendLayer {
    static func submitSend(using store: WalletStore) async {
        guard let walletIndex = store.wallets.firstIndex(where: { $0.id.uuidString == store.sendWalletID }) else {
            store.sendError = "Select a wallet"
            return
        }
        guard let holdingIndex = store.wallets[walletIndex].holdings.firstIndex(where: { $0.holdingKey == store.sendHoldingKey }) else {
            store.sendError = "Select an asset"
            return
        }
        guard !store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.sendError = "Enter a destination address"
            return
        }
        guard let amount = Double(store.sendAmount) else {
            store.sendError = "Enter a valid amount"
            return
        }
        
        let wallet = store.wallets[walletIndex]
        let holding = wallet.holdings[holdingIndex]
        let destinationInput = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        var destinationAddress = destinationInput
        var usedENSResolution = false
        if amount < 0 {
            store.sendError = "Enter a valid amount"
            return
        }
        if amount > holding.amount {
            store.sendError = "Amount exceeds the available balance"
            return
        }

        if holding.chainName == "Sui", holding.symbol == "SUI" {
            guard !store.isSendingSui else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedSuiAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Sui signing address from the seed phrase."
                return
            }
            if store.suiSendPreview == nil {
                await store.refreshSuiSendPreview()
            }
            guard let preview = store.suiSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Sui network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeSUI
            if totalCost > holding.amount {
                store.sendError = "Insufficient SUI for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) SUI)."
                return
            }
            if store.requiresSelfSendConfirmation(
                wallet: wallet,
                holding: holding,
                destinationAddress: destinationAddress,
                amount: amount
            ) {
                return
            }

            store.isSendingSui = true
            defer { store.isSendingSui = false }

            do {
                let sendResult = try await SuiWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationAccount: store.derivationAccount(for: wallet, chain: .sui),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionPayloadJSON,
                    signedTransactionPayloadFormat: "sui.signed_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.suiSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingSuiSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Aptos", holding.symbol == "APT" {
            guard !store.isSendingAptos else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedAptosAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Aptos signing address from the seed phrase."
                return
            }
            if store.aptosSendPreview == nil {
                await store.refreshAptosSendPreview()
            }
            guard let preview = store.aptosSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Aptos network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeAPT
            if totalCost > holding.amount {
                store.sendError = "Insufficient APT for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) APT)."
                return
            }
            if store.requiresSelfSendConfirmation(
                wallet: wallet,
                holding: holding,
                destinationAddress: destinationAddress,
                amount: amount
            ) {
                return
            }

            store.isSendingAptos = true
            defer { store.isSendingAptos = false }

            do {
                let sendResult = try await AptosWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationAccount: store.derivationAccount(for: wallet, chain: .aptos),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionJSON,
                    signedTransactionPayloadFormat: "aptos.signed_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.aptosSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingAptosSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "TON", holding.symbol == "TON" {
            guard !store.isSendingTON else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedTONAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's TON signing address from the seed phrase."
                return
            }
            if store.tonSendPreview == nil {
                await store.refreshTONSendPreview()
            }
            guard let preview = store.tonSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate TON network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeTON
            if totalCost > holding.amount {
                store.sendError = "Insufficient TON for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) TON)."
                return
            }
            if store.requiresSelfSendConfirmation(
                wallet: wallet,
                holding: holding,
                destinationAddress: destinationAddress,
                amount: amount
            ) {
                return
            }

            store.isSendingTON = true
            defer { store.isSendingTON = false }

            do {
                let sendResult = try await TONWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationAccount: store.derivationAccount(for: wallet, chain: .ton)
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedBOC,
                    signedTransactionPayloadFormat: "ton.boc"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.tonSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingTONSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Internet Computer", holding.symbol == "ICP" {
            guard !store.isSendingICP else { return }
            if store.icpSendPreview == nil {
                await store.refreshICPSendPreview()
            }
            guard let walletIndex = store.wallets.firstIndex(where: { $0.id == wallet.id }),
                  let sourceAddress = store.resolvedICPAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's ICP address."
                return
            }

            let privateKey = store.storedPrivateKey(for: wallet.id)
            let seedPhrase = store.storedSeedPhrase(for: wallet.id)
            guard privateKey != nil || seedPhrase != nil else {
                store.sendError = "This wallet's signing secret is unavailable."
                return
            }
            if store.requiresSelfSendConfirmation(
                wallet: wallet,
                holding: holding,
                destinationAddress: destinationAddress,
                amount: amount
            ) {
                return
            }

            store.isSendingICP = true
            defer { store.isSendingICP = false }

            do {
                let sendResult: ICPSendResult
                if let privateKey {
                    sendResult = try await ICPWalletEngine.sendInBackground(
                        privateKeyHex: privateKey,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount
                    )
                } else if let seedPhrase {
                    sendResult = try await ICPWalletEngine.sendInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                        derivationPath: wallet.seedDerivationPaths.internetComputer
                    )
                } else {
                    throw ICPWalletEngineError.invalidSeedPhrase
                }

                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionHex,
                    signedTransactionPayloadFormat: "icp.signed_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.icpSendPreview = nil
                    store.wallets[walletIndex] = store.wallets[walletIndex]
                }
            } catch {
                store.sendError = store.userFacingICPSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if store.isEVMChain(holding.chainName) {
            do {
                let resolvedDestination = try await store.resolveEVMRecipientAddress(input: destinationInput, for: holding.chainName)
                destinationAddress = resolvedDestination.address
                usedENSResolution = resolvedDestination.usedENS
                if usedENSResolution {
                    store.sendDestinationInfoMessage = "Resolved ENS \(destinationInput) to \(destinationAddress)."
                }
            } catch {
                store.sendError = (error as? LocalizedError)?.errorDescription ?? "Enter a valid \(holding.chainName) destination."
                return
            }
        }

        if !store.bypassHighRiskSendConfirmation {
            var highRiskReasons = store.evaluateHighRiskSendReasons(
                wallet: wallet,
                holding: holding,
                amount: amount,
                destinationAddress: destinationAddress,
                destinationInput: destinationInput,
                usedENSResolution: usedENSResolution
            )
            if let chain = store.evmChainContext(for: holding.chainName) {
                let preflightReasons = await store.evmRecipientPreflightReasons(
                    holding: holding,
                    chain: chain,
                    destinationAddress: destinationAddress
                )
                highRiskReasons.append(contentsOf: preflightReasons)
            }
            if !highRiskReasons.isEmpty {
                store.pendingHighRiskSendReasons = highRiskReasons
                store.isShowingHighRiskSendConfirmation = true
                store.sendError = nil
                return
            }
        } else {
            store.bypassHighRiskSendConfirmation = false
        }

        if store.requiresSelfSendConfirmation(
            wallet: wallet,
            holding: holding,
            destinationAddress: destinationAddress,
            amount: amount
        ) {
            return
        }

        guard await store.authenticateForSensitiveAction(reason: "Authorize transaction send") else {
            return
        }
        if holding.symbol == "BTC" {
            guard amount > 0 else {
                store.sendError = "Enter a valid amount"
                return
            }
            guard !store.isSendingBitcoin else { return }
            store.isSendingBitcoin = true
            defer { store.isSendingBitcoin = false }
            do {
                guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                    store.sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                let sendResult = try await BitcoinWalletEngine.sendInBackground(
                    from: wallet,
                    seedPhrase: seedPhrase,
                    to: destinationAddress,
                    amountBTC: amount,
                    feePriority: store.bitcoinFeePriority(for: holding.chainName),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.rawTransactionHex,
                    signedTransactionPayloadFormat: "bitcoin.raw_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState()
            } catch {
                store.sendError = error.localizedDescription
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "BCH", holding.chainName == "Bitcoin Cash" {
            guard amount > 0 else {
                store.sendError = "Enter a valid amount"
                return
            }
            guard !store.isSendingBitcoinCash else { return }
            store.isSendingBitcoinCash = true
            defer { store.isSendingBitcoinCash = false }
            do {
                guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                    store.sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = store.resolvedBitcoinCashAddress(for: wallet) else {
                    store.sendError = "Unable to resolve this wallet's Bitcoin Cash address from the seed phrase."
                    return
                }
                if store.bitcoinCashSendPreview == nil {
                    await store.refreshBitcoinCashSendPreview()
                }
                if let bitcoinCashSendPreview = store.bitcoinCashSendPreview {
                    let totalCost = amount + bitcoinCashSendPreview.estimatedNetworkFeeBTC
                    if totalCost > holding.amount {
                        store.sendError = "Insufficient BCH for amount plus network fee (needs ~\(String(format: "%.8f", totalCost)) BCH)."
                        return
                    }
                }
                let sendResult = try await BitcoinCashWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    sourceAddress: sourceAddress,
                    to: destinationAddress,
                    amountBCH: amount,
                    options: BitcoinCashWalletEngine.SendOptions(
                        maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil,
                        enableRBF: store.sendEnableRBF
                    ),
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinCash),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.rawTransactionHex,
                    signedTransactionPayloadFormat: "bitcoin_cash.raw_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.bitcoinCashSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "BSV", holding.chainName == "Bitcoin SV" {
            guard amount > 0 else {
                store.sendError = "Enter a valid amount"
                return
            }
            guard !store.isSendingBitcoinSV else { return }
            store.isSendingBitcoinSV = true
            defer { store.isSendingBitcoinSV = false }
            do {
                guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                    store.sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = store.resolvedBitcoinSVAddress(for: wallet) else {
                    store.sendError = "Unable to resolve this wallet's Bitcoin SV address from the seed phrase."
                    return
                }
                if store.bitcoinSVSendPreview == nil {
                    await store.refreshBitcoinSVSendPreview()
                }
                if let bitcoinSVSendPreview = store.bitcoinSVSendPreview {
                    let totalCost = amount + bitcoinSVSendPreview.estimatedNetworkFeeBTC
                    if totalCost > holding.amount {
                        store.sendError = "Insufficient BSV for amount plus network fee (needs ~\(String(format: "%.8f", totalCost)) BSV)."
                        return
                    }
                }
                let sendResult = try await BitcoinSVWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    sourceAddress: sourceAddress,
                    to: destinationAddress,
                    amountBSV: amount,
                    options: BitcoinSVWalletEngine.SendOptions(
                        maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil,
                        enableRBF: store.sendEnableRBF
                    ),
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinSV),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.rawTransactionHex,
                    signedTransactionPayloadFormat: "bitcoin_sv.raw_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.bitcoinSVSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "LTC", holding.chainName == "Litecoin" {
            guard amount > 0 else {
                store.sendError = "Enter a valid amount"
                return
            }
            guard !store.isSendingLitecoin else { return }
            store.isSendingLitecoin = true
            defer { store.isSendingLitecoin = false }
            do {
                guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                    store.sendError = "This wallet's seed phrase is unavailable."
                    return
                }
                guard let sourceAddress = store.resolvedLitecoinAddress(for: wallet) else {
                    store.sendError = "Unable to resolve this wallet's Litecoin address from the seed phrase."
                    return
                }
                if store.litecoinSendPreview == nil {
                    await store.refreshLitecoinSendPreview()
                }
                if let litecoinSendPreview = store.litecoinSendPreview {
                    let totalCost = amount + litecoinSendPreview.estimatedNetworkFeeBTC
                    if totalCost > holding.amount {
                        store.sendError = "Insufficient LTC for amount plus network fee (needs ~\(String(format: "%.8f", totalCost)) LTC)."
                        return
                    }
                }
                let sendResult = try await LitecoinWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    sourceAddress: sourceAddress,
                    to: destinationAddress,
                    amountLTC: amount,
                    feePriority: store.bitcoinFeePriority(for: holding.chainName),
                    options: LitecoinWalletEngine.SendOptions(
                        maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil,
                        changeStrategy: store.sendLitecoinChangeStrategy,
                        enableRBF: store.sendEnableRBF
                    ),
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .litecoin),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.rawTransactionHex,
                    signedTransactionPayloadFormat: "litecoin.raw_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.litecoinSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }
        if holding.symbol == "DOGE", holding.chainName == "Dogecoin" {
            guard !store.isSendingDogecoin else { return }
            guard let dogecoinAmount = store.parseDogecoinAmountInput(store.sendAmount) else {
                store.sendError = "Enter a valid DOGE amount with up to 8 decimal places."
                return
            }
            guard store.isValidDogecoinAddressForPolicy(destinationAddress, networkMode: store.dogecoinNetworkMode(for: wallet)) else {
                store.sendError = CommonLocalization.invalidDestinationAddressPrompt("Dogecoin")
                return
            }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }

            guard store.resolvedDogecoinAddress(for: wallet) != nil else {
                store.sendError = "Unable to resolve this wallet's Dogecoin signing address from the seed phrase."
                return
            }
            store.appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send initiated.")

            if store.dogecoinSendPreview == nil {
                await store.refreshDogecoinSendPreview()
            }
            if let dogecoinSendPreview = store.dogecoinSendPreview, dogecoinAmount > dogecoinSendPreview.maxSendableDOGE {
                store.sendError = "Insufficient DOGE for amount plus network fee (max sendable ~\(String(format: "%.6f", dogecoinSendPreview.maxSendableDOGE)) DOGE)."
                return
            }

            store.isSendingDogecoin = true
            defer { store.isSendingDogecoin = false }

            let sendResult: DogecoinWalletEngine.DogecoinSendResult
            do {
                sendResult = try await DogecoinWalletEngine.sendInBackground(
                    from: store.walletWithResolvedDogecoinAddress(wallet),
                    seedPhrase: seedPhrase,
                    to: destinationAddress,
                    amountDOGE: dogecoinAmount,
                    feePriority: store.dogecoinFeePriority,
                    changeIndex: store.reserveDogecoinChangeIndex(for: wallet),
                    maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil
                )
            } catch {
                store.sendError = error.localizedDescription
                store.appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE send failed: \(error.localizedDescription)")
                return
            }

            let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                walletID: wallet.id,
                kind: .send,
                status: .pending,
                walletName: wallet.name,
                assetName: holding.name,
                symbol: holding.symbol,
                chainName: holding.chainName,
                amount: dogecoinAmount,
                address: destinationAddress,
                transactionHash: sendResult.transactionHash,
                dogecoinConfirmations: 0,
                dogecoinFeePriorityRaw: store.dogecoinFeePriority.rawValue,
                dogecoinEstimatedFeeRateDOGEPerKB: store.dogecoinSendPreview?.estimatedFeeRateDOGEPerKB,
                dogecoinUsedChangeOutput: store.dogecoinSendPreview?.usesChangeOutput,
                sourceDerivationPath: sendResult.derivationMetadata.sourceDerivationPath,
                changeDerivationPath: sendResult.derivationMetadata.changeDerivationPath,
                sourceAddress: sendResult.derivationMetadata.sourceAddress,
                changeAddress: sendResult.derivationMetadata.changeAddress,
                dogecoinRawTransactionHex: sendResult.rawTransactionHex,
                signedTransactionPayload: sendResult.rawTransactionHex,
                signedTransactionPayloadFormat: "dogecoin.raw_hex"
            ), holding: holding)
            store.registerDogecoinOwnedAddress(
                address: sendResult.derivationMetadata.sourceAddress,
                walletID: wallet.id,
                derivationPath: sendResult.derivationMetadata.sourceDerivationPath,
                index: store.parseDogecoinDerivationIndex(
                    path: sendResult.derivationMetadata.sourceDerivationPath,
                    expectedPrefix: WalletDerivationPath.dogecoinExternalPrefix(account: 0)
                ),
                branch: "external",
                networkMode: wallet.dogecoinNetworkMode
            )
            store.registerDogecoinOwnedAddress(
                address: sendResult.derivationMetadata.changeAddress,
                walletID: wallet.id,
                derivationPath: sendResult.derivationMetadata.changeDerivationPath,
                index: store.parseDogecoinDerivationIndex(
                    path: sendResult.derivationMetadata.changeDerivationPath,
                    expectedPrefix: WalletDerivationPath.dogecoinChangePrefix(account: 0)
                ),
                branch: "change",
                networkMode: wallet.dogecoinNetworkMode
            )
            store.recordPendingSentTransaction(transaction)
            switch sendResult.verificationStatus {
            case .verified:
                store.clearSendVerificationNotice()
                store.appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send broadcast verified.", transactionHash: sendResult.transactionHash)
            case .deferred:
                store.setDeferredSendVerificationNotice(for: holding.chainName)
                store.appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE send broadcast accepted; verification deferred.", transactionHash: sendResult.transactionHash)
            case .failed(let message):
                store.setFailedSendVerificationNotice("Broadcast succeeded, but post-broadcast verification reported: \(message)")
                store.appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE send verification warning: \(message)", transactionHash: sendResult.transactionHash)
            }
            await store.refreshDogecoinTransactions()
            await store.refreshPendingDogecoinTransactions()
            store.updateSendVerificationNoticeForLastSentTransaction()
            store.resetSendComposerState {
                store.dogecoinSendPreview = nil
            }
            return
        }

        if holding.chainName == "Tron", holding.symbol == "TRX" || holding.symbol == "USDT" {
            guard !store.isSendingTron else { return }
            let seedPhrase = store.storedSeedPhrase(for: wallet.id)
            let privateKey = store.storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                store.sendError = "This wallet's signing key is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedTronAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Tron signing address."
                return
            }

            if store.tronSendPreview == nil {
                await store.refreshTronSendPreview()
            }
            guard let preview = store.tronSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Tron network fee."
                return
            }

            if holding.symbol == "TRX" {
                let totalCost = amount + preview.estimatedNetworkFeeTRX
                if totalCost > holding.amount {
                    store.sendError = "Insufficient TRX for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) TRX)."
                    return
                }
            } else {
                let trxBalance = wallet.holdings.first(where: { $0.chainName == "Tron" && $0.symbol == "TRX" })?.amount ?? 0
                if preview.estimatedNetworkFeeTRX > trxBalance {
                    store.sendError = "Insufficient TRX to cover Tron network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeTRX)) TRX)."
                    return
                }
            }

            store.isSendingTron = true
            defer { store.isSendingTron = false }

            do {
                let sendResult: TronSendResult
                if let seedPhrase {
                    sendResult = try await TronWalletEngine.sendInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        symbol: holding.symbol,
                        amount: amount,
                        contractAddress: holding.contractAddress,
                        derivationAccount: store.derivationAccount(for: wallet, chain: .tron),
                    )
                } else if let privateKey {
                    sendResult = try await TronWalletEngine.sendInBackground(
                        privateKeyHex: privateKey,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        symbol: holding.symbol,
                        amount: amount,
                        contractAddress: holding.contractAddress,
                    )
                } else {
                    store.sendError = "This wallet's signing key is unavailable."
                    return
                }
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionJSON,
                    signedTransactionPayloadFormat: "tron.signed_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.tronSendPreview = nil
                    store.tronLastSendErrorDetails = nil
                    store.tronLastSendErrorAt = nil
                }
            } catch {
                let message = store.userFacingTronSendError(error, symbol: holding.symbol)
                store.sendError = message
                store.recordTronSendDiagnosticError(message)
                store.noteSendBroadcastFailure(for: holding.chainName, message: message)
            }
            return
        }

        if store.isSupportedSolanaSendCoin(holding) {
            guard !store.isSendingSolana else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedSolanaAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Solana signing address from the seed phrase."
                return
            }
            if store.solanaSendPreview == nil {
                await store.refreshSolanaSendPreview()
            }
            guard let preview = store.solanaSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Solana network fee."
                return
            }
            if holding.symbol == "SOL" {
                let totalCost = amount + preview.estimatedNetworkFeeSOL
                if totalCost > holding.amount {
                    store.sendError = "Insufficient SOL for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) SOL)."
                    return
                }
            } else {
                if amount > holding.amount {
                    store.sendError = "Insufficient \(holding.symbol) balance for this transfer."
                    return
                }
                let solBalance = wallet.holdings.first(where: { $0.chainName == "Solana" && $0.symbol == "SOL" })?.amount ?? 0
                if preview.estimatedNetworkFeeSOL > solBalance {
                    store.sendError = "Insufficient SOL to cover Solana network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeSOL)) SOL)."
                    return
                }
            }

            store.isSendingSolana = true
            defer { store.isSendingSolana = false }

            do {
                let sendResult: SolanaSendResult
                let solanaPreference = store.solanaDerivationPreference(for: wallet)
                if holding.symbol == "SOL" {
                    sendResult = try await SolanaWalletEngine.sendInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                        preference: solanaPreference,
                        account: store.derivationAccount(for: wallet, chain: .solana),
                    )
                } else {
                    let solanaTokenMetadataByMint = store.solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol),
                          let tokenMetadata = solanaTokenMetadataByMint[mintAddress] else {
                        store.sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    let sourceTokenAccount = try await SolanaBalanceService.resolveOwnedTokenAccount(
                        for: sourceAddress,
                        mintAddress: mintAddress
                    )
                    sendResult = try await SolanaWalletEngine.sendTokenInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        mintAddress: mintAddress,
                        decimals: tokenMetadata.decimals,
                        amount: amount,
                        sourceTokenAccountAddress: sourceTokenAccount,
                        preference: solanaPreference,
                        account: store.derivationAccount(for: wallet, chain: .solana),
                    )
                }
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionBase64,
                    signedTransactionPayloadFormat: "solana.base64"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.solanaSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "XRP Ledger", holding.symbol == "XRP" {
            guard !store.isSendingXRP else { return }
            let seedPhrase = store.storedSeedPhrase(for: wallet.id)
            let privateKey = store.storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                store.sendError = "This wallet's signing key is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedXRPAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's XRP signing address."
                return
            }
            if store.xrpSendPreview == nil {
                await store.refreshXRPSendPreview()
            }
            guard let preview = store.xrpSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate XRP network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeXRP
            if totalCost > holding.amount {
                store.sendError = "Insufficient XRP for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) XRP)."
                return
            }

            store.isSendingXRP = true
            defer { store.isSendingXRP = false }

            do {
                let sendResult: XRPSendResult
                if let seedPhrase {
                    sendResult = try await XRPWalletEngine.sendInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                        derivationAccount: store.derivationAccount(for: wallet, chain: .xrp),
                    )
                } else if let privateKey {
                    sendResult = try await XRPWalletEngine.sendInBackground(
                        privateKeyHex: privateKey,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                    )
                } else {
                    store.sendError = "This wallet's signing key is unavailable."
                    return
                }
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionBlobHex,
                    signedTransactionPayloadFormat: "xrp.blob_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.xrpSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingXRPSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Stellar", holding.symbol == "XLM" {
            guard !store.isSendingStellar else { return }
            let seedPhrase = store.storedSeedPhrase(for: wallet.id)
            let privateKey = store.storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                store.sendError = "This wallet's signing key is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedStellarAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Stellar signing address."
                return
            }
            if store.stellarSendPreview == nil {
                await store.refreshStellarSendPreview()
            }
            guard let preview = store.stellarSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Stellar network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeXLM
            if totalCost > holding.amount {
                store.sendError = "Insufficient XLM for amount plus network fee (needs ~\(String(format: "%.7f", totalCost)) XLM)."
                return
            }

            store.isSendingStellar = true
            defer { store.isSendingStellar = false }

            do {
                let sendResult: StellarSendResult
                if let seedPhrase {
                    sendResult = try await StellarWalletEngine.sendInBackground(
                        seedPhrase: seedPhrase,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                        derivationPath: wallet.seedDerivationPaths.stellar,
                    )
                } else if let privateKey {
                    sendResult = try await StellarWalletEngine.sendInBackground(
                        privateKeyHex: privateKey,
                        ownerAddress: sourceAddress,
                        destinationAddress: destinationAddress,
                        amount: amount,
                    )
                } else {
                    store.sendError = "This wallet's signing key is unavailable."
                    return
                }
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedEnvelopeXDR,
                    signedTransactionPayloadFormat: "stellar.xdr"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.stellarSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingStellarSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Monero", holding.symbol == "XMR" {
            guard !store.isSendingMonero else { return }
            guard let sourceAddress = store.resolvedMoneroAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Monero address."
                return
            }
            if store.moneroSendPreview == nil {
                await store.refreshMoneroSendPreview()
            }
            guard let preview = store.moneroSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Monero network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeXMR
            if totalCost > holding.amount {
                store.sendError = "Insufficient XMR for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) XMR)."
                return
            }

            store.isSendingMonero = true
            defer { store.isSendingMonero = false }

            do {
                let sendResult = try await MoneroWalletEngine.sendInBackground(
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: nil,
                    signedTransactionPayloadFormat: nil
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.moneroSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingMoneroSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Cardano", holding.symbol == "ADA" {
            guard !store.isSendingCardano else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedCardanoAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Cardano signing address from the seed phrase."
                return
            }
            if store.cardanoSendPreview == nil {
                await store.refreshCardanoSendPreview()
            }
            guard let preview = store.cardanoSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Cardano network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeADA
            if totalCost > holding.amount {
                store.sendError = "Insufficient ADA for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) ADA)."
                return
            }

            store.isSendingCardano = true
            defer { store.isSendingCardano = false }

            do {
                let sendResult = try await CardanoWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .cardano),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionCBORHex,
                    signedTransactionPayloadFormat: "cardano.cbor_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.cardanoSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingCardanoSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "NEAR", holding.symbol == "NEAR" {
            guard !store.isSendingNear else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedNearAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's NEAR signing address from the seed phrase."
                return
            }
            if store.nearSendPreview == nil {
                await store.refreshNearSendPreview()
            }
            guard let preview = store.nearSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate NEAR network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeNEAR
            if totalCost > holding.amount {
                store.sendError = "Insufficient NEAR for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) NEAR)."
                return
            }

            store.isSendingNear = true
            defer { store.isSendingNear = false }

            do {
                let sendResult = try await NearWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationAccount: store.derivationAccount(for: wallet, chain: .near),
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedTransactionBase64,
                    signedTransactionPayloadFormat: "near.base64"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.nearSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingNearSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if holding.chainName == "Polkadot", holding.symbol == "DOT" {
            guard !store.isSendingPolkadot else { return }
            guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
                store.sendError = "This wallet's seed phrase is unavailable."
                return
            }
            guard let sourceAddress = store.resolvedPolkadotAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Polkadot signing address from the seed phrase."
                return
            }
            if store.polkadotSendPreview == nil {
                await store.refreshPolkadotSendPreview()
            }
            guard let preview = store.polkadotSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate Polkadot network fee."
                return
            }
            let totalCost = amount + preview.estimatedNetworkFeeDOT
            if totalCost > holding.amount {
                store.sendError = "Insufficient DOT for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) DOT)."
                return
            }

            store.isSendingPolkadot = true
            defer { store.isSendingPolkadot = false }

            do {
                let sendResult = try await PolkadotWalletEngine.sendInBackground(
                    seedPhrase: seedPhrase,
                    ownerAddress: sourceAddress,
                    destinationAddress: destinationAddress,
                    amount: amount,
                    derivationPath: wallet.seedDerivationPaths.polkadot
                )
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: sendResult.transactionHash,
                    signedTransactionPayload: sendResult.signedExtrinsicHex,
                    signedTransactionPayloadFormat: "polkadot.extrinsic_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: sendResult.verificationStatus)
                store.resetSendComposerState {
                    store.polkadotSendPreview = nil
                }
            } catch {
                store.sendError = store.userFacingPolkadotSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }

        if store.isEVMChain(holding.chainName) {
            guard let chain = store.evmChainContext(for: holding.chainName) else {
                store.sendError = "\(holding.chainName) native sending is not enabled yet."
                return
            }
            guard !store.isSendingEthereum else { return }
            guard !store.activeEthereumSendWalletIDs.contains(wallet.id) else {
                store.sendError = "An \(holding.chainName) send is already in progress for this wallet."
                return
            }
            if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
                store.sendError = store.customEthereumNonceValidationError
                return
            }
            if holding.symbol != "ETH" && holding.symbol != "BNB", amount <= 0 {
                store.sendError = "Enter a valid amount"
                return
            }
            let seedPhrase = store.storedSeedPhrase(for: wallet.id)
            let privateKey = store.storedPrivateKey(for: wallet.id)
            guard seedPhrase != nil || privateKey != nil else {
                store.sendError = "This wallet's signing key is unavailable."
                return
            }

            let nativeSymbol: String = {
                if holding.chainName == "BNB Chain" { return "BNB" }
                if holding.chainName == "Ethereum Classic" { return "ETC" }
                if holding.chainName == "Avalanche" { return "AVAX" }
                if holding.chainName == "Hyperliquid" { return "HYPE" }
                return "ETH"
            }()
            let nativeBalance = wallet.holdings.first(where: { $0.chainName == holding.chainName && $0.symbol == nativeSymbol })?.amount ?? 0
            if store.ethereumSendPreview == nil {
                await refreshEthereumSendPreview(using: store)
            }
            guard let preview = store.ethereumSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate \(holding.chainName) network fee."
                return
            }

            if holding.symbol == "ETH" || holding.symbol == "ETC" || holding.symbol == "BNB" || holding.symbol == "AVAX" || holding.symbol == "HYPE" {
                let totalCost = amount + preview.estimatedNetworkFeeETH
                if totalCost > nativeBalance {
                    store.sendError = "Insufficient \(nativeSymbol) for amount plus network fee (needs ~\(String(format: "%.6f", totalCost)) \(nativeSymbol))."
                    return
                }
            } else if preview.estimatedNetworkFeeETH > nativeBalance {
                store.sendError = "Insufficient \(nativeSymbol) to cover the network fee (~\(String(format: "%.6f", preview.estimatedNetworkFeeETH)) \(nativeSymbol))."
                return
            }

            store.isSendingEthereum = true
            store.activeEthereumSendWalletIDs.insert(wallet.id)
            defer {
                store.isSendingEthereum = false
                store.activeEthereumSendWalletIDs.remove(wallet.id)
            }

            do {
                if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                    store.sendError = store.customEthereumFeeValidationError
                    return
                }
                let customFees = store.customEthereumFeeConfiguration()
                let explicitNonce = store.explicitEthereumNonce()
                let evmDerivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: holding.chainName) ?? .ethereum
                let result: EthereumSendResult
                if holding.symbol == "ETH" || holding.symbol == "ETC" {
                    if let seedPhrase {
                        result = try await EthereumWalletEngine.sendInBackground(
                            seedPhrase: seedPhrase,
                            to: destinationAddress,
                            amountETH: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain,
                            derivationAccount: store.derivationAccount(for: wallet, chain: evmDerivationChain)
                        )
                    } else if let privateKey {
                        result = try await EthereumWalletEngine.sendInBackground(
                            privateKeyHex: privateKey,
                            to: destinationAddress,
                            amountETH: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain
                        )
                    } else {
                        store.sendError = "This wallet's signing key is unavailable."
                        return
                    }
                } else if let token = store.supportedEVMToken(for: holding) {
                    if let seedPhrase {
                        result = try await EthereumWalletEngine.sendTokenInBackground(
                            seedPhrase: seedPhrase,
                            to: destinationAddress,
                            token: token,
                            amount: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain,
                            derivationAccount: store.derivationAccount(for: wallet, chain: evmDerivationChain)
                        )
                    } else if let privateKey {
                        result = try await EthereumWalletEngine.sendTokenInBackground(
                            privateKeyHex: privateKey,
                            to: destinationAddress,
                            token: token,
                            amount: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain
                        )
                    } else {
                        store.sendError = "This wallet's signing key is unavailable."
                        return
                    }
                } else if holding.symbol == "BNB" {
                    if let seedPhrase {
                        result = try await EthereumWalletEngine.sendInBackground(
                            seedPhrase: seedPhrase,
                            to: destinationAddress,
                            amountETH: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain,
                            derivationAccount: store.derivationAccount(for: wallet, chain: evmDerivationChain)
                        )
                    } else if let privateKey {
                        result = try await EthereumWalletEngine.sendInBackground(
                            privateKeyHex: privateKey,
                            to: destinationAddress,
                            amountETH: amount,
                            explicitNonce: explicitNonce,
                            customFees: customFees,
                            rpcEndpoint: store.configuredEVMRPCEndpointURL(for: holding.chainName),
                            chain: chain
                        )
                    } else {
                        store.sendError = "This wallet's signing key is unavailable."
                        return
                    }
                } else {
                    store.sendError = "\(holding.symbol) transfers on \(holding.chainName) are not enabled yet."
                    return
                }
                let transaction = store.decoratePendingSendTransaction(TransactionRecord(
                    walletID: wallet.id,
                    kind: .send,
                    status: .pending,
                    walletName: wallet.name,
                    assetName: holding.name,
                    symbol: holding.symbol,
                    chainName: holding.chainName,
                    amount: amount,
                    address: destinationAddress,
                    transactionHash: result.transactionHash,
                    ethereumNonce: result.preview.nonce,
                    signedTransactionPayload: result.rawTransactionHex,
                    signedTransactionPayloadFormat: "evm.raw_hex"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: result.verificationStatus)
                store.resetSendComposerState()
            } catch {
                store.sendError = store.mapEthereumSendError(error)
                store.noteSendBroadcastFailure(for: holding.chainName, message: store.sendError ?? error.localizedDescription)
            }
            return
        }
        store.sendError = "\(holding.chainName) native sending is not enabled yet."
    }

}
