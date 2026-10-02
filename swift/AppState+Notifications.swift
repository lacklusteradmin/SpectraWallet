import Foundation
import UserNotifications

// Core decides what is worth telling the user — a price alert, a large
// portfolio movement, a send reaching a terminal status — and logs it. What is
// left on this side is what a platform has: a notification and a Live Activity.
extension AppState {
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    func requestTransactionStatusNotificationPermission() {
        guard committedAppSettings.useTransactionStatusNotifications || committedAppSettings.useLargeMovementNotifications else { return }
        requestNotificationPermission()
    }

    private func postNotification(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do { try await UNUserNotificationCenter.current().add(request) }
        catch { appendOperationalLog(.error, category: "Notifications", message: error.localizedDescription) }
    }

    func deliverPriceAlertNotifications(_ notifications: [PriceAlertNotification]) async {
        for notification in notifications { await sendPriceAlertNotification(for: notification) }
    }
    /// One sentence per condition, so each language words both directions.
    private func sendPriceAlertNotification(for notification: PriceAlertNotification) async {
        let template: String
        switch notification.condition {
        case .above: template = "%@ on %@ is now %@, above your target of %@."
        case .below: template = "%@ on %@ is now %@, below your target of %@."
        }
        await postNotification(
            identifier: "price-alert-\(notification.id)-\(UUID().uuidString)",
            title: AppLocalization.format("%@ price alert", notification.symbol),
            body: AppLocalization.format(
                template, notification.assetDisplayName, notification.chainId.displayName,
                amounts.formattedFiat(notification.livePrice, currency: notification.currency),
                amounts.formattedFiat(notification.targetPrice, currency: notification.currency)))
    }

    func deliverPortfolioMovement(_ evaluation: LargeMovementEvaluation) async {
        let percent = evaluation.ratio.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale))
        await postNotification(
            identifier: "portfolio-movement-\(UUID().uuidString)",
            title: AppLocalization.string("Large portfolio movement detected"),
            body: AppLocalization.format(
                evaluation.directionUp
                    ? "Your portfolio rose by %@ (%@) since the last sync."
                    : "Your portfolio fell by %@ (%@) since the last sync.",
                amounts.formattedFiat(evaluation.absoluteDelta, currency: evaluation.currency), percent))
    }

    /// Deliver native effects after the caller adopts the transaction projection.
    /// A Live Activity follows every change; a notification only what core
    /// says is worth one.
    func deliverPendingStatusChanges(_ changes: [TransactionStatusChange]) async {
        for change in changes where change.statusChanged {
            guard let transaction = try? await bridge.ready().transaction(id: change.id) else { continue }
            if change.notify { await sendTransactionStatusNotification(for: transaction, newStatus: change.newStatus) }
            await finishSendLiveActivity(for: transaction, newStatus: change.newStatus)
        }
    }
    private func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) async {
        guard let body = transaction.sendOutcomeDetail(for: newStatus) else { return }
        let title = newStatus == .confirmed
            ? AppLocalization.format("%@ transaction confirmed", transaction.symbol)
            : AppLocalization.format("%@ transaction failed", transaction.symbol)
        await postNotification(identifier: "transaction-status-\(transaction.id)-\(newStatus)", title: title, body: body)
    }
}
