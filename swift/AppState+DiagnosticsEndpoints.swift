import Foundation
import SwiftUI

// Swift holds progress and rendered diagnostics; core owns probes and status updates.
@MainActor
extension AppState {
    func runBitcoinXpubHistoryDiagnostics() async { await runHistoryDiagnostics(for: .bitcoin) }
    func runHistoryDiagnostics(for chain: Chain) async {
        let name = chain.displayName
        guard !self[historyRunFor: name].isRunning else { return }
        self[historyRunFor: name].isRunning = true
        defer { self[historyRunFor: name].isRunning = false }
        try? await withTimeout(seconds: 20) { await self.refreshHistory(chainName: name) }
        self[historyRunFor: name].lastUpdatedAt = Date()
    }
    func runEndpointDiagnostics(for chain: Chain) async {
        await runCatalogEndpointReachabilityDiagnostics(for: chain.displayName)
    }

    // MARK: Custom reachability probes that need inline JSON-RPC parsing

    /// Run one chain's endpoint probe, holding its "checking" flag and owning
    /// the write-back.
    private func withEndpointCheck(
        for chainName: String, operation: (_ publish: @MainActor ([EndpointHealthRow]) -> Void) async -> Void
    ) async {
        guard !self[endpointHealthFor: chainName].isChecking else { return }
        self[endpointHealthFor: chainName].isChecking = true
        defer { self[endpointHealthFor: chainName].isChecking = false }
        await operation { rows in
            self[endpointHealthFor: chainName].results = rows
            self[endpointHealthFor: chainName].lastUpdatedAt = Date()
        }
    }
    func runBitcoinEndpointReachabilityDiagnostics() async { await runCatalogEndpointReachabilityDiagnostics(for: "Bitcoin") }
    func runMoneroEndpointReachabilityDiagnostics() async { await runCatalogEndpointReachabilityDiagnostics(for: "Monero") }
    func runCatalogEndpointReachabilityDiagnostics(for chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        await withEndpointCheck(for: chainName) { publish in
            do {
                let rows = try await WalletServiceBridge.shared.probeChainEndpoints(chainID: chain.id)
                publish(rows.map { EndpointHealthRow(label: $0.checked ? "" : "Not checked", endpoint: $0.endpoint, reachable: $0.reachable, statusCode: nil, detail: $0.detail) })
            } catch {
                publish([EndpointHealthRow(label: "", endpoint: chainName, reachable: false, statusCode: nil, detail: error.localizedDescription)])
            }
        }
    }

    // MARK: Pending transaction refresh

    /// Poll one chain's pending transactions for a final status.
    ///
    /// Three loops used to live here, one per poll shape — a UTXO status
    /// endpoint, an address history naming confirmed txids, an EVM receipt.
    /// Each selected the records to poll from this projection of core's store,
    /// asked core whether each was due, fetched, told core the outcome,
    /// collected the resolutions and handed them back to be applied: five
    /// crossings per transaction, for a store core owns. What comes back is
    /// what changed, and this writes the event and the notification — the two
    /// things that are genuinely this platform's.
    func refreshPendingTransactions(chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        let changes = (try? await WalletServiceBridge.shared.pollPendingTransactions(
            chainId: chain.id)) ?? []
        guard !changes.isEmpty else { return }
        await applyPendingStatusChanges(changes)
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
