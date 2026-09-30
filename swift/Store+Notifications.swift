import Foundation
import UserNotifications
@MainActor
extension AppState {
    func deliverPriceAlertNotifications(_ notifications: [PriceAlertNotification]) {
        for notification in notifications { sendPriceAlertNotification(for: notification) }
    }
    private func postNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    func requestTransactionStatusNotificationPermission() {
        guard committedAppSettings.useTransactionStatusNotifications || committedAppSettings.useLargeMovementNotifications else { return }
        requestNotificationPermission()
    }
    /// One sentence per condition. The single template took the condition's
    /// raw value, lowercased, as a word — so a Chinese notification read
    /// "这已above您的目标价".
    private func sendPriceAlertNotification(for notification: PriceAlertNotification) {
        let template: String
        switch notification.condition {
        case .above: template = "%@ on %@ is now %@, above your target of %@."
        case .below: template = "%@ on %@ is now %@, below your target of %@."
        }
        postNotification(
            identifier: "price-alert-\(notification.id)-\(UUID().uuidString)",
            title: AppLocalization.format("%@ price alert", notification.symbol),
            body: AppLocalization.format(
                template, notification.assetDisplayName, notification.chainId.displayName,
                amounts.formattedFiat(notification.livePrice, currency: notification.currency),
                amounts.formattedFiat(notification.targetPrice, currency: notification.currency)
            )
        )
    }
    func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) {
        guard committedAppSettings.useTransactionStatusNotifications else { return }
        guard let body = transaction.sendOutcomeDetail(for: newStatus) else { return }
        let title = newStatus == .confirmed
            ? AppLocalization.format("%@ transaction confirmed", transaction.symbol)
            : AppLocalization.format("%@ transaction failed", transaction.symbol)
        postNotification(
            identifier: "transaction-status-\(transaction.id)-\(newStatus)", title: title, body: body
        )
    }
}
