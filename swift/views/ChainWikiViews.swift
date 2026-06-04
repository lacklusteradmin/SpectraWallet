import SwiftUI
struct ChainWikiEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let tags: [String]
    let comment: String
    let family: String
    let consensus: String
    let stateModel: String
    let primaryUse: String
    let derivationPaths: [ChainWikiDerivationPath]
    let totalCirculationModel: String
    static var all: [ChainWikiEntry] {
        listAllChains()
            .filter { !$0.family.isEmpty }
            .map { chain in
                ChainWikiEntry(
                    id: chain.id, name: chain.name, symbol: chain.symbol, tags: chain.tags,
                    comment: chain.comment, family: chain.family, consensus: chain.consensus, stateModel: chain.stateModel,
                    primaryUse: chain.primaryUse,
                    derivationPaths: chain.derivationPath.map(ChainWikiDerivationPath.init(corePath:)),
                    totalCirculationModel: chain.totalCirculationModel
                )
            }
    }
}

struct ChainWikiDerivationPath: Identifiable, Equatable {
    let tag: String
    let path: String
    let isDefault: Bool
    let note: String
    var id: String { "\(tag)|\(path)" }
    var displayPath: String { path.replacingOccurrences(of: "{account}", with: "0") }

    init(corePath: ChainDerivationPathEntry) {
        tag = corePath.tag
        path = corePath.path
        isDefault = corePath.isDefault
        note = corePath.note
    }
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
                || entry.comment.localizedCaseInsensitiveContains(query)
                || entry.family.localizedCaseInsensitiveContains(query)
                || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    private var availableTags: [String] { ChainWikiEntry.all.availableWikiTags }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(filteredEntries) { chain in
                        NavigationLink {
                            ChainWikiDetailView(chain: chain)
                        } label: {
                            ChainWikiRowCard(chain: chain).equatable()
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { spectraHaptic(.light) })
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }.overlay {
                if filteredEntries.isEmpty { ContentUnavailableView.search }
            }
        }
        .navigationTitle(AppLocalization.string("Chain Wiki"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: AppLocalization.string("Search chains"))
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: selectedTag) { spectraHaptic(.light) }
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
    }
}
private struct ChainWikiRowCard: View, Equatable {
    let chain: ChainWikiEntry
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.chain == rhs.chain }
    var body: some View {
        HStack(spacing: 14) {
            ChainWikiChainLogoBadge(chain: chain, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(chain.name).font(.headline).foregroundStyle(Color.primary)
                Text(chain.family).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)).interactive(), in: .rect(cornerRadius: 22))
    }
}

// MARK: — Detail view

struct ChainWikiDetailView: View {
    let chain: ChainWikiEntry
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                wikiHeroCard
                wikiIdentityCard
                wikiDerivationCard
                wikiCirculationCard
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(chain.name).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var wikiHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ChainWikiChainLogoBadge(chain: chain, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chain.name).font(.title3.weight(.semibold))
                    Text(chain.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(chain.comment).font(.subheadline).foregroundStyle(.secondary)
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
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }

    private var wikiIdentityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            wikiStatRow(label: AppLocalization.string("Ticker"), value: chain.symbol, icon: "tag.fill")
            Divider().opacity(0.4)
            wikiStatRow(label: AppLocalization.string("Family"), value: chain.family, icon: "link.circle.fill")
            Divider().opacity(0.4)
            wikiStatRow(label: AppLocalization.string("Consensus"), value: chain.consensus, icon: "checkmark.shield.fill")
            Divider().opacity(0.4)
            wikiStatRow(label: AppLocalization.string("State Model"), value: chain.stateModel, icon: "cylinder.split.1x2.fill")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    private var wikiDerivationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
                Text(AppLocalization.string("Derivation Paths")).font(.subheadline).foregroundStyle(.secondary)
            }
            if chain.derivationPaths.isEmpty {
                Text(AppLocalization.string("Not user-configurable in Spectra's current UI."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
            } else {
                ForEach(chain.derivationPaths) { path in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(path.tag).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if path.isDefault {
                                Text(AppLocalization.string("Default"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.orange.opacity(0.14), in: Capsule())
                            }
                        }
                        Text(path.displayPath).font(.body.monospaced()).foregroundStyle(Color.primary)
                            .textSelection(.enabled)
                        if !path.note.isEmpty {
                            Text(path.note).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 32)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    private var wikiCirculationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
                Text(AppLocalization.string("Circulation Model"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(chain.totalCirculationModel).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 32)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    private func wikiStatRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                .multilineTextAlignment(.trailing)
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
