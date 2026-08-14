import Foundation

@MainActor
@Observable
final class WalletDiagnosticsState {
    static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    static let operationalLogsDefaultsKey = "operational.logs.v1"
    private static let persistenceEncoder = JSONEncoder()
    private static let persistenceDecoder = JSONDecoder()
    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    private static let chainSyncPersistenceDelay: TimeInterval = 0.15
    private static let operationalLogsPersistenceDelay: TimeInterval = 0.35
    @ObservationIgnored private var pendingChainSyncPersistence: Task<Void, Never>?
    @ObservationIgnored private var pendingOperationalLogsPersistence: Task<Void, Never>?
    @ObservationIgnored private var suspendPersistenceScheduling = false
    private var chainDegradedMessagesByID: [WalletChainID: String] = [:] {
        didSet {
            scheduleChainSyncPersistence()
        }
    }
    private var lastGoodChainSyncByID: [WalletChainID: Date] = [:] {
        didSet {
            scheduleChainSyncPersistence()
        }
    }
    var operationalLogs: [AppState.OperationalLogEvent] = [] {
        didSet {
            operationalLogsRevision &+= 1
            scheduleOperationalLogsPersistence()
        }
    }
    private(set) var operationalLogsRevision: UInt64 = 0
    init() {}
    deinit {
        pendingChainSyncPersistence?.cancel()
        pendingOperationalLogsPersistence?.cancel()
    }
    func loadFromSQLite() async {
        async let opsLogsJSON = try? WalletServiceBridge.shared.loadState(key: Self.operationalLogsDefaultsKey)
        async let chainSyncJSON = try? WalletServiceBridge.shared.loadState(key: Self.chainSyncStateDefaultsKey)
        let opsJSON = await opsLogsJSON
        let chainJSON = await chainSyncJSON
        let loadedLogs: [AppState.OperationalLogEvent]? = {
            guard let json = opsJSON, json != "{}", let data = json.data(using: .utf8) else { return nil }
            return (try? Self.persistenceDecoder.decode([AppState.OperationalLogEvent].self, from: data))?.sorted {
                $0.timestamp > $1.timestamp
            }
        }()
        let loadedChainSync: (degradedMessages: [WalletChainID: String], lastGoodSyncByID: [WalletChainID: Date])? = {
            guard let json = chainJSON, json != "{}", let data = json.data(using: .utf8),
                let payload = try? Self.persistenceDecoder.decode(AppState.PersistedChainSyncState.self, from: data),
                payload.version == AppState.PersistedChainSyncState.currentVersion
            else { return nil }
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
        }()
        suspendPersistenceScheduling = true
        if let loadedLogs { operationalLogs = loadedLogs }
        if let loadedChainSync {
            chainDegradedMessagesByID = loadedChainSync.degradedMessages
            lastGoodChainSyncByID = loadedChainSync.lastGoodSyncByID
        }
        suspendPersistenceScheduling = false
    }
    private static func byName<V>(_ d: [WalletChainID: V]) -> [String: V] {
        Dictionary(uniqueKeysWithValues: d.map { ($0.key.displayName, $0.value) })
    }
    private static func byChainID<V>(_ d: [String: V]) -> [WalletChainID: V] {
        Dictionary(uniqueKeysWithValues: d.compactMap { k, v in WalletChainID(k).map { ($0, v) } })
    }
    var chainDegradedMessages: [String: String] {
        get { Self.byName(chainDegradedMessagesByID) }
        set { chainDegradedMessagesByID = Self.byChainID(newValue) }
    }
    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        get { chainDegradedMessagesByID }
        set { chainDegradedMessagesByID = newValue }
    }
    var lastGoodChainSyncByName: [String: Date] {
        get { Self.byName(lastGoodChainSyncByID) }
        set { lastGoodChainSyncByID = Self.byChainID(newValue) }
    }
    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        get { lastGoodChainSyncByID }
        set { lastGoodChainSyncByID = newValue }
    }
    var chainDegradedBanners: [AppState.ChainDegradedBanner] {
        chainDegradedMessagesByID.keys.sorted().map { chainID in
            AppState.ChainDegradedBanner(
                chainName: chainID.displayName,
                message: localizedDegradedMessage(
                    chainDegradedMessagesByID[chainID] ?? "", chainID: chainID
                ), lastGoodSyncAt: lastGoodChainSyncByID[chainID]
            )
        }
    }
    func clearOperationalLogs() { operationalLogs = [] }
    func exportOperationalLogsText(networkSyncStatusText: String, events: [AppState.OperationalLogEvent]? = nil) -> String {
        let entries = events ?? operationalLogs
        let header = [
            localizedStoreString("Spectra Operational Logs"),
            localizedStoreFormat("Generated: %@", Self.operationalLogTimestampFormatter.string(from: Date())),
            localizedStoreFormat("Entries: %d", entries.count), networkSyncStatusText, "",
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
        let event = AppState.OperationalLogEvent(
            id: UUID(), timestamp: Date(), level: level, category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            chainName: chainName?.trimmingCharacters(in: .whitespacesAndNewlines), walletID: walletID,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source?.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadata?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        operationalLogs.insert(event, at: 0)
        if operationalLogs.count > 800 { operationalLogs = Array(operationalLogs.prefix(800)) }
    }
    func markChainHealthy(_ chainName: String) {
        guard let chainID = WalletChainID(chainName) else { return }
        let chainName = chainID.displayName
        let wasDegraded = chainDegradedMessagesByID[chainID] != nil
        chainDegradedMessagesByID.removeValue(forKey: chainID)
        lastGoodChainSyncByID[chainID] = Date()
        if wasDegraded {
            appendOperationalLog(
                .info, category: "Chain Sync", message: localizedStoreString("Chain recovered"), chainName: chainName, source: "network"
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
        if diagnosticsDetailIndicatesLiveSuccess(detail: detail) { lastGoodChainSyncByID[chainID] = Date() }
        let localizedDetail = localizedDegradedDetail(detail, chainName: chainName)
        let metadata = degradedSyncSuffix(for: chainID)
        chainDegradedMessagesByID[chainID] = localizedDetail
        appendOperationalLog(
            .warning, category: "Chain Sync", message: localizedDetail, chainName: chainName, source: "network", metadata: metadata
        )
    }
    private func localizedDegradedMessage(_ message: String, chainID: WalletChainID) -> String {
        if message.isEmpty { return message }
        let detail = localizedDegradedDetail(
            diagnosticsNormalizeDegradedDetail(message: message), chainName: chainID.displayName
        )
        return [detail, degradedSyncSuffix(for: chainID)].filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func localizedDegradedDetail(_ detail: String, chainName: String) -> String {
        if let templateKey = diagnosticsDegradedDetailTemplateKey(detail: detail) {
            return localizedStoreFormat(templateKey, chainName)
        }
        return localizedStoreString(detail)
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
    func flushPendingPersistence() async {
        pendingChainSyncPersistence?.cancel()
        pendingOperationalLogsPersistence?.cancel()
        pendingChainSyncPersistence = nil
        pendingOperationalLogsPersistence = nil
        await persistChainSyncStateNow()
        await persistOperationalLogsNow()
    }
    private func scheduleChainSyncPersistence() {
        guard !suspendPersistenceScheduling else { return }
        pendingChainSyncPersistence?.cancel()
        pendingChainSyncPersistence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.chainSyncPersistenceDelay))
            guard !Task.isCancelled, let self else { return }
            await self.persistChainSyncStateNow()
            self.pendingChainSyncPersistence = nil
        }
    }
    private func scheduleOperationalLogsPersistence() {
        guard !suspendPersistenceScheduling else { return }
        pendingOperationalLogsPersistence?.cancel()
        pendingOperationalLogsPersistence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.operationalLogsPersistenceDelay))
            guard !Task.isCancelled, let self else { return }
            await self.persistOperationalLogsNow()
            self.pendingOperationalLogsPersistence = nil
        }
    }
    private func persistOperationalLogsNow() async {
        guard let data = try? Self.persistenceEncoder.encode(operationalLogs),
            let json = String(data: data, encoding: .utf8)
        else { return }
        try? await WalletServiceBridge.shared.saveState(key: Self.operationalLogsDefaultsKey, stateJSON: json)
    }
    private func persistChainSyncStateNow() async {
        let payload = AppState.PersistedChainSyncState(
            version: AppState.PersistedChainSyncState.currentVersion,
            degradedMessages: Dictionary(
                uniqueKeysWithValues: chainDegradedMessagesByID.map { ($0.key.rawValue, $0.value) }
            ),
            lastGoodSyncUnix: Dictionary(
                uniqueKeysWithValues: lastGoodChainSyncByID.map { key, value in
                    (key.rawValue, value.timeIntervalSince1970)
                }
            )
        )
        guard let data = try? Self.persistenceEncoder.encode(payload),
            let json = String(data: data, encoding: .utf8)
        else { return }
        try? await WalletServiceBridge.shared.saveState(key: Self.chainSyncStateDefaultsKey, stateJSON: json)
    }
}

