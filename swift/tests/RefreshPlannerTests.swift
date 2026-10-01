import Foundation
import Testing
@testable import Spectra

/// What this side of the refresh decision still owns: this device's
/// conditions. Core holds the clock, plans the cadence and runs both loops;
/// `refresh_policy.rs` and `refresh_engine.rs` test those.
@MainActor
@Suite(.isolatedAppState)
struct WalletRefreshPlannerTests: IsolatedAppStateSuite {
    @Test func deviceConditionsReportThisDeviceAndTheVisibleTab() {
        let store = makeState()
        store.isNetworkReachable = false
        store.selectedMainTab = .home
        #expect(!store.deviceConditions().isNetworkReachable)
        #expect(store.deviceConditions().wantsPriceRefresh, "prices are on the home tab")
        store.selectedMainTab = .settings
        #expect(!store.deviceConditions().wantsPriceRefresh)
    }

    @Test func coreRefreshEngineDoesNotKeepAppStateAlive() async throws {
        let wallet = WalletView(name: "Watch", chainId: Chain.ethereum, addresses: [Chain.ethereum: "0x" + String(repeating: "1", count: 40)])
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        var store: AppState? = AppState(bridge: bridge, startServices: false)
        store?.isNetworkReachable = false
        let observer = WalletRefreshObserver()
        store?.observeRefreshEvents(from: observer)
        try await bridge.setRefreshObserver(observer)
        // Active and offline: core's first maintenance tick runs at once and
        // reaches the observer without touching a network.
        let conditions = try #require(store?.deviceConditions())
        try await bridge.refreshEngine().setDeviceConditions(conditions: conditions)
        weak let released = store
        store = nil
        for _ in 0..<100 {
            if released == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(released == nil, "core's engine holds the observer, never the state")
        let inactive = DeviceConditions(appIsActive: false, isNetworkReachable: false, isConstrainedNetwork: false,
            isExpensiveNetwork: false, isLowPowerMode: false, batteryLevel: 1, wantsPriceRefresh: false)
        try await bridge.refreshEngine().setDeviceConditions(conditions: inactive)
    }

    @Test func refreshFailureDoesNotClaimCompletion() {
        #expect(refreshOutcomeMessage(succeeded: false) != refreshOutcomeMessage(succeeded: true))
        #expect(refreshOutcomeMessage(succeeded: false) == AppLocalization.string("Refresh failed or completed partially. See refresh errors."))
    }

}
