import Foundation
import XCTest

@testable import Spectra

/// What the send Live Activity says, for each status core can report.
///
/// The activity's lifecycle needs a device to observe, but the content is a
/// pure function of the record and the phase, which is the part that decides
/// whether a glance at the lock screen tells the truth.
final class SendLiveActivityContentTests: XCTestCase {
    private func record(
        status: TransactionStatus = .pending,
        transactionHash: String? = nil,
        failureReason: String? = nil
    ) -> TransactionRecord {
        TransactionRecord(
            kind: .send, status: status, walletName: "Main", assetDisplayName: "Ether",
            symbol: "ETH", chainName: "Ethereum", amount: 1.5,
            address: "0x1234567890abcdef1234567890abcdef12345678",
            transactionHash: transactionHash, failureReason: failureReason)
    }

    func testEachPhaseNamesItselfAndTheChain() {
        let sending = sendLiveActivityContentState(
            for: record(), phase: .sending, amountText: "1.5")
        XCTAssertEqual(sending.statusText, "Sending")
        XCTAssertTrue(
            sending.detailText.contains("Ethereum"), "the wait names the chain being waited on")

        let complete = sendLiveActivityContentState(
            for: record(status: .confirmed), phase: .complete, amountText: "1.5")
        XCTAssertEqual(complete.statusText, "Sent")
        XCTAssertTrue(complete.detailText.contains("Ethereum"))

        let failed = sendLiveActivityContentState(
            for: record(status: .failed), phase: .failed, amountText: "1.5")
        XCTAssertEqual(failed.statusText, "Send failed")
    }

    /// A failure the chain explained is more use than the generic sentence.
    func testAFailureReasonBeatsTheGenericLine() {
        let explained = record(status: .failed, failureReason: "stuckAfterRetries")
        let generic = record(status: .failed)
        let withReason = sendLiveActivityContentState(
            for: explained, phase: .failed, amountText: "1.5")
        let withoutReason = sendLiveActivityContentState(
            for: generic, phase: .failed, amountText: "1.5")
        XCTAssertEqual(withReason.detailText, explained.localizedFailureReason)
        XCTAssertNotEqual(withReason.detailText, withoutReason.detailText)
    }

    /// The symbol has its own label in the widget, so the amount arrives alone.
    func testTheAmountCarriesNoSymbolAndTheSymbolIsItsOwnField() {
        let state = sendLiveActivityContentState(for: record(), phase: .sending, amountText: "1.5")
        XCTAssertEqual(state.amountText, "1.5")
        XCTAssertEqual(state.symbol, "ETH")
    }

    func testLongIdentifiersKeepBothEndsAndShortOnesAreLeftAlone() {
        XCTAssertEqual(sendLiveActivityPreview("0xabc", keepingEachEnd: 6), "0xabc")
        XCTAssertEqual(
            sendLiveActivityPreview("0x1234567890abcdef1234567890abcdef12345678", keepingEachEnd: 6),
            "0x1234…345678")
    }

    func testTheHashAppearsOnlyOnceThereIsOne() {
        XCTAssertNil(
            sendLiveActivityContentState(for: record(), phase: .sending, amountText: "1.5")
                .transactionHashPreview)
        let broadcast = record(transactionHash: "0xfeedfacefeedfacefeedfacefeedfacefeedface")
        XCTAssertEqual(
            sendLiveActivityContentState(for: broadcast, phase: .complete, amountText: "1.5")
                .transactionHashPreview, "0xfeedfa…feedface")
    }

    /// The lock screen runs a timer off `startedAt`, so it has to be the send's
    /// own clock rather than the moment the phase last changed.
    func testTheTimerRunsFromTheTransactionsOwnStart() {
        let transaction = record()
        for phase in [
            SendTransactionLiveActivityAttributes.ContentState.Phase.sending, .complete, .failed,
        ] {
            XCTAssertEqual(
                sendLiveActivityContentState(for: transaction, phase: phase, amountText: "1.5")
                    .startedAt, transaction.createdAt)
        }
    }
}