// The 24 per-wallet diagnostic dictionaries that previously lived as stored
// properties on this class now live in the Rust registry
// (`core/src/diagnostics/registry.rs`). Swift presents the same `[String: T]`
// dict-shaped API via writable computed vars that delegate to UniFFI, so
// every existing call site and `ReferenceWritableKeyPath` continues to work.
//
// SwiftUI reactivity: mutations bump `diagnosticsRevision`. Because this type
// is `@Observable`, any view reading the revision (or reading through
// `AppState`) invalidates when it changes.
@MainActor
@Observable
final class WalletChainDiagnosticsState {
    var diagnosticsRevision: Int = 0

    /// One chain's self-test state, keyed by chain display name.
    ///
    /// This was three stored properties per chain — `<chain>SelfTestResults`,
    /// `isRunning<Chain>SelfTests`, `<chain>SelfTestsLastRunAt` — with a
    /// matching pair of forwarding accessors each, a runner each, and a row in
    /// two more tables. Keyed by chain, adding one costs nothing.
    struct SelfTests {
        var results: [ChainSelfTestResult] = []
        var isRunning: Bool = false
        var lastRunAt: Date?
    }
    var selfTestsByChain: [String: SelfTests] = [:]

    /// One chain's endpoint-health state, keyed by chain display name.
    ///
    /// Was three stored properties per chain across 24 chains. Keying them
    /// needed the two row records unified first — `EvmEndpointHealthRow`
    /// differed from `EndpointHealthRow` by a `label` field, and two types for
    /// one thing meant two differently-typed slots here.
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

