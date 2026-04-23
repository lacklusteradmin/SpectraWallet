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
struct ChainWikiLibraryView: View {
    @State private var selectedTag: String?
    private var filteredEntries: [ChainWikiEntry] {
        let entries = ChainWikiEntry.all
        guard let selectedTag else { return entries }
        return entries.filter { $0.tags.contains(selectedTag) }
    }
    private var availableTags: [String] { ChainWikiEntry.all.availableWikiTags }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ChainWikiIntroCard()
                ChainWikiTagFilterBar(
                    tags: availableTags, selectedTag: selectedTag,
                    onSelect: { tag in
                        if tag.isEmpty {
                            selectedTag = nil
                            return
                        }
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                )
                VStack(spacing: 0) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, chain in
                        NavigationLink {
                            ChainWikiDetailView(chain: chain)
                        } label: {
                            ChainWikiRowCard(chain: chain).equatable()
                                .padding(.horizontal, 4).padding(.vertical, 12)
                        }.buttonStyle(.plain)
                        if index < filteredEntries.count - 1 {
                            Divider().padding(.leading, 56).opacity(0.25)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.navigationTitle(AppLocalization.string("Chain Wiki"))
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
struct ChainWikiDetailView: View {
    let chain: ChainWikiEntry
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ChainWikiHeroCard(chain: chain)
                ChainWikiSectionCard(title: AppLocalization.string("Primary Use")) {
                    Text(chain.primaryUse).font(.body).foregroundStyle(.secondary)
                }
                ChainWikiSectionCard(title: AppLocalization.string("Identity")) {
                    VStack(spacing: 12) {
                        ChainWikiKeyValueRow(title: AppLocalization.string("Ticker"), value: chain.symbol)
                        ChainWikiKeyValueRow(title: AppLocalization.string("Family"), value: chain.family)
                        ChainWikiKeyValueRow(title: AppLocalization.string("Consensus"), value: chain.consensus)
                        ChainWikiKeyValueRow(title: AppLocalization.string("State Model"), value: chain.stateModel)
                    }
                }
                ChainWikiSectionCard(title: AppLocalization.string("Derivation In Spectra")) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocalization.string("Default Path")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(chain.derivationPath).font(.body.monospaced()).foregroundStyle(Color.primary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .spectraCardFill(cornerRadius: 18)
                        if let alternateDerivationPath = chain.alternateDerivationPath {
                            Text(alternateDerivationPath).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                ChainWikiSectionCard(title: AppLocalization.string("Circulation Model")) {
                    Text(chain.totalCirculationModel).font(.body).foregroundStyle(.secondary)
                }
                ChainWikiSectionCard(title: AppLocalization.string("Technical Notes")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(chain.notableDetails.indices, id: \.self) { index in
                            let detail = chain.notableDetails[index]
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(chain.accentColor).frame(
                                    width: 22, height: 22
                                ).background(
                                    Circle().fill(chain.accentColor.opacity(0.18))
                                )
                                Text(detail).font(.body).foregroundStyle(.secondary).frame(
                                    maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.navigationTitle(chain.name)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
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
    var secondaryAccentColor: Color {
        switch id {
        case "bitcoin", "bitcoin-cash", "dogecoin", "monero": return .yellow
        case "litecoin": return .white.opacity(0.85)
        case "ethereum", "ethereum-classic": return .blue
        case "bnb": return .orange
        case "avalanche", "tron": return .pink
        case "hyperliquid": return .indigo
        case "solana": return .cyan
        case "aptos": return .gray
        case "cardano", "xrp": return .cyan
        case "sui", "stellar": return .mint
        case "near": return .blue
        case "polkadot": return .purple
        case "internet-computer": return .pink
        default: return accentColor.opacity(0.7)
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
private struct ChainWikiIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.string("Protocol Reference")).font(.title3.weight(.bold)).foregroundStyle(Color.primary)
            Text(
                AppLocalization.string(
                    "Browse Spectra's supported chains, default derivation paths, and protocol-level notes in a cleaner reference format."
                )
            ).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }
}
private struct ChainWikiTagFilterBar: View {
    let tags: [String]
    let selectedTag: String?
    let onSelect: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ChainWikiFilterChip(
                    text: AppLocalization.string("Chains"), tint: .orange, isSelected: selectedTag == nil, action: { onSelect("") }
                )
                ForEach(tags, id: \.self) { tag in
                    ChainWikiFilterChip(
                        text: tag, tint: .blue, isSelected: selectedTag == tag, action: { onSelect(tag) }
                    )
                }
            }.padding(.vertical, 2)
        }
    }
}
private struct ChainWikiRowCard: View, Equatable {
    let chain: ChainWikiEntry
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.chain == rhs.chain }
    var body: some View {
        HStack(spacing: 14) {
            ChainWikiChainLogoBadge(
                chain: chain, size: 44, cornerRadius: 22, titleFont: .headline.weight(.bold)
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(chain.name).font(.headline.weight(.semibold)).foregroundStyle(Color.primary)
                Text(chain.family).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    ForEach(Array(chain.tags.prefix(3)), id: \.self) { tag in ChainWikiMiniTag(text: tag) }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }.contentShape(Rectangle())
    }
}
private struct ChainWikiHeroCard: View {
    let chain: ChainWikiEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ChainWikiChainLogoBadge(
                    chain: chain, size: 72, cornerRadius: 20, titleFont: .title3.weight(.bold), useFullSymbolFallback: true
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(chain.name).font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                    Text(chain.family).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !chain.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chain.tags, id: \.self) { tag in
                            ChainWikiPill(text: tag, tint: chain.secondaryAccentColor)
                        }
                    }
                }
            }
            ChainWikiMetricCard(title: AppLocalization.string("State"), value: chain.stateModel, tint: chain.secondaryAccentColor)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(chain.accentColor.opacity(0.12)), in: .rect(cornerRadius: 28))
    }
}
private struct ChainWikiChainLogoBadge: View {
    let chain: ChainWikiEntry
    let size: CGFloat
    let cornerRadius: CGFloat
    let titleFont: Font
    var useFullSymbolFallback = false
    var body: some View {
        if let nativeAssetIdentifier = chain.nativeAssetIdentifier {
            CoinBadge(
                assetIdentifier: nativeAssetIdentifier,
                fallbackText: useFullSymbolFallback ? chain.symbol : String(chain.symbol.prefix(2)), color: .white, size: size
            )
        } else {
            Text(useFullSymbolFallback ? chain.symbol : String(chain.symbol.prefix(2))).font(titleFont).foregroundStyle(
                chain.accentColor
            ).frame(width: size, height: size)
        }
    }
}
private struct ChainWikiSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(Color.primary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }
}
private struct ChainWikiKeyValueRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary).multilineTextAlignment(.trailing)
        }
    }
}
private struct ChainWikiMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: 18))
    }
}
private struct ChainWikiPill: View {
    let text: String
    var tint: Color = .orange
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 6).background(
            tint.opacity(0.12), in: Capsule())
    }
}
private struct ChainWikiMiniTag: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 8).padding(
            .vertical, 5
        ).background(Color.primary.opacity(0.05), in: Capsule())
    }
}
private struct ChainWikiFilterChip: View {
    let text: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(isSelected ? Color.white : tint).padding(.horizontal, 12).padding(
                .vertical, 8
            ).background(
                Capsule().fill(isSelected ? tint : tint.opacity(0.12))
            )
        }.buttonStyle(.plain)
    }
}
