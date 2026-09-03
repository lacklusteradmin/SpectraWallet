import SwiftUI

/// The wiki is indexed by coin. `listAssetWiki()` joins `crypto-wiki.toml` to
/// both catalogs, so one row is one coin however many chains it lives on —
/// ETH is one page, not the ten it used to be. Chains keep pages of their own,
/// one level down, for what has no coin to belong to.
extension AssetWikiEntry: Identifiable {
    public var id: String { symbol }
    var accentColor: Color { RegistryColorLookup.color(named: color) }
    var face: WikiCoinFace {
        WikiCoinFace(
            name: name, symbol: symbol,
            assetIdentifier: Coin.iconIdentifier(
                symbol: symbol, chainName: livesOn.first?.chainName ?? name),
            color: accentColor)
    }
    var nativePlaces: [AssetWikiPlace] { livesOn.filter(\.isNative) }
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
    private var allEntries: [AssetWikiEntry] { CachedCoreHelpers.assetWiki() }
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
                // Searching a chain finds every coin that lives there, which
                // is the axis the old chain-indexed wiki was built around.
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
                LazyVStack(spacing: 10) {
                    ForEach(filteredEntries) { asset in
                        NavigationLink {
                            AssetWikiDetailView(asset: asset)
                        } label: {
                            CryptoWikiRowCard(asset: asset).equatable()
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { spectraHaptic(.light) })
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }.overlay {
                if filteredEntries.isEmpty { ContentUnavailableView.search }
            }
        }
        .navigationTitle(AppLocalization.string("Crypto Wiki"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: AppLocalization.string("Search coins and chains"))
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: selectedTag) { spectraHaptic(.light) }
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

private struct CryptoWikiRowCard: View, Equatable {
    let asset: AssetWikiEntry
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.asset == rhs.asset }
    var body: some View {
        HStack(spacing: 14) {
            WikiCoinBadge(face: asset.face, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.headline).foregroundStyle(Color.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)).interactive(), in: .rect(cornerRadius: 22))
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
            LazyVStack(spacing: 16) {
                heroCard
                AssetPlacesCard(places: asset.livesOn, symbol: asset.symbol)
                if !asset.totalCirculationModel.isEmpty {
                    circulationCard
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(asset.name).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WikiRotatingCoin(face: asset.face)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            HStack(spacing: 12) {
                WikiCoinBadge(face: asset.face, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name).font(.title3.weight(.semibold))
                    Text(asset.symbol).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(asset.comment).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !asset.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(asset.tags, id: \.self) { tag in
                            Text(tag).font(.caption.weight(.semibold)).foregroundStyle(asset.accentColor)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(asset.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }

    /// A supply cap is the coin's, so it is on the coin's page. It used to be
    /// a column on the chain, which meant the ten chains ETH runs on each
    /// carried a copy of ETH's.
    private var circulationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
                Text(AppLocalization.string("Circulation Model"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(asset.totalCirculationModel).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 32)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
}

// MARK: — Chain detail
