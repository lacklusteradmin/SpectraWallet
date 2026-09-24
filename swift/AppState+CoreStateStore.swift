// MARK: - State commands
//
// Core is the canonical store for wallets, settings, contacts, tokens, alerts
// and pins; the `@Observable` values on AppState are projections of it, with
// one writer each. Every change is a `StateCommand` sent through the one queue
// below, and what core committed lands back through `applyCoreState` and the
// portfolio snapshot. Assigning a projection directly is a bug.

import Foundation

@MainActor
extension AppState {
    /// Send a command after every command issued before it, then adopt what core
    /// committed. `then` runs after adoption, inside the queue, with the result.
    ///
    /// Core serialises its own writes and stamps each state with a revision, so
    /// adoption order is already safe; the queue keeps the order the user acted
    /// in, so a later edit is never overtaken by an earlier one.
    @discardableResult
    func enqueueStateCommand(
        _ command: StateCommand,
        then handle: @escaping @MainActor (AppState, Result<StateTransition, Error>) async -> Void = { _, _ in }
    ) -> Task<StateTransition, Error> {
        let previous = stateCommandTask
        let task = Task { @MainActor [weak self] () throws -> StateTransition in
            await previous?.value
            guard let self else { throw CancellationError() }
            do {
                let transition = try await self.bridge.ready().applyStateCommand(command: command)
                self.applyCoreState(transition.state)
                await self.rebuildWalletDerivedStateFromCore()
                await handle(self, .success(transition))
                return transition
            } catch {
                await handle(self, .failure(error))
                throw error
            }
        }
        stateCommandTask = Task { _ = try? await task.value }
        return task
    }

    /// Send a command, wait for it to be committed and adopted, and return it.
    @discardableResult
    func applyStateCommand(_ command: StateCommand) async throws -> StateTransition {
        try await enqueueStateCommand(command).value
    }

    /// Send a command whose only failure surface is `commandError`.
    func sendStateCommand(_ command: StateCommand) {
        enqueueStateCommand(command) { store, result in
            switch result {
            case .success: store.commandError = nil
            case .failure(let error): store.commandError = error.localizedDescription
            }
        }
    }

    /// Wait until every command issued so far has been committed and adopted.
    func awaitPendingStateCommands() async {
        await stateCommandTask?.value
    }

    @discardableResult
    func removeWallet(id: String) async -> Bool {
        do {
            try await applyStateCommand(.removeWallet(walletId: id))
            await refreshTransactionProjection()
            commandError = nil
            return true
        } catch {
            commandError = error.localizedDescription
            return false
        }
    }

    /// A bounded recent/pending projection, adopted with its core-derived summary.
    func adoptTransactionsFromCore(_ records: [TransactionRecord]) {
        setTransactionProjection(records)
    }
}
