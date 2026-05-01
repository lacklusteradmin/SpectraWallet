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

    private func bump() { diagnosticsRevision &+= 1 }

    // MARK: Non-dict state (unchanged)
    var dogecoinSelfTestResults: [ChainSelfTestResult] = []
    var isRunningDogecoinSelfTests: Bool = false
    var dogecoinSelfTestsLastRunAt: Date?
    var bitcoinSelfTestResults: [ChainSelfTestResult] = []
    var isRunningBitcoinSelfTests: Bool = false
    var bitcoinSelfTestsLastRunAt: Date?
    var bitcoinCashSelfTestResults: [ChainSelfTestResult] = []
    var isRunningBitcoinCashSelfTests: Bool = false
    var bitcoinCashSelfTestsLastRunAt: Date?
    var bitcoinSVSelfTestResults: [ChainSelfTestResult] = []
    var isRunningBitcoinSVSelfTests: Bool = false
    var bitcoinSVSelfTestsLastRunAt: Date?
    var litecoinSelfTestResults: [ChainSelfTestResult] = []
    var isRunningLitecoinSelfTests: Bool = false
    var litecoinSelfTestsLastRunAt: Date?
    var dogecoinHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningDogecoinHistoryDiagnostics: Bool = false
    var dogecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var dogecoinEndpointHealthLastUpdatedAt: Date?
    var isCheckingDogecoinEndpointHealth: Bool = false
    var ethereumSelfTestResults: [ChainSelfTestResult] = []
    var isRunningEthereumSelfTests: Bool = false
    var ethereumSelfTestsLastRunAt: Date?
    var ethereumHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningEthereumHistoryDiagnostics: Bool = false
    var ethereumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var ethereumEndpointHealthLastUpdatedAt: Date?
    var isCheckingEthereumEndpointHealth: Bool = false
    var etcHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningETCHistoryDiagnostics: Bool = false
    var etcEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var etcEndpointHealthLastUpdatedAt: Date?
    var isCheckingETCEndpointHealth: Bool = false
    var arbitrumHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningArbitrumHistoryDiagnostics: Bool = false
    var arbitrumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var arbitrumEndpointHealthLastUpdatedAt: Date?
    var isCheckingArbitrumEndpointHealth: Bool = false
    var optimismHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningOptimismHistoryDiagnostics: Bool = false
    var optimismEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var optimismEndpointHealthLastUpdatedAt: Date?
    var isCheckingOptimismEndpointHealth: Bool = false
    var bnbHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningBNBHistoryDiagnostics: Bool = false
    var bnbEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var bnbEndpointHealthLastUpdatedAt: Date?
    var isCheckingBNBEndpointHealth: Bool = false
    var avalancheHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningAvalancheHistoryDiagnostics: Bool = false
    var avalancheEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var avalancheEndpointHealthLastUpdatedAt: Date?
    var isCheckingAvalancheEndpointHealth: Bool = false
    var hyperliquidHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningHyperliquidHistoryDiagnostics: Bool = false
    var hyperliquidEndpointHealthResults: [EthereumEndpointHealthResult] = []
    var hyperliquidEndpointHealthLastUpdatedAt: Date?
    var isCheckingHyperliquidEndpointHealth: Bool = false
    var tronHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningTronHistoryDiagnostics: Bool = false
    var tronEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var tronEndpointHealthLastUpdatedAt: Date?
    var isCheckingTronEndpointHealth: Bool = false
    var solanaHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningSolanaHistoryDiagnostics: Bool = false
    var solanaEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var solanaEndpointHealthLastUpdatedAt: Date?
    var isCheckingSolanaEndpointHealth: Bool = false
    var xrpHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningXRPHistoryDiagnostics: Bool = false
    var xrpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var xrpEndpointHealthLastUpdatedAt: Date?
    var isCheckingXRPEndpointHealth: Bool = false
    var stellarHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningStellarHistoryDiagnostics: Bool = false
    var stellarEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var stellarEndpointHealthLastUpdatedAt: Date?
    var isCheckingStellarEndpointHealth: Bool = false
    var moneroHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningMoneroHistoryDiagnostics: Bool = false
    var moneroEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var moneroEndpointHealthLastUpdatedAt: Date?
    var isCheckingMoneroEndpointHealth: Bool = false
    var suiHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningSuiHistoryDiagnostics: Bool = false
    var suiEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var suiEndpointHealthLastUpdatedAt: Date?
    var isCheckingSuiEndpointHealth: Bool = false
    var aptosHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningAptosHistoryDiagnostics: Bool = false
    var aptosEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var aptosEndpointHealthLastUpdatedAt: Date?
    var isCheckingAptosEndpointHealth: Bool = false
    var tonHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningTONHistoryDiagnostics: Bool = false
    var tonEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var tonEndpointHealthLastUpdatedAt: Date?
    var isCheckingTONEndpointHealth: Bool = false
    var icpHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningICPHistoryDiagnostics: Bool = false
    var icpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var icpEndpointHealthLastUpdatedAt: Date?
    var isCheckingICPEndpointHealth: Bool = false
    var nearHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningNearHistoryDiagnostics: Bool = false
    var nearEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var nearEndpointHealthLastUpdatedAt: Date?
    var isCheckingNearEndpointHealth: Bool = false
    var polkadotHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningPolkadotHistoryDiagnostics: Bool = false
    var polkadotEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var polkadotEndpointHealthLastUpdatedAt: Date?
    var isCheckingPolkadotEndpointHealth: Bool = false
    var cardanoHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningCardanoHistoryDiagnostics: Bool = false
    var cardanoEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var cardanoEndpointHealthLastUpdatedAt: Date?
    var isCheckingCardanoEndpointHealth: Bool = false
    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload?
    var bitcoinHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningBitcoinHistoryDiagnostics: Bool = false
    var bitcoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var bitcoinEndpointHealthLastUpdatedAt: Date?
    var isCheckingBitcoinEndpointHealth: Bool = false
    var bitcoinCashHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningBitcoinCashHistoryDiagnostics: Bool = false
    var bitcoinCashEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var bitcoinCashEndpointHealthLastUpdatedAt: Date?
    var isCheckingBitcoinCashEndpointHealth: Bool = false
    var bitcoinSVHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningBitcoinSVHistoryDiagnostics: Bool = false
    var bitcoinSVEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var bitcoinSVEndpointHealthLastUpdatedAt: Date?
    var isCheckingBitcoinSVEndpointHealth: Bool = false
    var litecoinHistoryDiagnosticsLastUpdatedAt: Date?
    var isRunningLitecoinHistoryDiagnostics: Bool = false
    var litecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    var litecoinEndpointHealthLastUpdatedAt: Date?
    var isCheckingLitecoinEndpointHealth: Bool = false

    // MARK: Per-wallet diagnostic dicts (Rust-owned; computed delegates)

    var dogecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllDogecoin() }
        set { diagnosticsReplaceDogecoin(entries: newValue); bump() }
    }
    var ethereumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEthereum() }
        set { diagnosticsReplaceEthereum(entries: newValue); bump() }
    }
    var etcHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllEtc() }
        set { diagnosticsReplaceEtc(entries: newValue); bump() }
    }
    var arbitrumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllArbitrum() }
        set { diagnosticsReplaceArbitrum(entries: newValue); bump() }
    }
    var optimismHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllOptimism() }
        set { diagnosticsReplaceOptimism(entries: newValue); bump() }
    }
    var bnbHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllBnb() }
        set { diagnosticsReplaceBnb(entries: newValue); bump() }
    }
    var avalancheHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllAvalanche() }
        set { diagnosticsReplaceAvalanche(entries: newValue); bump() }
    }
    var hyperliquidHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { diagnosticsAllHyperliquid() }
        set { diagnosticsReplaceHyperliquid(entries: newValue); bump() }
    }
    var tronHistoryDiagnosticsByWallet: [String: TronHistoryDiagnostics] {
        get { diagnosticsAllTron() }
        set { diagnosticsReplaceTron(entries: newValue); bump() }
    }
    var solanaHistoryDiagnosticsByWallet: [String: SolanaHistoryDiagnostics] {
        get { diagnosticsAllSolana() }
        set { diagnosticsReplaceSolana(entries: newValue); bump() }
    }
    var xrpHistoryDiagnosticsByWallet: [String: XrpHistoryDiagnostics] {
        get { diagnosticsAllXrp() }
        set { diagnosticsReplaceXrp(entries: newValue); bump() }
    }
    var stellarHistoryDiagnosticsByWallet: [String: StellarHistoryDiagnostics] {
        get { diagnosticsAllStellar() }
        set { diagnosticsReplaceStellar(entries: newValue); bump() }
    }
    var moneroHistoryDiagnosticsByWallet: [String: MoneroHistoryDiagnostics] {
        get { diagnosticsAllMonero() }
        set { diagnosticsReplaceMonero(entries: newValue); bump() }
    }
    var suiHistoryDiagnosticsByWallet: [String: SuiHistoryDiagnostics] {
        get { diagnosticsAllSui() }
        set { diagnosticsReplaceSui(entries: newValue); bump() }
    }
    var aptosHistoryDiagnosticsByWallet: [String: AptosHistoryDiagnostics] {
        get { diagnosticsAllAptos() }
        set { diagnosticsReplaceAptos(entries: newValue); bump() }
    }
    var tonHistoryDiagnosticsByWallet: [String: TonHistoryDiagnostics] {
        get { diagnosticsAllTon() }
        set { diagnosticsReplaceTon(entries: newValue); bump() }
    }
    var icpHistoryDiagnosticsByWallet: [String: IcpHistoryDiagnostics] {
        get { diagnosticsAllIcp() }
        set { diagnosticsReplaceIcp(entries: newValue); bump() }
    }
    var nearHistoryDiagnosticsByWallet: [String: NearHistoryDiagnostics] {
        get { diagnosticsAllNear() }
        set { diagnosticsReplaceNear(entries: newValue); bump() }
    }
    var polkadotHistoryDiagnosticsByWallet: [String: PolkadotHistoryDiagnostics] {
        get { diagnosticsAllPolkadot() }
        set { diagnosticsReplacePolkadot(entries: newValue); bump() }
    }
    var cardanoHistoryDiagnosticsByWallet: [String: CardanoHistoryDiagnostics] {
        get { diagnosticsAllCardano() }
        set { diagnosticsReplaceCardano(entries: newValue); bump() }
    }
    var bitcoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoin() }
        set { diagnosticsReplaceBitcoin(entries: newValue); bump() }
    }
    var bitcoinCashHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoinCash() }
        set { diagnosticsReplaceBitcoinCash(entries: newValue); bump() }
    }
    var bitcoinSVHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllBitcoinSv() }
        set { diagnosticsReplaceBitcoinSv(entries: newValue); bump() }
    }
    var litecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { diagnosticsAllLitecoin() }
        set { diagnosticsReplaceLitecoin(entries: newValue); bump() }
    }
}
