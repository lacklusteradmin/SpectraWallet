import Foundation
import UserNotifications
@MainActor
extension AppState {
    func mergeBuiltInTokenPreferences(with persisted: [TokenPreferenceEntry]) -> [TokenPreferenceEntry] {
        let builtIns = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        return corePlanMergeBuiltInTokenPreferences(builtIns: builtIns, persisted: persisted)
    }
    func evaluatePriceAlerts() {
        guard preferences.usePriceAlerts, !priceAlerts.isEmpty else { return }
        let alertsByID = Dictionary(uniqueKeysWithValues: priceAlerts.map { ($0.id.uuidString, $0) })
        let ffiAlerts: [PriceAlertEvaluationAlert] = priceAlerts.map { alert in
            PriceAlertEvaluationAlert(
                id: alert.id.uuidString, holdingKey: alert.holdingKey, assetName: alert.assetName,
                symbol: alert.symbol, chainName: alert.chainName, targetPrice: alert.targetPrice,
                condition: alert.condition, isEnabled: alert.isEnabled, hasTriggered: alert.hasTriggered
            )
        }
        let ffiPrices: [PriceAlertEvaluationPrice] = priceAlerts.compactMap { alert in
            guard let coin = portfolio.first(where: { $0.holdingKey == alert.holdingKey }),
                let livePrice = currentPriceIfAvailable(for: coin)
            else { return nil }
            return PriceAlertEvaluationPrice(holdingKey: alert.holdingKey, livePrice: livePrice)
        }
        let plan = corePlanPriceAlertEvaluation(alerts: ffiAlerts, prices: ffiPrices)
        if !plan.updates.isEmpty {
            var updated = priceAlerts
            let idxByID = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id.uuidString, $0.offset) })
            for update in plan.updates {
                guard let idx = idxByID[update.id] else { continue }
                updated[idx].hasTriggered = update.hasTriggered
            }
            priceAlerts = updated
        }
        for notif in plan.notifications {
            guard let alert = alertsByID[notif.id] else { continue }
            sendPriceAlertNotification(for: alert, livePrice: notif.livePrice)
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
    func shouldRebuildDashboardForLivePriceChange(from oldPrices: [String: Double], to newPrices: [String: Double]) -> Bool {
        let pinnedPrototypeKeys =
            selectedMainTab == .home
            ? Array(Set(dashboardPinnedAssetPricingPrototypes.filter(isPricedAsset).map(assetIdentityKey)))
            : []
        return corePlanDashboardRebuildForLivePriceChange(
            request: DashboardRebuildDecisionRequest(
                oldPrices: oldPrices.map { PriceAlertEvaluationPrice(holdingKey: $0.key, livePrice: $0.value) },
                newPrices: newPrices.map { PriceAlertEvaluationPrice(holdingKey: $0.key, livePrice: $0.value) },
                cachedRelevantPriceKeys: Array(cachedDashboardRelevantPriceKeys),
                pinnedPrototypeKeys: pinnedPrototypeKeys,
                selectedMainTabIsHome: selectedMainTab == .home
            )
        )
    }
    private func sendPriceAlertNotification(for alert: PriceAlertRule, livePrice: Double) {
        postNotification(
            identifier: "price-alert-\(alert.id.uuidString)-\(UUID().uuidString)",
            title: localizedStoreFormat("%@ price alert", alert.symbol),
            body: localizedStoreFormat(
                "%@ on %@ is now %@, which is %@ your target of %@.", alert.assetName, alert.chainName,
                formattedFiatAmount(fromUSD: livePrice), alert.condition.rawValue.lowercased(),
                formattedFiatAmount(fromUSD: alert.targetPrice)
            )
        )
    }
    func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) {
        guard preferences.useTransactionStatusNotifications else { return }
        let title: String
        let body: String
        switch newStatus {
        case .confirmed:
            title = localizedStoreFormat("%@ transaction confirmed", transaction.symbol)
            body = localizedStoreFormat(
                "Your %@ send from %@ is now confirmed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .failed:
            title = localizedStoreFormat("%@ transaction failed", transaction.symbol)
            body =
                transaction.failureReason
                ?? localizedStoreFormat(
                    "Your %@ send from %@ failed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .pending: return
        }
        postNotification(
            identifier: "transaction-status-\(transaction.id.uuidString)-\(newStatus.rawValue)", title: title, body: body
        )
    }
}
