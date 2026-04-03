import Foundation
import os

extension WalletStore {
    // Lightweight maintenance entry for inactive/app background periods.
    func performBackgroundMaintenanceTick() async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("Running background maintenance tick")
        await refreshPendingTransactions(includeHistoryRefreshes: false, historyRefreshInterval: 300)
        if appIsActive {
            if shouldRunScheduledPriceRefresh {
                await refreshLivePrices()
            }
            await refreshFiatExchangeRatesIfNeeded()
            recordPerformanceSample(
                "background_maintenance_tick",
                startedAt: startedAt,
                metadata: "mode=active"
            )
            return
        }

        guard canRunHeavyBackgroundRefresh() else { return }
        let previousTotal = lastObservedPortfolioTotalUSD ?? totalBalance
        await withBalanceRefreshWindow {
            await refreshChainBalances(
                includeHistoryRefreshes: false,
                historyRefreshInterval: 300,
                forceChainRefresh: false
            )
        }
        await runHistoryRefreshes(for: refreshableChainIDs, interval: 300)
        let didRefreshPrices = shouldRunScheduledPriceRefresh ? await refreshLivePrices() : false
        await refreshFiatExchangeRatesIfNeeded()
        let currentTotal = totalBalance
        if didRefreshPrices || currentTotal != previousTotal {
            maybeSendLargeMovementNotification(previousTotalUSD: previousTotal, currentTotalUSD: currentTotal)
            lastObservedPortfolioTotalUSD = currentTotal
        }
        lastFullRefreshAt = Date()
        recordPerformanceSample(
            "background_maintenance_tick",
            startedAt: startedAt,
            metadata: "mode=background chains=\(refreshableChainIDs.count)"
        )
    }

    // Pull-to-refresh orchestration for the whole app.
    func performUserInitiatedRefresh(forceChainRefresh: Bool = true) async {
        if let existingRefreshTask = userInitiatedRefreshTask {
            await existingRefreshTask.value
            return
        }

        let refreshTask = Task { @MainActor in
            let startedAt = CFAbsoluteTimeGetCurrent()
            isUserInitiatedRefreshInProgress = true
            defer {
                isUserInitiatedRefreshInProgress = false
                recordPerformanceSample(
                    "user_refresh_all",
                    startedAt: startedAt,
                    metadata: "force=\(forceChainRefresh) active=\(appIsActive)"
                )
            }

            if appIsActive {
                await refreshPendingTransactions(includeHistoryRefreshes: true, historyRefreshInterval: 120)
                await withBalanceRefreshWindow {
                    await refreshChainBalances(
                        includeHistoryRefreshes: true,
                        historyRefreshInterval: 120,
                        forceChainRefresh: forceChainRefresh
                    )
                }
                await refreshLivePrices()
                await refreshFiatExchangeRatesIfNeeded()
                lastFullRefreshAt = Date()
            } else {
                await performBackgroundMaintenanceTick()
            }
        }
        userInitiatedRefreshTask = refreshTask
        await refreshTask.value
        userInitiatedRefreshTask = nil
    }

    func runActiveScheduledMaintenance(now: Date) async {
        let plan = WalletRefreshPlanner.activeMaintenancePlan(
            now: now,
            lastPendingTransactionRefreshAt: lastPendingTransactionRefreshAt,
            lastLivePriceRefreshAt: lastLivePriceRefreshAt,
            hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
            shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh,
            pendingRefreshInterval: activePendingRefreshIntervalForProfile(),
            priceRefreshInterval: activePriceRefreshIntervalForProfile()
        )
        if plan.refreshPendingTransactions {
            await refreshPendingTransactions(includeHistoryRefreshes: false)
        }

        if plan.refreshLivePrices {
            await refreshLivePrices()
        }

        await refreshFiatExchangeRatesIfNeeded()
    }
}
