import Foundation

extension AppState {
    /// Core names the wallets with history left to fetch in its snapshot.
    func canLoadMoreOnChainHistory(for walletIds: Set<String>) -> Bool {
        !isLoadingMoreOnChainHistory && !walletIds.isDisjoint(with: walletsWithMoreHistory)
    }
    func loadMoreOnChainHistory(for walletIds: Set<String>) async {
        guard !isLoadingMoreOnChainHistory, !walletIds.isEmpty else { return }
        isLoadingMoreOnChainHistory = true
        defer { isLoadingMoreOnChainHistory = false }
        await adoptHistoryRefresh(scope: .wallets(walletIds: Array(walletIds)), loadMore: true)
    }
    func refreshHistory(chain: Chain) async {
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
            let results = try await self.bridge.ready().refreshHistory(
                scope: scope, loadMore: loadMore, limit: nil, intervalSecs: interval)
            for result in results {
                guard let chain = Chain(id: result.chainId), result.outcome?.diagnostics.isEmpty == false else { continue }
                self[historyRunFor: chain].lastUpdatedAt = Date()
            }
            chainDiagnosticsState.diagnosticsRevision &+= 1
            await diagnostics.loadFromSQLite()
            // Loading more always moves a cursor, even when every page was already stored.
            if loadMore || results.contains(where: { ($0.outcome?.added ?? 0) > 0 || ($0.outcome?.updated ?? 0) > 0 }) {
                await refreshTransactionProjection()
            }
        } catch {
            appendOperationalLog(.error, category: "History", message: String(describing: error))
        }
    }
    @discardableResult
    func performUserInitiatedRefresh(forChain chainId: String) async -> Bool {
        await performCoreRefresh(.chain(chainId: chainId))
    }
}
