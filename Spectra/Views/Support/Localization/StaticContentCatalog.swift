import Foundation
import SwiftUI

private enum LocalizationCatalogReferenceKeeper {
    // Xcode's localization validator does not track dynamic `AppLocalization.string(...)`
    // lookups, so keep explicit references for dynamic keys that are intentionally resolved
    // through the app's localization layer at runtime.
    static let strings: [String] = [
        String(localized: "%@ Diagnostics"),
        String(localized: "%lld valid %@ address%@ ready to import."),
        String(localized: "About Spectra"),
        String(localized: "Addresses"),
        String(localized: "Aptos"),
        String(localized: "Arbitrum"),
        String(localized: "Asset"),
        String(localized: "Avalanche"),
        String(localized: "Bitcoin"),
        String(localized: "Bitcoin Cash"),
        String(localized: "Bitcoin SV"),
        String(localized: "Block"),
        String(localized: "BNB Chain"),
        String(localized: "Broadcasting Bitcoin Cash transaction..."),
        String(localized: "Broadcasting Bitcoin transaction..."),
        String(localized: "Broadcasting Cardano transaction..."),
        String(localized: "Broadcasting Dogecoin transaction..."),
        String(localized: "Broadcasting Litecoin transaction..."),
        String(localized: "Broadcasting Monero transaction..."),
        String(localized: "Broadcasting Tron transaction..."),
        String(localized: "Broadcasting XRP transaction..."),
        String(localized: "Cancel This Transaction"),
        String(localized: "Cardano"),
        String(localized: "Change Address"),
        String(localized: "Change Path"),
        String(localized: "Confirmations"),
        String(localized: "Done"),
        String(localized: "Dogecoin"),
        String(localized: "DOGE Change Output"),
        String(localized: "DOGE Confirmed Fee"),
        String(localized: "DOGE Fee Priority"),
        String(localized: "DOGE Fee Rate"),
        String(localized: "Enter one %@ address per line."),
        String(localized: "Ethereum"),
        String(localized: "Ethereum Classic"),
        String(localized: "Ethereum Mempool Actions"),
        String(localized: "Effective Gas Price"),
        String(localized: "EVM (Ethereum / ETC / Arbitrum / Optimism / BNB Chain / Avalanche / Hyperliquid)"),
        String(localized: "Every line must contain a valid %@ address."),
        String(localized: "Failure"),
        String(localized: "From"),
        String(localized: "Gas Used"),
        String(localized: "History Source"),
        String(localized: "Hyperliquid"),
        String(localized: "Internet Computer"),
        String(localized: "Litecoin"),
        String(localized: "Monero"),
        String(localized: "My Assets"),
        String(localized: "My Wallets"),
        String(localized: "NEAR"),
        String(localized: "Network"),
        String(localized: "Network Fee"),
        String(localized: "Optimism"),
        String(localized: "Overview"),
        String(localized: "Polkadot"),
        String(localized: "Primary Use"),
        String(localized: "Preparing replacement/cancel context..."),
        String(localized: "Protocol Reference"),
        String(localized: "QR Code"),
        String(localized: "Regenerate"),
        String(localized: "Scan to Donate"),
        String(localized: "SLIP44"),
        String(localized: "SLIP44 Coin Type"),
        String(localized: "Seed Phrase Length"),
        String(localized: "Solana"),
        String(localized: "Source Address"),
        String(localized: "Source Path"),
        String(localized: "Speed Up This Transaction"),
        String(localized: "State"),
        String(localized: "State Model"),
        String(localized: "Stellar"),
        String(localized: "Status"),
        String(localized: "Sui"),
        String(localized: "Support Link"),
        String(localized: "Technical Notes"),
        String(localized: "This opens the Send composer with the same nonce and higher fee defaults so you can safely speed up or cancel the pending transaction."),
        String(localized: "Timestamp"),
        String(localized: "TON"),
        String(localized: "To"),
        String(localized: "Transaction Hash"),
        String(localized: "Tron"),
        String(localized: "Type"),
        String(localized: "Wallet"),
        String(localized: "XRP Ledger"),
        String(localized: "Browse Spectra's supported chains, default derivation paths, registered SLIP44 coin types, and protocol-level notes in a cleaner reference format."),
        String(localized: "Chains"),
        String(localized: "Circulation Model"),
        String(localized: "Consensus"),
        String(localized: "Default Path"),
        String(localized: "Derivation In Spectra"),
        String(localized: "Derivation Paths"),
        String(localized: "Family"),
        String(localized: "Identity"),
        String(localized: "Ticker"),
        String(localized: " Last good sync: %@."),
        String(localized: "%@ %@"),
        String(localized: "%@ • %@"),
        String(localized: "%@ Endpoint Reachability"),
        String(localized: "%@ History Sources"),
        String(localized: "%@ Network"),
        String(localized: "%@ sent to %@"),
        String(localized: "Aptos broadcast failed: %@"),
        String(localized: "Aptos network request failed: %@"),
        String(localized: "Aptos RPC error: %@"),
        String(localized: "Auto-managed"),
        String(localized: "Broadcast via Blockchair"),
        String(localized: "Broadcast via BlockCypher"),
        String(localized: "Cardano broadcast failed: %@"),
        String(localized: "Cardano network request failed: %@"),
        String(localized: "Cardano signing failed: %@"),
        String(localized: "Change Output: %@"),
        String(localized: "Confirmation Preference: %@"),
        String(localized: "DOGE Exclusive Actions"),
        String(localized: "Dogecoin broadcast failed: %@"),
        String(localized: "Dogecoin network error: %@"),
        String(localized: "Dogecoin Send"),
        String(localized: "Enter a valid Dogecoin amount."),
        String(localized: "Enter a valid Dogecoin destination address."),
        String(localized: "Enter amount to preview estimated %@ network fee."),
        String(localized: "Enter an amount to load a live UTXO and fee preview. Add a valid destination address before sending."),
        String(localized: "Enter word %lld"),
        String(localized: "Estimated Fee Rate: %llu sat/vB"),
        String(localized: "Estimated Fee: %.6f DOGE"),
        String(localized: "Estimated Fee: %.6f DOGE (~%@)"),
        String(localized: "Estimated Network Fee: %.6f %@"),
        String(localized: "Estimated Network Fee: %.6f %@ (~%@)"),
        String(localized: "Estimated Network Fee: %.6f ADA"),
        String(localized: "Estimated Network Fee: %.6f ADA (~%@)"),
        String(localized: "Estimated Network Fee: %.6f APT"),
        String(localized: "Estimated Network Fee: %.6f APT (~%@)"),
        String(localized: "Estimated Network Fee: %.6f DOT"),
        String(localized: "Estimated Network Fee: %.6f DOT (~%@)"),
        String(localized: "Estimated Network Fee: %.6f NEAR"),
        String(localized: "Estimated Network Fee: %.6f NEAR (~%@)"),
        String(localized: "Estimated Network Fee: %.6f SOL"),
        String(localized: "Estimated Network Fee: %.6f SOL (~%@)"),
        String(localized: "Estimated Network Fee: %.6f SUI"),
        String(localized: "Estimated Network Fee: %.6f SUI (~%@)"),
        String(localized: "Estimated Network Fee: %.6f TON"),
        String(localized: "Estimated Network Fee: %.6f TON (~%@)"),
        String(localized: "Estimated Network Fee: %.6f TRX"),
        String(localized: "Estimated Network Fee: %.6f TRX (~%@)"),
        String(localized: "Estimated Network Fee: %.6f XMR"),
        String(localized: "Estimated Network Fee: %.6f XMR (~%@)"),
        String(localized: "Estimated Network Fee: %.6f XRP"),
        String(localized: "Estimated Network Fee: %.6f XRP (~%@)"),
        String(localized: "Estimated Network Fee: %.7f XLM"),
        String(localized: "Estimated Network Fee: %.7f XLM (~%@)"),
        String(localized: "Estimated Network Fee: %.8f %@"),
        String(localized: "Estimated Network Fee: %.8f %@ (~%@)"),
        String(localized: "Estimated Network Fee: %.8f ICP"),
        String(localized: "Estimated Network Fee: %.8f ICP (~%@)"),
        String(localized: "Estimated Size: %lld bytes"),
        String(localized: "Failed to sign Aptos transaction: %@"),
        String(localized: "Failed to sign ICP transaction: %@"),
        String(localized: "Failed to sign Litecoin transaction."),
        String(localized: "Failed to sign NEAR transaction: %@"),
        String(localized: "Failed to sign Polkadot transaction: %@"),
        String(localized: "Failed to sign Solana transaction: %@"),
        String(localized: "Failed to sign Stellar transaction: %@"),
        String(localized: "Failed to sign Sui transaction: %@"),
        String(localized: "Failed to sign the Dogecoin transaction."),
        String(localized: "Failed to sign TON transaction: %@"),
        String(localized: "Failed to sign XRP transaction: %@"),
        String(localized: "Fee Rate: %.4f DOGE/KB"),
        String(localized: "Fee Rate: %@"),
        String(localized: "Gas Budget: %llu MIST"),
        String(localized: "Gas Limit: %lld"),
        String(localized: "Gas Unit Price: %llu octas"),
        String(localized: "ICP broadcast failed: %@"),
        String(localized: "ICP network request failed: %@"),
        String(localized: "Insufficient Bitcoin Cash balance for amount plus network fee."),
        String(localized: "Insufficient Bitcoin SV balance for amount plus network fee."),
        String(localized: "Insufficient DOGE to cover amount plus network fee."),
        String(localized: "Insufficient Litecoin balance for amount plus fee."),
        String(localized: "Invalid Tron endpoint URL."),
        String(localized: "Invalid Tron verification endpoint URL."),
        String(localized: "Last Ledger Sequence: %lld"),
        String(localized: "Max Fee: %.2f gwei"),
        String(localized: "Max Gas Amount: %llu"),
        String(localized: "Max Inputs: %@"),
        String(localized: "Max Sendable: %.6f DOGE"),
        String(localized: "Max Sendable: %@"),
        String(localized: "NEAR broadcast failed: %@"),
        String(localized: "NEAR network request failed: %@"),
        String(localized: "NEAR RPC error: %@"),
        String(localized: "Next change index: %lld"),
        String(localized: "Next receive index: %lld"),
        String(localized: "No (dust-safe fee absorption)"),
        String(localized: "Nonce: %lld"),
        String(localized: "Other Chains"),
        String(localized: "Polkadot broadcast failed: %@"),
        String(localized: "Polkadot network request failed: %@"),
        String(localized: "Priority Fee: %.2f gwei"),
        String(localized: "Priority: %@"),
        String(localized: "Received invalid Bitcoin Cash UTXO data."),
        String(localized: "Received invalid Bitcoin SV UTXO data."),
        String(localized: "Received invalid Litecoin UTXO data."),
        String(localized: "Reference Gas Price: %llu"),
        String(localized: "Refresh Aptos"),
        String(localized: "Refresh Arbitrum"),
        String(localized: "Refresh Avalanche"),
        String(localized: "Refresh Bitcoin"),
        String(localized: "Refresh BNB Chain"),
        String(localized: "Refresh Cardano"),
        String(localized: "Refresh Dogecoin"),
        String(localized: "Refresh Ethereum"),
        String(localized: "Refresh Ethereum Classic"),
        String(localized: "Refresh Hyperliquid"),
        String(localized: "Refresh Internet Computer"),
        String(localized: "Refresh Litecoin"),
        String(localized: "Refresh Monero"),
        String(localized: "Refresh NEAR"),
        String(localized: "Refresh Optimism"),
        String(localized: "Refresh Polkadot"),
        String(localized: "Refresh Solana"),
        String(localized: "Refresh Stellar"),
        String(localized: "Refresh Sui"),
        String(localized: "Refresh TON"),
        String(localized: "Refresh Tron"),
        String(localized: "Refresh XRP"),
        String(localized: "Refreshing Aptos..."),
        String(localized: "Refreshing Arbitrum..."),
        String(localized: "Refreshing Avalanche..."),
        String(localized: "Refreshing Bitcoin..."),
        String(localized: "Refreshing BNB Chain..."),
        String(localized: "Refreshing Cardano..."),
        String(localized: "Refreshing Dogecoin..."),
        String(localized: "Refreshing Ethereum Classic..."),
        String(localized: "Refreshing Ethereum..."),
        String(localized: "Refreshing Hyperliquid..."),
        String(localized: "Refreshing Internet Computer..."),
        String(localized: "Refreshing Litecoin..."),
        String(localized: "Refreshing Monero..."),
        String(localized: "Refreshing NEAR..."),
        String(localized: "Refreshing Optimism..."),
        String(localized: "Refreshing Polkadot..."),
        String(localized: "Refreshing Solana..."),
        String(localized: "Refreshing Stellar..."),
        String(localized: "Refreshing Sui..."),
        String(localized: "Refreshing TON..."),
        String(localized: "Refreshing Tron..."),
        String(localized: "Refreshing XRP..."),
        String(localized: "Reserved receive index: %lld"),
        String(localized: "Selected Inputs: %lld"),
        String(localized: "send.preview.nonceLabel"),
        String(localized: "Sequence Number: %u"),
        String(localized: "Sequence: %lld"),
        String(localized: "Solana broadcast failed: %@"),
        String(localized: "Spectra signs and broadcasts Dogecoin in-app. The preview shows estimated network fee and max sendable DOGE for this wallet."),
        String(localized: "Spectra signs and broadcasts supported %@ transfers. This preview is the live nonce and fee estimate for the transaction you are about to send."),
        String(localized: "Spendable Balance: %.6f DOGE"),
        String(localized: "Spendable Balance: %@"),
        String(localized: "Status via Blockchair"),
        String(localized: "Status via BlockCypher"),
        String(localized: "Stellar broadcast failed: %@"),
        String(localized: "Stellar network request failed: %@"),
        String(localized: "Sui broadcast failed: %@"),
        String(localized: "Sui network request failed: %@"),
        String(localized: "Sui RPC error: %@"),
        String(localized: "The amount is not valid for this Aptos transfer."),
        String(localized: "The amount is not valid for this ICP transfer."),
        String(localized: "The amount is not valid for this NEAR transfer."),
        String(localized: "The amount is not valid for this Polkadot transfer."),
        String(localized: "The amount is not valid for this Solana transfer."),
        String(localized: "The amount is not valid for this Stellar transfer."),
        String(localized: "The amount is not valid for this Sui transfer."),
        String(localized: "The amount is not valid for this TON transfer."),
        String(localized: "The amount is not valid for this Tron transfer."),
        String(localized: "The amount is not valid for this XRP transfer."),
        String(localized: "The Aptos address is not valid."),
        String(localized: "The Aptos provider response was invalid."),
        String(localized: "The Aptos seed phrase is invalid."),
        String(localized: "The Bitcoin Cash destination address is invalid."),
        String(localized: "The Bitcoin Cash seed phrase is invalid."),
        String(localized: "The Bitcoin SV destination address is invalid."),
        String(localized: "The Bitcoin SV seed phrase is invalid."),
        String(localized: "The Cardano address is not valid."),
        String(localized: "The Cardano amount is not valid."),
        String(localized: "The Cardano provider response was invalid."),
        String(localized: "The Cardano seed phrase is invalid."),
        String(localized: "The Ethereum address is not valid."),
        String(localized: "The ICP provider response was invalid."),
        String(localized: "The ICP seed phrase is invalid."),
        String(localized: "The Litecoin destination address is invalid."),
        String(localized: "The Litecoin seed phrase is invalid."),
        String(localized: "The Monero address is not valid."),
        String(localized: "The Monero amount is not valid."),
        String(localized: "The Monero backend response was invalid."),
        String(localized: "The NEAR address is not valid."),
        String(localized: "The NEAR provider response was invalid."),
        String(localized: "The NEAR seed phrase is invalid."),
        String(localized: "The Polkadot address is not valid."),
        String(localized: "The Polkadot provider response was invalid."),
        String(localized: "The Polkadot seed phrase is invalid."),
        String(localized: "The Solana address is not valid."),
        String(localized: "The Solana provider response was invalid."),
        String(localized: "The Solana seed phrase is invalid."),
        String(localized: "The source Bitcoin Cash address does not match the provided seed phrase."),
        String(localized: "The source Bitcoin SV address does not match the provided seed phrase."),
        String(localized: "The source Litecoin address does not match the provided seed phrase."),
        String(localized: "The Stellar address is not valid."),
        String(localized: "The Stellar provider response was invalid."),
        String(localized: "The Stellar seed phrase is invalid."),
        String(localized: "The Sui address is not valid."),
        String(localized: "The Sui provider response was invalid."),
        String(localized: "The Sui seed phrase is invalid."),
        String(localized: "The TON address is not valid."),
        String(localized: "The TON provider response was invalid."),
        String(localized: "The TON seed phrase is invalid."),
        String(localized: "The Tron address is not valid."),
        String(localized: "The Tron provider response was invalid."),
        String(localized: "The Tron seed phrase is invalid."),
        String(localized: "The XRP address is not valid."),
        String(localized: "The XRP provider response was invalid."),
        String(localized: "The XRP seed phrase is invalid."),
        String(localized: "These networks use dynamic fee estimation from providers and do not expose a manual priority setting in this build."),
        String(localized: "TON broadcast failed: %@"),
        String(localized: "TON network request failed: %@"),
        String(localized: "TON RPC error: %@"),
        String(localized: "TTL Slot: %lld"),
        String(localized: "TTL Slot: %llu"),
        String(localized: "word %lld"),
        String(localized: "XRP broadcast failed: %@"),
        String(localized: "XRP network request failed: %@"),
    ]
}

