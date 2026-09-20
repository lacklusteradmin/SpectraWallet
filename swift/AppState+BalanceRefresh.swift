import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Core has committed a wallet's new balances. Re-read the projection,
    /// coalescing a sweep's worth of updates into one read; nothing is written
    /// back.
    ///
    /// Took the wallet id and its new state, and read neither: the projection
    /// is re-read whole either way.
    func walletBalancesDidChange() {
        balanceFlushTask?.cancel()
        balanceFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            await self.rebuildWalletDerivedStateFromCore()
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
    }
    /// Stop-then-start the refresh engine using the current effective
    /// interval. Called when the refresh-frequency preference changes or
    /// when the app transitions active/inactive — contexts where we want
    /// the interval value or the running state to actually change.
    func restartBalanceRefreshForCurrentConfiguration() async {
        try? await WalletServiceBridge.shared.configureBalanceRefresh(appIsActive: appIsActive)
    }
}
