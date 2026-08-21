import Foundation

// MARK: - Private pure helpers (no store state)

private func decodedUTXOFeePreview(chainId: String, address: String, satPerCoin: Double, feeRateSvb: UInt64 = 0) async throws
    -> BitcoinSendPreview
{
    guard
        let preview = try await WalletServiceBridge.shared.fetchUtxoFeePreviewTyped(
            chainId: chainId, address: address, feeRateSvb: feeRateSvb)
    else {
        throw NSError(domain: "UTXOFeePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"])
    }
    return preview
}

private func evmCustomFeeDTO(_ customFees: EthereumCustomFeeConfiguration?) -> EvmCustomFeeConfiguration? {
    customFees.map {
        EvmCustomFeeConfiguration(maxFeePerGasGwei: $0.maxFeePerGasGwei, maxPriorityFeePerGasGwei: $0.maxPriorityFeePerGasGwei)
    }
}

// MARK: - AppState send preview methods

extension AppState {
    func refreshEthereumSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, isEVMChain(selectedSendCoin.chainName),
            let fromAddress = resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName), let amount = Double(sendAmount),
            ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB")
                ? amount >= 0 : amount > 0)
        else {
            sendPreviewStore.ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        if let customEthereumNonceValidationError = customEthereumNonceValidationError {
            sendError = customEthereumNonceValidationError
            sendPreviewStore.ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty {
            previewDestination = fromAddress
        } else {
            if AddressValidation.isValid(trimmedDestination, kind: "evm") {
                previewDestination = normalizeEVMAddress(trimmedDestination)
            } else if selectedSendCoin.chainName == "Ethereum", isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmedDestination) else {
                        sendPreviewStore.ethereumSendPreview = nil
                        preparingChains.remove("Ethereum")
                        return
                    }
                    previewDestination = resolved
                    sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    sendPreviewStore.ethereumSendPreview = nil
                    preparingChains.remove("Ethereum")
                    return
                }
            } else {
                sendPreviewStore.ethereumSendPreview = nil
                preparingChains.remove("Ethereum")
                return
            }
        }
        guard !preparingChains.contains("Ethereum") else {
            pendingSendPreviewRefreshChains.insert("Ethereum")
            return
        }
        preparingChains.insert("Ethereum")
        defer {
            preparingChains.remove("Ethereum")
            if pendingSendPreviewRefreshChains.remove("Ethereum") != nil {
                Task { @MainActor in await self.refreshEthereumSendPreview() }
            }
        }
        guard let chainId = Chain(displayName: selectedSendCoin.chainName)?.id else {
            sendPreviewStore.ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
            return
        }
        do {
            let assemblyToken: EvmSupportedToken? = supportedEVMToken(for: selectedSendCoin).map {
                EvmSupportedToken(symbol: $0.symbol, contractAddress: $0.contractAddress, decimals: UInt32($0.decimals))
            }
            let assembly: EvmSendAssembly
            do {
                assembly = try prepareEvmSendAssembly(
                    input: EvmSendAssemblyInput(
                        chainName: selectedSendCoin.chainName, symbol: selectedSendCoin.symbol,
                        fromAddress: fromAddress, resolvedDestination: previewDestination, amount: amount,
                        token: assemblyToken
                    ))
            } catch {
                sendPreviewStore.ethereumSendPreview = nil
                preparingChains.remove("Ethereum")
                return
            }
            let valueWei = assembly.valueWei
            let toAddress = assembly.toAddress
            let dataHex = assembly.dataHex
            sendPreviewStore.ethereumSendPreview = try await WalletServiceBridge.shared.fetchEvmSendPreviewTyped(
                chainId: chainId, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex,
                explicitNonce: explicitEthereumNonce().map(Int64.init),
                customFees: evmCustomFeeDTO(customEthereumFeeConfiguration())
            )
            if sendPreviewStore.ethereumSendPreview != nil {
                sendError = nil
                clearSendVerificationNotice()
            }
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.ethereumSendPreview = nil
            sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }
    }
    func refreshDogecoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Dogecoin",
            selectedSendCoin.symbol == "DOGE", let amount = parseDogecoinAmountInput(sendAmount), amount > 0
        else {
            sendPreviewStore.dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !isValidDogecoinAddressForPolicy(trimmedDestination, wallet: wallet)
        {
            sendPreviewStore.dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            sendPreviewStore.dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        guard !preparingChains.contains("Dogecoin") else {
            pendingSendPreviewRefreshChains.insert("Dogecoin")
            return
        }
        preparingChains.insert("Dogecoin")
        defer {
            preparingChains.remove("Dogecoin")
            if pendingSendPreviewRefreshChains.remove("Dogecoin") != nil {
                Task { @MainActor in await self.refreshDogecoinSendPreview() }
            }
        }
        guard let address = resolvedDogecoinAddress(for: wallet) else {
            sendPreviewStore.dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
            return
        }
        do {
            guard
                let preview = try await WalletServiceBridge.shared.fetchDogecoinSendPreviewTyped(
                    address: address, requestedAmount: amount, feePriority: dogecoinFeePriority.rawValue)
            else {
                sendPreviewStore.dogecoinSendPreview = nil
                sendError = "Insufficient DOGE funds."
                return
            }
            sendPreviewStore.dogecoinSendPreview = preview
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.dogecoinSendPreview = nil
            sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }
    }
    func refreshBitcoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Bitcoin",
            selectedSendCoin.symbol == "BTC", let amount = Double(sendAmount), amount > 0
        else {
            sendPreviewStore.bitcoinSendPreview = nil
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            sendPreviewStore.bitcoinSendPreview = nil
            return
        }
        do {
            if let xpub = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !xpub.isEmpty {
                sendPreviewStore.bitcoinSendPreview = try await WalletServiceBridge.shared.fetchBitcoinHdSendPreviewTyped(xpub: xpub)
            } else if let address = resolvedBitcoinAddress(for: wallet) {
                sendPreviewStore.bitcoinSendPreview = try await decodedUTXOFeePreview(
                    chainId: Chain.bitcoin.id, address: address, satPerCoin: 100_000_000
                )
            } else {
                sendPreviewStore.bitcoinSendPreview = nil
            }
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.bitcoinSendPreview = nil
            sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }
    }
    private func refreshUTXOSatChainPreview(
        chainName: String, symbol: String, chainId: String, resolveAddress: (ImportedWallet) -> String?,
        setPreview: (BitcoinSendPreview?) -> Void
    ) async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == chainName,
            selectedSendCoin.symbol == symbol, let amount = Double(sendAmount), amount > 0
        else { setPreview(nil); return }
        guard storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolveAddress(wallet) else { setPreview(nil); return }
        do {
            setPreview(try await decodedUTXOFeePreview(chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000))
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            setPreview(nil)
            sendError = "Unable to estimate \(symbol) fee right now. Check provider health and retry."
        }
    }
    func refreshBitcoinCashSendPreview() async {
        await refreshUTXOSatChainPreview(
            chainName: "Bitcoin Cash", symbol: "BCH", chainId: Chain.bitcoinCash.id,
            resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, setPreview: { self.sendPreviewStore.bitcoinCashSendPreview = $0 })
    }
    func refreshBitcoinSVSendPreview() async {
        await refreshUTXOSatChainPreview(
            chainName: "Bitcoin SV", symbol: "BSV", chainId: Chain.bitcoinSv.id,
            resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, setPreview: { self.sendPreviewStore.bitcoinSVSendPreview = $0 })
    }
    func refreshLitecoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin,
            selectedSendCoin.chainName == "Litecoin", selectedSendCoin.symbol == "LTC",
            let amount = Double(sendAmount), amount > 0
        else { sendPreviewStore.litecoinSendPreview = nil; return }
        guard storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolvedLitecoinAddress(for: wallet)
        else { sendPreviewStore.litecoinSendPreview = nil; return }
        let isMweb = sendAddress.hasPrefix("ltcmweb1") || sendAddress.hasPrefix("tmweb1")
        do {
            var preview = try await decodedUTXOFeePreview(chainId: Chain.litecoin.id, address: sourceAddress, satPerCoin: 100_000_000)
            if isMweb {
                let mwebOverhead: Int64 = 1017
                let adjustedBytes = (preview.estimatedTransactionBytes ?? 0) + mwebOverhead
                let additionalFeeBtc = Double(mwebOverhead) * Double(preview.estimatedFeeRateSatVb) / 100_000_000.0
                preview = BitcoinSendPreview(
                    estimatedFeeRateSatVb: preview.estimatedFeeRateSatVb,
                    estimatedNetworkFee: preview.estimatedNetworkFee + additionalFeeBtc,
                    feeRateDescription: preview.feeRateDescription,
                    spendableBalance: preview.spendableBalance,
                    estimatedTransactionBytes: adjustedBytes,
                    selectedInputCount: preview.selectedInputCount,
                    usesChangeOutput: preview.usesChangeOutput,
                    maxSendable: preview.maxSendable.map { max(0, $0 - additionalFeeBtc) }
                )
            }
            sendPreviewStore.litecoinSendPreview = preview
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.litecoinSendPreview = nil
            sendError = "Unable to estimate LTC fee right now. Check provider health and retry."
        }
    }
    func refreshTronSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Tron",
            (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"), let amount = Double(sendAmount), amount > 0
        else {
            sendPreviewStore.tronSendPreview = nil
            preparingChains.remove("Tron")
            return
        }
        guard let sourceAddress = resolvedTronAddress(for: wallet) else {
            sendPreviewStore.tronSendPreview = nil
            preparingChains.remove("Tron")
            return
        }
        guard !preparingChains.contains("Tron") else { return }
        preparingChains.insert("Tron")
        defer { preparingChains.remove("Tron") }
        do {
            sendPreviewStore.tronSendPreview = try await WalletServiceBridge.shared.fetchTronSendPreviewTyped(
                address: sourceAddress, symbol: selectedSendCoin.symbol, contractAddress: selectedSendCoin.contractAddress ?? ""
            )
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.tronSendPreview = nil
            sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }
    }
    // Simple-chain dispatch: Rust owns per-chain defaults (fee raw parsing, priorityLabel,
    // gasBudgetMist, feeStroops, etc.). Swift just resolves address, fetches JSON, and
    // applies the tagged-enum result to the right AppState field.
    private struct SimpleChainConfig {
        let chainId: String
        let rustChain: SimpleChain
        let coinCheck: (AppState, Coin) async -> Bool
        let resolveAddress: (AppState, ImportedWallet) -> String?
        let chainName: String
        let applyPreview: (AppState, SimpleChainPreview?) -> Void
        let errorMessage: String
    }
    @MainActor private func refreshSimpleChain(_ cfg: SimpleChainConfig) async {
        guard let wallet = wallet(for: sendWalletID), let coin = selectedSendCoin,
            await cfg.coinCheck(self, coin),
            let amount = Double(sendAmount), amount > 0
        else { cfg.applyPreview(self, nil); preparingChains.remove(cfg.chainName); return }
        guard let src = cfg.resolveAddress(self, wallet)
        else { cfg.applyPreview(self, nil); preparingChains.remove(cfg.chainName); return }
        guard !preparingChains.contains(cfg.chainName) else { return }
        preparingChains.insert(cfg.chainName); defer { preparingChains.remove(cfg.chainName) }
        do {
            let preview = try await WalletServiceBridge.shared.fetchSimpleChainSendPreviewTyped(
                chainId: cfg.chainId, address: src, chain: cfg.rustChain)
            cfg.applyPreview(self, preview)
            sendError = nil
        } catch {
            if isCancelledRequest(error) { return }
            cfg.applyPreview(self, nil)
            sendError = cfg.errorMessage
        }
    }
    /// Which `SimpleChain` a chain name is, for chains whose preview core
    /// fetches through one entry point.
    private static let simplePreviewChains: [String: SimpleChain] = [
        "Solana": .solana, "XRP Ledger": .xrp, "Stellar": .stellar, "Monero": .monero,
        "Cardano": .cardano, "Sui": .sui, "Aptos": .aptos, "TON": .ton,
        "Internet Computer": .icp, "NEAR": .near, "Polkadot": .polkadot,
    ]

    /// Refresh the send preview for a chain core estimates through the shared
    /// path.
    ///
    /// Eleven near-identical functions used to do this, differing in a chain
    /// name, a symbol, an address resolver and a message. Two differences were
    /// real and are stated here: Solana's sendable-coin rule is its own, and
    /// Polkadot refuses to preview without a seed phrase.
    func refreshSendPreview(forChainNamed chainName: String) async {
        guard let rustChain = Self.simplePreviewChains[chainName],
            let chainID = Chain(displayName: chainName)?.id, !chainID.isEmpty
        else { return }
        let symbol = Chain(displayName: chainName)?.gasTokenSymbol ?? ""
        await refreshSimpleChain(
            .init(
                chainId: chainID, rustChain: rustChain,
                coinCheck: { s, c in
                    // Solana's rule is core's: SOL, or a token whose mint the
                    // user tracks. Asking core rather than repeating it here is
                    // what let the Swift copy of that rule go.
                    guard chainName == "Solana" else {
                        return c.chainName == chainName && c.symbol == symbol
                    }
                    let plan = await WalletServiceBridge.shared.sendAssetRouting(
                        walletID: s.sendWalletID, holdingKey: c.holdingKey)
                    return plan?.previewKind == "solana"
                },
                resolveAddress: { s, w in
                    // Polkadot's estimate needs the account, which it derives
                    // from the seed; a watch-only wallet gets no preview.
                    if chainName == "Polkadot", s.storedSeedPhrase(for: w.id) == nil { return nil }
                    return s.resolvedAddress(for: w, chainName: chainName)
                },
                chainName: chainName,
                applyPreview: { s, p in s.sendPreviewStore.apply(p, forChainNamed: chainName) },
                errorMessage: "Unable to estimate \(chainName) fee right now. Check provider health and retry."))
    }
}
