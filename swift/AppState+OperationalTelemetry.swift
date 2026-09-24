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
    /// Log a failure on this side of the boundary — a platform API, or a call
    /// into core that threw. Core logs the work it performs itself.
    func appendOperationalLog(
        _ level: DiagnosticLogLevel, category: String, message: String, chainId: String? = nil, walletId: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level, category: category, message: message, chainId: chainId, walletId: walletId, transactionHash: transactionHash,
            source: source, metadata: metadata
        )
    }
    // Core owns the confirmation-poll backoff table, the fetch, the store and
    // the log line. What is left on this side is what a platform has: a
    // notification and a Live Activity.

    /// Deliver native effects after the caller adopts the transaction projection.
    func deliverPendingStatusChanges(_ changes: [TransactionStatusChange]) async {
        for change in changes where change.statusChanged {
            guard let transaction = try? await bridge.ready().transaction(id: change.id) else { continue }
            sendTransactionStatusNotification(for: transaction, newStatus: change.newStatus)
            await finishSendLiveActivity(for: transaction, newStatus: change.newStatus)
        }
    }

    func editPriceAlert(_ command: StateCommand) async throws {
        let transition = try await applyStateCommand(command)
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
