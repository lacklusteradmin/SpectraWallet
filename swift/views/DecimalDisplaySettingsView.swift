import Foundation
import SwiftUI
struct DecimalDisplaySettingsView: View {
    let store: AppState
    @State private var searchText: String = ""
    private let decimalExamples: [(symbol: String, chainName: String)] = [
        ("BTC", "Bitcoin"), ("BCH", "Bitcoin Cash"), ("LTC", "Litecoin"), ("DOGE", "Dogecoin"), ("ETH", "Ethereum"),
        ("ETC", "Ethereum Classic"), ("BNB", "BNB Chain"), ("AVAX", "Avalanche"), ("HYPE", "Hyperliquid"), ("SOL", "Solana"),
        ("ADA", "Cardano"), ("XRP", "XRP Ledger"), ("TRX", "Tron"), ("XMR", "Monero"), ("SUI", "Sui"), ("APT", "Aptos"), ("TON", "TON"),
        ("ICP", "Internet Computer"), ("NEAR", "NEAR"), ("DOT", "Polkadot"), ("XLM", "Stellar"),
    ]
    var body: some View {
        Form {
            Section(AppLocalization.string("Native Asset Display")) {
                Text(
                    AppLocalization.string(
                        "Adjust how many decimals are shown for each chain's native asset. Very small values switch to a threshold marker instead of rounding to zero."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                Button(AppLocalization.string("Reset Native Asset Display")) {
                    store.resetNativeAssetDisplayDecimals()
                }
                if filteredDecimalExamples.isEmpty {
                    Text(AppLocalization.string("No matching native assets.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredDecimalExamples, id: \.symbol) { example in
                        let currentDisplayDecimals = store.assetDisplayDecimalPlaces(for: example.chainName)
                        let supportedDecimals = store.supportedAssetDecimals(symbol: example.symbol, chainName: example.chainName)
                        decimalStepperCard(
                            assetIdentifier: Coin.iconIdentifier(symbol: example.symbol, chainName: example.chainName),
                            fallbackText: example.symbol, tint: Coin.displayColor(for: example.symbol),
                            title: example.chainName, subtitle: example.symbol, currentDisplayDecimals: currentDisplayDecimals,
                            supportedDecimals: supportedDecimals, supportedLabel: AppLocalization.string("Asset supports"),
                            onDecrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals - 1, for: example.chainName)
                            },
                            onIncrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals + 1, for: example.chainName)
                            }
                        )
                    }
                }
            }
            Section(AppLocalization.string("Tracked Token Decimals")) {
                Text(
                    AppLocalization.string(
                        "ERC-20 and TRC-20 tokens expose decimals on the contract, and Solana tokens store decimals on the mint account. Manage tracked token decimal support separately from native asset display precision."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                Button(AppLocalization.string("Reset Tracked Token Display")) {
                    store.resetTrackedTokenDisplayDecimals()
                }
                if filteredTokenDecimalEntries.isEmpty {
                    Text(
                        store.enabledTrackedTokenPreferences.isEmpty
                            ? AppLocalization.string("No tokens are currently enabled for tracking.")
                            : AppLocalization.string("No matching tracked tokens.")
                    ).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTokenDecimalEntries, id: \.id) { entry in
                        let currentDisplayDecimals = store.displayAssetDecimals(symbol: entry.symbol, chainName: entry.chain.rawValue)
                        let supportedDecimals = Int(entry.decimals)
                        decimalStepperCard(
                            assetIdentifier: decimalTokenAssetIdentifier(for: entry),
                            fallbackText: String(entry.symbol.prefix(2)).uppercased(), tint: decimalTokenTint(for: entry.chain),
                            title: entry.name, subtitle: "\(entry.chain.rawValue) · \(entry.symbol)",
                            currentDisplayDecimals: currentDisplayDecimals, supportedDecimals: supportedDecimals,
                            supportedLabel: AppLocalization.string("Token supports"), detailText: entry.contractAddress,
                            onDecrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals - 1)
                            },
                            onIncrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals + 1)
                            }
                        )
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Decimal Display"))
            .searchable(text: $searchText, prompt: AppLocalization.string("Search symbol, name, chain, or address"))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    private var filteredDecimalExamples: [(symbol: String, chainName: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return decimalExamples }
        return decimalExamples.filter { example in [example.symbol, example.chainName].joined(separator: " ").lowercased().contains(query) }
    }
    private var filteredTokenDecimalEntries: [TokenPreferenceEntry] {
        let entries = store.enabledTrackedTokenPreferences.sorted { lhs, rhs in
            if lhs.chain.rawValue != rhs.chain.rawValue { return lhs.chain.rawValue < rhs.chain.rawValue }
            return lhs.symbol < rhs.symbol
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            [
                entry.symbol, entry.name, entry.chain.rawValue, entry.contractAddress, entry.coinGeckoId,
            ].joined(separator: " ").lowercased().contains(query)
        }
    }
    @ViewBuilder
    private func decimalStepperCard(
        assetIdentifier: String?, fallbackText: String, tint: Color, title: String, subtitle: String, currentDisplayDecimals: Int,
        supportedDecimals: Int, supportedLabel: String, detailText: String? = nil, onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CoinBadge(assetIdentifier: assetIdentifier, fallbackText: fallbackText, color: tint, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(detailText).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals <= 0)
                    Text("\(currentDisplayDecimals)").font(.subheadline.monospacedDigit()).frame(minWidth: 30)
                    Button(action: onIncrease) {
                        Image(systemName: "plus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals >= supportedDecimals)
                }.font(.title3)
            }
            HStack {
                Text(supportedLabel)
                Spacer()
                Text(AppLocalization.format("%lld decimals", supportedDecimals)).foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(.vertical, 4)
    }
    private func decimalTokenAssetIdentifier(for entry: TokenPreferenceEntry) -> String? {
        let slug = entry.chain.slug
        let symbol = entry.symbol.lowercased()
        if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(slug):\(entry.coinGeckoId.lowercased()):\(symbol)"
        }
        return "\(slug):\(symbol)"
    }
    private func decimalTokenTint(for chain: TokenTrackingChain) -> Color {
        switch chain {
        case .ethereum, .ton: return .blue
        case .arbitrum, .aptos: return .cyan
        case .optimism, .avalanche, .tron: return .red
        case .bnb: return .yellow
        case .hyperliquid, .sui: return .mint
        case .solana, .polygon: return .purple
        case .base, .linea: return .blue
        case .scroll: return .orange
        case .blast: return .yellow
        case .mantle: return .green
        case .near: return .indigo
        }
    }
}
