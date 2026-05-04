import Foundation
import OrderedCollections
struct WalletChainRefreshDescriptor: Sendable {
    let chainID: WalletChainID
    let executeRefresh: @Sendable (AppState, Bool) async -> Void
    let executeHistoryOnly: (@Sendable (AppState) async -> Void)?
    let executePendingOnly: (@Sendable (AppState) async -> Void)?
    var chainName: String { chainID.displayName }
    init(
        chainID: WalletChainID, executeRefresh: @escaping @Sendable (AppState, Bool) async -> Void,
        executeHistoryOnly: (@Sendable (AppState) async -> Void)? = nil,
        executePendingOnly: (@Sendable (AppState) async -> Void)? = nil
    ) {
        self.chainID = chainID
        self.executeRefresh = executeRefresh
        self.executeHistoryOnly = executeHistoryOnly
        self.executePendingOnly = executePendingOnly
    }
    @MainActor static func evm(_ chainName: String) -> WalletChainRefreshDescriptor {
        WalletChainRefreshDescriptor(
            chainID: WalletChainID(chainName)!,
            executeRefresh: { store, refreshHistory in
                await store.refreshBalances()
                if refreshHistory { await store.refreshEVMTokenTransactions(chainName: chainName, loadMore: false) }
                await store.refreshPendingEVMTransactions(chainName: chainName)
            },
            executeHistoryOnly: { await $0.refreshEVMTokenTransactions(chainName: chainName) },
            executePendingOnly: { await $0.refreshPendingEVMTransactions(chainName: chainName) }
        )
    }
    @MainActor static func standard(
        _ chainName: String,
        history: @escaping @Sendable (AppState) async -> Void,
        pending: @escaping @Sendable (AppState) async -> Void
    ) -> WalletChainRefreshDescriptor {
        WalletChainRefreshDescriptor(
            chainID: WalletChainID(chainName)!,
            executeRefresh: { store, refreshHistory in
                await store.refreshBalances()
                if refreshHistory { await history(store) }
                await pending(store)
            },
            executeHistoryOnly: history,
            executePendingOnly: pending
        )
    }
    @MainActor static func utxo(
        _ chainName: String,
        history: @escaping @Sendable (AppState) async -> Void,
        pending: @escaping @Sendable (AppState) async -> Void
    ) -> WalletChainRefreshDescriptor {
        WalletChainRefreshDescriptor(
            chainID: WalletChainID(chainName)!,
            executeRefresh: { store, refreshHistory in
                await store.refreshUTXOAddressDiscovery(chainName: chainName)
                await store.refreshUTXOReceiveReservationState(chainName: chainName)
                await store.refreshBalances()
                if refreshHistory { await history(store) }
                await pending(store)
            },
            executeHistoryOnly: history,
            executePendingOnly: pending
        )
    }
}
extension WalletChainRefreshDescriptor {
    @MainActor static let all: OrderedDictionary<WalletChainID, WalletChainRefreshDescriptor> = {
        let descriptors: [WalletChainRefreshDescriptor] = [
            .utxo("Bitcoin",
                history: { await $0.refreshBitcoinTransactions(limit: 20, loadMore: false) },
                pending: { await $0.refreshPendingBitcoinTransactions() }),
            .utxo("Bitcoin Cash",
                history: { await $0.refreshBitcoinCashTransactions(limit: 20, loadMore: false) },
                pending: { await $0.refreshPendingBitcoinCashTransactions() }),
            .utxo("Bitcoin SV",
                history: { await $0.refreshBitcoinSVTransactions(limit: 20, loadMore: false) },
                pending: { await $0.refreshPendingBitcoinSVTransactions() }),
            .utxo("Litecoin",
                history: { await $0.refreshLitecoinTransactions(limit: 20, loadMore: false) },
                pending: { await $0.refreshPendingLitecoinTransactions() }),
            .utxo("Dogecoin",
                history: { await $0.refreshDogecoinTransactions(loadMore: false) },
                pending: { await $0.refreshPendingDogecoinTransactions() }),
            .evm("Ethereum"), .evm("Arbitrum"), .evm("Optimism"), .evm("Ethereum Classic"),
            .evm("BNB Chain"), .evm("Avalanche"), .evm("Hyperliquid"), .evm("Polygon"), .evm("Base"),
            .evm("Linea"), .evm("Scroll"), .evm("Blast"), .evm("Mantle"),
            .standard("Tron",
                history: { await $0.refreshTronTransactions(loadMore: false) },
                pending: { await $0.refreshPendingTronTransactions() }),
            .standard("Solana",
                history: { await $0.refreshSolanaTransactions(loadMore: false) },
                pending: { await $0.refreshPendingSolanaTransactions() }),
            .standard("Cardano",
                history: { await $0.refreshCardanoTransactions(loadMore: false) },
                pending: { await $0.refreshPendingCardanoTransactions() }),
            .standard("XRP Ledger",
                history: { await $0.refreshXRPTransactions(loadMore: false) },
                pending: { await $0.refreshPendingXRPTransactions() }),
            .standard("Stellar",
                history: { await $0.refreshStellarTransactions(loadMore: false) },
                pending: { await $0.refreshPendingStellarTransactions() }),
            .standard("Monero",
                history: { await $0.refreshMoneroTransactions(loadMore: false) },
                pending: { await $0.refreshPendingMoneroTransactions() }),
            .standard("Sui",
                history: { await $0.refreshSuiTransactions(loadMore: false) },
                pending: { await $0.refreshPendingSuiTransactions() }),
            .standard("Aptos",
                history: { await $0.refreshAptosTransactions(loadMore: false) },
                pending: { await $0.refreshPendingAptosTransactions() }),
            .standard("TON",
                history: { await $0.refreshTONTransactions(loadMore: false) },
                pending: { await $0.refreshPendingTONTransactions() }),
            .standard("Internet Computer",
                history: { await $0.refreshICPTransactions(loadMore: false) },
                pending: { await $0.refreshPendingICPTransactions() }),
            .standard("NEAR",
                history: { await $0.refreshNearTransactions(loadMore: false) },
                pending: { await $0.refreshPendingNearTransactions() }),
            .standard("Polkadot",
                history: { await $0.refreshPolkadotTransactions(loadMore: false) },
                pending: { await $0.refreshPendingPolkadotTransactions() }),
        ]
        return OrderedDictionary(uniqueKeysWithValues: descriptors.map { ($0.chainID, $0) })
    }()
}
extension AppState {
    static var chainRefreshDescriptors: OrderedDictionary<WalletChainID, WalletChainRefreshDescriptor> {
        WalletChainRefreshDescriptor.all
    }
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
    func runPlannedChainRefreshes(using refreshPlanByChain: [WalletChainID: Bool], timeout: Double) async {
        for descriptor in Self.chainRefreshDescriptors.values {
            guard let refreshHistory = refreshPlanByChain[descriptor.chainID] else { continue }
            await runTimedChainRefresh(descriptor.chainID, refreshHistory: refreshHistory, timeout: timeout) {
                await descriptor.executeRefresh(self, refreshHistory)
            }
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
            for descriptor in Self.chainRefreshDescriptors.values {
                guard plannedHistoryChains.contains(descriptor.chainID), let executeHistoryOnly = descriptor.executeHistoryOnly else {
                    continue
                }
                group.addTask { await executeHistoryOnly(self) }
            }
            await group.waitForAll()
        }
    }
    func runPendingTransactionHistoryRefreshes(for trackedChains: Set<WalletChainID>, interval: TimeInterval) async {
        await runHistoryRefreshes(for: trackedChains, interval: interval)
    }
    private func runTimedChainRefresh(
        _ chainID: WalletChainID, refreshHistory: Bool, timeout: Double, operation: @escaping @Sendable () async -> Void
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
            if let id = WalletChainID(chainName),
               let descriptor = Self.chainRefreshDescriptors[id],
               let historyOnly = descriptor.executeHistoryOnly {
                await historyOnly(self)
            } else {
                await performUserInitiatedRefresh()
            }
        }
        await refreshLivePrices()
        await refreshFiatExchangeRatesIfNeeded()
        recordPerformanceSample("user_refresh_chain", startedAt: startedAt, metadata: chainName)
    }
}
