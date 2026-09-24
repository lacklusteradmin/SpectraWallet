import Foundation
import UIKit
import UserNotifications

extension AppState {
    func deliverPortfolioMovement(_ evaluation: LargeMovementEvaluation) async {
        // Localize the notification for the transfer direction.
        let percent = evaluation.ratio.formatted(.percent.precision(.fractionLength(0)))
        let content = UNMutableNotificationContent()
        content.title = localizedStoreString("Large portfolio movement detected")
        content.body = AppLocalization.format(
            evaluation.directionUp
                ? "Your portfolio rose by %@ (%@) since the last sync."
                : "Your portfolio fell by %@ (%@) since the last sync.",
            amounts.formattedFiat(evaluation.absoluteDelta, currency: evaluation.currency), percent)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "portfolio-movement-\(UUID().uuidString)", content: content, trigger: nil
        )
        do { try await UNUserNotificationCenter.current().add(request) }
        catch { appendOperationalLog(.error, category: "Portfolio Movement", message: error.localizedDescription) }
    }

    /// Ask core to refresh for `intent` and adopt the result. Scheduled ticks
    /// are core's own; they arrive through the refresh observer.
    @discardableResult
    func performCoreRefresh(_ intent: AppRefreshIntent) async -> Bool {
        do {
            let result = try await self.bridge.ready().refreshApp(intent: intent, conditions: deviceConditions())
            return await adoptRefreshResult(result)
        } catch {
            appendOperationalLog(.error, category: "Refresh", message: error.localizedDescription)
            return false
        }
    }

    /// Core evaluated alerts and movement after its own writes and logged its
    /// failures; adopt what it says changed, once, then tell the user.
    @discardableResult
    func adoptRefreshResult(_ result: AppRefreshResult) async -> Bool {
        let portfolioReadSucceeded = await rebuildWalletDerivedStateFromCore()
        let historyReadSucceeded = result.transactionsChanged ? await refreshTransactionProjection() : true
        if let pending = result.pending {
            await deliverPendingStatusChanges(pending.changes)
            lastPendingTransactionRefreshAt = Date()
        }
        if result.transactionsChanged { await updateStagedSendVerificationNotice() }
        if result.diagnosticsChanged { await diagnostics.loadFromSQLite() }
        deliverPriceAlertNotifications(result.priceAlerts)
        if let movement = result.movement { await deliverPortfolioMovement(movement) }
        return portfolioReadSucceeded && historyReadSucceeded
            && result.failures.isEmpty && (result.pending?.failures.isEmpty ?? true)
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
    var pendingTransactionRefreshStatusText: String? {
        guard let at = lastPendingTransactionRefreshAt else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return AppLocalization.format("Last checked %@", f.localizedString(for: at, relativeTo: Date()))
    }
}
