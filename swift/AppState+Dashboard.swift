import Foundation
import SwiftUI
extension AppState {
    /// Pin or unpin one asset. Core applies it to the set the dashboard shows,
    /// defaults included, and each pin option says whether it is pinned.
    func setDashboardAssetPinned(_ isPinned: Bool, tokenId: String) {
        sendDashboardPinCommand(.setDashboardAssetPinned(tokenId: tokenId, isPinned: isPinned))
    }
    func resetPinnedDashboardAssets() { sendDashboardPinCommand(.resetPinnedDashboardAssets) }
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
        for error in [walletImport.error, walletCommandError].compactMap({ $0 }) {
            let importNotice = error.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !importNotice.isEmpty else { continue }
            notices.append(
                AppNoticeItem(
                    title: commonCopy.walletImportErrorTitle, message: importNotice, severity: .error,
                    systemImage: "square.and.arrow.down.badge.exclamationmark"
                )
            )
        }
        if let sendNotice = sendFlow.error?.trimmingCharacters(in: .whitespacesAndNewlines), !sendNotice.isEmpty {
            notices.append(
                AppNoticeItem(
                    title: commonCopy.sendErrorTitle, message: sendNotice, severity: .error, systemImage: "paperplane.circle"
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
        return notices
    }
}
