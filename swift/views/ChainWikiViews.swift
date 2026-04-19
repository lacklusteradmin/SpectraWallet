import SwiftUI
private func localizedChainWikiString(_ key: String) -> String {
    AppLocalization.string(key)
}
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
        return entries.filter { $0.tags.contains(selectedTag) }}
    private var availableTags: [String] { ChainWikiEntry.all.availableWikiTags }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ChainWikiIntroCard()
                ChainWikiTagFilterBar(
                    tags: availableTags, selectedTag: selectedTag, onSelect: { tag in
                        if tag.isEmpty {
                            selectedTag = nil
                            return
                        }
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                )
                LazyVStack(spacing: 14) {
                    ForEach(filteredEntries) { chain in
                        NavigationLink {
                            ChainWikiDetailView(chain: chain)
                        } label: { ChainWikiRowCard(chain: chain).equatable() }.buttonStyle(.plain)
                    }}}.padding(.horizontal, 20).padding(.vertical, 18)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(localizedChainWikiString("Chain Wiki"))
    }
}
struct ChainWikiDetailView: View {
    let chain: ChainWikiEntry
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ChainWikiHeroCard(chain: chain)
                ChainWikiSectionCard(title: localizedChainWikiString("Primary Use")) {
                    Text(chain.primaryUse).font(.body).foregroundStyle(Color.primary.opacity(0.86))
                }
                ChainWikiSectionCard(title: localizedChainWikiString("Identity")) {
                    VStack(spacing: 12) {
                        ChainWikiKeyValueRow(title: localizedChainWikiString("Ticker"), value: chain.symbol)
                        ChainWikiKeyValueRow(title: localizedChainWikiString("Family"), value: chain.family)
                        ChainWikiKeyValueRow(title: localizedChainWikiString("Consensus"), value: chain.consensus)
                        ChainWikiKeyValueRow(title: localizedChainWikiString("State Model"), value: chain.stateModel)
                    }}
                ChainWikiSectionCard(title: localizedChainWikiString("Derivation In Spectra")) {
                    VStack(alignment: .leading, spacing: 14) {
                        ChainWikiKeyValueRow(title: localizedChainWikiString("SLIP44 Coin Type"), value: chain.slip44CoinType)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizedChainWikiString("Default Path")).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.58))
                            Text(chain.derivationPath).font(.body.monospaced()).foregroundStyle(Color.primary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05))
                        )
                        if let alternateDerivationPath = chain.alternateDerivationPath { Text(alternateDerivationPath).font(.footnote).foregroundStyle(Color.primary.opacity(0.7)) }}}
                ChainWikiSectionCard(title: localizedChainWikiString("Circulation Model")) {
                    Text(chain.totalCirculationModel).font(.body).foregroundStyle(Color.primary.opacity(0.86))
                }
                ChainWikiSectionCard(title: localizedChainWikiString("Technical Notes")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(chain.notableDetails.enumerated()), id: \.offset) { index, detail in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(chain.accentColor).frame(width: 22, height: 22).background(
                                        Circle().fill(chain.accentColor.opacity(0.14))
                                    )
                                Text(detail).font(.body).foregroundStyle(Color.primary.opacity(0.84)).frame(maxWidth: .infinity, alignment: .leading)
                            }}}}}.padding(.horizontal, 20).padding(.vertical, 18)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(chain.name)
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
        }}
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
        }}
}
private extension Array where Element == ChainWikiEntry {
    var availableWikiTags: [String] {
        let preferredOrder = [
            "UTXO", "eUTXO", "EVM", "L2", "Rollup", "Move", "Object", "Privacy", "Payments", "Settlement", "Smart Contracts", "PoW", "PoS", "Sharding", "Relay Chain", "Canisters", "Messaging", "High Throughput"
        ]
        let tags = reduce(into: [String]()) { result, entry in
            for tag in entry.tags where !result.contains(tag) { result.append(tag) }}
        return tags.sorted { lhs, rhs in
            let leftIndex = preferredOrder.firstIndex(of: lhs) ?? .max
            let rightIndex = preferredOrder.firstIndex(of: rhs) ?? .max
            if leftIndex == rightIndex { return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending }
            return leftIndex < rightIndex
        }}
}
private struct ChainWikiIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedChainWikiString("Protocol Reference")).font(.title3.weight(.bold)).foregroundStyle(Color.primary)
            Text(localizedChainWikiString("Browse Spectra's supported chains, default derivation paths, registered SLIP44 coin types, and protocol-level notes in a cleaner reference format.")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.74))
            HStack(spacing: 10) {
                ChainWikiPill(text: "\(ChainWikiEntry.all.count) \(localizedChainWikiString("Chains"))")
                ChainWikiPill(text: localizedChainWikiString("Derivation Paths"))
                ChainWikiPill(text: localizedChainWikiString("SLIP44"))
            }}.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.18), Color.yellow.opacity(0.08), Color.white.opacity(0.82)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        ).overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
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
                    text: localizedChainWikiString("Chains"), tint: .orange, isSelected: selectedTag == nil, action: { onSelect("") }
                )
                ForEach(tags, id: \.self) { tag in
                    ChainWikiFilterChip(
                        text: tag, tint: .blue, isSelected: selectedTag == tag, action: { onSelect(tag) }
                    )
                }}.padding(.vertical, 2)
        }}
}
private struct ChainWikiRowCard: View, Equatable {
    let chain: ChainWikiEntry
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.chain == rhs.chain }
    var body: some View {
        HStack(spacing: 14) {
            ChainWikiChainLogoBadge(
                chain: chain, size: 50, cornerRadius: 25, titleFont: .headline.weight(.bold)
            )
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chain.name).font(.headline.weight(.semibold)).foregroundStyle(Color.primary)
                    Spacer(minLength: 0)
                }
                Text(chain.family).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72)).lineLimit(2)
                HStack(spacing: 8) {
                    ForEach(Array(chain.tags.prefix(3)), id: \.self) { tag in ChainWikiMiniTag(text: tag) }}}
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.primary.opacity(0.35))
        }.padding(16).background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground))
        ).overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
