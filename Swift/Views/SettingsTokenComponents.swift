import Foundation
import PhotosUI
import SwiftUI
func settingsTokenAssetIdentifier(for entry: TokenPreferenceEntry) -> String? {
    let chainSlug: String
    switch entry.chain {
    case .ethereum: chainSlug = "ethereum"
    case .arbitrum: chainSlug = "arbitrum"
    case .optimism: chainSlug = "optimism"
    case .bnb: chainSlug = "bnb"
    case .avalanche: chainSlug = "avalanche"
    case .hyperliquid: chainSlug = "hyperliquid"
    case .solana: chainSlug = "solana"
    case .sui: chainSlug = "sui"
    case .aptos: chainSlug = "aptos"
    case .ton: chainSlug = "ton"
    case .near: chainSlug = "near"
    case .tron: chainSlug = "tron"
    }
    let symbol = entry.symbol.lowercased()
    if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "\(chainSlug):\(entry.coinGeckoId.lowercased()):\(symbol)" }
    return "\(chainSlug):\(symbol)"
}
func settingsTokenFallbackMark(for entry: TokenPreferenceEntry) -> String {
    let compact = entry.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(compact.prefix(2)).uppercased()
}
func settingsTokenTint(for chain: TokenTrackingChain) -> Color {
    switch chain {
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
                assetIdentifier: settingsTokenAssetIdentifier(for: group.representativeEntry), fallbackText: settingsTokenFallbackMark(for: group.representativeEntry), color: settingsTokenTint(for: group.representativeEntry.chain), size: 30
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
                    settingsLocalizedString("Shown"), isOn: Binding(get: { entry.isEnabled }, set: setEnabled)
                ).labelsHidden()
            }
            settingsTokenDetailRow(title: settingsLocalizedString("Source"), value: entry.isBuiltIn ? settingsLocalizedString("Built-In") : settingsLocalizedString("Custom"))
            settingsTokenDetailRow(title: settingsLocalizedString("Supported Decimals"), value: "\(entry.decimals)")
            VStack(alignment: .leading, spacing: 6) {
                Text(settingsLocalizedString("Contract / Mint")).font(.caption).foregroundStyle(.secondary)
                Text(entry.contractAddress).font(.caption.monospaced()).textSelection(.enabled)
            }
            if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { settingsTokenDetailRow(title: settingsLocalizedString("CoinGecko ID"), value: entry.coinGeckoId) }
            if !entry.marketDataId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.marketDataId != "0" { settingsTokenDetailRow(title: settingsLocalizedString("Market Data ID"), value: entry.marketDataId) }
            if !entry.isBuiltIn {
                Stepper(
                    settingsLocalizedFormat("Supports: %lld decimals", Int(entry.decimals)), value: Binding(get: { Int(entry.decimals) }, set: updateDecimals), in: 0 ... 30, step: 1
                )
                Button(role: .destructive, action: removeToken) {
                    Label(settingsLocalizedString("Remove Token"), systemImage: "trash")
                }}}.padding(.vertical, 4)
    }
}
struct TokenIconSetting: Identifiable {
    let title: String
    let symbol: String
    let assetIdentifier: String
    let mark: String
    let color: Color
    var id: String { assetIdentifier }
}
struct TokenIconCustomizationRow: View {
    let setting: TokenIconSetting
    @AppStorage(TokenIconPreferenceStore.defaultsKey) private var tokenIconPreferencesStorage = ""
    @AppStorage(TokenIconPreferenceStore.customImageRevisionDefaultsKey) private var tokenIconCustomImageRevision = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    @State private var photoImportError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CoinBadge(assetIdentifier: setting.assetIdentifier, fallbackText: setting.mark, color: setting.color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.title)
                    Text(setting.symbol).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker(setting.title, selection: styleBinding) {
                ForEach(TokenIconStyle.allCases) { style in Text(style.title).tag(style) }}.pickerStyle(.segmented).labelsHidden()
            if selectedStyle == .customPhoto || hasCustomPhoto {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(hasCustomPhoto ? settingsLocalizedString("Replace Photo") : settingsLocalizedString("Choose Photo"), systemImage: "photo")
                    }
                    if hasCustomPhoto {
                        Button(settingsLocalizedString("Remove Photo"), role: .destructive) {
                            TokenIconImageStore.removeImage(for: setting.assetIdentifier)
                            tokenIconCustomImageRevision += 1
                            if selectedStyle == .customPhoto { selectedStyle = .artwork }}}
                    if isImportingPhoto {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                    }}.font(.caption.weight(.semibold))
                if !hasCustomPhoto { Text(settingsLocalizedString("Select a photo from your library to use as this token icon.")).font(.caption).foregroundStyle(.secondary) }}
            if let photoImportError { Text(photoImportError).font(.caption).foregroundStyle(.red) }}.padding(.vertical, 4).task(id: selectedPhotoItem) {
            await importSelectedPhotoIfNeeded()
        }}
    private var styleBinding: Binding<TokenIconStyle> {
        Binding(
            get: { selectedStyle }, set: { newValue in selectedStyle = newValue }
        )
    }
    private var selectedStyle: TokenIconStyle {
        get {
            TokenIconPreferenceStore.preference(for: setting.assetIdentifier, storage: tokenIconPreferencesStorage)
        }
        nonmutating set {
            tokenIconPreferencesStorage = TokenIconPreferenceStore.updatePreference(
                newValue, for: setting.assetIdentifier, storage: tokenIconPreferencesStorage
            )
        }}
    private var hasCustomPhoto: Bool {
        _ = tokenIconCustomImageRevision
        return TokenIconImageStore.hasCustomImage(for: setting.assetIdentifier)
    }
    @MainActor
    private func importSelectedPhotoIfNeeded() async {
        guard let selectedPhotoItem else { return }
        isImportingPhoto = true
        photoImportError = nil
        do {
            guard let imageData = try await selectedPhotoItem.loadTransferable(type: Data.self) else { throw TokenIconImageStore.IconError.unreadableImage }
            try TokenIconImageStore.saveImageData(imageData, for: setting.assetIdentifier)
            tokenIconCustomImageRevision += 1
            self.selectedStyle = .customPhoto
        } catch {
            photoImportError = (error as? LocalizedError)?.errorDescription ?? settingsLocalizedString("The selected photo could not be imported.")
        }
        isImportingPhoto = false
        self.selectedPhotoItem = nil
    }
}
private func settingsTokenDetailRow(title: String, value: String) -> some View {
    HStack {
        Text(title).foregroundStyle(.secondary)
        Spacer()
        Text(value).multilineTextAlignment(.trailing)
    }
}
private func settingsLocalizedString(_ key: String) -> String {
    AppLocalization.string(key)
}
private func settingsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
