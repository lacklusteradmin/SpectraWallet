import Foundation
import UIKit
import XCTest

@testable import Spectra

/// The badge draws a coin, and a coin is held wherever it is held.
///
/// This is the regression test for the bug the core-side ones do not reach.
/// `CoinBadge` resolved artwork through two Swift tables keyed on the *chain*,
/// so a coin held anywhere but its home chain fell through both and drew a
/// letter — thirty-one of the wiki's sixty-six coins, plus ETH on all nine of
/// its rollups. Every assertion below was red before that resolution moved to
/// `core_icon_asset_name`, and none of them can be satisfied by the catalogs
/// agreeing with themselves: the chain goes Swift identifier → core → asset
/// catalog → `UIImage`, and only a file on disk ends it.
@MainActor
final class CoinBadgeArtworkTests: XCTestCase {
    /// Every coin, on every chain it lives on, drawn the way the dashboard's
    /// per-chain breakdown rows draw it — `iconIdentifier(symbol:chainName:)`
    /// with no contract, which is what produced `native:aptos:usdc`.
    func testEveryCoinDrawsItselfOnEveryChainItLivesOn() {
        let wiki = CachedCoreHelpers.assetWiki()
        XCTAssertFalse(wiki.isEmpty, "the wiki is empty, so this asserts nothing")
        for entry in wiki {
            for place in entry.livesOn {
                let badge = CoinBadge(
                    assetIdentifier: Coin.iconIdentifier(symbol: entry.symbol, chainName: place.chainName),
                    fallbackText: entry.symbol, color: .orange)
                XCTAssertNotNil(
                    UIImage(named: badge.assetName),
                    "\(entry.symbol) on \(place.chainName) drew a letter, not its mark")
            }
        }
    }

    /// A held token carries its contract, so its identifier is `token:…` and
    /// takes a different branch. It has to land on the same mark.
    func testAHeldTokenDrawsTheSameMarkAsItsWikiRow() {
        for entry in CachedCoreHelpers.assetWiki() {
            for place in entry.livesOn where !place.contract.isEmpty {
                let held = CoinBadge(
                    assetIdentifier: Coin.iconIdentifier(
                        symbol: entry.symbol, chainName: place.chainName,
                        contractAddress: place.contract, tokenStandard: place.tokenStandard),
                    fallbackText: entry.symbol, color: .orange)
                XCTAssertEqual(
                    held.assetName, entry.face.assetName,
                    "\(entry.symbol) on \(place.chainName) draws one mark held and another in the wiki")
                XCTAssertNotNil(UIImage(named: held.assetName))
            }
        }
    }

    /// Both wikis hand the badge core's own `assetName` rather than an
    /// identifier to take apart. That shortcut has to reach a real file too.
    func testEveryWikiFaceLoadsItsMark() {
        for entry in CachedCoreHelpers.assetWiki() {
            let badge = CoinBadge(
                assetName: entry.face.assetName, fallbackText: entry.symbol, color: .orange)
            XCTAssertNotNil(UIImage(named: badge.assetName), "\(entry.symbol)'s wiki face drew a letter")
        }
        for chain in CachedCoreHelpers.chainWiki() {
            let badge = CoinBadge(
                assetName: chain.face.assetName, fallbackText: chain.symbol, color: .orange)
            XCTAssertNotNil(UIImage(named: badge.assetName), "\(chain.name)'s wiki face drew a letter")
        }
    }

    /// A chain's own ticker draws the chain, not the coin it pays fees in.
    /// Base's gas is ETH, so these two live side by side and the badge must
    /// keep them apart — the direction the fix could have overshot in.
    func testAChainBadgeStillDrawsTheChain() {
        for descriptor in Coin.nativeChainIconDescriptors {
            let badge = CoinBadge(
                assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol,
                color: descriptor.color)
            XCTAssertNotNil(UIImage(named: badge.assetName), "\(descriptor.title) drew a letter")
        }
        let base = CoinBadge(
            assetIdentifier: Coin.iconIdentifier(symbol: "BASE", chainName: "Base"),
            fallbackText: "BASE", color: .orange)
        let etherOnBase = CoinBadge(
            assetIdentifier: Coin.iconIdentifier(symbol: "ETH", chainName: "Base"),
            fallbackText: "ETH", color: .orange)
        XCTAssertEqual(base.assetName, "base")
        XCTAssertEqual(etherOnBase.assetName, "ethereum")
    }

    /// A coin nothing ships a mark for draws its letter rather than borrowing
    /// someone else's. The substring match this replaced would have handed a
    /// custom `USDCE` the USDC mark.
    func testAnUnknownCoinFallsBackToItsLetter() {
        let unknown = CoinBadge(
            assetIdentifier: Coin.iconIdentifier(
                symbol: "USDCE", chainName: "Ethereum", contractAddress: "0xdead", tokenStandard: "ERC-20"),
            fallbackText: "USDCE", color: .orange)
        XCTAssertEqual(unknown.assetName, "")
    }
}
