// Rust→Swift observer for core's refresh engine.
//
// Core calls these; nothing in Swift does. Every sweep ends with a completed
// refresh that says what changed and what to notify the user about; Swift
// re-reads those projections once and delivers native effects.

import Foundation

final class WalletRefreshObserver: RefreshObserver, @unchecked Sendable {
    weak var store: AppState?
    // Per-wallet progress is for one-shot callers such as the CLI; the app
    // reads the portfolio once, when the sweep's refresh completes. No
    // logging: a summary carries every holding's amount.
    func onBalanceUpdated(chainId: String, walletId: String, summary: WalletState?) {}
    func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) {}
    func onRefreshComplete(result: AppRefreshResult) {
        Task { @MainActor [weak self] in
            await self?.store?.adoptRefreshResult(result)
        }
    }
    func onTorStatusChanged(status: TorStatus) {
        Task { @MainActor [weak self] in
            self?.store?.torStatus = status
        }
    }
}
