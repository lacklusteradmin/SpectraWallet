import Foundation
extension AppState {
    var operationalLogs: [DiagnosticLog] { diagnostics.operationalLogs }
    var chainDegradedBanners: [ChainDegradedBanner] { diagnostics.chainDegradedBanners }
    /// A family's diagnostics as core recorded them, on the network it is on.
    func chainDiagnostics(for chain: Chain) async throws -> ChainDiagnostics {
        try await bridge.ready().chainDiagnostics(chain: chain)
    }
}
