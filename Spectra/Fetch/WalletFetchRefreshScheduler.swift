import Foundation

extension WalletFetchLayer {
    static func refreshChainBalances(
        using store: WalletStore,
        includeHistoryRefreshes: Bool = true,
        historyRefreshInterval: TimeInterval = 120,
        forceChainRefresh: Bool = true
    ) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        guard !store.isRefreshingChainBalances else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        store.isRefreshingChainBalances = true
        store.suppressWalletSideEffects = true
        defer {
            store.suppressWalletSideEffects = false
            store.applyWalletCollectionSideEffects()
            store.isRefreshingChainBalances = false
            store.lastChainBalanceRefreshAt = Date()
            store.recordPerformanceSample(
                "refresh_chain_balances",
                startedAt: startedAt,
                metadata: "include_history=\(includeHistoryRefreshes) force=\(forceChainRefresh)"
            )
        }

        let chainRefreshTimeout: Double = 35
        let chainIDs = store.refreshableChainIDs
        guard !chainIDs.isEmpty else { return }
        let refreshPlanByChain = Dictionary(
            uniqueKeysWithValues: WalletRefreshPlanner.chainPlans(
                for: chainIDs,
                now: Date(),
                forceChainRefresh: forceChainRefresh,
                includeHistoryRefreshes: includeHistoryRefreshes,
                historyRefreshInterval: historyRefreshInterval,
                pendingTransactionMaintenanceChains: store.pendingTransactionMaintenanceChainIDs,
                degradedChains: Set(store.chainDegradedMessagesByChainID.keys),
                lastGoodChainSyncByID: store.lastGoodChainSyncByChainID,
                lastHistoryRefreshAtByChainID: Dictionary(
                    uniqueKeysWithValues: store.lastHistoryRefreshAtByChain.compactMap { key, value in
                        WalletChainID(key).map { ($0, value) }
                    }
                ),
                automaticChainRefreshStalenessInterval: WalletStore.automaticChainRefreshStalenessInterval
            ).map { ($0.chainID, $0.refreshHistory) }
        )
        guard !refreshPlanByChain.isEmpty else { return }

        await store.runPlannedChainRefreshes(
            using: refreshPlanByChain,
            timeout: chainRefreshTimeout
        )
    }
}
