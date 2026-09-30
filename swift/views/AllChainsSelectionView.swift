import SwiftUI

// Extracted from WalletSetupViews.swift to keep that file under control.
// Self-contained — takes its dependencies as bindings/closures and doesn't
// reach into AppState. New chain-selection variants (e.g. for receive
// flow) should follow this shape: descriptor list + selected set +
// toggle/clear callbacks.
struct AllChainsSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var chainSearchText: String
    let descriptors: [SetupChainSelectionDescriptor]
    let selectedChains: Set<Chain>
    let toggleSelection: (Chain) -> Void
    /// Absent when the caller picks one chain rather than a set: the running
    /// count and its "Clear all" belong to a multi-select and read as noise
    /// above a list where exactly one row is always ticked.
    let clearAllSelections: (() -> Void)?
    @State private var isShowingInfo = false
    private var trimmedQuery: String { chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }
    private var filteredDescriptors: [SetupChainSelectionDescriptor] {
        guard isSearching else { return descriptors }
        return descriptors.filter { d in
            d.title.localizedCaseInsensitiveContains(trimmedQuery)
                || d.symbol.localizedCaseInsensitiveContains(trimmedQuery)
                || d.chainName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    private var groupedDescriptors: [(SetupChainCategory, [SetupChainSelectionDescriptor])] {
        SetupChainCategory.allCases.compactMap { category in
            let entries = descriptors.filter { $0.category == category }
            return entries.isEmpty ? nil : (category, entries)
        }
    }
    @ViewBuilder
    private func row(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChains.contains(descriptor.id)
        Button {
            spectraHaptic(.light)
            toggleSelection(descriptor.id)
        } label: {
            HStack(spacing: SpectraLayout.Space.m) {
                ZStack(alignment: .bottomTrailing) {
                    CoinBadge(
                        artworkName: descriptor.artworkName, fallbackText: descriptor.symbol,
                        color: descriptor.color, size: 36
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(descriptor.color)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .light ? 1 : 0.85)))
                            .offset(x: 5, y: 5)
                    }
                }
                .frame(width: 40, height: 40)
                Text(descriptor.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: SpectraLayout.Space.s)
                Text(descriptor.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? descriptor.color : Color.secondary)
                    .padding(.horizontal, SpectraLayout.Space.s)
                    .padding(.vertical, SpectraLayout.Space.xs)
                    .background(
                        Capsule(style: .continuous).fill(
                            isSelected ? descriptor.color.opacity(0.14) : SpectraLayout.insetFill)
                    )
            }
            .spectraRowPadding()
        }
        .buttonStyle(.plain)
    }
    private func rowList(_ items: [SetupChainSelectionDescriptor]) -> some View {
        SpectraRowGroup(data: items) { descriptor in row(descriptor) }
    }
    @ViewBuilder
    private var searchAndCounter: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(AppLocalization.string("import_flow.search_chains"), text: $chainSearchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if isSearching {
                    Button { chainSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, SpectraLayout.Space.m).padding(.vertical, SpectraLayout.Space.m).spectraInputFieldStyle()
            if let clearAllSelections, !selectedChains.isEmpty {
                HStack(spacing: SpectraLayout.Space.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.caption)
                    Text(AppLocalization.format("%lld selected", selectedChains.count))
                        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Spacer()
                    Button(AppLocalization.string("Clear all"), role: .destructive) { clearAllSelections() }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
                }
                .padding(.horizontal, SpectraLayout.Space.m).padding(.vertical, SpectraLayout.Space.s)
                .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.10)))
            }
        }
    }
    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: SpectraLayout.Space.s) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.primary)
            Text("\(count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xxs)
                .background(SpectraLayout.insetFill, in: Capsule(style: .continuous))
            Spacer()
        }
        .padding(.top, SpectraLayout.Space.xs).padding(.bottom, SpectraLayout.Space.xxs)
    }
    @ViewBuilder
    private var bodyContent: some View {
        if isSearching {
            if filteredDescriptors.isEmpty {
                VStack(spacing: SpectraLayout.Space.s) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    Text(AppLocalization.string("import_flow.no_chains_match"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, SpectraLayout.Space.xl)
            } else {
                rowList(filteredDescriptors)
            }
        } else {
            VStack(alignment: .leading, spacing: SpectraLayout.Space.l) {
                ForEach(groupedDescriptors, id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
                        sectionHeader(category.sectionTitle, count: items.count)
                        rowList(items)
                    }
                }
            }
        }
    }
    @ViewBuilder
    private var gasTokenInfoSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.l) {
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
                        Label(AppLocalization.string("Gas Token"), systemImage: "fuelpump.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                        Text(
                            AppLocalization.string(
                                "The symbol shown on the right of each chain is its gas token — the asset you need to pay transaction fees."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(SpectraLayout.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SpectraLayout.Radius.inner, style: .continuous).fill(Color.accentColor.opacity(0.08))
                    )
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
                        Label(AppLocalization.string("L2s and Native Tokens"), systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                        Text(
                            AppLocalization.string(
                                "Some L2 chains have a separate native token (e.g. ARB, OP) but use a different asset for gas fees (e.g. ETH). Spectra shows the gas token since that's what you'll need to keep funded for transactions."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(SpectraLayout.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SpectraLayout.Radius.inner, style: .continuous).fill(Color.accentColor.opacity(0.08))
                    )
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
                        Label(AppLocalization.string("Missing a Chain?"), systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                        Text(
                            AppLocalization.string(
                                "If you'd like a chain added, go to Settings → Report a Problem and let the developer know. New chains are added regularly."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(SpectraLayout.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SpectraLayout.Radius.inner, style: .continuous).fill(Color.accentColor.opacity(0.08))
                    )
                }
                .padding(SpectraLayout.Space.l)
            }
            .navigationTitle(AppLocalization.string("Chain Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done")) { isShowingInfo = false }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                    searchAndCounter
                    bodyContent
                }.padding(SpectraLayout.Space.l)
            }
        }
        .navigationTitle(AppLocalization.string("import_flow.all_chains_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingInfo = true } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) { gasTokenInfoSheet }
    }
}
