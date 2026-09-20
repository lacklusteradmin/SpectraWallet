import XCTest

@testable import Spectra

/// The composer's destination field, across the binding.
///
/// The rule about which chains look a `.eth` name up used to be
/// `chainName == "Ethereum"` in three Swift call sites; it is
/// `Chain::resolves_ens_names` behind one async export now. An async export is
/// the one thing the CLI cannot vouch for — a missing Tokio runtime fails only
/// here — so this exercises the refusals and the plain answer with no
/// endpoints configured, which is to say without a request leaving the machine.
final class SendDestinationBridgeTests: XCTestCase {
    func testATypedAddressResolvesToItsNormalizedFormAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        let resolved = try await service.resolveSendDestination(
            chainId: "base", input: "  0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA  ")
        XCTAssertEqual(resolved.address, "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertFalse(resolved.usedEns, "nothing was looked up")
    }

    func testAnEmptyDestinationIsRefusedRatherThanResolvedToNothing() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.resolveSendDestination(chainId: "ethereum", input: "   ")
            XCTFail("An empty field is not an address")
        } catch SpectraBridgeError.InvalidInput(let message) {
            XCTAssertTrue(message.contains("Ethereum"), "got \(message)")
        }
    }

    /// The probe is named by wallet and holding, and refuses one it cannot
    /// find rather than probing something else. The composer used to name the
    /// token itself and showed no verdict at all when it could not identify
    /// one, which reads as "checked, and fine".
    func testAProbeForAnUnknownHoldingThrowsRatherThanProbingAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.sendDestinationRisk(
                walletId: "no-such-wallet", holdingKey: "Ethereum|ETH",
                destinationInput: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e")
            XCTFail("A holding core does not have is not a verdict")
        } catch SpectraBridgeError.InvalidInput(let message) {
            // Refused before any endpoint is consulted, which is why a service
            // with none can prove it.
            XCTAssertTrue(message.contains("Ethereum|ETH"), "got \(message)")
        }
    }

    func testPendingPollingPropagatesUnopenedStorageAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.pollPendingTransactions(chainId: "ethereum")
            XCTFail("Unopened storage must not appear as no pending transactions")
        } catch SpectraBridgeError.Failure { }
    }

    func testReviewedDestinationMustStillMatchAcrossBinding() async throws {
        let service = try WalletService(endpoints: [])
        let old = "0x1111111111111111111111111111111111111111"
        let new = "0x2222222222222222222222222222222222222222"
        let same = try await service.verifySendDestination(chainId: "ethereum", input: old, expectedAddress: old)
        XCTAssertEqual(same.address, old)
        do {
            _ = try await service.verifySendDestination(chainId: "ethereum", input: new, expectedAddress: old)
            XCTFail("A changed destination must require a new review")
        } catch SpectraBridgeError.InvalidInput(let message) {
            XCTAssertTrue(message.contains("Review"))
        }
    }

}
