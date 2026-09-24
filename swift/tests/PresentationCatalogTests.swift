import SwiftUI
import XCTest
@testable import Spectra

final class PresentationCatalogTests: XCTestCase {
    func testTestnetSymbolsKeepTheirLowercasePrefix() {
        for chain in Chain.all where chain.isTestnet {
            XCTAssertEqual(chain.gasTokenSymbol, "t" + chain.mainnetCounterpart.gasTokenSymbol)
        }
        XCTAssertEqual(Chain(id: "bitcoin")?.gasTokenSymbol, "BTC")
        XCTAssertEqual(Chain(id: "bitcoin-testnet-4")?.gasTokenSymbol, "tBTC")
        XCTAssertEqual(Chain(id: "ethereum-sepolia")?.gasTokenSymbol, "tETH")
    }

    /// Colour follows deployment identity, never the ticker: a custom token
    /// that calls itself `ETH` is grey, not Ether's colour.
    func testCoinColorsFollowDeploymentIdentity() {
        for token in listTokenDeployments(chainId: "") {
            if let color = token.color {
                XCTAssertEqual(AssetPresentationCatalog.color(deploymentId: token.deploymentId), color.color)
            }
        }
        let ethereum = try? XCTUnwrap(Chain.ethereum.entry)
        XCTAssertEqual(AssetPresentationCatalog.color(deploymentId: ethereum?.nativeDeploymentId ?? ""), ethereum?.color.color)
        XCTAssertEqual(AssetPresentationCatalog.color(deploymentId: "ethereum:erc-20:0xnot-in-the-catalog"), .gray)
    }

    /// A native asset's display name is its chain's, so naming the pair
    /// unconditionally read "Solana on Solana". The subtitle spells the chain
    /// only when it is not already the asset, and the expectations are built
    /// from the shipped formats so the assertion is about that shape rather
    /// than about English.
    func testTransactionSubtitleNamesTheChainOnlyWhenItIsNotTheAsset() {
        let copy = CommonLocalizationContent.current
        func subtitle(asset: String, chainId: String) -> String {
            TransactionRecord(
                id: "tx", kind: .receive, status: .confirmed, walletName: "Main Wallet",
                assetDisplayName: asset, symbol: "SOL", chainId: chainId, amount: "0.1", address: "address"
            ).subtitleText
        }
        func wallet(_ asset: String) -> String { String(format: copy.transactionSubtitleFormat, asset, "Main Wallet") }
        func onChain(_ asset: String, _ chain: String) -> String { String(format: copy.assetOnChainFormat, asset, chain) }

        XCTAssertEqual(subtitle(asset: "Solana", chainId: "solana"), wallet("Solana"))
        XCTAssertEqual(subtitle(asset: "solana", chainId: "solana"), wallet("solana"))
        XCTAssertEqual(subtitle(asset: "USD Coin", chainId: "solana"), wallet(onChain("USD Coin", "Solana")))
        XCTAssertEqual(
            subtitle(asset: "Bitcoin", chainId: "bitcoin-testnet-4"),
            wallet(onChain("Bitcoin", Chain.displayName(forId: "bitcoin-testnet-4"))))
    }

    /// Every localized content file decodes in every locale the manifest
    /// declares — read from the manifest rather than listed here, so adding a
    /// locale cannot leave a file silently untested.
    func testBundledCopyDecodesInEveryDeclaredLocale() throws {
        let locales = try declaredLocales()
        XCTAssertTrue(locales.contains("en"), "the source language must ship")
        for locale in locales {
            try decode("CommonContent", locale: locale, as: CommonLocalizationContent.self)
            try decode("DiagnosticsContent", locale: locale, as: DiagnosticsContentCopy.self)
            try decode("DonationsContent", locale: locale, as: DonationsContentCopy.self)
            try decode("EndpointsContent", locale: locale, as: EndpointsContentCopy.self)
            try decode("ImportFlowContent", locale: locale, as: ImportFlowContent.self)
            try decode("SettingsContent", locale: locale, as: SettingsContentCopy.self)
        }
    }

    /// A localized file ships per locale and nothing else; a locale-independent
    /// one ships unsuffixed and nothing else.
    ///
    /// `StaticContentCatalog` tries `<name>.<locale>.json` first and falls back
    /// to `<name>.json`, which is how `AppLinks` and `BuyProviders` — URLs and
    /// provider lists, the same in every language — are found. The fallback
    /// also meant six localized files could ship an unsuffixed byte-identical
    /// copy of their `.en` twin without anything reading it: `en` always
    /// resolves first, because `preferredLocalizationIdentifiers` appends the
    /// manifest's `sourceLanguage` before it ever reaches `Base`. Two copies of
    /// one string, one of them unreachable, is the drift `resources/` is flat
    /// to avoid — so the absence is asserted rather than left to be noticed.
    func testLocalizedCopyShipsPerLocaleAndNothingElse() throws {
        for name in ["CommonContent", "DiagnosticsContent", "DonationsContent",
                     "EndpointsContent", "ImportFlowContent", "SettingsContent"] {
            XCTAssertNil(
                Bundle.main.url(forResource: name, withExtension: "json"),
                "\(name).json shadows \(name).en.json and is never read"
            )
        }
        for name in ["AppLinks", "BuyProviders"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "json"), name)
        }
    }

    private struct Manifest: Decodable {
        let availableLocales: [String]
    }

    private func declaredLocales() throws -> [String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "RuntimeStrings.manifest", withExtension: "json"),
            "RuntimeStrings.manifest.json"
        )
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).availableLocales
    }

    private func decode<T: Decodable>(_ name: String, locale: String, as type: T.Type) throws {
        let filename = "\(name).\(locale)"
        let url = try XCTUnwrap(Bundle.main.url(forResource: filename, withExtension: "json"), filename)
        _ = try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
