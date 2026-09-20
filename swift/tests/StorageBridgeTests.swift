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
            _ = try await bridge.applyStateCommand(.setFiatCurrency(currency: .eur))
            XCTFail("a failed open must refuse the command")
        } catch {
            XCTAssertFalse(String(describing: error).contains("call open_state first"))
        }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = try await bridge.openState()
        XCTAssertEqual(state.settings.fiatCurrency, .usd)
        _ = try await bridge.applyStateCommand(.setFiatCurrency(currency: .eur))
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path, service: try WalletService(endpoints: []))
        let stored = try await reopened.openState()
        XCTAssertEqual(stored.settings.fiatCurrency, .eur)
    }

    func testOwnedClosureOperationsAcrossAsyncBinding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try WalletService(endpoints: [])
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.db").path)
        let history = try await service.refreshHistory(scope: .all, loadMore: false, limit: 20, intervalSecs: 0)
        XCTAssertTrue(history.isEmpty)
        let alerts = try await service.evaluatePriceAlerts()
        XCTAssertTrue(alerts.isEmpty)
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
            walletId: "fault", chainName: "Bitcoin", address: "fixture",
            derivationPath: nil, branch: "external", branchIndex: Int64.max)
        do {
            _ = try await service.reserveReceiveIndex(walletId: "fault", chainName: "Bitcoin", minimumIndex: 1)
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
        try bridge.registerSecretStore(secretStore)
        let outcome = try await bridge.importWallets(WalletImportCommit(
            password: nil,
            request: WalletImportRequest(walletName: "Imported", selectedChainNames: ["Ethereum"],
                isWatchOnlyImport: false, isPrivateKeyImport: false,
                watchOnlyEntries: WalletImportWatchOnlyEntries(bySlot: [:], bitcoinXpub: nil)),
            seedDerivationPreset: .standard, seedDerivationPaths: .defaults,
            derivationOverrides: CoreWalletDerivationOverrides(passphrase: nil, hmacKey: nil),
            seedPhrase: "test test test test test test test test test test test junk", privateKey: nil))
        XCTAssertEqual(outcome.wallets.count, 1)
        XCTAssertTrue(bridge.walletSecretState(walletID: outcome.wallets[0].id)?.hasSigningMaterial == true)
        let reopened = WalletServiceBridge(databasePath: path, service: try WalletService(endpoints: []))
        let stored = try await reopened.portfolioSnapshot().wallets
        XCTAssertEqual(stored.count, 1)
        _ = try await bridge.applyStateCommand(.removeWallet(walletId: outcome.wallets[0].id))
        XCTAssertFalse(bridge.walletSecretState(walletID: outcome.wallets[0].id)?.hasSigningMaterial == true)
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

    func testAlertIntentsKeepSubcentTargetsAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.sqlite").path)
        let added = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: 0.000001, currency: .usd, condition: .above))
        let alert = try XCTUnwrap(added.state.priceAlerts.first)
        XCTAssertEqual(alert.targetPrice, 0.000001)
        let duplicate = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: 0.000001, currency: .usd, condition: .above))
        XCTAssertEqual(duplicate.state.priceAlerts.count, 1)
        XCTAssertTrue(duplicate.events.contains(.priceAlertRejected(reason: .duplicateAlert)))
        let paused = try await service.applyStateCommand(command: .togglePriceAlert(id: alert.id))
        XCTAssertFalse(try XCTUnwrap(paused.state.priceAlerts.first).isEnabled)
        let removed = try await service.applyStateCommand(command: .removePriceAlert(id: alert.id))
        XCTAssertTrue(removed.state.priceAlerts.isEmpty)
    }

}
