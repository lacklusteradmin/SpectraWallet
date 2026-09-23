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
    // Core owns the list. Commands persist first; the coherent snapshot then
    // replaces the displayed wallets and their derived values together.

    // Wallet writes are awaitable, unlike the transaction ones. They are rare —
    // import, rename, delete, a balance change — and a caller that needs to know
    // the wallet is durably stored before moving on (import, above all) must be
    // able to wait. The `Task`-wrapping variants exist only for the synchronous
    // UI entry points.

    @discardableResult
    func removeWallet(id: String) async -> Bool {
        do {
            _ = try await self.bridge.applyStateCommand(.removeWallet(walletId: id))
            await refreshTransactionProjection()
            await rebuildWalletDerivedStateFromCore()
            return true
        } catch {
            importError = error.localizedDescription
            return false
        }
    }

    /// Send a field intent and adopt only the committed projection.
    func enqueueStateCommand(_ command: StateCommand) {
        let previous = stateCommandTask
        stateCommandTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let transition = try await self.bridge.applyStateCommand(command)
                self.applyCoreState(transition.state, refreshPortfolio: false)
                await self.rebuildWalletDerivedStateFromCore()
            } catch {
                self.importError = error.localizedDescription
            }
        }
    }

    /// Send a pin command; the projection that comes back is the authority,
    /// not what was sent.
    func sendDashboardPinCommand(_ command: StateCommand) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let transition = try? await self.bridge.applyStateCommand(command) else {
                return
            }
            self.applyCoreState(transition.state)
        }
    }

    /// A bounded recent/pending projection, adopted with its core-derived summary.
    func adoptTransactionsFromCore(_ records: [TransactionRecord]) {
        setTransactionProjection(records)
    }
}
