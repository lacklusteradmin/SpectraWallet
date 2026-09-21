import Foundation

extension AppState {
    func historyPaginationExhausted(chainId: String, walletId: String) -> Bool {
        self.bridge.historyCursor(chainId: chainId, walletId: walletId).isExhausted
    }
    func canLoadMoreHistory(for walletId: String) -> Bool {
        guard let wallet = cachedWalletById[walletId], let chain = Chain(displayName: wallet.familyName) else { return false }
        return !historyPaginationExhausted(chainId: chain.id, walletId: walletId)
    }
    func canLoadMoreOnChainHistory(for walletIds: Set<String>) -> Bool {
        !isLoadingMoreOnChainHistory && walletIds.contains(where: canLoadMoreHistory(for:))
    }
    func loadMoreOnChainHistory(for walletIds: Set<String>) async {
        guard !isLoadingMoreOnChainHistory, !walletIds.isEmpty else { return }
        isLoadingMoreOnChainHistory = true
        defer { isLoadingMoreOnChainHistory = false }
        await adoptHistoryRefresh(scope: .wallets(walletIds: Array(walletIds)), loadMore: true)
    }
    func refreshHistory(chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        await adoptHistoryRefresh(scope: .chains(chainIds: [chain.id]))
    }
    /// Run a history refresh and adopt what it changed.
    ///
    /// Core records the run's diagnostics rows and the chain's health itself.
    /// This copied each row back through an export and decided degraded or
    /// healthy from the outcome, on the two paths it drove and not on the
    /// scheduled refresh.
    private func adoptHistoryRefresh(scope: HistoryRefreshScope, loadMore: Bool = false, interval: TimeInterval = 0) async {
        do {
            let results = try await self.bridge.refreshHistory(scope: scope, loadMore: loadMore, interval: interval)
            for result in results {
                guard let chain = Chain(id: result.chainId), result.outcome?.diagnostics.isEmpty == false else { continue }
                self[historyRunFor: chain.displayName].lastUpdatedAt = Date()
            }
            chainDiagnosticsState.diagnosticsRevision &+= 1
            await diagnostics.loadFromSQLite()
            if results.contains(where: { ($0.outcome?.added ?? 0) > 0 || ($0.outcome?.updated ?? 0) > 0 }) {
                await refreshTransactionProjection()
            }
        } catch {
            appendOperationalLog(.error, category: "History", message: String(describing: error))
        }
    }
    @discardableResult
    func performUserInitiatedRefresh(forChain chainName: String) async -> Bool {
        guard let chain = Chain(displayName: chainName) else { return false }
        return await performCoreRefresh(.chain(chainId: chain.id))
    }
}
