import Foundation

/// Bundled derived state of `AppState.wallets`, as core resolved it.
/// Assigned as one value by `applyWalletDerivedState`, so readers see one
/// observable update per rebuild rather than a field at a time.
///
/// Every field here has a reader. State the app collects but never shows is
/// not a cache, it is a second copy of core's answer going stale in the dark.
struct WalletDerivedCache {
    var resolvedAddressesByWalletId: [String: [String: String]]
    var walletById: [String: WalletView]
    var includedPortfolioWallets: [WalletView]
    var portfolio: [Coin]
    var availableSendCoinsByWalletId: [String: [Coin]]
    var availableReceiveCoinsByWalletId: [String: [Coin]]
    var sendEnabledWallets: [WalletView]
    var receiveEnabledWallets: [WalletView]
    var refreshableChainNames: Set<String>

    static let empty = WalletDerivedCache(
        resolvedAddressesByWalletId: [:],
        walletById: [:],
        includedPortfolioWallets: [],
        portfolio: [],
        availableSendCoinsByWalletId: [:],
        availableReceiveCoinsByWalletId: [:],
        sendEnabledWallets: [],
        receiveEnabledWallets: [],
        refreshableChainNames: []
    )
}
