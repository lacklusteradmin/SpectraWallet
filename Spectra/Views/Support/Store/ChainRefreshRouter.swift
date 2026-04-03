import Foundation

extension WalletStore {
    func performUserInitiatedRefresh(forChain chainName: String) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if appIsActive {
            await refreshPendingTransactions(includeHistoryRefreshes: false)
        }

        await withBalanceRefreshWindow {
            switch chainName {
            case "Bitcoin":
                await refreshBitcoinBalances()
                await refreshBitcoinTransactions(limit: 20)
            case "Bitcoin Cash":
                await refreshBitcoinCashBalances()
                await refreshBitcoinCashTransactions(limit: 20)
            case "Bitcoin SV":
                await refreshBitcoinSVBalances()
                await refreshBitcoinSVTransactions(limit: 20)
            case "Litecoin":
                await refreshLitecoinBalances()
                await refreshLitecoinTransactions(limit: 20)
            case "Dogecoin":
                await refreshDogecoinBalances()
                await refreshDogecoinTransactions(limit: 20)
            case "Ethereum":
                await refreshEthereumBalances()
                await refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: 20, loadMore: false)
            case "Arbitrum":
                await refreshArbitrumBalances()
                await refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: 20, loadMore: false)
            case "Optimism":
                await refreshOptimismBalances()
                await refreshEVMTokenTransactions(chainName: "Optimism", maxResults: 20, loadMore: false)
            case "Ethereum Classic":
                await refreshETCBalances()
            case "BNB Chain":
                await refreshBNBBalances()
                await refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: 20, loadMore: false)
            case "Avalanche":
                await refreshAvalancheBalances()
                await refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: 20, loadMore: false)
            case "Hyperliquid":
                await refreshHyperliquidBalances()
                await refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: 20, loadMore: false)
            case "Tron":
                await refreshTronBalances()
                await refreshTronTransactions(loadMore: false)
            case "Solana":
                await refreshSolanaBalances()
                await refreshSolanaTransactions(loadMore: false)
            case "Cardano":
                await refreshCardanoBalances()
                await refreshCardanoTransactions(loadMore: false)
            case "XRP Ledger":
                await refreshXRPBalances()
                await refreshXRPTransactions(loadMore: false)
            case "Stellar":
                await refreshStellarBalances()
                await refreshStellarTransactions(loadMore: false)
            case "Monero":
                await refreshMoneroBalances()
                await refreshMoneroTransactions(loadMore: false)
            case "Sui":
                await refreshSuiBalances()
                await refreshSuiTransactions(loadMore: false)
            case "Aptos":
                await refreshAptosBalances()
                await refreshAptosTransactions(loadMore: false)
            case "TON":
                await refreshTONBalances()
                await refreshTONTransactions(loadMore: false)
            case "Internet Computer":
                await refreshICPBalances()
                await refreshICPTransactions(loadMore: false)
            case "NEAR":
                await refreshNearBalances()
                await refreshNearTransactions(loadMore: false)
            case "Polkadot":
                await refreshPolkadotBalances()
                await refreshPolkadotTransactions(loadMore: false)
            default:
                await performUserInitiatedRefresh()
                return
            }
        }

        await refreshLivePrices()
        await refreshFiatExchangeRatesIfNeeded()
        recordPerformanceSample(
            "user_refresh_chain",
            startedAt: startedAt,
            metadata: chainName
        )
    }
}
