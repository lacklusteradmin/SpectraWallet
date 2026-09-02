import Foundation
extension AppState {
    /// Self-test state for one chain, keyed by display name. Reads of an
    /// unknown chain give the empty state rather than trapping.
    var selfTests: [String: WalletChainDiagnosticsState.SelfTests] {
        get { chainDiagnosticsState.selfTestsByChain }
        set { chainDiagnosticsState.selfTestsByChain = newValue }
    }
    func selfTests(for chainName: String) -> WalletChainDiagnosticsState.SelfTests {
        chainDiagnosticsState.selfTestsByChain[chainName] ?? .init()
    }
    /// Endpoint-health state for one chain, keyed by display name.
    var endpointHealth: [String: WalletChainDiagnosticsState.EndpointHealth] {
        get { chainDiagnosticsState.endpointHealthByChain }
        set { chainDiagnosticsState.endpointHealthByChain = newValue }
    }
    func endpointHealth(for chainName: String) -> WalletChainDiagnosticsState.EndpointHealth {
        chainDiagnosticsState.endpointHealthByChain[chainName] ?? .init()
    }
    /// Writable, non-optional access for one chain.
    ///
    /// A subscript rather than `endpointHealth[x, default: .init()]` because a
    /// key path cannot carry a `default:` — its subscript index has to be
    /// Hashable — and the generic diagnostics runners take key paths.
    var historyRuns: [String: WalletChainDiagnosticsState.HistoryRun] {
        get { chainDiagnosticsState.historyRunByChain }
        set { chainDiagnosticsState.historyRunByChain = newValue }
    }
    /// Record one wallet's history-run row.
    ///
    /// One row goes across the boundary, not the chain's whole map: reading
    /// every row, mutating a copy and sending them all back is what made two
    /// wallets refreshing at once keep only the later one. Nothing reads the
    /// map for its own sake — the screen's counts come from
    /// `diagnosticsRunSummary`.
    func recordHistoryDiagnostics(chainName: String, _ entry: HistoryDiagnostics) {
        diagnosticsRecord(chainName: chainName, entry: entry)
        chainDiagnosticsState.diagnosticsRevision &+= 1
    }

    subscript(historyRunFor chainName: String) -> WalletChainDiagnosticsState.HistoryRun {
        get { chainDiagnosticsState.historyRunByChain[chainName] ?? .init() }
        set { chainDiagnosticsState.historyRunByChain[chainName] = newValue }
    }
    subscript(endpointHealthFor chainName: String) -> WalletChainDiagnosticsState.EndpointHealth {
        get { chainDiagnosticsState.endpointHealthByChain[chainName] ?? .init() }
        set { chainDiagnosticsState.endpointHealthByChain[chainName] = newValue }
    }
    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload? {
        get { chainDiagnosticsState.lastImportedDiagnosticsBundle }
        set { chainDiagnosticsState.lastImportedDiagnosticsBundle = newValue }
    }
    var chainDegradedMessages: [String: String] {
        get { diagnostics.chainDegradedMessages }
        set { diagnostics.chainDegradedMessages = newValue }
    }
    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        get { diagnostics.chainDegradedMessagesByChainID }
        set { diagnostics.chainDegradedMessagesByChainID = newValue }
    }
    var lastGoodChainSyncByName: [String: Date] {
        get { diagnostics.lastGoodChainSyncByName }
        set { diagnostics.lastGoodChainSyncByName = newValue }
    }
    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        get { diagnostics.lastGoodChainSyncByChainID }
        set { diagnostics.lastGoodChainSyncByChainID = newValue }
    }
    var operationalLogs: [OperationalLogEvent] {
        get { diagnostics.operationalLogs }
        set { diagnostics.operationalLogs = newValue }
    }
    var chainDegradedBanners: [ChainDegradedBanner] { diagnostics.chainDegradedBanners }
    func markChainDegraded(_ chainName: String, detail: String) { diagnostics.markChainDegraded(chainName, detail: detail) }
}

enum ChainSelfTests {
    static func run(_ chainKey: String) -> [ChainSelfTestResult] {
        selfTestsRunChain(chainKey: chainKey)
    }
}
extension ChainSelfTestOutcome {
    var displayMessage: String {
        switch self {
        case .validAddressAccepted: return AppLocalization.string("Valid address accepted.")
        case .validAddressRejected: return AppLocalization.string("Valid address was rejected.")
        case .invalidAddressRejected: return AppLocalization.string("Invalid address rejected.")
        case .invalidAddressUnexpectedlyAccepted: return AppLocalization.string("Invalid address was unexpectedly accepted.")
        case .derivationFailed: return AppLocalization.string("Seed derivation failed.")
        case .derivedAddressValid: return AppLocalization.string("Derived address is valid.")
        case .derivedAddressInvalid: return AppLocalization.string("Derived address is invalid.")
        case .normalizationSuccess: return AppLocalization.string("Address normalization succeeded.")
        case .normalizationFailure: return AppLocalization.string("Address normalization failed.")
        case .checksumMutationRejected: return AppLocalization.string("Checksum mutation rejected.")
        case .checksumMutationAccepted: return AppLocalization.string("Checksum mutation was unexpectedly accepted.")
        case .custom(let text): return text
        }
    }
}
extension ChainSelfTestResult {
    var displayMessage: String { outcome.displayMessage }
}
