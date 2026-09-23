import Foundation
import UIKit
import XCTest

@testable import Spectra

/// Verify the identity-based core lookup reaches real bundled images through Swift.
@MainActor
final class CoinBadgeArtworkTests: XCTestCase {
    /// A mark that is named has to load; a coin that names none draws its
    /// letter, which `CoinBadge` does for an empty name. The catalog carries
    /// tokens with no artwork on purpose, so "not nil" alone would fail on a
    /// row that is behaving correctly.
    private func assertDrawsItsMark(_ badge: CoinBadge, _ what: @autoclosure () -> String) {
        guard !badge.artworkName.isEmpty else { return }
        XCTAssertNotNil(UIImage(named: badge.artworkName), "\(what()) drew a letter, not its mark")
    }

    func testCatalogTokenIdentityLoadsItsArtwork() {
        for entry in CoreReferenceTables.assetWiki() {
            let badge = CoinBadge(artworkName: entry.face.artworkName, fallbackText: entry.symbol, color: .orange)
            assertDrawsItsMark(badge, entry.symbol)
        }
    }

    func testHeldDeploymentsUseTheirOwnArtwork() {
        for token in listAllBuiltinTokenDeployments() {
            let holding = AssetHolding(
                name: token.name, symbol: token.symbol, coingeckoId: token.coingeckoId,
                chainName: Chain(id: token.chainId)?.displayName ?? token.chainId, tokenStandard: token.tokenStandard,
                contractAddress: token.contract.isEmpty ? nil : token.contract, amount: 0, priceUsd: 0)
            let badge = CoinBadge(artworkName: holding.artworkName, fallbackText: token.symbol, color: .orange)
            XCTAssertEqual(badge.artworkName, token.artworkName, token.deploymentId)
            assertDrawsItsMark(badge, token.deploymentId)
        }
        XCTAssertEqual(AssetPresentationCatalog.artwork(deploymentId: "base:native"), "ethereum")
        XCTAssertEqual(AssetPresentationCatalog.artwork(deploymentId: nil), "")
    }

    /// Network wiki artwork must also reach real bundled images.
    func testEveryNetworkWikiFaceLoadsItsMark() {
        for chain in CoreReferenceTables.chainWiki() {
            let badge = CoinBadge(
                artworkName: chain.face.artworkName, fallbackText: chain.name, color: .orange)
            XCTAssertNotNil(
                UIImage(named: badge.artworkName), "\(chain.name)'s wiki face drew a letter")
        }
    }

    /// A chain's own ticker draws the chain, not the coin it pays fees in.
    /// Base's gas is ETH, so these two live side by side and the badge must
    /// keep them apart — the direction the fix could have overshot in.
    func testAChainBadgeStillDrawsTheChain() throws {
        for chain in Chain.all {
            let native = try XCTUnwrap(Coin.nativeChainBadge(chainName: chain.displayName), chain.displayName)
            let badge = CoinBadge(
                artworkName: native.artworkName, fallbackText: chain.gasTokenSymbol, color: native.color)
            XCTAssertNotNil(UIImage(named: badge.artworkName), "\(chain.displayName) drew a letter")
        }
        let base = CoinBadge(
            artworkName: Chain(id: "base")?.entry?.artworkName,
            fallbackText: "BASE", color: .orange)
        let etherOnBase = CoinBadge(
            artworkName: AssetHolding(name: "", symbol: "ETH", coingeckoId: "", chainName: "Base", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 0).artworkName,
            fallbackText: "ETH", color: .orange)
        XCTAssertEqual(base.artworkName, "base")
        XCTAssertEqual(etherOnBase.artworkName, "ethereum")
    }

    /// A custom contract cannot borrow USDC artwork by copying its symbol.
    func testAnUnknownCoinFallsBackToItsLetter() {
        let unknown = CoinBadge(
            artworkName: AssetHolding(name: "USD Coin", symbol: "USDC", coingeckoId: "usd-coin", chainName: "Ethereum", tokenStandard: "ERC-20", contractAddress: "0xdead", amount: 0, priceUsd: 0).artworkName,
            fallbackText: "USDCE", color: .orange)
        XCTAssertEqual(unknown.artworkName, "")
    }
    func testCachedIdentityAndArtworkIgnoreBalanceAndTickerButKeepNetwork() {
        var coin = AssetHolding(name: "Ether", symbol: "ETH", coingeckoId: "ethereum", chainName: "Base",
            tokenStandard: "Native", contractAddress: nil, amount: 1, priceUsd: 2)
        let id = coin.holdingKey
        XCTAssertEqual(coin.artworkName, "ethereum")
        coin.amount = 10
        coin.priceUsd = 20
        coin.symbol = "USDC"
        coin.name = "Changed label"
        XCTAssertEqual(coin.holdingKey, id)
        XCTAssertEqual(coin.artworkName, "ethereum")
        coin.chainName = "Ethereum"
        XCTAssertNotEqual(coin.holdingKey, id)
        coin.tokenStandard = "ERC-20"
        coin.contractAddress = "0x1111111111111111111111111111111111111111"
        XCTAssertEqual(coin.artworkName, "", "An unknown deployment cannot borrow the ticker's artwork")
    }
}
