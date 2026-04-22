// Rust→Swift observer bridges.
//
// The wallet/transactions/address_book event bus has been removed; Swift now
// owns those collections directly. Only the per-chain balance refresh
// observer remains — it pushes balance updates from the Rust refresh engine
// into AppState's `@Observable` mirrors on the main actor.

import Foundation

final class WalletBalanceObserver: BalanceObserverImpl, @unchecked Sendable {
    weak var store: AppState?
    nonisolated override init(noPointer: BalanceObserverImpl.NoPointer) {
        super.init(noPointer: noPointer)
    }
    nonisolated required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }
    nonisolated override func onBalanceUpdated(chainId: UInt32, walletId: String, summary: WalletSummary?) {
        _ = chainId
        guard let summary else { return }
        Task { @MainActor [weak self] in
            self?.store?.applyRustBalance(walletId: walletId, summary: summary)
        }
    }
    nonisolated override func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {
        _ = errors
        Task { @MainActor [weak self] in
            guard let store = self?.store else { return }
            if refreshed > 0 {
                store.isRefreshingChainBalances = false
                store.lastChainBalanceRefreshAt = Date()
                // Derived-state rebuilds + `persistWallets` are already driven
                // by `wallets.didSet` whenever a balance actually differed
                // (via `flushBalanceBatch`). Calling them again here ran a
                // redundant Keychain write + Rust FFI cascade every cycle
                // even when nothing changed.
            }
        }
    }
}
