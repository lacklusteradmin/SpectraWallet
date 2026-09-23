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
        _ level: DiagnosticLogLevel, category: String, message: String, chainName: String? = nil, walletId: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level, category: category, message: message, chainName: chainName, walletId: walletId, transactionHash: transactionHash,
            source: source, metadata: metadata
        )
    }
    func appendChainOperationalEvent(
        _ level: DiagnosticLogLevel, chainName: String, message: String, transactionHash: String? = nil
    ) {
        appendOperationalLog(
            level, category: "\(chainName) Broadcast", message: message, chainName: chainName, transactionHash: transactionHash
        )
    }
    func noteSendBroadcastQueued(for transaction: TransactionRecord) {
        appendChainOperationalEvent(
            .info, chainName: transaction.chainName, message: "\(transaction.symbol) send broadcast accepted.",
            transactionHash: transaction.transactionHash
        )
    }
    func noteSendBroadcastFailure(for chainName: String, message: String) {
        appendChainOperationalEvent(.error, chainName: chainName, message: "Send failed: \(message)")
    }

    func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        AppLocalization.format(
            "%@ transaction appears stuck and could not be confirmed after extended retries.", transaction.chainName
        )
    }
    // Core owns the confirmation-poll backoff table, the fetch and the store.
    // What is left on this side is the two things a platform has: the localized
    // text of an operational event, and a notification.

    /// Adopt core's outcome and emit localized operational text and notifications.
    func applyPendingStatusChanges(_ changes: [TransactionStatusChange]) async {
        let oldById = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })

        await refreshTransactionProjection()

        for change in changes {
            let id = change.id
            let transaction = (try? await self.bridge.transaction(id: id)) ?? oldById[id]
            guard let transaction else { continue }
            if change.statusChanged {
                switch change.newStatus {
                case .confirmed:
                    appendChainOperationalEvent(
                        .info, chainName: change.chainName,
                        message: localizedStoreString("Transaction confirmed on-chain."),
                        transactionHash: change.transactionHash)
                case .failed:
                    appendChainOperationalEvent(
                        .error, chainName: change.chainName,
                        message: statusPollFailedEventMessage(for: transaction),
                        transactionHash: change.transactionHash)
                case .pending: break
                }
                sendTransactionStatusNotification(for: transaction, newStatus: change.newStatus)
                await finishSendLiveActivity(for: transaction, newStatus: change.newStatus)
            }
            if let confirmations = change.reachedFinalityConfirmations {
                appendChainOperationalEvent(
                    .info, chainName: change.chainName,
                    message: AppLocalization.format(
                        "Transaction reached finality (%d confirmations).", Int(confirmations)),
                    transactionHash: change.transactionHash)
            }
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
