import Foundation
extension AppState {
    func persistCodableToSQLite<T: Encodable & Sendable>(_ value: T, key: String) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
            try? await WalletServiceBridge.shared.saveState(key: key, stateJSON: json)
        }
    }
    func loadCodableFromSQLite<T: Decodable>(_ type: T.Type, key: String) async -> T? {
        guard let json = try? await WalletServiceBridge.shared.loadState(key: key), json != "{}", let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
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
        // The eighteen settings core owns arrive with `loadCoreOwnedState()`
        // above, through `applyCoreState`. What is left here is the four this
        // platform keeps: hiding balances, Face ID, auto-lock and
        // biometric-gated sends, which no other front end has a use for.
        if let platform = await loadCodableFromSQLite(
            PlatformPreferences.self, key: Self.platformPreferencesDefaultsKey)
        {
            preferences.applyPlatform(platform)
        }
        let walletRevision = walletsRevision
        if let stored = try? await WalletServiceBridge.shared.storedWallets(), walletsRevision == walletRevision {
            adoptWalletsFromCore(stored)
            rebuildWalletDerivedState()
        }
        let transactionSnapshot = transactions
        if let stored = try? await WalletServiceBridge.shared.storedTransactions(), transactions == transactionSnapshot {
            adoptTransactionsFromCore(stored.compactMap(TransactionRecord.init(snapshot:)))
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
    /// The four this platform keeps. A blob, because it is one front end's
    /// preferences and nothing else reads it.
    func persistPlatformPreferences() {
        persistCodableToSQLite(preferences.platformSnapshot, key: Self.platformPreferencesDefaultsKey)
    }
}
