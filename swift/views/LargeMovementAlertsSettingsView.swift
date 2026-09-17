import Foundation
import SwiftUI
struct LargeMovementAlertsSettingsView: View {
    @Bindable var store: AppState
    private var settings: AppSettings { store.appSettings }
    var body: some View {
        Form {
            Section(AppLocalization.string("Notifications")) {
                Toggle(isOn: store.settingBinding(\.useLargeMovementNotifications) { .useLargeMovementNotifications(value: $0) }) {
                    Label(AppLocalization.string("Large Portfolio Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                }
                Text(
                    settings.useLargeMovementNotifications
                        ? AppLocalization.string(
                            "Spectra can notify you when your total portfolio moves beyond your configured thresholds.")
                        : AppLocalization.string("Large movement notifications are currently off.")
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Alert Controls")) {
                Stepper(
                    String(
                        format: AppLocalization.string("Large movement threshold: %@"),
                        (settings.largeMovementAlertPercentThreshold / 100).formatted(.percent.precision(.fractionLength(0)))
                    ),
                    value: store.settingBinding(\.largeMovementAlertPercentThreshold) {
                        .largeMovementAlertPercentThreshold(value: $0)
                    }, in: 1...90, step: 1
                ).disabled(!settings.useLargeMovementNotifications)
                Stepper(
                    AppLocalization.format("Large movement minimum: %lld USD", Int(settings.largeMovementAlertUsdThreshold)),
                    value: store.settingBinding(\.largeMovementAlertUsdThreshold) {
                        .largeMovementAlertUsdThreshold(value: $0)
                    }, in: 1...100_000, step: 5
                ).disabled(!settings.useLargeMovementNotifications)
            }
            Section {
                Text(
                    AppLocalization.string(
                        "These controls tune when portfolio movement notifications are sent during portfolio balance refreshes.")
                ).font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(AppLocalization.string("Large Movement Alerts"))
    }
}
