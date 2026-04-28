import Foundation

/// Bundled derived state of `AppState.wallets`. Every field is a pure
/// projection of the wallet collection (plus a few signing/availability
/// inputs), recomputed in one shot by `_rebuildWalletDerivedStateBody`.
/// Treating these fields as one value — assigned as a unit — means readers
/// see one observable update per rebuild instead of 17 ordered mutations,
/// and callers can reason about cache freshness as a single revision.
struct WalletDerivedCache {
    var walletByID: [String: ImportedWallet]
    var walletByIDString: [String: ImportedWallet]
    var includedPortfolioWallets: [ImportedWallet]
    var includedPortfolioHoldings: [Coin]
    var includedPortfolioHoldingsBySymbol: [String: [Coin]]
    var uniqueWalletPriceRequestCoins: [Coin]
    var portfolio: [Coin]
    var availableSendCoinsByWalletID: [String: [Coin]]
    var availableReceiveCoinsByWalletID: [String: [Coin]]
    var availableReceiveChainsByWalletID: [String: [String]]
    var sendEnabledWallets: [ImportedWallet]
    var receiveEnabledWallets: [ImportedWallet]
    var refreshableChainNames: Set<String>
    var signingMaterialWalletIDs: Set<String>
    var privateKeyBackedWalletIDs: Set<String>
    var passwordProtectedWalletIDs: Set<String>
    var secretDescriptorsByWalletID: [String: CoreWalletRustSecretMaterialDescriptor]

    static let empty = WalletDerivedCache(
        walletByID: [:],
        walletByIDString: [:],
        includedPortfolioWallets: [],
        includedPortfolioHoldings: [],
        includedPortfolioHoldingsBySymbol: [:],
        uniqueWalletPriceRequestCoins: [],
        portfolio: [],
        availableSendCoinsByWalletID: [:],
        availableReceiveCoinsByWalletID: [:],
        availableReceiveChainsByWalletID: [:],
        sendEnabledWallets: [],
        receiveEnabledWallets: [],
        refreshableChainNames: [],
        signingMaterialWalletIDs: [],
        privateKeyBackedWalletIDs: [],
        passwordProtectedWalletIDs: [],
        secretDescriptorsByWalletID: [:]
    )
}
