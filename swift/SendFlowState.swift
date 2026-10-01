import Foundation

/// Transient native flow state; persisted domain data remains in core.
@MainActor
@Observable
final class SendFlowState {
    var walletId: String = ""
    var holdingKey: String = ""
    var amount: String = ""
    var address: String = ""
    var destinationRiskWarning: String? = nil
    var destinationInfoMessage: String? = nil
    /// The recipient is checked inside the preview request.
    var isCheckingDestination: Bool {
        isPreparingPreview && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isShowingHighRiskConfirmation: Bool = false
    var verificationNotice: String? = nil
    var verificationNoticeIsWarning: Bool = false
    var isPreparingReplacement: Bool = false
    var isPreparingPreview: Bool = false
    let session = SendSession()
    var savedArtifacts: [SendArtifact] = []
    let previewStore = SendPreviewStore()
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
        isPreparingPreview = false
        isPreparingReplacement = false
        isShowingHighRiskConfirmation = false
        clearVerificationNotice()
    }

    func clearPreview() {
        previewRequestId = UUID()
        previewStore.reset()
        isPreparingPreview = false
        isShowingHighRiskConfirmation = false
    }

    func clearDestinationCheck() {
        destinationRiskWarning = nil
        destinationInfoMessage = nil
    }

    func clearEvmOverrides() {
        useCustomEvmFees = false
        customEvmMaxFeeGwei = ""
        customEvmPriorityFeeGwei = ""
        evmManualNonceEnabled = false
        evmManualNonce = ""
    }

    func resetComposer() {
        invalidateSession()
        clearPreview()
        amount = ""
        address = ""
        clearDestinationCheck()
        clearEvmOverrides()
    }

    /// Dismissing resets the composer; one that is not on screen is reset here.
    func close() {
        if isPresented { isPresented = false } else { resetComposer() }
    }

    func reset() {
        close()
        walletId = ""
        holdingKey = ""
        savedArtifacts = []
    }
}
