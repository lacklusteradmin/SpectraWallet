import Foundation
final class WalletBalanceObserver: BalanceObserverImpl, @unchecked Sendable {
    weak var store: AppState?
    nonisolated override init(noPointer: BalanceObserverImpl.NoPointer) {
        super.init(noPointer: noPointer)
    }
    nonisolated required init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        super.init(unsafeFromRawPointer: pointer)
    }
    nonisolated override func onBalanceUpdated(chainId: UInt32, walletId: String, balanceJson: String) {
        Task { @MainActor [weak self] in
            self?.store?.applyRustBalance(chainId: chainId, walletId: walletId, json: balanceJson)
        }}
    nonisolated override func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {
        _ = errors
        Task { @MainActor [weak self] in
            guard let store = self?.store else { return }
            if refreshed > 0 {
                store.isRefreshingChainBalances = false
                store.lastChainBalanceRefreshAt = Date()
                store.applyWalletCollectionSideEffects()
            }}}
}
