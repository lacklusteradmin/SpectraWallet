import Foundation
import SwiftUI
struct BackgroundSyncSettingsView: View {
    @Bindable var store: AppState
    var body: some View {
        @Bindable var preferences = store.preferences
        return Form {
            Section(AppLocalization.string("Refresh Frequency")) {
                Text(AppLocalization.string("Choose how often Spectra refreshes balances automatically while the app is active.")).font(
                    .caption
                ).foregroundStyle(.secondary)
                Stepper(
                    value: $preferences.automaticRefreshFrequencyMinutes,
                    in: 5...60, step: 5
                ) {
                    LabeledContent(AppLocalization.string("Active app refresh"), value: "\(preferences.automaticRefreshFrequencyMinutes) min")
                }
            }
            Section(AppLocalization.string("Current Timing")) {
                LabeledContent(
                    AppLocalization.string("Active app balance refresh"), value: "\(preferences.automaticRefreshFrequencyMinutes) min")
                LabeledContent(
                    AppLocalization.string("Background balance refresh"), value: AppLocalization.string("Adaptive"))
            }
            Section(AppLocalization.string("Hint")) {
                Label(
                    AppLocalization.string("Lower refresh times can increase battery usage and network traffic."),
                    systemImage: "bolt.batteryblock.fill"
                ).foregroundStyle(.orange)
                Text(AppLocalization.string("Choose a longer interval if you want lower background activity and less battery impact."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isTooFrequent(preferences.automaticRefreshFrequencyMinutes) {
                Section(AppLocalization.string("Warning")) {
                    Label(
                        AppLocalization.string("This refresh speed can increase battery usage and network traffic."),
                        systemImage: "exclamationmark.triangle.fill"
                    ).foregroundStyle(.orange)
                    Text(AppLocalization.string("Use this mode only if you need near-real-time updates.")).font(.caption).foregroundStyle(
                        .secondary)
                }
            }
        }.navigationTitle(AppLocalization.string("Background Sync"))
    }
    private func isTooFrequent(_ minutes: Int) -> Bool { minutes <= 10 }
}
