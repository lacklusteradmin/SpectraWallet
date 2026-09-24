import Foundation

@MainActor
extension AppState {
    /// Core resolves the selected network and effective RPC, runs the tests
    /// and logs their outcome.
    func runSelfTests(for chain: Chain) async {
        guard !self[selfTestsFor: chain].isRunning else { return }
        self[selfTestsFor: chain].isRunning = true
        let results: [ChainSelfTestResult]
        do {
            results = try await self.bridge.ready().runConfiguredSelfTests(chainId: chain.id).results
        } catch {
            appendOperationalLog(.error, category: "Self-Tests", message: error.localizedDescription, chainId: chain.id)
            results = [ChainSelfTestResult(
                name: chain.displayName, passed: false, chainLabel: chain.displayName,
                outcome: .custom(text: error.localizedDescription))]
        }
        self[selfTestsFor: chain] = .init(results: results, isRunning: false, lastRunAt: Date())
        await diagnostics.loadFromSQLite()
    }
    func operationalEvents(for chain: Chain) async -> [DiagnosticLog] {
        (try? await self.bridge.ready().operationalEvents(chainId: chain.id)) ?? []
    }
    /// Core runs the rescan and logs how it went.
    func runUTXORescan(chain: Chain) async {
        guard !self[rescanFor: chain].isRunning else { return }
        self[rescanFor: chain].isRunning = true
        defer { self[rescanFor: chain].isRunning = false }
        if await performCoreRefresh(.deepRescan(chainId: chain.id)) {
            self[rescanFor: chain].lastRunAt = Date()
        }
    }
}
