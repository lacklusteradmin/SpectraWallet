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
        let isUTXO = (Chain(displayName: chainName)?.supportsDeepUTXODiscovery ?? false)
        let isEVM = (Chain(displayName: chainName)?.isEVM ?? false)

        // Three shapes, chosen by what the chain's wallets hold rather than by
        // name. Bitcoin is the only chain with a stored xpub, so core expands
        // the HD range for it; the other four deep-UTXO chains hold many
        // discovered addresses and need their legs netted per transaction;
        // everything else is one address per wallet.
        //
        // Dogecoin used to be the only name in the second arm, so Litecoin,
        // Bitcoin Cash and Bitcoin SV fell to the third and only ever had
        // their first address's history fetched.
        let history: @Sendable (AppState) async -> Void = { store in
            if chainName == "Bitcoin" {
                await store.refreshBitcoinTransactions(loadMore: false)
            } else if Chain(displayName: chainName)?.supportsDeepUTXODiscovery == true {
                await store.refreshMultiAddressUTXOTransactions(chainName: chainName, loadMore: false)
            } else if isEVM {
                await store.refreshEVMTokenTransactions(chainName: chainName, loadMore: false)
            } else {
                await store.refreshNormalizedTransactions(chainName: chainName, loadMore: false)
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
    /// Refresh the history of the chains that are due one.
    ///
    /// Which those are is core's answer, from core's clock. This used to pass
    /// `lastHistoryRefreshAtByChainID` — a dictionary on this side — so the
    /// answer was only as current as the caller's copy of it.
    func runHistoryRefreshes(for trackedChains: Set<WalletChainID>, interval: TimeInterval) async {
        let due = await WalletServiceBridge.shared.historyRefreshPlans(
            chainIDs: trackedChains.map(\.rawValue), intervalSecs: interval)
        let plannedHistoryChains = Set(due.compactMap(WalletChainID.init))
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
        for chainID in plannedHistoryChains {
            await WalletServiceBridge.shared.recordHistoryRefresh(chainID: chainID.rawValue)
        }
    }
    func runPendingTransactionHistoryRefreshes(for trackedChains: Set<WalletChainID>, interval: TimeInterval) async {
        await runHistoryRefreshes(for: trackedChains, interval: interval)
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
