import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshPendingEVMTransactions(chainName: String) async {
        let now = Date()
        guard let chainId = SpectraChainID.id(for: chainName) else { return }
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }
        guard !pendingTransactions.isEmpty else { return }
        var resolvedClassifications: [UUID: (TransactionStatus, EvmReceiptClassification)] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                guard let receiptJSON = try await WalletServiceBridge.shared.fetchEVMReceiptJSON(
                    chainId: chainId, txHash: transactionHash
                ) else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                    continue
                }
                guard let classified = classifyEvmReceiptJson(json: receiptJSON) else {
                    throw NSError(domain: "EvmReceipt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid receipt JSON"])
                }
                if classified.isConfirmed {
                    let resolvedStatus: TransactionStatus = classified.isFailed ? .failed : .confirmed
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                    resolvedClassifications[transaction.id] = (resolvedStatus, classified)
                } else { markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now) }
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }}
        let resolvedStatuses = resolvedClassifications.mapValues { resolvedStatus, classified in
            PendingTransactionStatusResolution(
                status: resolvedStatus, receiptBlockNumber: classified.blockNumber.map(Int.init), confirmations: nil, dogecoinNetworkFeeDoge: nil
            )
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }
}