private struct ChainWikiHeroCard: View {
    let chain: ChainWikiEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ChainWikiChainLogoBadge(
                    chain: chain, size: 82, cornerRadius: 24, titleFont: .title3.weight(.black), useFullSymbolFallback: true
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(chain.name).font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                    Text(chain.family).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72))
                    HStack(spacing: 8) {
                        ForEach(chain.tags, id: \.self) { tag in ChainWikiPill(text: tag, tint: chain.secondaryAccentColor) }}}}
            HStack(spacing: 12) {
                ChainWikiMetricCard(
                    title: localizedChainWikiString("SLIP44"), value: chain.slip44CoinType.components(separatedBy: " ").first ?? chain.slip44CoinType, tint: chain.accentColor
                )
                ChainWikiMetricCard(title: localizedChainWikiString("State"), value: chain.stateModel, tint: chain.secondaryAccentColor)
            }}.padding(20).background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(
                    LinearGradient(
                        colors: [
                            chain.accentColor.opacity(0.18), chain.secondaryAccentColor.opacity(0.1), Color.white.opacity(0.82)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        ).overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.58), lineWidth: 1)
        )
    }
}
private struct ChainWikiChainLogoBadge: View {
    let chain: ChainWikiEntry
    let size: CGFloat
    let cornerRadius: CGFloat
    let titleFont: Font
    var useFullSymbolFallback = false
    var body: some View {
        Group {
            if let nativeAssetIdentifier = chain.nativeAssetIdentifier {
                CoinBadge(
                    assetIdentifier: nativeAssetIdentifier, fallbackText: useFullSymbolFallback ? chain.symbol : String(chain.symbol.prefix(2)), color: .white, size: size
                )
            } else { Text(useFullSymbolFallback ? chain.symbol : String(chain.symbol.prefix(2))).font(titleFont).foregroundStyle(chain.accentColor).frame(width: size, height: size) }}}
}
private struct ChainWikiSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(Color.primary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground))
        ).overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
private struct ChainWikiKeyValueRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.56))
            Text(value).font(.body).foregroundStyle(Color.primary.opacity(0.88))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct ChainWikiMetricCard: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.58))
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.12))
        )
    }
}
private struct ChainWikiPill: View {
    let text: String
    var tint: Color = .orange
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 6).background(tint.opacity(0.12), in: Capsule())
    }
}
private struct ChainWikiMiniTag: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5).background(Color.primary.opacity(0.05), in: Capsule())
    }
}
private struct ChainWikiFilterChip: View {
    let text: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(isSelected ? Color.white : tint).padding(.horizontal, 12).padding(.vertical, 8).background(
                    Capsule().fill(isSelected ? tint : tint.opacity(0.12))
                )
        }.buttonStyle(.plain)
    }
}
