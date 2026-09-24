import Foundation
import SwiftUI
@MainActor
extension AppState {
    func clearOperationalLogs() { diagnostics.clearOperationalLogs() }
    var networkSyncStatusText: String {
        let reachability = isNetworkReachable ? localizedStoreString("reachable") : localizedStoreString("offline")
        let constrained = isConstrainedNetwork ? localizedStoreString("constrained") : localizedStoreString("unconstrained")
        let expensive = isExpensiveNetwork ? localizedStoreString("expensive") : localizedStoreString("non-expensive")
        return AppLocalization.format(
            "Network: %@, %@, %@", reachability, constrained, expensive
        )
    }
    func exportOperationalLogsText(events: [DiagnosticLog]? = nil) -> String {
        diagnostics.exportOperationalLogsText(networkSyncStatusText: networkSyncStatusText, events: events)
    }
    func appendOperationalLog(
        _ level: DiagnosticLogLevel, category: String, message: String, chainId: String? = nil, walletId: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level, category: category, message: message, chainId: chainId, walletId: walletId, transactionHash: transactionHash,
            source: source, metadata: metadata
        )
    }
    func noteSendBroadcastQueued(for transaction: TransactionRecord) {
        appendOperationalLog(
            .info, category: "Broadcast", message: "\(transaction.symbol) send broadcast accepted.",
            chainId: transaction.chainId, transactionHash: transaction.transactionHash
        )
    }

    func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        AppLocalization.format(
            "%@ transaction appears stuck and could not be confirmed after extended retries.", transaction.chainName
        )
    }
    // Core owns the confirmation-poll backoff table, the fetch and the store.
    // What is left on this side is the two things a platform has: the localized
    // text of an operational event, and a notification.

    /// Deliver native effects after the caller adopts the transaction projection.
    func deliverPendingStatusChanges(_ changes: [TransactionStatusChange]) async {
        for change in changes where change.statusChanged {
            guard let transaction = try? await bridge.transaction(id: change.id) else { continue }
            switch change.newStatus {
            case .confirmed:
                appendOperationalLog(
                    .info, category: "Transaction Status",
                    message: localizedStoreString("Transaction confirmed on-chain."),
                    chainId: change.chainId, transactionHash: change.transactionHash)
            case .failed:
                appendOperationalLog(
                    .error, category: "Transaction Status",
                    message: statusPollFailedEventMessage(for: transaction),
                    chainId: change.chainId, transactionHash: change.transactionHash)
            case .pending: break
            }
            sendTransactionStatusNotification(for: transaction, newStatus: change.newStatus)
            await finishSendLiveActivity(for: transaction, newStatus: change.newStatus)
        }
    }

    // Localized messages shared by all chains.
    private func statusPollFailedEventMessage(for transaction: TransactionRecord) -> String {
        transaction.localizedFailureReason ?? statusPollFailureMessage(for: transaction)
    }

    func editPriceAlert(_ command: StateCommand) async throws {
        let transition = try await self.bridge.applyStateCommand(command)
        applyCoreState(transition.state)
        for case .priceAlertRejected(let reason) in transition.events {
            throw NSError(domain: "PriceAlert", code: 1,
                userInfo: [NSLocalizedDescriptionKey: priceAlertRejectionMessage(reason)])
        }
    }
    /// Localize core's typed reason.
    func priceAlertRejectionMessage(_ reason: PriceAlertRejection) -> String {
        switch reason {
        case .missingCurrencyRate:
            return localizedStoreString("Exchange rates for this currency have not loaded yet. Try again shortly.")
        case .invalidTarget: return localizedStoreString("Enter a target price above zero.")
        case .unknownAsset: return localizedStoreString("This asset is no longer in your wallets.")
        case .duplicateAlert: return localizedStoreString("An identical alert already exists.")
        case .alertNotFound: return localizedStoreString("This alert no longer exists.")
        }
    }
}
