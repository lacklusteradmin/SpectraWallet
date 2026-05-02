import Foundation
import UIKit
import UserNotifications
import os
extension AppState {
    func currentBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1.0 : level
    }
    func activePendingRefreshIntervalForProfile() -> TimeInterval {
        Spectra.activePendingRefreshIntervalForProfile(
            backgroundSyncProfile: backgroundSyncProfile.rawValue, balancedInterval: Self.activePendingRefreshInterval
        )
    }
    func activePriceRefreshIntervalForProfile() -> TimeInterval { max(60, TimeInterval(preferences.automaticRefreshFrequencyMinutes * 60)) }
    func baseBackgroundMaintenanceInterval() -> TimeInterval { TimeInterval(backgroundBalanceRefreshFrequencyMinutes * 60) }
    func backgroundMaintenanceInterval(now _: Date = Date()) -> TimeInterval {
        computeBackgroundMaintenanceInterval(
            baseIntervalSec: baseBackgroundMaintenanceInterval(),
            isConstrainedNetwork: isConstrainedNetwork,
            isExpensiveNetwork: isExpensiveNetwork,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: currentBatteryLevel()
        )
    }
    func canRunHeavyBackgroundRefresh() -> Bool {
        evaluateHeavyRefreshGate(
            backgroundSyncProfile: backgroundSyncProfile.rawValue,
            isNetworkReachable: isNetworkReachable,
            isConstrainedNetwork: isConstrainedNetwork,
            isExpensiveNetwork: isExpensiveNetwork,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: currentBatteryLevel()
        )
    }
    func maybeSendLargeMovementNotification(previousTotalUSD: Double, currentTotalUSD: Double) {
        guard preferences.useLargeMovementNotifications else { return }
        guard !appIsActive else { return }
        let currentCompositionSignature = portfolioCompositionSignature()
        guard lastObservedPortfolioCompositionSignature == currentCompositionSignature else {
            resetLargeMovementAlertBaseline()
            return
        }
        guard previousTotalUSD > 0 else { return }
        let evaluation = coreEvaluateLargeMovement(
            previousTotalUsd: previousTotalUSD, currentTotalUsd: currentTotalUSD,
            usdThreshold: preferences.largeMovementAlertUSDThreshold, percentThreshold: preferences.largeMovementAlertPercentThreshold
        )
        guard evaluation.shouldAlert else { return }
        let direction = evaluation.directionUp ? "up" : "down"
        let absoluteDelta = evaluation.absoluteDelta
        let ratio = evaluation.ratio
        let content = UNMutableNotificationContent()
        content.title = "Large portfolio movement detected"
        content.body =
            "Your portfolio moved \(direction) by \(formattedFiatAmount(fromUSD: absoluteDelta)) (\(Int((ratio * 100).rounded()))%) since last sync."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "portfolio-movement-\(UUID().uuidString)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    func resetLargeMovementAlertBaseline() {
        lastObservedPortfolioTotalUSD = totalBalance
        lastObservedPortfolioCompositionSignature = portfolioCompositionSignature()
    }
    func portfolioCompositionSignature() -> String { Spectra.portfolioCompositionSignature(holdingKeys: portfolio.map(\.holdingKey)) }
    func performBackgroundMaintenanceTick() async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("Running background maintenance tick")
        await refreshPendingTransactions(includeHistoryRefreshes: false, historyRefreshInterval: 300)
        if appIsActive {
            if shouldRunScheduledPriceRefresh { await refreshLivePrices() }
            await refreshFiatExchangeRatesIfNeeded()
            recordPerformanceSample("background_maintenance_tick", startedAt: startedAt, metadata: "mode=active")
            return
        }
        guard canRunHeavyBackgroundRefresh() else { return }
        let previousTotal = lastObservedPortfolioTotalUSD ?? totalBalance
        await withBalanceRefreshWindow {
            await refreshChainBalances(includeHistoryRefreshes: false, historyRefreshInterval: 300, forceChainRefresh: false)
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
            "background_maintenance_tick", startedAt: startedAt, metadata: "mode=background chains=\(refreshableChainIDs.count)"
        )
    }
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
                    "user_refresh_all", startedAt: startedAt, metadata: "force=\(forceChainRefresh) active=\(appIsActive)"
                )
            }
            if appIsActive {
                await refreshPendingTransactions(includeHistoryRefreshes: true, historyRefreshInterval: 120)
                await withBalanceRefreshWindow {
                    await refreshChainBalances(
                        includeHistoryRefreshes: true, historyRefreshInterval: 120, forceChainRefresh: forceChainRefresh
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
            now: now, lastPendingTransactionRefreshAt: lastPendingTransactionRefreshAt, lastLivePriceRefreshAt: lastLivePriceRefreshAt,
            hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
            shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh,
            pendingRefreshInterval: activePendingRefreshIntervalForProfile(), priceRefreshInterval: activePriceRefreshIntervalForProfile()
        )
        if plan.refreshPendingTransactions { await refreshPendingTransactions(includeHistoryRefreshes: false) }
        if plan.refreshLivePrices { await refreshLivePrices() }
        await refreshFiatExchangeRatesIfNeeded()
    }
}

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
        now: Date, lastPendingTransactionRefreshAt: Date?, lastLivePriceRefreshAt: Date?, hasPendingTransactionMaintenanceWork: Bool,
        shouldRunScheduledPriceRefresh: Bool, pendingRefreshInterval: TimeInterval, priceRefreshInterval: TimeInterval
    ) -> WalletActiveMaintenancePlan {
        let plan = coreActiveMaintenancePlan(
            request: ActiveMaintenancePlanRequest(
                nowUnix: now.timeIntervalSince1970,
                lastPendingTransactionRefreshAtUnix: lastPendingTransactionRefreshAt?.timeIntervalSince1970,
                lastLivePriceRefreshAtUnix: lastLivePriceRefreshAt?.timeIntervalSince1970,
                hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork,
                shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh, pendingRefreshInterval: pendingRefreshInterval,
                priceRefreshInterval: priceRefreshInterval
            )
        )
        return WalletActiveMaintenancePlan(
            refreshPendingTransactions: plan.refreshPendingTransactions, refreshLivePrices: plan.refreshLivePrices)
    }
    static func shouldRunBackgroundMaintenance(
        now: Date, isNetworkReachable: Bool, lastBackgroundMaintenanceAt: Date?, interval: TimeInterval
    ) -> Bool {
        coreShouldRunBackgroundMaintenance(
            request: BackgroundMaintenanceRequest(
                nowUnix: now.timeIntervalSince1970, isNetworkReachable: isNetworkReachable,
                lastBackgroundMaintenanceAtUnix: lastBackgroundMaintenanceAt?.timeIntervalSince1970, interval: interval
            )
        )
    }
    static func chainPlans(
        for chainIDs: Set<WalletChainID>, now: Date, forceChainRefresh: Bool, includeHistoryRefreshes: Bool,
        historyRefreshInterval: TimeInterval, pendingTransactionMaintenanceChains: Set<WalletChainID>, degradedChains: Set<WalletChainID>,
        lastGoodChainSyncByID: [WalletChainID: Date], lastHistoryRefreshAtByChainID: [WalletChainID: Date],
        automaticChainRefreshStalenessInterval: TimeInterval
    ) -> [WalletRefreshChainPlan] {
        let plans = coreChainRefreshPlans(
            request: ChainRefreshPlanRequest(
                chainIds: chainIDs.map(\.rawValue), nowUnix: now.timeIntervalSince1970, forceChainRefresh: forceChainRefresh,
                includeHistoryRefreshes: includeHistoryRefreshes, historyRefreshInterval: historyRefreshInterval,
                pendingTransactionMaintenanceChainIds: pendingTransactionMaintenanceChains.map(\.rawValue),
                degradedChainIds: degradedChains.map(\.rawValue),
                lastGoodChainSyncById: Dictionary(
                    uniqueKeysWithValues: lastGoodChainSyncByID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }),
                lastHistoryRefreshAtByChainId: Dictionary(
                    uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }),
                automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
            )
        )
        return plans.compactMap { plan in
            guard let chainID = WalletChainID(plan.chainId) else { return nil }
            return WalletRefreshChainPlan(chainID: chainID, refreshHistory: plan.refreshHistory)
        }
    }
    static func historyPlans(
        for chainIDs: Set<WalletChainID>, now: Date, interval: TimeInterval, lastHistoryRefreshAtByChainID: [WalletChainID: Date]
    ) -> [WalletChainID] {
        let ids = coreHistoryRefreshPlans(
            request: HistoryRefreshPlanRequest(
                chainIds: chainIDs.map(\.rawValue), nowUnix: now.timeIntervalSince1970, interval: interval,
                lastHistoryRefreshAtByChainId: Dictionary(
                    uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
            )
        )
        return ids.compactMap(WalletChainID.init)
    }
}