enum StaticContentCatalog {
    private final class BundleMarker {}
    private static let decoder = JSONDecoder()
    private static let localizationRootDirectoryName = "Localization"
    private static let rustLocalizedResources: Set<String> = [
        "ChainWikiEntries",
        "CommonContent",
        "DiagnosticsContent",
        "DonationsContent",
        "EndpointsContent",
        "ImportFlowContent",
        "SettingsContent"
    ]
    private static let candidateBundles: [Bundle] = {
        var seen = Set<URL>()
        return ([Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            guard let bundleURL = bundle.bundleURL.standardizedFileURL as URL? else {
                return false
            }
            return seen.insert(bundleURL).inserted
        }
    }()
    private static var resourceURLCache: [String: URL] = [:]
    private static var decodedResourceCache: [String: Any] = [:]
    private static var textResourceCache: [String: String] = [:]
    private static var localizedResourceIndexCache: [String: [String: URL]] = [:]
    private static var flatResourceIndexCache: [String: URL]?

    static func loadResource<T: Decodable>(_ resourceName: String, as type: T.Type) -> T? {
        let cacheKey = "\(localizationCacheKeyPrefix())|json|\(resourceName)|\(String(reflecting: type))"
        if let cachedValue = decodedResourceCache[cacheKey] as? T {
            return cachedValue
        }
        if rustLocalizedResources.contains(resourceName),
           let data = try? WalletRustAppCoreBridge.localizedDocumentData(
            named: resourceName,
            preferredLocales: preferredLocalizationIdentifiers()
           ),
           let decodedValue = try? decoder.decode(type, from: data) {
            decodedResourceCache[cacheKey] = decodedValue
            return decodedValue
        }
        guard let url = resourceURL(named: resourceName),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let decodedValue = try? decoder.decode(type, from: data) else {
            return nil
        }
        decodedResourceCache[cacheKey] = decodedValue
        return decodedValue
    }

    static func loadRequiredResource<T: Decodable>(_ resourceName: String, as type: T.Type) -> T {
        guard let value = loadResource(resourceName, as: type) else {
            fatalError("Missing required bundled resource: \(resourceName).json")
        }
        return value
    }

    static func loadTextResource(_ resourceName: String, extension fileExtension: String = "txt") -> String? {
        let cacheKey = "\(localizationCacheKeyPrefix())|text|\(resourceName)|\(fileExtension)"
        if let cachedValue = textResourceCache[cacheKey] {
            return cachedValue
        }
        guard let url = resourceURL(named: resourceName, fileExtension: fileExtension) else {
            return nil
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        textResourceCache[cacheKey] = text
        return text
    }

    static func loadRequiredTextResource(_ resourceName: String, extension fileExtension: String = "txt") -> String {
        guard let value = loadTextResource(resourceName, extension: fileExtension) else {
            fatalError("Missing required bundled resource: \(resourceName).\(fileExtension)")
        }
        return value
    }

    private static func resourceURL(named resourceName: String) -> URL? {
        resourceURL(named: resourceName, fileExtension: "json")
    }

    private static func resourceURL(named resourceName: String, fileExtension: String) -> URL? {
        for localizationIdentifier in preferredLocalizationIdentifiers() {
            let expectedFilename = localizedFilename(
                resourceName: resourceName,
                localizationIdentifier: localizationIdentifier,
                fileExtension: fileExtension
            )
            let cacheKey = "\(localizationRootDirectoryName)/\(localizationIdentifier)/\(expectedFilename)"
            if let cachedURL = resourceURLCache[cacheKey] {
                return cachedURL
            }

            let localizedIndex = localizedResourceIndex(for: localizationIdentifier)
            if let indexedURL = localizedIndex[expectedFilename] {
                resourceURLCache[cacheKey] = indexedURL
                return indexedURL
            }

            for bundle in candidateBundles {
                guard let resourceRootURL = bundle.resourceURL else { continue }
                let candidateURL = resourceRootURL
                    .appendingPathComponent(localizationRootDirectoryName, isDirectory: true)
                    .appendingPathComponent(localizationIdentifier, isDirectory: true)
                    .appendingPathComponent(expectedFilename, isDirectory: false)
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    resourceURLCache[cacheKey] = candidateURL
                    return candidateURL
                }

                if let enumerator = FileManager.default.enumerator(
                    at: resourceRootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator where fileURL.lastPathComponent == expectedFilename {
                        resourceURLCache[cacheKey] = fileURL
                        return fileURL
                    }
                }
            }
        }

        let expectedFilename = "\(resourceName).\(fileExtension)"
        let flatCacheKey = expectedFilename
        if let cachedURL = resourceURLCache[flatCacheKey] {
            return cachedURL
        }

        let flatIndex = flatResourceIndex()
        if let indexedURL = flatIndex[expectedFilename] {
            resourceURLCache[flatCacheKey] = indexedURL
            return indexedURL
        }

        for bundle in candidateBundles {
            if let url = bundle.url(forResource: resourceName, withExtension: fileExtension) {
                resourceURLCache[flatCacheKey] = url
                return url
            }
            if let resourceURL = bundle.resourceURL,
               let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
               ) {
                for case let fileURL as URL in enumerator where fileURL.lastPathComponent == expectedFilename {
                    resourceURLCache[flatCacheKey] = fileURL
                    return fileURL
                }
            }
        }

        return nil
    }

