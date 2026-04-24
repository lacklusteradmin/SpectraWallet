import Foundation
import SwiftUI
private enum LocalizationCatalogReferenceKeeper {
    static let strings: [String] = []
}
enum StaticContentCatalog {
    private final class BundleMarker {}
    // Memoize decoded resources across the app. `XxxContentCopy.current` is
    // accessed from inside view bodies (hot path) and each lookup used to hit
    // Rust FFI + JSON decode. Keyed by `(localeSignature, baseName, typeID)`
    // so a language switch invalidates automatically on the next read.
    private static var decodedResourceCache: [String: Any] = [:]
    private static func cacheKey(baseName: String, typeID: String) -> String {
        let signature = AppLocalization.preferredLocalizationIdentifiers().joined(separator: ",")
        return "\(signature)|\(baseName)|\(typeID)"
    }
    static func loadRequiredResource<T: Decodable>(_ baseName: String, as type: T.Type) -> T {
        let key = cacheKey(baseName: baseName, typeID: String(describing: type))
        if let cached = decodedResourceCache[key] as? T { return cached }
        let value: T = loadRequiredResourceUncached(baseName, as: type)
        decodedResourceCache[key] = value
        return value
    }
    static func loadResource<T: Decodable>(_ baseName: String, as type: T.Type) -> T? {
        let key = cacheKey(baseName: baseName, typeID: String(describing: type))
        if let cached = decodedResourceCache[key] as? T { return cached }
        guard let value: T = loadResourceUncached(baseName, as: type) else { return nil }
        decodedResourceCache[key] = value
        return value
    }
    private static func loadRequiredResourceUncached<T: Decodable>(_ baseName: String, as type: T.Type) -> T {
        if let value: T = loadFromRustCore(baseName) { return value }
        let decoder = JSONDecoder()
        let localeIdentifiers = AppLocalization.preferredLocalizationIdentifiers()
        for url in candidateJSONURLs(for: baseName, localeIdentifiers: localeIdentifiers) {
            guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(T.self, from: data) else { continue }
            return value
        }
        fatalError("Missing required resource: \(baseName).json")
    }
    private static func loadResourceUncached<T: Decodable>(_ baseName: String, as type: T.Type) -> T? {
        if let value: T = loadFromRustCore(baseName) { return value }
        let decoder = JSONDecoder()
        let localeIdentifiers = AppLocalization.preferredLocalizationIdentifiers()
        for url in candidateJSONURLs(for: baseName, localeIdentifiers: localeIdentifiers) {
            guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(T.self, from: data) else { continue }
            return value
        }
        return nil
    }
    private static func loadFromRustCore<T: Decodable>(_ baseName: String) -> T? {
        guard let bytes = try? coreStaticResourceJson(resourceName: baseName) else { return nil }
        return try? JSONDecoder().decode(T.self, from: bytes)
    }
    private static func candidateJSONURLs(for baseName: String, localeIdentifiers: [String]) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()
        func append(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            candidates.append(url)
        }
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            for localeIdentifier in localeIdentifiers {
                if localeIdentifier == "Base" {
                    append(resourceURL.appendingPathComponent("\(baseName).json", isDirectory: false))
                    append(
                        resourceURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(
                            "strings", isDirectory: true
                        ).appendingPathComponent("base", isDirectory: true).appendingPathComponent("\(baseName).json", isDirectory: false))
                    append(
                        resourceURL.appendingPathComponent("strings", isDirectory: true).appendingPathComponent("base", isDirectory: true)
                            .appendingPathComponent("\(baseName).json", isDirectory: false))
                } else {
                    append(resourceURL.appendingPathComponent("\(baseName).\(localeIdentifier).json", isDirectory: false))
                    append(
                        resourceURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(
                            "strings", isDirectory: true
                        ).appendingPathComponent(localeIdentifier, isDirectory: true).appendingPathComponent(
                            "\(baseName).\(localeIdentifier).json", isDirectory: false))
                    append(
                        resourceURL.appendingPathComponent("strings", isDirectory: true).appendingPathComponent(
                            localeIdentifier, isDirectory: true
                        ).appendingPathComponent("\(baseName).\(localeIdentifier).json", isDirectory: false))
                }
            }
            append(resourceURL.appendingPathComponent("\(baseName).json", isDirectory: false))
            append(
                resourceURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("strings", isDirectory: true)
                    .appendingPathComponent("base", isDirectory: true).appendingPathComponent("\(baseName).json", isDirectory: false))
            append(
                resourceURL.appendingPathComponent("strings", isDirectory: true).appendingPathComponent("base", isDirectory: true)
                    .appendingPathComponent("\(baseName).json", isDirectory: false))
        }
        return candidates
    }
    private static let candidateBundles: [Bundle] = {
        var seen = Set<URL>()
        return ([Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            guard let bundleURL = bundle.bundleURL.standardizedFileURL as URL? else { return false }
            return seen.insert(bundleURL).inserted
        }
    }()
}
struct SettingsContentCopy: Decodable {
    let pricingIntro: String
    let fiatRateProviderNote: String
    let publicProviderNote: String
    let aboutTitle: String
    let aboutSubtitle: String
    let aboutEthosTitle: String
    let aboutEthosLines: [String]
    let aboutNarrativeTitle: String
    let aboutNarrativeParagraphs: [String]
    let reportProblemDescription: String
    let reportProblemActionTitle: String
    let buyProvidersIntro: String
    let buyWarning: String
    static var current: SettingsContentCopy { StaticContentCatalog.loadRequiredResource("SettingsContent", as: SettingsContentCopy.self) }
}
struct DiagnosticsContentCopy: Decodable {
    let navigationTitle: String
    let searchPrompt: String
    let chainsSectionTitle: String
    let crossChainSectionTitle: String
    let actionsSectionTitle: String
    let statusSectionTitle: String
    let historyNotRunYet: String
    let walletDiagnosticsCoveredFormat: String
    let mostUsedHistorySourceFormat: String
    let lastHistoryRunFormat: String
    let lastEndpointCheckFormat: String
    let endpointHealthFormat: String
    let noHistoryTelemetryYet: String
    let noEndpointChecksYet: String
    let bitcoinEsploraHint: String
    let ethereumRPCNote: String
    let etherscanNote: String
    let moneroBackendNote: String
    let moneroAPIKeyNote: String
    let historySourcesSectionTitleFormat: String
    let endpointReachabilitySectionTitleFormat: String
    let degradedLastGoodSyncFormat: String
    let degradedNoPriorSuccessfulSyncYet: String
    static var current: DiagnosticsContentCopy {
        StaticContentCatalog.loadRequiredResource("DiagnosticsContent", as: DiagnosticsContentCopy.self)
    }
}
struct ImportFlowContent: Decodable {
    let backupVerificationTitle: String
    let advancedTitle: String
    let watchAddressesTitle: String
    let recordSeedPhraseTitle: String
    let enterPrivateKeyTitle: String
    let enterSeedPhraseTitle: String
    let editWalletTitle: String
    let createWalletTitle: String
    let importWalletTitle: String
    let backupVerificationSubtitle: String
    let advancedSubtitle: String
    let watchAddressesSubtitle: String
    let privateKeySubtitle: String
    let saveRecoveryPhraseSubtitle: String
    let enterRecoveryPhraseSubtitle: String
    let editWalletSubtitle: String
    let chooseNameAndChainsSubtitle: String
    let chooseNameAndChainSubtitle: String
    let seedImportMethodDescription: String
    let privateKeyImportMethodDescription: String
    let importSeedLengthTitle: String
    let importSeedLengthSubtitle: String
    let createSeedLengthTitle: String
    let createSeedLengthSubtitle: String
    let seedPhraseEntryHelp: String
    let createSeedPhraseWarning: String
    let privateKeyTitle: String
    let privateKeyPrompt: String
    let privateKeyPlaceholder: String
    let backupVerificationButtonTitle: String
    let backupVerifiedMessage: String
    let backupVerificationHint: String
    let watchOnlyFixedMessage: String
    let publicAddressOnlyMessage: String
    let moneroWatchUnsupportedMessage: String
    let addressesToWatchTitle: String
    let addressesToWatchSubtitle: String
    let bitcoinWatchCaption: String
    static var current: ImportFlowContent { StaticContentCatalog.loadRequiredResource("ImportFlowContent", as: ImportFlowContent.self) }
}
struct CommonLocalizationContent: Decodable {
    let priceAlertTitleFormat: String
    let addressBookSubtitleFormat: String
    let transactionSentTitleFormat: String
    let transactionReceivedTitleFormat: String
    let transactionSubtitleFormat: String
    let invalidAddressFormat: String
    let invalidAmountFormat: String
    let invalidDestinationAddressPromptFormat: String
    let invalidAssetAmountPromptFormat: String
    let invalidSeedPhraseFormat: String
    let invalidProviderResponseFormat: String
    let invalidTransferAmountFormat: String
    let signingTransactionFailedFormat: String
    let insufficientBalanceForAmountPlusNetworkFeeFormat: String
    let invalidUTXODataFormat: String
    let sourceAddressDoesNotMatchSeedFormat: String
    let networkErrorFormat: String
    let signingFailedFormat: String
    let networkRequestFailedFormat: String
    let broadcastFailedFormat: String
    let rpcErrorFormat: String
    let walletImportErrorTitle: String
    let sendErrorTitle: String
    let securityNoticeTitle: String
    let tronSendDiagnosticTitle: String
    static var current: CommonLocalizationContent {
        StaticContentCatalog.loadRequiredResource("CommonContent", as: CommonLocalizationContent.self)
    }
}
enum CommonLocalization {
    static func invalidAddress(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidAddressFormat, chainName)
    }
    static func invalidAmount(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidAmountFormat, chainName)
    }
    static func invalidDestinationAddressPrompt(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidDestinationAddressPromptFormat, chainName)
    }
    static func invalidAssetAmountPrompt(_ symbol: String) -> String {
        String(format: CommonLocalizationContent.current.invalidAssetAmountPromptFormat, symbol)
    }
    static func invalidSeedPhrase(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidSeedPhraseFormat, chainName)
    }
    static func invalidProviderResponse(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidProviderResponseFormat, chainName)
    }
    static func invalidTransferAmount(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidTransferAmountFormat, chainName)
    }
    static func signingTransactionFailed(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.signingTransactionFailedFormat, chainName)
    }
    static func insufficientBalanceForAmountPlusNetworkFee(_ symbolOrChain: String) -> String {
        String(format: CommonLocalizationContent.current.insufficientBalanceForAmountPlusNetworkFeeFormat, symbolOrChain)
    }
    static func invalidUTXOData(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidUTXODataFormat, chainName)
    }
    static func sourceAddressDoesNotMatchSeed(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.sourceAddressDoesNotMatchSeedFormat, chainName)
    }
    static func networkError(_ chainName: String, message: String) -> String {
        String(format: CommonLocalizationContent.current.networkErrorFormat, chainName, AppLocalization.string(message))
    }
    static func signingFailed(_ chainName: String, message: String) -> String {
        String(format: CommonLocalizationContent.current.signingFailedFormat, chainName, AppLocalization.string(message))
    }
    static func networkRequestFailed(_ chainName: String, message: String) -> String {
        String(format: CommonLocalizationContent.current.networkRequestFailedFormat, chainName, AppLocalization.string(message))
    }
    static func broadcastFailed(_ chainName: String, message: String) -> String {
        String(format: CommonLocalizationContent.current.broadcastFailedFormat, chainName, AppLocalization.string(message))
    }
    static func rpcError(_ chainName: String, message: String) -> String {
        String(format: CommonLocalizationContent.current.rpcErrorFormat, chainName, AppLocalization.string(message))
    }
}
/// Maps a human-readable color name string (stored in `core/tokens.toml`
/// and `resources/ChainVisualRegistry.json`) to a SwiftUI `Color`. Kept at
/// module scope so both the chain and token visual catalogs can share it.
enum RegistryColorLookup {
    static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "pink": return .pink
        case "indigo": return .indigo
        case "yellow": return .yellow
        case "cyan": return .cyan
        case "teal": return .teal
        case "gray": return .gray
        case "red": return .red
        case "purple": return .purple
        case "mint": return .mint
        default: return .accentColor
        }
    }
}
enum TokenVisualRegistryCatalog {
    /// Token visuals now derive from the single source of truth — the Rust
    /// `list_builtin_tokens` registry — rather than a separate JSON file.
    /// Dedupes by symbol because the TOML has one row per (chain, symbol)
    /// pair and visual metadata is symbol-level.
    static func loadEntries() -> [TokenVisualRegistryEntry] {
        var seen = Set<String>()
        var entries: [TokenVisualRegistryEntry] = []
        for token in listBuiltinTokens(chainId: UInt32.max) {
            let normalizedSymbol = token.symbol.uppercased()
            guard seen.insert(normalizedSymbol).inserted else { continue }
            guard let referenceChain = tokenTrackingChainFor(token.chain) else { continue }
            entries.append(
                TokenVisualRegistryEntry(
                    title: token.name, symbol: token.symbol, referenceChain: referenceChain,
                    color: RegistryColorLookup.color(named: token.colorName), assetName: token.assetName
                )
            )
        }
        return entries
    }
}
struct BuyCryptoProviderSeed: Decodable {
    let name: String
    let description: String
    let url: String
    let urlLabel: String
}
enum BuyCryptoProviderCatalog {
    static func loadEntries() -> [BuyCryptoProviderSeed] {
        StaticContentCatalog.loadRequiredResource("BuyCryptoProviders", as: [BuyCryptoProviderSeed].self)
    }
}
/// App-wide links that do NOT vary by locale — same URL regardless of the
/// user's language. Stored in `resources/AppLinks.json` at the root of the
/// shared resources folder (not `core/embedded/`, since Rust has no reason
/// to consume this — it's purely a Swift-side UI link).
struct AppLinks: Decodable {
    let reportProblem: String
    static var current: AppLinks { StaticContentCatalog.loadRequiredResource("AppLinks", as: AppLinks.self) }
}
struct DonationDestinationSeed: Decodable {
    let chainName: String
    let title: String
    let address: String
}
struct DonationsContentCopy: Decodable {
    let navigationTitle: String
    let heroTitle: String
    let heroSubtitle: String
    let destinations: [DonationDestinationSeed]
    static var current: DonationsContentCopy {
        StaticContentCatalog.loadRequiredResource("DonationsContent", as: DonationsContentCopy.self)
    }
}
struct EndpointsContentCopy: Decodable {
    let navigationTitle: String
    let intro: String
    let readOnlyFootnote: String
    let addEsploraEndpointPlaceholder: String
    let addEndpointButtonTitle: String
    let clearCustomBitcoinEndpointsTitle: String
    let customEthereumRPCURLPlaceholder: String
    let customMoneroBackendURLPlaceholder: String
    static var current: EndpointsContentCopy {
        StaticContentCatalog.loadRequiredResource("EndpointsContent", as: EndpointsContentCopy.self)
    }
}
struct ChainVisualRegistrySeed: Decodable {
    let id: String
    let colorName: String
    let assetName: String
}
struct ChainVisualRegistryEntry {
    let id: String
    let color: Color
    let assetName: String
}
enum ChainVisualRegistryCatalog {
    static func loadEntries() -> [String: ChainVisualRegistryEntry] {
        let seeds = StaticContentCatalog.loadRequiredResource("ChainVisualRegistry", as: [ChainVisualRegistrySeed].self)
        return Dictionary(
            uniqueKeysWithValues: seeds.map {
                (
                    $0.id,
                    ChainVisualRegistryEntry(
                        id: $0.id, color: RegistryColorLookup.color(named: $0.colorName), assetName: $0.assetName
                    )
                )
            })
    }
}
private func tokenTrackingChainFor(_ value: String) -> TokenTrackingChain? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "ethereum": return .ethereum
    case "arbitrum": return .arbitrum
    case "optimism": return .optimism
    case "bnb", "bnb chain": return .bnb
    case "avalanche": return .avalanche
    case "hyperliquid": return .hyperliquid
    case "solana": return .solana
    case "sui": return .sui
    case "aptos": return .aptos
    case "ton": return .ton
    case "near": return .near
    case "tron": return .tron
    default:
        return TokenTrackingChain.allCases.first { $0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
    }
}
extension ChainTokenRegistryEntry {
    static let builtIn: [ChainTokenRegistryEntry] = {
        listBuiltinTokens(chainId: UInt32.max).compactMap { entry -> ChainTokenRegistryEntry? in
            guard let chain = tokenTrackingChainFor(entry.chain),
                  let category = TokenPreferenceCategory(rawValue: entry.category)
            else { return nil }
            return ChainTokenRegistryEntry(
                chain: chain, name: entry.name, symbol: entry.symbol, tokenStandard: entry.tokenStandard,
                contractAddress: entry.contract, coinGeckoId: entry.coingeckoId,
                decimals: Int(entry.decimals), displayDecimals: entry.displayDecimals.map(Int.init),
                category: category, isBuiltIn: true, isEnabledByDefault: entry.enabled
            )
        }
    }()
}
enum BIP39EnglishWordList {
    static let words: Set<String> = {
        let text = bip39EnglishWordlist()
        return Set(
            text.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }()
}
enum AppLocalization {
    private final class BundleMarker {}
    private struct LocalizationState {
        let signature: String
        let identifiers: [String]
        let locale: Locale
        let bundles: [Bundle]
    }
    private struct RuntimeStringManifest: Decodable {
        let sourceLanguage: String
        let availableLocales: [String]
    }
    private static let candidateBundles: [Bundle] = {
        var seen = Set<URL>()
        return ([Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            guard let bundleURL = bundle.bundleURL.standardizedFileURL as URL? else { return false }
            return seen.insert(bundleURL).inserted
        }
    }()
    private static var localizedStringCache: [String: String] = [:]
    private static var cachedState: LocalizationState?
    private static var runtimeManifest: RuntimeStringManifest?
    private static var manifestLoadAttempted = false
    private static var runtimeStringsBaseURL: URL?
    private static var loadedLocaleDicts: [String: [String: String]] = [:]
    static var locale: Locale { localizationState().locale }
    static func string(_ key: String, table: String? = nil) -> String {
        let state = localizationState()
        let signature = state.signature
        let cacheKey = "\(signature)|\(table ?? "<default>")|\(key)"
        if let cachedValue = localizedStringCache[cacheKey] { return cachedValue }
        if let runtimeValue = runtimeString(for: key, localizationIdentifiers: state.identifiers) {
            localizedStringCache[cacheKey] = runtimeValue
            return runtimeValue
        }
        for bundle in state.bundles {
            let value = bundle.localizedString(forKey: key, value: key, table: table)
            if value != key {
                localizedStringCache[cacheKey] = value
                return value
            }
        }
        let fallbackValue: String
        if let developmentPath = Bundle.main.path(forResource: Bundle.main.developmentLocalization ?? "en", ofType: "lproj"),
            let developmentBundle = Bundle(path: developmentPath)
        {
            fallbackValue = developmentBundle.localizedString(forKey: key, value: key, table: table)
        } else {
            fallbackValue = Bundle.main.localizedString(forKey: key, value: key, table: table)
        }
        localizedStringCache[cacheKey] = fallbackValue
        return fallbackValue
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
    static func preferredLocalizationIdentifiers() -> [String] { localizationState().identifiers }
    private static func localizationState() -> LocalizationState {
        let signature = preferenceSignature()
        if let cachedState, cachedState.signature == signature { return cachedState }
        let supported = supportedLocalizationIdentifiers()
        guard !supported.isEmpty else {
            let state = LocalizationState(
                signature: signature, identifiers: ["en"], locale: Locale(identifier: "en"), bundles: [Bundle.main]
            )
            cachedState = state
            return state
        }
        let development = loadManifest()?.sourceLanguage ?? Bundle.main.developmentLocalization ?? "en"
        let preferred = preferredLanguageCandidates()
        let resolved = preferred.compactMap { preferredLocalization(for: $0, supported: supported) }
        var ordered: [String] = []
        var seen = Set<String>()
        for localization in resolved where seen.insert(localization).inserted { ordered.append(localization) }
        if seen.insert(development).inserted { ordered.append(development) }
        if seen.insert("Base").inserted { ordered.append("Base") }
        let bundles =
            ordered.compactMap { identifier in
                guard identifier != "Base" else { return Bundle.main }
                guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"), let bundle = Bundle(path: path) else {
                    return nil
                }
                return bundle
            } + [Bundle.main]
        let state = LocalizationState(
            signature: signature, identifiers: ordered, locale: Locale(identifier: ordered.first ?? development), bundles: bundles
        )
        cachedState = state
        return state
    }
    private static func preferenceSignature() -> String {
        (Locale.preferredLanguages + Bundle.main.preferredLocalizations).joined(separator: "|")
    }
    private static func supportedLocalizationIdentifiers() -> [String] {
        var supported = Set(Bundle.main.localizations.filter { $0 != "Base" })
        if let manifest = loadManifest() {
            supported.formUnion(manifest.availableLocales)
            supported.insert(manifest.sourceLanguage)
        }
        return supported.isEmpty ? ["en"] : supported.sorted()
    }
    private static func preferredLanguageCandidates() -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()
        for identifier in Locale.preferredLanguages + Bundle.main.preferredLocalizations {
            for fallback in localizationFallbacks(for: identifier) where seen.insert(fallback).inserted { candidates.append(fallback) }
        }
        if candidates.isEmpty {
            let fallbackIdentifiers = [loadManifest()?.sourceLanguage ?? Bundle.main.developmentLocalization ?? "en"]
            for identifier in fallbackIdentifiers {
                for fallback in localizationFallbacks(for: identifier) where seen.insert(fallback).inserted { candidates.append(fallback) }
            }
        }
        return candidates
    }
    private static func preferredLocalization(for identifier: String, supported: [String]) -> String? {
        if supported.contains(identifier) { return identifier }
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if supported.contains(normalized) { return normalized }
        if normalized.lowercased().hasPrefix("zh-hans"), supported.contains("zh-Hans") { return "zh-Hans" }
        if normalized.lowercased().hasPrefix("zh-hant"), supported.contains("zh-Hant") { return "zh-Hant" }
        let languageCode = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return supported.first(where: { $0.caseInsensitiveCompare(languageCode) == .orderedSame })
    }
    private static func localizationFallbacks(for identifier: String) -> [String] {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let components = normalized.split(separator: "-").map(String.init)
        guard !components.isEmpty else { return [] }
        var fallbacks: [String] = []
        for index in stride(from: components.count, through: 1, by: -1) {
            fallbacks.append(components.prefix(index).joined(separator: "-"))
        }
        return fallbacks
    }
    private static func runtimeString(for key: String, localizationIdentifiers: [String]) -> String? {
        guard loadManifest() != nil else { return nil }
        for identifier in localizationIdentifiers {
            for fallback in localizationFallbacks(for: identifier) {
                if let dict = loadLocaleDict(fallback), let value = dict[key] { return value }
            }
        }
        if let sourceLanguage = runtimeManifest?.sourceLanguage, let dict = loadLocaleDict(sourceLanguage) { return dict[key] }
        return nil
    }
    private static func loadManifest() -> RuntimeStringManifest? {
        if manifestLoadAttempted { return runtimeManifest }
        manifestLoadAttempted = true
        let decoder = JSONDecoder()
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            let candidateDirs = [
                resourceURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("strings", isDirectory: true),
                resourceURL.appendingPathComponent("strings", isDirectory: true),
                resourceURL,
            ]
            for dir in candidateDirs {
                let url = dir.appendingPathComponent("RuntimeStrings.manifest.json")
                guard let data = try? Data(contentsOf: url), let manifest = try? decoder.decode(RuntimeStringManifest.self, from: data)
                else { continue }
                runtimeManifest = manifest
                runtimeStringsBaseURL = dir
                return manifest
            }
        }
        return nil
    }
    private static func loadLocaleDict(_ locale: String) -> [String: String]? {
        if let cached = loadedLocaleDicts[locale] { return cached }
        guard let baseURL = runtimeStringsBaseURL else { return nil }
        let url = baseURL.appendingPathComponent("RuntimeStrings.\(locale).json")
        guard let data = try? Data(contentsOf: url), let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        loadedLocaleDicts[locale] = dict
        return dict
    }
}
