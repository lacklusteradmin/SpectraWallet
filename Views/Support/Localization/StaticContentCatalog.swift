import Foundation
import SwiftUI

private enum LocalizationCatalogReferenceKeeper {
    // Runtime short strings now come from `Resources/Localization/RuntimeStrings.json`.
    // Keep this placeholder so older references to the type still compile while the
    // remaining SwiftUI literal sites are migrated away from Apple-only localization APIs.
    static let strings: [String] = []
}

enum StaticContentCatalog {
    private final class BundleMarker {}

    static func loadRequiredResource<T: Decodable>(_ baseName: String, as type: T.Type) -> T {
        let decoder = JSONDecoder()
        let localeIdentifiers = AppLocalization.preferredLocalizationIdentifiers()

        for url in candidateJSONURLs(for: baseName, localeIdentifiers: localeIdentifiers) {
            guard let data = try? Data(contentsOf: url),
                  let value = try? decoder.decode(T.self, from: data) else {
                continue
            }
            return value
        }

        fatalError("Missing required resource: \(baseName).json")
    }

    static func loadResource<T: Decodable>(_ baseName: String, as type: T.Type) -> T? {
        let decoder = JSONDecoder()
        let localeIdentifiers = AppLocalization.preferredLocalizationIdentifiers()

        for url in candidateJSONURLs(for: baseName, localeIdentifiers: localeIdentifiers) {
            guard let data = try? Data(contentsOf: url),
                  let value = try? decoder.decode(T.self, from: data) else {
                continue
            }
            return value
        }

        return nil
    }

    static func loadRequiredTextResource(_ baseName: String) -> String {
        for url in candidateTextURLs(for: baseName) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            return text
        }

        fatalError("Missing required text resource: \(baseName)")
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
                    append(resourceURL
                        .appendingPathComponent("Resources", isDirectory: true)
                        .appendingPathComponent("Localization", isDirectory: true)
                        .appendingPathComponent("Base", isDirectory: true)
                        .appendingPathComponent("\(baseName).json", isDirectory: false))
                    append(resourceURL
                        .appendingPathComponent("Localization", isDirectory: true)
                        .appendingPathComponent("Base", isDirectory: true)
                        .appendingPathComponent("\(baseName).json", isDirectory: false))
                } else {
                    append(resourceURL
                        .appendingPathComponent("Resources", isDirectory: true)
                        .appendingPathComponent("Localization", isDirectory: true)
                        .appendingPathComponent(localeIdentifier, isDirectory: true)
                        .appendingPathComponent("\(baseName).\(localeIdentifier).json", isDirectory: false))
                    append(resourceURL
                        .appendingPathComponent("Localization", isDirectory: true)
                        .appendingPathComponent(localeIdentifier, isDirectory: true)
                        .appendingPathComponent("\(baseName).\(localeIdentifier).json", isDirectory: false))
                }
            }

            append(resourceURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Localization", isDirectory: true)
                .appendingPathComponent("Base", isDirectory: true)
                .appendingPathComponent("\(baseName).json", isDirectory: false))
            append(resourceURL
                .appendingPathComponent("Localization", isDirectory: true)
                .appendingPathComponent("Base", isDirectory: true)
                .appendingPathComponent("\(baseName).json", isDirectory: false))
            append(resourceURL.appendingPathComponent("\(baseName).json", isDirectory: false))
        }

        return candidates
    }

    private static func candidateTextURLs(for baseName: String) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            candidates.append(url)
        }

        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            append(resourceURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("\(baseName).txt", isDirectory: false))
            append(resourceURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("\(baseName).md", isDirectory: false))
            append(resourceURL
                .appendingPathComponent("\(baseName).txt", isDirectory: false))
            append(resourceURL
                .appendingPathComponent("\(baseName).md", isDirectory: false))
            append(resourceURL
                .appendingPathComponent("\(baseName).txt", isDirectory: false))
        }

        return candidates
    }

    private static let candidateBundles: [Bundle] = {
        var seen = Set<URL>()
        return ([Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            guard let bundleURL = bundle.bundleURL.standardizedFileURL as URL? else {
                return false
            }
            return seen.insert(bundleURL).inserted
        }
    }()
}

struct SettingsContentCopy: Decodable {
    let pricingIntro: String
    let fiatRateProviderNote: String
    let coinGeckoNote: String
    let publicProviderNote: String
    let aboutTitle: String
    let aboutSubtitle: String
    let aboutEthosTitle: String
    let aboutEthosLines: [String]
    let aboutNarrativeTitle: String
    let aboutNarrativeParagraphs: [String]
    let reportProblemDescription: String
    let reportProblemActionTitle: String
    let reportProblemURL: String
    let buyProvidersIntro: String
    let buyWarning: String

    static var current: SettingsContentCopy {
        StaticContentCatalog.loadRequiredResource("SettingsContent", as: SettingsContentCopy.self)
    }
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

