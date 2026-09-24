import Foundation

@MainActor
extension AppState {
    /// Core resolves the selected network and effective RPC before running diagnostics.
    func runSelfTests(for chain: Chain) async {
        guard !self[selfTestsFor: chain].isRunning else { return }
        self[selfTestsFor: chain].isRunning = true
        let results: [ChainSelfTestResult]
        do {
            results = try await self.bridge.runConfiguredSelfTests(chainId: chain.id).results
        } catch {
            appendOperationalLog(.error, category: "Self-Tests", message: error.localizedDescription, chainId: chain.id)
            self[selfTestsFor: chain] = .init(results: [ChainSelfTestResult(
                name: chain.displayName, passed: false, chainLabel: chain.displayName,
                outcome: .custom(text: error.localizedDescription))], isRunning: false, lastRunAt: Date())
            return
        }
        self[selfTestsFor: chain] = .init(results: results, isRunning: false, lastRunAt: Date())

        let failedCount = results.filter { !$0.passed }.count
        appendOperationalLog(
            failedCount == 0 ? .info : .warning, category: "Self-Tests",
            message: failedCount == 0
                ? "\(chain.gasTokenSymbol) self-tests passed (\(results.count) checks)."
                : "\(chain.gasTokenSymbol) self-tests completed with \(failedCount) failure(s).",
            chainId: chain.id)
    }
    func operationalEvents(for chain: Chain) async -> [DiagnosticLog] {
        await self.bridge.operationalEvents(chainId: chain.id)
    }
    func runUTXORescan(chain: Chain) async {
        guard !self[rescanFor: chain].isRunning else { return }
        self[rescanFor: chain].isRunning = true
        defer { self[rescanFor: chain].isRunning = false }
        appendOperationalLog(.info, category: "Rescan", message: "\(chain.gasTokenSymbol) rescan started.", chainId: chain.id)
        if await performCoreRefresh(.deepRescan(chainId: chain.id)) {
            self[rescanFor: chain].lastRunAt = Date()
            appendOperationalLog(.info, category: "Rescan", message: "\(chain.gasTokenSymbol) rescan completed.", chainId: chain.id)
        } else {
            appendOperationalLog(
                .warning, category: "Rescan",
                message: "\(chain.gasTokenSymbol) rescan failed or completed partially. See refresh errors.", chainId: chain.id)
        }
    }
}
