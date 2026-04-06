import Foundation
import SwiftUI

extension WalletStore {
    var selectedMainTab: MainAppTab {
        get { runtimeState.selectedMainTab }
        set { runtimeState.selectedMainTab = newValue }
    }

    var selectedMainTabBinding: Binding<MainAppTab> {
        Binding(get: { self.runtimeState.selectedMainTab }, set: { self.runtimeState.selectedMainTab = $0 })
    }

    var isAppLocked: Bool {
        get { runtimeState.isAppLocked }
        set { runtimeState.isAppLocked = newValue }
    }

    var appLockError: String? {
        get { runtimeState.appLockError }
        set { runtimeState.appLockError = newValue }
    }

    var isRefreshingLivePrices: Bool {
        get { runtimeState.isRefreshingLivePrices }
        set { runtimeState.isRefreshingLivePrices = newValue }
    }

    var isRefreshingChainBalances: Bool {
        get { runtimeState.isRefreshingChainBalances }
        set { runtimeState.isRefreshingChainBalances = newValue }
    }

    var allowsBalanceNetworkRefresh: Bool {
        get { runtimeState.allowsBalanceNetworkRefresh }
        set { runtimeState.allowsBalanceNetworkRefresh = newValue }
    }

    var isRefreshingPendingTransactions: Bool {
        get { runtimeState.isRefreshingPendingTransactions }
        set { runtimeState.isRefreshingPendingTransactions = newValue }
    }

    var lastLivePriceRefreshAt: Date? {
        get { runtimeState.lastLivePriceRefreshAt }
        set { runtimeState.lastLivePriceRefreshAt = newValue }
    }

    var lastFiatRatesRefreshAt: Date? {
        get { runtimeState.lastFiatRatesRefreshAt }
        set { runtimeState.lastFiatRatesRefreshAt = newValue }
    }

    var lastFullRefreshAt: Date? {
        get { runtimeState.lastFullRefreshAt }
        set { runtimeState.lastFullRefreshAt = newValue }
    }

    var lastChainBalanceRefreshAt: Date? {
        get { runtimeState.lastChainBalanceRefreshAt }
        set { runtimeState.lastChainBalanceRefreshAt = newValue }
    }

    var lastBackgroundMaintenanceAt: Date? {
        get { runtimeState.lastBackgroundMaintenanceAt }
        set { runtimeState.lastBackgroundMaintenanceAt = newValue }
    }

    var isNetworkReachable: Bool {
        get { runtimeState.isNetworkReachable }
        set { runtimeState.isNetworkReachable = newValue }
    }

    var isConstrainedNetwork: Bool {
        get { runtimeState.isConstrainedNetwork }
        set { runtimeState.isConstrainedNetwork = newValue }
    }

    var isExpensiveNetwork: Bool {
        get { runtimeState.isExpensiveNetwork }
        set { runtimeState.isExpensiveNetwork = newValue }
    }
}
