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

// MARK: - AppState send preview methods

extension AppState {
    /// Hold one chain's "preview in flight" flag for the duration of `body`,
    /// coalescing a second request into a single retry afterwards.
    ///
    /// The three debounced previews each inlined this, and each also called
    /// `preparingChains.remove(chainName)` on **every early exit** — including
    /// the exits that run *before* the flag is set. Those did not clear this
    /// call's flag, because this call had not set one; they cleared whatever
    /// call was actually in flight. So a keystroke that made the input
    /// momentarily invalid dropped the guard protecting a request already on
    /// the network, and the next keystroke started a second one beside it.
    ///
    /// Nothing outside this function touches the flag now, so an early exit
    /// cannot reach it.
    private func withSendPreviewInFlight(
        _ chainName: String, retry: @escaping @MainActor () async -> Void, body: () async -> Void
    ) async {
        guard !preparingChains.contains(chainName) else {
            pendingSendPreviewRefreshChains.insert(chainName)
            return
        }
        preparingChains.insert(chainName)
        defer {
            preparingChains.remove(chainName)
            if pendingSendPreviewRefreshChains.remove(chainName) != nil {
                Task { @MainActor in await retry() }
            }
        }
        await body()
    }

    func refreshEvmSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, isEVMChain(selectedSendCoin.chainName),
            let fromAddress = resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName), let amount = Double(sendAmount),
            // Whether a zero amount previews is `allows_zero_amount`, which core
            // derives from `is_native_evm_asset`. Three symbols were named here
            // — the third place this rule has been written down — so a
            // zero-amount preview was refused on the twenty EVM chains whose
            // gas token is none of ETH, ETC or BNB.
            ((selectedSendCoin.symbol == Chain(displayName: selectedSendCoin.chainName)?.gasTokenSymbol)
                ? amount >= 0 : amount > 0)
        else {
            sendPreviewStore.evmSendPreview = nil
            return
        }
        if let customEthereumNonceValidationError = customEthereumNonceValidationError {
            sendError = customEthereumNonceValidationError
            sendPreviewStore.evmSendPreview = nil
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
                        sendPreviewStore.evmSendPreview = nil
                        return
                    }
                    previewDestination = resolved
                    sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    sendPreviewStore.evmSendPreview = nil
                    return
                }
            } else {
                sendPreviewStore.evmSendPreview = nil
                return
            }
        }
        // The in-flight key is the preview *slot*, and every EVM chain shares
        // Ethereum's. Asking for the slot rather than spelling it keeps that a
        // registry fact instead of a fourth copy of it.
        let slot = SendPreviewStore.previewSlot(forChainNamed: selectedSendCoin.chainName) ?? "Ethereum"
        await withSendPreviewInFlight(slot, retry: { await self.refreshEvmSendPreview() }) {
        guard let chainId = Chain(displayName: selectedSendCoin.chainName)?.id else {
            sendPreviewStore.evmSendPreview = nil
            return
        }
        do {
            let assemblyToken: EvmSupportedToken? = supportedToken(for: selectedSendCoin).map {
                EvmSupportedToken(
                    symbol: $0.token.symbol, contractAddress: $0.token.contract,
                    decimals: $0.token.decimals)
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
                sendPreviewStore.evmSendPreview = nil
                return
            }
            let valueWei = assembly.valueWei
            let toAddress = assembly.toAddress
            let dataHex = assembly.dataHex
            sendPreviewStore.evmSendPreview = try await WalletServiceBridge.shared.fetchEvmSendPreviewTyped(
                chainId: chainId, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex,
                explicitNonce: explicitEthereumNonce().map(Int64.init),
                customFees: customEthereumFeeConfiguration()
            )
            if sendPreviewStore.evmSendPreview != nil {
                sendError = nil
                clearSendVerificationNotice()
            }
        } catch {
            if isCancelledRequest(error) { return }
            sendPreviewStore.evmSendPreview = nil
            sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }
        }
    }
    func refreshDogecoinSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Dogecoin",
            selectedSendCoin.symbol == "DOGE", let amount = parseAmountInput(text: sendAmount, maxDecimals: Chain.dogecoin.nativeDecimals), amount > 0
        else {
            sendPreviewStore.dogecoinSendPreview = nil
            return
        }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty,
            !isValidAddressForPolicy(trimmedDestination, chainName: "Dogecoin", wallet: wallet)
        {
            sendPreviewStore.dogecoinSendPreview = nil
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil else {
            sendPreviewStore.dogecoinSendPreview = nil
            return
        }
        await withSendPreviewInFlight("Dogecoin", retry: { await self.refreshDogecoinSendPreview() }) {
        guard let address = resolvedNetworkModeAddress(for: wallet, family: "dogecoin", fallback: .dogecoin) else {
            sendPreviewStore.dogecoinSendPreview = nil
            return
        }
        do {
            guard
                let preview = try await WalletServiceBridge.shared.fetchDogecoinSendPreviewTyped(
                    address: address, requestedAmount: amount,
                    feePriority: feePriorityOption(for: "Dogecoin").rawValue)
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
    }
    func refreshBitcoinSendPreview() async {
        // Bitcoin is the only chain with a stored account xpub, so core can
        // expand the HD range and price against every derived address rather
        // than the one this wallet happens to be showing. Everything around
        // that — precision, destination check, request coalescing — is the
        // same as its UTXO siblings, and used to be missing here.
        let wallet = wallet(for: sendWalletID)
        let xpub = wallet?.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines)
        await refreshUTXOChainPreview(
            chainName: "Bitcoin", chainId: Chain.bitcoin.id,
            resolveAddress: { self.resolvedNetworkModeAddress(for: $0, family: "bitcoin", fallback: .bitcoin) },
            fetch: { chainId, address in
                if let xpub, !xpub.isEmpty {
                    return try await WalletServiceBridge.shared.fetchBitcoinHdSendPreviewTyped(xpub: xpub)
                }
                return try await decodedUTXOFeePreview(
                    chainId: chainId, address: address, satPerCoin: 100_000_000)
            },
            setPreview: { self.sendPreviewStore.bitcoinSendPreview = $0 })
    }
    private func refreshUTXOChainPreview(
        chainName: String, chainId: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        adjust: @escaping (BitcoinSendPreview) -> BitcoinSendPreview = { $0 },
        fetch: (@MainActor (String, String) async throws -> BitcoinSendPreview?)? = nil,
        setPreview: @escaping (BitcoinSendPreview?) -> Void
    ) async {
        guard let chain = Chain(displayName: chainName) else { setPreview(nil); return }
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin,
            selectedSendCoin.chainName == chainName, selectedSendCoin.symbol == chain.gasTokenSymbol,
            let amount = parseAmountInput(text: sendAmount, maxDecimals: chain.nativeDecimals),
            amount > 0
        else { setPreview(nil); return }
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty,
            !isValidAddressForPolicy(trimmedDestination, chainName: chainName, wallet: wallet)
        {
            setPreview(nil)
            return
        }
        guard storedSeedPhrase(for: wallet.id) != nil, let sourceAddress = resolveAddress(wallet)
        else { setPreview(nil); return }
        await withSendPreviewInFlight(
            chainName,
            retry: { [weak self] in
                await self?.refreshUTXOChainPreview(
                    chainName: chainName, chainId: chainId, resolveAddress: resolveAddress,
                    adjust: adjust, fetch: fetch, setPreview: setPreview)
            }
        ) {
            do {
                // A chain-specific fetch may legitimately answer nil — the
                // Bitcoin HD path does when the xpub yields nothing — and that
                // clears the preview rather than showing a stale one.
                let preview: BitcoinSendPreview?
                if let fetch {
                    preview = try await fetch(chainId, sourceAddress)
                } else {
                    preview = try await decodedUTXOFeePreview(
                        chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000)
                }
                setPreview(preview.map(adjust))
                sendError = nil
            } catch {
                if isCancelledRequest(error) { return }
                setPreview(nil)
                sendError = AppLocalization.format(
                    "Unable to estimate %@ fee right now. Check provider health and retry.",
                    chain.gasTokenSymbol)
            }
        }
    }
    /// The UTXO chains without a preview path of their own.
    ///
    /// Three functions stood here — Bitcoin Cash, Bitcoin SV and Litecoin —
    /// each passing four arguments, three of which are registry facts. The
    /// fourth was Litecoin's MWEB overhead, which is a fact about the chain and
    /// lives on it now.
    func refreshUTXOSendPreview(for chain: Chain) async {
        let chainName = chain.displayName
        await refreshUTXOChainPreview(
            chainName: chainName, chainId: chain.id,
            resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
            adjust: { [self] preview in
                let overhead = Int64(
                    extraOutputOverheadBytes(chainName: chainName, destination: sendAddress))
                guard overhead > 0 else { return preview }
                let additionalFee =
                    Double(overhead) * Double(preview.estimatedFeeRateSatVb) / 100_000_000.0
                return BitcoinSendPreview(
                    estimatedFeeRateSatVb: preview.estimatedFeeRateSatVb,
                    estimatedNetworkFee: preview.estimatedNetworkFee + additionalFee,
                    feeRateDescription: preview.feeRateDescription,
                    spendableBalance: preview.spendableBalance,
                    estimatedTransactionBytes: (preview.estimatedTransactionBytes ?? 0) + overhead,
                    selectedInputCount: preview.selectedInputCount,
                    usesChangeOutput: preview.usesChangeOutput,
                    maxSendable: preview.maxSendable.map { max(0, $0 - additionalFee) }
                )
            },
            setPreview: { [self] preview in
                sendPreviewStore.apply(
                    preview.map { SendPreview.utxo(preview: $0) }, forChainNamed: chainName)
            })
    }

    func refreshTronSendPreview() async {
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin, selectedSendCoin.chainName == "Tron",
            (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"), let amount = Double(sendAmount), amount > 0
        else {
            sendPreviewStore.clearPreview(forChainNamed: "Tron")
            return
        }
        guard let sourceAddress = resolvedTronAddress(for: wallet) else {
            sendPreviewStore.clearPreview(forChainNamed: "Tron")
            return
        }
        // Tron's guard used to be `guard !contains else { return }` with no
        // `pendingSendPreviewRefreshChains.insert`, so a request arriving while
        // one was in flight was dropped rather than retried — the preview then
        // showed the fee for the previous amount. It coalesces like the other
        // two now.
        await withSendPreviewInFlight("Tron", retry: { await self.refreshTronSendPreview() }) {
            do {
                sendPreviewStore.tronSendPreview = try await WalletServiceBridge.shared.fetchTronSendPreviewTyped(
                    address: sourceAddress, symbol: selectedSendCoin.symbol,
                    contractAddress: selectedSendCoin.contractAddress ?? ""
                )
                sendError = nil
            } catch {
                if isCancelledRequest(error) { return }
                sendPreviewStore.clearPreview(forChainNamed: "Tron")
                sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
            }
        }
    }
    // Simple-chain dispatch: Rust owns per-chain defaults (fee raw parsing, priorityLabel,
    // gasBudgetMist, feeStroops, etc.). Swift just resolves address, fetches JSON, and
    // applies the tagged-enum result to the right AppState field.
    private struct SimpleChainConfig {
        let chainId: String
        let coinCheck: (AppState, Coin) async -> Bool
        let resolveAddress: (AppState, ImportedWallet) -> String?
        let chainName: String
        let applyPreview: (AppState, SimpleChainPreview?) -> Void
        let errorMessage: String
    }
    @MainActor private func refreshSimpleChain(_ cfg: SimpleChainConfig) async {
        // Every exit must leave the in-flight flag to `withSendPreviewInFlight`.
        // Clearing it by hand on an early exit releases the guard over a request
        // still on the network, and the next keystroke starts a second one
        // beside it.
        guard let wallet = wallet(for: sendWalletID), let coin = selectedSendCoin,
            await cfg.coinCheck(self, coin),
            let amount = parseAmountInput(
                text: sendAmount,
                maxDecimals: Chain(displayName: cfg.chainName)?.nativeDecimals ?? 18),
            amount > 0
        else { cfg.applyPreview(self, nil); return }
        guard let src = cfg.resolveAddress(self, wallet) else { cfg.applyPreview(self, nil); return }
        await withSendPreviewInFlight(
            cfg.chainName, retry: { [weak self] in await self?.refreshSimpleChain(cfg) }
        ) {
            do {
                let preview = try await WalletServiceBridge.shared.fetchSimpleChainSendPreviewTyped(
                    chainId: cfg.chainId, address: src)
                cfg.applyPreview(self, preview)
                sendError = nil
            } catch {
                if isCancelledRequest(error) { return }
                cfg.applyPreview(self, nil)
                sendError = cfg.errorMessage
            }
        }
    }
    /// Refresh the send preview for a chain core estimates through the shared
    /// path.
    func refreshSendPreview(forChainNamed chainName: String) async {
        // The eleven-entry `[String: SimpleChain]` table that used to gate this
        // is gone: core derives the decode shape from the chain id it is given,
        // and refuses a chain that has no shared-path preview. Which chains
        // reach here is `route_send_asset`'s answer, so a second gate could
        // only disagree with it.
        guard let chain = Chain(displayName: chainName), !chain.id.isEmpty else { return }
        let chainID = chain.id
        let symbol = chain.gasTokenSymbol
        await refreshSimpleChain(
            .init(
                chainId: chainID,
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
