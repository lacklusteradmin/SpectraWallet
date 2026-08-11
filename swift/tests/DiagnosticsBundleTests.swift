import Foundation
import XCTest
@testable import Spectra
@MainActor
final class DiagnosticsBundleTests: XCTestCase {
    func testExportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = AppState()
        let fileURL = try store.exportDiagnosticsBundle()
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        XCTAssertEqual(imported.schemaVersion, 1)
        XCTAssertFalse(imported.environment.osVersion.isEmpty)
        for chainName in ["Bitcoin", "Litecoin", "Ethereum"] {
            let json = imported.diagnosticsJSON(forChainNamed: chainName)
            XCTAssertNotNil(json, "\(chainName) missing from the bundle")
            XCTAssertFalse(json?.isEmpty ?? true, "\(chainName) diagnostics empty")
        }
        // Keys are canonical chain ids, not display names.
        XCTAssertNotNil(imported.chainDiagnosticsJson["bitcoin-cash"])
        XCTAssertNotNil(imported.chainDiagnosticsJson["internet-computer"])
        XCTAssertEqual(imported.chainDiagnosticsJson.count, 24)
    }
}
