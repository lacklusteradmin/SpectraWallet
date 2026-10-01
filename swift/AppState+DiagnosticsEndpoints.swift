import Foundation

// Swift holds which runs are in flight; core runs them and records what they found.
extension AppState {
    func runHistoryDiagnostics(for chain: Chain) async {
        await chainDiagnosticsState.run(\.runningHistory, chain: chain) {
            // No deadline of its own: a UniFFI call does not stop when its Swift
            // task is cancelled, and core's transport timeouts bound the run.
            await self.refreshHistory(chain: chain)
        }
    }

    /// Core probes the network the family is on and keeps the result.
    func runEndpointDiagnostics(for chain: Chain) async {
        await chainDiagnosticsState.run(\.checkingEndpoints, chain: chain) {
            do {
                _ = try await self.bridge.ready().probeChainEndpoints(chain: self.selectedChain(forFamily: chain))
            } catch {
                self.appendOperationalLog(.error, category: "Endpoints", message: error.localizedDescription, chain: chain)
            }
        }
    }
}
