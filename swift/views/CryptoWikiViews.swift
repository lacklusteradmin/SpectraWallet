import SwiftUI

/// The wiki is indexed by coin. `listAssetWiki()` joins both catalogs so
/// each coin has one page. Chain-specific information lives one level below.
extension AssetWikiEntry: Identifiable {
    public var id: String { tokenId }
    var accentColor: Color { color?.color ?? .accentColor }
    var face: WikiCoinFace {
        WikiCoinFace(name: name, symbol: symbol, artworkName: artworkName, color: accentColor)
    }
}

extension AssetWikiPlace: Identifiable {
    public var id: String { "\(chainId)|\(contract)" }
}

extension ChainDerivationPathEntry: Identifiable {
    public var id: String { "\(tag)|\(path)" }
    var displayPath: String { path.replacingOccurrences(of: "{account}", with: "0") }
}

// MARK: — Library (list view)

struct CryptoWikiLibraryView: View {
    @State private var searchText: String = ""
    @State private var selectedTag: String?
    private var allEntries: [AssetWikiEntry] { CoreReferenceTables.assetWiki }
    private var filteredEntries: [AssetWikiEntry] {
        var entries = allEntries
        if let selectedTag { entries = entries.filter { $0.tags.contains(selectedTag) } }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || entry.symbol.localizedCaseInsensitiveContains(query)
                || entry.comment.localizedCaseInsensitiveContains(query)
                || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                // Searching a chain finds every coin that lives there.
                || entry.livesOn.contains(where: { $0.chainName.localizedCaseInsensitiveContains(query) })
        }
    }
    private var availableTags: [String] {
        var seen: [String] = []
        for entry in allEntries where !entry.tags.isEmpty {
            for tag in entry.tags where !seen.contains(tag) { seen.append(tag) }
        }
        return seen.sorted()
    }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                if !filteredEntries.isEmpty {
                    SpectraRowGroup(data: filteredEntries) { asset in
                        NavigationLink {
                            AssetWikiDetailView(asset: asset)
                        } label: {
                            CryptoWikiRow(asset: asset).equatable()
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { spectraHaptic(.light) })
                    }.spectraScreenPadding()
                }
            }.overlay {
                if filteredEntries.isEmpty { ContentUnavailableView.search }
            }
        }
        .navigationTitle(AppLocalization.string("Crypto Wiki"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: AppLocalization.string("Search coins and chains"))
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedTag)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(AppLocalization.string("Tag"), selection: $selectedTag) {
                        Text(AppLocalization.string("All")).tag(String?.none)
                        ForEach(availableTags, id: \.self) { tag in
                            Text(tag).tag(String?.some(tag))
                        }
                    }
                } label: {
                    Image(systemName: selectedTag == nil
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(AppLocalization.string("Filter by tag"))
            }
        }
    }
}

private struct CryptoWikiRow: View, Equatable {
    let asset: AssetWikiEntry
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.asset == rhs.asset }
    var body: some View {
        HStack(spacing: SpectraLayout.Space.m) {
            WikiCoinBadge(face: asset.face, size: 36)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                Text(asset.name).font(.headline).foregroundStyle(Color.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .spectraRowPadding()
    }
    private var subtitle: String {
        let places = asset.livesOn.count
        guard let first = asset.livesOn.first else { return asset.symbol }
        if places == 1 {
            return AppLocalization.format("dashboard.asset.onChain", first.chainName)
        }
        return AppLocalization.format("wiki.asset.onChains", "\(places)")
    }
}

// MARK: — Asset detail

struct AssetWikiDetailView: View {
    let asset: AssetWikiEntry
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: SpectraLayout.Space.m) {
                heroCard
                AssetPlacesCard(places: asset.livesOn, symbol: asset.symbol)
                if !asset.totalCirculationModel.isEmpty {
                    circulationCard
                }
            }
            .spectraScreenPadding()
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(asset.name).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack(spacing: SpectraLayout.Space.m) {
                WikiCoinBadge(face: asset.face, size: 52)
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(asset.name).font(.title3.weight(.semibold))
                    Text(asset.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(asset.comment).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !asset.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpectraLayout.Space.xs) {
                        ForEach(asset.tags, id: \.self) { tag in
                            Text(tag).font(.caption.weight(.semibold)).foregroundStyle(asset.accentColor)
                                .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xs)
                                .background(asset.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }

    /// Supply caps belong to coins.
    private var circulationCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.tint).frame(width: 22)
                Text(AppLocalization.string("Circulation Model"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(asset.totalCirculationModel).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, SpectraLayout.Space.xl)
        }
        .padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }
}

// MARK: — Chain detail
