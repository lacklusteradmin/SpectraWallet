import Foundation
import Combine

final class WalletRuntimeState: ObservableObject {
    @Published var selectedMainTab: MainAppTab = .home
    @Published var isAppLocked: Bool = false
    @Published var appLockError: String?
    @Published var isPreparingEthereumReplacementContext: Bool = false
    @Published var isPreparingEthereumSend: Bool = false
    @Published var isPreparingDogecoinSend: Bool = false
    @Published var isPreparingTronSend: Bool = false
    @Published var isPreparingSolanaSend: Bool = false
    @Published var isPreparingXRPSend: Bool = false
    @Published var isPreparingStellarSend: Bool = false
    @Published var isPreparingMoneroSend: Bool = false
    @Published var isPreparingCardanoSend: Bool = false
    @Published var isPreparingSuiSend: Bool = false
    @Published var isPreparingAptosSend: Bool = false
    @Published var isPreparingTONSend: Bool = false
    @Published var isPreparingICPSend: Bool = false
    @Published var isPreparingNearSend: Bool = false
    @Published var isPreparingPolkadotSend: Bool = false

    var statusTrackingByTransactionID: [UUID: WalletStore.TransactionStatusTrackingState] = [:]
    var pendingSelfSendConfirmation: WalletStore.PendingSelfSendConfirmation?
    var activeEthereumSendWalletIDs: Set<UUID> = []
    var lastSendDestinationProbeKey: String?
    var lastSendDestinationProbeWarning: String?
    var lastSendDestinationProbeInfoMessage: String?
    var cachedResolvedENSAddresses: [String: String] = [:]
    var bypassHighRiskSendConfirmation = false
    var isRefreshingLivePrices = false
    var isRefreshingChainBalances = false
    var allowsBalanceNetworkRefresh = false
    var isRefreshingPendingTransactions = false
    var lastLivePriceRefreshAt: Date?
    var lastFiatRatesRefreshAt: Date?
    var lastFullRefreshAt: Date?
    var lastChainBalanceRefreshAt: Date?
    var lastBackgroundMaintenanceAt: Date?
    var isNetworkReachable: Bool = true
    var isConstrainedNetwork: Bool = false
    var isExpensiveNetwork: Bool = false
}
