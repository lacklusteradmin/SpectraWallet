import XCTest
@testable import Spectra

@MainActor
final class SendAmountBridgeTests: IsolatedAppStateTestCase {

    func testFeeAdjustedShortcutIsFlooredAcrossBinding() {
        XCTAssertEqual(sendAmountShortcut(maximum: 0.99999, decimals: 8, percentage: 100), "0.99998999")
        XCTAssertNil(sendAmountShortcut(maximum: .infinity, decimals: 8, percentage: 100))
        XCTAssertNil(quotedSendAmount(preview: nil, chainName: "Bitcoin", isNative: true, tokenDecimals: nil, percentage: 100))
        XCTAssertNil(parseAmountInput(text: "340282366920938463463374607431768211456", maxDecimals: 0))
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
            { $0.sendWalletID = "other" }, { $0.sendHoldingKey = "other" },
            { $0.sendAmount = "2" }, { $0.sendAddress = "other" },
            { $0.evmManualNonceEnabled.toggle() }, { $0.evmManualNonce = "invalid" },
            { $0.useCustomEvmFees.toggle() }, { $0.customEvmMaxFeeGwei = "invalid" },
            { $0.customEvmPriorityFeeGwei = "invalid" },
            { $0.sendPreviewRequestID = UUID() },
        ]
        for edit in edits {
            let input = store.sendPreviewInputSnapshot
            let request = store.sendPreviewRequestID
            edit(store)
            store.sendError = "current form message"
            store.adoptSendPreviewResult(.failure(NSError(domain: "old", code: 1)),
                requestID: request, input: input, chainName: "Ethereum")
            XCTAssertEqual(store.sendError, "current form message")
            store.adoptSendPreviewResult(.success(nil), requestID: request, input: input, chainName: "Ethereum")
            XCTAssertEqual(store.sendError, "current form message")
        }
        store.adoptSendPreviewResult(.failure(NSError(domain: "current", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "current failure"])),
            requestID: store.sendPreviewRequestID, input: store.sendPreviewInputSnapshot, chainName: "Ethereum")
        XCTAssertEqual(store.sendError, "current failure")
        let oldRequest = store.sendPreviewRequestID
        store.cancelSend()
        XCTAssertNotEqual(store.sendPreviewRequestID, oldRequest)
    }

}
