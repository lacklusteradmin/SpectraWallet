import Foundation

#if canImport(XCTest)
import XCTest
@testable import Spectra

@MainActor
final class WalletRefreshPlannerTests: XCTestCase {
    func testActiveMaintenancePlanRequestsPendingAndPriceRefreshWhenIntervalsElapsed() {
        let now = Date()

        let plan = WalletRefreshPlanner.activeMaintenancePlan(
            now: now,
            lastPendingTransactionRefreshAt: now.addingTimeInterval(-301),
            lastLivePriceRefreshAt: now.addingTimeInterval(-601),
            hasPendingTransactionMaintenanceWork: true,
            shouldRunScheduledPriceRefresh: true,
            pendingRefreshInterval: 300,
            priceRefreshInterval: 600
        )

        XCTAssertTrue(plan.refreshPendingTransactions)
        XCTAssertTrue(plan.refreshLivePrices)
    }

    func testActiveMaintenancePlanSkipsRefreshesWhenWorkOrScheduleIsMissing() {
        let now = Date()

        let plan = WalletRefreshPlanner.activeMaintenancePlan(
            now: now,
            lastPendingTransactionRefreshAt: now.addingTimeInterval(-10_000),
            lastLivePriceRefreshAt: now.addingTimeInterval(-10_000),
            hasPendingTransactionMaintenanceWork: false,
            shouldRunScheduledPriceRefresh: false,
            pendingRefreshInterval: 300,
            priceRefreshInterval: 600
        )

        XCTAssertFalse(plan.refreshPendingTransactions)
        XCTAssertFalse(plan.refreshLivePrices)
    }

    func testShouldRunBackgroundMaintenanceRequiresReachableNetworkAndElapsedInterval() {
        let now = Date()

        XCTAssertFalse(
            WalletRefreshPlanner.shouldRunBackgroundMaintenance(
                now: now,
                isNetworkReachable: false,
                lastBackgroundMaintenanceAt: nil,
                interval: 300
            )
        )

        XCTAssertTrue(
            WalletRefreshPlanner.shouldRunBackgroundMaintenance(
                now: now,
                isNetworkReachable: true,
                lastBackgroundMaintenanceAt: nil,
                interval: 300
            )
        )

        XCTAssertFalse(
            WalletRefreshPlanner.shouldRunBackgroundMaintenance(
                now: now,
                isNetworkReachable: true,
                lastBackgroundMaintenanceAt: now.addingTimeInterval(-60),
                interval: 300
            )
        )
    }

    func testChainPlansIncludeForcedPendingAndDegradedChainsWithExpectedHistoryFlags() {
        let now = Date()
        let plans = WalletRefreshPlanner.chainPlans(
            for: Set(["Ethereum", "Solana", "Bitcoin"].compactMap(WalletChainID.init)),
            now: now,
            forceChainRefresh: false,
            includeHistoryRefreshes: true,
            historyRefreshInterval: 300,
            pendingTransactionMaintenanceChains: Set(["Ethereum"].compactMap(WalletChainID.init)),
            degradedChains: Set(["Solana"].compactMap(WalletChainID.init)),
            lastGoodChainSyncByID: [
                WalletChainID("Ethereum")!: now,
                WalletChainID("Solana")!: now,
                WalletChainID("Bitcoin")!: now
            ],
            lastHistoryRefreshAtByChainID: [
                WalletChainID("Ethereum")!: now.addingTimeInterval(-600),
                WalletChainID("Solana")!: now
            ],
            automaticChainRefreshStalenessInterval: 86_400
        )

        XCTAssertEqual(plans.map(\.chainName), ["Ethereum", "Solana"])
        XCTAssertEqual(plans.first(where: { $0.chainName == "Ethereum" })?.refreshHistory, true)
        XCTAssertEqual(plans.first(where: { $0.chainName == "Solana" })?.refreshHistory, false)
    }

    func testHistoryPlansOnlyIncludeChainsWhoseHistoryIsStaleOrMissing() {
        let now = Date()
        let chains = WalletRefreshPlanner.historyPlans(
            for: Set(["Ethereum", "Solana", "Bitcoin"].compactMap(WalletChainID.init)),
            now: now,
            interval: 300,
            lastHistoryRefreshAtByChainID: [
                WalletChainID("Ethereum")!: now.addingTimeInterval(-600),
                WalletChainID("Solana")!: now
            ]
        )

        XCTAssertEqual(chains.map(\.displayName), ["Bitcoin", "Ethereum"])
    }

    func testWalletChainIDResolvesStableRegistryIDFromDisplayNameAndSymbol() {
        XCTAssertEqual(WalletChainID("Ethereum")?.rawValue, "ethereum")
        XCTAssertEqual(WalletChainID("ETH")?.rawValue, "ethereum")
        XCTAssertEqual(WalletChainID("XRP Ledger")?.displayName, "XRP Ledger")
    }
}
#endif
