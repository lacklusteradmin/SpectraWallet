import Foundation

struct WalletRefreshChainPlan: Hashable {
    let chainID: WalletChainID
    let refreshHistory: Bool

    var chainName: String { chainID.displayName }
}

struct WalletActiveMaintenancePlan {
    let refreshPendingTransactions: Bool
    let refreshLivePrices: Bool
}

struct WalletRefreshPlanner {
    static func activeMaintenancePlan(
        now: Date,
        lastPendingTransactionRefreshAt: Date?,
        lastLivePriceRefreshAt: Date?,
        hasPendingTransactionMaintenanceWork: Bool,
        shouldRunScheduledPriceRefresh: Bool,
        pendingRefreshInterval: TimeInterval,
        priceRefreshInterval: TimeInterval
    ) -> WalletActiveMaintenancePlan {
        let shouldRefreshPendingTransactions: Bool
        if let lastPendingTransactionRefreshAt {
            shouldRefreshPendingTransactions =
                hasPendingTransactionMaintenanceWork &&
                now.timeIntervalSince(lastPendingTransactionRefreshAt) >= pendingRefreshInterval
        } else {
            shouldRefreshPendingTransactions = hasPendingTransactionMaintenanceWork
        }

        let shouldRefreshLivePrices: Bool
        if let lastLivePriceRefreshAt {
            shouldRefreshLivePrices =
                shouldRunScheduledPriceRefresh &&
                now.timeIntervalSince(lastLivePriceRefreshAt) >= priceRefreshInterval
        } else {
            shouldRefreshLivePrices = shouldRunScheduledPriceRefresh
        }

        return WalletActiveMaintenancePlan(
            refreshPendingTransactions: shouldRefreshPendingTransactions,
            refreshLivePrices: shouldRefreshLivePrices
        )
    }

    static func shouldRunBackgroundMaintenance(
        now: Date,
        isNetworkReachable: Bool,
        lastBackgroundMaintenanceAt: Date?,
        interval: TimeInterval
    ) -> Bool {
        guard isNetworkReachable else { return false }
        guard let lastBackgroundMaintenanceAt else { return true }
        return now.timeIntervalSince(lastBackgroundMaintenanceAt) >= interval
    }

    static func chainPlans(
        for chainIDs: Set<WalletChainID>,
        now: Date,
        forceChainRefresh: Bool,
        includeHistoryRefreshes: Bool,
        historyRefreshInterval: TimeInterval,
        pendingTransactionMaintenanceChains: Set<WalletChainID>,
        degradedChains: Set<WalletChainID>,
        lastGoodChainSyncByID: [WalletChainID: Date],
        lastHistoryRefreshAtByChainID: [WalletChainID: Date],
        automaticChainRefreshStalenessInterval: TimeInterval
    ) -> [WalletRefreshChainPlan] {
        chainIDs
            .sorted()
            .compactMap { chainID in
                guard shouldRefreshChainData(
                    chainID,
                    now: now,
                    force: forceChainRefresh,
                    pendingTransactionMaintenanceChains: pendingTransactionMaintenanceChains,
                    degradedChains: degradedChains,
                    lastGoodChainSyncByID: lastGoodChainSyncByID,
                    automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
                ) else {
                    return nil
                }

                let refreshHistory = includeHistoryRefreshes && shouldRefreshOnChainHistory(
                    for: chainID,
                    now: now,
                    interval: historyRefreshInterval,
                    lastHistoryRefreshAtByChainID: lastHistoryRefreshAtByChainID
                )
                return WalletRefreshChainPlan(chainID: chainID, refreshHistory: refreshHistory)
            }
    }

    static func historyPlans(
        for chainIDs: Set<WalletChainID>,
        now: Date,
        interval: TimeInterval,
        lastHistoryRefreshAtByChainID: [WalletChainID: Date]
    ) -> [WalletChainID] {
        chainIDs
            .sorted()
            .filter {
                shouldRefreshOnChainHistory(
                    for: $0,
                    now: now,
                    interval: interval,
                    lastHistoryRefreshAtByChainID: lastHistoryRefreshAtByChainID
                )
            }
    }

    private static func shouldRefreshChainData(
        _ chainID: WalletChainID,
        now: Date,
        force: Bool,
        pendingTransactionMaintenanceChains: Set<WalletChainID>,
        degradedChains: Set<WalletChainID>,
        lastGoodChainSyncByID: [WalletChainID: Date],
        automaticChainRefreshStalenessInterval: TimeInterval
    ) -> Bool {
        if force {
            return true
        }
        if pendingTransactionMaintenanceChains.contains(chainID) {
            return true
        }
        if degradedChains.contains(chainID) {
            return true
        }
        guard let lastGoodSyncAt = lastGoodChainSyncByID[chainID] else {
            return true
        }
        return now.timeIntervalSince(lastGoodSyncAt) >= automaticChainRefreshStalenessInterval
    }

    private static func shouldRefreshOnChainHistory(
        for chainID: WalletChainID,
        now: Date,
        interval: TimeInterval,
        lastHistoryRefreshAtByChainID: [WalletChainID: Date]
    ) -> Bool {
        guard let lastRefreshAt = lastHistoryRefreshAtByChainID[chainID] else {
            return true
        }
        return now.timeIntervalSince(lastRefreshAt) >= interval
    }
}
