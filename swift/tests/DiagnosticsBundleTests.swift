import Foundation
import Testing
@testable import Spectra
@MainActor
@Suite(.isolatedAppState)
struct DiagnosticsBundleTests: IsolatedAppStateSuite {
    /// Core writes the bundle; the file the app shares reads back whole.
    @Test func exportsAndImportsDiagnosticsBundleJSON() async throws {
        let store = makeState()
        let fileURL = try await store.exportDiagnosticsBundle()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        #expect(imported.schemaVersion == 2)
        #expect(!imported.environment.osVersion.isEmpty)
        #expect(imported.environment.walletCount == 0)
        // Keys are canonical chain ids, one per mainnet.
        #expect(imported.chainDiagnosticsJson["bitcoin-cash"] != nil)
        #expect(imported.chainDiagnosticsJson["internet-computer"] != nil)
        #expect(Set(imported.chainDiagnosticsJson.keys) == Set(Chain.mainnets.map(\.id)))
    }

    /// The screen's document is the one the bundle carries for that chain.
    @Test func chainDiagnosticsMatchTheBundle() async throws {
        let store = makeState()
        let diagnostics = try await store.chainDiagnostics(for: .bitcoin)
        #expect(diagnostics.networkId == .bitcoin)
        let fileURL = try await store.exportDiagnosticsBundle()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let imported = try store.importDiagnosticsBundle(from: fileURL)
        #expect(imported.chainDiagnosticsJson["bitcoin"] == diagnostics.document)
    }
}
