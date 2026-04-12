import Foundation

/// Swift implementation of the UniFFI `BalanceObserver` callback interface.
///
/// Rust's `BalanceRefreshEngine` calls `onBalanceUpdated` for each wallet
/// after a successful fetch. This class dispatches the result to the main
/// actor so SwiftUI re-renders correctly.
final class WalletBalanceObserver: BalanceObserverImpl {
    weak var store: WalletStore?

    init() {
        super.init(noPointer: BalanceObserverImpl.NoPointer())
    }

    required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }

    override func onBalanceUpdated(chainId: UInt32, walletId: String, balanceJson: String) {
        Task { @MainActor [weak self] in
            self?.store?.applyRustBalance(chainId: chainId, walletId: walletId, json: balanceJson)
        }
    }

    override func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {
        _ = errors
        Task { @MainActor [weak self] in
            guard let store = self?.store else { return }
            if refreshed > 0 {
                store.isRefreshingChainBalances = false
                store.lastChainBalanceRefreshAt = Date()
                store.applyWalletCollectionSideEffects()
            }
        }
    }
}
