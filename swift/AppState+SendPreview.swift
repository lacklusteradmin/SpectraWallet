import Foundation

// MARK: - Private pure helpers (no store state)

private func decodedUTXOFeePreview(
    chainId: String, address: String, satPerCoin: Double, feeRateSvb: UInt64 = 0,
    destination: String = ""
) async throws -> BitcoinSendPreview {
    guard
        let preview = try await WalletServiceBridge.shared.fetchUtxoFeePreviewTyped(
            chainId: chainId, address: address, feeRateSvb: feeRateSvb,
            destinationAddress: destination)
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
        guard let selectedSendCoin, isEVMChain(selectedSendCoin.chainName), !sendWalletID.isEmpty else {
            sendPreviewStore.evmSendPreview = nil
            return
        }
        let slot = SendPreviewStore.previewSlot(forChainNamed: selectedSendCoin.chainName) ?? "Ethereum"
        await withSendPreviewInFlight(slot, retry: { [weak self] in await self?.refreshEvmSendPreview() }) {
        let walletID = sendWalletID
        let amount = sendPreviewAmountInput
        let destination = sendAddress
        do {
            let preview = try await WalletServiceBridge.shared.previewOwnedEvmSend(
                walletID: walletID, holdingKey: selectedSendCoin.holdingKey,
                amount: amount, destination: destination,
                explicitNonce: try explicitEvmNonce().map(Int64.init), customFees: customEvmFeeConfiguration())
            guard sendWalletID == walletID, sendPreviewAmountInput == amount, sendAddress == destination, self.selectedSendCoin?.holdingKey == selectedSendCoin.holdingKey else { return }
            sendPreviewStore.evmSendPreview = preview
            if preview != nil {
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
            selectedSendCoin.symbol == "DOGE", let amount = parseAmountInput(text: sendPreviewAmountInput, maxDecimals: Chain.dogecoin.nativeDecimals), amount > 0
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
        await withSendPreviewInFlight("Dogecoin", retry: { [weak self] in await self?.refreshDogecoinSendPreview() }) {
        guard let address = resolvedAddress(for: wallet, chainName: "Dogecoin") else {
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
            chainName: "Bitcoin",
            resolveAddress: { self.resolvedAddress(for: $0, chainName: "Bitcoin") },
            fetch: { chainId, address in
                if let xpub, !xpub.isEmpty {
                    return try await WalletServiceBridge.shared.fetchBitcoinHdSendPreviewTyped(
                        chainId: chainId, xpub: xpub)
                }
                return try await decodedUTXOFeePreview(
                    chainId: chainId, address: address, satPerCoin: 100_000_000)
            },
            setPreview: { self.sendPreviewStore.bitcoinSendPreview = $0 })
    }
    /// The preview is priced on the network the wallet is on.
    ///
    /// The chain id used to come in from the caller as the family's mainnet,
    /// which cost only a wrong fee estimate while a send signed for mainnet
    /// too. Now that `execute_send` follows `WalletSummary::network_chain`, a
    /// testnet send would have been priced — and its spendable balance read —
    /// against mainnet. One rule, resolved from the wallet this is previewing.
    private func refreshUTXOChainPreview(
        chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        fetch: (@MainActor (String, String) async throws -> BitcoinSendPreview?)? = nil,
        setPreview: @escaping (BitcoinSendPreview?) -> Void
    ) async {
        guard let chain = Chain(displayName: chainName) else { setPreview(nil); return }
        guard let wallet = wallet(for: sendWalletID), let selectedSendCoin = selectedSendCoin,
            selectedSendCoin.chainName == chainName, selectedSendCoin.symbol == chain.gasTokenSymbol,
            let amount = parseAmountInput(text: sendPreviewAmountInput, maxDecimals: chain.nativeDecimals),
            amount > 0
        else { setPreview(nil); return }
        let chainId = walletNetworkChainID(for: wallet, family: chain.mainnetCounterpart.id)
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty,
            !isValidAddressForPolicy(trimmedDestination, chainName: chainName, wallet: wallet)
        {
            setPreview(nil)
            return
        }
        guard let sourceAddress = resolveAddress(wallet)
        else { setPreview(nil); return }
        await withSendPreviewInFlight(
            chainName,
            retry: { [weak self] in
                await self?.refreshUTXOChainPreview(
                    chainName: chainName, resolveAddress: resolveAddress,
                    fetch: fetch, setPreview: setPreview)
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
                        chainId: chainId, address: sourceAddress, satPerCoin: 100_000_000,
                        destination: trimmedDestination)
                }
                setPreview(preview)
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
            chainName: chainName,
            resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
            // An extra output's bytes — Litecoin's MWEB peg-in is the one the
            // registry names — are priced by the preview core builds. The
            // arithmetic used to be here, beside a registry fact fetched to do
            // it, and had no test.
            setPreview: { [self] preview in
                sendPreviewStore.apply(
                    preview.map { SendPreview.utxo(preview: $0) }, forChainNamed: chainName)
            })
    }

    func refreshTronSendPreview() async {
        // Which Tron assets have a preview is `route_send_asset`'s answer, the
        // same one the submit path takes. It was `TRX || USDT` written out
        // here — a third copy of that rule, and the one that would keep
        // refusing if core's router were widened.
        let routedToTron = await WalletServiceBridge.shared.sendAssetRouting(
            walletID: sendWalletID, holdingKey: sendHoldingKey)?.previewKind == "tron"
        guard routedToTron, let wallet = wallet(for: sendWalletID),
            let selectedSendCoin = selectedSendCoin,
            let amount = Double(sendPreviewAmountInput), amount > 0
        else {
            sendPreviewStore.clearPreview(forChainNamed: "Tron")
            return
        }
        guard let sourceAddress = resolvedAddress(for: wallet, chainName: "Tron") else {
            sendPreviewStore.clearPreview(forChainNamed: "Tron")
            return
        }
        // Tron's guard used to be `guard !contains else { return }` with no
        // `pendingSendPreviewRefreshChains.insert`, so a request arriving while
        // one was in flight was dropped rather than retried — the preview then
        // showed the fee for the previous amount. It coalesces like the other
        // two now.
        await withSendPreviewInFlight("Tron", retry: { [weak self] in await self?.refreshTronSendPreview() }) {
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
                text: sendPreviewAmountInput,
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
