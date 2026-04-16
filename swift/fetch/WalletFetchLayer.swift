import Foundation
enum WalletFetchLayer {
    static func loadMoreOnChainHistory(for walletIDs: Set<String>, using store: AppState) async {
        guard store.canLoadMoreOnChainHistory(for: walletIDs) else { return }
        store.isLoadingMoreOnChainHistory = true
        defer { store.isLoadingMoreOnChainHistory = false }
        let eligibleWalletIDs = Set(walletIDs.filter(store.canLoadMoreHistory(for:)))
        if store.hasBitcoinWallets { await store.refreshBitcoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasBitcoinCashWallets { await store.refreshBitcoinCashTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasBitcoinSVWallets { await store.refreshBitcoinSVTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasLitecoinWallets { await store.refreshLitecoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasDogecoinWallets { await store.refreshDogecoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasEthereumWallets { await store.refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasArbitrumWallets { await store.refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasOptimismWallets { await store.refreshEVMTokenTransactions(chainName: "Optimism", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasBNBWallets { await store.refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasAvalancheWallets { await store.refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.wallets.contains(where: { $0.selectedChain == "Hyperliquid" && store.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") != nil }) {
            await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.wallets.contains(where: { $0.selectedChain == "Tron" && store.resolvedTronAddress(for: $0) != nil }) {
            await store.refreshTronTransactions(loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }}
}
