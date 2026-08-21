import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra

    /// What this side of the refresh decision still owns.
    ///
    /// It used to own the decision: `WalletRefreshPlanner` packed five
    /// `AppState` properties and two dictionaries into request records, asked
    /// core the arithmetic, and unpacked the answer — so these tests asserted
    /// core's arithmetic through a Swift wrapper. Core holds the clock now and
    /// `policy.rs` tests the arithmetic against it, including the case no test
    /// here could reach: that a stamped clock is the *same* clock the next
    /// question reads.
    ///
    /// What is left is the half core cannot know — this device's conditions —
    /// and that the plan comes back and drives the loop.
    @MainActor
    final class WalletRefreshPlannerTests: XCTestCase {
        func testMaintenancePlanReportsThisDeviceAndComesBackWithACadence() async {
            let store = AppState()
            let plan = await store.maintenancePlan()
            XCTAssertGreaterThan(plan.pollSeconds, 0, "a cadence of zero would spin the loop")
            // No wallets and nothing pending, so there is nothing to refresh —
            // but the loop still gets told how long to wait.
            XCTAssertFalse(plan.refreshPendingTransactions)
        }

        func testAnUnreachableNetworkStopsTheBackgroundTick() async {
            let store = AppState()
            store.appIsActive = false
            store.isNetworkReachable = false
            let offline = await store.maintenancePlan()
            XCTAssertFalse(offline.runBackgroundTick, "no network, nothing to do")
            XCTAssertFalse(offline.allowHeavyBackgroundWork)

            store.isNetworkReachable = true
            let online = await store.maintenancePlan()
            XCTAssertTrue(online.runBackgroundTick, "a fresh clock has never ticked")
        }

        func testWalletChainIDResolvesStableRegistryIDFromDisplayNameAndSymbol() {
            XCTAssertEqual(WalletChainID("Ethereum")?.rawValue, "ethereum")
            XCTAssertEqual(WalletChainID("ETH")?.rawValue, "ethereum")
            XCTAssertEqual(WalletChainID("XRP Ledger")?.displayName, "XRP Ledger")
        }
    }
#endif
