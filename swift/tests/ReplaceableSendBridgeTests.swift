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
    final class ReplaceableSendBridgeTests: XCTestCase {
        override func setUp() async throws {
            try await super.setUp()
            _ = try await WalletServiceBridge.shared.openState()
            _ = try await WalletServiceBridge.shared.applyTransactionCommand(.clear)
        }

        override func tearDown() async throws {
            _ = try? await WalletServiceBridge.shared.applyTransactionCommand(.clear)
            try await super.tearDown()
        }

        func testUnopenedHistoryReadsThrowAcrossBinding() async throws {
            let service = try WalletService.newTyped(endpoints: [])
            let reads: [() async throws -> Void] = [
                { _ = try await service.normalizedHistory(unknownLabel: "Unknown") },
                { _ = try await service.earliestTransactionDates() },
                { _ = try await service.activeWalletTransactionIds() },
                { _ = try await service.replaceableSends() },
            ]
            for read in reads {
                do {
                    try await read()
                    XCTFail("An unopened history store must not return an empty success")
                } catch SpectraBridgeError.Failure(let message) {
                    XCTAssertTrue(message.contains("not opened"))
                }
            }
        }

        private func record(
            chain: String, symbol: String, kind: TransactionKind = .send,
            status: TransactionStatus = .pending, hash: String? = "0xfeed", nonce: Int? = 7
        ) -> TransactionRecord {
            TransactionRecord(
                walletID: "wallet-1", kind: kind, status: status, walletName: "Main",
                assetName: chain, symbol: symbol, chainName: chain, amount: 1.5,
                address: "0x1111111111111111111111111111111111111111",
                transactionHash: hash, ethereumNonce: nonce)
        }

        private func store(_ records: [TransactionRecord]) async throws {
            _ = try await WalletServiceBridge.shared.applyTransactionCommand(
                .upsert(records: records.map(\.persistedSnapshot)))
        }

        /// The family is the registry's, so a pending Arbitrum send replaces
        /// exactly the way a mainnet one does.
        func testEveryEVMChainOffersReplacementAndNothingElseDoes() async throws {
            try await store([
                record(chain: "Arbitrum", symbol: "ETH"),
                record(chain: "Base", symbol: "ETH"),
                record(chain: "Bitcoin", symbol: "BTC"),
                record(chain: "Solana", symbol: "SOL"),
            ])
            let sends = try await WalletServiceBridge.shared.replaceableSends()
            XCTAssertEqual(Set(sends.map(\.chainId)), ["arbitrum", "base"])
            let arbitrum = try XCTUnwrap(sends.first { $0.chainId == "arbitrum" })
            XCTAssertEqual(arbitrum.recordedNonce, 7)
            XCTAssertEqual(arbitrum.transactionHash, "0xfeed")
            XCTAssertTrue(arbitrum.canSpeedUp)
        }

        /// A token transfer cannot be rebuilt from its record, so it may be
        /// cancelled but not sped up. `ARB` is Arbitrum's own ticker while its
        /// gas is `ETH`, which is the pair that has to come apart.
        func testOnlyANativeTransferCanBeSpedUp() async throws {
            try await store([record(chain: "Arbitrum", symbol: "ARB")])
            let sends = try await WalletServiceBridge.shared.replaceableSends()
            let pending = try XCTUnwrap(sends.first)
            XCTAssertEqual(pending.symbol, "ARB")
            XCTAssertFalse(pending.canSpeedUp)
        }

        func testRowsWithNothingToReplaceAreNotOffered() async throws {
            try await store([
                record(chain: "Ethereum", symbol: "ETH", kind: .receive),
                record(chain: "Ethereum", symbol: "ETH", status: .confirmed),
                record(chain: "Ethereum", symbol: "ETH", status: .failed),
                record(chain: "Ethereum", symbol: "ETH", hash: nil),
            ])
            let sends = try await WalletServiceBridge.shared.replaceableSends()
            XCTAssertTrue(sends.isEmpty, "offered \(sends.map(\.transactionId))")
        }
    }
#endif
