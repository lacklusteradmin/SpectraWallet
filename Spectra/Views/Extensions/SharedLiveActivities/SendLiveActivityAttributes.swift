import ActivityKit
import Foundation

struct SendTransactionLiveActivityAttributes: ActivityAttributes {
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
