import Foundation
import UIKit
import UserNotifications

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
    @discardableResult
    func performCoreRefresh(_ intent: AppRefreshIntent) async -> Bool {
        do {
            let result = try await WalletServiceBridge.shared.refreshApp(intent: intent, conditions: deviceConditions())
            lastMaintenancePollSeconds = result.pollSeconds
            applyQuoteProjection(result.state)
            adoptWalletsFromCore(try await WalletServiceBridge.shared.storedWallets())
            await rebuildWalletDerivedStateFromCore()
            rebuildDashboardDerivedState()
            if let pending = result.pending {
                await applyPendingStatusChanges(pending.changes)
                for failure in pending.failures {
                    appendOperationalLog(.error, category: "Pending Transactions", message: failure.message)
                }
                lastPendingTransactionRefreshAt = Date()
            }
            await refreshTransactionProjection()
            if let sent = lastSentTransaction {
                lastSentTransaction = transactions.first { $0.id == sent.id }
            }
            updateSendVerificationNoticeForLastSentTransaction()
            for failure in result.failures {
                appendOperationalLog(.error, category: "Refresh", message: failure)
            }
            await diagnostics.loadFromSQLite()
            await evaluatePriceAlerts()
            await notifyPortfolioMovement()
            return result.failures.isEmpty && (result.pending?.failures.isEmpty ?? true)
        } catch {
            appendOperationalLog(.error, category: "Refresh", message: error.localizedDescription)
            return false
        }
    }

    func performUserInitiatedRefresh() async {
        if let existing = userInitiatedRefreshTask { await existing.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isUserInitiatedRefreshInProgress = true
            defer { self.isUserInitiatedRefreshInProgress = false }
            await self.performCoreRefresh(.user)
        }
        userInitiatedRefreshTask = task
        await task.value
        userInitiatedRefreshTask = nil
    }
}
