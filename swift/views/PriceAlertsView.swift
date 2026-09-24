import Foundation
import SwiftUI
struct PriceAlertsView: View {
    @Bindable var store: AppState
    @State private var selectedHoldingKey: String = ""
    @State private var selectedCondition: PriceAlertCondition = .above
    @State private var targetPriceText: String = ""
    @State private var isSubmitting = false
    @State private var formMessage: String?
    @State private var removingAlertId: String?
    private var alertableHoldingKeys: Set<String> { Set(store.alertableCoins.map(\.holdingKey)) }
    private var selectedCoin: Coin? {
        store.alertableCoins.first(where: { $0.holdingKey == selectedHoldingKey })
    }
    var body: some View {
        Form {
            Section(AppLocalization.string("Notifications")) {
                Toggle(
                    AppLocalization.string("Enable Price Alerts"),
                    isOn: store.settingBinding(\.usePriceAlerts) { .usePriceAlerts(value: $0) }
                )
            }
            Section(AppLocalization.string("New Alert")) {
                if store.alertableCoins.isEmpty {
                    SpectraEmptyStateCard(
                        title: "No alertable assets",
                        message: "Import a wallet with assets first. Alerts are created from assets currently in your portfolio.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    Picker(AppLocalization.string("Asset"), selection: $selectedHoldingKey) {
                        ForEach(store.alertableCoins, id: \.holdingKey) { coin in
                            Text(AppLocalization.format("%@ on %@", coin.symbol, coin.chainName)).tag(
                                coin.holdingKey)
                        }
                    }
                    Picker(AppLocalization.string("Condition"), selection: $selectedCondition) {
                        ForEach(PriceAlertCondition.allCases, id: \.self) { condition in Text(condition.displayName).tag(condition) }
                    }.pickerStyle(.segmented)
                    TextField(AppLocalization.format("Target Price (%@)", store.selectedFiatCurrency.code), text: $targetPriceText)
                        .keyboardType(.decimalPad)
                    if let selectedCoin {
                        Text(
                            AppLocalization.format(
                                "Current price: %@",
                                store.amounts.formattedFiat(store.amounts.price(of: selectedCoin)))
                        ).spectraHintText().spectraNumericTextLayout()
                    }
                    if let formMessage { Text(formMessage).font(.caption).foregroundStyle(.secondary) }
                    Button(AppLocalization.string("Add Alert")) {
                        Task { await addAlert() }
                    }
                        .disabled(!canAddAlert)
                }
            }
            Section(AppLocalization.string("Active Alerts")) {
                if store.priceAlerts.isEmpty {
                    SpectraEmptyStateCard(
                        title: "No alerts configured yet",
                        message: "Add a price rule to watch one of your portfolio assets.",
                        systemImage: "bell.slash"
                    )
                } else {
                    ForEach(store.priceAlerts) { alert in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.titleText).font(.headline)
                                    Text(alertTargetText(alert)).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
                                }
                                Spacer()
                                Text(alert.statusText).font(.caption.bold()).frame(minWidth: 78).padding(.horizontal, 8).padding(
                                    .vertical, 4
                                ).background(statusColor(for: alert).opacity(0.18), in: Capsule()).foregroundStyle(statusColor(for: alert))
                            }
                            HStack {
                                Button(alert.isEnabled ? AppLocalization.string("Pause") : AppLocalization.string("Resume")) {
                                    spectraHaptic(.light)
                                    Task { await editAlert(.togglePriceAlert(id: alert.id)) }
                                }.buttonStyle(.borderless)
                                Spacer()
                                Button(AppLocalization.string("Remove"), role: .destructive) {
                                    removingAlertId = alert.id
                                }.buttonStyle(.borderless)
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Price Alerts"))
        .confirmationDialog(
            AppLocalization.string("Remove Alert"),
            isPresented: Binding(get: { removingAlertId != nil }, set: { if !$0 { removingAlertId = nil } }),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Remove"), role: .destructive) {
                if let id = removingAlertId {
                    spectraHaptic(.medium)
                    Task { await editAlert(.removePriceAlert(id: id)) }
                }
                removingAlertId = nil
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) { removingAlertId = nil }
        } message: {
            Text(AppLocalization.string("This alert rule will be permanently removed."))
        }
        .onAppear {
            syncSelection()
        }.onChange(of: store.walletsRevision) { _, _ in
            syncSelection()
        }
    }
    private var canAddAlert: Bool {
        selectedCoin != nil && !targetPriceText.isEmpty && !isSubmitting
    }
    private func editAlert(_ command: StateCommand) async {
        do { try await store.editPriceAlert(command) }
        catch { formMessage = error.localizedDescription }
    }
    private func addAlert() async {
        guard let selectedCoin else { return }
        // Core parses the number; the locale's decimal separator is this
        // field's to undo.
        let separator = Locale.current.decimalSeparator ?? "."
        let target = targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.editPriceAlert(.addPriceAlert(
                holdingKey: selectedCoin.holdingKey, targetPrice: target,
                currency: store.selectedFiatCurrency, condition: selectedCondition))
            store.requestNotificationPermission()
            targetPriceText = ""
            selectedCondition = .above
            formMessage = AppLocalization.string("Alert added. Spectra will notify you when this target is hit.")
        } catch { formMessage = error.localizedDescription }
    }
    private func syncSelection() {
        if !alertableHoldingKeys.contains(selectedHoldingKey) { selectedHoldingKey = store.alertableCoins.first?.holdingKey ?? "" }
    }
    private func alertTargetText(_ alert: PriceAlertRule) -> String {
        "\(alert.condition.displayName) \(store.amounts.formattedFiat(store.amounts.alertTarget(alert)))"
    }
    private func statusColor(for alert: PriceAlertRule) -> Color {
        Color.spectraPriceAlertStatusColor(isEnabled: alert.isEnabled, hasTriggered: alert.hasTriggered)
    }
}