    private static func localizedFilename(
        resourceName: String,
        localizationIdentifier: String,
        fileExtension: String
    ) -> String {
        if localizationIdentifier == "Base" {
            return "\(resourceName).\(fileExtension)"
        }
        return "\(resourceName).\(localizationIdentifier).\(fileExtension)"
    }

    private static func preferredLocalizationIdentifiers() -> [String] {
        AppLocalization.preferredLocalizationIdentifiers()
    }

    private static func localizationCacheKeyPrefix() -> String {
        preferredLocalizationIdentifiers().joined(separator: "|")
    }

    private static func localizedResourceIndex(for localizationIdentifier: String) -> [String: URL] {
        if let cachedIndex = localizedResourceIndexCache[localizationIdentifier] {
            return cachedIndex
        }

        var index: [String: URL] = [:]
        for bundle in candidateBundles {
            guard let resourceRootURL = bundle.resourceURL else { continue }

            let directLocalizationRoot = resourceRootURL
                .appendingPathComponent(localizationRootDirectoryName, isDirectory: true)
                .appendingPathComponent(localizationIdentifier, isDirectory: true)

            if let enumerator = FileManager.default.enumerator(
                at: directLocalizationRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    index[fileURL.lastPathComponent] = fileURL
                }
                continue
            }

            if let enumerator = FileManager.default.enumerator(
                at: resourceRootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                let localizedSuffix = ".\(localizationIdentifier)."
                for case let fileURL as URL in enumerator where fileURL.lastPathComponent.contains(localizedSuffix) {
                    index[fileURL.lastPathComponent] = fileURL
                }
            }
        }

        localizedResourceIndexCache[localizationIdentifier] = index
        return index
    }

    private static func flatResourceIndex() -> [String: URL] {
        if let cachedIndex = flatResourceIndexCache {
            return cachedIndex
        }

        var index: [String: URL] = [:]
        for bundle in candidateBundles {
            if let resourceRootURL = bundle.resourceURL,
               let enumerator = FileManager.default.enumerator(
                at: resourceRootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
               ) {
                for case let fileURL as URL in enumerator {
                    index[fileURL.lastPathComponent] = fileURL
                }
            }
        }

        flatResourceIndexCache = index
        return index
    }

    private static func localizationFallbacks(for identifier: String) -> [String] {
        let components = identifier
            .split(separator: "-")
            .map(String.init)

        guard !components.isEmpty else { return [] }

        var fallbacks: [String] = []
        for index in stride(from: components.count, through: 1, by: -1) {
            fallbacks.append(components.prefix(index).joined(separator: "-"))
        }
        return fallbacks
    }
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