    static var current: ImportFlowContent {
        StaticContentCatalog.loadRequiredResource("ImportFlowContent", as: ImportFlowContent.self)
    }
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

struct TokenVisualRegistrySeed: Decodable {
    let title: String
    let symbol: String
    let referenceChain: String
    let mark: String
    let colorName: String
    let assetName: String
}

enum TokenVisualRegistryCatalog {
    static func loadEntries() -> [TokenVisualRegistryEntry] {
        let seeds = StaticContentCatalog.loadRequiredResource("TokenVisualRegistry", as: [TokenVisualRegistrySeed].self)
        return seeds.compactMap { seed in
            guard let referenceChain = TokenTrackingChain(rawValue: seed.referenceChain) else { return nil }
            return TokenVisualRegistryEntry(
                title: seed.title,
                symbol: seed.symbol,
                referenceChain: referenceChain,
                mark: seed.mark,
                color: color(named: seed.colorName),
                assetName: seed.assetName
            )
        }
    }

    private static func color(named name: String) -> Color {
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
        default: return .accentColor
        }
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
    let mark: String
    let colorName: String
    let assetName: String
}

struct ChainVisualRegistryEntry {
    let id: String
    let mark: String
    let color: Color
    let assetName: String
}

enum ChainVisualRegistryCatalog {
    static func loadEntries() -> [String: ChainVisualRegistryEntry] {
        let seeds = StaticContentCatalog.loadRequiredResource("ChainVisualRegistry", as: [ChainVisualRegistrySeed].self)
        return Dictionary(uniqueKeysWithValues: seeds.map {
            (
                $0.id,
                ChainVisualRegistryEntry(
                    id: $0.id,
                    mark: $0.mark,
                    color: color(named: $0.colorName),
                    assetName: $0.assetName
                )
            )
        })
    }

    private static func color(named name: String) -> Color {
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

struct BuiltInTokenRegistrySeed: Decodable {
    let chain: String
    let name: String
    let symbol: String
    let tokenStandard: String
    let contractAddress: String
    let marketDataID: String
    let coinGeckoID: String
    let decimals: Int
    let displayDecimals: Int?
    let category: String
    let isBuiltIn: Bool
    let isEnabledByDefault: Bool
}

enum BuiltInTokenRegistryCatalog {
    static func loadEntries() -> [ChainTokenRegistryEntry] {
        let seeds = StaticContentCatalog.loadRequiredResource("BuiltInTokenRegistry", as: [BuiltInTokenRegistrySeed].self)
        return seeds.compactMap { seed in
            guard let chain = tokenTrackingChain(for: seed.chain),
                  let category = TokenPreferenceCategory(rawValue: seed.category) else {
                return nil
            }
            return ChainTokenRegistryEntry(
                chain: chain,
                name: seed.name,
                symbol: seed.symbol,
                tokenStandard: seed.tokenStandard,
                contractAddress: resolvedContractAddress(seed.contractAddress),
                marketDataID: seed.marketDataID,
                coinGeckoID: seed.coinGeckoID,
                decimals: seed.decimals,
                displayDecimals: seed.displayDecimals,
                category: category,
                isBuiltIn: seed.isBuiltIn,
                isEnabledByDefault: seed.isEnabledByDefault
            )
        }
    }

    private static func tokenTrackingChain(for value: String) -> TokenTrackingChain? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ethereum":
            return .ethereum
        case "arbitrum":
            return .arbitrum
        case "optimism":
            return .optimism
        case "bnb", "bnb chain":
            return .bnb
        case "avalanche":
            return .avalanche
        case "hyperliquid":
            return .hyperliquid
        case "solana":
            return .solana
        case "sui":
            return .sui
        case "aptos":
            return .aptos
        case "ton":
            return .ton
        case "near":
            return .near
        case "tron":
            return .tron
        default:
            return TokenTrackingChain.allCases.first {
                $0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            }
        }
    }

    private static func resolvedContractAddress(_ value: String) -> String {
        switch value {
        case "SolanaBalanceService.usdtMintAddress":
            return SolanaBalanceService.usdtMintAddress
        case "SolanaBalanceService.usdcMintAddress":
            return SolanaBalanceService.usdcMintAddress
        case "SolanaBalanceService.pyusdMintAddress":
            return SolanaBalanceService.pyusdMintAddress
        case "SolanaBalanceService.usdgMintAddress":
            return SolanaBalanceService.usdgMintAddress
        case "SolanaBalanceService.usd1MintAddress":
            return SolanaBalanceService.usd1MintAddress
        case "SolanaBalanceService.linkMintAddress":
            return SolanaBalanceService.linkMintAddress
        case "SolanaBalanceService.wlfiMintAddress":
            return SolanaBalanceService.wlfiMintAddress
        case "SolanaBalanceService.jupMintAddress":
            return SolanaBalanceService.jupMintAddress
        case "SolanaBalanceService.bonkMintAddress":
            return SolanaBalanceService.bonkMintAddress
        case "TronBalanceService.usdtTronContract":
            return TronBalanceService.usdtTronContract
        case "TronBalanceService.usddTronContract":
            return TronBalanceService.usddTronContract
        case "TronBalanceService.usd1TronContract":
            return TronBalanceService.usd1TronContract
        case "TronBalanceService.bttTronContract":
            return TronBalanceService.bttTronContract
        default:
            return value
        }
    }
}

extension ChainTokenRegistryEntry {
    static let builtIn: [ChainTokenRegistryEntry] = BuiltInTokenRegistryCatalog.loadEntries()
}

enum BIP39EnglishWordList {
    static let words: Set<String> = {
        let text = StaticContentCatalog.loadRequiredTextResource("BIP39EnglishWordList")
        return Set(
            text
                .split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }()
}
