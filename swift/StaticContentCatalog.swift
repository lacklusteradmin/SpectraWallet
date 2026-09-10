import Foundation
import SwiftUI
private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
enum StaticContentCatalog {
    private final class BundleMarker {}
    // Memoize decoded resources across the app: `XxxContentCopy.current` is
    // read from view bodies. Keyed by `(localeSignature, baseName, typeID)` so a
    // language switch invalidates on the next read.
    private static let decodedResourceCache = LockedValue<[String: Any]>([:])
    private static func cacheKey(baseName: String, typeID: String) -> String {
        let signature = AppLocalization.preferredLocalizationIdentifiers().joined(separator: ",")
        return "\(signature)|\(baseName)|\(typeID)"
    }
    static func loadRequiredResource<T: Decodable>(_ baseName: String, as type: T.Type) -> T {
        let key = cacheKey(baseName: baseName, typeID: String(describing: type))
        if let cached = decodedResourceCache.withLock({ $0[key] as? T }) { return cached }
        let value: T = loadRequiredResourceUncached(baseName, as: type)
        decodedResourceCache.withLock { $0[key] = value }
        return value
    }
    private static func loadRequiredResourceUncached<T: Decodable>(_ baseName: String, as type: T.Type) -> T {
        let decoder = JSONDecoder()
        let localeIdentifiers = AppLocalization.preferredLocalizationIdentifiers()
        for url in candidateJSONURLs(for: baseName, localeIdentifiers: localeIdentifiers) {
            guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(T.self, from: data) else { continue }
            return value
        }
        fatalError("Missing required resource: \(baseName).json")
    }
    /// Every content file sits at the bundle's resource root, so the locale
    /// lives in the file name and nowhere else.
    ///
    /// `resources/` is the app target's synchronized group, and Xcode copies
    /// such a group in flat: `resources/strings/CommonContent.en.json` ships as
    /// `CommonContent.en.json`. Three path shapes were built per lookup —
    /// the flat one plus `Resources/strings/<locale>/` and `strings/<locale>/`
    /// — guesses at a nested layout the bundle has never had. Only the flat one
    /// ever opened a file; the source tree is now flat to match.
    private static func candidateJSONURLs(for baseName: String, localeIdentifiers: [String]) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()
        func append(_ name: String, in resourceURL: URL) {
            let url = resourceURL.appendingPathComponent(name, isDirectory: false)
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            candidates.append(url)
        }
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            for localeIdentifier in localeIdentifiers {
                let name = localeIdentifier == "Base" ? "\(baseName).json" : "\(baseName).\(localeIdentifier).json"
                append(name, in: resourceURL)
            }
            append("\(baseName).json", in: resourceURL)
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
    let buyOnrampNote: String
    let buyExchangeNote: String
    let buyListingNote: String
    static var current: SettingsContentCopy { StaticContentCatalog.loadRequiredResource("SettingsContent", as: SettingsContentCopy.self) }
}
struct DiagnosticsContentCopy: Decodable {
    let navigationTitle: String
    let searchPrompt: String
    let chainsSectionTitle: String
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
    let invalidDestinationAddressPromptFormat: String
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
    static func invalidDestinationAddressPrompt(_ chainName: String) -> String {
        String(format: CommonLocalizationContent.current.invalidDestinationAddressPromptFormat, chainName)
    }
}
/// Maps a human-readable color string (stored in `core/data/tokens.toml`
/// and `core/data/chains.toml`) to a SwiftUI `Color`.
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
/// App-wide links that do NOT vary by locale — same URL regardless of the
/// user's language. Stored in `resources/AppLinks.json` at the root of the
/// shared resources folder (not `core/embedded/`, since Rust has no reason
/// to consume this — it's purely a Swift-side UI link).
struct AppLinks: Decodable {
    let reportProblem: String
    static var current: AppLinks { StaticContentCatalog.loadRequiredResource("AppLinks", as: AppLinks.self) }
}

/// The buy/exchange directory, from `resources/BuyProviders.json`.
///
/// Names, URLs and domains do not translate, so the list is one
/// locale-independent file rather than four keys per provider in every
/// `SettingsContent.*.json`. Only the section notes are copy. Adding a
/// provider is one row here.
struct BuyProviderSeed: Decodable, Identifiable {
    let id: String
    let name: String
    let url: String
    let label: String
}

