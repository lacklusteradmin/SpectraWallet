import Foundation
import SwiftUI

struct TokenRegistryDetailView: View {
    let store: AppState
    let groupKey: String
    @State private var isShowingRemoveConfirmation = false
    @Environment(\.dismiss) private var dismiss
    private var groupEntries: [TokenPreferenceEntry] {
        store.tokenPreferences.filter { $0.token.tokenId == groupKey }
            .sorted { $0.token.chainId < $1.token.chainId }
    }
    var body: some View {
        Group {
            if let entry = groupEntries.first {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            CoinBadge(artworkName: entry.settingsArtworkName,
                                fallbackText: entry.settingsFallbackMark,
                                color: entry.hostingChain?.settingsIconTint ?? .accentColor, size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.token.name).font(.headline)
                                Text(entry.token.symbol).foregroundStyle(.secondary)
                                Text(AppLocalization.string(entry.isBuiltIn ? "Built-In" : "Custom"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    if let error = store.tokenPreferenceError {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                    Section(AppLocalization.string("Price Sources")) {
                        providerRow("CoinGecko", id: entry.token.coingeckoId)
                        providerRow("CoinPaprika", id: entry.token.coinpaprikaId)
                    }
                    Section(AppLocalization.string("Networks")) {
                        ForEach(groupEntries) { entry in TokenRegistryEntryCardView(entry: entry) }
                    }
                    if !entry.isBuiltIn {
                        Section {
                            Button(AppLocalization.string("Remove Token"), role: .destructive) {
                                isShowingRemoveConfirmation = true
                            }
                        }
                    }
                }
                .navigationTitle(entry.token.symbol)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !entry.isBuiltIn {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(AppLocalization.string("Edit")) {
                                AddCustomTokenView(store: store, editing: entry)
                            }
                        }
                    }
                }
                .confirmationDialog(AppLocalization.string("Remove Token"), isPresented: $isShowingRemoveConfirmation,
                    titleVisibility: .visible) {
                    Button(AppLocalization.string("Remove"), role: .destructive) { store.removeCustomTokenPreference(entry) }
                    Button(AppLocalization.string("Cancel"), role: .cancel) {}
                } message: {
                    Text(AppLocalization.string("This custom token will be removed and will no longer appear in your portfolio."))
                }
                .onAppear { store.tokenPreferenceError = nil }
            } else {
                ContentUnavailableView(AppLocalization.string("Token Not Found"), systemImage: "questionmark.circle")
            }
        }
        .onChange(of: groupEntries.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    private func providerRow(_ name: String, id: String) -> some View {
        LabeledContent(name) {
            Text(id.isEmpty ? AppLocalization.string("Not Configured") : id)
                .foregroundStyle(id.isEmpty ? .secondary : .primary).textSelection(.enabled)
        }
    }
}
