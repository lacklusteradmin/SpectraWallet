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
    final class WalletRefreshPlannerTests: IsolatedAppStateTestCase {
        func testMaintenancePlanReportsThisDeviceAndComesBackWithACadence() async {
            let store = makeState()
            let plan = await store.maintenancePlan()
            XCTAssertGreaterThan(plan.pollSeconds, 0, "a cadence of zero would spin the loop")
            // No wallets and nothing pending, so there is nothing to refresh —
            // but the loop still gets told how long to wait.
            XCTAssertFalse(plan.refreshPendingTransactions)
        }

        func testAnUnreachableNetworkStopsTheBackgroundTick() async {
            let store = makeState()
            store.appIsActive = false
            store.isNetworkReachable = false
            let offline = await store.maintenancePlan()
            XCTAssertFalse(offline.runBackgroundTick, "no network, nothing to do")
            XCTAssertFalse(offline.allowHeavyBackgroundWork)

            store.isNetworkReachable = true
            let online = await store.maintenancePlan()
            XCTAssertTrue(online.runBackgroundTick, "a fresh clock has never ticked")
        }

        func testOfflineRefreshAndRescanCrossAsyncBinding() async throws {
            let service = try WalletService(endpoints: [])
            let result = try await service.refreshApp(intent: .user, conditions: DeviceConditions(
                appIsActive: true, isNetworkReachable: false, isConstrainedNetwork: false,
                isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: true))
            XCTAssertNil(result.pending)
            XCTAssertTrue(result.failures.isEmpty)
            let rescan = try await service.refreshApp(intent: .deepRescan(chainId: "bitcoin"), conditions: DeviceConditions(
                appIsActive: true, isNetworkReachable: false, isConstrainedNetwork: false,
                isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: false))
            XCTAssertFalse(rescan.failures.isEmpty)
            XCTAssertNil(rescan.pending)

        }

        func testMaintenanceSleepDoesNotKeepAppStateAlive() async throws {
            let wallet = WalletView(name: "Watch", chainId: "ethereum", addresses: ["ethereum": "0x" + String(repeating: "1", count: 40)])
            _ = try await bridge.applyStateCommand(.upsertWallet(wallet: wallet.walletState()))
            var store: AppState? = AppState(bridge: bridge, startServices: false)
            store?.isNetworkReachable = false
            await store?.rebuildWalletDerivedStateFromCore()
            store?.lastMaintenancePollSeconds = 0
            weak var released = store
            store?.maintenanceTask = store?.makeMaintenanceTask()
            // Wait for a complete tick, then drop the only external owner during its sleep.
            for _ in 0..<100 {
                if (store?.lastMaintenancePollSeconds ?? 0) > 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertGreaterThan(store?.lastMaintenancePollSeconds ?? 0, 0)
            store = nil
            for _ in 0..<100 {
                if released == nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNil(released, "the maintenance loop must not own AppState across sleep")
        }

        func testRefreshFailureDoesNotClaimCompletion() {
            XCTAssertNotEqual(refreshOutcomeMessage(succeeded: false), refreshOutcomeMessage(succeeded: true))
            XCTAssertEqual(refreshOutcomeMessage(succeeded: false), AppLocalization.string("Refresh failed or completed partially. See refresh errors."))
        }

    }
#endif
