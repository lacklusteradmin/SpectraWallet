import Foundation
import Combine

final class WalletDiagnosticsState: ObservableObject {
    private static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    private static let operationalLogsDefaultsKey = "operational.logs.v1"
    private static let persistenceEncoder = JSONEncoder()
    private static let persistenceDecoder = JSONDecoder()
    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    private static let chainSyncPersistenceDelay: TimeInterval = 0.15
    private static let operationalLogsPersistenceDelay: TimeInterval = 0.35

    private var pendingChainSyncPersistence: DispatchWorkItem?
    private var pendingOperationalLogsPersistence: DispatchWorkItem?

    @Published private var chainDegradedMessagesByID: [WalletChainID: String] = [:] {
        didSet {
            scheduleChainSyncPersistence()
        }
    }

    @Published private var lastGoodChainSyncByID: [WalletChainID: Date] = [:] {
        didSet {
            scheduleChainSyncPersistence()
        }
    }

    @Published var operationalLogs: [WalletStore.OperationalLogEvent] = [] {
        didSet {
            operationalLogsRevision &+= 1
            scheduleOperationalLogsPersistence()
        }
    }
    @Published private(set) var operationalLogsRevision: UInt64 = 0

    init() {
        operationalLogs = loadOperationalLogs()
        let persistedChainSync = loadChainSyncState()
        chainDegradedMessagesByID = persistedChainSync.degradedMessages
        lastGoodChainSyncByID = persistedChainSync.lastGoodSyncByID
    }

    deinit {
        pendingChainSyncPersistence?.cancel()
        pendingOperationalLogsPersistence?.cancel()
    }

