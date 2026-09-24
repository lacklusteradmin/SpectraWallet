import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra

    /// Which pending sends can still be replaced is core's rule, and this is it
    /// crossing the binding.
    ///
    /// The rule used to be two filters in `AppState` over its own transaction
    /// projection, and both spelled the chain as the string `"Ethereum"` — so a
    /// pending send on any of the other EVM chains offered neither speed-up nor
    /// cancel, and a pending *token* send offered a speed-up that would have
    /// composed a native transfer of the token's amount.
    @MainActor
    final class ReplaceableSendBridgeTests: IsolatedAppStateTestCase {

        func testReplacementFieldsCrossTheAsyncBridge() async throws {
            let wallet = WalletView(name: "Main", chainId: "arbitrum", addresses: ["arbitrum": "0x1111111111111111111111111111111111111111"])
            _ = try await bridge.applyStateCommand(.upsertWallet(wallet: wallet.walletState()))
            let record = TransactionRecord(
                id: UUID().uuidString, walletId: wallet.id, deploymentId: "arbitrum:native",
                kind: .send, status: .pending, walletName: "Main", assetDisplayName: "Arbitrum",
                symbol: "ETH", chainId: "arbitrum", amount: "1.5",
                address: "0x1111111111111111111111111111111111111111",
                transactionHash: "0xfeed", nonce: 7)
            _ = try await bridge.applyTransactionCommand(.upsert(records: [record]))
            let sends = try await bridge.transactionSnapshot().replaceable
            XCTAssertEqual(sends.count, 1)
            let arbitrum = try XCTUnwrap(sends.first)
            XCTAssertEqual(arbitrum.chainId, "arbitrum")
            XCTAssertEqual(arbitrum.transactionId, record.id)
            XCTAssertEqual(arbitrum.recordedNonce, 7)
            XCTAssertEqual(arbitrum.transactionHash, "0xfeed")
            XCTAssertTrue(arbitrum.canSpeedUp)
        }

    }
#endif
