import Foundation
import Combine

@MainActor
final class ViewRefreshSignal: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private var cancellables: Set<AnyCancellable> = []
    init(_ publishers: [AnyPublisher<Void, Never>]) {
        for publisher in publishers {
            publisher.receive(on: RunLoop.main).sink { [weak self] in
                    self?.revision &+= 1
                }.store(in: &cancellables)
        }}
}

extension Publisher where Failure == Never {
    func asVoidSignal() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}

struct WalletRefreshChainPlan: Hashable {
    let chainID: WalletChainID
    let refreshHistory: Bool
    var chainName: String { chainID.displayName }
}
struct WalletActiveMaintenancePlan {
    let refreshPendingTransactions: Bool
    let refreshLivePrices: Bool
}
struct WalletRefreshPlanner {
    static func activeMaintenancePlan(now: Date, lastPendingTransactionRefreshAt: Date?, lastLivePriceRefreshAt: Date?, hasPendingTransactionMaintenanceWork: Bool, shouldRunScheduledPriceRefresh: Bool, pendingRefreshInterval: TimeInterval, priceRefreshInterval: TimeInterval) -> WalletActiveMaintenancePlan {
        let plan = WalletRustAppCoreBridge.activeMaintenancePlan(
            WalletRustActiveMaintenancePlanRequest(
                nowUnix: now.timeIntervalSince1970, lastPendingTransactionRefreshAtUnix: lastPendingTransactionRefreshAt?.timeIntervalSince1970, lastLivePriceRefreshAtUnix: lastLivePriceRefreshAt?.timeIntervalSince1970, hasPendingTransactionMaintenanceWork: hasPendingTransactionMaintenanceWork, shouldRunScheduledPriceRefresh: shouldRunScheduledPriceRefresh, pendingRefreshInterval: pendingRefreshInterval, priceRefreshInterval: priceRefreshInterval
            )
        )
        return WalletActiveMaintenancePlan(refreshPendingTransactions: plan.refreshPendingTransactions, refreshLivePrices: plan.refreshLivePrices)
    }
    static func shouldRunBackgroundMaintenance(now: Date, isNetworkReachable: Bool, lastBackgroundMaintenanceAt: Date?, interval: TimeInterval) -> Bool {
        WalletRustAppCoreBridge.shouldRunBackgroundMaintenance(
            WalletRustBackgroundMaintenanceRequest(
                nowUnix: now.timeIntervalSince1970, isNetworkReachable: isNetworkReachable, lastBackgroundMaintenanceAtUnix: lastBackgroundMaintenanceAt?.timeIntervalSince1970, interval: interval
            )
        )
    }
    static func chainPlans(for chainIDs: Set<WalletChainID>, now: Date, forceChainRefresh: Bool, includeHistoryRefreshes: Bool, historyRefreshInterval: TimeInterval, pendingTransactionMaintenanceChains: Set<WalletChainID>, degradedChains: Set<WalletChainID>, lastGoodChainSyncByID: [WalletChainID: Date], lastHistoryRefreshAtByChainID: [WalletChainID: Date], automaticChainRefreshStalenessInterval: TimeInterval) -> [WalletRefreshChainPlan] {
        let plans = WalletRustAppCoreBridge.chainRefreshPlans(
            WalletRustChainRefreshPlanRequest(
                chainIds: chainIDs.map(\.rawValue), nowUnix: now.timeIntervalSince1970, forceChainRefresh: forceChainRefresh, includeHistoryRefreshes: includeHistoryRefreshes, historyRefreshInterval: historyRefreshInterval, pendingTransactionMaintenanceChainIds: pendingTransactionMaintenanceChains.map(\.rawValue), degradedChainIds: degradedChains.map(\.rawValue), lastGoodChainSyncById: Dictionary(uniqueKeysWithValues: lastGoodChainSyncByID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), lastHistoryRefreshAtByChainId: Dictionary(uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), automaticChainRefreshStalenessInterval: automaticChainRefreshStalenessInterval
            )
        )
        return plans.compactMap { plan in
            guard let chainID = WalletChainID(plan.chainId) else { return nil }
            return WalletRefreshChainPlan(chainID: chainID, refreshHistory: plan.refreshHistory)
        }
    }
    static func historyPlans(for chainIDs: Set<WalletChainID>, now: Date, interval: TimeInterval, lastHistoryRefreshAtByChainID: [WalletChainID: Date]) -> [WalletChainID] {
        let ids = WalletRustAppCoreBridge.historyRefreshPlans(
            WalletRustHistoryRefreshPlanRequest(
                chainIds: chainIDs.map(\.rawValue), nowUnix: now.timeIntervalSince1970, interval: interval, lastHistoryRefreshAtByChainId: Dictionary(uniqueKeysWithValues: lastHistoryRefreshAtByChainID.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
            )
        )
        return ids.compactMap(WalletChainID.init)
    }
}
