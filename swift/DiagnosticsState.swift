import Foundation

@MainActor
@Observable
final class WalletDiagnosticsState {
    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    private var snapshot = DiagnosticState(degraded: [:], lastGoodUnix: [:], logs: [])
    private(set) var operationalLogs: [AppState.OperationalLogEvent] = []
    private(set) var operationalLogsRevision: UInt64 = 0
    private(set) var persistenceError: String?
    @ObservationIgnored private var pendingCommand: Task<Void, Never>?
    @ObservationIgnored private var revision: UInt64 = 0

    private func adopt(_ state: DiagnosticState) {
        snapshot = state
        operationalLogs = state.logs.compactMap { log in
            guard let id = UUID(uuidString: log.id), let level = AppState.OperationalLogEvent.Level(rawValue: log.input.level) else { return nil }
            let input = log.input
            return AppState.OperationalLogEvent(id: id, timestamp: Date(timeIntervalSince1970: log.timestampUnix), level: level,
                category: input.category, message: input.message, chainName: input.chainName, walletID: input.walletId,
                transactionHash: input.transactionHash, source: input.source, metadata: input.metadata)
        }
        operationalLogsRevision &+= 1
    }
    private func enqueue(_ command: DiagnosticCommand) {
        revision &+= 1
        let previous = pendingCommand
        // A queued event finishes even when its diagnostics view is closed.
        pendingCommand = Task { @MainActor [weak self] in
            await previous?.value
            do {
                let result = try await WalletServiceBridge.shared.applyDiagnosticCommand(command)
                self?.adopt(result)
                self?.persistenceError = nil
            } catch { self?.persistenceError = error.localizedDescription }
        }
    }
    func loadFromSQLite() async {
        await pendingCommand?.value
        let started = revision
        do {
            let state = try await WalletServiceBridge.shared.diagnosticState()
            guard started == revision else { return }
            adopt(state)
        } catch { persistenceError = error.localizedDescription }
    }
    func flushPendingPersistence() async { await pendingCommand?.value }
    func reset() { enqueue(.reset) }
    var chainDegradedMessages: [String: String] { snapshot.degraded }
    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        Dictionary(uniqueKeysWithValues: snapshot.degraded.compactMap { key, value in WalletChainID(key).map { ($0, value) } })
    }
    var lastGoodChainSyncByName: [String: Date] { snapshot.lastGoodUnix.mapValues { Date(timeIntervalSince1970: $0) } }
    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        Dictionary(uniqueKeysWithValues: lastGoodChainSyncByName.compactMap { key, value in WalletChainID(key).map { ($0, value) } })
    }
    private var lastGoodChainSyncByID: [WalletChainID: Date] { lastGoodChainSyncByChainID }
    var chainDegradedBanners: [AppState.ChainDegradedBanner] {
        chainDegradedMessagesByChainID.keys.sorted().map { id in
            AppState.ChainDegradedBanner(chainName: id.displayName, message: localizedDegradedMessage(chainDegradedMessagesByChainID[id] ?? "", chainID: id), lastGoodSyncAt: lastGoodChainSyncByID[id])
        }
    }
    func clearOperationalLogs() { enqueue(.clearLogs(chainName: nil)) }
    func exportOperationalLogsText(networkSyncStatusText: String, events: [AppState.OperationalLogEvent]? = nil) -> String {
        let entries = events ?? operationalLogs
        let header = [
            localizedStoreString("Spectra Operational Logs"),
            AppLocalization.format("Generated: %@", Self.operationalLogTimestampFormatter.string(from: Date())),
            AppLocalization.format("Entries: %d", entries.count), networkSyncStatusText, "",
        ]
        let lines = entries.map { event in
            var parts: [String] = [
                Self.operationalLogTimestampFormatter.string(from: event.timestamp), "[\(event.level.rawValue.uppercased())]",
                "[\(event.category)]", event.message,
            ]
            if let source = event.source, !source.isEmpty { parts.append("source=\(source)") }
            if let chainName = event.chainName, !chainName.isEmpty { parts.append("chain=\(chainName)") }
            if let walletID = event.walletID { parts.append("wallet=\(walletID)") }
            if let transactionHash = event.transactionHash, !transactionHash.isEmpty { parts.append("tx=\(transactionHash)") }
            if let metadata = event.metadata, !metadata.isEmpty { parts.append("meta=\(metadata)") }
            return parts.joined(separator: " | ")
        }
        return (header + lines).joined(separator: "\n")
    }
    func appendOperationalLog(
        _ level: AppState.OperationalLogEvent.Level, category: String, message: String, chainName: String? = nil, walletID: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        enqueue(.append(input: DiagnosticLogInput(level: level.rawValue, category: category, message: message,
            chainName: chainName, walletId: walletID, transactionHash: transactionHash, source: source, metadata: metadata)))
    }
    func markChainHealthy(_ chainName: String) { enqueue(.healthy(chainName: chainName)) }
    func noteChainSuccessfulSync(_ chainName: String) { enqueue(.synced(chainName: chainName)) }
    func markChainDegraded(_ chainName: String, detail: String) { enqueue(.degraded(chainName: chainName, detail: detail)) }
    private func localizedDegradedMessage(_ message: String, chainID: WalletChainID) -> String {
        if message.isEmpty { return message }
        let detail = localized(
            diagnosticsClassifyDegradedDetail(detail: message), chainName: chainID.displayName)
        return [detail, degradedSyncSuffix(for: chainID)].filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// One classification, localized.
    private func localized(_ classified: DegradedDetail, chainName: String) -> String {
        if let templateKey = classified.templateKey {
            return AppLocalization.format(templateKey, chainName)
        }
        return localizedStoreString(classified.normalized)
    }
    private func degradedSyncSuffix(for chainID: WalletChainID) -> String {
        let copy = DiagnosticsContentCopy.current
        if let lastGood = lastGoodChainSyncByID[chainID] {
            return String(
                format: copy.degradedLastGoodSyncFormat, lastGood.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return copy.degradedNoPriorSuccessfulSyncYet
    }
}

// The per-wallet diagnostic dictionaries are not stored here: they live in
// the Rust registry (`core/src/diagnostics/registry.rs`) and the `[String: T]`
// vars below are writable computed delegates over UniFFI.
//
// SwiftUI reactivity: mutations bump `diagnosticsRevision`. Because this type
// is `@Observable`, any view reading the revision (or reading through
// `AppState`) invalidates when it changes.
@MainActor
@Observable
final class WalletChainDiagnosticsState {
    var diagnosticsRevision: Int = 0

    /// One chain's self-test state, keyed by chain display name.
    struct SelfTests {
        var results: [ChainSelfTestResult] = []
        var isRunning: Bool = false
        var lastRunAt: Date?
    }
    var selfTestsByChain: [String: SelfTests] = [:]

    /// One chain's endpoint-health state, keyed by chain display name.
    struct EndpointHealth {
        var results: [EndpointHealthRow] = []
        var lastUpdatedAt: Date?
        var isChecking: Bool = false
    }
    var endpointHealthByChain: [String: EndpointHealth] = [:]

    /// When a chain's history diagnostics last ran, and whether one is in
    /// flight. The *results* stay per chain for now — their record types still
    /// differ — but the scalars around them never did.
    struct HistoryRun {
        var lastUpdatedAt: Date?
        var isRunning: Bool = false
    }
    var historyRunByChain: [String: HistoryRun] = [:]

    private func bump() { diagnosticsRevision &+= 1 }

    // MARK: Non-dict state (unchanged)
    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload?

    // MARK: Per-wallet diagnostic dicts (Rust-owned; computed delegates)
    //
    // Only Tron and Solana are named here. The other twenty-two shared one of
    // three record shapes, so they read through `[utxoHistoryFor:]`,
    // `[evmHistoryFor:]` and `[simpleHistoryFor:]` instead — twenty-two
    // four-line accessors and their twenty-two forwards in `DiagnosticsStore`.
    // These two keep theirs because their records genuinely differ.

}
