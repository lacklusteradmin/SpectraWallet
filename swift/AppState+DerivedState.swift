import Foundation
extension AppState {
    /// The one index over the token preferences: the deployment a holding
    /// names, so a formatter or a send can ask "is this token known, and with
    /// what decimals" without walking the list.
    func rebuildTokenPreferenceDerivedState() {
        cachedTokenPreferenceByDeploymentID = Dictionary(
            tokenPreferences.map { ($0.token.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    func rebuildWalletDerivedState() {
        Task { @MainActor [weak self] in await self?.rebuildWalletDerivedStateFromCore() }
    }
    /// Core resolves the whole thing — grouping, price-request set, and which
    /// coins each wallet can send or receive on. It holds the wallets, so it
    /// hands back coins rather than indices into a list the caller has to
    /// re-walk.
    func rebuildWalletDerivedStateFromCore() async {
        guard let derived = try? await WalletServiceBridge.shared.walletDerivedState() else { return }
        applyWalletDerivedState(derived)
    }
    private func applyWalletDerivedState(_ derived: WalletDerivedState) {
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        walletDerivedCache = WalletDerivedCache(
            resolvedAddressesByWalletID: derived.resolvedAddressesByWalletId,
            walletByID: walletByID,
            includedPortfolioWallets: wallets.filter(\.includeInPortfolioTotal),
            portfolio: derived.portfolio,
            availableSendCoinsByWalletID: derived.sendCoinsByWalletId,
            availableReceiveCoinsByWalletID: derived.receiveCoinsByWalletId,
            sendEnabledWallets: derived.sendEnabledWalletIds.compactMap { walletByID[$0] },
            receiveEnabledWallets: derived.receiveEnabledWalletIds.compactMap { walletByID[$0] },
            refreshableChainNames: Set(derived.refreshableChainNames)
        )
    }
    /// Run after `wallets` mutates: rebuild the observable derived state now,
    /// then — inside a 200ms debounce, so a fast cascade of edits costs one
    /// pass rather than N — let the refresh engine adopt the list and start or
    /// stop the background services.
    ///
    /// There was a middle phase, "persist wallet state optimistically", whose
    /// comment described writing wallets to SQLite and Keychain and pruning
    /// orphaned transactions. Core does all of that inside the command that
    /// changed the wallet; the phase's body had come down to the one call
    /// below.
    func applyWalletCollectionSideEffects() {
        rebuildWalletDerivedState()
        rebuildDashboardDerivedState()
        walletSideEffectsTask?.cancel()
        walletSideEffectsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self.reconcileBackgroundServices()
            self.walletSideEffectsTask = nil
        }
    }

    /// Let the balance-refresh engine adopt the wallet list, and start the
    /// maintenance loop once there is something to maintain.
    ///
    /// Runs after every replacement of the projection, including the one each
    /// refresh sweep ends with. Core refreshes only when what a sweep fetches
    /// changed, and stops the engine when nothing is left to fetch. This used to
    /// sync the entries, trigger a sweep and restart the engine — whose restart
    /// ticks at once — every time, so the end of each sweep began the next.
    private func reconcileBackgroundServices() async {
        _ = try? await WalletServiceBridge.shared.reconcileBalanceRefresh(appIsActive: appIsActive)
        if !wallets.isEmpty { startMaintenanceLoopIfNeeded() }
    }

    /// Merge a fetched page into the store core owns, then adopt the result.
    ///
    /// Only the incoming page crosses the FFI. Core merges against its own
    /// records and writes just what changed; this then re-reads the projection.
    /// Previously the entire history went out, came back merged, and the
    /// changed subset went out again — three crossings of the whole list per
    /// refresh.
    /// Re-read the projection from core. Used after a change core made itself.
    func refreshTransactionProjection() async {
        guard let stored = try? await WalletServiceBridge.shared.storedTransactions() else { return }
        adoptTransactionsFromCore(stored)
        await rebuildTransactionDerivedState()
    }
}
