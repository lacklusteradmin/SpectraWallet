import Foundation

extension WalletStore {
    var wallets: [ImportedWallet] {
        get { portfolioState.wallets }
        set { portfolioState.wallets = newValue }
    }

    var cachedWalletByID: [UUID: ImportedWallet] {
        get { portfolioState.walletByID }
        set { portfolioState.walletByID = newValue }
    }

    var cachedWalletByIDString: [String: ImportedWallet] {
        get { portfolioState.walletByIDString }
        set { portfolioState.walletByIDString = newValue }
    }

    var cachedIncludedPortfolioWallets: [ImportedWallet] {
        get { portfolioState.includedPortfolioWallets }
        set { portfolioState.includedPortfolioWallets = newValue }
    }

    var cachedIncludedPortfolioHoldings: [Coin] {
        get { portfolioState.includedPortfolioHoldings }
        set { portfolioState.includedPortfolioHoldings = newValue }
    }

    var cachedIncludedPortfolioHoldingsBySymbol: [String: [Coin]] {
        get { portfolioState.includedPortfolioHoldingsBySymbol }
        set { portfolioState.includedPortfolioHoldingsBySymbol = newValue }
    }

    var cachedUniqueWalletPriceRequestCoins: [Coin] {
        get { portfolioState.uniqueWalletPriceRequestCoins }
        set { portfolioState.uniqueWalletPriceRequestCoins = newValue }
    }

    var cachedPortfolio: [Coin] {
        get { portfolioState.portfolio }
        set { portfolioState.portfolio = newValue }
    }

    var cachedAvailableSendCoinsByWalletID: [String: [Coin]] {
        get { portfolioState.availableSendCoinsByWalletID }
        set { portfolioState.availableSendCoinsByWalletID = newValue }
    }

    var cachedAvailableReceiveCoinsByWalletID: [String: [Coin]] {
        get { portfolioState.availableReceiveCoinsByWalletID }
        set { portfolioState.availableReceiveCoinsByWalletID = newValue }
    }

    var cachedAvailableReceiveChainsByWalletID: [String: [String]] {
        get { portfolioState.availableReceiveChainsByWalletID }
        set { portfolioState.availableReceiveChainsByWalletID = newValue }
    }

    var cachedSendEnabledWallets: [ImportedWallet] {
        get { portfolioState.sendEnabledWallets }
        set { portfolioState.sendEnabledWallets = newValue }
    }

    var cachedReceiveEnabledWallets: [ImportedWallet] {
        get { portfolioState.receiveEnabledWallets }
        set { portfolioState.receiveEnabledWallets = newValue }
    }

    var cachedRefreshableChainNames: Set<String> {
        get { portfolioState.refreshableChainNames }
        set { portfolioState.refreshableChainNames = newValue }
    }

    var cachedSigningMaterialWalletIDs: Set<UUID> {
        get { portfolioState.signingMaterialWalletIDs }
        set { portfolioState.signingMaterialWalletIDs = newValue }
    }

    var cachedPrivateKeyBackedWalletIDs: Set<UUID> {
        get { portfolioState.privateKeyBackedWalletIDs }
        set { portfolioState.privateKeyBackedWalletIDs = newValue }
    }

    @discardableResult
    func applyIndexedWalletHoldingUpdates(
        _ updates: [(index: Int, holdings: [Coin])],
        to walletSnapshot: [ImportedWallet]
    ) -> Bool {
        guard !updates.isEmpty else { return false }

        var updatedWallets = walletSnapshot
        var changed = false

        for update in updates {
            guard updatedWallets.indices.contains(update.index) else { continue }
            let existingWallet = updatedWallets[update.index]
            guard !walletHoldingSnapshotsMatch(existingWallet.holdings, update.holdings) else { continue }
            updatedWallets[update.index] = walletByReplacingHoldings(existingWallet, with: update.holdings)
            changed = true
        }

        if changed {
            wallets = updatedWallets
        }

        return changed
    }

    private func walletHoldingSnapshotsMatch(_ lhs: [Coin], _ rhs: [Coin]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (left, right) in zip(lhs, rhs) {
            guard left.name == right.name,
                  left.symbol == right.symbol,
                  left.marketDataID == right.marketDataID,
                  left.coinGeckoID == right.coinGeckoID,
                  left.chainName == right.chainName,
                  left.tokenStandard == right.tokenStandard,
                  left.contractAddress == right.contractAddress,
                  abs(left.amount - right.amount) < 0.0000000001,
                  abs(left.priceUSD - right.priceUSD) < 0.0000000001,
                  left.mark == right.mark else {
                return false
            }
        }

        return true
    }
}
