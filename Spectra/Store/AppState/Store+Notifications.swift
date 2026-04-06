import Foundation
import UserNotifications

@MainActor
extension WalletStore {
    func mergeBuiltInTokenPreferences(with persisted: [TokenPreferenceEntry]) -> [TokenPreferenceEntry] {
        let builtIns = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        let custom = persisted.filter { !$0.isBuiltIn }
        var merged: [TokenPreferenceEntry] = []
        for builtIn in builtIns {
            if let existing = persisted.first(where: { entry in
                entry.isBuiltIn
                    && entry.chain == builtIn.chain
                    && normalizedTrackedTokenIdentifier(for: entry.chain, contractAddress: entry.contractAddress)
                        == normalizedTrackedTokenIdentifier(for: builtIn.chain, contractAddress: builtIn.contractAddress)
            }) {
                var updated = builtIn
                updated.isEnabled = existing.isEnabled
                updated.displayDecimals = existing.displayDecimals
                merged.append(updated)
            } else {
                merged.append(builtIn)
            }
        }
        merged.append(contentsOf: custom)
        merged.sort { lhs, rhs in
            if lhs.chain != rhs.chain {
                return lhs.chain.rawValue < rhs.chain.rawValue
            }
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.symbol < rhs.symbol
        }
        return merged
    }

    func evaluatePriceAlerts() {
        guard usePriceAlerts, !priceAlerts.isEmpty else { return }

        var updatedAlerts = priceAlerts

        for index in updatedAlerts.indices {
            let alert = updatedAlerts[index]
            guard alert.isEnabled,
                  let coin = portfolio.first(where: { $0.holdingKey == alert.holdingKey }),
                  let livePrice = currentPriceIfAvailable(for: coin) else {
                continue
            }
            let meetsTarget: Bool
            switch alert.condition {
            case .above:
                meetsTarget = livePrice >= alert.targetPrice
            case .below:
                meetsTarget = livePrice <= alert.targetPrice
            }

            if meetsTarget && !alert.hasTriggered {
                updatedAlerts[index].hasTriggered = true
                sendPriceAlertNotification(for: alert, livePrice: livePrice)
            } else if !meetsTarget && alert.hasTriggered {
                updatedAlerts[index].hasTriggered = false
            }
        }

        priceAlerts = updatedAlerts
    }

    private func requestStandardNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            // Ignore the result here; wallet workflows should remain responsive regardless.
        }
    }

    private func postNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func requestPriceAlertNotificationPermission() {
        requestStandardNotificationPermission()
    }

    func requestNotificationPermissionIfNeeded() {
        requestStandardNotificationPermission()
    }

    func requestTransactionStatusNotificationPermission() {
        guard useTransactionStatusNotifications || useLargeMovementNotifications else { return }
        requestNotificationPermissionIfNeeded()
    }

    func shouldRebuildDashboardForLivePriceChange(
        from oldPrices: [String: Double],
        to newPrices: [String: Double]
    ) -> Bool {
        guard oldPrices != newPrices else { return false }
        guard !cachedDashboardRelevantPriceKeys.isEmpty else { return true }

        let changedRelevantKey = cachedDashboardRelevantPriceKeys.contains { key in
            oldPrices[key] != newPrices[key]
        }
        if changedRelevantKey {
            return true
        }

        if selectedMainTab == .home {
            let pinnedPrototypeKeys = Set(
                dashboardPinnedAssetPricingPrototypes
                    .filter(isPricedAsset)
                    .map(assetIdentityKey)
            )
            return pinnedPrototypeKeys.contains { key in
                oldPrices[key] != newPrices[key]
            }
        }

        return false
    }

    private func sendPriceAlertNotification(for alert: PriceAlertRule, livePrice: Double) {
        postNotification(
            identifier: "price-alert-\(alert.id.uuidString)-\(UUID().uuidString)",
            title: localizedStoreFormat("%@ price alert", alert.symbol),
            body: localizedStoreFormat(
                "%@ on %@ is now %@, which is %@ your target of %@.",
                alert.assetName,
                alert.chainName,
                formattedFiatAmount(fromUSD: livePrice),
                alert.condition.rawValue.lowercased(),
                formattedFiatAmount(fromUSD: alert.targetPrice)
            )
        )
    }

    func sendTransactionStatusNotification(for transaction: TransactionRecord, newStatus: TransactionStatus) {
        guard useTransactionStatusNotifications else { return }
        let title: String
        let body: String
        switch newStatus {
        case .confirmed:
            title = localizedStoreFormat("%@ transaction confirmed", transaction.symbol)
            body = localizedStoreFormat("Your %@ send from %@ is now confirmed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .failed:
            title = localizedStoreFormat("%@ transaction failed", transaction.symbol)
            body = transaction.failureReason ?? localizedStoreFormat("Your %@ send from %@ failed on %@.", transaction.symbol, transaction.walletName, transaction.chainName)
        case .pending:
            return
        }

        postNotification(
            identifier: "transaction-status-\(transaction.id.uuidString)-\(newStatus.rawValue)",
            title: title,
            body: body
        )
    }
}
