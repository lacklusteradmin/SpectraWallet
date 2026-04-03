import Foundation

extension WalletSendLayer {
    static func refreshEthereumSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              store.isEVMChain(selectedSendCoin.chainName),
              let chain = store.evmChainContext(for: selectedSendCoin.chainName),
              let fromAddress = store.resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName),
              let amount = Double(store.sendAmount),
              ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB") ? amount >= 0 : amount > 0) else {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }
        if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
            store.sendError = customEthereumNonceValidationError
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }

        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty {
            previewDestination = fromAddress
        } else {
            if AddressValidation.isValidEthereumAddress(trimmedDestination) {
                previewDestination = EthereumWalletEngine.normalizeAddress(trimmedDestination)
            } else if selectedSendCoin.chainName == "Ethereum", store.isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await EthereumWalletEngine.resolveENSAddress(trimmedDestination, chain: .ethereum) else {
                        store.ethereumSendPreview = nil
                        store.isPreparingEthereumSend = false
                        return
                    }
                    previewDestination = resolved
                    store.sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    store.ethereumSendPreview = nil
                    store.isPreparingEthereumSend = false
                    return
                }
            } else {
                store.ethereumSendPreview = nil
                store.isPreparingEthereumSend = false
                return
            }
        }

        guard !store.isPreparingEthereumSend else {
            store.pendingEthereumSendPreviewRefresh = true
            return
        }
        store.isPreparingEthereumSend = true
        defer {
            store.isPreparingEthereumSend = false
            if store.pendingEthereumSendPreviewRefresh {
                store.pendingEthereumSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshEthereumSendPreview(using: store)
                }
            }
        }

        do {
            if selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB" {
                store.ethereumSendPreview = try await EthereumWalletEngine.fetchSendPreview(
                    from: fromAddress,
                    to: previewDestination,
                    amountETH: amount,
                    explicitNonce: store.explicitEthereumNonce(),
                    customFees: store.customEthereumFeeConfiguration(),
                    rpcEndpoint: store.configuredEVMRPCEndpointURL(for: selectedSendCoin.chainName),
                    chain: chain
                )
            } else if let token = store.supportedEVMToken(for: selectedSendCoin) {
                store.ethereumSendPreview = try await EthereumWalletEngine.fetchTokenSendPreview(
                    from: fromAddress,
                    to: previewDestination,
                    token: token,
                    amount: amount,
                    explicitNonce: store.explicitEthereumNonce(),
                    customFees: store.customEthereumFeeConfiguration(),
                    rpcEndpoint: store.configuredEVMRPCEndpointURL(for: selectedSendCoin.chainName),
                    chain: chain
                )
            } else {
                store.ethereumSendPreview = nil
            }
            if store.ethereumSendPreview != nil {
                store.sendError = nil
                store.clearSendVerificationNotice()
            }
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.ethereumSendPreview = nil
            store.sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }
    }

    static func refreshDogecoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Dogecoin",
              selectedSendCoin.symbol == "DOGE",
              let amount = store.parseDogecoinAmountInput(store.sendAmount),
              amount > 0 else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !store.isValidDogecoinAddressForPolicy(trimmedDestination, networkMode: store.dogecoinNetworkMode(for: wallet)) {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        guard !store.isPreparingDogecoinSend else {
            store.pendingDogecoinSendPreviewRefresh = true
            return
        }
        store.isPreparingDogecoinSend = true
        defer {
            store.isPreparingDogecoinSend = false
            if store.pendingDogecoinSendPreviewRefresh {
                store.pendingDogecoinSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshDogecoinSendPreview(using: store)
                }
            }
        }

        do {
            store.dogecoinSendPreview = try await DogecoinWalletEngine.fetchSendPreviewInBackground(
                from: store.walletWithResolvedDogecoinAddress(wallet),
                seedPhrase: seedPhrase,
                amountDOGE: amount,
                feePriority: store.dogecoinFeePriority,
                maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.dogecoinSendPreview = nil
            store.sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin",
              selectedSendCoin.symbol == "BTC",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinSendPreview = nil
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
            store.bitcoinSendPreview = nil
            return
        }
        let selectedFeePriority = store.bitcoinFeePriority(for: selectedSendCoin.chainName)

        do {
            let preview = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let preview = try BitcoinWalletEngine.estimateSendPreview(
                            for: wallet,
                            seedPhrase: seedPhrase,
                            feePriority: selectedFeePriority
                        )
                        continuation.resume(returning: preview)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            store.bitcoinSendPreview = preview
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinSendPreview = nil
            store.sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinCashSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin Cash",
              selectedSendCoin.symbol == "BCH",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinCashSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil,
              let sourceAddress = store.resolvedBitcoinCashAddress(for: wallet) else {
            store.bitcoinCashSendPreview = nil
            return
        }
        do {
            store.bitcoinCashSendPreview = try await BitcoinCashWalletEngine.estimateSendPreview(
                sourceAddress: sourceAddress,
                maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinCashSendPreview = nil
            store.sendError = "Unable to estimate BCH fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinSVSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin SV",
              selectedSendCoin.symbol == "BSV",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinSVSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil,
              let sourceAddress = store.resolvedBitcoinSVAddress(for: wallet) else {
            store.bitcoinSVSendPreview = nil
            return
        }
        do {
            store.bitcoinSVSendPreview = try await BitcoinSVWalletEngine.estimateSendPreview(
                sourceAddress: sourceAddress,
                maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinSVSendPreview = nil
            store.sendError = "Unable to estimate BSV fee right now. Check provider health and retry."
        }
    }

    static func refreshLitecoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Litecoin",
              selectedSendCoin.symbol == "LTC",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.litecoinSendPreview = nil
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id),
              let sourceAddress = store.resolvedLitecoinAddress(for: wallet) else {
            store.litecoinSendPreview = nil
            return
        }
        let selectedFeePriority = store.bitcoinFeePriority(for: selectedSendCoin.chainName)

        do {
            store.litecoinSendPreview = try await LitecoinWalletEngine.estimateSendPreview(
                seedPhrase: seedPhrase,
                sourceAddress: sourceAddress,
                feePriority: selectedFeePriority,
                maxInputCount: store.sendAdvancedMode && store.sendUTXOMaxInputCount > 0 ? store.sendUTXOMaxInputCount : nil
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.litecoinSendPreview = nil
            store.sendError = "Unable to estimate LTC fee right now. Check provider health and retry."
        }
    }

    static func refreshTronSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Tron",
              (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"),
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }

        guard let sourceAddress = store.resolvedTronAddress(for: wallet) else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }

        guard !store.isPreparingTronSend else { return }
        store.isPreparingTronSend = true
        defer { store.isPreparingTronSend = false }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        do {
            store.tronSendPreview = try await TronWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                symbol: selectedSendCoin.symbol,
                amount: amount,
                contractAddress: selectedSendCoin.contractAddress
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.tronSendPreview = nil
            store.sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }
    }

    static func refreshSolanaSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              store.isSupportedSolanaSendCoin(selectedSendCoin),
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.solanaSendPreview = nil
            store.isPreparingSolanaSend = false
            return
        }

        guard let sourceAddress = store.resolvedSolanaAddress(for: wallet) else {
            store.solanaSendPreview = nil
            store.isPreparingSolanaSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingSolanaSend else { return }
        store.isPreparingSolanaSend = true
        defer { store.isPreparingSolanaSend = false }

        do {
            store.solanaSendPreview = try await SolanaWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.solanaSendPreview = nil
            store.sendError = "Unable to estimate Solana fee right now. Check provider health and retry."
        }
    }

    static func refreshXRPSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "XRP Ledger",
              selectedSendCoin.symbol == "XRP",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.xrpSendPreview = nil
            store.isPreparingXRPSend = false
            return
        }

        guard let sourceAddress = store.resolvedXRPAddress(for: wallet) else {
            store.xrpSendPreview = nil
            store.isPreparingXRPSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingXRPSend else { return }
        store.isPreparingXRPSend = true
        defer { store.isPreparingXRPSend = false }

        do {
            store.xrpSendPreview = try await XRPWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.xrpSendPreview = nil
            store.sendError = "Unable to estimate XRP fee right now. Check provider health and retry."
        }
    }

    static func refreshStellarSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Stellar",
              selectedSendCoin.symbol == "XLM",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.stellarSendPreview = nil
            store.isPreparingStellarSend = false
            return
        }

        guard let sourceAddress = store.resolvedStellarAddress(for: wallet) else {
            store.stellarSendPreview = nil
            store.isPreparingStellarSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingStellarSend else { return }
        store.isPreparingStellarSend = true
        defer { store.isPreparingStellarSend = false }

        do {
            store.stellarSendPreview = try await StellarWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.stellarSendPreview = nil
            store.sendError = "Unable to estimate Stellar fee right now. Check provider health and retry."
        }
    }

    static func refreshMoneroSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Monero",
              selectedSendCoin.symbol == "XMR",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.moneroSendPreview = nil
            store.isPreparingMoneroSend = false
            return
        }

        guard let sourceAddress = store.resolvedMoneroAddress(for: wallet) else {
            store.moneroSendPreview = nil
            store.isPreparingMoneroSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingMoneroSend else { return }
        store.isPreparingMoneroSend = true
        defer { store.isPreparingMoneroSend = false }

        do {
            store.moneroSendPreview = try await MoneroWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.moneroSendPreview = MoneroSendPreview(
                estimatedNetworkFeeXMR: 0.0002,
                priorityLabel: "normal",
                spendableBalance: 0,
                feeRateDescription: "normal",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = error.localizedDescription
        }
    }

    static func refreshCardanoSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Cardano",
              selectedSendCoin.symbol == "ADA",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.cardanoSendPreview = nil
            store.isPreparingCardanoSend = false
            return
        }

        guard let sourceAddress = store.resolvedCardanoAddress(for: wallet) else {
            store.cardanoSendPreview = nil
            store.isPreparingCardanoSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingCardanoSend else { return }
        store.isPreparingCardanoSend = true
        defer { store.isPreparingCardanoSend = false }

        do {
            store.cardanoSendPreview = try await CardanoWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.cardanoSendPreview = CardanoSendPreview(
                estimatedNetworkFeeADA: 0.2,
                ttlSlot: 0,
                spendableBalance: 0,
                feeRateDescription: nil,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingCardanoSendError(error)
        }
    }

    static func refreshSuiSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Sui",
              selectedSendCoin.symbol == "SUI",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.suiSendPreview = nil
            store.isPreparingSuiSend = false
            return
        }

        guard let sourceAddress = store.resolvedSuiAddress(for: wallet) else {
            store.suiSendPreview = nil
            store.isPreparingSuiSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingSuiSend else { return }
        store.isPreparingSuiSend = true
        defer { store.isPreparingSuiSend = false }

        do {
            store.suiSendPreview = try await SuiWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.suiSendPreview = SuiSendPreview(
                estimatedNetworkFeeSUI: 0.001,
                gasBudgetMist: 3_000_000,
                referenceGasPrice: 1_000,
                spendableBalance: 0,
                feeRateDescription: "Reference gas price: 1000",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingSuiSendError(error)
        }
    }

    static func refreshAptosSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Aptos",
              selectedSendCoin.symbol == "APT",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.aptosSendPreview = nil
            store.isPreparingAptosSend = false
            return
        }

        guard let sourceAddress = store.resolvedAptosAddress(for: wallet) else {
            store.aptosSendPreview = nil
            store.isPreparingAptosSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingAptosSend else { return }
        store.isPreparingAptosSend = true
        defer { store.isPreparingAptosSend = false }

        do {
            store.aptosSendPreview = try await AptosWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.aptosSendPreview = AptosSendPreview(
                estimatedNetworkFeeAPT: 0.0002,
                maxGasAmount: 2_000,
                gasUnitPriceOctas: 100,
                spendableBalance: 0,
                feeRateDescription: "100 octas/unit",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingAptosSendError(error)
        }
    }

    static func refreshTONSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "TON",
              selectedSendCoin.symbol == "TON",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.tonSendPreview = nil
            store.isPreparingTONSend = false
            return
        }

        guard let sourceAddress = store.resolvedTONAddress(for: wallet) else {
            store.tonSendPreview = nil
            store.isPreparingTONSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingTONSend else { return }
        store.isPreparingTONSend = true
        defer { store.isPreparingTONSend = false }

        do {
            store.tonSendPreview = try await TONWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.tonSendPreview = TONSendPreview(
                estimatedNetworkFeeTON: 0.005,
                sequenceNumber: 0,
                spendableBalance: 0,
                feeRateDescription: nil,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingTONSendError(error)
        }
    }

    static func refreshICPSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Internet Computer",
              selectedSendCoin.symbol == "ICP",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.icpSendPreview = nil
            store.isPreparingICPSend = false
            return
        }

        guard let sourceAddress = store.resolvedICPAddress(for: wallet) else {
            store.icpSendPreview = nil
            store.isPreparingICPSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingICPSend else { return }
        store.isPreparingICPSend = true
        defer { store.isPreparingICPSend = false }

        do {
            store.icpSendPreview = try await ICPWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.icpSendPreview = nil
            store.sendError = error.localizedDescription
        }
    }

    static func refreshNearSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "NEAR",
              selectedSendCoin.symbol == "NEAR",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.nearSendPreview = nil
            store.isPreparingNearSend = false
            return
        }

        guard let sourceAddress = store.resolvedNearAddress(for: wallet) else {
            store.nearSendPreview = nil
            store.isPreparingNearSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingNearSend else { return }
        store.isPreparingNearSend = true
        defer { store.isPreparingNearSend = false }

        do {
            store.nearSendPreview = try await NearWalletEngine.estimateSendPreview(
                from: sourceAddress,
                to: previewAddress,
                amount: amount
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.nearSendPreview = NearSendPreview(
                estimatedNetworkFeeNEAR: 0.00005,
                gasPriceYoctoNear: "100000000",
                spendableBalance: 0,
                feeRateDescription: "100000000",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingNearSendError(error)
        }
    }

    static func refreshPolkadotSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Polkadot",
              selectedSendCoin.symbol == "DOT",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.polkadotSendPreview = nil
            store.isPreparingPolkadotSend = false
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id),
              let sourceAddress = store.resolvedPolkadotAddress(for: wallet) else {
            store.polkadotSendPreview = nil
            store.isPreparingPolkadotSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingPolkadotSend else { return }
        store.isPreparingPolkadotSend = true
        defer { store.isPreparingPolkadotSend = false }

        do {
            store.polkadotSendPreview = try await PolkadotWalletEngine.estimateSendPreview(
                seedPhrase: seedPhrase,
                ownerAddress: sourceAddress,
                destinationAddress: previewAddress,
                amount: amount,
                derivationPath: wallet.seedDerivationPaths.polkadot
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.polkadotSendPreview = nil
            store.sendError = store.userFacingPolkadotSendError(error)
        }
    }
}
