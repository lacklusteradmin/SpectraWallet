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
                    self.reportDeviceConditions()
                }
            }
            networkPathMonitor.start(queue: networkPathMonitorQueue)
        #endif
    }
    /// Core's engine starts both refresh loops in the foreground and stops
    /// them in the background.
    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, preferences.useFaceId, preferences.useAutoLock { isAppLocked = true; appLockError = nil }
        reportDeviceConditions()
    }
    /// Launch-time wiring. Nothing domain is seeded here: settings, tokens,
    /// alerts, contacts, keypools and logs all arrive from core, through
    /// `applyCoreState` and `reloadCoreProjections()`.
    func restorePersistedRuntimeConfigurationAndState() {
        applyWalletCollectionSideEffects()
        UIDevice.current.isBatteryMonitoringEnabled = true
        startNetworkPathMonitorIfNeeded()
    }
    func refreshForForegroundIfNeeded() async {
        await performCoreRefresh(.foreground)
        await reconcileSendLiveActivities()
    }
}
