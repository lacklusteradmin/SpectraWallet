import Foundation
import SwiftUI
@MainActor
extension AppState {
    func resetImportForm() {
        importDraft.configureForNewWallet()
    }
    func beginWalletImport(setupMode: SetupModeChoice = .simple) {
        importDraft.configureForNewWallet()
        importDraft.setupModeChoice = setupMode
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWatchAddressesImport() {
        importDraft.configureForWatchAddressesImport()
        // Watch mode doesn't use derivation, so the simple/advanced toggle is
        // irrelevant — always reset to simple so the state is deterministic.
        importDraft.setupModeChoice = .simple
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWalletCreation(setupMode: SetupModeChoice = .simple) {
        importDraft.configureForCreatedWallet()
        importDraft.setupModeChoice = setupMode
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func cancelWalletImport() {
        importDraft.configureForNewWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = false
    }
    func beginEditingWallet(_ wallet: WalletView) {
        editingWalletID = wallet.id
        importError = nil
        isImportingWallet = false
        importDraft.configureForEditing(wallet: wallet)
        isShowingWalletImporter = true
    }
    func confirmDeleteWallet(_ wallet: WalletView) { walletPendingDeletion = wallet }
    func deletePendingWallet() async {
        guard let walletPendingDeletion else { return }
        guard
            await authenticateForSensitiveAction(
                reason: AppLocalization.string("Authenticate to delete wallet"), allowWhenAuthenticationUnavailable: true
            )
        else {
            return
        }
        let deletedWalletID = walletPendingDeletion.id
        // Core forgets the wallet's secrets, owned addresses, history
        // pagination and diagnostics rows in the same removal.
        guard await removeWallet(id: deletedWalletID) else { return }
        chainDiagnosticsState.diagnosticsRevision &+= 1
        await diagnostics.loadFromSQLite()
        if receiveWalletID == deletedWalletID {
            receiveWalletID = ""
            receiveHoldingKey = ""
            receiveResolvedAddress = ""
            isResolvingReceiveAddress = false
        }
        if sendWalletID == deletedWalletID { cancelSend() }
        if editingWalletID == deletedWalletID {
            editingWalletID = nil
            isShowingWalletImporter = false
        }
        selectedMainTab = .home
        self.walletPendingDeletion = nil
        if wallets.isEmpty { cancelWalletImport() }
    }
    func importWallet() async {
        guard canImportWallet else { return }
        guard !isImportingWallet else { return }
        importError = nil
        let trimmedWalletName = importDraft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingWalletID {
            await renameWallet(id: editingWalletID, to: trimmedWalletName)
            return
        }
        if importDraft.requiresBackupVerification && !importDraft.isBackupVerificationComplete {
            importError = AppLocalization.string("Confirm your seed backup words before importing the wallet.")
            return
        }
        isImportingWallet = true
        defer { isImportingWallet = false }
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let draft = importDraft
        let selectedDerivationPreset = importDraft.seedDerivationPreset
        let selectedDerivationPaths: CoreSeedDerivationPaths = {
            var paths = importDraft.seedDerivationPaths
            paths.isCustomEnabled = true
            return paths
        }()
        var importedWalletsForRefresh: [WalletView] = []
        if editingWalletID == nil {
            // Core mints the wallet ids, derives every address from the secret
            // the commit carries, and reads each family's network from its own
            // settings; only a watch-only import supplies addresses, typed, in
            // `watchOnlyEntries`.
            let importPlanRequest = WalletImportRequest(
                walletName: trimmedWalletName, selectedChainNames: draft.selectedChainNames,
                isWatchOnlyImport: draft.isWatchOnlyMode, isPrivateKeyImport: draft.isPrivateKeyImportMode,
                watchOnlyEntries: draft.watchOnlyImportEntries)
            // Core derives addresses, stores secrets through the registered
            // callback and commits the entire wallet batch before returning.
            let outcome: WalletImportOutcome
            do {
                outcome = try await self.bridge.importWallets(
                    WalletImportCommit(
                        password: trimmedWalletPassword,
                        request: importPlanRequest,
                        seedDerivationPreset: selectedDerivationPreset,
                        seedDerivationPaths: selectedDerivationPaths,
                        derivationOverrides: draft.resolvedDerivationOverrides,
                        seedPhrase: draft.seedPhrase,
                        privateKey: draft.privateKeyInput
                    )
                )
            } catch {
                importError = error.localizedDescription
                return
            }
            // Core refuses addresses that do not parse for their chain. Wallets
            // it did create are already stored, so this is a notice rather than
            // a failure — but it has to be shown. Dropping it silently is how a
            // typo becomes a wallet whose receive address is missing.
            if !outcome.rejectedAddresses.isEmpty {
                let refused = outcome.rejectedAddresses.joined(separator: ", ")
                importError = AppLocalization.format("These addresses were not valid and were not imported: %@", refused)
            }
            let createdWallets = outcome.wallets
            importedWalletsForRefresh = createdWallets
        }
        await rebuildWalletDerivedStateFromCore()
        finishWalletImportFlow(notice: importError)
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: String, to newName: String) async {
        changeWallet(.renameWallet(walletId: id, name: newName))
        await walletMutationTask?.value
        if importError == nil { finishWalletImportFlow() }
    }
    func finishWalletImportFlow(notice: String? = nil) {
        importError = notice
        importDraft.clearSensitiveInputs()
        resetImportForm()
        editingWalletID = nil
        isShowingWalletImporter = false
        // Also pop the Add Wallet entry page so the user lands back on
        // Dashboard after a successful import — they started on Dashboard,
        // pushed Add Wallet, pushed the Importer, and shouldn't be stranded
        // on the intermediate Add Wallet page after finishing.
        isShowingAddWalletEntry = false
    }
}
