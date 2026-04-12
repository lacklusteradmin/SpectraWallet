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

}
