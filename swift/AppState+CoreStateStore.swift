// MARK: - Wallet/transactions/address-book mutation helpers
//
// Core is the canonical store for all three collections; the `@Observable`
// arrays on AppState are projections of it, with one writer each. These helpers
// send the `StateCommand` and update the projection, so direct assignment to
// `self.wallets`, `self.transactions` or `self.addressBook` is a bug — it
// desynchronises the projection from the store rather than failing loudly.

import Foundation

@MainActor
extension AppState {
    // ── Wallets ────────────────────────────────────────────────────────
    //
    // Core owns the list. These update the projection immediately so the UI
    // stays responsive, then send the command that makes it durable.

    // Wallet writes are awaitable, unlike the transaction ones. They are rare —
    // import, rename, delete, a balance change — and a caller that needs to know
    // the wallet is durably stored before moving on (import, above all) must be
    // able to wait. The `Task`-wrapping variants exist only for the synchronous
    // UI entry points.

    @discardableResult
    func removeWallet(id: String) async -> Bool {
        do {
            _ = try await WalletServiceBridge.shared.applyStateCommand(.removeWallet(walletId: id))
            adoptWalletsFromCore(try await WalletServiceBridge.shared.storedWallets())
            await refreshTransactionProjection()
            await rebuildWalletDerivedStateFromCore()
            return true
        } catch {
            importError = error.localizedDescription
            return false
        }
    }

    /// Send a field intent and adopt only the committed projection.
    func changeWallet(_ command: StateCommand) {
        let previous = walletMutationTask
        walletMutationTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let epoch = self.beginCoreStateRead()
            do {
                let transition = try await WalletServiceBridge.shared.applyStateCommand(command)
                self.applyCoreState(transition.state, epoch: epoch)
                self.adoptWalletsFromCore(try await WalletServiceBridge.shared.storedWallets())
                await self.rebuildWalletDerivedStateFromCore()
            } catch {
                self.finishCoreStateRead(epoch)
                self.importError = error.localizedDescription
            }
        }
    }

    /// Replace the pinned dashboard set. Core normalises and de-duplicates, so
    /// the projection that comes back is the authority, not what was sent.
    func setPinnedDashboardAssets(_ tokenIDs: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let epoch = self.beginCoreStateRead()
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .setPinnedDashboardAssets(tokenIds: tokenIDs))
            else { return }
            self.applyCoreState(transition.state, epoch: epoch)
        }
    }

    /// Replace the projection without touching the store. Only for loading what
    /// core already has.
    func adoptWalletsFromCore(_ records: [ImportedWallet]) {
        suppressWalletSideEffects = true
        setWalletProjection(records)
        suppressWalletSideEffects = false
    }


    /// Replace the projection without touching the store. Only for loading what
    /// core already has.
    func adoptTransactionsFromCore(_ records: [TransactionRecord]) {
        withSuspendedTransactionSideEffects { setTransactionProjection(records) }
    }

    // Address-book mutation helpers are gone: core owns that list, and it is
    // changed by `StateCommand` rather than by assigning to an array here.
}
