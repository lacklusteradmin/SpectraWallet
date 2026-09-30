import XCTest
@testable import Spectra

@MainActor
final class WalletServiceBridgeTests: XCTestCase {
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
            request: WalletImportRequest(walletName: "Imported", selectedChainIds: [Chain.ethereum],
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

}
