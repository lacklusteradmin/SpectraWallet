// Rust→Swift observer bridge for the balance refresh engine.
//
// Core calls these; nothing in Swift does. A balance update means core has
// committed a wallet's new state; Swift re-reads the projection for rendering.

import Foundation

final class WalletBalanceObserver: BalanceObserver, @unchecked Sendable {
    weak var store: AppState?
    func onBalanceUpdated(chainId: String, walletId: String, summary: WalletState?) {
        // No logging here: this carries every holding's amount, and `print`
        // put a wallet's balances in the device log on every sweep.
        guard summary != nil else { return }
        Task { @MainActor [weak self] in
            self?.store?.walletBalancesDidChange()
        }
    }
    func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {
        Task { @MainActor [weak self] in
            guard let store = self?.store else { return }
            await store.performCoreRefresh(.balancesUpdated)
        }
    }
}
