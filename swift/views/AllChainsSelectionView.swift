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
    let selectedChainNames: Set<String>
    let toggleSelection: (String) -> Void
    let clearAllSelections: () -> Void
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
        let isSelected = selectedChainNames.contains(descriptor.chainName)
        Button {
            spectraHaptic(.light)
            toggleSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    CoinBadge(
                        assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol,
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
                Spacer(minLength: 8)
                Text(descriptor.gasTokenSymbol.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? descriptor.color : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous).fill(
                            isSelected ? descriptor.color.opacity(0.14) : Color.primary.opacity(0.07))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    @ViewBuilder
    private func rowList(_ items: [SetupChainSelectionDescriptor]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, descriptor in
                row(descriptor)
                if index < items.count - 1 {
                    Divider().padding(.leading, 66)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .light ? 0.55 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    @ViewBuilder
    private var searchAndCounter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(AppLocalization.string("import_flow.search_chains"), text: $chainSearchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if isSearching {
                    Button { chainSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14).padding(.vertical, 12).spectraInputFieldStyle()
            if !selectedChainNames.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange).font(.caption)
                    Text(AppLocalization.format("%lld selected", selectedChainNames.count))
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Spacer()
                    Button(AppLocalization.string("Clear all"), role: .destructive) { clearAllSelections() }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.10)))
            }
        }
    }
    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.primary)
            Text("\(count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
            Spacer()
        }
        .padding(.top, 4).padding(.bottom, 2)
    }
    @ViewBuilder
    private var bodyContent: some View {
        if isSearching {
            if filteredDescriptors.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    Text(AppLocalization.string("import_flow.no_chains_match"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                rowList(filteredDescriptors)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groupedDescriptors, id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(AppLocalization.string("Gas Token"), systemImage: "fuelpump.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(
                            AppLocalization.string(
                                "The symbol shown on the right of each chain is its gas token — the asset you need to pay transaction fees."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.08))
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        Label(AppLocalization.string("L2s and Native Tokens"), systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(
                            AppLocalization.string(
                                "Some L2 chains have a separate native token (e.g. ARB, OP) but use a different asset for gas fees (e.g. ETH). Spectra shows the gas token since that's what you'll need to keep funded for transactions."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.blue.opacity(0.08))
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        Label(AppLocalization.string("Missing a Chain?"), systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)
                        Text(
                            AppLocalization.string(
                                "If you'd like a chain added, go to Settings → Report a Problem and let the developer know. New chains are added regularly."
                            )
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.purple.opacity(0.08))
                    )
                }
                .padding(20)
            }
            .navigationTitle(AppLocalization.string("Chain Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done")) { isShowingInfo = false }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        }
    }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    searchAndCounter
                    bodyContent
                }.padding(20)
            }
        }
        .navigationTitle(AppLocalization.string("import_flow.all_chains_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingInfo = true } label: {
                    Image(systemName: "info.circle")
                }
                .tint(.orange)
            }
        }
        .sheet(isPresented: $isShowingInfo) { gasTokenInfoSheet }
    }
}
