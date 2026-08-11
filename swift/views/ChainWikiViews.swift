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
            ChainWikiRotatingCoin(chain: chain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                ChainWikiChainLogoBadge(chain: chain, size: 38)
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
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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

private struct ChainWikiRotatingCoin: View {
    let chain: ChainWikiEntry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGSize = .zero
    @State private var manualYaw: Double = 0
    @State private var manualPitch: Double = 0

    private let coinSize: CGFloat = 142

    var body: some View {
        Group {
            if reduceMotion {
                rotatingCoin(date: nil)
            } else {
                TimelineView(.animation) { context in
                    rotatingCoin(date: context.date)
                }
            }
        }
        .frame(height: 190)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    manualYaw += Double(value.translation.width) * 0.72
                    manualPitch = Self.clamped(manualPitch - Double(value.translation.height) * 0.18, -18, 18)
                    spectraHaptic(.light)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(chain.name) \(AppLocalization.string("Interactive coin"))"))
    }

    private func rotatingCoin(date: Date?) -> some View {
        let automaticYaw = date.map { $0.timeIntervalSinceReferenceDate * 38 } ?? 0
        let yaw = automaticYaw + manualYaw + Double(dragOffset.width) * 0.72
        let pitch = Self.clamped(manualPitch - Double(dragOffset.height) * 0.18, -22, 22)
        let pulse = date.map { 0.5 + 0.5 * sin($0.timeIntervalSinceReferenceDate * 2.1) } ?? 0.5
        let radians = yaw * .pi / 180
        let edgeStrength = abs(sin(radians))
        let faceLight = 0.5 + 0.5 * cos(radians)

        return ZStack {
            orbitRings(yaw: yaw, pulse: pulse)
            coinShadow(yaw: yaw)
            ridgedCoinEdge(yaw: yaw, pitch: pitch, edgeStrength: edgeStrength)
            coinFace(yaw: yaw, pulse: pulse, faceLight: faceLight)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
                .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
        }
        .frame(width: 232, height: 192)
    }

    private func orbitRings(yaw: Double, pulse: Double) -> some View {
        ZStack {
            Ellipse()
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            chain.accentColor.opacity(0.72),
                            .white.opacity(0.72),
                            .clear,
                            chain.accentColor.opacity(0.48),
                            .clear,
                        ],
                        center: .center,
                        angle: .degrees(yaw * 0.7)
                    ),
                    lineWidth: 1.4
                )
                .frame(width: 208, height: 74)
                .rotationEffect(.degrees(-11))

            Ellipse()
                .stroke(chain.accentColor.opacity(0.16 + pulse * 0.08), lineWidth: 1)
                .frame(width: 176, height: 138)
                .rotationEffect(.degrees(23))
        }
        .blur(radius: 0.1)
    }

    private func coinShadow(yaw: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.black.opacity(0.24), .black.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: 94
                )
            )
            .frame(width: 148, height: 30)
            .scaleEffect(x: CGFloat(0.78 + abs(cos(yaw * .pi / 180)) * 0.3), y: 1)
            .offset(y: 76)
            .blur(radius: 8)
    }

    private func ridgedCoinEdge(yaw: Double, pitch: Double, edgeStrength: Double) -> some View {
        let radians = yaw * .pi / 180
        let sideWidth = 16 + CGFloat(edgeStrength) * 46
        let offsetX = CGFloat(sin(radians)) * 15

        return ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            chain.accentColor.opacity(0.58),
                            .white.opacity(0.82),
                            chain.accentColor.opacity(0.84),
                            .black.opacity(0.34),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: sideWidth, height: coinSize * 1.03)

            ForEach(0..<24, id: \.self) { index in
                sideRidge(index: index, count: 24, width: sideWidth, edgeStrength: edgeStrength)
            }

            Capsule()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                .frame(width: sideWidth, height: coinSize * 1.03)
        }
        .offset(x: offsetX)
        .rotation3DEffect(.degrees(pitch * 0.34), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
        .opacity(0.2 + edgeStrength * 0.8)
        .shadow(color: chain.accentColor.opacity(0.26), radius: 18, y: 8)
    }

    private func sideRidge(index: Int, count: Int, width: CGFloat, edgeStrength: Double) -> some View {
        let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
        let x = -width / 2 + progress * width
        let centerDistance = abs(progress - 0.5) * 2
        let opacity = 0.26 + (1 - Double(centerDistance)) * 0.34 + edgeStrength * 0.26

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.72), chain.accentColor.opacity(0.34), .black.opacity(0.26)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1.5, height: coinSize * (0.82 + centerDistance * 0.12))
            .offset(x: x)
            .opacity(opacity)
    }

    private func coinFace(yaw: Double, pulse: Double, faceLight: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.92),
                            chain.accentColor.opacity(0.94),
                            chain.accentColor.opacity(0.5),
                            .white.opacity(0.76 + faceLight * 0.12),
                            chain.accentColor.opacity(0.86),
                            .white.opacity(0.92),
                        ],
                        center: .center,
                        angle: .degrees(yaw * 0.45)
                    )
                )

            coinRidgeRing()

            Circle()
                .strokeBorder(.white.opacity(0.72), lineWidth: 2.6)
                .padding(8)

            Circle()
                .strokeBorder(chain.accentColor.opacity(0.34), lineWidth: 9)
                .padding(16)

            ChainWikiStampedCoinLogo(chain: chain, size: 86)
                .compositingGroup()

            coinFaceGlare(yaw: yaw, pulse: pulse)

            Circle()
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .frame(width: coinSize, height: coinSize)
        .clipShape(Circle())
        .shadow(color: chain.accentColor.opacity(0.34), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 12)
    }

    private func coinRidgeRing() -> some View {
        ZStack {
            ForEach(0..<56, id: \.self) { index in
                rimRidge(index: index, count: 56)
            }
        }
        .frame(width: coinSize, height: coinSize)
    }

    private func rimRidge(index: Int, count: Int) -> some View {
        let angle = Double(index) * 360 / Double(count)
        return Capsule()
            .fill(index.isMultiple(of: 2) ? .white.opacity(0.66) : chain.accentColor.opacity(0.5))
            .frame(width: 1.4, height: 10)
            .offset(y: -coinSize / 2 + 8)
            .rotationEffect(.degrees(angle))
            .opacity(0.68)
    }

    private func coinFaceGlare(yaw: Double, pulse: Double) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [.clear, .white.opacity(0.42 + pulse * 0.16), .clear, .clear],
                    center: .center,
                    angle: .degrees(yaw * 0.32)
                )
            )
            .blendMode(.screen)
            .opacity(0.72)
            .padding(4)
    }

    private static func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}

private struct ChainWikiStampedCoinLogo: View {
    let chain: ChainWikiEntry
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.34),
                            chain.accentColor.opacity(0.2),
                            .black.opacity(0.18),
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: size * 0.68
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1.4)
                }

            ChainWikiChainLogoBadge(chain: chain, size: size * 0.68)
                .padding(size * 0.14)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.black.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
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
