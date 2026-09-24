import XCTest
@testable import Spectra

@MainActor
final class SendAmountBridgeTests: IsolatedAppStateTestCase {

    func testQuoteCannotBeReusedForAnotherWalletHoldingOrNetwork() {
        let store = SendPreviewStore()
        let preview = SendPreview.solana(preview: SolanaSendPreview(
            estimatedNetworkFee: 0.000005, spendableBalance: 1, feeRateDescription: nil,
            estimatedTransactionBytes: nil, selectedInputCount: nil, usesChangeOutput: nil, maxSendable: 0.999995))
        let quote = OwnedSendPreview(walletId: "w", holdingKey: "solana:native", chainId: "solana", amount: "1",
            preview: preview, networkFee: "0.000005", networkFeeValue: nil, amountValue: nil,
            details: nil, shortcuts: [100: "0.999994999"], recipient: nil)
        store.apply(quote)
        let sol = Coin.fixture(name: "Solana", symbol: "SOL", chainId: "solana", amount: "1")
        XCTAssertEqual(store.quote(walletId: "w", coin: sol)?.shortcuts[100], "0.999994999")
        XCTAssertNil(store.quote(walletId: "other", coin: sol))
        let token = Coin.fixture(name: "Other", symbol: "OTH", chainId: "solana", tokenStandard: "SPL",
            contractAddress: "other", amount: "1")
        XCTAssertNil(store.quote(walletId: "w", coin: token))
        // The same asset on another network is another holding.
        let devnet = Coin.fixture(name: "Solana", symbol: "SOL", chainId: "solana-devnet", amount: "1")
        XCTAssertNil(store.quote(walletId: "w", coin: devnet))
        store.reset()
        XCTAssertNil(store.quote(walletId: "w", coin: sol))
    }

    func testShortcutIsFlooredExactlyAcrossBinding() {
        XCTAssertEqual(sendAmountShortcut(maximum: "0.99999", decimals: 8, percentage: 100), "0.99999")
        XCTAssertEqual(sendAmountShortcut(maximum: "0.123456789", decimals: 8, percentage: 10), "0.01234567")
        XCTAssertNil(sendAmountShortcut(maximum: "NaN", decimals: 8, percentage: 100))
        XCTAssertFalse(isValidAmountInput(text: "340282366920938463463374607431768211456", maxDecimals: 0))
        XCTAssertTrue(isValidAmountInput(text: "1.5", maxDecimals: 8))
    }

    func testInvalidExactAmountIsRefusedBeforeSigningMaterialAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        for amount in ["0.000000001", "-1", "NaN", "1.é"] {
            let request = SendExecutionRequest(
                chainId: "bitcoin", walletId: "missing", password: nil, toAddress: "",
                amountStr: amount, contractAddress: nil, tokenDecimals: nil,
                feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil,
                evmOverrides: nil, moneroPriority: nil
            )
            do {
                _ = try await service.executeSend(request: request)
                XCTFail("Invalid amount must fail")
            } catch SpectraBridgeError.InvalidInput {
                // Validation precedes missing signing material and network access.
            } catch {
                XCTFail("Expected an amount validation error, got \(error)")
            }
        }
    }
    func testMissingWalletIsRefusedBeforeSecretStoreOrNetwork() async throws {
        let service = try WalletService(endpoints: [])
        let request = SendExecutionRequest(
            chainId: "ethereum", walletId: "missing", password: nil,
            toAddress: "0x9858effd232b4033e47d90003d41ec34ecaeda94", amountStr: "1",
            contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil,
            gasBudget: nil, feeAmount: nil, evmOverrides: nil, moneroPriority: nil
        )
        do {
            _ = try await service.executeSend(request: request)
            XCTFail("Missing wallet must fail")
        } catch {
            XCTAssertTrue(String(describing: error).contains("wallet does not exist"))
        }
    }

    func testOwnedPreviewRefusesMissingWalletAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.previewOwnedSend(walletId: "missing", holdingKey: "ethereum:native", amount: "1", destination: "", explicitNonce: nil, customFees: nil)
            XCTFail("A missing wallet must not produce a preview")
        } catch {
            XCTAssertTrue(String(describing: error).contains("wallet does not exist"))
        }
    }

    func testMissingReviewIsRefusedAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.executeOwnedSend(reviewId: "missing", input: SendReviewInput(
                walletId: "w", holdingKey: "ethereum:native", amount: "1", destination: "0x1111111111111111111111111111111111111111", overrides: nil), password: nil)
            XCTFail("sending requires a core-issued review")
        } catch {
            XCTAssertTrue(String(describing: error).contains("review missing"))
        }
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
