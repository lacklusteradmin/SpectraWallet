import Foundation

@MainActor
@Observable
final class WalletDiagnosticsState {
    @ObservationIgnored private let bridge: WalletServiceBridge // Persistence dependency.
    init(bridge: WalletServiceBridge = .shared) { self.bridge = bridge }

    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    private var snapshot = DiagnosticState(degraded: [:], lastGoodUnix: [:], logs: [])
    private(set) var operationalLogs: [DiagnosticLog] = []
    private(set) var operationalLogsRevision: UInt64 = 0
    private(set) var persistenceError: String?
    @ObservationIgnored private(set) var pendingCommand: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0

    private func adopt(_ state: DiagnosticState) {
        snapshot = state
        operationalLogs = state.logs
        operationalLogsRevision &+= 1
    }
    private func enqueue(_ command: DiagnosticCommand) {
        revision &+= 1
        let previous = pendingCommand
        let bridge = self.bridge
        // A queued event finishes even when its diagnostics view is closed.
        pendingCommand = Task { @MainActor [weak self] in
            await previous?.value
            do {
                let result = try await bridge.ready().applyDiagnosticCommand(command: command)
                self?.adopt(result)
                self?.persistenceError = nil
            } catch { self?.persistenceError = error.localizedDescription }
        }
    }
    func loadFromSQLite() async {
        await pendingCommand?.value
        let started = revision
        do {
            let state = try await bridge.ready().diagnosticState()
            guard started == revision else { return }
            adopt(state)
        } catch { persistenceError = error.localizedDescription }
    }
    func reset() { enqueue(.reset) }
    var chainDegraded: [String: ChainDegradation] { snapshot.degraded }
    private var lastGoodSyncByChainId: [String: Date] { snapshot.lastGoodUnix.mapValues { Date(timeIntervalSince1970: $0) } }
    /// One banner per degraded chain, ordered by name. Core keys both maps by chain id.
    var chainDegradedBanners: [AppState.ChainDegradedBanner] {
        snapshot.degraded.map { chainId, reason in
            AppState.ChainDegradedBanner(
                chainId: chainId, message: localizedDegradedMessage(reason, chainId: chainId),
                lastGoodSyncAt: lastGoodSyncByChainId[chainId])
        }.sorted { $0.chainName.localizedCaseInsensitiveCompare($1.chainName) == .orderedAscending }
    }
    func clearOperationalLogs() { enqueue(.clearLogs(chainId: nil)) }
    func exportOperationalLogsText(networkSyncStatusText: String, events: [DiagnosticLog]? = nil) -> String {
        let entries = events ?? operationalLogs
        let header = [
            localizedStoreString("Spectra Operational Logs"),
            AppLocalization.format("Generated: %@", Self.operationalLogTimestampFormatter.string(from: Date())),
            AppLocalization.format("Entries: %d", entries.count), networkSyncStatusText, "",
        ]
        let lines = entries.map { log in
            let event = log.input
            var parts: [String] = [
                Self.operationalLogTimestampFormatter.string(from: log.timestamp), "[\(event.level.exportTag)]",
                "[\(event.category)]", event.message,
            ]
            if let source = event.source, !source.isEmpty { parts.append("source=\(source)") }
            if let chainId = event.chainId, !chainId.isEmpty { parts.append("chain=\(chainId)") }
            if let walletId = event.walletId { parts.append("wallet=\(walletId)") }
            if let transactionHash = event.transactionHash, !transactionHash.isEmpty { parts.append("tx=\(transactionHash)") }
            if let metadata = event.metadata, !metadata.isEmpty { parts.append("meta=\(metadata)") }
            return parts.joined(separator: " | ")
        }
        return (header + lines).joined(separator: "\n")
    }
    func appendOperationalLog(
        _ level: DiagnosticLogLevel, category: String, message: String, chainId: String? = nil, walletId: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        enqueue(.append(input: DiagnosticLogInput(level: level, category: category, message: message,
            chainId: chainId, walletId: walletId, transactionHash: transactionHash, source: source, metadata: metadata)))
    }
    /// Core stores why a chain is stale; the sentence is worded here.
    private func localizedDegradedMessage(_ reason: ChainDegradation, chainId: String) -> String {
        let chainName = Chain.displayName(forId: chainId)
        let detail: String
        switch reason {
        case .historyRefreshFailed:
            detail = AppLocalization.format("%@ history refresh failed. Using cached history.", chainName)
        case .historyPartiallyLoaded:
            detail = AppLocalization.format("%@ history loaded with partial provider failures.", chainName)
        case .failed(let message):
            detail = message
        }
        return [detail, degradedSyncSuffix(for: chainId)].filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func degradedSyncSuffix(for chainId: String) -> String {
        let copy = DiagnosticsContentCopy.current
        if let lastGood = lastGoodSyncByChainId[chainId] {
            return String(
                format: copy.degradedLastGoodSyncFormat, lastGood.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return copy.degradedNoPriorSuccessfulSyncYet
    }
}

/// Which diagnostics runs are in flight, keyed by chain id, and a revision
/// that tells screens to re-read what core recorded. Results live in core.
@MainActor
@Observable
final class WalletChainDiagnosticsState {
    var diagnosticsRevision: Int = 0
    var runningHistory: Set<String> = []
    var checkingEndpoints: Set<String> = []
    var runningSelfTests: Set<String> = []
    var runningRescans: Set<String> = []

    /// Hold `chainId`'s slot in `runs` for `operation`, then tell screens to
    /// re-read. A run already in flight is not started twice.
    func run(
        _ runs: ReferenceWritableKeyPath<WalletChainDiagnosticsState, Set<String>>, chainId: String,
        _ operation: () async -> Void
    ) async {
        guard self[keyPath: runs].insert(chainId).inserted else { return }
        await operation()
        self[keyPath: runs].remove(chainId)
        diagnosticsRevision &+= 1
    }
}
