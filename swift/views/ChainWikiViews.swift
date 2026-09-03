import SwiftUI

/// A chain's own page, one level down from the coin that runs on it.
///
/// The wiki is indexed by coin — see `CryptoWikiViews.swift`. This is what has
/// no coin to belong to: ten chains share ETH, so "Base is an optimistic
/// rollup" cannot live on ETH's page. Reached from a coin's lives-on rows.

struct ChainWikiDetailView: View {
    let chain: ChainWikiEntry
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                wikiHeroCard
                wikiIdentityCard
                wikiDerivationCard
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(chain.name).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var wikiHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WikiRotatingCoin(face: chain.face)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                WikiCoinBadge(face: chain.face, size: 38)
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
                            Text(tag).font(.caption.weight(.semibold)).foregroundStyle(chain.face.color)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(chain.face.color.opacity(0.14), in: Capsule())
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
            if chain.derivationPath.isEmpty {
                Text(AppLocalization.string("Not user-configurable in Spectra's current UI."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
            } else {
                ForEach(chain.derivationPath) { path in
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
                    }
                    .padding(.leading, 32)
                }
            }
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

extension ChainWikiEntry {
    var registryEntry: ChainRegistryEntry? { ChainRegistryEntry.entry(id: id) }
    /// A chain draws the coin it runs on, which is what the badge already was.
    var face: WikiCoinFace {
        WikiCoinFace(
            name: name, symbol: symbol,
            assetIdentifier: registryEntry?.assetIdentifier,
            color: registryEntry?.color ?? .accentColor)
    }
}
