import Foundation
extension AppState {
    /// Self-test state for one chain. Reads of a chain with no run give the
    /// empty state.
    subscript(selfTestsFor chain: Chain) -> WalletChainDiagnosticsState.SelfTests {
        get { chainDiagnosticsState.selfTestsByChain[chain.id] ?? .init() }
        set { chainDiagnosticsState.selfTestsByChain[chain.id] = newValue }
    }
    subscript(historyRunFor chain: Chain) -> WalletChainDiagnosticsState.HistoryRun {
        get { chainDiagnosticsState.historyRunByChain[chain.id] ?? .init() }
        set { chainDiagnosticsState.historyRunByChain[chain.id] = newValue }
    }
    subscript(endpointHealthFor chain: Chain) -> WalletChainDiagnosticsState.EndpointHealth {
        get { chainDiagnosticsState.endpointHealthByChain[chain.id] ?? .init() }
        set { chainDiagnosticsState.endpointHealthByChain[chain.id] = newValue }
    }
    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload? {
        get { chainDiagnosticsState.lastImportedDiagnosticsBundle }
        set { chainDiagnosticsState.lastImportedDiagnosticsBundle = newValue }
    }
    var operationalLogs: [DiagnosticLog] {
        get { diagnostics.operationalLogs }
    }
    var chainDegradedBanners: [ChainDegradedBanner] { diagnostics.chainDegradedBanners }
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
