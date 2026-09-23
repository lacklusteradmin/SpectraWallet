import Foundation
import SwiftUI

extension TokenHostingChain {
    var settingsIconTint: Color { chain?.entry?.color.color ?? .accentColor }
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
        HStack(spacing: 12) {
            CoinBadge(
                artworkName: group.representativeEntry.settingsArtworkName,
                fallbackText: group.representativeEntry.settingsFallbackMark,
                color: group.representativeEntry.hostingChain?.settingsIconTint ?? .accentColor, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(group.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(group.entries.map { Chain(id: $0.token.chainId)?.displayName ?? $0.token.chainId }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if !group.representativeEntry.isBuiltIn {
                Text(AppLocalization.string("Custom")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
struct TokenRegistryEntryCardView: View {
    let entry: TokenPreferenceEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Chain(id: entry.token.chainId)?.displayName ?? entry.token.chainId)
                .font(.headline)
            LabeledContent(AppLocalization.string("Token Standard"), value: entry.token.tokenStandard)
            LabeledContent(AppLocalization.string("Supported Decimals"), value: "\(entry.token.decimals)")
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("Token Identifier")).foregroundStyle(.secondary)
                Text(entry.token.contract).font(.caption.monospaced()).textSelection(.enabled)
            }
        }.padding(.vertical, 4)
    }
}
