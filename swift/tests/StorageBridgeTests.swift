import XCTest
@testable import Spectra

@MainActor
final class StorageBridgeTests: XCTestCase {
    @MainActor
    func testStorageOpenFailureCanBeRetriedWithoutWritingInMemory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path, service: try WalletService(endpoints: []))
        do {
            _ = try await bridge.ready().applyStateCommand(command: .setFiatCurrency(currency: .eur))
            XCTFail("a failed open must refuse the command")
        } catch {
            XCTAssertFalse(String(describing: error).contains("call open_state first"))
        }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = try await bridge.openState()
        XCTAssertEqual(state.settings.fiatCurrency, .usd)
        _ = try await bridge.ready().applyStateCommand(command: .setFiatCurrency(currency: .eur))
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path, service: try WalletService(endpoints: []))
        let stored = try await reopened.openState()
        XCTAssertEqual(stored.settings.fiatCurrency, .eur)
    }

    func testTransactionActionsAndUnixTimeCrossBindingAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("actions.sqlite").path
        let service = try WalletService(endpoints: [])
        _ = try await service.openState(databasePath: path)
        var record = TransactionRecord(id: "tx", kind: .send, status: .failed,
            walletName: "Watch", assetDisplayName: "Bitcoin", symbol: "BTC", chainId: "bitcoin",
            amount: "1", address: "recipient", transactionHash: String(repeating: "a", count: 64))
        record.createdAtUnix = 1_700_000_000.125
        // Caller-supplied availability must not survive storage; core derives it on read.
        record.actions = TransactionActions(recheckUnavailableReason: "wrong", rebroadcastUnavailableReason: nil)
        _ = try await service.applyTransactionCommand(command: .upsert(records: [record]))
        let reopened = try WalletService(endpoints: [])
        _ = try await reopened.openState(databasePath: path)
        let result = try await reopened.transaction(id: "tx")
        let stored = try XCTUnwrap(result)
        XCTAssertNil(stored.actions.recheckUnavailableReason)
        XCTAssertNotNil(stored.actions.rebroadcastUnavailableReason)
        XCTAssertEqual(stored.createdDate.timeIntervalSince1970, 1_700_000_000.125)
    }

    func testOwnedClosureOperationsAcrossAsyncBinding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try WalletService(endpoints: [])
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.db").path)
        let history = try await service.refreshHistory(scope: .all, loadMore: false, limit: 20, intervalSecs: 0)
        XCTAssertTrue(history.isEmpty)
        let discovered = try await service.discoverChainAddresses(chainId: "bitcoin")
        XCTAssertTrue(discovered.isEmpty)
        do {
            _ = try await service.receiveAddress(walletId: "missing", chainId: "bitcoin", reserve: true)
            XCTFail("Missing wallet must fail before reserving")
        } catch SpectraBridgeError.InvalidInput { }
        let reset = try await service.resetData(scopes: [.walletsAndSecrets, .historyAndCache])
        XCTAssertTrue(reset.state.wallets.isEmpty)
        XCTAssertTrue(reset.plan.resetHistoryAndCache)
    }

    func testInvalidKeypoolBaselineThrowsAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        // Inject an out-of-range in-memory record to exercise the throwing read.
        try await service.registerOwnedAddress(
            walletId: "fault", chainId: "bitcoin", address: "fixture",
            derivationPath: nil, branch: "external", branchIndex: Int64.max)
        do {
            _ = try await service.reserveReceiveIndex(walletId: "fault", chainId: "bitcoin", minimumIndex: 1)
            XCTFail("Cannot reserve from an invalid baseline")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("index out of range"))
        }
    }

    func testColdBridgeImportOpensStorageAndPersistsBeforeReturningWallet() async throws {
        let secretStore = TestSecretStore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state.db").path
        let bridge = WalletServiceBridge(databasePath: path, service: try WalletService(endpoints: []))
        try bridge.service().setSecretStore(store: secretStore)
        let outcome = try await bridge.ready().importWallets(commit: WalletImportCommit(
            password: nil,
            request: WalletImportRequest(walletName: "Imported", selectedChainIds: ["ethereum"],
                isWatchOnlyImport: false, isPrivateKeyImport: false,
                watchOnlyEntries: WalletImportWatchOnlyEntries(byChainId: [:], bitcoinXpub: nil)),
            seedDerivationPreset: .standard, seedDerivationPaths: .defaults,
            derivationOverrides: CoreWalletDerivationOverrides(passphrase: nil, hmacKey: nil),
            seedPhrase: "test test test test test test test test test test test junk", privateKey: nil))
        XCTAssertEqual(outcome.wallets.count, 1)
        XCTAssertEqual(outcome.wallets[0].signing, .seedPhrase(passwordProtected: false))
        XCTAssertEqual(
            try bridge.service().revealSeedPhrase(walletId: outcome.wallets[0].id, password: nil),
            .phrase(phrase: "test test test test test test test test test test test junk"))
        let reopened = WalletServiceBridge(databasePath: path, service: try WalletService(endpoints: []))
        let stored = try await reopened.ready().portfolioSnapshot().wallets
        XCTAssertEqual(stored.count, 1)
        _ = try await bridge.ready().applyStateCommand(command: .removeWallet(walletId: outcome.wallets[0].id))
        // Removing the wallet removes its secrets with it.
        XCTAssertNotEqual(
            try? bridge.service().revealSeedPhrase(walletId: outcome.wallets[0].id, password: nil),
            .phrase(phrase: "test test test test test test test test test test test junk"))
    }

    func testUnopenedHistoryReadsThrowAcrossBinding() async throws {
        let service = try WalletService(endpoints: [])
        let reads: [() async throws -> Void] = [
            { _ = try await service.historyPage(query: HistoryQuery(walletId: nil, filter: .all, search: "", oldestFirst: false, cursor: nil, limit: 20)) },
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
            walletId: nil, filter: .all, search: "", oldestFirst: false, cursor: nil, limit: 20))
        XCTAssertTrue(page.records.isEmpty)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextCursor)
        do {
            _ = try await service.historyPage(query: HistoryQuery(
                walletId: nil, filter: .all, search: "", oldestFirst: false, cursor: "invalid", limit: 20))
            XCTFail("Malformed history cursor must be rejected through the async binding")
        } catch { /* Core validates cursors, including through UniFFI. */ }
        let summary = try await service.transactionSnapshot()
        XCTAssertEqual(summary.totalCount, 0)
        let missing = try await service.transaction(id: "missing")
        XCTAssertNil(missing)
    }

    func testHistoryCursorContinuesAcrossAsyncBindingAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("cursor.sqlite").path
        let service = try WalletService(endpoints: [])
        _ = try await service.openState(databasePath: path)
        let wallet = WalletView(name: "Cursor", chainId: "ethereum", addresses: ["ethereum": "0x1111111111111111111111111111111111111111"])
        _ = try await service.applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        let records = ["a", "b", "c"].map { id in
            var record = TransactionRecord(id: id, walletId: wallet.id, deploymentId: "ethereum:native",
                kind: .receive, status: .confirmed, walletName: "Cursor", assetDisplayName: "Ether",
                symbol: "ETH", chainId: "ethereum", amount: "1", address: "recipient", transactionHash: id)
            record.createdAtUnix = 1_700_000_000.125
            return record
        }
        _ = try await service.applyTransactionCommand(command: .upsert(records: records))
        let first = try await service.historyPage(query: HistoryQuery(
            walletId: nil, filter: .all, search: "", oldestFirst: false, cursor: nil, limit: 2))
        XCTAssertEqual(first.records.map(\.id), ["a", "b"])
        XCTAssertTrue(first.hasMore)
        let cursor = try XCTUnwrap(first.nextCursor)
        let reopened = try WalletService(endpoints: [])
        _ = try await reopened.openState(databasePath: path)
        let next = try await reopened.historyPage(query: HistoryQuery(
            walletId: nil, filter: .all, search: "", oldestFirst: false, cursor: cursor, limit: 2))
        XCTAssertEqual(next.records.map(\.id), ["c"])
        XCTAssertFalse(next.hasMore)
        XCTAssertNil(next.nextCursor)
    }

    func testAlertIntentsKeepSubcentTargetsAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.sqlite").path)
        let added = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: "0.000001", currency: .usd, condition: .above))
        let alert = try XCTUnwrap(added.state.priceAlerts.first)
        XCTAssertEqual(alert.targetPrice, 0.000001)
        let duplicate = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: "0.000001", currency: .usd, condition: .above))
        XCTAssertEqual(duplicate.state.priceAlerts.count, 1)
        XCTAssertTrue(duplicate.events.contains(.priceAlertRejected(reason: .duplicateAlert)))
        let paused = try await service.applyStateCommand(command: .togglePriceAlert(id: alert.id))
        XCTAssertFalse(try XCTUnwrap(paused.state.priceAlerts.first).isEnabled)
        let removed = try await service.applyStateCommand(command: .removePriceAlert(id: alert.id))
        XCTAssertTrue(removed.state.priceAlerts.isEmpty)
    }

}
