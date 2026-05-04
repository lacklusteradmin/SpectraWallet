import SwiftUI
struct ChainWikiEntry: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let tags: [String]
    let family: String
    let consensus: String
    let stateModel: String
    let primaryUse: String
    let slip44CoinType: String
    let derivationPath: String
    let alternateDerivationPath: String?
    let totalCirculationModel: String
    let notableDetails: [String]
    static var all: [ChainWikiEntry] { ChainWikiLibrary.loadEntries() }
}
private enum ChainWikiLibrary {
    static func loadEntries() -> [ChainWikiEntry] { StaticContentCatalog.loadResource("ChainWikiEntries", as: [ChainWikiEntry].self) ?? [] }
}

// MARK: — Library (list view)

struct ChainWikiLibraryView: View {
    @State private var searchText: String = ""
    @State private var selectedTag: String?
    private var filteredEntries: [ChainWikiEntry] {
        var entries = ChainWikiEntry.all
        if let selectedTag { entries = entries.filter { $0.tags.contains(selectedTag) } }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || entry.symbol.localizedCaseInsensitiveContains(query)
                || entry.family.localizedCaseInsensitiveContains(query)
                || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    private var availableTags: [String] { ChainWikiEntry.all.availableWikiTags }
    var body: some View {
        List {
            ForEach(filteredEntries) { chain in
                NavigationLink {
                    ChainWikiDetailView(chain: chain)
                } label: {
                    ChainWikiRowLabel(chain: chain).equatable()
                }
            }
        }.listStyle(.insetGrouped)
            .navigationTitle(AppLocalization.string("Chain Wiki"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: AppLocalization.string("Search chains"))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(AppLocalization.string("Tag"), selection: $selectedTag) {
                            Text(AppLocalization.string("All")).tag(Optional<String>.none)
                            ForEach(availableTags, id: \.self) { tag in
                                Text(tag).tag(Optional(tag))
                            }
                        }
                    } label: {
                        Image(systemName: selectedTag == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }.accessibilityLabel(AppLocalization.string("Filter by tag"))
                }
            }
            .overlay {
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search
                }
            }
    }
}
private struct ChainWikiRowLabel: View, Equatable {
    let chain: ChainWikiEntry
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.chain == rhs.chain }
    var body: some View {
        HStack(spacing: 12) {
            ChainWikiChainLogoBadge(chain: chain, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.name).font(.body)
                Text(chain.family).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 2)
    }
}

// MARK: — Detail view

struct ChainWikiDetailView: View {
    let chain: ChainWikiEntry
    var body: some View {
        Form {
            Section {
                ChainWikiDetailHero(chain: chain)
            }
            Section(AppLocalization.string("Identity")) {
                ChainWikiKeyValueRow(title: AppLocalization.string("Ticker"), value: chain.symbol)
                ChainWikiKeyValueRow(title: AppLocalization.string("Family"), value: chain.family)
                ChainWikiKeyValueRow(title: AppLocalization.string("Consensus"), value: chain.consensus)
                ChainWikiKeyValueRow(title: AppLocalization.string("State Model"), value: chain.stateModel)
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Default Path")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(chain.derivationPath).font(.body.monospaced()).textSelection(.enabled)
                }.padding(.vertical, 4)
                if let alternateDerivationPath = chain.alternateDerivationPath {
                    Text(alternateDerivationPath).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(AppLocalization.string("Derivation"))
            }
            Section(AppLocalization.string("Circulation Model")) {
                Text(chain.totalCirculationModel).font(.body).foregroundStyle(.secondary)
            }
            if !chain.notableDetails.isEmpty {
                Section(AppLocalization.string("Technical Notes")) {
                    ForEach(Array(chain.notableDetails.enumerated()), id: \.offset) { index, detail in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold)).foregroundStyle(chain.accentColor)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(chain.accentColor.opacity(0.18)))
                            Text(detail).font(.body).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 2)
                    }
                }
            }
        }.navigationTitle(chain.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChainWikiDetailHero: View {
    let chain: ChainWikiEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ChainWikiChainLogoBadge(chain: chain, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.name).font(.title3.weight(.semibold))
                    Text(chain.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(chain.primaryUse).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !chain.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chain.tags, id: \.self) { tag in
                            Text(tag).font(.caption.weight(.semibold)).foregroundStyle(chain.accentColor)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(chain.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }.padding(.vertical, 6)
    }
}

private struct ChainWikiKeyValueRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Color.primary).multilineTextAlignment(.trailing)
        }
    }
}

private struct ChainWikiChainLogoBadge: View {
    let chain: ChainWikiEntry
    let size: CGFloat
    var body: some View {
        CoinBadge(
            assetIdentifier: chain.nativeAssetIdentifier, fallbackText: chain.symbol,
            color: chain.accentColor, size: size
        )
    }
}

// MARK: — Data helpers

private extension ChainWikiEntry {
    var registryEntry: ChainRegistryEntry? { ChainRegistryEntry.entry(id: id) }
    var nativeAssetIdentifier: String? { registryEntry?.assetIdentifier }
    var accentColor: Color {
        if let registryEntry { return registryEntry.color }
        switch id {
        case "bitcoin", "bitcoin-cash", "dogecoin", "monero": return .orange
        case "litecoin": return .gray
        case "ethereum", "ethereum-classic": return .indigo
        case "bnb": return .yellow
        case "avalanche", "tron": return .red
        case "hyperliquid": return .cyan
        case "solana": return .mint
        case "aptos": return .black
        case "cardano", "xrp": return .blue
        case "sui", "stellar": return .teal
        case "near": return .green
        case "polkadot": return .pink
        case "internet-computer": return .purple
        default: return .accentColor
        }
    }
}
private extension Array where Element == ChainWikiEntry {
    var availableWikiTags: [String] {
        let preferredOrder = [
            "UTXO", "eUTXO", "EVM", "L2", "Rollup", "Move", "Object", "Privacy", "Payments", "Settlement", "Smart Contracts", "PoW", "PoS",
            "Sharding", "Relay Chain", "Canisters", "Messaging", "High Throughput",
        ]
        let tags = reduce(into: [String]()) { result, entry in
            for tag in entry.tags where !result.contains(tag) { result.append(tag) }
        }
        return tags.sorted { lhs, rhs in
            let leftIndex = preferredOrder.firstIndex(of: lhs) ?? .max
            let rightIndex = preferredOrder.firstIndex(of: rhs) ?? .max
            if leftIndex == rightIndex { return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending }
            return leftIndex < rightIndex
        }
    }
}
