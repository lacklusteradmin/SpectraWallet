import XCTest
@testable import Spectra

final class SendAmountBridgeTests: XCTestCase {
    @MainActor
    func testImportStoresSecretThroughForeignCallbackBeforeReturningWallet() async throws {
        let service = try WalletService.newTyped(endpoints: [])
        let secretStore = ImportTestSecretStore()
        service.setSecretStore(store: secretStore)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await service.openState(dbPath: directory.appendingPathComponent("state.db").path)
        let outcome = try await service.importWallets(commit: WalletImportCommit(
            password: nil,
            request: WalletImportRequest(walletName: "Imported", defaultWalletNameStartIndex: 1,
                primarySelectedChainName: "Ethereum", selectedChainNames: ["Ethereum"], plannedWalletIds: [],
                isWatchOnlyImport: false, isPrivateKeyImport: false, hasWalletPassword: false,
                resolvedAddresses: WalletImportAddresses(bySlot: [:], bitcoinXpub: nil),
                watchOnlyEntries: WalletImportWatchOnlyEntries(bySlot: [:], bitcoinXpub: nil)),
            holdings: [], seedDerivationPreset: .standard, seedDerivationPaths: .defaults,
            derivationOverrides: .empty, networkChainByFamily: [:],
            seedPhrase: "test test test test test test test test test test test junk", privateKey: nil))
        XCTAssertEqual(outcome.wallets.count, 1)
        XCTAssertTrue(service.walletSecretState(walletId: outcome.wallets[0].id).hasSigningMaterial)
        let stored = try await service.walletsForDisplay()
        XCTAssertEqual(stored.count, 1)
        _ = try await service.applyStateCommand(command: .removeWallet(walletId: outcome.wallets[0].id))
        XCTAssertFalse(service.walletSecretState(walletId: outcome.wallets[0].id).hasSigningMaterial)
    }

    func testFeeAdjustedShortcutIsFlooredAcrossBinding() {
        XCTAssertEqual(sendAmountShortcut(maximum: 0.99999, decimals: 8, percentage: 100), "0.99998999")
        XCTAssertNil(sendAmountShortcut(maximum: .infinity, decimals: 8, percentage: 100))
        XCTAssertNil(quotedSendAmount(preview: nil, chainName: "Bitcoin", symbol: "BTC", tokenDecimals: nil, percentage: 100))
        XCTAssertNil(parseAmountInput(text: "340282366920938463463374607431768211456", maxDecimals: 0))
    }

    func testInvalidExactAmountIsRefusedBeforeSigningMaterialAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
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
        let service = try WalletService.newTyped(endpoints: [])
        let request = SendExecutionRequest(
            chainId: "ethereum", walletId: "missing", password: nil,
            toAddress: "0x9858effd232b4033e47d90003d41ec34ecaeda94", amountStr: "1",
            contractAddress: nil, tokenDecimals: nil, feeRateSvb: nil, feeSat: nil,
            gasBudget: nil, feeAmount: nil, evmOverrides: nil, moneroPriority: nil
        )
        do {
            _ = try await service.executeSend(request: request)
            XCTFail("Missing wallet must fail")
        } catch SpectraBridgeError.InvalidInput(let message) {
            XCTAssertTrue(message.contains("wallet does not exist"))
        }
    }

    func testInvalidKeypoolBaselineThrowsAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
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

    func testOwnedEvmPreviewRefusesMissingWalletAcrossAsyncBinding() async throws {
        let service = try WalletService.newTyped(endpoints: [])
        do {
            _ = try await service.previewOwnedEvmSend(walletId: "missing", holdingKey: "Ethereum|ETH", amount: "1", destination: "", explicitNonce: nil, customFees: nil)
            XCTFail("A missing wallet must not produce a preview")
        } catch SpectraBridgeError.InvalidInput(let message) {
            XCTAssertTrue(message.contains("wallet does not exist"))
        }
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
