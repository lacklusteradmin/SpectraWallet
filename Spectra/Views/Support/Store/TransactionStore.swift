import Foundation

extension WalletStore {
    var transactions: [TransactionRecord] {
        get { transactionState.transactions }
        set { transactionState.transactions = newValue }
    }

    var normalizedHistoryIndex: [NormalizedHistoryEntry] {
        get { transactionState.normalizedHistoryIndex }
        set { transactionState.normalizedHistoryIndex = newValue }
    }

    var cachedTransactionByID: [UUID: TransactionRecord] {
        get { transactionState.cachedTransactionByID }
        set { transactionState.cachedTransactionByID = newValue }
    }

    var cachedFirstActivityDateByWalletID: [UUID: Date] {
        get { transactionState.firstActivityDateByWalletID }
        set { transactionState.firstActivityDateByWalletID = newValue }
    }

    func firstActivityDate(for walletID: UUID) -> Date? {
        cachedFirstActivityDateByWalletID[walletID]
    }

    @discardableResult
    func setTransactionsIfChanged(_ newTransactions: [TransactionRecord]) -> Bool {
        guard !transactionSnapshotsMatch(transactions, newTransactions) else { return false }
        transactions = newTransactions
        return true
    }

    private func transactionSnapshotsMatch(_ lhs: [TransactionRecord], _ rhs: [TransactionRecord]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.persistedSnapshot == $1.persistedSnapshot }
    }
}
