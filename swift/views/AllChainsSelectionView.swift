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
    private let gridColumns = [
        GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
    ]
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
    private func chip(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNames.contains(descriptor.chainName)
        Button {
            toggleSelection(descriptor.chainName)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    CoinBadge(
                        assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol, color: descriptor.color, size: 36
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").font(.caption.weight(.bold)).foregroundStyle(descriptor.color).background(
                            Circle().fill(Color.white.opacity(colorScheme == .light ? 1 : 0.85))
                        ).offset(x: 4, y: -4)
                    }
                }
                Text(descriptor.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(descriptor.symbol.uppercased()).font(.caption2.weight(.medium)).foregroundStyle(
                    isSelected ? descriptor.color : Color.primary.opacity(0.55)
                ).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 88).padding(.vertical, 10).padding(.horizontal, 6).background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
                    isSelected ? descriptor.color.opacity(0.14) : Color.white.opacity(colorScheme == .light ? 0.55 : 0.04))
            ).overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
                    isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(colorScheme == .light ? 0.10 : 0.07),
                    lineWidth: isSelected ? 1.5 : 1)
            )
        }.buttonStyle(.plain).contentShape(Rectangle())
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
                    Text(AppLocalization.format("%lld selected", selectedChainNames.count)).font(.caption.weight(.semibold)).foregroundStyle(
                        .orange)
                    Spacer()
                    Button(AppLocalization.string("Clear all"), role: .destructive) { clearAllSelections() }.font(
                        .caption.weight(.semibold)
                    ).buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
                }.padding(.horizontal, 12).padding(.vertical, 8).background(
                    Capsule(style: .continuous).fill(Color.orange.opacity(0.10))
                )
            }
        }
    }
    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.primary)
            Text("\(count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(
                .vertical, 2
            ).background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
            Spacer()
        }.padding(.top, 6).padding(.bottom, 2)
    }
    @ViewBuilder
    private var bodyContent: some View {
        if isSearching {
            if filteredDescriptors.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    Text(AppLocalization.string("import_flow.no_chains_match")).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(filteredDescriptors) { descriptor in chip(descriptor) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedDescriptors, id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(category.sectionTitle, count: items.count)
                        LazyVGrid(columns: gridColumns, spacing: 8) {
                            ForEach(items) { descriptor in chip(descriptor) }
                        }
                    }
                }
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    searchAndCounter
                    bodyContent
                }.padding(20)
            }.navigationTitle(AppLocalization.string("import_flow.all_chains_title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("import_flow.done")) { dismiss() }.buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        }
    }
}
