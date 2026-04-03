import Foundation

enum WalletFetchLayer {
    static func loadMoreOnChainHistory(for walletIDs: Set<UUID>, using store: WalletStore) async {
        guard store.canLoadMoreOnChainHistory(for: walletIDs) else { return }
        store.isLoadingMoreOnChainHistory = true
        defer { store.isLoadingMoreOnChainHistory = false }

        let eligibleWalletIDs = Set(walletIDs.filter(store.canLoadMoreHistory(for:)))

        if store.hasBitcoinWallets {
            await store.refreshBitcoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBitcoinCashWallets {
            await store.refreshBitcoinCashTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBitcoinSVWallets {
            await store.refreshBitcoinSVTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasLitecoinWallets {
            await store.refreshLitecoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasDogecoinWallets {
            await store.refreshDogecoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasEthereumWallets {
            await store.refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasArbitrumWallets {
            await store.refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasOptimismWallets {
            await store.refreshEVMTokenTransactions(chainName: "Optimism", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBNBWallets {
            await store.refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasAvalancheWallets {
            await store.refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: false)
        }
        if store.wallets.contains(where: { $0.selectedChain == "Hyperliquid" && store.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") != nil }) {
            await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.wallets.contains(where: { $0.selectedChain == "Tron" && store.resolvedTronAddress(for: $0) != nil }) {
            await store.refreshTronTransactions(loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
    }

    static func refreshWalletBalance(_ walletID: UUID, using store: WalletStore) async {
        await store.withBalanceRefreshWindow {
            guard let wallet = store.wallets.first(where: { $0.id == walletID }) else { return }

            let updatedHoldings: [Coin]?

            switch wallet.selectedChain {
            case "Bitcoin":
                await store.refreshBitcoinBalances()
                return
            case "Bitcoin Cash":
                guard let address = store.resolvedBitcoinCashAddress(for: wallet) else { return }
                guard let balance = try? await BitcoinCashBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyBitcoinCashBalance(balance, to: wallet.holdings)
            case "Bitcoin SV":
                guard let address = store.resolvedBitcoinSVAddress(for: wallet) else { return }
                guard let balance = try? await BitcoinSVBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyBitcoinSVBalance(balance, to: wallet.holdings)
            case "Litecoin":
                guard let address = store.resolvedLitecoinAddress(for: wallet) else { return }
                guard let balance = try? await LitecoinBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyLitecoinBalance(balance, to: wallet.holdings)
            case "Dogecoin":
                await store.refreshDogecoinBalances()
                return
            case "Ethereum":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Ethereum") else { return }
                guard let portfolio = try? await store.fetchEthereumPortfolio(for: address) else { return }
                updatedHoldings = store.applyEthereumBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Ethereum Classic":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Ethereum Classic") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Ethereum Classic") else { return }
                updatedHoldings = store.applyETCBalances(nativeBalance: portfolio.nativeBalance, to: wallet.holdings)
            case "Arbitrum":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Arbitrum") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Arbitrum") else { return }
                updatedHoldings = store.applyArbitrumBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Optimism":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Optimism") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Optimism") else { return }
                updatedHoldings = store.applyOptimismBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "BNB Chain":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "BNB Chain") else { return }
                updatedHoldings = store.applyBNBBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Avalanche":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Avalanche") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Avalanche") else { return }
                updatedHoldings = store.applyAvalancheBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Hyperliquid":
                guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Hyperliquid") else { return }
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Hyperliquid") else { return }
                updatedHoldings = store.applyHyperliquidBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Tron":
                guard let address = store.resolvedTronAddress(for: wallet) else { return }
                guard let balances = try? await TronBalanceService.fetchBalances(
                    for: address,
                    trackedTokens: store.enabledTronTrackedTokens()
                ) else { return }
                let nativeBalance = store.resolvedTronNativeBalance(
                    fetchedNativeBalance: balances.trxBalance,
                    tokenBalances: balances.tokenBalances,
                    wallet: wallet
                )
                updatedHoldings = store.applyTronBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: balances.tokenBalances,
                    to: wallet.holdings
                )
            case "Solana":
                guard let address = store.resolvedSolanaAddress(for: wallet) else { return }
                guard let portfolio = try? await SolanaBalanceService.fetchPortfolio(
                    for: address,
                    trackedTokenMetadataByMint: store.enabledSolanaTrackedTokens()
                ) else { return }
                updatedHoldings = store.applySolanaPortfolio(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Cardano":
                guard let address = store.resolvedCardanoAddress(for: wallet) else { return }
                guard let balance = try? await CardanoBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyCardanoBalance(balance, to: wallet.holdings)
            case "XRP Ledger":
                guard let address = store.resolvedXRPAddress(for: wallet) else { return }
                guard let balance = try? await XRPBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyXRPBalance(balance, to: wallet.holdings)
            case "Stellar":
                guard let address = store.resolvedStellarAddress(for: wallet) else { return }
                guard let balance = try? await StellarBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyStellarBalance(balance, to: wallet.holdings)
            case "Monero":
                guard let address = store.resolvedMoneroAddress(for: wallet) else { return }
                guard let balance = try? await MoneroBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyMoneroBalance(balance, to: wallet.holdings)
            case "Sui":
                guard let address = store.resolvedSuiAddress(for: wallet) else { return }
                guard let portfolio = try? await SuiBalanceService.fetchPortfolio(
                    for: address,
                    trackedTokenMetadataByCoinType: store.enabledSuiTrackedTokens()
                ) else { return }
                updatedHoldings = store.applySuiBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Aptos":
                guard let address = store.resolvedAptosAddress(for: wallet) else { return }
                guard let portfolio = try? await AptosBalanceService.fetchPortfolio(
                    for: address,
                    trackedTokenMetadataByType: store.enabledAptosTrackedTokens()
                ) else { return }
                updatedHoldings = store.applyAptosBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "TON":
                guard let address = store.resolvedTONAddress(for: wallet) else { return }
                guard let portfolio = try? await TONBalanceService.fetchPortfolio(
                    for: address,
                    trackedTokenMetadataByMasterAddress: store.enabledTONTrackedTokens()
                ) else { return }
                updatedHoldings = store.applyTONBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: wallet.holdings
                )
            case "Internet Computer":
                guard let address = store.resolvedICPAddress(for: wallet) else { return }
                guard let balance = try? await ICPBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyICPBalance(balance, to: wallet.holdings)
            case "NEAR":
                guard let address = store.resolvedNearAddress(for: wallet) else { return }
                async let nativeBalanceTask = try? await NearBalanceService.fetchBalance(for: address)
                async let tokenBalancesTask = try? await NearBalanceService.fetchTrackedTokenBalances(
                    for: address,
                    trackedTokenMetadataByContract: store.enabledNearTrackedTokens()
                )
                let nativeBalance = await nativeBalanceTask
                let tokenBalances = await tokenBalancesTask
                updatedHoldings = store.applyNearBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: tokenBalances,
                    to: wallet.holdings
                )
            case "Polkadot":
                guard let address = store.resolvedPolkadotAddress(for: wallet) else { return }
                guard let balance = try? await PolkadotBalanceService.fetchBalance(for: address) else { return }
                updatedHoldings = store.applyPolkadotBalance(balance, to: wallet.holdings)
            default:
                return
            }

            guard let updatedHoldings,
                  let index = store.wallets.firstIndex(where: { $0.id == walletID }) else { return }
            store.wallets[index] = store.walletByReplacingHoldings(store.wallets[index], with: updatedHoldings)
            store.applyWalletCollectionSideEffects()
        }
    }
}
