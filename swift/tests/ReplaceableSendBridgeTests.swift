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
            let service = try WalletService(endpoints: [])
            let reads: [() async throws -> Void] = [
                { _ = try await service.historyPage(query: HistoryQuery(walletId: nil, filter: .all, search: "", oldestFirst: false, offset: 0, limit: 20)) },
                { _ = try await service.transactionSnapshot() },
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

        func testBoundedHistoryReadsRunThroughAsyncBinding() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let service = try WalletService(endpoints: [])
            _ = try await service.openState(databasePath: directory.appendingPathComponent("history.sqlite").path)
            let page = try await service.historyPage(query: HistoryQuery(
                walletId: nil, filter: .all, search: "", oldestFirst: false, offset: 0, limit: 20))
            XCTAssertTrue(page.records.isEmpty)
            XCTAssertFalse(page.hasMore)
            let summary = try await service.transactionSnapshot()
            XCTAssertEqual(summary.totalCount, 0)
            let missing = try await service.transaction(id: "missing")
            XCTAssertNil(missing)
        }

        func testPortfolioSnapshotRejectsADelayedOlderResult() async throws {
            let service = try WalletService(endpoints: [])
            let old = try await service.portfolioSnapshot()
            _ = try await service.applyStateCommand(command: .setFiatCurrency(currency: .eur))
            let new = try await service.portfolioSnapshot()
            let store = AppState(startServices: false)
            let olderRequest = store.beginCoreStateRead()
            let newerRequest = store.beginCoreStateRead()
            store.applyPortfolioSnapshot(new, epoch: newerRequest)
            store.applyPortfolioSnapshot(old, epoch: olderRequest)
            XCTAssertEqual(store.portfolioSnapshotRevision, new.revision)
            XCTAssertEqual(store.portfolioValuation?.currency, .eur)
            XCTAssertNil(store.portfolioValuation?.portfolio.fiatTotal)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
        }

        func testImportCompletionPreservesAPartialSuccessNotice() {
            let store = AppState(startServices: false)
            store.finishWalletImportFlow(notice: "Some addresses were refused")
            XCTAssertEqual(store.importError, "Some addresses were refused")
            XCTAssertFalse(store.isShowingWalletImporter)
            XCTAssertTrue(store.appNoticeItems.contains { $0.message == "Some addresses were refused" })
        }

        func testSnapshotCannotPartiallyOverwriteANewerStateCommand() async throws {
            let service = try WalletService(endpoints: [])
            let stale = try await service.portfolioSnapshot()
            let store = AppState(startServices: false)
            let oldRead = store.beginCoreStateRead()
            let transition = try await service.applyStateCommand(command: .setFiatCurrency(currency: .eur))
            store.applyCoreState(transition.state, epoch: store.beginCoreStateRead(), refreshPortfolio: false)
            store.applyPortfolioSnapshot(stale, epoch: oldRead)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
            XCTAssertNil(store.portfolioValuation)
            XCTAssertEqual(store.portfolioSnapshotRevision, 0)
        }

        func testRefreshFailureDoesNotClaimCompletion() {
            XCTAssertNotEqual(refreshOutcomeMessage(succeeded: false), refreshOutcomeMessage(succeeded: true))
            XCTAssertEqual(refreshOutcomeMessage(succeeded: false), AppLocalization.string("Refresh failed or completed partially. See refresh errors."))
        }

        private func record(
            chain: String, symbol: String, kind: TransactionKind = .send,
            status: TransactionStatus = .pending, deploymentID: String? = nil, hash: String? = "0xfeed", nonce: Int64? = 7
        ) -> TransactionRecord {
            TransactionRecord(
                id: UUID().uuidString,
                walletId: "wallet-1", deploymentId: deploymentID, kind: kind, status: status, walletName: "Main",
                assetDisplayName: chain, symbol: symbol, chainName: chain, amount: 1.5,
                address: "0x1111111111111111111111111111111111111111",
                transactionHash: hash, nonce: nonce)
        }

        private func store(_ records: [TransactionRecord]) async throws {
            _ = try await WalletServiceBridge.shared.applyTransactionCommand(
                .upsert(records: records))
        }

        /// The family is the registry's, so a pending Arbitrum send replaces
        /// exactly the way a mainnet one does.
        func testEveryEVMChainOffersReplacementAndNothingElseDoes() async throws {
            try await store([
                record(chain: "Arbitrum", symbol: "ETH", deploymentID: "arbitrum:native"),
                record(chain: "Base", symbol: "ETH", deploymentID: "base:native"),
                record(chain: "Bitcoin", symbol: "BTC"),
                record(chain: "Solana", symbol: "SOL"),
            ])
            let sends = try await WalletServiceBridge.shared.transactionSnapshot().replaceable
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
            let sends = try await WalletServiceBridge.shared.transactionSnapshot().replaceable
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
            let sends = try await WalletServiceBridge.shared.transactionSnapshot().replaceable
            XCTAssertTrue(sends.isEmpty, "offered \(sends.map(\.transactionId))")
        }
    }
#endif