    var chainDegradedMessages: [String: String] {
        get {
            Dictionary(uniqueKeysWithValues: chainDegradedMessagesByID.map { ($0.key.displayName, $0.value) })
        }
        set {
            chainDegradedMessagesByID = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }
                }
            )
        }
    }

    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        get { chainDegradedMessagesByID }
        set { chainDegradedMessagesByID = newValue }
    }

    var lastGoodChainSyncByName: [String: Date] {
        get {
            Dictionary(uniqueKeysWithValues: lastGoodChainSyncByID.map { ($0.key.displayName, $0.value) })
        }
        set {
            lastGoodChainSyncByID = Dictionary(
                uniqueKeysWithValues: newValue.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }
                }
            )
        }
    }

    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        get { lastGoodChainSyncByID }
        set { lastGoodChainSyncByID = newValue }
    }

    var chainDegradedBanners: [WalletStore.ChainDegradedBanner] {
        chainDegradedMessagesByID
            .keys
            .sorted()
            .map { chainID in
                WalletStore.ChainDegradedBanner(
                    chainName: chainID.displayName,
                    message: localizedDegradedMessage(
                        chainDegradedMessagesByID[chainID] ?? "",
                        chainID: chainID
                    ),
                    lastGoodSyncAt: lastGoodChainSyncByID[chainID]
                )
            }
    }

    func clearOperationalLogs() {
        operationalLogs = []
    }

    func exportOperationalLogsText(
        networkSyncStatusText: String,
        events: [WalletStore.OperationalLogEvent]? = nil
    ) -> String {
        let entries = events ?? operationalLogs
        let header = [
            localizedStoreString("Spectra Operational Logs"),
            localizedStoreFormat("Generated: %@", Self.operationalLogTimestampFormatter.string(from: Date())),
            localizedStoreFormat("Entries: %d", entries.count),
            networkSyncStatusText,
            ""
        ]
        let lines = entries.map { event in
            var parts: [String] = [
                Self.operationalLogTimestampFormatter.string(from: event.timestamp),
                "[\(event.level.rawValue.uppercased())]",
                "[\(event.category)]",
                event.message
            ]
            if let source = event.source, !source.isEmpty {
                parts.append("source=\(source)")
            }
            if let chainName = event.chainName, !chainName.isEmpty {
                parts.append("chain=\(chainName)")
            }
            if let walletID = event.walletID {
                parts.append("wallet=\(walletID.uuidString)")
            }
            if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                parts.append("tx=\(transactionHash)")
            }
            if let metadata = event.metadata, !metadata.isEmpty {
                parts.append("meta=\(metadata)")
            }
            return parts.joined(separator: " | ")
        }
        return (header + lines).joined(separator: "\n")
    }

    func appendOperationalLog(
        _ level: WalletStore.OperationalLogEvent.Level,
        category: String,
        message: String,
        chainName: String? = nil,
        walletID: UUID? = nil,
        transactionHash: String? = nil,
        source: String? = nil,
        metadata: String? = nil
    ) {
        let event = WalletStore.OperationalLogEvent(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            chainName: chainName?.trimmingCharacters(in: .whitespacesAndNewlines),
            walletID: walletID,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source?.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadata?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        operationalLogs.insert(event, at: 0)
        if operationalLogs.count > 800 {
            operationalLogs = Array(operationalLogs.prefix(800))
        }
    }

    func markChainHealthy(_ chainName: String) {
        guard let chainID = WalletChainID(chainName) else { return }
        let chainName = chainID.displayName
        let wasDegraded = chainDegradedMessagesByID[chainID] != nil
        chainDegradedMessagesByID.removeValue(forKey: chainID)
        lastGoodChainSyncByID[chainID] = Date()
        if wasDegraded {
            appendOperationalLog(
                .info,
                category: "Chain Sync",
                message: localizedStoreString("Chain recovered"),
                chainName: chainName,
                source: "network"
            )
        }
    }

    func noteChainSuccessfulSync(_ chainName: String) {
        guard let chainID = WalletChainID(chainName) else { return }
        lastGoodChainSyncByID[chainID] = Date()
    }

    func markChainDegraded(_ chainName: String, detail: String) {
        guard let chainID = WalletChainID(chainName) else { return }
        let chainName = chainID.displayName
        if detailIndicatesLiveSuccess(detail) {
            lastGoodChainSyncByID[chainID] = Date()
        }
        let localizedDetail = localizedDegradedDetail(detail, chainName: chainName)
        let metadata = degradedSyncSuffix(for: chainID)
        chainDegradedMessagesByID[chainID] = localizedDetail
        appendOperationalLog(
            .warning,
            category: "Chain Sync",
            message: localizedDetail,
            chainName: chainName,
            source: "network",
            metadata: metadata
        )
    }

    private func localizedDegradedMessage(_ message: String, chainID: WalletChainID) -> String {
        if message.isEmpty {
            return message
        }
        let detail = localizedDegradedDetail(
            normalizedDegradedDetail(message),
            chainName: chainID.displayName
        )
        return [detail, degradedSyncSuffix(for: chainID)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func localizedDegradedDetail(_ detail: String, chainName: String) -> String {
        let templates: [(suffix: String, key: String)] = [
            (
                " refresh timed out. Using cached balances and history.",
                "%@ refresh timed out. Using cached balances and history."
            ),
            (
                " providers are partially reachable. Showing the latest available balances.",
                "%@ providers are partially reachable. Showing the latest available balances."
            ),
            (
                " providers are unavailable. Using cached balances and history.",
                "%@ providers are unavailable. Using cached balances and history."
            ),
            (
                " history loaded with partial provider failures.",
                "%@ history loaded with partial provider failures."
            ),
            (
                " history refresh failed. Using cached history.",
                "%@ history refresh failed. Using cached history."
            )
        ]

        for template in templates {
            if detail.hasSuffix(template.suffix) {
                return localizedStoreFormat(template.key, chainName)
            }
        }

        return localizedStoreString(detail)
    }

    private func detailIndicatesLiveSuccess(_ detail: String) -> Bool {
        detail.contains("partially reachable")
            || detail.contains("partial provider failures")
    }

    private func degradedSyncSuffix(for chainID: WalletChainID) -> String {
        let copy = DiagnosticsContentCopy.current
        if let lastGood = lastGoodChainSyncByID[chainID] {
            return String(
                format: copy.degradedLastGoodSyncFormat,
                lastGood.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return copy.degradedNoPriorSuccessfulSyncYet
    }

    private func normalizedDegradedDetail(_ message: String) -> String {
        if let range = message.range(of: " Last good sync: ") {
            return String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if message.hasSuffix(" No prior successful sync yet.") {
            return String(message.dropLast(" No prior successful sync yet.".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadOperationalLogs() -> [WalletStore.OperationalLogEvent] {
        guard let data = UserDefaults.standard.data(forKey: Self.operationalLogsDefaultsKey),
              let decoded = try? JSONDecoder().decode([WalletStore.OperationalLogEvent].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    func flushPendingPersistence() {
        pendingChainSyncPersistence?.cancel()
        pendingOperationalLogsPersistence?.cancel()
        pendingChainSyncPersistence = nil
        pendingOperationalLogsPersistence = nil
        persistChainSyncState()
        persistOperationalLogs()
    }

    private func scheduleChainSyncPersistence() {
        pendingChainSyncPersistence?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistChainSyncState()
            self?.pendingChainSyncPersistence = nil
        }
        pendingChainSyncPersistence = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chainSyncPersistenceDelay, execute: workItem)
    }

    private func scheduleOperationalLogsPersistence() {
        pendingOperationalLogsPersistence?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistOperationalLogs()
            self?.pendingOperationalLogsPersistence = nil
        }
        pendingOperationalLogsPersistence = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.operationalLogsPersistenceDelay, execute: workItem)
    }

    private func persistOperationalLogs() {
        guard let data = try? JSONEncoder().encode(operationalLogs) else { return }
        UserDefaults.standard.set(data, forKey: Self.operationalLogsDefaultsKey)
    }

    private func persistChainSyncState() {
        let payload = WalletStore.PersistedChainSyncState(
            version: WalletStore.PersistedChainSyncState.currentVersion,
            degradedMessages: Dictionary(
                uniqueKeysWithValues: chainDegradedMessagesByID.map { ($0.key.rawValue, $0.value) }
            ),
            lastGoodSyncUnix: Dictionary(
                uniqueKeysWithValues: lastGoodChainSyncByID.map { key, value in
                    (key.rawValue, value.timeIntervalSince1970)
                }
            )
        )
        guard let data = try? Self.persistenceEncoder.encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.chainSyncStateDefaultsKey)
    }

    private func loadChainSyncState() -> (degradedMessages: [WalletChainID: String], lastGoodSyncByID: [WalletChainID: Date]) {
        guard let data = UserDefaults.standard.data(forKey: Self.chainSyncStateDefaultsKey),
              let payload = try? Self.persistenceDecoder.decode(WalletStore.PersistedChainSyncState.self, from: data),
              payload.version == WalletStore.PersistedChainSyncState.currentVersion else {
            return ([:], [:])
        }
        let degradedMessages = Dictionary(
            uniqueKeysWithValues: payload.degradedMessages.compactMap { key, value in
                WalletChainID(key).map { ($0, value) }
            }
        )
        let dates = Dictionary(
            uniqueKeysWithValues: payload.lastGoodSyncUnix.compactMap { key, value in
                WalletChainID(key).map { ($0, Date(timeIntervalSince1970: value)) }
            }
        )
        return (degradedMessages, dates)
    }
}
