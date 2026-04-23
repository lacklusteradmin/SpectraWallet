import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Called by the Rust balance refresh engine after each successful balance
    /// fetch. Accumulates updates and flushes them as a single wallets mutation
    /// after a short debounce so a burst of 50+ callbacks produces one SwiftUI
    /// re-render. `pendingBalanceUpdates` + `balanceFlushTask` are instance
    /// properties on AppState (not static) so they're released when the
    /// AppState is; the prior `static var` held WalletSummary values and a
    /// scheduled Task process-wide, keeping memory around across AppState
    /// lifecycles (previews, lock/unlock reinit).
    func applyRustBalance(walletId: String, summary: WalletSummary) {
        pendingBalanceUpdates.append(PendingBalanceUpdate(walletId: walletId, summary: summary))
        balanceFlushTask?.cancel()
        balanceFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
            guard !Task.isCancelled, let self else { return }
            let batch = self.pendingBalanceUpdates
            self.pendingBalanceUpdates = []
            guard !batch.isEmpty else { return }
            self.flushBalanceBatch(batch)
        }
    }

    private func flushBalanceBatch(_ batch: [PendingBalanceUpdate]) {
        var walletsCopy = wallets
        let walletIndexById = Dictionary(uniqueKeysWithValues: walletsCopy.enumerated().map { ($1.id, $0) })
        var anyChanged = false
        for update in batch {
            guard let idx = walletIndexById[update.walletId] else { continue }
            if let updated = holdingsAppliedFromSummary(update.summary, to: walletsCopy[idx]) {
                walletsCopy[idx] = updated
                anyChanged = true
            }
        }
        if anyChanged { wallets = walletsCopy }
    }

    /// Decode the `holdings` array from a WalletSummary JSON blob and apply
    /// their amounts to `wallet`. Visual properties (color, priceUsd) are
    /// preserved from the existing Coin if found; new holdings get defaults.
    /// Returns `nil` if the JSON could not be parsed.
    private func holdingsAppliedFromSummary(_ summary: WalletSummary, to wallet: ImportedWallet) -> ImportedWallet? {
        let existing = wallet.holdings.map {
            HoldingMergeExistingInput(symbol: $0.symbol, chainName: $0.chainName, contractAddress: $0.contractAddress)
        }
        let incoming = summary.holdings.map {
            HoldingMergeIncomingInput(
                name: $0.name, symbol: $0.symbol, marketDataId: $0.marketDataId, coinGeckoId: $0.coinGeckoId,
                chainName: $0.chainName, tokenStandard: $0.tokenStandard, contractAddress: $0.contractAddress,
                amount: $0.amount
            )
        }
        let actions = corePlanApplyHoldingsFromSummary(existing: existing, incoming: incoming)
        guard !actions.isEmpty else { return nil }
        var merged = wallet.holdings
        for action in actions {
            switch action {
            case .updateAmount(let existingIndex, let amount):
                let idx = Int(existingIndex)
                guard merged.indices.contains(idx) else { continue }
                let old = merged[idx]
                merged[idx] = CoreCoin(
                    id: old.id, name: old.name, symbol: old.symbol, marketDataId: old.marketDataId,
                    coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                    tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                    amount: amount, priceUsd: old.priceUsd)
            case .append(let coin):
                merged.append(
                    CoreCoin(
                        id: UUID().uuidString,
                        name: coin.name, symbol: coin.symbol, marketDataId: coin.marketDataId,
                        coinGeckoId: coin.coinGeckoId, chainName: coin.chainName,
                        tokenStandard: coin.tokenStandard, contractAddress: coin.contractAddress,
                        amount: coin.amount, priceUsd: 0))
            }
        }
        return walletByReplacingHoldings(wallet, with: merged)
    }

    func updateRefreshEngineEntries() {
        let entries: [RefreshEntry] = wallets.compactMap { wallet in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain),
                let address = resolvedRefreshAddress(for: wallet)
            else { return nil }
            return RefreshEntry(chainId: chainId, walletId: wallet.id, address: address)
        }
        Task { try? await WalletServiceBridge.shared.setRefreshEntriesTyped(entries) }
    }

    /// Install the Rust balance-refresh observer and start the periodic
    /// refresh loop. Interval is driven by the user's
    /// `automaticRefreshFrequencyMinutes` preference (default 5 min) — NOT a
    /// hardcoded 30 s, which was firing at 10× the requested rate and
    /// keeping the phone warm with constant radio activity.
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver(noPointer: .init())
        observer.store = self
        Task { [weak self] in
            try? await WalletServiceBridge.shared.setBalanceObserver(observer)
            await self?.restartBalanceRefreshForCurrentConfiguration()
        }
        updateRefreshEngineEntries()
    }
    /// Stop-then-start the refresh engine using the current effective
    /// interval. Called when the refresh-frequency preference changes or
    /// when the app transitions active/inactive — contexts where we want
    /// the interval value or the running state to actually change.
    func restartBalanceRefreshForCurrentConfiguration() async {
        try? await WalletServiceBridge.shared.stopBalanceRefresh()
        guard appIsActive else { return }
        // No wallets = no entries to refresh. Keeping the tokio interval
        // alive just to wake every N minutes and no-op is pure idle heat,
        // so don't start it at all until the user imports a wallet.
        // `applyWalletCollectionSideEffects` calls
        // `startBalanceRefreshIfNeeded` when wallets change.
        guard !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

    /// Idempotent start path used after wallet mutations. Skips work when
    /// the app is inactive or there are no wallets, and relies on the
    /// Rust engine's own "already running" guard to make repeat calls
    /// cheap instead of stopping + restarting each time.
    func startBalanceRefreshIfNeeded() async {
        guard appIsActive, !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

    private func resolvedRefreshAddress(for wallet: ImportedWallet) -> String? {
        switch wallet.selectedChain {
        case "Bitcoin":
            if let xpub = wallet.bitcoinXpub, !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return xpub }
            return resolvedBitcoinAddress(for: wallet)
        case "Ethereum", "Arbitrum", "Optimism", "Avalanche", "BNB Chain", "Hyperliquid", "Ethereum Classic", "Base":
            return resolvedEVMAddress(for: wallet, chainName: wallet.selectedChain)
        case "Solana": return resolvedSolanaAddress(for: wallet)
        case "Tron": return resolvedTronAddress(for: wallet)
        case "Sui": return resolvedSuiAddress(for: wallet)
        case "Aptos": return resolvedAptosAddress(for: wallet)
        case "TON": return resolvedTONAddress(for: wallet)
        case "ICP": return resolvedICPAddress(for: wallet)
        case "NEAR": return resolvedNearAddress(for: wallet)
        case "XRP Ledger": return resolvedXRPAddress(for: wallet)
        case "Stellar": return resolvedStellarAddress(for: wallet)
        case "Cardano": return resolvedCardanoAddress(for: wallet)
        case "Polkadot": return resolvedPolkadotAddress(for: wallet)
        case "Monero": return resolvedMoneroAddress(for: wallet)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV": return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin": return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin": return resolvedDogecoinAddress(for: wallet)
        default: return nil
        }
    }

    // EVM helpers kept because they're still called from SendFlow / DiagnosticsEndpoints.
    func configuredEthereumRPCEndpointURL() -> URL? {
        guard ethereumRPCEndpointValidationError == nil else { return nil }
        let trimmed = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [TokenBalanceResult]) {
        let ethereumContext = evmChainContext(for: "Ethereum") ?? .ethereum
        let summary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: SpectraChainID.ethereum, address: address)
        let nativeBalance = Double(summary.amountDisplay) ?? 0
        let tokenBalances =
            ethereumContext.isEthereumMainnet
            ? ((try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                chainId: SpectraChainID.ethereum, address: address,
                tokens: enabledEthereumTrackedTokens().map { TokenDescriptor(contract: $0.contractAddress, symbol: $0.symbol, decimals: UInt8($0.decimals), name: nil) }
            )) ?? [])
            : []
        return (nativeBalance, tokenBalances)
    }
    func refreshPendingEVMTransactions(chainName: String) async {
        let now = Date()
        guard let chainId = SpectraChainID.id(for: chainName) else { return }
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }
        guard !pendingTransactions.isEmpty else { return }
        var resolvedClassifications: [UUID: (TransactionStatus, EvmReceiptClassification)] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                guard
                    let classified = try await WalletServiceBridge.shared.fetchEvmReceiptClassification(
                        chainId: chainId, txHash: transactionHash
                    )
                else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                    continue
                }
                if classified.isConfirmed {
                    let resolvedStatus: TransactionStatus = classified.isFailed ? .failed : .confirmed
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                    resolvedClassifications[transaction.id] = (resolvedStatus, classified)
                } else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                }
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let resolvedStatuses = resolvedClassifications.mapValues { resolvedStatus, classified in
            PendingTransactionStatusResolution(
                status: resolvedStatus, receiptBlockNumber: classified.blockNumber.map(Int.init), confirmations: nil,
                dogecoinNetworkFeeDoge: nil
            )
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }
}
