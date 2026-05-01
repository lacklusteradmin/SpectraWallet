import Foundation
struct WalletChainRefreshDescriptor {
    let chainID: WalletChainID
    let executeRefresh: (AppState, Bool) async -> Void
    let executeBalancesOnly: (AppState) async -> Void
    let executeHistoryOnly: ((AppState) async -> Void)?
    var chainName: String { chainID.displayName }
    init(
        chainID: WalletChainID, executeRefresh: @escaping (AppState, Bool) async -> Void,
        executeBalancesOnly: @escaping (AppState) async -> Void = { await $0.refreshBalances() },
        executeHistoryOnly: ((AppState) async -> Void)? = nil
    ) {
        self.chainID = chainID
        self.executeRefresh = executeRefresh
        self.executeBalancesOnly = executeBalancesOnly
        self.executeHistoryOnly = executeHistoryOnly
    }
    static func evm(_ chainName: String) -> WalletChainRefreshDescriptor {
        WalletChainRefreshDescriptor(
            chainID: WalletChainID(chainName)!,
            executeRefresh: { store, refreshHistory in
                await store.refreshBalances()
                if refreshHistory { await store.refreshEVMTokenTransactions(chainName: chainName, loadMore: false) }
                await store.refreshPendingEVMTransactions(chainName: chainName)
            }, executeHistoryOnly: { store in await store.refreshEVMTokenTransactions(chainName: chainName) }
        )
    }
}
extension AppState {
    var lastHistoryRefreshAtByChainID: [WalletChainID: Date] {
        get {
            Dictionary(
                uniqueKeysWithValues: lastHistoryRefreshAtByChain.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }
                }
            )
        }
        set {
            lastHistoryRefreshAtByChain = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.displayName, $0.value) }
            )
        }
    }
    var plannedChainRefreshDescriptors: [WalletChainRefreshDescriptor] {
        [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinTransactions()
                }, executeHistoryOnly: { store in await store.refreshBitcoinTransactions(limit: 20, loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin Cash")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin Cash")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin Cash")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinCashTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinCashTransactions()
                }, executeHistoryOnly: { store in await store.refreshBitcoinCashTransactions(limit: 20, loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin SV")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin SV")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin SV")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshBitcoinSVTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingBitcoinSVTransactions()
                }, executeHistoryOnly: { store in await store.refreshBitcoinSVTransactions(limit: 20, loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Litecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Litecoin")
                    await store.refreshUTXOReceiveReservationState(chainName: "Litecoin")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshLitecoinTransactions(limit: 20, loadMore: false) }
                    await store.refreshPendingLitecoinTransactions()
                }, executeHistoryOnly: { store in await store.refreshLitecoinTransactions(limit: 20, loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Dogecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Dogecoin")
                    await store.refreshUTXOReceiveReservationState(chainName: "Dogecoin")
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshDogecoinTransactions(loadMore: false) }
                    await store.refreshPendingDogecoinTransactions()
                }, executeHistoryOnly: { store in await store.refreshDogecoinTransactions(loadMore: false) }
            ),
            .evm("Ethereum"), .evm("Arbitrum"), .evm("Optimism"), .evm("Ethereum Classic"),
            .evm("BNB Chain"), .evm("Avalanche"), .evm("Hyperliquid"), .evm("Polygon"), .evm("Base"),
            .evm("Linea"), .evm("Scroll"), .evm("Blast"), .evm("Mantle"),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Tron")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshTronTransactions(loadMore: false) }
                    await store.refreshPendingTronTransactions()
                }, executeHistoryOnly: { store in await store.refreshTronTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Solana")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshSolanaTransactions(loadMore: false) }
                    await store.refreshPendingSolanaTransactions()
                }, executeHistoryOnly: { store in await store.refreshSolanaTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Cardano")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshCardanoTransactions(loadMore: false) }
                    await store.refreshPendingCardanoTransactions()
                }, executeHistoryOnly: { store in await store.refreshCardanoTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("XRP Ledger")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshXRPTransactions(loadMore: false) }
                    await store.refreshPendingXRPTransactions()
                }, executeHistoryOnly: { store in await store.refreshXRPTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Stellar")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshStellarTransactions(loadMore: false) }
                    await store.refreshPendingStellarTransactions()
                }, executeHistoryOnly: { store in await store.refreshStellarTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Monero")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshMoneroTransactions(loadMore: false) }
                    await store.refreshPendingMoneroTransactions()
                }, executeHistoryOnly: { store in await store.refreshMoneroTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Sui")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshSuiTransactions(loadMore: false) }
                    await store.refreshPendingSuiTransactions()
                }, executeHistoryOnly: { store in await store.refreshSuiTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("NEAR")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshNearTransactions(loadMore: false) }
                    await store.refreshPendingNearTransactions()
                }, executeHistoryOnly: { store in await store.refreshNearTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Polkadot")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshPolkadotTransactions(loadMore: false) }
                    await store.refreshPendingPolkadotTransactions()
                }, executeHistoryOnly: { store in await store.refreshPolkadotTransactions(loadMore: false) }
            ),
        ]
    }
    var importedWalletRefreshDescriptors: [WalletChainRefreshDescriptor] {
        plannedChainRefreshDescriptors + [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Aptos")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshAptosTransactions(loadMore: false) }
                    await store.refreshPendingAptosTransactions()
                }, executeHistoryOnly: { store in await store.refreshAptosTransactions(loadMore: false) }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Internet Computer")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBalances()
                    if refreshHistory { await store.refreshICPTransactions(loadMore: false) }
                    await store.refreshPendingICPTransactions()
                }, executeHistoryOnly: { store in await store.refreshICPTransactions(loadMore: false) }
            ),
        ]
    }

    func runPlannedChainRefreshes(using refreshPlanByChain: [WalletChainID: Bool], timeout: Double) async {
        for descriptor in plannedChainRefreshDescriptors {
            guard let refreshHistory = refreshPlanByChain[descriptor.chainID] else { continue }
            await runTimedChainRefresh(descriptor.chainID, refreshHistory: refreshHistory, timeout: timeout) {
                await descriptor.executeRefresh(self, refreshHistory)
            }
        }
    }
    func refreshImportedWalletBalances(forChains chainNames: Set<String>) async {
        for descriptor in importedWalletRefreshDescriptors where chainNames.contains(descriptor.chainName) {
            await descriptor.executeBalancesOnly(self)
        }
    }
    func runHistoryRefreshes(for trackedChains: Set<WalletChainID>, interval: TimeInterval) async {
        let plannedHistoryChains = Set(
            WalletRefreshPlanner.historyPlans(
                for: trackedChains, now: Date(), interval: interval, lastHistoryRefreshAtByChainID: lastHistoryRefreshAtByChainID
            )
        )
        guard !plannedHistoryChains.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for descriptor in plannedChainRefreshDescriptors {
                guard plannedHistoryChains.contains(descriptor.chainID), let executeHistoryOnly = descriptor.executeHistoryOnly else {
                    continue
                }
                group.addTask {
                    await executeHistoryOnly(self)
                }
            }
            await group.waitForAll()
        }
    }
    func runPendingTransactionHistoryRefreshes(for trackedChains: Set<WalletChainID>, interval: TimeInterval) async {
        await runHistoryRefreshes(for: trackedChains, interval: interval)
    }
    private func runTimedChainRefresh(
        _ chainID: WalletChainID, refreshHistory: Bool, timeout: Double, operation: @escaping () async -> Void
    ) async {
        let chainName = chainID.displayName
        do {
            try await withTimeout(seconds: timeout) {
                await operation()
                return ()
            }
            if refreshHistory { lastHistoryRefreshAtByChainID[chainID] = Date() }
        } catch {
            markChainDegraded(chainName, detail: "\(chainName) refresh timed out. Using cached balances and history.")
            appendOperationalLog(
                .warning, category: "Chain Sync", message: "\(chainName) refresh timeout", chainName: chainName, source: "timeout",
                metadata: error.localizedDescription
            )
        }
    }

    func performUserInitiatedRefresh(forChain chainName: String) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if appIsActive { await refreshPendingTransactions(includeHistoryRefreshes: false) }
        await withBalanceRefreshWindow {
            await refreshBalances()
            switch chainName {
            case "Bitcoin": await refreshBitcoinTransactions(limit: 20)
            case "Bitcoin Cash": await refreshBitcoinCashTransactions(limit: 20)
            case "Bitcoin SV": await refreshBitcoinSVTransactions(limit: 20)
            case "Litecoin": await refreshLitecoinTransactions(limit: 20)
            case "Dogecoin": await refreshDogecoinTransactions(limit: 20)
            case "Ethereum": await refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: 20, loadMore: false)
            case "Arbitrum": await refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: 20, loadMore: false)
            case "Optimism": await refreshEVMTokenTransactions(chainName: "Optimism", maxResults: 20, loadMore: false)
            case "Ethereum Classic": await refreshEVMTokenTransactions(chainName: "Ethereum Classic", maxResults: 20, loadMore: false)
            case "BNB Chain": await refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: 20, loadMore: false)
            case "Avalanche": await refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: 20, loadMore: false)
            case "Hyperliquid": await refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: 20, loadMore: false)
            case "Polygon": await refreshEVMTokenTransactions(chainName: "Polygon", maxResults: 20, loadMore: false)
            case "Base": await refreshEVMTokenTransactions(chainName: "Base", maxResults: 20, loadMore: false)
            case "Linea": await refreshEVMTokenTransactions(chainName: "Linea", maxResults: 20, loadMore: false)
            case "Scroll": await refreshEVMTokenTransactions(chainName: "Scroll", maxResults: 20, loadMore: false)
            case "Blast": await refreshEVMTokenTransactions(chainName: "Blast", maxResults: 20, loadMore: false)
            case "Mantle": await refreshEVMTokenTransactions(chainName: "Mantle", maxResults: 20, loadMore: false)
            case "Tron": await refreshTronTransactions(loadMore: false)
            case "Solana": await refreshSolanaTransactions(loadMore: false)
            case "Cardano": await refreshCardanoTransactions(loadMore: false)
            case "XRP Ledger": await refreshXRPTransactions(loadMore: false)
            case "Stellar": await refreshStellarTransactions(loadMore: false)
            case "Monero": await refreshMoneroTransactions(loadMore: false)
            case "Sui": await refreshSuiTransactions(loadMore: false)
            case "Aptos": await refreshAptosTransactions(loadMore: false)
            case "TON": await refreshTONTransactions(loadMore: false)
            case "Internet Computer": await refreshICPTransactions(loadMore: false)
            case "NEAR": await refreshNearTransactions(loadMore: false)
            case "Polkadot": await refreshPolkadotTransactions(loadMore: false)
            default:
                await performUserInitiatedRefresh()
                return
            }
        }
        await refreshLivePrices()
        await refreshFiatExchangeRatesIfNeeded()
        recordPerformanceSample("user_refresh_chain", startedAt: startedAt, metadata: chainName)
    }
}
