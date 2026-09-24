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

    /// One string table per declared locale, every table with the same keys —
    /// read from the manifest rather than listed here, so adding a locale
    /// cannot leave a table silently missing.
    func testEveryDeclaredLocaleShipsTheSameStringTable() throws {
        let locales = try declaredLocales()
        XCTAssertTrue(locales.contains("en"), "the source language must ship")
        let source = try Set(table("en").keys)
        for locale in locales {
            XCTAssertEqual(try Set(table(locale).keys), source, locale)
        }
    }

    /// Donation addresses are funds destinations: each must be a valid address
    /// on the chain it names, and there is one list for every language.
    func testDonationAddressesAreValidForTheirChains() {
        let destinations = DonationsContentCopy.current.destinations
        XCTAssertFalse(destinations.isEmpty)
        for destination in destinations {
            XCTAssertNotNil(Chain(id: destination.chainId), destination.chainId)
            XCTAssertTrue(isValidSendAddress(chainId: destination.chainId, address: destination.address), destination.chainId)
        }
    }

    /// A localized string ships in a locale's table and nothing else; a
    /// locale-independent data file ships once, unsuffixed.
    func testLocaleIndependentDataShipsOnce() {
        for name in ["AppLinks", "BuyProviders", "Donations"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "json"), name)
        }
        for name in ["CommonContent", "DiagnosticsContent", "DonationsContent",
                     "EndpointsContent", "ImportFlowContent", "SettingsContent"] {
            XCTAssertNil(Bundle.main.url(forResource: "\(name).en", withExtension: "json"), name)
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

    private func table(_ locale: String) throws -> [String: String] {
        let name = "RuntimeStrings.\(locale)"
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"), name)
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
}
