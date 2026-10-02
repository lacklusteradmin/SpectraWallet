import SwiftUI

/// Where a coin lives: chain, token standard, and contract (absent for native coins).
/// Shown on a held asset's Details page. Show contracts so users can verify
/// asset identity independently of the ticker.
struct AssetPlacesCard: View {
    let places: [AssetWikiPlace]
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack(spacing: SpectraLayout.Space.s) {
                Text(AppLocalization.string("Lives On")).font(.headline).foregroundStyle(Color.primary)
                Spacer()
                if places.count > 1 {
                    Text("\(places.count)").font(.caption.weight(.bold)).foregroundStyle(.tint)
                        .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xxs)
                        .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.14)))
                }
            }
            if places.isEmpty {
                Text(AppLocalization.string("No chains are listed for this asset."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    // A chain still has a page — for consensus and state
                    // model, which have no coin to belong to.
                    // It is one level down from the coin now, reached here.
                    if let chain = CoreReferenceTables.chainWikiEntry(id: place.chainId.id) {
                        NavigationLink { ChainWikiDetailView(chain: chain) } label: { row(place) }
                            .buttonStyle(.plain)
                    } else {
                        row(place)
                    }
                    if index < places.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
        .padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    @ViewBuilder
    private func row(_ place: AssetWikiPlace) -> some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
            HStack(spacing: SpectraLayout.Space.s) {
                Text(place.chainName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
                Text(place.tokenStandard).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xxs)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if place.contract.isEmpty {
                // Native here, so there is no contract — saying so is the
                // honest answer and it is what distinguishes the two kinds of
                // place without a second flag that could disagree.
                Text(AppLocalization.format("wiki.place.nativeTo", place.chainName))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(place.contract).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
        }
        .padding(.vertical, SpectraLayout.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.format("%@ on %@", symbol, place.chainName))
    }
}
