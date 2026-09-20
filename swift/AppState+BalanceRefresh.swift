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

    /// Install the observer; core owns automatic refresh cadence.
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
        observer.store = self
        Task { [weak self] in
            try? WalletServiceBridge.shared.setBalanceObserver(observer)
            await self?.restartBalanceRefreshForCurrentConfiguration()
        }
    }
    /// Forward activity so core starts or stops periodic balance refresh.
    func restartBalanceRefreshForCurrentConfiguration() async {
        try? await WalletServiceBridge.shared.configureBalanceRefresh(appIsActive: appIsActive)
    }
}
