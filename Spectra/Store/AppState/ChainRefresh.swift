import Foundation

extension WalletStore {
    func runPlannedChainRefreshes(
        using refreshPlanByChain: [WalletChainID: Bool],
        timeout: Double
    ) async {
        for descriptor in plannedChainRefreshDescriptors {
            guard let refreshHistory = refreshPlanByChain[descriptor.chainID] else { continue }
            await runTimedChainRefresh(
                descriptor.chainID,
                refreshHistory: refreshHistory,
                timeout: timeout
            ) {
                await descriptor.executeRefresh(self, refreshHistory)
            }
        }
    }

    func refreshImportedWalletBalances(forChains chainNames: Set<String>) async {
        for descriptor in importedWalletRefreshDescriptors where chainNames.contains(descriptor.chainName) {
            await descriptor.executeBalancesOnly(self)
        }
    }

    func runHistoryRefreshes(
        for trackedChains: Set<WalletChainID>,
        interval: TimeInterval
    ) async {
        let plannedHistoryChains = Set(
            WalletRefreshPlanner.historyPlans(
                for: trackedChains,
                now: Date(),
                interval: interval,
                lastHistoryRefreshAtByChainID: lastHistoryRefreshAtByChainID
            )
        )
        guard !plannedHistoryChains.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for descriptor in plannedChainRefreshDescriptors {
                guard plannedHistoryChains.contains(descriptor.chainID),
                      let executeHistoryOnly = descriptor.executeHistoryOnly else {
                    continue
                }
                group.addTask {
                    await executeHistoryOnly(self)
                }
            }
            await group.waitForAll()
        }
    }

    func runPendingTransactionHistoryRefreshes(
        for trackedChains: Set<WalletChainID>,
        interval: TimeInterval
    ) async {
        await runHistoryRefreshes(for: trackedChains, interval: interval)
    }

    private func runTimedChainRefresh(
        _ chainID: WalletChainID,
        refreshHistory: Bool,
        timeout: Double,
        operation: @escaping () async -> Void
    ) async {
        let chainName = chainID.displayName
        do {
            try await withTimeout(seconds: timeout) {
                await operation()
                return ()
            }
            if refreshHistory {
                lastHistoryRefreshAtByChainID[chainID] = Date()
            }
        } catch {
            markChainDegraded(chainName, detail: "\(chainName) refresh timed out. Using cached balances and history.")
            appendOperationalLog(
                .warning,
                category: "Chain Sync",
                message: "\(chainName) refresh timeout",
                chainName: chainName,
                source: "timeout",
                metadata: error.localizedDescription
            )
        }
    }
}
