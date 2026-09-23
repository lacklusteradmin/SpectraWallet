import Foundation

/// Transient native flow state; persisted domain data remains in core.
@MainActor
@Observable
final class SendFlowState {
    var walletId: String = ""
    var holdingKey: String = ""
    var amount: String = ""
    var address: String = ""
    var error: String? {
        get { session.error }
        set { session.error = newValue }
    }
    var destinationRiskWarning: String? = nil
    var destinationInfoMessage: String? = nil
    var isCheckingDestination: Bool = false
    var isShowingHighRiskConfirmation: Bool = false
    var verificationNotice: String? = nil
    var verificationNoticeIsWarning: Bool = false
    var isPreparingReplacement: Bool = false
    var preparingChains: Set<String> = []
    @ObservationIgnored var destinationProbeRequestId = UUID() // Reject stale recipient probes.
    let session = SendSession()
    var artifact: SendArtifact? { session.artifact }
    var savedArtifacts: [SendArtifact] = []
    var endpointChoices: [String] { session.endpoints }
    var selectedEndpoints: Set<String> {
        get { session.selectedEndpoints }
        set { session.selectedEndpoints = newValue }
    }
    let previewStore = SendPreviewStore()
    var isBusy: Bool { session.operation != nil }
    var useCustomEvmFees: Bool = false
    var customEvmMaxFeeGwei: String = ""
    var customEvmPriorityFeeGwei: String = ""
    var evmManualNonceEnabled: Bool = false
    var evmManualNonce: String = ""
    @ObservationIgnored var previewRequestId = UUID() // Reject every completion of a superseded preview.
    var isPresented: Bool = false {
        didSet { if oldValue && !isPresented { resetComposer() } }
    }

    func clearVerificationNotice() {
        verificationNotice = nil
        verificationNoticeIsWarning = false
    }

    func invalidateSession() {
        session.reset()
        previewRequestId = UUID()
        destinationProbeRequestId = UUID()
        preparingChains = []
        isCheckingDestination = false
        isPreparingReplacement = false
        isShowingHighRiskConfirmation = false
        clearVerificationNotice()
    }

    func clearPreview() {
        previewRequestId = UUID()
        previewStore.resetAll()
        preparingChains = []
        isShowingHighRiskConfirmation = false
    }

    func resetComposer() {
        invalidateSession()
        clearPreview()
        amount = ""
        address = ""
        destinationRiskWarning = nil
        destinationInfoMessage = nil
        useCustomEvmFees = false
        customEvmMaxFeeGwei = ""
        customEvmPriorityFeeGwei = ""
        evmManualNonceEnabled = false
        evmManualNonce = ""
    }

    func reset() {
        resetComposer()
        walletId = ""
        holdingKey = ""
        savedArtifacts = []
        isPresented = false
    }
}
