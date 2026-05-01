import ActivityKit
import Foundation
@MainActor
final class SendTransactionLiveActivityManager {
    static let shared = SendTransactionLiveActivityManager()
    private var currentActivity: Activity<SendTransactionLiveActivityAttributes>?
    private init() {}
    func startSending(walletName: String, chainName: String, symbol: String, amountText: String, destinationAddress: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let currentActivity {
            await currentActivity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
        let attributes = SendTransactionLiveActivityAttributes()
        let startedAt = Date()
        let content = ActivityContent<SendTransactionLiveActivityAttributes.ContentState>(
            state: SendTransactionLiveActivityAttributes.ContentState(
                phase: .sending, walletName: walletName, chainName: chainName, symbol: symbol, amountText: amountText,
                statusText: "Broadcasting", detailText: "Sending to \(previewText(for: destinationAddress))",
                destinationPreview: previewText(for: destinationAddress), transactionHashPreview: nil, startedAt: startedAt
            ), staleDate: Date().addingTimeInterval(300), relevanceScore: 100
        )
        do {
            currentActivity = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard)
        } catch {
            currentActivity = nil
        }
    }
    func complete(
        walletName: String, transactionHash: String?, chainName: String, symbol: String, amountText: String, destinationAddress: String
    ) async {
        guard let currentActivity else { return }
        let content = ActivityContent<SendTransactionLiveActivityAttributes.ContentState>(
            state: SendTransactionLiveActivityAttributes.ContentState(
                phase: .complete, walletName: walletName, chainName: chainName, symbol: symbol, amountText: amountText,
                statusText: "Broadcast Sent",
                detailText: transactionHash.flatMap { "Hash \(previewText(for: $0))" } ?? "Waiting for network indexing",
                destinationPreview: previewText(for: destinationAddress), transactionHashPreview: previewText(for: transactionHash),
                startedAt: currentActivity.content.state.startedAt
            ), staleDate: Date().addingTimeInterval(90), relevanceScore: 100
        )
        await currentActivity.update(content)
        await currentActivity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20)))
        self.currentActivity = nil
    }
    func fail(message: String?) async {
        guard let currentActivity else { return }
        let currentState = currentActivity.content.state
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detailText =
            trimmedMessage.isEmpty
            ? "The send flow was cancelled before broadcast finished." : previewText(for: trimmedMessage, maxLength: 54)
        let content = ActivityContent<SendTransactionLiveActivityAttributes.ContentState>(
            state: SendTransactionLiveActivityAttributes.ContentState(
                phase: .failed, walletName: currentState.walletName, chainName: currentState.chainName, symbol: currentState.symbol,
                amountText: currentState.amountText, statusText: trimmedMessage.isEmpty ? "Send Cancelled" : "Send Failed",
                detailText: detailText, destinationPreview: currentState.destinationPreview, transactionHashPreview: nil,
                startedAt: currentState.startedAt
            ), staleDate: Date().addingTimeInterval(20), relevanceScore: 1
        )
        await currentActivity.update(content)
        await currentActivity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(8)))
        self.currentActivity = nil
    }
    private func previewText(for value: String?, maxLength: Int = 18) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Unknown" }
        if trimmed.count <= maxLength { return trimmed }
        let leadingCount = max(6, maxLength / 2 - 1)
        let trailingCount = max(4, maxLength - leadingCount - 1)
        return "\(trimmed.prefix(leadingCount))…\(trimmed.suffix(trailingCount))"
    }
}
