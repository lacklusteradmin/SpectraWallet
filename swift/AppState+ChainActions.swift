import Foundation

@MainActor
extension AppState {
    /// Core resolves the selected network and effective RPC before running diagnostics.
    func runSelfTests(for chainName: String) async {
        guard !selfTests(for: chainName).isRunning else { return }
        selfTests[chainName, default: .init()].isRunning = true
        defer { selfTests[chainName, default: .init()].isRunning = false }
        let results: [ChainSelfTestResult]
        do {
            guard let chain = Chain(displayName: chainName) else { return }
            let report = try await WalletServiceBridge.shared.runConfiguredSelfTests(chainID: chain.id)
            results = report.results
        } catch {
            appendChainOperationalEvent(.error, chainName: chainName, message: error.localizedDescription)
            selfTests[chainName] = .init(results: [ChainSelfTestResult(
                name: chainName, passed: false, chainLabel: chainName,
                outcome: .custom(text: error.localizedDescription))], isRunning: true, lastRunAt: Date())
            return
        }
        selfTests[chainName] = .init(results: results, isRunning: true, lastRunAt: Date())

        let failedCount = results.filter { !$0.passed }.count
        let abbrev = Chain(displayName: chainName)?.gasTokenSymbol ?? chainName
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: chainName,
            message: failedCount == 0
                ? "\(abbrev) self-tests passed (\(results.count) checks)."
                : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func operationalEvents(for chainName: String) async -> [DiagnosticLog] {
        await WalletServiceBridge.shared.operationalEvents(chainName: chainName)
    }
    func runUTXORescan(chainName: String) async {
        guard let chain = Chain(displayName: chainName), !self[rescanFor: chainName].isRunning else { return }
        self[rescanFor: chainName].isRunning = true
        defer { self[rescanFor: chainName].isRunning = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan started.")
        if await performCoreRefresh(.deepRescan(chainId: chain.id)) {
            self[rescanFor: chainName].lastRunAt = Date()
            appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan completed.")
        } else {
            appendChainOperationalEvent(.warning, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan failed or completed partially. See refresh errors.")
        }
    }
}
