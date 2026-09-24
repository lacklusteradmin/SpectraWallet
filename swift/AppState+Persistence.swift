import Foundation
extension AppState {
    func reloadCoreProjections() async {
        // Core-owned domain state first: it is the authority, so anything
        // loaded after it must not contradict it.
        await loadCoreOwnedState()
        await diagnostics.loadFromSQLite()
        // Opening the state folds this build's built-in tokens in, and carries
        // settings, alerts and contacts; the five preferences this platform
        // keeps were read from `UserDefaults` when `preferences` was created.
        await rebuildWalletDerivedStateFromCore()
        await refreshTransactionProjection()
    }
}
