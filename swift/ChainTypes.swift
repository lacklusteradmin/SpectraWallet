import Foundation

nonisolated extension NetworkChoice: Identifiable {
    public var id: String { chainId }
}

// MARK: - Transactions & price alerts (Rust-owned enums)

typealias TransactionStatus = CoreTransactionStatus
typealias PriceAlertCondition = CorePriceAlertCondition
extension CorePriceAlertCondition {
    static let allCases: [CorePriceAlertCondition] = [.above, .below]
}
