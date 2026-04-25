import Foundation
import SwiftUI
enum TokenRegistryGrouping {
    nonisolated static func key(for entry: TokenPreferenceEntry) -> String {
        let geckoID = entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !geckoID.isEmpty { return "gecko:\(geckoID)" }
        return "symbol:\(entry.symbol.lowercased())|\(entry.name.lowercased())"
    }
}
struct TokenRegistrySettingsView: View {
    let store: AppState
    private enum TokenRegistryChainFilter: CaseIterable, Identifiable {
        case all
        case ethereum
        case arbitrum
        case optimism
        case bnb
        case avalanche
        case hyperliquid
        case polygon
        case base
        case linea
        case scroll
        case blast
        case mantle
        case solana
        case sui
        case aptos
        case ton
        case near
        case tron
        var id: Self { self }
        var title: String { chain?.filterDisplayName ?? AppLocalization.string("All") }
        var chain: TokenTrackingChain? {
            switch self {
            case .all: return nil
            case .ethereum: return .ethereum
            case .arbitrum: return .arbitrum
            case .optimism: return .optimism
            case .bnb: return .bnb
            case .avalanche: return .avalanche
            case .hyperliquid: return .hyperliquid
            case .polygon: return .polygon
            case .base: return .base
            case .linea: return .linea
            case .scroll: return .scroll
            case .blast: return .blast
            case .mantle: return .mantle
            case .solana: return .solana
            case .sui: return .sui
            case .aptos: return .aptos
            case .ton: return .ton
            case .near: return .near
            case .tron: return .tron
            }
        }
    }
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
    @State private var chainFilter: TokenRegistryChainFilter = .all
    @State private var sourceFilter: TokenRegistrySourceFilter = .all
    var body: some View {
        Form {
            Section(AppLocalization.string("Filters")) {
                Picker(AppLocalization.string("Network"), selection: $chainFilter) {
                    ForEach(TokenRegistryChainFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                Picker(AppLocalization.string("Source"), selection: $sourceFilter) {
                    ForEach(TokenRegistrySourceFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                if chainFilter != .all || sourceFilter != .all {
                    Button(AppLocalization.string("Clear Filters")) {
                        chainFilter = .all
                        sourceFilter = .all
                    }
                }
            }
            Section(AppLocalization.string("Tracked Tokens")) {
                if filteredGroups.isEmpty {
                    Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppLocalization.string("No tracked tokens match the selected filters.")
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
                                    set: { store.setTokenPreferencesEnabled(ids: group.allEntryIDs, isEnabled: $0) }
                                )
                            ) { EmptyView() }.labelsHidden().scaleEffect(0.9)
                        }
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Tracked Tokens"))
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
    private func entries(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { $0.chain == chain }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
                return lhs.symbol < rhs.symbol
            }
    }
    private var filteredGroups: [TokenRegistryGroup] {
        let allEntries = store.resolvedTokenPreferences
        let grouped = Dictionary(grouping: allEntries, by: TokenRegistryGrouping.key(for:))
        let groups = grouped.values.compactMap { entries -> TokenRegistryGroup? in
            let sortedEntries = entries.sorted { lhs, rhs in
                if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                return lhs.contractAddress < rhs.contractAddress
            }
            guard let representative = sortedEntries.first else { return nil }
            return TokenRegistryGroup(
                key: TokenRegistryGrouping.key(for: representative), name: representative.name, symbol: representative.symbol,
                entries: sortedEntries
            )
        }
        let filtered = groups.filter { group in
            if let selectedChain = chainFilter.chain, !group.entries.contains(where: { $0.chain == selectedChain }) {
                return false
            }
            switch sourceFilter {
            case .all: break
            case .builtIn: guard group.entries.contains(where: \.isBuiltIn) else { return false }
            case .custom: guard group.entries.contains(where: { !$0.isBuiltIn }) else { return false }
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            let haystack =
                ([group.symbol, group.name]
                + group.entries.flatMap { entry in [entry.chain.rawValue, entry.tokenStandard, entry.contractAddress, entry.coinGeckoId] })
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.entries.contains(where: \.isBuiltIn) != rhs.entries.contains(where: \.isBuiltIn) {
                return lhs.entries.contains(where: \.isBuiltIn)
            }
            return lhs.symbol < rhs.symbol
        }
    }
}
