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
    }
    var lastGoodChainSyncByName: [String: Date] {
        get { diagnostics.lastGoodChainSyncByName }
    }
    var operationalLogs: [DiagnosticLog] {
        get { diagnostics.operationalLogs }
    }
    var chainDegradedBanners: [ChainDegradedBanner] { diagnostics.chainDegradedBanners }
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
