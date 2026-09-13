import Foundation

extension AppState {
    func historyPaginationExhausted(chainId: String, walletId: String) -> Bool {
        WalletServiceBridge.shared.historyCursor(chainId: chainId, walletId: walletId).isExhausted
    }
    func resetHistoryPaginationForWallet(_ walletId: String) {
        WalletServiceBridge.shared.resetHistory(.wallet(walletId: walletId))
    }
    func resetHistoryPaginationForChain(_ chainId: String) {
        WalletServiceBridge.shared.resetHistory(.chain(chainId: chainId))
    }
    func canLoadMoreHistory(for walletID: String) -> Bool {
        guard let wallet = cachedWalletByID[walletID], let chain = Chain(displayName: wallet.selectedChain) else { return false }
        return !historyPaginationExhausted(chainId: chain.id, walletId: walletID)
    }
    func canLoadMoreOnChainHistory(for walletIDs: Set<String>) -> Bool {
        !isLoadingMoreOnChainHistory && walletIDs.contains(where: canLoadMoreHistory(for:))
    }
    func loadMoreOnChainHistory(for walletIDs: Set<String>) async {
        guard !isLoadingMoreOnChainHistory, !walletIDs.isEmpty else { return }
        isLoadingMoreOnChainHistory = true
        defer { isLoadingMoreOnChainHistory = false }
        await adoptHistoryRefresh(scope: .wallets(walletIds: Array(walletIDs)), loadMore: true)
    }
    func refreshHistory(chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        await adoptHistoryRefresh(scope: .chains(chainIds: [chain.id]))
    }
    func runHistoryRefreshes(interval: TimeInterval) async {
        await adoptHistoryRefresh(scope: .all, interval: interval)
    }
    func runPendingTransactionHistoryRefreshes(for chains: Set<WalletChainID>, interval: TimeInterval) async {
        await adoptHistoryRefresh(scope: .chains(chainIds: chains.map(\.rawValue)), interval: interval)
    }
    private func adoptHistoryRefresh(scope: HistoryRefreshScope, loadMore: Bool = false, interval: TimeInterval = 0) async {
        do {
            let results = try await WalletServiceBridge.shared.refreshHistory(scope: scope, loadMore: loadMore, interval: interval)
            var changed = false
            for result in results {
                guard let chain = Chain(id: result.chainId) else { continue }
                let name = chain.displayName
                guard let outcome = result.outcome else {
                    markChainDegraded(name, detail: result.error ?? "History refresh failed.")
                    continue
                }
                changed = changed || outcome.added > 0 || outcome.updated > 0
                for row in outcome.diagnostics {
                    recordHistoryDiagnostics(chainName: name, HistoryDiagnostics(
                        walletId: row.walletId, identifier: row.identifier, sourceUsed: row.sourceUsed,
                        transactionCount: Int32(clamping: row.transactionCount), scannedCount: nil,
                        nextCursor: row.nextCursor, error: row.error, perSource: []))
                }
                if !outcome.diagnostics.isEmpty { self[historyRunFor: name].lastUpdatedAt = Date() }
                if outcome.walletsFailed > 0 {
                    markChainDegraded(name, detail: AppLocalization.format(
                        outcome.walletsRefreshed == 0 ? "%@ history refresh failed. Using cached history." : "%@ history loaded with partial provider failures.", name))
                } else if outcome.walletsRefreshed > 0 { markChainHealthy(name) }
            }
            if changed { await refreshTransactionProjection() }
        } catch {
            appendOperationalLog(.error, category: "History", message: String(describing: error))
        }
    }
    func performUserInitiatedRefresh(forChain chainName: String) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if appIsActive { await refreshPendingTransactions(includeHistoryRefreshes: false) }
        await withBalanceRefreshWindow {
            await refreshBalances()
            await refreshHistory(chainName: chainName)
        }
        await refreshLivePrices()
        await refreshFiatExchangeRatesIfNeeded()
        recordPerformanceSample("user_refresh_chain", startedAt: startedAt, metadata: chainName)
    }
}
