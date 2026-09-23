import Foundation
import SwiftUI
@MainActor
extension AppState {
    func beginWalletImport(setupMode: SetupModeChoice = .simple) {
        walletImport.begin {
            $0.configureForNewWallet()
            $0.setupModeChoice = setupMode
        }
    }
    func beginWatchAddressesImport() {
        walletImport.begin { $0.configureForWatchAddressesImport() }
    }
    func beginWalletCreation(setupMode: SetupModeChoice = .simple) {
        walletImport.begin {
            $0.configureForCreatedWallet()
            $0.setupModeChoice = setupMode
        }
    }
    func cancelWalletImport() { walletImport.close() }
    func beginEditingWallet(_ wallet: WalletView) {
        walletImport.begin(editing: wallet) { $0.configureForEditing(wallet: wallet) }
    }
    func confirmDeleteWallet(_ wallet: WalletView) { walletPendingDeletion = wallet }
    func deletePendingWallet() async {
        guard let walletPendingDeletion else { return }
        guard
            await authenticateForSensitiveAction(.deleteWallet,
                reason: AppLocalization.string("Authenticate to delete wallet")
            )
        else {
            return
        }
        let deletedWalletId = walletPendingDeletion.id
        // Core forgets the wallet's secrets, owned addresses, history
        // pagination and diagnostics rows in the same removal.
        guard await removeWallet(id: deletedWalletId) else { return }
        chainDiagnosticsState.diagnosticsRevision &+= 1
        await diagnostics.loadFromSQLite()
        if receiveFlow.walletId == deletedWalletId {
            receiveFlow.reset()
        }
        if sendFlow.walletId == deletedWalletId { cancelSend() }
        if walletImport.editingWalletId == deletedWalletId {
            walletImport.close()
        }
        selectedMainTab = .home
        self.walletPendingDeletion = nil
        if wallets.isEmpty { cancelWalletImport() }
    }
    func importWallet() async {
        guard canImportWallet, !walletImport.isBusy else { return }
        let draft = walletImport.draft
        let name = draft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let walletId = walletImport.editingWalletId {
            await renameWallet(id: walletId, to: name)
            return
        }
        // Snapshot all user input before suspension. The draft may be replaced
        // while core commits, but that must not alter this operation's inputs.
        var paths = draft.seedDerivationPaths
        paths.isCustomEnabled = true
        let commit = WalletImportCommit(
            password: draft.normalizedWalletPassword,
            request: WalletImportRequest(
                walletName: name, selectedChainNames: draft.selectedChainNames,
                isWatchOnlyImport: draft.isWatchOnlyMode, isPrivateKeyImport: draft.isPrivateKeyImportMode,
                watchOnlyEntries: draft.watchOnlyImportEntries),
            seedDerivationPreset: draft.seedDerivationPreset, seedDerivationPaths: paths,
            derivationOverrides: draft.resolvedDerivationOverrides,
            seedPhrase: draft.seedPhrase, privateKey: draft.privateKeyInput)
        let completed = await walletImport.submit {
            let outcome = try await self.bridge.importWallets(commit)
            await self.rebuildWalletDerivedStateFromCore()
            self.scheduleImportedWalletRefresh(outcome.wallets)
            return outcome.rejectedAddresses.isEmpty ? nil : AppLocalization.format(
                "These addresses were not valid and were not imported: %@",
                outcome.rejectedAddresses.joined(separator: ", "))
        }
        if completed { isShowingAddWalletEntry = false }
    }
    func renameWallet(id: String, to newName: String) async {
        let completed = await walletImport.submit {
            let transition = try await self.bridge.applyStateCommand(.renameWallet(walletId: id, name: newName))
            self.applyCoreState(transition.state, refreshPortfolio: false)
            await self.rebuildWalletDerivedStateFromCore()
            return nil
        }
        if completed { isShowingAddWalletEntry = false }
    }
}