struct BuyProviders: Decodable {
    let onramps: [BuyProviderSeed]
    let exchanges: [BuyProviderSeed]
    static var current: BuyProviders { StaticContentCatalog.loadRequiredResource("BuyProviders", as: BuyProviders.self) }
}
struct DonationDestinationSeed: Decodable {
    let chainName: String
    let title: String
    let address: String
}
struct DonationsContentCopy: Decodable {
    let navigationTitle: String
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
    let customRPCURLPlaceholder: String
    let customMoneroBackendURLPlaceholder: String
    static var current: EndpointsContentCopy {
        StaticContentCatalog.loadRequiredResource("EndpointsContent", as: EndpointsContentCopy.self)
    }
}
/// The token-hosting chain a name or id stands for.
private func tokenHostingChainFor(_ value: String) -> TokenHostingChain? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }
    let chain = Chain(id: normalized) ?? Chain.all.first { $0.displayName.lowercased() == normalized }
    return chain?.tokenHostingChain
}
extension TokenPreferenceEntry {
    /// The catalog's tokens, as preferences with nothing changed yet.
    ///
    /// Went through `ChainTokenRegistryEntry` — a fourth record for one token,
    /// built here from the catalog row and converted back to a preference at
    /// every use.
    static let builtIn: [TokenPreferenceEntry] = {
        listAllBuiltinTokens().compactMap { token -> TokenPreferenceEntry? in
            guard tokenHostingChainFor(token.chain) != nil else { return nil }
            let category: TokenPreferenceCategory = token.tags.lazy
                .compactMap { TokenPreferenceCategory(rawValue: $0) }
                .first ?? .custom
            return TokenPreferenceEntry(
                token: token, category: category, isBuiltIn: true, isEnabled: token.enabled)
        }
    }()
}
enum BIP39WordList {
    private static let cache = LockedValue<[String: Set<String>]>([:])
    static func words(for language: String) -> Set<String> {
        let key = language.lowercased()
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let text = bip39Wordlist(language: language)
        let set = Set(
            text.split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        cache.withLock { $0[key] = set }
        return set
    }
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
    private static let localizedStringCache = LockedValue<[String: String]>([:])
    private static let cachedState = LockedValue<LocalizationState?>(nil)
    private static let runtimeManifest = LockedValue<RuntimeStringManifest?>(nil)
    private static let manifestLoadAttempted = LockedValue(false)
    private static let runtimeStringsBaseURL = LockedValue<URL?>(nil)
    private static let loadedLocaleDicts = LockedValue<[String: [String: String]]>([:])
    static var locale: Locale { localizationState().locale }
    static func string(_ key: String, table: String? = nil) -> String {
        let state = localizationState()
        let signature = state.signature
        let cacheKey = "\(signature)|\(table ?? "<default>")|\(key)"
        if let cachedValue = localizedStringCache.withLock({ $0[cacheKey] }) { return cachedValue }
        if let runtimeValue = runtimeString(for: key, localizationIdentifiers: state.identifiers) {
            localizedStringCache.withLock { $0[cacheKey] = runtimeValue }
            return runtimeValue
        }
        for bundle in state.bundles {
            let value = bundle.localizedString(forKey: key, value: key, table: table)
            if value != key {
                localizedStringCache.withLock { $0[cacheKey] = value }
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
        localizedStringCache.withLock { $0[cacheKey] = fallbackValue }
        return fallbackValue
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
    static func preferredLocalizationIdentifiers() -> [String] { localizationState().identifiers }
    private static func localizationState() -> LocalizationState {
        let signature = preferenceSignature()
        if let state = cachedState.withLock({ $0 }), state.signature == signature { return state }
        let supported = supportedLocalizationIdentifiers()
        guard !supported.isEmpty else {
            let state = LocalizationState(
                signature: signature, identifiers: ["en"], locale: Locale(identifier: "en"), bundles: [Bundle.main]
            )
            cachedState.withLock { $0 = state }
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
        cachedState.withLock { $0 = state }
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
        if let sourceLanguage = runtimeManifest.withLock({ $0 })?.sourceLanguage,
           let dict = loadLocaleDict(sourceLanguage) {
            return dict[key]
        }
        return nil
    }
    private static func loadManifest() -> RuntimeStringManifest? {
        if manifestLoadAttempted.withLock({ $0 }) {
            return runtimeManifest.withLock { $0 }
        }
        manifestLoadAttempted.withLock { $0 = true }
        let decoder = JSONDecoder()
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            let url = resourceURL.appendingPathComponent("RuntimeStrings.manifest.json")
            guard let data = try? Data(contentsOf: url), let manifest = try? decoder.decode(RuntimeStringManifest.self, from: data)
            else { continue }
            runtimeManifest.withLock { $0 = manifest }
            runtimeStringsBaseURL.withLock { $0 = resourceURL }
            return manifest
        }
        return nil
    }
    private static func loadLocaleDict(_ locale: String) -> [String: String]? {
        if let cached = loadedLocaleDicts.withLock({ $0[locale] }) { return cached }
        guard let baseURL = runtimeStringsBaseURL.withLock({ $0 }) else { return nil }
        let url = baseURL.appendingPathComponent("RuntimeStrings.\(locale).json")
        guard let data = try? Data(contentsOf: url), let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        loadedLocaleDicts.withLock { $0[locale] = dict }
        return dict
    }
}
