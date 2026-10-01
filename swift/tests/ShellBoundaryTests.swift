import Foundation
import Testing
@testable import Spectra

@MainActor
@Suite(.isolatedAppState)
struct ShellBoundaryTests: IsolatedAppStateSuite {
    @Test func activityReconciliationFindsOldRecordsAndKeepsReadFailures() async throws {
        let wallet = WalletView(name: "Archive", chainId: Chain.ethereum, addresses: [Chain.ethereum: "0x1111111111111111111111111111111111111111"])
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        var records = (0..<55).map { index in
            var record = TransactionRecord(id: "record-\(index)", walletId: wallet.id, kind: .send, status: .confirmed,
                walletName: wallet.name, assetDisplayName: "Ether", symbol: "ETH", chainId: Chain.ethereum,
                amount: "1", address: "0x2222222222222222222222222222222222222222")
            record.createdAtUnix = Double(index)
            return record
        }
        records[1].status = .failed
        records[2].status = .pending
        _ = try await service.applyTransactionCommand(command: .upsert(records: records))
        let summary = try await bridge.ready().transactionSnapshot()
        #expect(!summary.recentAndPending.contains { $0.id == "record-0" || $0.id == "record-1" })
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
        #expect(finished == ["record-0": .confirmed, "record-1": .failed])
        #expect(missing == ["missing"])
        #expect(failures == 1)
    }

    @Test func oneRefreshReadsOnlyWhatCoreSaysChanged() async throws {
        let store = makeState()
        store.isNetworkReachable = false
        let before = try await bridge.ready().transactionSnapshot()
        let succeeded = await store.performCoreRefresh(.user)
        #expect(succeeded)
        let adoptedPortfolio = store.portfolioSnapshotRevision
        #expect(adoptedPortfolio == before.revision + 1, "the portfolio is read once")
        #expect(store.transactionSnapshotRevision == 0, "nothing changed, so history is not re-read")
        // Alert adoption must not enqueue another portfolio read.
        for _ in 0..<10 { await Task.yield() }
        let after = try await bridge.ready().transactionSnapshot()
        #expect(after.revision == adoptedPortfolio + 1)
        #expect(store.portfolioSnapshotRevision == adoptedPortfolio)
    }
}
