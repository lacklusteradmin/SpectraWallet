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
        do {
            let plan = try WalletRustAppCoreBridge.activeMaintenancePlan(
                WalletRustActiveMaintenancePlanRequest(
                    nowUnix: now.timeIntervalSince1970,
                    lastPendingTransactionRefreshAtUnix: lastPendingTransactionRefreshAt?.timeIntervalSince1970,
                    lastLivePriceRefreshAtUnix: lastLivePriceRefreshAt?.timeIntervalSince1970,
                    hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
                    shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh,
                    pendingRefreshInterval: pendingRefreshInterval,
                    priceRefreshInterval: priceRefreshInterval
                )
            )
            return WalletActiveMaintenancePlan(
                refreshPendingTransactions: plan.refreshPendingTransactions,
                refreshLivePrices: plan.refreshLivePrices
            )
        } catch {
            let refreshPendingTransactions: Bool
            if let lastPendingTransactionRefreshAt {
                refreshPendingTransactions =
                    hasPendingTransactionMaintenanceWork &&
                    now.timeIntervalSince(lastPendingTransactionRefreshAt) >= pendingRefreshInterval
            } else {
                refreshPendingTransactions = hasPendingTransactionMaintenanceWork
            }

            let refreshLivePrices: Bool
            if let lastLivePriceRefreshAt {
                refreshLivePrices =
                    shouldRunScheduledPriceRefresh &&
                    now.timeIntervalSince(lastLivePriceRefreshAt) >= priceRefreshInterval
            } else {
                refreshLivePrices = shouldRunScheduledPriceRefresh
            }

            return WalletActiveMaintenancePlan(
                refreshPendingTransactions: refreshPendingTransactions,
                refreshLivePrices: refreshLivePrices
            )
        }
    }

    static func shouldRunBackgroundMaintenance(
        now: Date,
        isNetworkReachable: Bool,
        lastBackgroundMaintenanceAt: Date?,
        interval: TimeInterval
    ) -> Bool {
        do {
            return try WalletRustAppCoreBridge.shouldRunBackgroundMaintenance(
                WalletRustBackgroundMaintenanceRequest(
                    nowUnix: now.timeIntervalSince1970,
                    isNetworkReachable: isNetworkReachable,
                    lastBackgroundMaintenanceAtUnix: lastBackgroundMaintenanceAt?.timeIntervalSince1970,
                    interval: interval
                )
            )
        } catch {
            guard isNetworkReachable else { return false }
            guard let lastBackgroundMaintenanceAt else { return true }
            return now.timeIntervalSince(lastBackgroundMaintenanceAt) >= interval
        }
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
        do {
            let plans = try WalletRustAppCoreBridge.chainRefreshPlans(
                WalletRustChainRefreshPlanRequest(
                    chainIDs: chainIDs.map(\.rawValue),
                    nowUnix: now.timeIntervalSince1970,
                    forceChainRefresh: forceChainRefresh,
                    includeHistoryRefreshes: includeHistoryRefreshes,
                    historyRefreshInterval: historyRefreshInterval,
                    pendingTransactionMaintenanceChainIDs: pendingTransactionMaintenanceChains.map(\.rawValue),
                    degradedChainIDs: degradedChains.map(\.rawValue),
                    lastGoodChainSyncByID: Dictionary(uniqueKeysWithValues: lastGoodChainSyncByID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }),
                    lastHistoryRefreshAtByChainID: Dictionary(uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }),
                    automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
                )
            )
            return plans.compactMap { plan in
                guard let chainID = WalletChainID(plan.chainID) else { return nil }
                return WalletRefreshChainPlan(chainID: chainID, refreshHistory: plan.refreshHistory)
            }
        } catch {
            return chainIDs
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
    }

    static func historyPlans(
        for chainIDs: Set<WalletChainID>,
        now: Date,
        interval: TimeInterval,
        lastHistoryRefreshAtByChainID: [WalletChainID: Date]
    ) -> [WalletChainID] {
        do {
            let chainIDs = try WalletRustAppCoreBridge.historyRefreshPlans(
                WalletRustHistoryRefreshPlanRequest(
                    chainIDs: chainIDs.map(\.rawValue),
                    nowUnix: now.timeIntervalSince1970,
                    interval: interval,
                    lastHistoryRefreshAtByChainID: Dictionary(uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
                )
            )
            return chainIDs.compactMap(WalletChainID.init)
        } catch {
            return chainIDs
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
