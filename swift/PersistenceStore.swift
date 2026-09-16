import Foundation
extension AppState {
    func reloadPersistedStateFromSQLite() async {
        // Core-owned domain state first: it is the authority, so anything
        // loaded after it must not contradict it.
        await loadCoreOwnedState()
        await diagnostics.loadFromSQLite()
        // Folding in the built-ins catches tokens this build added. Core does
        // the merge and stores it, so this only adopts the answer — assigning
        // through the `didSet` would send it straight back.
        if let merged = try? await WalletServiceBridge.shared.mergeBuiltInTokenPreferences() {
            applyCoreState(merged, epoch: beginCoreStateRead())
        }
        // Price alerts arrive with the rest of the state — `loadCoreOwnedState()`
        // above already set them.
        // Owned addresses load with the rest of core's state in `open_state`.
        // Reserves receive indices, so it runs only after core's keypool is in
        // memory — reserving against an unloaded table would reissue addresses.
        // The settings core owns arrive with `loadCoreOwnedState()` above,
        // through `applyCoreState`. The five this platform keeps were read
        // from `UserDefaults` when `preferences` was created.
        let walletRevision = walletsRevision
        if let stored = try? await WalletServiceBridge.shared.storedWallets(), walletsRevision == walletRevision {
            adoptWalletsFromCore(stored)
            rebuildWalletDerivedState()
        }
        let transactionSnapshot = transactions
        if let stored = try? await WalletServiceBridge.shared.storedTransactions(), transactions == transactionSnapshot {
            adoptTransactionsFromCore(stored.map(TransactionRecord.init(snapshot:)))
            await rebuildTransactionDerivedState()
        }
    }
    /// Tell core which network of a family the user picked.
    func commitNetworkChain(_ chainID: String) {
        let epoch = beginCoreStateRead()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .selectNetworkChain(chainId: chainID))
            else {
                self.finishCoreStateRead(epoch)
                return
            }
            self.applyCoreState(transition.state, epoch: epoch)
        }
    }
    /// Send the known-token list to core, which clamps it and stores it.
    // ── Settings ──────────────────────────────────────────────────────────────
    /// Debounced — a slider drag or a typed endpoint would otherwise be one
    /// command per frame or per keystroke.
    func commitAppSettingsSoon() {
        if pendingAppSettingsEpoch == nil { pendingAppSettingsEpoch = beginCoreStateRead() }
        appSettingsPersist.fire { [weak self] in self?.commitAppSettings() }
    }
}
