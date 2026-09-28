import Foundation

@MainActor
extension AppState {
    /// Core resolves the selected network and effective RPC, runs the tests
    /// and logs their outcome, which the chain's operational events show.
    func runSelfTests(for chain: Chain) async {
        await chainDiagnosticsState.run(\.runningSelfTests, chainId: chain.id) {
            do {
                _ = try await self.bridge.ready().runConfiguredSelfTests(chainId: chain.id)
            } catch {
                self.appendOperationalLog(.error, category: "Self-Tests", message: error.localizedDescription, chainId: chain.id)
            }
            await self.diagnostics.loadFromSQLite()
        }
    }
    func operationalEvents(for chain: Chain) async -> [DiagnosticLog] {
        (try? await self.bridge.ready().operationalEvents(chainId: chain.id)) ?? []
    }
    /// Core runs the rescan and logs how it went.
    func runUTXORescan(chain: Chain) async {
        await chainDiagnosticsState.run(\.runningRescans, chainId: chain.id) {
            await self.performCoreRefresh(.deepRescan(chainId: chain.id))
        }
    }
}
