import Foundation
import XCTest

@testable import Spectra

/// The diagnostics code used to write the same twenty-four chains down six
/// times: `StandardDiagnosticsChain`, `chainDiagDescriptors`, `dispatchTable`,
/// `utxoActions`, `diagnosticsBundleChainNames` and the `diagnosticsJSON(for:)`
/// switch. Five of those are gone — the chain list is `Chain.mainnets` and the
/// per-chain differences (`diagnosticsShape`, the native ticker, the display
/// name) are registry columns — so the tests that pinned the copies together
/// have nothing left to pin.
///
/// What survives is the one table that is still hand-written:
/// `chainDiagDescriptors`, which overrides the generic drivers for the chains
/// whose history diagnostics are not generic. It is keyed by `Chain`, so it
/// cannot name a chain that does not exist; it can still name one no screen
/// ever reaches.
@MainActor
final class DiagnosticsChainTableTests: XCTestCase {
    func testEveryRunDescriptorNamesAChainTheHubOffers() {
        let offered = Set(Chain.mainnets)
        for chain in AppState.chainDiagDescriptors.keys {
            XCTAssertTrue(
                offered.contains(chain),
                "chainDiagDescriptors overrides \(chain.displayName), which has no screen")
        }
    }

    /// The hub, the export bundle and the per-chain screens have to be reading
    /// the same list. They are the same expression now; this fails if one of
    /// them is edited back into a copy.
    func testTheBundleListIsTheChainsTheHubOffers() {
        XCTAssertEqual(AppState.diagnosticsBundleChainNames, Chain.mainnets.map(\.displayName))
        XCTAssertEqual(
            Set(AppState.diagnosticsBundleChainNames).count,
            AppState.diagnosticsBundleChainNames.count,
            "duplicate chain in the bundle list")
    }
}
