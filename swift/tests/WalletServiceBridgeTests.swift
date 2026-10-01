import Foundation
import Testing
@testable import Spectra

@MainActor
struct WalletServiceBridgeTests {
    @Test func storageOpenFailureCanBeRetriedWithoutWritingInMemory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path, service: try WalletService(endpoints: []))
        let error = await #expect(throws: (any Error).self, "a failed open must refuse the command") {
            try await bridge.ready().applyStateCommand(command: .setFiatCurrency(currency: .eur))
        }
        if let error { #expect(!String(describing: error).contains("call open_state first")) }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = try await bridge.ready().appState()
        #expect(state.settings.fiatCurrency == .usd)
        _ = try await bridge.ready().applyStateCommand(command: .setFiatCurrency(currency: .eur))
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.db").path, service: try WalletService(endpoints: []))
        let stored = try await reopened.ready().appState()
        #expect(stored.settings.fiatCurrency == .eur)
    }

    @Test func coldBridgeImportOpensStorageAndPersistsBeforeReturningWallet() async throws {
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
        #expect(outcome.wallets.count == 1)
        #expect(outcome.wallets[0].signing == .seedPhrase(passwordProtected: false))
        #expect(try bridge.service().revealSeedPhrase(walletId: outcome.wallets[0].id, password: nil) == .phrase(phrase: "test test test test test test test test test test test junk"))
        let reopened = WalletServiceBridge(databasePath: path, service: try WalletService(endpoints: []))
        let stored = try await reopened.ready().portfolioSnapshot().wallets
        #expect(stored.count == 1)
        _ = try await bridge.ready().applyStateCommand(command: .removeWallet(walletId: outcome.wallets[0].id))
        // Removing the wallet removes its secrets with it.
        #expect(
            (try? bridge.service().revealSeedPhrase(walletId: outcome.wallets[0].id, password: nil))
                != .phrase(phrase: "test test test test test test test test test test test junk"))
    }

}
