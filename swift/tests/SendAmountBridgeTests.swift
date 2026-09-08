import XCTest
@testable import Spectra

final class SendAmountBridgeTests: XCTestCase {
    func testInvalidExactAmountIsRefusedBeforeSigningMaterialAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
        for amount in ["0.000000001", "-1", "NaN", "1.é"] {
            let request = SendExecutionRequest(
                chainId: "bitcoin", chainName: "Bitcoin", derivationPath: "",
                seedPhrase: nil, privateKeyHex: nil, fromAddress: "", toAddress: "",
                amountStr: amount, contractAddress: nil, tokenDecimals: nil,
                feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil,
                evmOverrides: nil, moneroPriority: nil, derivationOverrides: nil
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
}
