// MARK: - Wallet/transactions/address-book mutation helpers
//
// Core is the canonical store for all three collections; the `@Observable`
// arrays on AppState are projections of it, with one writer each. These helpers
// send the `StateCommand` and update the projection, so direct assignment to
// `self.wallets`, `self.transactions` or `self.addressBook` is a bug — it
// desynchronises the projection from the store rather than failing loudly.
//
// This comment used to say the opposite ("Swift's arrays are the canonical
// store … There is no Rust round-trip"), and `docs/ARCHITECTURE.md` quoted it
// as evidence for a claim that had also stopped being true.

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

    /// Store these wallets, adding or updating as core determines.
    @discardableResult
    func recordWallets(_ records: [ImportedWallet]) async -> Bool {
        guard !records.isEmpty else { return true }
        var next = wallets
        for record in records {
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else {
                next.append(record)
            }
        }
        setWalletProjection(next)
        for record in records {
            let summary = record.summary(isWatchOnly: isWatchOnlyWallet(record))
            guard
                (try? await WalletServiceBridge.shared.applyStateCommand(
                    .upsertWallet(wallet: summary))) != nil
            else { return false }
        }
        return true
    }

    func recordWallet(_ record: ImportedWallet) async { await recordWallets([record]) }

    /// Update wallets that core still has, creating none.
    ///
    /// Balance refresh uses this. A refresh result can arrive after the user
    /// deleted the wallet, and an upsert would bring it back.
    func updateWalletsIfPresent(_ records: [ImportedWallet]) async {
        guard !records.isEmpty else { return }
        var next = wallets
        for record in records {
            guard let index = next.firstIndex(where: { $0.id == record.id }) else { continue }
            next[index] = record
        }
        setWalletProjection(next)
        for record in records {
            let summary = record.summary(isWatchOnly: isWatchOnlyWallet(record))
            _ = try? await WalletServiceBridge.shared.applyStateCommand(
                .updateWalletIfPresent(wallet: summary))
        }
    }

    func removeWallet(id: String) async {
        setWalletProjection(wallets.filter { $0.id != id })
        _ = try? await WalletServiceBridge.shared.applyStateCommand(.removeWallet(walletId: id))
    }

    /// Remove every wallet core holds.
    ///
    /// Reads the ids from core rather than from the projection: "clear all"
    /// must mean all, not "the ones this instance happens to be showing".
    func clearAllWallets() async {
        setWalletProjection([])
        guard let stored = try? await WalletServiceBridge.shared.storedWallets() else { return }
        for wallet in stored {
            _ = try? await WalletServiceBridge.shared.applyStateCommand(
                .removeWallet(walletId: wallet.id))
        }
    }

    // Synchronous entry points for UI actions that cannot await. The
    // projection updates now — a rename must show immediately — and only the
    // command is deferred.
    func recordWalletDetached(_ record: ImportedWallet) {
        var next = wallets
        if let index = next.firstIndex(where: { $0.id == record.id }) {
            next[index] = record
        } else {
            next.append(record)
        }
        setWalletProjection(next)
        let summary = record.summary(isWatchOnly: isWatchOnlyWallet(record))
        Task.detached(priority: .utility) {
            _ = try? await WalletServiceBridge.shared.applyStateCommand(
                .upsertWallet(wallet: summary))
        }
    }

    func clearAllWalletsDetached() {
        let ids = wallets.map(\.id)
        setWalletProjection([])
        Task.detached(priority: .utility) {
            for id in ids {
                _ = try? await WalletServiceBridge.shared.applyStateCommand(
                    .removeWallet(walletId: id))
            }
        }
    }

    /// Replace the pinned dashboard set. Core normalises and de-duplicates, so
    /// the projection that comes back is the authority, not what was sent.
    func setPinnedDashboardAssets(_ symbols: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let epoch = self.beginCoreStateRead()
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .setPinnedDashboardAssets(symbols: symbols))
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


    // ── Transactions ──────────────────────────────────────────────────
    //
    // Core owns the store. Each of these updates the projection immediately so
    // the UI stays responsive, then sends the command that makes it durable.
    // Nothing here computes a persistence delta: whether a record is new is a
    // property of the store, and core answers that.

    /// Store these records, adding or updating as core determines.
    ///
    /// Covers recording a send, merging a fetched history page, and updating a
    /// status. Callers pass whatever they want stored; unchanged records in the
    /// batch are harmless — the whole batch is one SQLite transaction.
    func recordTransactions(_ records: [TransactionRecord]) {
        guard !records.isEmpty else { return }
        var next = transactions
        for record in records {
            if let index = next.firstIndex(where: { $0.id == record.id }) {
                next[index] = record
            } else {
                next.insert(record, at: 0)
            }
        }
        setTransactionProjection(next)
        sendTransactionCommand(.upsert(records: records.map(\.persistedSnapshot)))
    }

    func recordTransaction(_ record: TransactionRecord) { recordTransactions([record]) }

    func removeTransactions(withIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let doomed = Set(ids)
        setTransactionProjection(transactions.filter { !doomed.contains($0.id) })
        sendTransactionCommand(.remove(ids: ids.map { $0.uuidString.lowercased() }))
    }

    func removeTransactions(forWalletID walletID: String) {
        setTransactionProjection(transactions.filter { $0.walletID != walletID })
        sendTransactionCommand(.removeForWallet(walletId: walletID))
    }

    func clearAllTransactions() {
        setTransactionProjection([])
        sendTransactionCommand(.clear)
    }

    /// Replace the projection without touching the store. Only for loading what
    /// core already has.
    func adoptTransactionsFromCore(_ records: [TransactionRecord]) {
        withSuspendedTransactionSideEffects { setTransactionProjection(records) }
    }

    private func sendTransactionCommand(_ command: TransactionCommand) {
        Task.detached(priority: .utility) {
            try? await WalletServiceBridge.shared.applyTransactionCommand(command)
        }
    }

    // Address-book mutation helpers are gone: core owns that list, and it is
    // changed by `StateCommand` rather than by assigning to an array here.
}
