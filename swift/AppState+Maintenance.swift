import Foundation
import UIKit
import UserNotifications

extension AppState {
    func currentBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1.0 : level
    }
    /// Device-local inputs to core's maintenance plan. Core owns the profile,
    /// refresh cadence, last-run times, and pending-send polling decisions.
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
        await self.bridge.maintenancePlan(conditions: deviceConditions())
    }
    func notifyPortfolioMovement() async {
        let evaluation: LargeMovementEvaluation
        do {
            guard let result = try await self.bridge.evaluatePortfolioMovement(appIsActive: appIsActive) else { return }
            evaluation = result
        } catch {
            appendOperationalLog(.error, category: "Portfolio Movement", message: error.localizedDescription)
            return
        }
        // Localize the notification for the transfer direction.
        let percent = evaluation.ratio.formatted(.percent.precision(.fractionLength(0)))
        let content = UNMutableNotificationContent()
        content.title = localizedStoreString("Large portfolio movement detected")
        content.body = AppLocalization.format(
            evaluation.directionUp
                ? "Your portfolio rose by %@ (%@) since the last sync."
                : "Your portfolio fell by %@ (%@) since the last sync.",
            formattedFiatAmount(fromUSD: evaluation.absoluteDelta), percent)
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
            let result = try await self.bridge.refreshApp(intent: intent, conditions: deviceConditions())
            lastMaintenancePollSeconds = result.pollSeconds
            let portfolioReadSucceeded = await rebuildWalletDerivedStateFromCore()
            if let pending = result.pending {
                await applyPendingStatusChanges(pending.changes)
                for failure in pending.failures {
                    appendOperationalLog(.error, category: "Pending Transactions", message: failure.message)
                }
                lastPendingTransactionRefreshAt = Date()
            }
            let historyReadSucceeded = await refreshTransactionProjection()
            if let sent = lastSentTransaction {
                lastSentTransaction = try await self.bridge.transaction(id: sent.id)
            }
            await updateSendVerificationNoticeForLastSentTransaction()
            for failure in result.failures {
                appendOperationalLog(.error, category: "Refresh", message: failure)
            }
            await diagnostics.loadFromSQLite()
            await evaluatePriceAlerts()
            await notifyPortfolioMovement()
            return portfolioReadSucceeded && historyReadSucceeded
                && result.failures.isEmpty && (result.pending?.failures.isEmpty ?? true)
        } catch {
            appendOperationalLog(.error, category: "Refresh", message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func performUserInitiatedRefresh() async -> Bool {
        if let existing = userInitiatedRefreshTask { return await existing.value }
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            self.isUserInitiatedRefreshInProgress = true
            defer { self.isUserInitiatedRefreshInProgress = false }
            return await self.performCoreRefresh(.user)
        }
        userInitiatedRefreshTask = task
        let succeeded = await task.value
        userInitiatedRefreshTask = nil
        return succeeded
    }
    func startMaintenanceLoopIfNeeded() {
        guard servicesEnabled else { return }
        guard maintenanceTask == nil else { return }
        // With no wallets there's nothing to maintain — no pending tx to
        // poll, no price work, no chain history to sync. Don't even spin
        // the loop until something's worth checking.
        // `applyWalletCollectionSideEffects` re-invokes this once a wallet
        // exists. The loop also self-exits below when wallets drop to 0.
        guard !wallets.isEmpty else { return }
        maintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Self-exit when the user deletes all wallets. Lets the
                // loop terminate naturally instead of sleeping forever
                // doing nothing — matches the no-wallet startup gate.
                if self.wallets.isEmpty {
                    self.maintenanceTask = nil
                    break
                }
                await self.runScheduledMaintenanceOnce()
                // The cadence comes back with the plan: core knows whether
                // anything is pending and what the sync profile allows.
                try? await Task.sleep(
                    nanoseconds: self.lastMaintenancePollSeconds * 1_000_000_000)
            }
        }
    }
    /// One tick. Core decides what it is, from its own clock and this device's
    /// conditions; four questions and a `Date?` on this side became one.
    func runScheduledMaintenanceOnce() async {
        await performCoreRefresh(.scheduled)
    }
    var pendingTransactionRefreshStatusText: String? {
        guard let at = lastPendingTransactionRefreshAt else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return AppLocalization.format("Last checked %@", f.localizedString(for: at, relativeTo: Date()))
    }
}
