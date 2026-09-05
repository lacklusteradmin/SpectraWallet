// Rust→Swift observer bridge for the balance refresh engine.
//
// Core calls these; nothing in Swift does. `onBalanceUpdated` carries one
// wallet's native balance, which `applyRustBalance` merges into the holding
// and writes back through a `StateCommand` — the collections themselves are
// core's (see `AppState+CoreStateStore.swift`).

import Foundation

final class WalletBalanceObserver: BalanceObserver, @unchecked Sendable {
    weak var store: AppState?
    func onBalanceUpdated(chainId: String, walletId: String, summary: WalletSummary?) {
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
            // Always clear the refreshing flag — if it only cleared on
            // `refreshed > 0`, an all-error cycle would leave it stuck
            // permanently and block every subsequent `refreshChainBalances`
            // call via its `guard !isRefreshingChainBalances` guard.
            store.isRefreshingChainBalances = false
            if refreshed > 0 {
                store.lastChainBalanceRefreshAt = Date()
                // Derived-state rebuilds are already driven
                // by `wallets.didSet` whenever a balance actually differed
                // (via `flushBalanceBatch`). Calling them again here ran a
                // redundant Keychain write + Rust FFI cascade every cycle
                // even when nothing changed.
            }
            await store.refreshKnownTokenBalances()
            // Refresh prices immediately after balances update so the portfolio
            // total reflects fresh amounts without waiting for the next
            // maintenance-loop tick (which can be up to 5 min away).
            _ = await store.refreshLivePrices()
        }
    }
}
