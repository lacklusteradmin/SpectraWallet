import SwiftUI

struct EndpointCatalogSettingsView: View {
    let store: AppState
    @State private var entries: [EndpointDirectoryEntry] = []
    @State private var loadError: String?
    @State private var sourceFilter = "All"
    private let copy = EndpointsContentCopy.current

    private var endpointSections: [Chain] {
        Chain.mainnets.filter { chain in
            !visibleEntries(for: chain).isEmpty
        }
    }
    private func visibleEntries(for chain: Chain) -> [EndpointDirectoryEntry] {
        let ids = Set(AppEndpointDirectory.groupedSettingsEntries(for: chain.id).map(\.chainId) + [chain.id])
        var seen = Set<String>()
        return entries.filter {
            ids.contains($0.record.chainId)
                && seen.insert($0.record.chainId + "\n" + $0.record.endpoint + ($0.isBuiltIn ? "" : $0.apiName)).inserted
                && (sourceFilter == "All" || $0.isBuiltIn == (sourceFilter == "Built-In"))
        }
    }
    private func endpointRow(_ entry: EndpointDirectoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.record.endpoint).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
            let tags = ([entry.apiName].filter { !$0.isEmpty }
                + entry.record.capabilities.map { AppLocalization.string("endpointCapability.\($0)") })
            if !tags.isEmpty {
                Text(tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
            Text(AppLocalization.string(entry.isBuiltIn ? "Built-In" : "Custom"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    var body: some View {
        Form {
            if let loadError { Section { Text(loadError).foregroundStyle(.red) } }
            ForEach(endpointSections) { chain in
                Section(chain.displayName) {
                    let rows = visibleEntries(for: chain)
                    let groups = AppEndpointDirectory.groupedSettingsEntries(for: chain.id)
                    if groups.count > 1 {
                        ForEach(groups, id: \.chainId) { group in
                            let groupRows = rows.filter { $0.record.chainId == group.chainId }
                            if !groupRows.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.title).font(.subheadline.weight(.semibold))
                                    ForEach(groupRows, id: \.record.id) { endpointRow($0) }
                                }.padding(.vertical, 2)
                            }
                        }
                    } else {
                        ForEach(rows, id: \.record.id) { endpointRow($0) }
                    }
                }
            }
        }
        .navigationTitle(copy.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddCustomEndpointView(store: store, directory: entries)
                } label: { Image(systemName: "plus") }
                .accessibilityLabel(copy.addEndpointTitle)
                .disabled(entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(AppLocalization.string("Source"), selection: $sourceFilter) {
                        Text(AppLocalization.string("All")).tag("All")
                        Text(AppLocalization.string("Built-In")).tag("Built-In")
                        Text(AppLocalization.string("Custom")).tag("Custom")
                    }
                } label: {
                    Image(systemName: sourceFilter == "All"
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }.accessibilityLabel(AppLocalization.string("Filters"))
            }
        }
        .task {
            do { entries = try await store.bridge.endpointDirectory(); loadError = nil }
            catch { loadError = error.localizedDescription }
        }
    }
}
