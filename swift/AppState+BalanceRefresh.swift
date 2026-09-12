import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Core has committed the refresh. Coalesce projection reads, never write balances back.
    func applyRustBalance(walletId: String, summary: WalletSummary) {
        balanceFlushTask?.cancel()
        balanceFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            let before = self.wallets
            guard let records = try? await WalletServiceBridge.shared.storedWallets(), !Task.isCancelled else { return }
            // A user mutation during the read wins; its own projection remains current.
            guard self.wallets == before else { return }
            self.adoptWalletsFromCore(records)
            self.rebuildWalletDerivedState()
            self.rebuildDashboardDerivedState()
        }
    }

    /// Tell the engine the wallet list changed. Core builds the entries.
    ///
    /// This used to map the wallet projection into `(chain, wallet, address)`
    /// triples and hand them over — resolving each address by deriving it from
    /// the seed, so a sealed wallet or one this platform could not resolve was
    /// dropped from the refresh with a `print` and no other trace.
    func updateRefreshEngineEntries() {
        Task(priority: .utility) {
            let count = (try? await WalletServiceBridge.shared.syncRefreshEntries()) ?? 0
            if count > 0 {
                try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
            }
        }
    }

    /// Install the Rust balance-refresh observer and start the periodic
    /// refresh loop. Interval is driven by the user's
    /// `automaticRefreshFrequencyMinutes` preference (default 5 min) — NOT a
    /// hardcoded 30 s, which was firing at 10× the requested rate and
    /// keeping the phone warm with constant radio activity.
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
        observer.store = self
        Task { [weak self] in
            try? WalletServiceBridge.shared.setBalanceObserver(observer)
            await self?.restartBalanceRefreshForCurrentConfiguration()
        }
        updateRefreshEngineEntries()
    }
    /// Stop-then-start the refresh engine using the current effective
    /// interval. Called when the refresh-frequency preference changes or
    /// when the app transitions active/inactive — contexts where we want
    /// the interval value or the running state to actually change.
    func restartBalanceRefreshForCurrentConfiguration() async {
        try? WalletServiceBridge.shared.stopBalanceRefresh()
        guard appIsActive else { return }
        // No wallets = no entries to refresh. Keeping the tokio interval
        // alive just to wake every N minutes and no-op is pure idle heat,
        // so don't start it at all until the user imports a wallet.
        // `applyWalletCollectionSideEffects` calls
        // `startBalanceRefreshIfNeeded` when wallets change.
        guard !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

    /// Idempotent start path used after wallet mutations. Skips work when
    /// the app is inactive or there are no wallets, and relies on the
    /// Rust engine's own "already running" guard to make repeat calls
    /// cheap instead of stopping + restarting each time.
    func startBalanceRefreshIfNeeded() async {
        guard appIsActive, !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

}
