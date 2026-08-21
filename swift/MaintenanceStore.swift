import Foundation
import UIKit
import UserNotifications
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Spectra", category: "Maintenance")

extension AppState {
    func currentBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1.0 : level
    }
    /// What only this device can tell core.
    ///
    /// Everything else the plan needs — the sync profile, the refresh cadence,
    /// when each thing last ran, whether a pending send is still worth
    /// polling — is state core holds. This was five separate questions, each
    /// taking the piece of `AppState` it needed as an argument.
    private func deviceConditions() -> DeviceConditions {
        DeviceConditions(
            appIsActive: appIsActive,
            isNetworkReachable: isNetworkReachable,
            isConstrainedNetwork: isConstrainedNetwork,
            isExpensiveNetwork: isExpensiveNetwork,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: currentBatteryLevel(),
            wantsPriceRefresh: shouldRunScheduledPriceRefresh)
    }
    func maintenancePlan() async -> MaintenancePlan {
        await WalletServiceBridge.shared.maintenancePlan(conditions: deviceConditions())
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
    func performBackgroundMaintenanceTick(allowHeavyBackgroundWork: Bool = true) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("Running background maintenance tick")
        await refreshPendingTransactions(includeHistoryRefreshes: false, historyRefreshInterval: 300)
        if appIsActive {
            if shouldRunScheduledPriceRefresh { await refreshLivePrices() }
            await refreshFiatExchangeRatesIfNeeded()
            recordPerformanceSample("background_maintenance_tick", startedAt: startedAt, metadata: "mode=active")
            return
        }
        guard allowHeavyBackgroundWork else { return }
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
    func runActiveScheduledMaintenance(plan: MaintenancePlan) async {
        if plan.refreshPendingTransactions {
            await refreshPendingTransactions(includeHistoryRefreshes: false)
            await WalletServiceBridge.shared.recordRefresh(kind: .pendingTransactions)
        }
        if plan.refreshLivePrices {
            await refreshLivePrices()
            await WalletServiceBridge.shared.recordRefresh(kind: .livePrices)
        }
        await refreshFiatExchangeRatesIfNeeded()
    }
}
