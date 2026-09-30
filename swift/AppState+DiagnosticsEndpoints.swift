import Foundation

// Swift holds which runs are in flight; core runs them and records what they found.
@MainActor
extension AppState {
    func runHistoryDiagnostics(for chain: Chain) async {
        await chainDiagnosticsState.run(\.runningHistory, chain: chain) {
            try? await withTimeout(seconds: 20) { await self.refreshHistory(chain: chain) }
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

/// UI deadline for the history diagnostic action; transport timeouts remain core's.
private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(seconds)); throw AppState.TimeoutError.timedOut(seconds: seconds) }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw AppState.TimeoutError.timedOut(seconds: seconds) }
        return first
    }
}
