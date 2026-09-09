import XCTest
@testable import Spectra

final class SendAmountBridgeTests: XCTestCase {
    func testInvalidExactAmountIsRefusedBeforeSigningMaterialAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
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
        let service = try WalletService.newTyped(endpoints: [])
        let request = SendExecutionRequest(
            chainId: "ethereum", walletId: "missing", password: nil,
            toAddress: "0x9858effd232b4033e47d90003d41ec34ecaeda94", amountStr: "1",
            contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil,
            gasBudget: nil, feeAmount: nil, evmOverrides: nil, moneroPriority: nil
        )
        do {
            _ = try await service.executeSend(request: request)
            XCTFail("Missing wallet must fail")
        } catch SpectraBridgeError.InvalidInput(let message) {
            XCTAssertTrue(message.contains("wallet does not exist"))
        }
    }

    func testInvalidKeypoolBaselineThrowsAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
        // Inject an out-of-range in-memory record to exercise the throwing read.
        try await service.registerOwnedAddress(
            walletId: "fault", chainName: "Bitcoin", address: "fixture",
            derivationPath: nil, branch: "external", branchIndex: Int64.max)
        do {
            _ = try await service.keypoolState(walletId: "fault", chainName: "Bitcoin")
            XCTFail("An invalid baseline must not become index zero")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("index out of range"))
        }
        do {
            _ = try await service.reserveReceiveIndex(walletId: "fault", chainName: "Bitcoin", minimumIndex: 1)
            XCTFail("Cannot reserve from an invalid baseline")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("index out of range"))
        }
    }

    func testUnavailableEvmPreviewDoesNotReturnDefaults() async throws {
        let service = try WalletService.newTyped(endpoints: [])
        do {
            _ = try await service.fetchEvmSendPreviewTyped(
                chainId: "ethereum", from: "from", to: "to", valueWei: "1", dataHex: "0x", explicitNonce: nil, customFees: nil)
            XCTFail("Unavailable RPCs must not produce a default preview")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("no endpoints configured"))
        }
    }

}
