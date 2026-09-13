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
    func notifyPortfolioMovement() async {
        let evaluation: LargeMovementEvaluation
        do {
            guard let result = try await WalletServiceBridge.shared.evaluatePortfolioMovement(appIsActive: appIsActive) else { return }
            evaluation = result
        } catch {
            appendOperationalLog(.error, category: "Portfolio Movement", message: error.localizedDescription)
            return
        }
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
        do { try await UNUserNotificationCenter.current().add(request) }
        catch { appendOperationalLog(.error, category: "Portfolio Movement", message: error.localizedDescription) }
    }
    func performBackgroundMaintenanceTick(allowHeavyBackgroundWork: Bool = true) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("Running background maintenance tick")
        await refreshPendingTransactions(includeHistoryRefreshes: false, historyRefreshInterval: 300)
        if appIsActive {
            if shouldRunScheduledPriceRefresh { await refreshLivePrices() }
            await refreshFiatExchangeRatesIfNeeded()
            await notifyPortfolioMovement()
            recordPerformanceSample("background_maintenance_tick", startedAt: startedAt, metadata: "mode=active")
            return
        }
        guard allowHeavyBackgroundWork else { return }
        await withBalanceRefreshWindow {
            await refreshChainBalances(includeHistoryRefreshes: false, historyRefreshInterval: 300, forceChainRefresh: false)
        }
        await runHistoryRefreshes(interval: 300)
        if shouldRunScheduledPriceRefresh { await refreshLivePrices() }
        await refreshFiatExchangeRatesIfNeeded()
        await notifyPortfolioMovement()
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
        let refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
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
                await notifyPortfolioMovement()
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
        await notifyPortfolioMovement()
    }
}
