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
    /// The refresh steps a chain needs, decided from the registry.
    ///
    /// There were three constructors and a 24-row table naming every chain
    /// twice more — once for its history fetch and once for its pending poll.
    /// Both of those dispatch on a chain name now, and whether a chain needs
    /// UTXO address discovery is `supportsDeepUtxoDiscovery`. So the row is
    /// the chain name, and the list comes from core.
    @MainActor static func forChain(_ chainName: String) -> WalletChainRefreshDescriptor? {
        guard let chainID = WalletChainID(chainName) else { return nil }
        let isUTXO = coreSupportsDeepUtxoDiscovery(chainName: chainName)
        let isEVM = coreIsEvmChain(chainName: chainName)

        // Bitcoin and Dogecoin keep their own history fetch: HD xpub expansion
        // and a confirmed-fee path respectively.
        let history: @Sendable (AppState) async -> Void = { store in
            switch chainName {
            case "Bitcoin": await store.refreshBitcoinTransactions(loadMore: false)
            case "Dogecoin": await store.refreshDogecoinTransactions(loadMore: false)
            default:
                if isEVM {
                    await store.refreshEVMTokenTransactions(chainName: chainName, loadMore: false)
                } else {
                    await store.refreshNormalizedTransactions(chainName: chainName, loadMore: false)
                }
            }
        }
        let pending: @Sendable (AppState) async -> Void = { store in
            await store.refreshPendingTransactions(chainName: chainName)
        }
        return WalletChainRefreshDescriptor(
            chainID: chainID,
            executeRefresh: { store, refreshHistory in
                if isUTXO {
                    await store.refreshUTXOAddressDiscovery(chainName: chainName)
                    await store.refreshUTXOReceiveReservationState(chainName: chainName)
                }
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
    /// Every chain the app refreshes, in the order core lists them. Adding a
    /// chain to the catalog adds it here.
    @MainActor static let all: OrderedDictionary<WalletChainID, WalletChainRefreshDescriptor> = {
        let descriptors = AppEndpointDirectory.liveChainNames.compactMap { WalletChainRefreshDescriptor.forChain($0) }
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
