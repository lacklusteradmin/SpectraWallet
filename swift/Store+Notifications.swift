import Foundation
import UserNotifications
@MainActor
extension AppState {
    /// Core evaluates its stored alerts against its stored quotes.
    func evaluatePriceAlerts() async {
        let epoch = beginCoreStateRead()
        guard let notifications = try? await self.bridge.evaluatePriceAlerts()
        else { return }
        if let state = try? await self.bridge.appState() {
            applyCoreState(state, epoch: epoch)
        }
        for notification in notifications {
            sendPriceAlertNotification(for: notification)
        }
    }
    private func requestStandardNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
        }
    }
    private func postNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    func requestPriceAlertNotificationPermission() { requestStandardNotificationPermission() }
    func requestNotificationPermissionIfNeeded() { requestStandardNotificationPermission() }
    func requestTransactionStatusNotificationPermission() {
        guard committedAppSettings.useTransactionStatusNotifications || committedAppSettings.useLargeMovementNotifications else { return }
        requestNotificationPermissionIfNeeded()
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
                template, notification.assetDisplayName, notification.chainName,
                formattedFiatAmount(fromUSD: notification.livePrice),
                formattedFiatAmount(fromUSD: notification.targetPrice)
            )
        )
    }
    func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) {
        guard committedAppSettings.useTransactionStatusNotifications else { return }
        let title: String
        let body: String
        switch newStatus {
        case .confirmed:
            title = AppLocalization.format("%@ transaction confirmed", transaction.symbol)
            body = AppLocalization.format(
                "Your %@ send from %@ is now confirmed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .failed:
            title = AppLocalization.format("%@ transaction failed", transaction.symbol)
            body =
                transaction.localizedFailureReason
                ?? AppLocalization.format(
                    "Your %@ send from %@ failed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .pending: return
        }
        postNotification(
            identifier: "transaction-status-\(transaction.id)-\(newStatus)", title: title, body: body
        )
    }
}
