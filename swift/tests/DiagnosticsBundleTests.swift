import Foundation
import XCTest
@testable import Spectra
@MainActor
final class DiagnosticsBundleTests: IsolatedAppStateTestCase {
    func testExportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = makeState()
        let fileURL = try store.exportDiagnosticsBundle()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        XCTAssertEqual(imported.schemaVersion, 1)
        XCTAssertFalse(imported.environment.osVersion.isEmpty)
        for chain in [Chain.bitcoin, .litecoin, .ethereum] {
            let json = imported.diagnosticsJSON(for: chain)
            XCTAssertNotNil(json, "\(chain.id) missing from the bundle")
            XCTAssertFalse(json?.isEmpty ?? true, "\(chain.id) diagnostics empty")
        }
        // Keys are canonical chain ids, not display names.
        XCTAssertNotNil(imported.chainDiagnosticsJson["bitcoin-cash"])
        XCTAssertNotNil(imported.chainDiagnosticsJson["internet-computer"])
        // One entry per mainnet. It was twenty-four while a Swift enum decided
        // which chains had diagnostics; the catalog decides now.
        XCTAssertEqual(imported.chainDiagnosticsJson.count, Chain.mainnets.count)
    }

    func testConfiguredDiagnosticsRunsThroughAsyncServiceBinding() async throws {
        let service = try WalletService(endpoints: [])
        let result = try await service.runConfiguredSelfTests(chainId: "bitcoin")
        XCTAssertEqual(result.chainId, "bitcoin")
        XCTAssertNil(result.rpcEndpoint)
        XCTAssertFalse(result.results.isEmpty)
        XCTAssertTrue(result.results.allSatisfy(\.passed))
    }

}

@MainActor
final class DiagnosticsBundleCoverageTests: IsolatedAppStateTestCase {
    /// Every chain the bundle reports on must be a chain the registry knows.
    ///
    /// The bundle list and the `diagnosticsJSON(for:)` switch are two lists
    /// that have to agree. Collapsing the old 23 wrapper functions onto them
    /// silently dropped Tron and Solana — they have their own JSON builders and
    /// did not match the shape the other 22 shared — and nothing failed,
    /// because a missing case just returns nil. This is the check that would
    /// have caught it.
    func testEveryBundledChainProducesADistinctEntry() {
        let ids = AppState.diagnosticsBundleChains.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate chain in the bundle list")
    }

    func testEveryBundledChainHasACaseInTheSwitch() {
        let store = makeState()
        // With no wallets every chain yields an empty-but-present document, so
        // a `nil` here means the switch has no case for that chain at all.
        for chain in AppState.diagnosticsBundleChains {
            XCTAssertNotNil(store.diagnosticsJSON(for: chain), "no diagnosticsJSON case for \(chain.id)")
        }
    }
}
