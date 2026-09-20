import ActivityKit
import Foundation
struct SendTransactionLiveActivityAttributes: ActivityAttributes {
    /// The `TransactionRecord.id` this activity is reporting on.
    ///
    /// ActivityKit hands back running activities but not a way to label them,
    /// so the identity travels in the attributes: `Activity.activities` is then
    /// enough to find the one activity a status change concerns, and it still
    /// works after a relaunch, when no Swift-side handle survived.
    let transactionId: String

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case sending
            case complete
            case failed
        }
        var phase: Phase
        var walletName: String
        var chainName: String
        var symbol: String
        var amountText: String
        var statusText: String
        var detailText: String
        var destinationPreview: String
        var transactionHashPreview: String?
        var startedAt: Date
    }
}
