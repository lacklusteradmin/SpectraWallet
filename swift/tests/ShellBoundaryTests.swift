import XCTest
@testable import Spectra

@MainActor
final class ShellBoundaryTests: IsolatedAppStateTestCase {
    func testActivityReconciliationFindsOldRecordsAndKeepsReadFailures() async throws {
        let wallet = WalletView(name: "Archive", addresses: ["Ethereum": "0x1111111111111111111111111111111111111111"], familyName: "Ethereum")
        _ = try await bridge.applyStateCommand(.upsertWallet(wallet: wallet.walletState(isWatchOnly: true)))
        var records = (0..<55).map { index in
            var record = TransactionRecord(id: "record-\(index)", walletId: wallet.id, kind: .send, status: .confirmed,
                walletName: wallet.name, assetDisplayName: "Ether", symbol: "ETH", chainName: "Ethereum",
                amount: 1, address: "0x2222222222222222222222222222222222222222")
            record.createdAtUnix = Double(index)
            return record
        }
        records[1].status = .failed
        records[2].status = .pending
        _ = try await service.applyTransactionCommand(command: .upsert(records: records))
        let summary = try await bridge.transactionSnapshot()
        XCTAssertFalse(summary.recentAndPending.contains { $0.id == "record-0" || $0.id == "record-1" })
        var finished: [String: TransactionStatus] = [:]
        var missing: [String] = []
        var failures = 0
        await reconcileSendActivities(transactionIds: ["record-0", "record-1", "record-2", "missing", "unreadable"],
            lookup: { id in
                if id == "unreadable" { throw NSError(domain: "Storage", code: 1) }
                return try await self.bridge.transaction(id: id)
            }, finish: { id, record in
                if let record { finished[id] = record.status }
                else { missing.append(id) }
            }, failed: { _ in failures += 1 })
        XCTAssertEqual(finished, ["record-0": .confirmed, "record-1": .failed])
        XCTAssertEqual(missing, ["missing"])
        XCTAssertEqual(failures, 1)
    }

    func testOneRefreshAdoptsEachProjectionOnceWithoutQueuedReadback() async throws {
        let store = makeState()
        store.isNetworkReachable = false
        let before = try await bridge.transactionSnapshot()
        let succeeded = await store.performCoreRefresh(.user)
        XCTAssertTrue(succeeded)
        let adoptedPortfolio = store.portfolioSnapshotRevision
        let adoptedHistory = store.transactionSnapshotRevision
        XCTAssertEqual(adoptedPortfolio, before.revision + 1)
        XCTAssertEqual(adoptedHistory, adoptedPortfolio + 1)
        // Alert adoption used to enqueue an additional unstructured portfolio read.
        for _ in 0..<10 { await Task.yield() }
        let after = try await bridge.transactionSnapshot()
        XCTAssertEqual(after.revision, adoptedHistory + 1)
        XCTAssertEqual(store.portfolioSnapshotRevision, adoptedPortfolio)
    }
}
