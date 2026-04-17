import Foundation
import UIKit
import UserNotifications
extension AppState {
    func currentBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 1.0 : level
    }
    func activePendingRefreshIntervalForProfile() -> TimeInterval {
        switch backgroundSyncProfile {
        case .conservative: return 30
        case .balanced: return Self.activePendingRefreshInterval
        case .aggressive: return 10
        }}
    func activePriceRefreshIntervalForProfile() -> TimeInterval { TimeInterval(automaticRefreshFrequencyMinutes * 60) }
    func baseBackgroundMaintenanceInterval() -> TimeInterval { TimeInterval(backgroundBalanceRefreshFrequencyMinutes * 60) }
    func backgroundMaintenanceInterval(now _: Date = Date()) -> TimeInterval {
        computeBackgroundMaintenanceInterval(
            baseIntervalSec: baseBackgroundMaintenanceInterval(),
            isConstrainedNetwork: isConstrainedNetwork,
            isExpensiveNetwork: isExpensiveNetwork,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: currentBatteryLevel()
        )
    }
    func canRunHeavyBackgroundRefresh() -> Bool {
        evaluateHeavyRefreshGate(
            backgroundSyncProfile: backgroundSyncProfile.rawValue,
            isNetworkReachable: isNetworkReachable,
            isConstrainedNetwork: isConstrainedNetwork,
            isExpensiveNetwork: isExpensiveNetwork,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: currentBatteryLevel()
        )
    }
    func maybeSendLargeMovementNotification(previousTotalUSD: Double, currentTotalUSD: Double) {
        guard useLargeMovementNotifications else { return }
        guard !appIsActive else { return }
        let currentCompositionSignature = portfolioCompositionSignature()
        guard lastObservedPortfolioCompositionSignature == currentCompositionSignature else {
            resetLargeMovementAlertBaseline()
            return
        }
        guard previousTotalUSD > 0 else { return }
        let evaluation = coreEvaluateLargeMovement(
            previousTotalUsd: previousTotalUSD, currentTotalUsd: currentTotalUSD,
            usdThreshold: largeMovementAlertUSDThreshold, percentThreshold: largeMovementAlertPercentThreshold
        )
        guard evaluation.shouldAlert else { return }
        let direction = evaluation.directionUp ? "up" : "down"
        let absoluteDelta = evaluation.absoluteDelta
        let ratio = evaluation.ratio
        let content = UNMutableNotificationContent()
        content.title = "Large portfolio movement detected"
        content.body = "Your portfolio moved \(direction) by \(formattedFiatAmount(fromUSD: absoluteDelta)) (\(Int((ratio * 100).rounded()))%) since last sync."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "portfolio-movement-\(UUID().uuidString)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    func resetLargeMovementAlertBaseline() {
        lastObservedPortfolioTotalUSD = totalBalance
        lastObservedPortfolioCompositionSignature = portfolioCompositionSignature()
    }
    func portfolioCompositionSignature() -> String { portfolio.map(\.holdingKey).sorted().joined(separator: "|") }
}
