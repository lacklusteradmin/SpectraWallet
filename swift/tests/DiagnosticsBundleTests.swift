import Foundation
import XCTest
@testable import Spectra
@MainActor
final class DiagnosticsBundleTests: IsolatedAppStateTestCase {
    /// Core writes the bundle; the file the app shares reads back whole.
    func testExportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = makeState()
        let fileURL = try await store.exportDiagnosticsBundle()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        XCTAssertEqual(imported.schemaVersion, 2)
        XCTAssertFalse(imported.environment.osVersion.isEmpty)
        XCTAssertEqual(imported.environment.walletCount, 0)
        // Keys are canonical chain ids, one per mainnet.
        XCTAssertNotNil(imported.chainDiagnosticsJson["bitcoin-cash"])
        XCTAssertNotNil(imported.chainDiagnosticsJson["internet-computer"])
        XCTAssertEqual(Set(imported.chainDiagnosticsJson.keys), Set(Chain.mainnets.map(\.id)))
    }

    /// The screen's document is the one the bundle carries for that chain.
    func testChainDiagnosticsMatchTheBundle() async throws {
        let store = makeState()
        let diagnostics = try await store.chainDiagnostics(for: .bitcoin)
        XCTAssertEqual(diagnostics.networkId, "bitcoin")
        let fileURL = try await store.exportDiagnosticsBundle()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        XCTAssertEqual(imported.chainDiagnosticsJson["bitcoin"], diagnostics.document)
    }
}
