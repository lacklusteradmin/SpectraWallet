import Foundation

// MARK: - Transactions & price alerts (Rust-owned enums)

typealias TransactionStatus = CoreTransactionStatus
typealias PriceAlertCondition = CorePriceAlertCondition
extension PriceAlertCondition {
    static let allCases: [PriceAlertCondition] = [.above, .below]
}
