import Foundation

@MainActor
extension AppState {
    func retryUTXOTransactionStatus(for transactionId: String) async -> String {
        do {
            let change = try await self.bridge.ready().recheckTransactionStatus(transactionId: transactionId)
            await refreshTransactionProjection()
            await deliverPendingStatusChanges([change])
            if change.statusChanged {
                return AppLocalization.format("Status updated: %@.", change.newStatus.localizedTitle)
            }
            if change.newStatus == .pending { return AppLocalization.string("No confirmation yet. Spectra will keep retrying automatically.") }
            return AppLocalization.string("Transaction is confirmed.")
        } catch {
            // Core logs the failed recheck.
            await diagnostics.loadFromSQLite()
            return error.localizedDescription
        }
    }
    func rebroadcastSignedTransaction(for transactionId: String) async -> String {
        if let failure = await authenticate(.send, reason: AppLocalization.string("Authorize transaction rebroadcast")) {
            return failure
        }
        do {
            let transactionHash = try await self.bridge.ready().rebroadcastTransaction(transactionId: transactionId)
            await refreshTransactionProjection()
            return AppLocalization.format("Transaction rebroadcasted: %@. Network confirmation is pending.", transactionHash)
        } catch {
            return error.localizedDescription
        }
    }
}
