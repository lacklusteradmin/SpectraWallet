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
        for entry in CachedCoreHelpers.assetWiki() {
            let badge = CoinBadge(artworkName: coreTokenArtworkName(tokenId: entry.tokenId), fallbackText: entry.symbol, color: .orange)
            XCTAssertEqual(badge.artworkName, entry.face.artworkName)
            assertDrawsItsMark(badge, entry.symbol)
        }
    }

    func testHeldDeploymentsUseTheirOwnArtwork() {
        for token in listAllBuiltinTokens() {
            let holding = AssetHolding(
                name: token.name, symbol: token.symbol, coinGeckoId: token.coingeckoId,
                chainName: token.chain, tokenStandard: token.tokenStandard,
                contractAddress: token.contract.isEmpty ? nil : token.contract, amount: 0, priceUsd: 0)
            let badge = CoinBadge(artworkName: holding.artworkName, fallbackText: token.symbol, color: .orange)
            XCTAssertEqual(badge.artworkName, token.artworkName, token.id)
            assertDrawsItsMark(badge, token.id)
        }
        XCTAssertEqual(coreDeploymentArtworkName(deploymentId: "base:native"), "ethereum")
        XCTAssertEqual(coreDeploymentArtworkName(deploymentId: nil), "")
    }

    /// Network wiki artwork must also reach real bundled images.
    func testEveryNetworkWikiFaceLoadsItsMark() {
        for chain in CachedCoreHelpers.chainWiki() {
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
            artworkName: coreNetworkArtworkName(networkId: "base"),
            fallbackText: "BASE", color: .orange)
        let etherOnBase = CoinBadge(
            artworkName: coreHoldingArtworkName(holding: AssetHolding(name: "", symbol: "ETH", coinGeckoId: "", chainName: "Base", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 0)),
            fallbackText: "ETH", color: .orange)
        XCTAssertEqual(base.artworkName, "base")
        XCTAssertEqual(etherOnBase.artworkName, "ethereum")
    }

    /// A custom contract cannot borrow USDC artwork by copying its symbol.
    func testAnUnknownCoinFallsBackToItsLetter() {
        let unknown = CoinBadge(
            artworkName: coreHoldingArtworkName(holding: AssetHolding(name: "USD Coin", symbol: "USDC", coinGeckoId: "usd-coin", chainName: "Ethereum", tokenStandard: "ERC-20", contractAddress: "0xdead", amount: 0, priceUsd: 0)),
            fallbackText: "USDCE", color: .orange)
        XCTAssertEqual(unknown.artworkName, "")
    }
}
