import Foundation

extension WalletSendLayer {
    static func submitSend(using store: WalletStore) async {
        let destinationInput = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let walletIndex = store.wallets.firstIndex(where: { $0.id.uuidString == store.sendWalletID })
        let holdingIndex = walletIndex.flatMap { index in
            store.wallets[index].holdings.firstIndex(where: { $0.holdingKey == store.sendHoldingKey })
        }
        let selectedCoin = holdingIndex.flatMap { holdingIndex in
            walletIndex.map { store.wallets[$0].holdings[holdingIndex] }
        }

        let preflight: WalletRustSendSubmitPreflightPlan
        do {
            preflight = try WalletRustAppCoreBridge.planSendSubmitPreflight(
                WalletRustSendSubmitPreflightRequest(
                    walletFound: walletIndex != nil,
                    assetFound: holdingIndex != nil,
                    destinationAddress: destinationInput,
                    amountInput: store.sendAmount,
                    availableBalance: selectedCoin?.amount ?? 0,
                    asset: selectedCoin.map {
                        WalletRustSendAssetRoutingInput(
                            chainName: $0.chainName,
                            symbol: $0.symbol,
                            isEVMChain: store.isEVMChain($0.chainName),
                            supportsSolanaSendCoin: store.isSupportedSolanaSendCoin($0)
                        )
                    }
                )
            )
        } catch {
            store.sendError = error.localizedDescription
            return
        }

        guard let walletIndex, let holdingIndex else {
            store.sendError = "Select an asset"
            return
        }
        let wallet = store.wallets[walletIndex]
        let holding = wallet.holdings[holdingIndex]
        var destinationAddress = preflight.normalizedDestinationAddress
        var usedENSResolution = false
        let amount = preflight.amount

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
                let mistAmount = UInt64(amount * 1e9)
                let gasBudget = UInt64(preview.estimatedNetworkFeeSUI * 1e9)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.sui,
                    seedPhrase: seedPhrase,
                    chain: .sui,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .sui)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"mist\":\(mistAmount),\"gas_budget\":\(gasBudget),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("digest", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "sui.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                store.resetSendComposerState {
                    store.suiSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
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
                let octasAmount = UInt64(amount * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.aptos,
                    seedPhrase: seedPhrase,
                    chain: .aptos,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .aptos)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"octas\":\(octasAmount),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "aptos.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                store.resetSendComposerState {
                    store.aptosSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
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
                let nanotons = UInt64(amount * 1e9)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.ton,
                    seedPhrase: seedPhrase,
                    chain: .ton,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .ton)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"nanotons\":\(nanotons),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "ton.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                store.resetSendComposerState {
                    store.tonSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
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
                let e8sAmount = UInt64(amount * 1e8)
                let resultJSON: String
                if let seedPhrase {
                    resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.icp,
                        seedPhrase: seedPhrase,
                        chain: .internetComputer,
                        derivationPath: wallet.seedDerivationPaths.internetComputer
                    ) { privKeyHex, pubKeyHex in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                    }
                } else if let privateKey {
                    // Private-key-only path: Rust derives the secp256k1 pubkey from the privkey.
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(normalizedPriv)\"}"
                    resultJSON = try await WalletServiceBridge.shared.signAndSend(
                        chainId: SpectraChainID.icp,
                        paramsJson: paramsJson
                    )
                } else {
                    throw NSError(domain: "ICPSend", code: 1, userInfo: [NSLocalizedDescriptionKey: "This wallet seed phrase cannot derive a valid ICP signer."])
                }

                let txid = WalletSendLayer.rustField("block_index", from: resultJSON)
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
                    transactionHash: txid.isEmpty ? resultJSON : txid,
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "icp.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                guard let sourceAddress = store.resolvedBitcoinAddress(for: wallet) else {
                    store.sendError = "Unable to resolve this wallet's Bitcoin address from the seed phrase."
                    return
                }
                if store.bitcoinSendPreview == nil {
                    await store.refreshBitcoinSendPreview()
                }
                let amountSat = UInt64(amount * 1e8)
                let feeRateSvB: Double = Double(store.bitcoinSendPreview?.estimatedFeeRateSatVb ?? 10)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.bitcoin,
                    seedPhrase: seedPhrase,
                    chain: .bitcoin,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoin)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_rate_svb\":\(feeRateSvB),\"private_key_hex\":\"\(privKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "bitcoin.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
                store.resetSendComposerState {
                    store.bitcoinSendPreview = nil
                }
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
                let amountSat = UInt64(amount * 1e8)
                let feeSat = UInt64((store.bitcoinCashSendPreview?.estimatedNetworkFeeBTC ?? 0.00001) * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.bitcoinCash,
                    seedPhrase: seedPhrase,
                    chain: .bitcoinCash,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinCash)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "bitcoin_cash.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                let amountSat = UInt64(amount * 1e8)
                let feeSat = UInt64((store.bitcoinSVSendPreview?.estimatedNetworkFeeBTC ?? 0.00001) * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.bitcoinSv,
                    seedPhrase: seedPhrase,
                    chain: .bitcoinSV,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinSV)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "bitcoin_sv.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                let amountSat = UInt64(amount * 1e8)
                let feeSat = UInt64((store.litecoinSendPreview?.estimatedNetworkFeeBTC ?? 0.0001) * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.litecoin,
                    seedPhrase: seedPhrase,
                    chain: .litecoin,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .litecoin)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "litecoin.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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

            guard let sourceAddress = store.resolvedDogecoinAddress(for: wallet) else {
                store.sendError = "Unable to resolve this wallet's Dogecoin signing address."
                return
            }

            do {
                let amountSat = UInt64(dogecoinAmount * 1e8)
                let feeRateDOGEPerKB = store.dogecoinSendPreview?.estimatedFeeRateDOGEPerKB ?? 0.01
                let feeSat = UInt64(feeRateDOGEPerKB * 350.0 / 1000.0 * 1e8)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                    chainId: SpectraChainID.dogecoin,
                    seedPhrase: seedPhrase,
                    chain: .dogecoin,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .dogecoin)
                ) { privKeyHex, _ in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
                }
                let txid = WalletSendLayer.rustField("txid", from: resultJSON)
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
                    transactionHash: txid,
                    dogecoinConfirmations: 0,
                    dogecoinFeePriorityRaw: store.dogecoinFeePriority.rawValue,
                    dogecoinEstimatedFeeRateDOGEPerKB: store.dogecoinSendPreview?.estimatedFeeRateDOGEPerKB,
                    dogecoinUsedChangeOutput: store.dogecoinSendPreview?.usesChangeOutput,
                    sourceAddress: sourceAddress,
                    dogecoinRawTransactionHex: resultJSON,
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "dogecoin.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                store.clearSendVerificationNotice()
                store.appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE send broadcast.", transactionHash: txid)
                await store.refreshDogecoinTransactions()
                await store.refreshPendingDogecoinTransactions()
                store.updateSendVerificationNoticeForLastSentTransaction()
                store.resetSendComposerState {
                    store.dogecoinSendPreview = nil
                }
            } catch {
                store.sendError = error.localizedDescription
                store.appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE send failed: \(error.localizedDescription)")
                store.noteSendBroadcastFailure(for: holding.chainName, message: error.localizedDescription)
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
                if holding.symbol == "TRX", let seedPhrase {
                    // Native TRX: route through Rust
                    let amountSun = UInt64(amount * 1e6)
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                        chainId: SpectraChainID.tron,
                        seedPhrase: seedPhrase,
                        chain: .tron,
                        derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = TronSendResult(
                        transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                        estimatedNetworkFeeTRX: store.tronSendPreview?.estimatedNetworkFeeTRX ?? 0,
                        signedTransactionJSON: resultJSON,
                        verificationStatus: .verified
                    )
                } else if let seedPhrase, let contract = holding.contractAddress {
                    // TRC-20 USDT (and other supported TRC-20 tokens): route through Rust.
                    // USDT-TRC20 uses 6 decimals; scale amount × 1e6 as a decimal string.
                    let amountRawUInt = UInt64((amount * 1_000_000.0).rounded())
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.tron,
                        seedPhrase: seedPhrase,
                        chain: .tron,
                        derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contract)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = TronSendResult(
                        transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                        estimatedNetworkFeeTRX: store.tronSendPreview?.estimatedNetworkFeeTRX ?? 0,
                        signedTransactionJSON: resultJSON,
                        verificationStatus: .verified
                    )
                } else if let privateKey {
                    // Private-key-only path: route through Rust directly.
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    if holding.symbol == "TRX" {
                        let amountSun = UInt64(amount * 1e6)
                        let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(normalizedPriv)\"}"
                        let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                            chainId: SpectraChainID.tron,
                            paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                            estimatedNetworkFeeTRX: store.tronSendPreview?.estimatedNetworkFeeTRX ?? 0,
                            signedTransactionJSON: resultJSON,
                            verificationStatus: .verified
                        )
                    } else if let contract = holding.contractAddress {
                        let amountRawUInt = UInt64((amount * 1_000_000.0).rounded())
                        let paramsJson = "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contract)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"private_key_hex\":\"\(normalizedPriv)\"}"
                        let resultJSON = try await WalletServiceBridge.shared.signAndSendToken(
                            chainId: SpectraChainID.tron,
                            paramsJson: paramsJson
                        )
                        sendResult = TronSendResult(
                            transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                            estimatedNetworkFeeTRX: store.tronSendPreview?.estimatedNetworkFeeTRX ?? 0,
                            signedTransactionJSON: resultJSON,
                            verificationStatus: .verified
                        )
                    } else {
                        store.sendError = "Unsupported Tron asset for private-key send."
                        return
                    }
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
                    signedTransactionPayloadFormat: "tron.rust_json"
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
                if holding.symbol == "SOL" {
                    // Native SOL: route through Rust
                    let lamports = UInt64(amount * 1e9)
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.solana,
                        seedPhrase: seedPhrase,
                        chain: .solana,
                        derivationPath: store.walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        "{\"from_pubkey_hex\":\"\(pubKeyHex)\",\"to\":\"\(destinationAddress)\",\"lamports\":\(lamports),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: WalletSendLayer.rustField("signature", from: resultJSON),
                        estimatedNetworkFeeSOL: store.solanaSendPreview?.estimatedNetworkFeeSOL ?? 0,
                        signedTransactionBase64: resultJSON,
                        verificationStatus: .verified
                    )
                } else {
                    let solanaTokenMetadataByMint = store.solanaTrackedTokens(includeDisabled: true)
                    guard let mintAddress = holding.contractAddress ?? SolanaBalanceService.mintAddress(for: holding.symbol),
                          let tokenMetadata = solanaTokenMetadataByMint[mintAddress] else {
                        store.sendError = "\(holding.symbol) on Solana is not configured for sending yet."
                        return
                    }
                    // Scale amount by token decimals into an integer raw unit.
                    let decimals = tokenMetadata.decimals
                    let scale = pow(10.0, Double(decimals))
                    let amountRawUInt = UInt64((amount * scale).rounded())
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                        chainId: SpectraChainID.solana,
                        seedPhrase: seedPhrase,
                        chain: .solana,
                        derivationPath: store.walletDerivationPath(for: wallet, chain: .solana)
                    ) { privKeyHex, pubKeyHex in
                        let pk = pubKeyHex ?? ""
                        return "{\"from_pubkey_hex\":\"\(pk)\",\"to\":\"\(destinationAddress)\",\"mint\":\"\(mintAddress)\",\"amount_raw\":\"\(amountRawUInt)\",\"decimals\":\(decimals),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                    sendResult = SolanaSendResult(
                        transactionHash: WalletSendLayer.rustField("signature", from: resultJSON),
                        estimatedNetworkFeeSOL: store.solanaSendPreview?.estimatedNetworkFeeSOL ?? 0,
                        signedTransactionBase64: resultJSON,
                        verificationStatus: .verified
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
                    signedTransactionPayloadFormat: "solana.rust_json"
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
                let drops = UInt64(amount * 1e6)
                let txHash: String
                let signedPayload: String
                if let seedPhrase {
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.xrp,
                        seedPhrase: seedPhrase,
                        chain: .xrp,
                        derivationPath: store.walletDerivationPath(for: wallet, chain: .xrp)
                    ) { privKeyHex, pubKeyHex in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"drops\":\(drops),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                    }
                    txHash = WalletSendLayer.rustField("txid", from: resultJSON)
                    signedPayload = resultJSON
                } else if let privateKey {
                    // Private-key-only path: Rust derives the secp256k1 pubkey from the privkey.
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"drops\":\(drops),\"private_key_hex\":\"\(normalizedPriv)\"}"
                    let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                        chainId: SpectraChainID.xrp,
                        paramsJson: paramsJson
                    )
                    txHash = WalletSendLayer.rustField("txid", from: resultJSON)
                    signedPayload = resultJSON
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
                    transactionHash: txHash,
                    signedTransactionPayload: signedPayload,
                    signedTransactionPayloadFormat: "xrp.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                let stroops = Int64(amount * 1e7)
                let txHash: String
                let signedPayload: String
                if let seedPhrase {
                    let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                        chainId: SpectraChainID.stellar,
                        seedPhrase: seedPhrase,
                        chain: .stellar,
                        derivationPath: wallet.seedDerivationPaths.stellar
                    ) { privKeyHex, pubKeyHex in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                    }
                    txHash = WalletSendLayer.rustField("txid", from: resultJSON)
                    signedPayload = resultJSON
                } else if let privateKey {
                    // Private-key-only path: Rust derives the ed25519 pubkey from the 32-byte seed.
                    let normalizedPriv = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
                    let paramsJson = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(normalizedPriv)\"}"
                    let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                        chainId: SpectraChainID.stellar,
                        paramsJson: paramsJson
                    )
                    txHash = WalletSendLayer.rustField("txid", from: resultJSON)
                    signedPayload = resultJSON
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
                    transactionHash: txHash,
                    signedTransactionPayload: signedPayload,
                    signedTransactionPayloadFormat: "stellar.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                let piconeros = UInt64(amount * 1e12)
                let resultJSON = try await WalletServiceBridge.shared.signAndSend(
                    chainId: SpectraChainID.monero,
                    paramsJson: "{\"to\":\"\(destinationAddress)\",\"piconeros\":\(piconeros),\"priority\":2}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "monero.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                let amountLovelace = UInt64(amount * 1e6)
                let feeLovelace = UInt64((store.cardanoSendPreview?.estimatedNetworkFeeADA ?? 0.17) * 1e6)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.cardano,
                    seedPhrase: seedPhrase,
                    chain: .cardano,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .cardano)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"amount_lovelace\":\(amountLovelace),\"fee_lovelace\":\(feeLovelace),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "cardano.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                // NEAR uses u128 yocto (1 NEAR = 10^24 yocto); represent as decimal string
                let nearAmt = amount
                let yoctoStr = WalletSendLayer.nearToYoctoString(nearAmt)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.near,
                    seedPhrase: seedPhrase,
                    chain: .near,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .near)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"yocto_near\":\"\(yoctoStr)\",\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "near.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
                // Polkadot uses u128 planck (1 DOT = 10^10 planck); represent as decimal string
                let planckStr = WalletSendLayer.dotToPlanckString(amount)
                let resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivationAndPubKey(
                    chainId: SpectraChainID.polkadot,
                    seedPhrase: seedPhrase,
                    chain: .polkadot,
                    derivationPath: wallet.seedDerivationPaths.polkadot
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"planck\":\"\(planckStr)\",\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
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
                    transactionHash: WalletSendLayer.rustField("txid", from: resultJSON),
                    signedTransactionPayload: resultJSON,
                    signedTransactionPayloadFormat: "polkadot.rust_json"
                ), holding: holding)
                store.recordPendingSentTransaction(transaction)
                await store.runPostSendRefreshActions(for: holding.chainName, verificationStatus: .verified)
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
            if store.customEthereumNonceValidationError != nil {
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

            let nativeSymbol = preflight.nativeEVMSymbol ?? "ETH"
            let nativeBalance = wallet.holdings.first(where: { $0.chainName == holding.chainName && $0.symbol == nativeSymbol })?.amount ?? 0
            if store.ethereumSendPreview == nil {
                await refreshEthereumSendPreview(using: store)
            }
            guard let preview = store.ethereumSendPreview else {
                store.sendError = store.sendError ?? "Unable to estimate \(holding.chainName) network fee."
                return
            }

            if preflight.isNativeEVMAsset {
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
                if store.customEthereumFeeValidationError != nil {
                    store.sendError = store.customEthereumFeeValidationError
                    return
                }
                let customFees = store.customEthereumFeeConfiguration()
                let explicitNonce = store.explicitEthereumNonce()
                let evmDerivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: holding.chainName) ?? .ethereum
                let result: EthereumSendResult
                let spectraEvmChainId = SpectraChainID.id(for: holding.chainName)
                let overridesFragment = WalletSendLayer.evmOverridesJSONFragment(
                    nonce: explicitNonce,
                    customFees: customFees
                )
                let rustSupportsChain = spectraEvmChainId != nil
                if preflight.isNativeEVMAsset && rustSupportsChain, let chainId = spectraEvmChainId {
                    let valueWei = WalletSendLayer.ethToWeiString(amount)
                    guard let sourceAddress = store.resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        store.sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendWithDerivation(
                            chainId: chainId,
                            seedPhrase: seedPhrase,
                            chain: evmDerivationChain,
                            derivationPath: store.walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                        }
                    } else if let privateKey {
                        let payload = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destinationAddress)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(privateKey)\"\(overridesFragment)}"
                        resultJSON = try await WalletServiceBridge.shared.signAndSend(chainId: chainId, paramsJson: payload)
                    } else {
                        store.sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = WalletSendLayer.decodeEvmSendResult(
                        resultJSON,
                        fallbackNonce: explicitNonce ?? store.ethereumSendPreview?.nonce ?? 0
                    )
                } else if let token = store.supportedEVMToken(for: holding), rustSupportsChain, let chainId = spectraEvmChainId {
                    guard let sourceAddress = store.resolvedEVMAddress(for: wallet, chainName: holding.chainName) else {
                        store.sendError = "Unable to resolve this wallet's \(holding.chainName) signing address."
                        return
                    }
                    let amountRaw = WalletSendLayer.tokenAmountToRawString(amount, decimals: token.decimals)
                    let resultJSON: String
                    if let seedPhrase {
                        resultJSON = try await WalletServiceBridge.shared.signAndSendTokenWithDerivation(
                            chainId: chainId,
                            seedPhrase: seedPhrase,
                            chain: evmDerivationChain,
                            derivationPath: store.walletDerivationPath(for: wallet, chain: evmDerivationChain)
                        ) { privKeyHex, _ in
                            "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(token.contractAddress)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                        }
                    } else if let privateKey {
                        let payload = "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(token.contractAddress)\",\"to\":\"\(destinationAddress)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privateKey)\"\(overridesFragment)}"
                        resultJSON = try await WalletServiceBridge.shared.signAndSendToken(chainId: chainId, paramsJson: payload)
                    } else {
                        store.sendError = "This wallet's signing key is unavailable."
                        return
                    }
                    result = WalletSendLayer.decodeEvmSendResult(
                        resultJSON,
                        fallbackNonce: explicitNonce ?? store.ethereumSendPreview?.nonce ?? 0
                    )
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

    // MARK: - Rust send result helpers

    /// Extract a string or numeric field from a Rust-returned JSON result.
    /// Returns the value as a String (numeric values are stringified).
    static func rustField(_ key: String, from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = obj[key] else { return "" }
        if let s = val as? String { return s }
        return "\(val)"
    }

    /// Convert a NEAR amount (Double, in NEAR) to a yocto string (u128 decimal).
    /// 1 NEAR = 10^24 yocto. Uses string-based scaling to avoid UInt64 overflow.
    static func nearToYoctoString(_ near: Double) -> String {
        // Format with 12 decimal places → remove decimal point → append 12 zeros.
        // This gives a 24-digit yocto representation correct to 12 significant frac digits.
        let formatted = String(format: "%.12f", near)          // e.g. "1.500000000000"
        let noDecimal = formatted.replacingOccurrences(of: ".", with: "")  // "1500000000000"
        let yoctoStr  = noDecimal + String(repeating: "0", count: 12)      // append 12 more zeros → 10^24 scale
        let trimmed   = yoctoStr.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    /// Convert a DOT amount (Double) to planck string. 1 DOT = 10^10 planck.
    static func dotToPlanckString(_ dot: Double) -> String {
        return "\(UInt64((dot * 1e10).rounded()))"
    }

    /// Convert an ETH amount (Double) to a wei decimal string with 18 decimals
    /// of scale. Uses string-based padding to keep full precision for values
    /// that would overflow UInt64 (anything above ~18 ETH).
    static func ethToWeiString(_ eth: Double) -> String {
        return tokenAmountToRawString(eth, decimals: 18)
    }

    /// Scale a decimal amount (e.g. "1.234567") by `decimals` and return the
    /// integer raw-unit string. Used by EVM native + ERC-20 migrations to
    /// feed Rust's u128 `value_wei` / `amount_raw` params without losing
    /// precision to Double rounding.
    static func tokenAmountToRawString(_ amount: Double, decimals: Int) -> String {
        guard amount.isFinite, amount >= 0 else { return "0" }
        // Format with 9 fractional digits of IEEE754 precision, then
        // pad or truncate the fractional portion to `decimals` zeros.
        let formatted = String(format: "%.9f", amount)
        let parts = formatted.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        var frac = parts.count > 1 ? String(parts[1]) : ""
        if frac.count < decimals {
            frac += String(repeating: "0", count: decimals - frac.count)
        } else if frac.count > decimals {
            frac = String(frac.prefix(decimals))
        }
        let combined = whole + frac
        let trimmed = combined.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    /// Build the trailing JSON object fragment (always starts with `,`) that
    /// contains optional EVM send overrides. Returns an empty string when no
    /// overrides apply.
    static func evmOverridesJSONFragment(
        nonce: Int?,
        customFees: EthereumCustomFeeConfiguration?
    ) -> String {
        var fragments: [String] = []
        if let nonce {
            fragments.append("\"nonce\":\(nonce)")
        }
        if let customFees {
            let maxFeeWei = UInt64((customFees.maxFeePerGasGwei * 1e9).rounded())
            let priorityWei = UInt64((customFees.maxPriorityFeePerGasGwei * 1e9).rounded())
            fragments.append("\"max_fee_per_gas_wei\":\"\(maxFeeWei)\"")
            fragments.append("\"max_priority_fee_per_gas_wei\":\"\(priorityWei)\"")
        }
        return fragments.isEmpty ? "" : "," + fragments.joined(separator: ",")
    }

    /// Decode the `EvmSendResult` JSON that Rust returns after a successful
    /// EVM send, mapping it into the Swift `EthereumSendResult` shape the
    /// transaction-record pipeline still expects. `fallbackNonce` is used
    /// when Rust didn't return a nonce (e.g. `broadcast_raw` path).
    static func decodeEvmSendResult(
        _ json: String,
        fallbackNonce: Int
    ) -> EthereumSendResult {
        let txid = rustField("txid", from: json)
        let rawTxHex = rustField("raw_tx_hex", from: json)
        let nonceString = rustField("nonce", from: json)
        let nonce = Int(nonceString) ?? fallbackNonce
        let gasLimit = Int(rustField("gas_limit", from: json)) ?? 0
        let preview = EthereumSendPreview(
            nonce: nonce,
            gasLimit: gasLimit,
            maxFeePerGasGwei: 0,
            maxPriorityFeePerGasGwei: 0,
            estimatedNetworkFeeETH: 0,
            spendableBalance: nil,
            feeRateDescription: nil,
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: nil
        )
        return EthereumSendResult(
            fromAddress: "",
            transactionHash: txid,
            rawTransactionHex: rawTxHex,
            preview: preview,
            verificationStatus: .verified
        )
    }
}
