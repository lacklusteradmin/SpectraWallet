import XCTest
@testable import Spectra

final class SendAmountBridgeTests: XCTestCase {
    @MainActor
    func testStorageOpenFailureCanBeRetriedWithoutWritingInMemory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path)
        do {
            _ = try await bridge.applyStateCommand(.setFiatCurrency(fiatCurrencyCode: "EUR"))
            XCTFail("a failed open must refuse the command")
        } catch {
            XCTAssertFalse(String(describing: error).contains("call open_state first"))
        }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = try await bridge.openState()
        XCTAssertEqual(state.settings.fiatCurrencyCode, "USD")
        _ = try await bridge.applyStateCommand(.setFiatCurrency(fiatCurrencyCode: "EUR"))
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path)
        let stored = try await reopened.openState()
        XCTAssertEqual(stored.settings.fiatCurrencyCode, "EUR")
    }

    @MainActor
    func testColdBridgeImportOpensStorageAndPersistsBeforeReturningWallet() async throws {
        let secretStore = ImportTestSecretStore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state.db").path
        let bridge = WalletServiceBridge(databasePath: path)
        try bridge.registerSecretStore(secretStore)
        let outcome = try await bridge.importWallets(WalletImportCommit(
            password: nil,
            request: WalletImportRequest(walletName: "Imported",
                primarySelectedChainName: "Ethereum", selectedChainNames: ["Ethereum"], plannedWalletIds: [],
                isWatchOnlyImport: false, isPrivateKeyImport: false, hasWalletPassword: false,
                resolvedAddresses: WalletImportAddresses(bySlot: [:], bitcoinXpub: nil),
                watchOnlyEntries: WalletImportWatchOnlyEntries(bySlot: [:], bitcoinXpub: nil)),
            holdings: [], seedDerivationPreset: .standard, seedDerivationPaths: .defaults,
            derivationOverrides: .empty, networkChainByFamily: [:],
            seedPhrase: "test test test test test test test test test test test junk", privateKey: nil))
        XCTAssertEqual(outcome.wallets.count, 1)
        XCTAssertTrue(bridge.walletSecretState(walletID: outcome.wallets[0].id)?.hasSigningMaterial == true)
        let reopened = WalletServiceBridge(databasePath: path)
        let stored = try await reopened.storedWallets()
        XCTAssertEqual(stored.count, 1)
        _ = try await bridge.applyStateCommand(.removeWallet(walletId: outcome.wallets[0].id))
        XCTAssertFalse(bridge.walletSecretState(walletID: outcome.wallets[0].id)?.hasSigningMaterial == true)
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
        let reset = try await service.resetData(scopes: ["walletsAndSecrets", "historyAndCache"])
        XCTAssertTrue(reset.state.wallets.isEmpty)
        XCTAssertTrue(reset.plan.resetHistoryAndCache)
    }

    func testFeeAdjustedShortcutIsFlooredAcrossBinding() {
        XCTAssertEqual(sendAmountShortcut(maximum: 0.99999, decimals: 8, percentage: 100), "0.99998999")
        XCTAssertNil(sendAmountShortcut(maximum: .infinity, decimals: 8, percentage: 100))
        XCTAssertNil(quotedSendAmount(preview: nil, chainName: "Bitcoin", isNative: true, tokenDecimals: nil, percentage: 100))
        XCTAssertNil(parseAmountInput(text: "340282366920938463463374607431768211456", maxDecimals: 0))
    }

    func testInvalidExactAmountIsRefusedBeforeSigningMaterialAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        for amount in ["0.000000001", "-1", "NaN", "1.é"] {
            let request = SendExecutionRequest(
                chainId: "bitcoin", walletId: "missing", password: nil, toAddress: "",
                amountStr: amount, contractAddress: nil, tokenDecimals: nil,
                feeRateSvb: nil, feeSat: nil, gasBudget: nil, feeAmount: nil,
                evmOverrides: nil, moneroPriority: nil
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
    func testMissingWalletIsRefusedBeforeSecretStoreOrNetwork() async throws {
        let service = try WalletService(endpoints: [])
        let request = SendExecutionRequest(
            chainId: "ethereum", walletId: "missing", password: nil,
            toAddress: "0x9858effd232b4033e47d90003d41ec34ecaeda94", amountStr: "1",
            contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil,
            gasBudget: nil, feeAmount: nil, evmOverrides: nil, moneroPriority: nil
        )
        do {
            _ = try await service.executeSend(request: request)
            XCTFail("Missing wallet must fail")
        } catch {
            XCTAssertTrue(String(describing: error).contains("wallet does not exist"))
        }
    }

    func testInvalidKeypoolBaselineThrowsAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        // Inject an out-of-range in-memory record to exercise the throwing read.
        try await service.registerOwnedAddress(
            walletId: "fault", chainName: "Bitcoin", address: "fixture",
            derivationPath: nil, branch: "external", branchIndex: Int64.max)
        do {
            _ = try await service.keypoolState(walletId: "fault", chainName: "Bitcoin")
            XCTFail("An invalid baseline must not become index zero")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("index out of range"))
        }
        do {
            _ = try await service.reserveReceiveIndex(walletId: "fault", chainName: "Bitcoin", minimumIndex: 1)
            XCTFail("Cannot reserve from an invalid baseline")
        } catch SpectraBridgeError.Failure(let message) {
            XCTAssertTrue(message.contains("index out of range"))
        }
    }

    func testOwnedPreviewRefusesMissingWalletAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        do {
            _ = try await service.previewOwnedSend(walletId: "missing", holdingKey: "ethereum:native", amount: "1", destination: "", explicitNonce: nil, customFees: nil)
            XCTFail("A missing wallet must not produce a preview")
        } catch {
            XCTAssertTrue(String(describing: error).contains("wallet does not exist"))
        }
    }
    func testAlertIntentsKeepSubcentTargetsAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.sqlite").path)
        let added = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: 0.000001, currencyCode: "USD", condition: .above))
        let alert = try XCTUnwrap(added.state.priceAlerts.first)
        XCTAssertEqual(alert.targetPrice, 0.000001)
        let duplicate = try await service.applyStateCommand(command: .addPriceAlert(
            holdingKey: "ethereum:native", targetPrice: 0.000001, currencyCode: "USD", condition: .above))
        XCTAssertEqual(duplicate.state.priceAlerts.count, 1)
        XCTAssertTrue(duplicate.events.contains { $0.kind == "priceAlertRejected" })
        let paused = try await service.applyStateCommand(command: .togglePriceAlert(id: alert.id))
        XCTAssertFalse(try XCTUnwrap(paused.state.priceAlerts.first).isEnabled)
        let removed = try await service.applyStateCommand(command: .removePriceAlert(id: alert.id))
        XCTAssertTrue(removed.state.priceAlerts.isEmpty)
    }

}

