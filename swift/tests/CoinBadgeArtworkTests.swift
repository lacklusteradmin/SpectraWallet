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
        guard !badge.assetName.isEmpty else { return }
        XCTAssertNotNil(UIImage(named: badge.assetName), "\(what()) drew a letter, not its mark")
    }

    func testCatalogTokenIdentityLoadsItsArtwork() {
        for entry in CachedCoreHelpers.assetWiki() {
            let badge = CoinBadge(assetName: coreTokenIconAssetName(tokenId: entry.tokenId), fallbackText: entry.symbol, color: .orange)
            XCTAssertEqual(badge.assetName, entry.face.assetName)
            assertDrawsItsMark(badge, entry.symbol)
        }
    }

    func testHeldDeploymentsUseTheirOwnArtwork() {
        for token in listAllBuiltinTokens() {
            let holding = AssetHolding(
                name: token.name, symbol: token.symbol, coinGeckoId: token.coingeckoId,
                chainName: token.chain, tokenStandard: token.tokenStandard,
                contractAddress: token.contract.isEmpty ? nil : token.contract, amount: 0, priceUsd: 0)
            let badge = CoinBadge(assetName: holding.iconAssetName, fallbackText: token.symbol, color: .orange)
            XCTAssertEqual(badge.assetName, token.assetName, token.id)
            assertDrawsItsMark(badge, token.id)
        }
        XCTAssertEqual(coreDeploymentIconAssetName(deploymentId: "base:native"), "ethereum")
        XCTAssertEqual(coreDeploymentIconAssetName(deploymentId: nil), "")
    }

    /// Both wikis hand the badge core's own `assetName` rather than an
    /// identifier to take apart. That shortcut has to reach a real file too.
    func testEveryWikiFaceLoadsItsMark() {
        for entry in CachedCoreHelpers.assetWiki() {
            let badge = CoinBadge(
                assetName: entry.face.assetName, fallbackText: entry.symbol, color: .orange)
            assertDrawsItsMark(badge, "\(entry.symbol)'s wiki face")
        }
        for chain in CachedCoreHelpers.chainWiki() {
            let badge = CoinBadge(
                assetName: chain.face.assetName, fallbackText: chain.name, color: .orange)
            XCTAssertNotNil(
                UIImage(named: badge.assetName), "\(chain.name)'s wiki face drew a letter")
        }
    }

    /// A chain's own ticker draws the chain, not the coin it pays fees in.
    /// Base's gas is ETH, so these two live side by side and the badge must
    /// keep them apart — the direction the fix could have overshot in.
    func testAChainBadgeStillDrawsTheChain() {
        for descriptor in Coin.nativeChainIconDescriptors {
            let badge = CoinBadge(
                assetName: descriptor.artworkName, fallbackText: descriptor.symbol,
                color: descriptor.color)
            XCTAssertNotNil(UIImage(named: badge.assetName), "\(descriptor.title) drew a letter")
        }
        let base = CoinBadge(
            assetName: coreNetworkIconAssetName(networkId: "base"),
            fallbackText: "BASE", color: .orange)
        let etherOnBase = CoinBadge(
            assetName: coreHoldingIconAssetName(holding: AssetHolding(name: "", symbol: "ETH", coinGeckoId: "", chainName: "Base", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 0)),
            fallbackText: "ETH", color: .orange)
        XCTAssertEqual(base.assetName, "base")
        XCTAssertEqual(etherOnBase.assetName, "ethereum")
    }

    /// A custom contract cannot borrow USDC artwork by copying its symbol.
    func testAnUnknownCoinFallsBackToItsLetter() {
        let unknown = CoinBadge(
            assetName: coreHoldingIconAssetName(holding: AssetHolding(name: "USD Coin", symbol: "USDC", coinGeckoId: "usd-coin", chainName: "Ethereum", tokenStandard: "ERC-20", contractAddress: "0xdead", amount: 0, priceUsd: 0)),
            fallbackText: "USDCE", color: .orange)
        XCTAssertEqual(unknown.assetName, "")
    }
}
