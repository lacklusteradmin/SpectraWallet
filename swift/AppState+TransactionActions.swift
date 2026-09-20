import Foundation

@MainActor
extension AppState {
    func retryUTXOTransactionStatus(for transactionID: String) async -> String {
        do {
            let change = try await self.bridge.recheckTransactionStatus(id: transactionID)
            await applyPendingStatusChanges([change])
            if change.statusChanged {
                return AppLocalization.format("Status updated: %@.", change.newStatus.localizedTitle)
            }
            if change.newStatus == .pending { return AppLocalization.string("No confirmation yet. Spectra will keep retrying automatically.") }
            return AppLocalization.string("Transaction is confirmed.")
        } catch {
            let message = String(describing: error)
            appendOperationalLog(.error, category: "Pending Transactions", message: message)
            return message
        }
    }
    func rebroadcastSignedTransaction(for transactionID: String) async -> String {
        guard await authenticateForSensitiveAction(reason: AppLocalization.string("Authorize transaction rebroadcast")) else {
            return sendError ?? AppLocalization.string("Authentication failed.")
        }
        do {
            let transactionHash = try await self.bridge.rebroadcastTransaction(id: transactionID)
            await refreshTransactionProjection()
            return AppLocalization.format("Transaction rebroadcasted: %@. Network confirmation is pending.", transactionHash)
        } catch {
            return error.localizedDescription
        }
    }
}
