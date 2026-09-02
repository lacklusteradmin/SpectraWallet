import Foundation
import SwiftUI
struct TokenRegistryDetailView: View {
    let store: AppState
    let groupKey: String
    private var groupEntries: [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { TokenRegistryGrouping.key(for: $0) == groupKey }
            .sorted { lhs, rhs in
                if lhs.token.chain != rhs.token.chain { return lhs.token.chain < rhs.token.chain }
                return lhs.token.contract < rhs.token.contract
            }
    }
    private var representativeEntry: TokenPreferenceEntry? { groupEntries.first }
    var body: some View {
        if let representativeEntry {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: representativeEntry.settingsAssetIdentifier,
                            fallbackText: representativeEntry.settingsFallbackMark,
                            color: representativeEntry.hostingChain?.settingsIconTint ?? .accentColor, size: 42
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(representativeEntry.token.name).font(.headline)
                            Text(representativeEntry.token.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                Section(AppLocalization.string("Chain Support")) {
                    ForEach(groupEntries) { entry in
                        TokenRegistryEntryCardView(
                            entry: entry, setEnabled: { store.setTokenPreferenceEnabled(id: entry.id, isEnabled: $0) },
                            updateDecimals: { store.updateCustomTokenPreferenceDecimals(id: entry.id, decimals: $0) },
                            removeToken: { store.removeCustomTokenPreference(id: entry.id) }
                        )
                    }
                }
            }.navigationTitle(representativeEntry.token.symbol)
        } else {
            ContentUnavailableView(AppLocalization.string("Token Not Found"), systemImage: "questionmark.circle")
        }
    }
}
