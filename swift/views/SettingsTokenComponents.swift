import Foundation
import SwiftUI
extension TokenTrackingChain {
    var settingsIconSlug: String {
        switch self {
        case .ethereum: return "ethereum"
        case .arbitrum: return "arbitrum"
        case .optimism: return "optimism"
        case .bnb: return "bnb"
        case .avalanche: return "avalanche"
        case .hyperliquid: return "hyperliquid"
        case .solana: return "solana"
        case .sui: return "sui"
        case .aptos: return "aptos"
        case .ton: return "ton"
        case .near: return "near"
        case .tron: return "tron"
        }
    }
    var settingsIconTint: Color {
        switch self {
        case .ethereum: return .blue
        case .arbitrum: return .cyan
        case .optimism: return .red
        case .bnb: return .yellow
        case .avalanche: return .red
        case .hyperliquid: return .mint
        case .solana: return .purple
        case .sui: return .mint
        case .aptos: return .cyan
        case .ton: return .blue
        case .near: return .indigo
        case .tron: return .red
        }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.chain.rawValue).font(.subheadline.weight(.semibold))
                    Text(entry.tokenStandard).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    AppLocalization.string("Shown"), isOn: Binding(get: { entry.isEnabled }, set: setEnabled)
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
                    value: Binding(get: { Int(entry.decimals) }, set: updateDecimals), in: 0...30, step: 1
                )
                Button(role: .destructive, action: removeToken) {
                    Label(AppLocalization.string("Remove Token"), systemImage: "trash")
                }
            }
        }.padding(.vertical, 4)
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
