// Rust→Swift observer bridge for the balance refresh engine.
//
// Core calls these; nothing in Swift does. `onBalanceUpdated` carries one
// committed wallet projection; Swift coalesces reads for rendering.

import Foundation

final class WalletBalanceObserver: BalanceObserver, @unchecked Sendable {
    weak var store: AppState?
    func onBalanceUpdated(chainId: String, walletId: String, summary: WalletState?) {
        _ = chainId
        guard let summary else { return }
        print("[BalanceRefresh] onBalanceUpdated chain=\(chainId) wallet=\(walletId) holdings=\(summary.holdings.map { "\($0.symbol):\($0.amount)" })")
        Task { @MainActor [weak self] in
            self?.store?.applyRustBalance(walletId: walletId, summary: summary)
        }
    }
    func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {
        print("[BalanceRefresh] cycle complete refreshed=\(refreshed) errors=\(errors)")
        Task { @MainActor [weak self] in
            guard let store = self?.store else {
                print("[BalanceRefresh] cycle complete — store is nil!")
                return
            }
            if refreshed > 0 {
                store.lastChainBalanceRefreshAt = Date()
                // Derived-state rebuilds are already driven
                // by `wallets.didSet` whenever a balance actually differed
                // (via `flushBalanceBatch`). Calling them again here ran a
                // redundant Keychain write + Rust FFI cascade every cycle
                // even when nothing changed.
            }
            await store.performCoreRefresh(.balancesUpdated)
        }
    }
}
