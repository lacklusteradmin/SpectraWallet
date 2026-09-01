import Foundation
import SwiftUI
extension TokenHostingChain {
    /// The icon slug is the chain's registry id.
    var settingsIconSlug: String { chain?.id ?? "" }

    /// The chain's colour, from the catalog.
    var settingsIconTint: Color {
        chain.flatMap { ChainRegistryEntry.entry(id: $0.id)?.color } ?? .accentColor
    }
}
extension TokenPreferenceEntry {
    var settingsAssetIdentifier: String {
        let slug = chain.settingsIconSlug
        let lowerSymbol = symbol.lowercased()
        let trimmedGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGeckoId.isEmpty {
            return "\(slug):\(trimmedGeckoId.lowercased()):\(lowerSymbol)"
        }
        return "\(slug):\(lowerSymbol)"
    }
    var settingsFallbackMark: String {
        String(symbol.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
    }
}
struct TokenRegistryGroup: Identifiable {
    let key: String
    let name: String
    let symbol: String
    let entries: [TokenPreferenceEntry]
    var id: String { key }
    var representativeEntry: TokenPreferenceEntry { entries[0] }
    var allEntryIDs: [String] { entries.map(\.id) }
    var isEnabled: Bool { entries.contains(where: \.isEnabled) }
}
struct TokenRegistryGroupRowView: View {
    let group: TokenRegistryGroup
    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(
                assetIdentifier: group.representativeEntry.settingsAssetIdentifier,
                fallbackText: group.representativeEntry.settingsFallbackMark,
                color: group.representativeEntry.chain.settingsIconTint, size: 30
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(group.symbol).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }.padding(.vertical, 2)
    }
}
struct TokenRegistryEntryCardView: View {
    let entry: TokenPreferenceEntry
    let setEnabled: (Bool) -> Void
    let updateDecimals: (Int) -> Void
    let removeToken: () -> Void
    @State private var isShowingRemoveConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.chain.rawValue).font(.subheadline.weight(.semibold))
                    Text(entry.tokenStandard).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    AppLocalization.string("Shown"), isOn: Binding(get: { entry.isEnabled }, set: { v in setEnabled(v) })
                ).labelsHidden()
            }
            SettingsTokenDetailRow(
                title: AppLocalization.string("Source"),
                value: entry.isBuiltIn ? AppLocalization.string("Built-In") : AppLocalization.string("Custom"))
            SettingsTokenDetailRow(title: AppLocalization.string("Supported Decimals"), value: "\(entry.decimals)")
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("Contract / Mint")).font(.caption).foregroundStyle(.secondary)
                Text(entry.contractAddress).font(.caption.monospaced()).textSelection(.enabled)
            }
            if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsTokenDetailRow(title: AppLocalization.string("CoinGecko ID"), value: entry.coinGeckoId)
            }
            if !entry.isBuiltIn {
                Stepper(
                    AppLocalization.format("Supports: %lld decimals", Int(entry.decimals)),
                    value: Binding(get: { Int(entry.decimals) }, set: { v in updateDecimals(v) }), in: 0...30, step: 1
                )
                Button(role: .destructive) {
                    isShowingRemoveConfirmation = true
                } label: {
                    Label(AppLocalization.string("Remove Token"), systemImage: "trash")
                }
            }
        }.padding(.vertical, 4)
        .confirmationDialog(
            AppLocalization.string("Remove Token"),
            isPresented: $isShowingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Remove"), role: .destructive) {
                spectraHaptic(.medium)
                removeToken()
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("This custom token will be removed and will no longer appear in your portfolio."))
        }
    }
}
private struct SettingsTokenDetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
