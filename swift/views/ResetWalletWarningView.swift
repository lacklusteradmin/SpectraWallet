import Foundation
import SwiftUI
struct ResetWalletWarningView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScopes = Set(AppState.ResetScope.allCases)
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        AppLocalization.string(
                            "Choose which categories to remove from this device. Selected items are deleted locally and some options also clear secure keychain data."
                        )
                    ).font(.body)
                    Text(
                        AppLocalization.string(
                            "You must have your seed phrase backed up. Without it, you cannot recover your funds after reset.")
                    ).font(.body.weight(.semibold)).foregroundStyle(.red)
                } header: {
                    Text(AppLocalization.string("Before You Continue"))
                }
                Section(AppLocalization.string("Choose What To Reset")) {
                    ForEach(AppState.ResetScope.allCases) { scope in
                        Toggle(isOn: binding(for: scope)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                Text(scope.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section(AppLocalization.string("Selected Reset Summary")) {
                    if selectedScopes.contains(.walletsAndSecrets) {
                        Label(
                            AppLocalization.string("Imported wallets, watched addresses, and secure seed material"),
                            systemImage: "wallet.pass")
                    }
                    if selectedScopes.contains(.historyAndCache) {
                        Label(
                            AppLocalization.string("Transaction history, chain snapshots, diagnostics, and network caches"),
                            systemImage: "clock.arrow.circlepath")
                    }
                    if selectedScopes.contains(.alertsAndContacts) {
                        Label(
                            AppLocalization.string("Price alerts, notification rules, and address book recipients"),
                            systemImage: "bell.slash")
                    }
                    if selectedScopes.contains(.settingsAndEndpoints) {
                        Label(
                            AppLocalization.string("Known tokens, API keys, endpoint settings, preferences, and custom icons"),
                            systemImage: "slider.horizontal.3")
                    }
                    if selectedScopes.contains(.dashboardCustomization) {
                        Label(AppLocalization.string("Pinned assets and dashboard customization choices"), systemImage: "square.grid.2x2")
                    }
                    if selectedScopes.contains(.providerState) {
                        Label(
                            AppLocalization.string("Provider selections, reliability memory, and low-level network state"),
                            systemImage: "network")
                    }
                    if selectedScopes.isEmpty {
                        Text(AppLocalization.string("Select at least one category to enable reset.")).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(AppLocalization.string("Reset Selected Data"), role: .destructive) {
                        Task {
                            await store.resetSelectedData(scopes: selectedScopes)
                            dismiss()
                        }
                    }.disabled(selectedScopes.isEmpty)
                }
            }.navigationTitle(AppLocalization.string("Reset Wallet")).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    private func binding(for scope: AppState.ResetScope) -> Binding<Bool> {
        Binding(
            get: { selectedScopes.contains(scope) },
            set: { isSelected in
                if isSelected { selectedScopes.insert(scope) } else { selectedScopes.remove(scope) }
            }
        )
    }
}
