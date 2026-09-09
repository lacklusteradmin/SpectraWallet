import Foundation
import XCTest

@testable import Spectra

/// The diagnostics code used to write the same twenty-four chains down six
/// times: `StandardDiagnosticsChain`, `chainDiagDescriptors`, `dispatchTable`,
/// `utxoActions`, `diagnosticsBundleChainNames` and the `diagnosticsJSON(for:)`
/// switch. All of them are gone — the chain list is `Chain.mainnets`, the
/// per-chain differences (`diagnosticsShape`, the native ticker, the display
/// name) are registry columns, and the last table, `chainDiagDescriptors`, held
/// six rows that were the generic run written out — so the tests that pinned
/// the copies together have nothing left to pin.
@MainActor
final class DiagnosticsChainTableTests: XCTestCase {
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
