import SwiftUI

/// Everywhere a coin lives: a chain, a token standard, and either a contract
/// or nothing because it is native there.
///
/// One card, two callers. The wiki and the held-asset detail page each used to
/// render half of this: the wiki had the prose and no contracts, the dashboard
/// detail had the contracts and no prose, and it was reachable only for coins
/// the user already held.
///
/// The contract is the useful half. A holder given an address for "USDC on
/// Arbitrum" has one string to compare it against, and it is the one string a
/// deployer cannot forge — the same reason an unvouched holding is shown by
/// contract rather than by a symbol nobody vouches for.
struct AssetPlacesCard: View {
    let places: [AssetWikiPlace]
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Lives On")).font(.headline).foregroundStyle(Color.primary)
                Spacer()
                if places.count > 1 {
                    Text("\(places.count)").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.14)))
                }
            }
            if places.isEmpty {
                Text(AppLocalization.string("No chains are listed for this asset."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    // A chain still has a page — for consensus, state model
                    // and derivation paths, which have no coin to belong to.
                    // It is one level down from the coin now, reached here.
                    if let chain = CachedCoreHelpers.chainWikiEntry(id: place.chainId) {
                        NavigationLink { ChainWikiDetailView(chain: chain) } label: { row(place) }
                            .buttonStyle(.plain)
                    } else {
                        row(place)
                    }
                    if index < places.count - 1 { Divider().opacity(0.3) }
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func row(_ place: AssetWikiPlace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(place.chainName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
                Text(place.tokenStandard).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.12)))
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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(symbol) on \(place.chainName)")
    }
}
