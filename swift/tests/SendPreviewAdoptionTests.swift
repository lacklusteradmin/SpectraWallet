import XCTest
@testable import Spectra

@MainActor
final class SendPreviewAdoptionTests: IsolatedAppStateTestCase {

    func testQuoteCannotBeReusedForAnotherWalletHoldingOrNetwork() {
        let store = SendPreviewStore()
        let preview = SendPreview.solana(preview: SolanaSendPreview(
            estimatedNetworkFee: "0.000005", spendableBalance: "1", feeRateDescription: nil,
            estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: "0.999995"))
        let quote = OwnedSendPreview(walletId: "w", holdingKey: "solana:native", chainId: Chain.solana, amount: "1",
            preview: preview, networkFee: "0.000005", networkFeeValue: nil, amountValue: nil,
            details: nil, shortcuts: [100: "0.999994999"], recipient: nil)
        store.apply(quote)
        let sol = Coin.fixture(name: "Solana", symbol: "SOL", chainId: Chain.solana, amount: "1")
        XCTAssertEqual(store.quote(walletId: "w", coin: sol)?.shortcuts[100], "0.999994999")
        XCTAssertNil(store.quote(walletId: "other", coin: sol))
        let token = Coin.fixture(name: "Other", symbol: "OTH", chainId: Chain.solana, tokenStandard: "SPL",
            contractAddress: "other", amount: "1")
        XCTAssertNil(store.quote(walletId: "w", coin: token))
        // The same asset on another network is another holding.
        let devnet = Coin.fixture(name: "Solana", symbol: "SOL", chainId: Chain.solanaDevnet, amount: "1")
        XCTAssertNil(store.quote(walletId: "w", coin: devnet))
        store.reset()
        XCTAssertNil(store.quote(walletId: "w", coin: sol))
    }

    func testPreviewDiscardsStaleSuccessAndFailureForEveryFormEdit() {
        let store = makeState()
        let edits: [(AppState) -> Void] = [
            { $0.sendFlow.walletId = "other" }, { $0.sendFlow.holdingKey = "other" },
            { $0.sendFlow.amount = "2" }, { $0.sendFlow.address = "other" },
            { $0.sendFlow.evmManualNonceEnabled.toggle() }, { $0.sendFlow.evmManualNonce = "invalid" },
            { $0.sendFlow.useCustomEvmFees.toggle() }, { $0.sendFlow.customEvmMaxFeeGwei = "invalid" },
            { $0.sendFlow.customEvmPriorityFeeGwei = "invalid" },
            { $0.sendFlow.previewRequestId = UUID() },
        ]
        for edit in edits {
            let input = store.sendPreviewInputSnapshot
            let request = store.sendFlow.previewRequestId
            edit(store)
            store.sendFlow.error = "current form message"
            store.adoptSendPreviewResult(.failure(NSError(domain: "old", code: 1)),
                requestId: request, input: input)
            XCTAssertEqual(store.sendFlow.error, "current form message")
            store.adoptSendPreviewResult(.success(nil), requestId: request, input: input)
            XCTAssertEqual(store.sendFlow.error, "current form message")
        }
        store.adoptSendPreviewResult(.failure(NSError(domain: "current", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "current failure"])),
            requestId: store.sendFlow.previewRequestId, input: store.sendPreviewInputSnapshot)
        XCTAssertEqual(store.sendFlow.error, "current failure")
        let oldRequest = store.sendFlow.previewRequestId
        store.cancelSend()
        XCTAssertNotEqual(store.sendFlow.previewRequestId, oldRequest)
    }

}