    var dogecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllUtxo(chainName: "Dogecoin") }
        set { diagnosticsReplaceUtxo(chainName: "Dogecoin", entries: newValue); bump() }
    }
    var ethereumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Ethereum") }
        set { diagnosticsReplaceEvm(chainName: "Ethereum", entries: newValue); bump() }
    }
    var etcHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Ethereum Classic") }
        set { diagnosticsReplaceEvm(chainName: "Ethereum Classic", entries: newValue); bump() }
    }
    var arbitrumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Arbitrum") }
        set { diagnosticsReplaceEvm(chainName: "Arbitrum", entries: newValue); bump() }
    }
    var optimismHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Optimism") }
        set { diagnosticsReplaceEvm(chainName: "Optimism", entries: newValue); bump() }
    }
    var bnbHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "BNB Chain") }
        set { diagnosticsReplaceEvm(chainName: "BNB Chain", entries: newValue); bump() }
    }
    var avalancheHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Avalanche") }
        set { diagnosticsReplaceEvm(chainName: "Avalanche", entries: newValue); bump() }
    }
    var hyperliquidHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEvm(chainName: "Hyperliquid") }
        set { diagnosticsReplaceEvm(chainName: "Hyperliquid", entries: newValue); bump() }
    }
    var tronHistoryDiagnosticsByWallet: [String: TronHistoryDiagnostics] {
        get { diagnosticsAllTron() }
        set { diagnosticsReplaceTron(entries: newValue); bump() }
    }
    var solanaHistoryDiagnosticsByWallet: [String: SolanaHistoryDiagnostics] {
        get { diagnosticsAllSolana() }
        set { diagnosticsReplaceSolana(entries: newValue); bump() }
    }
    var xrpHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "XRP Ledger") }
        set { diagnosticsReplaceSimple(chainName: "XRP Ledger", entries: newValue); bump() }
    }
    var stellarHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Stellar") }
        set { diagnosticsReplaceSimple(chainName: "Stellar", entries: newValue); bump() }
    }
    var moneroHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Monero") }
        set { diagnosticsReplaceSimple(chainName: "Monero", entries: newValue); bump() }
    }
    var suiHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Sui") }
        set { diagnosticsReplaceSimple(chainName: "Sui", entries: newValue); bump() }
    }
    var aptosHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Aptos") }
        set { diagnosticsReplaceSimple(chainName: "Aptos", entries: newValue); bump() }
    }
    var tonHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "TON") }
        set { diagnosticsReplaceSimple(chainName: "TON", entries: newValue); bump() }
    }
    var icpHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Internet Computer") }
        set { diagnosticsReplaceSimple(chainName: "Internet Computer", entries: newValue); bump() }
    }
    var nearHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "NEAR") }
        set { diagnosticsReplaceSimple(chainName: "NEAR", entries: newValue); bump() }
    }
    var polkadotHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Polkadot") }
        set { diagnosticsReplaceSimple(chainName: "Polkadot", entries: newValue); bump() }
    }
    var cardanoHistoryDiagnosticsByWallet: [String: SimpleHistoryDiagnostics] {
        get { diagnosticsAllSimple(chainName: "Cardano") }
        set { diagnosticsReplaceSimple(chainName: "Cardano", entries: newValue); bump() }
    }
    var bitcoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllUtxo(chainName: "Bitcoin") }
        set { diagnosticsReplaceUtxo(chainName: "Bitcoin", entries: newValue); bump() }
    }
    var bitcoinCashHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllUtxo(chainName: "Bitcoin Cash") }
        set { diagnosticsReplaceUtxo(chainName: "Bitcoin Cash", entries: newValue); bump() }
    }
    var bitcoinSVHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllUtxo(chainName: "Bitcoin SV") }
        set { diagnosticsReplaceUtxo(chainName: "Bitcoin SV", entries: newValue); bump() }
    }
    var litecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllUtxo(chainName: "Litecoin") }
        set { diagnosticsReplaceUtxo(chainName: "Litecoin", entries: newValue); bump() }
    }
}
