import XCTest
@testable import Spectra

@MainActor
final class ShellBoundaryTests: IsolatedAppStateTestCase {
    func testActivityReconciliationFindsOldRecordsAndKeepsReadFailures() async throws {
        let wallet = WalletView(name: "Archive", chainId: "ethereum", addresses: ["ethereum": "0x1111111111111111111111111111111111111111"])
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        var records = (0..<55).map { index in
            var record = TransactionRecord(id: "record-\(index)", walletId: wallet.id, kind: .send, status: .confirmed,
                walletName: wallet.name, assetDisplayName: "Ether", symbol: "ETH", chainId: "ethereum",
                amount: "1", address: "0x2222222222222222222222222222222222222222")
            record.createdAtUnix = Double(index)
            return record
        }
        records[1].status = .failed
        records[2].status = .pending
        _ = try await service.applyTransactionCommand(command: .upsert(records: records))
        let summary = try await bridge.ready().transactionSnapshot()
        XCTAssertFalse(summary.recentAndPending.contains { $0.id == "record-0" || $0.id == "record-1" })
        var finished: [String: TransactionStatus] = [:]
        var missing: [String] = []
        var failures = 0
        await reconcileSendActivities(transactionIds: ["record-0", "record-1", "record-2", "missing", "unreadable"],
            lookup: { id in
                if id == "unreadable" { throw NSError(domain: "Storage", code: 1) }
                return try await self.bridge.ready().transaction(id: id)
            }, finish: { id, record in
                if let record { finished[id] = record.status }
                else { missing.append(id) }
            }, failed: { _ in failures += 1 })
        XCTAssertEqual(finished, ["record-0": .confirmed, "record-1": .failed])
        XCTAssertEqual(missing, ["missing"])
        XCTAssertEqual(failures, 1)
    }

    func testOneRefreshReadsOnlyWhatCoreSaysChanged() async throws {
        let store = makeState()
        store.isNetworkReachable = false
        let before = try await bridge.ready().transactionSnapshot()
        let succeeded = await store.performCoreRefresh(.user)
        XCTAssertTrue(succeeded)
        let adoptedPortfolio = store.portfolioSnapshotRevision
        XCTAssertEqual(adoptedPortfolio, before.revision + 1, "the portfolio is read once")
        XCTAssertEqual(store.transactionSnapshotRevision, 0, "nothing changed, so history is not re-read")
        // Alert adoption used to enqueue an additional unstructured portfolio read.
        for _ in 0..<10 { await Task.yield() }
        let after = try await bridge.ready().transactionSnapshot()
        XCTAssertEqual(after.revision, adoptedPortfolio + 1)
        XCTAssertEqual(store.portfolioSnapshotRevision, adoptedPortfolio)
    }
}