private final class ImportTestSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretClass: [String: String]] = [:]
    func loadSecret(kind: SecretClass, key: String) throws -> String {
        try lock.withLock {
            guard let value = values[kind]?[key] else { throw SecretStoreError.NotFound }
            return value
        }
    }
    func saveSecret(kind: SecretClass, key: String, value: String) throws {
        lock.withLock { values[kind, default: [:]][key] = value }
    }
    func deleteSecret(kind: SecretClass, key: String) throws {
        lock.withLock { _ = values[kind]?.removeValue(forKey: key) }
    }
    func listKeys(kind: SecretClass, prefixFilter: String) throws -> [String] {
        lock.withLock { Array(values[kind, default: [:]].keys).filter { $0.hasPrefix(prefixFilter) } }
    }
}

extension SendAmountBridgeTests {
    @MainActor
    func testDerivationInputPreservesSecretWhitespace() throws {
        let draft = WalletImportDraft()
        draft.overridePassphrase = " secret "
        draft.overrideHmacKey = " key "
        let parsed = draft.resolvedDerivationOverrides
        XCTAssertEqual(parsed.passphrase, " secret ")
        XCTAssertEqual(parsed.hmacKey, " key ")
    }

    @MainActor
    func testOwnedRefreshAndMissingConfirmationAcrossAsyncBinding() async throws {
        let service = try WalletService(endpoints: [])
        let result = try await service.refreshApp(intent: .user, conditions: DeviceConditions(
            appIsActive: true, isNetworkReachable: false, isConstrainedNetwork: false,
            isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: true))
        XCTAssertNil(result.pending)
        XCTAssertTrue(result.failures.isEmpty)
        let rescan = try await service.refreshApp(intent: .deepRescan(chainId: "bitcoin"), conditions: DeviceConditions(
            appIsActive: true, isNetworkReachable: false, isConstrainedNetwork: false,
            isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: false))
        XCTAssertFalse(rescan.failures.isEmpty)
        XCTAssertNil(rescan.pending)
        do {
            _ = try await service.executeOwnedSend(reviewId: "missing", input: SendReviewInput(
                walletId: "w", holdingKey: "ethereum:native", amount: "1", destination: "0x1111111111111111111111111111111111111111", overrides: nil), password: nil)
            XCTFail("sending requires a core-issued review")
        } catch {
            XCTAssertTrue(String(describing: error).contains("review missing"))
        }
    }
}
