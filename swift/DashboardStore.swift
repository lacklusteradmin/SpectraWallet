import Foundation
import SwiftUI
extension AppState {
    var pinnedDashboardTokenIds: [String] {
        cachedPinnedDashboardTokenIds.isEmpty ? dashboardDefaultPinnedAssets() : cachedPinnedDashboardTokenIds
    }
    func isDashboardAssetPinned(_ tokenID: String) -> Bool { pinnedDashboardTokenIds.contains(tokenID) }
    func setDashboardAssetPinned(_ isPinned: Bool, tokenID: String) {
        var ids = pinnedDashboardTokenIds
        if isPinned {
            if !ids.contains(tokenID) { ids.append(tokenID) }
        } else { ids.removeAll { $0 == tokenID } }
        setPinnedDashboardAssets(ids)
    }
    func resetPinnedDashboardAssets() { setPinnedDashboardAssets([]) }
    var dashboardAssetGroups: [DashboardAssetGroup] { cachedDashboardAssetGroups }
    func rebuildDashboardDerivedState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let groups = try? await WalletServiceBridge.shared.dashboardAssetGroups(),
                  let options = try? await WalletServiceBridge.shared.dashboardPinOptions() else { return }
            if groups != self.cachedDashboardAssetGroups { self.cachedDashboardAssetGroups = groups }
            if options != self.cachedAvailableDashboardPinOptions { self.cachedAvailableDashboardPinOptions = options }
        }
    }
    var appNoticeItems: [AppNoticeItem] {
        let commonCopy = CommonLocalizationContent.current
        var notices: [AppNoticeItem] = []
        if let quoteRefreshError = quoteRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines), !quoteRefreshError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Pricing Notice"), message: quoteRefreshError, severity: .warning,
                    systemImage: "dollarsign.circle"
                )
            )
        }
        if let fiatRatesRefreshError = fiatRatesRefreshError?.trimmingCharacters(in: .whitespacesAndNewlines),
            !fiatRatesRefreshError.isEmpty
        {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Fiat Rates Degraded Mode"), message: fiatRatesRefreshError, severity: .warning,
                    systemImage: "antenna.radiowaves.left.and.right.slash"
                )
            )
        }
        notices.append(
            contentsOf: chainDegradedBanners.map { banner in
                AppNoticeItem(
                    title: AppLocalization.format("%@ Degraded Mode", banner.chainName), message: banner.message, severity: .warning,
                    systemImage: "antenna.radiowaves.left.and.right.slash", timestamp: banner.lastGoodSyncAt
                )
            })
        if let importError = importError?.trimmingCharacters(in: .whitespacesAndNewlines), !importError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.walletImportErrorTitle, message: importError, severity: .error,
                    systemImage: "square.and.arrow.down.badge.exclamationmark"
                )
            )
        }
        if let sendError = sendError?.trimmingCharacters(in: .whitespacesAndNewlines), !sendError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.sendErrorTitle, message: sendError, severity: .error, systemImage: "paperplane.circle"
                )
            )
        }
        if let secretStoreRegistrationError = secretStoreRegistrationError?.trimmingCharacters(in: .whitespacesAndNewlines),
            !secretStoreRegistrationError.isEmpty
        {
            notices.append(
                AppNoticeItem(
                    title: localizedStoreString("Secure Storage Unavailable"), message: secretStoreRegistrationError,
                    severity: .error, systemImage: "lock.trianglebadge.exclamationmark"
                )
            )
        }
        if let appLockError = appLockError?.trimmingCharacters(in: .whitespacesAndNewlines), !appLockError.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.securityNoticeTitle, message: appLockError, severity: .error,
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
            )
        }
        if let tronLastSendErrorDetails = tronLastSendErrorDetails?.trimmingCharacters(in: .whitespacesAndNewlines),
            !tronLastSendErrorDetails.isEmpty
        {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.tronSendDiagnosticTitle, message: tronLastSendErrorDetails, severity: .error,
                    systemImage: "bolt.trianglebadge.exclamationmark", timestamp: tronLastSendErrorAt
                )
            )
        }
        return notices
    }
}
