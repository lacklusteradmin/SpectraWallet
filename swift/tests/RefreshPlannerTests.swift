import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra

    /// What this side of the refresh decision still owns: this device's
    /// conditions. Core holds the clock, plans the cadence and runs both loops;
    /// `refresh_policy.rs` and `refresh_engine.rs` test those.
    @MainActor
    final class WalletRefreshPlannerTests: IsolatedAppStateTestCase {
        func testDeviceConditionsReportThisDeviceAndTheVisibleTab() {
            let store = makeState()
            store.isNetworkReachable = false
            store.selectedMainTab = .home
            XCTAssertFalse(store.deviceConditions().isNetworkReachable)
            XCTAssertTrue(store.deviceConditions().wantsPriceRefresh, "prices are on the home tab")
            store.selectedMainTab = .settings
            XCTAssertFalse(store.deviceConditions().wantsPriceRefresh)
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

        func testCoreRefreshEngineDoesNotKeepAppStateAlive() async throws {
            let wallet = WalletView(name: "Watch", chainId: "ethereum", addresses: ["ethereum": "0x" + String(repeating: "1", count: 40)])
            _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
            var store: AppState? = AppState(bridge: bridge, startServices: false)
            store?.isNetworkReachable = false
            let observer = WalletRefreshObserver()
            observer.store = store
            try await bridge.setRefreshObserver(observer)
            // Active and offline: core's first maintenance tick runs at once and
            // reaches the observer without touching a network.
            try await bridge.refreshEngine().setDeviceConditions(conditions: XCTUnwrap(store?.deviceConditions()))
            weak let released = store
            store = nil
            for _ in 0..<100 {
                if released == nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNil(released, "core's engine holds the observer, never the state")
            let inactive = DeviceConditions(appIsActive: false, isNetworkReachable: false, isConstrainedNetwork: false,
                isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: false)
            try await bridge.refreshEngine().setDeviceConditions(conditions: inactive)
        }

        func testRefreshFailureDoesNotClaimCompletion() {
            XCTAssertNotEqual(refreshOutcomeMessage(succeeded: false), refreshOutcomeMessage(succeeded: true))
            XCTAssertEqual(refreshOutcomeMessage(succeeded: false), AppLocalization.string("Refresh failed or completed partially. See refresh errors."))
        }

    }
#endif
