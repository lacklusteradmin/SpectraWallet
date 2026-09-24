import Foundation
import SwiftUI

// Swift holds progress and rendered diagnostics; core owns probes and status updates.
@MainActor
extension AppState {
    func runHistoryDiagnostics(for chain: Chain) async {
        guard !self[historyRunFor: chain].isRunning else { return }
        self[historyRunFor: chain].isRunning = true
        defer { self[historyRunFor: chain].isRunning = false }
        try? await withTimeout(seconds: 20) { await self.refreshHistory(chain: chain) }
        self[historyRunFor: chain].lastUpdatedAt = Date()
    }

    // MARK: Custom reachability probes that need inline JSON-RPC parsing

    /// Run one chain's endpoint probe, holding its "checking" flag and owning
    /// the write-back.
    private func withEndpointCheck(
        for chain: Chain, operation: (_ publish: @MainActor ([EndpointHealthRow]) -> Void) async -> Void
    ) async {
        guard !self[endpointHealthFor: chain].isChecking else { return }
        self[endpointHealthFor: chain].isChecking = true
        defer { self[endpointHealthFor: chain].isChecking = false }
        await operation { rows in
            self[endpointHealthFor: chain].results = rows
            self[endpointHealthFor: chain].lastUpdatedAt = Date()
        }
    }
    func runEndpointDiagnostics(for chain: Chain) async {
        await withEndpointCheck(for: chain) { publish in
            do {
                let rows = try await self.bridge.probeChainEndpoints(chainId: chain.id)
                publish(rows.map { EndpointHealthRow(label: $0.checked ? "" : "Not checked", endpoint: $0.endpoint, reachable: $0.reachable, statusCode: nil, detail: $0.detail) })
            } catch {
                publish([EndpointHealthRow(label: "", endpoint: chain.displayName, reachable: false, statusCode: nil, detail: error.localizedDescription)])
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
