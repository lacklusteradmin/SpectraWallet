import Foundation
import XCTest
@testable import Spectra

@MainActor
final class DiagnosticsBundleTests: XCTestCase {
    func testExportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = WalletStore()
        let fileURL = try store.exportDiagnosticsBundle()
        let imported = try store.importDiagnosticsBundle(from: fileURL)

        XCTAssertEqual(imported.schemaVersion, 1)
        XCTAssertFalse(imported.environment.osVersion.isEmpty)
        XCTAssertFalse(imported.bitcoinDiagnosticsJSON.isEmpty)
        XCTAssertFalse((imported.litecoinDiagnosticsJSON ?? "").isEmpty)
        XCTAssertFalse(imported.ethereumDiagnosticsJSON.isEmpty)
    }
}
