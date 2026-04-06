import Foundation

extension WalletStore {
    var isPreparingEthereumReplacementContext: Bool {
        get { runtimeState.isPreparingEthereumReplacementContext }
        set { runtimeState.isPreparingEthereumReplacementContext = newValue }
    }

    var isPreparingEthereumSend: Bool {
        get { runtimeState.isPreparingEthereumSend }
        set { runtimeState.isPreparingEthereumSend = newValue }
    }

    var isPreparingDogecoinSend: Bool {
        get { runtimeState.isPreparingDogecoinSend }
        set { runtimeState.isPreparingDogecoinSend = newValue }
    }

    var isPreparingTronSend: Bool {
        get { runtimeState.isPreparingTronSend }
        set { runtimeState.isPreparingTronSend = newValue }
    }

    var isPreparingSolanaSend: Bool {
        get { runtimeState.isPreparingSolanaSend }
        set { runtimeState.isPreparingSolanaSend = newValue }
    }

    var isPreparingXRPSend: Bool {
        get { runtimeState.isPreparingXRPSend }
        set { runtimeState.isPreparingXRPSend = newValue }
    }

    var isPreparingStellarSend: Bool {
        get { runtimeState.isPreparingStellarSend }
        set { runtimeState.isPreparingStellarSend = newValue }
    }

    var isPreparingMoneroSend: Bool {
        get { runtimeState.isPreparingMoneroSend }
        set { runtimeState.isPreparingMoneroSend = newValue }
    }

    var isPreparingCardanoSend: Bool {
        get { runtimeState.isPreparingCardanoSend }
        set { runtimeState.isPreparingCardanoSend = newValue }
    }

    var isPreparingSuiSend: Bool {
        get { runtimeState.isPreparingSuiSend }
        set { runtimeState.isPreparingSuiSend = newValue }
    }

    var isPreparingAptosSend: Bool {
        get { runtimeState.isPreparingAptosSend }
        set { runtimeState.isPreparingAptosSend = newValue }
    }

    var isPreparingTONSend: Bool {
        get { runtimeState.isPreparingTONSend }
        set { runtimeState.isPreparingTONSend = newValue }
    }

    var isPreparingICPSend: Bool {
        get { runtimeState.isPreparingICPSend }
        set { runtimeState.isPreparingICPSend = newValue }
    }

    var isPreparingNearSend: Bool {
        get { runtimeState.isPreparingNearSend }
        set { runtimeState.isPreparingNearSend = newValue }
    }

    var isPreparingPolkadotSend: Bool {
        get { runtimeState.isPreparingPolkadotSend }
        set { runtimeState.isPreparingPolkadotSend = newValue }
    }

    var statusTrackingByTransactionID: [UUID: TransactionStatusTrackingState] {
        get { runtimeState.statusTrackingByTransactionID }
        set { runtimeState.statusTrackingByTransactionID = newValue }
    }

    var dogecoinStatusTrackingByTransactionID: [UUID: DogecoinStatusTrackingState] {
        get { runtimeState.statusTrackingByTransactionID }
        set { runtimeState.statusTrackingByTransactionID = newValue }
    }

    var pendingSelfSendConfirmation: PendingSelfSendConfirmation? {
        get { runtimeState.pendingSelfSendConfirmation }
        set { runtimeState.pendingSelfSendConfirmation = newValue }
    }

    var pendingDogecoinSelfSendConfirmation: PendingDogecoinSelfSendConfirmation? {
        get { runtimeState.pendingSelfSendConfirmation }
        set { runtimeState.pendingSelfSendConfirmation = newValue }
    }

    var activeEthereumSendWalletIDs: Set<UUID> {
        get { runtimeState.activeEthereumSendWalletIDs }
        set { runtimeState.activeEthereumSendWalletIDs = newValue }
    }

    var lastSendDestinationProbeKey: String? {
        get { runtimeState.lastSendDestinationProbeKey }
        set { runtimeState.lastSendDestinationProbeKey = newValue }
    }

    var lastSendDestinationProbeWarning: String? {
        get { runtimeState.lastSendDestinationProbeWarning }
        set { runtimeState.lastSendDestinationProbeWarning = newValue }
    }

    var lastSendDestinationProbeInfoMessage: String? {
        get { runtimeState.lastSendDestinationProbeInfoMessage }
        set { runtimeState.lastSendDestinationProbeInfoMessage = newValue }
    }

    var cachedResolvedENSAddresses: [String: String] {
        get { runtimeState.cachedResolvedENSAddresses }
        set { runtimeState.cachedResolvedENSAddresses = newValue }
    }

    var bypassHighRiskSendConfirmation: Bool {
        get { runtimeState.bypassHighRiskSendConfirmation }
        set { runtimeState.bypassHighRiskSendConfirmation = newValue }
    }
}
