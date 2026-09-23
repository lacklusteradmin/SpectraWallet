import Foundation
import SwiftUI
struct AdvancedSettingsView: View {
    @Bindable var store: AppState
    @State private var isRunningMaintenance = false
    @State private var maintenanceNotice: String?
    var body: some View {
        @Bindable var preferences = store.preferences
        return Form {
            Section(AppLocalization.string("Security")) {
                Toggle(
                    AppLocalization.string("Biometric Confirmation For Send Actions"),
                    isOn: Binding(
                        get: { preferences.requireBiometricForSendActions }, set: { preferences.requireBiometricForSendActions = $0 }
                    )
                )
                Toggle(
                    AppLocalization.string("Strict RPC Only (Disable Ledger Fallback)"),
                    isOn: store.settingBinding(\.useStrictRpcOnly) { .useStrictRpcOnly(value: $0) }
                )
                Text(AppLocalization.string("When enabled, balances only come from live RPC responses.")).font(.caption).foregroundStyle(
                    .secondary)
                Button(AppLocalization.string("Lock App Now")) {
                    store.isAppLocked = true
                    maintenanceNotice = AppLocalization.string("App locked.")
                }
            }
            Section(AppLocalization.string("Quick Maintenance")) {
                Button(
                    isRunningMaintenance
                        ? AppLocalization.string("Refreshing...") : AppLocalization.string("Refresh Now (Balances + History)")
                ) {
                    Task {
                        isRunningMaintenance = true
                        let succeeded = await store.performUserInitiatedRefresh()
                        isRunningMaintenance = false
                        maintenanceNotice = refreshOutcomeMessage(succeeded: succeeded)
                    }
                }.disabled(isRunningMaintenance)
                if let maintenanceNotice { Text(maintenanceNotice).font(.caption).foregroundStyle(.secondary) }
            }
            Section(AppLocalization.string("Status")) {
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                if let pendingRefresh = store.pendingTransactionRefreshStatusText {
                    Text(pendingRefresh).font(.caption).foregroundStyle(.secondary)
                }
                Text(AppLocalization.format("Wallets: %lld", store.wallets.count)).font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.format("Known token checks enabled: %lld", store.tokenPreferences.filter { $0.isEnabled }.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(AppLocalization.string("Advanced"))
    }
}

func refreshOutcomeMessage(succeeded: Bool) -> String {
    AppLocalization.string(succeeded ? "Manual refresh completed." : "Refresh failed or completed partially. See refresh errors.")
}
