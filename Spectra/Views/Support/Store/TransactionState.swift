import Foundation
import Combine

final class WalletTransactionState: ObservableObject {
    @Published var transactions: [TransactionRecord] = [] {
        didSet {
            transactionRevision &+= 1
        }
    }
    @Published var normalizedHistoryIndex: [NormalizedHistoryEntry] = [] {
        didSet {
            normalizedHistoryRevision &+= 1
        }
    }
    @Published private(set) var transactionRevision: UInt64 = 0
    @Published private(set) var normalizedHistoryRevision: UInt64 = 0
    var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    var firstActivityDateByWalletID: [UUID: Date] = [:]
    var lastNormalizedHistorySignature: Int?
    var suppressSideEffects = false
    var lastObservedTransactions: [TransactionRecord] = []
}
