import Foundation
import UserNotifications
@MainActor
extension AppState {
    /// Core evaluates its stored alerts against its stored quotes.
    func evaluatePriceAlerts() async {
        let epoch = beginCoreStateRead()
        guard let notifications = try? await WalletServiceBridge.shared.evaluatePriceAlerts()
        else { return }
        if let state = try? await WalletServiceBridge.shared.appState() {
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
        guard preferences.useTransactionStatusNotifications || preferences.useLargeMovementNotifications else { return }
        requestNotificationPermissionIfNeeded()
    }
    private func sendPriceAlertNotification(for notification: PriceAlertNotification) {
        postNotification(
            identifier: "price-alert-\(notification.id)-\(UUID().uuidString)",
            title: AppLocalization.format("%@ price alert", notification.symbol),
            body: AppLocalization.format(
                "%@ on %@ is now %@, which is %@ your target of %@.", notification.assetName, notification.chainName,
                formattedFiatAmount(fromUSD: notification.livePrice), notification.condition.rawValue.lowercased(),
                formattedFiatAmount(fromUSD: notification.targetPrice)
            )
        )
    }
    func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) {
        guard preferences.useTransactionStatusNotifications else { return }
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
            identifier: "transaction-status-\(transaction.id.uuidString)-\(newStatus.rawValue)", title: title, body: body
        )
    }
}
