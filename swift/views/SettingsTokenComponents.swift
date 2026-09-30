import Foundation
import SwiftUI

extension Chain {
    var settingsIconTint: Color { entry?.color.color ?? .accentColor }
}
extension TokenPreferenceEntry {
    var settingsArtworkName: String { AssetPresentationCatalog.artwork(deploymentId: token.deploymentId) }
    var settingsFallbackMark: String {
        String(token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
    }
}
struct TokenRegistryGroup: Identifiable {
    let key: String
    let name: String
    let symbol: String
    let entries: [TokenPreferenceEntry]
    var id: String { key }
    var representativeEntry: TokenPreferenceEntry { entries[0] }
}
struct TokenRegistryGroupRowView: View {
    let group: TokenRegistryGroup
    var body: some View {
        HStack(spacing: SpectraLayout.Space.m) {
            CoinBadge(
                artworkName: group.representativeEntry.settingsArtworkName,
                fallbackText: group.representativeEntry.settingsFallbackMark,
                color: group.representativeEntry.hostingChain?.settingsIconTint ?? .accentColor, size: 36)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                Text(group.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(group.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(group.entries.map { $0.token.chainId.displayName }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: SpectraLayout.Space.s)
            if !group.representativeEntry.isBuiltIn {
                Text(AppLocalization.string("Custom")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, SpectraLayout.Space.xs)
    }
}
struct TokenRegistryEntryCardView: View {
    let entry: TokenPreferenceEntry
    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            Text(entry.token.chainId.displayName)
                .font(.headline)
            LabeledContent(AppLocalization.string("Token Standard"), value: entry.token.tokenStandard)
            LabeledContent(AppLocalization.string("Supported Decimals"), value: "\(entry.token.decimals)")
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                Text(AppLocalization.string("Token Identifier")).foregroundStyle(.secondary)
                Text(entry.token.contract).font(.caption.monospaced()).textSelection(.enabled)
            }
        }.padding(.vertical, SpectraLayout.Space.xs)
    }
}
