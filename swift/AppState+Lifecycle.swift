import Foundation
import UIKit
#if canImport(Network)
    import Network
#endif

@MainActor
extension AppState {
    func startNetworkPathMonitorIfNeeded() {
        #if canImport(Network)
            networkPathMonitor.pathUpdateHandler = { [weak self] path in
                let reachable = path.status == .satisfied; let constrained = path.isConstrained; let expensive = path.isExpensive
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isNetworkReachable = reachable; self.isConstrainedNetwork = constrained; self.isExpensiveNetwork = expensive
                }
            }
            networkPathMonitor.start(queue: networkPathMonitorQueue)
        #endif
    }
    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, preferences.useFaceId, preferences.useAutoLock { isAppLocked = true; appLockError = nil }
        if !isActive {
            maintenanceTask?.cancel(); maintenanceTask = nil
            // Stop the Rust balance-refresh engine so it isn't firing
            // network requests while the app is in the background.
            Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
            return
        }
        startMaintenanceLoopIfNeeded()
        // Resume core-managed automatic balance refresh.
        Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
    }
    /// Launch-time wiring. Nothing domain is seeded here: settings, tokens,
    /// alerts, contacts, keypools and logs all arrive from core, through
    /// `applyCoreState` and `reloadCoreProjections()`.
    func restorePersistedRuntimeConfigurationAndState() {
        applyWalletCollectionSideEffects()
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        startNetworkPathMonitorIfNeeded()
        // Tor starts when core's settings arrive and say it is on; see
        // `reactToSettingsChange`.
    }
    func refreshForForegroundIfNeeded() async {
        await performCoreRefresh(.foreground)
        await reconcileSendLiveActivities()
    }
}
