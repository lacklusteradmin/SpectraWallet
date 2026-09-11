import Foundation
import SwiftUI
enum TokenRegistryGrouping {
    nonisolated static func key(for entry: TokenPreferenceEntry) -> String {
        let geckoID = entry.token.coingeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !geckoID.isEmpty { return "gecko:\(geckoID)" }
        return "symbol:\(entry.token.symbol.lowercased())|\(entry.token.name.lowercased())"
    }
}
struct TokenRegistrySettingsView: View {
    let store: AppState
    /// The chain filter is `TokenHostingChain?`, `nil` meaning every chain.
    /// It was a parallel enum with a case per chain and a switch mapping each
    /// one back — eighteen chains hard-coded beside a list core already owns,
    /// which is how the picker came to offer eighteen of twenty-eight.
    private static let chainFilterOptions: [TokenHostingChain?] =
        [nil] + TokenHostingChain.allCases.map { Optional($0) }
    private enum TokenRegistrySourceFilter: CaseIterable, Identifiable {
        case all
        case builtIn
        case custom
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return AppLocalization.string("All")
            case .builtIn: return AppLocalization.string("Built-In")
            case .custom: return AppLocalization.string("Custom")
            }
        }
    }
    @State private var searchText: String = ""
    @State private var chainFilter: TokenHostingChain? = nil
    @State private var sourceFilter: TokenRegistrySourceFilter = .all
    var body: some View {
        Form {
            Section(AppLocalization.string("Filters")) {
                Picker(AppLocalization.string("Network"), selection: $chainFilter) {
                    ForEach(Self.chainFilterOptions, id: \.self) { chain in
                        Text(chain?.filterDisplayName ?? AppLocalization.string("All")).tag(chain)
                    }
                }
                Picker(AppLocalization.string("Source"), selection: $sourceFilter) {
                    ForEach(TokenRegistrySourceFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                if chainFilter != nil || sourceFilter != .all {
                    Button(AppLocalization.string("Clear Filters")) {
                        chainFilter = nil
                        sourceFilter = .all
                    }
                }
            }
            Section(AppLocalization.string("Known Tokens")) {
                if filteredGroups.isEmpty {
                    Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppLocalization.string("No known tokens match the selected filters.")
                            : AppLocalization.string("No matching tokens.")
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredGroups) { group in
                        HStack(spacing: 12) {
                            NavigationLink {
                                TokenRegistryDetailView(store: store, groupKey: group.key)
                            } label: {
                                TokenRegistryGroupRowView(group: group)
                            }.buttonStyle(.plain)
                            Toggle(
                                isOn: Binding(
                                    get: { group.isEnabled },
                                    set: { store.setTokenPreferencesEnabled(group.entries, isEnabled: $0) }
                                )
                            ) { EmptyView() }.labelsHidden().scaleEffect(0.9)
                        }
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Known Tokens"))
            .searchable(text: $searchText, prompt: AppLocalization.string("Search name, symbol, chain, or address"))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AddCustomTokenView(store: store)
                    } label: {
                        Text(AppLocalization.string("New Token"))
                    }
                }
            }
    }
    private var filteredGroups: [TokenRegistryGroup] {
        let allEntries = store.resolvedTokenPreferences
        let grouped = Dictionary(grouping: allEntries, by: TokenRegistryGrouping.key(for:))
        let groups = grouped.values.compactMap { entries -> TokenRegistryGroup? in
            let sortedEntries = entries.sorted { lhs, rhs in
                if lhs.token.chain != rhs.token.chain { return lhs.token.chain < rhs.token.chain }
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                return lhs.token.contract < rhs.token.contract
            }
            guard let representative = sortedEntries.first else { return nil }
            return TokenRegistryGroup(
                key: TokenRegistryGrouping.key(for: representative), name: representative.token.name,
                symbol: representative.token.symbol,
                entries: sortedEntries
            )
        }
        let filtered: [TokenRegistryGroup] = groups.filter { group in
            if let selectedChain = chainFilter, !group.entries.contains(where: { $0.token.chain == selectedChain.rawValue }) {
                return false
            }
            switch sourceFilter {
            case .all: break
            case .builtIn: guard group.entries.contains(where: { $0.isBuiltIn }) else { return false }
            case .custom: guard group.entries.contains(where: { !$0.isBuiltIn }) else { return false }
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            let haystack =
                ([group.symbol, group.name]
                + group.entries.flatMap { entry in
                    [entry.token.chain, entry.token.tokenStandard, entry.token.contract, entry.token.coingeckoId]
                })
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { lhs, rhs in
            let lhsBuiltIn = lhs.entries.contains { $0.isBuiltIn }
            let rhsBuiltIn = rhs.entries.contains { $0.isBuiltIn }
            if lhsBuiltIn != rhsBuiltIn { return lhsBuiltIn }
            return lhs.symbol < rhs.symbol
        }
    }
}
