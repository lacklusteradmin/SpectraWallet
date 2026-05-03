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

    private func holdingsAppliedFromSummary(_ summary: WalletSummary, to wallet: ImportedWallet) -> ImportedWallet? {
        guard !summary.holdings.isEmpty else { return nil }
        let existingKeys = wallet.holdings.map { holdingKey($0.chainName, $0.symbol, $0.contractAddress) }
        var merged = wallet.holdings
        var anyChanged = false
        for incoming in summary.holdings {
            let key = holdingKey(incoming.chainName, incoming.symbol, incoming.contractAddress)
            if let idx = existingKeys.firstIndex(of: key) {
                guard merged[idx].amount != incoming.amount else { continue }
                let old = merged[idx]
                merged[idx] = CoreCoin(
                    id: old.id, name: old.name, symbol: old.symbol,
                    coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                    tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                    amount: incoming.amount, priceUsd: old.priceUsd)
                anyChanged = true
            } else if incoming.amount > 0 {
                merged.append(CoreCoin(
                    id: UUID().uuidString,
                    name: incoming.name, symbol: incoming.symbol,
                    coinGeckoId: incoming.coinGeckoId, chainName: incoming.chainName,
                    tokenStandard: incoming.tokenStandard, contractAddress: incoming.contractAddress,
                    amount: incoming.amount, priceUsd: 0))
                anyChanged = true
            }
        }
        return anyChanged ? walletByReplacingHoldings(wallet, with: merged) : nil
    }

    private func holdingKey(_ chainName: String, _ symbol: String, _ contract: String?) -> String {
        contract.map { "\(chainName):\($0.lowercased())" } ?? "\(chainName):\(symbol)"
    }

    func updateRefreshEngineEntries() {
        let entries: [RefreshEntry] = wallets.compactMap { wallet in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain),
                let address = resolvedRefreshAddress(for: wallet)
            else { return nil }
            return RefreshEntry(chainId: chainId, walletId: wallet.id, address: address)
        }
        Task(priority: .utility) {
            try? await WalletServiceBridge.shared.setRefreshEntriesTyped(entries)
            if !entries.isEmpty {
                try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
            }
        }
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
        if wallet.selectedChain == "Bitcoin",
           let xpub = wallet.bitcoinXpub,
           !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return xpub
        }
        return resolvedAddress(for: wallet, chainName: wallet.selectedChain)
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
                tokens: enabledEVMTrackedTokens(for: .ethereum).map { TokenDescriptor(contract: $0.contractAddress, symbol: $0.symbol, decimals: UInt8($0.decimals), name: nil) }
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
