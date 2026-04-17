import Foundation
enum WalletFetchLayer {
    static func loadMoreOnChainHistory(for walletIDs: Set<String>, using store: AppState) async {
        guard store.canLoadMoreOnChainHistory(for: walletIDs) else { return }
        store.isLoadingMoreOnChainHistory = true
        defer { store.isLoadingMoreOnChainHistory = false }
        let eligibleWalletIDs = Set(walletIDs.filter(store.canLoadMoreHistory(for:)))
        if store.hasWalletForChain("Bitcoin") { await store.refreshBitcoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Bitcoin Cash") { await store.refreshBitcoinCashTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Bitcoin SV") { await store.refreshBitcoinSVTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Litecoin") { await store.refreshLitecoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Dogecoin") { await store.refreshDogecoinTransactions(limit: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Ethereum") { await store.refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Arbitrum") { await store.refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Optimism") { await store.refreshEVMTokenTransactions(chainName: "Optimism", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("BNB Chain") { await store.refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Avalanche") { await store.refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Hyperliquid") { await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: AppState.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs) }
        if store.hasWalletForChain("Tron") { await store.refreshTronTransactions(loadMore: true, targetWalletIDs: eligibleWalletIDs) }}
}
