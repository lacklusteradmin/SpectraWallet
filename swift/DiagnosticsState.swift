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
    @ObservationIgnored private var pendingCommand: Task<Void, Never>?
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
                let result = try await bridge.applyDiagnosticCommand(command)
                self?.adopt(result)
                self?.persistenceError = nil
            } catch { self?.persistenceError = error.localizedDescription }
        }
    }
    func loadFromSQLite() async {
        await pendingCommand?.value
        let started = revision
        do {
            let state = try await bridge.diagnosticState()
            guard started == revision else { return }
            adopt(state)
        } catch { persistenceError = error.localizedDescription }
    }
    func flushPendingPersistence() async { await pendingCommand?.value }
    func reset() { enqueue(.reset) }
    var chainDegradedMessages: [String: String] { snapshot.degraded }
    var lastGoodChainSyncByName: [String: Date] { snapshot.lastGoodUnix.mapValues { Date(timeIntervalSince1970: $0) } }
    /// Core keys both maps by chain display name.
    var chainDegradedBanners: [AppState.ChainDegradedBanner] {
        snapshot.degraded.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { chainName in
            AppState.ChainDegradedBanner(
                chainName: chainName, message: localizedDegradedMessage(snapshot.degraded[chainName] ?? "", chainName: chainName),
                lastGoodSyncAt: lastGoodChainSyncByName[chainName])
        }
    }
    func clearOperationalLogs() { enqueue(.clearLogs(chainName: nil)) }
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
            if let chainName = event.chainName, !chainName.isEmpty { parts.append("chain=\(chainName)") }
            if let walletID = event.walletId { parts.append("wallet=\(walletID)") }
            if let transactionHash = event.transactionHash, !transactionHash.isEmpty { parts.append("tx=\(transactionHash)") }
            if let metadata = event.metadata, !metadata.isEmpty { parts.append("meta=\(metadata)") }
            return parts.joined(separator: " | ")
        }
        return (header + lines).joined(separator: "\n")
    }
    func appendOperationalLog(
        _ level: DiagnosticLogLevel, category: String, message: String, chainName: String? = nil, walletID: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        enqueue(.append(input: DiagnosticLogInput(level: level, category: category, message: message,
            chainName: chainName, walletId: walletID, transactionHash: transactionHash, source: source, metadata: metadata)))
    }
    private func localizedDegradedMessage(_ message: String, chainName: String) -> String {
        if message.isEmpty { return message }
        let detail = localized(diagnosticsClassifyDegradedDetail(detail: message), chainName: chainName)
        return [detail, degradedSyncSuffix(for: chainName)].filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// One classification, localized.
    private func localized(_ classified: DegradedDetail, chainName: String) -> String {
        if let templateKey = classified.templateKey {
            return AppLocalization.format(templateKey, chainName)
        }
        return localizedStoreString(classified.normalized)
    }
    private func degradedSyncSuffix(for chainName: String) -> String {
        let copy = DiagnosticsContentCopy.current
        if let lastGood = lastGoodChainSyncByName[chainName] {
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

    /// Last-run time and in-flight state for each chain's history diagnostics.
    struct HistoryRun {
        var lastUpdatedAt: Date?
        var isRunning: Bool = false
    }
    var historyRunByChain: [String: HistoryRun] = [:]

    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload?
}
