import Foundation
import SwiftUI
import Combine
import UserNotifications
import LocalAuthentication
import os
import UIKit
#if canImport(Network)
import Network
#endif

@MainActor
class WalletStore: ObservableObject {
    enum HistoryPaging {
        static let endpointBatchSize = 20
        static let uiPageSize = 10
    }

    static let persistenceEncoder = JSONEncoder()
    static let persistenceDecoder = JSONDecoder()
    static let diagnosticsBundleEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    static let diagnosticsBundleDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    static let exportFilenameTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    static let operationalLogTimestampFormatter = ISO8601DateFormatter()

    enum ResetScope: String, CaseIterable, Identifiable {
        case walletsAndSecrets
        case historyAndCache
        case alertsAndContacts
        case settingsAndEndpoints
        case dashboardCustomization
        case providerState

        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .walletsAndSecrets:
                return localizedStoreString("Wallets & Secrets")
            case .historyAndCache:
                return localizedStoreString("History & Cache")
            case .alertsAndContacts:
                return localizedStoreString("Alerts & Contacts")
            case .settingsAndEndpoints:
                return localizedStoreString("Settings & Endpoints")
            case .dashboardCustomization:
                return localizedStoreString("Dashboard Customization")
            case .providerState:
                return localizedStoreString("Provider State")
            }
        }

        @MainActor
        var detail: String {
            switch self {
            case .walletsAndSecrets:
                return localizedStoreString("Imported wallets, seed phrases, watched addresses, and local wallet access data.")
            case .historyAndCache:
                return localizedStoreString("Transactions, history database, diagnostics snapshots, and cached chain state.")
            case .alertsAndContacts:
                return localizedStoreString("Price alerts, notification rules, and saved address book recipients.")
            case .settingsAndEndpoints:
                return localizedStoreString("Tracked tokens, pricing and RPC settings, preferences, and icon customizations.")
            case .dashboardCustomization:
                return localizedStoreString("Pinned assets and other home page customization choices stored on this device.")
            case .providerState:
                return localizedStoreString("Provider selections, reliability memory, transport caches, and low-level network heuristics.")
            }
        }
    }

    // WalletStore is the application state coordinator.
    // It owns wallet/session state, chain refresh orchestration, send/receive flows,
    // history normalization, diagnostics, and persistence side-effects.
    enum TimeoutError: LocalizedError {
        case timedOut(seconds: Double)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds):
                return localizedStoreFormat("Timed out after %ds", Int(seconds))
            }
        }
    }
    enum SeedPhraseRevealError: LocalizedError {
        case unavailable
        case authenticationRequired
        case passwordRequired
        case invalidPassword

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return localizedStoreString("No seed phrase is stored for this wallet.")
            case .authenticationRequired:
                return localizedStoreString("Face ID authentication is required to view this seed phrase.")
            case .passwordRequired:
                return localizedStoreString("Enter the wallet password to view this seed phrase.")
            case .invalidPassword:
                return localizedStoreString("The wallet password is incorrect.")
            }
        }
    }
    enum BackgroundSyncProfile: String, CaseIterable, Identifiable {
        case conservative
        case balanced
        case aggressive

        var id: String { rawValue }

        @MainActor
        var displayName: String {
            switch self {
            case .conservative: return localizedStoreString("Conservative")
            case .balanced: return localizedStoreString("Balanced")
            case .aggressive: return localizedStoreString("Aggressive")
            }
        }
    }
    let logger = Logger(subsystem: "com.spectra.wallet", category: "dogecoin")
    let balanceTelemetryLogger = Logger(subsystem: "com.spectra.wallet", category: "balance.telemetry")
    let transactionState = WalletTransactionState()
    struct ChainOperationalEvent: Codable, Identifiable {
        enum Level: String, Codable {
            case info
            case warning
            case error
        }

        let id: UUID
        let timestamp: Date
        let chainName: String
        let level: Level
        let message: String
        let transactionHash: String?
    }

    struct OperationalLogEvent: Codable, Identifiable {
        enum Level: String, Codable {
            case debug
            case info
            case warning
            case error
        }

        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let chainName: String?
        let walletID: UUID?
        let transactionHash: String?
        let source: String?
        let metadata: String?
    }

    struct PendingSelfSendConfirmation {
        let walletID: UUID
        let chainName: String
        let symbol: String
        let destinationAddressLowercased: String
        let amount: Double
        let createdAt: Date
    }

    typealias PendingDogecoinSelfSendConfirmation = PendingSelfSendConfirmation

    struct PerformanceSample: Identifiable, Codable, Equatable {
        let id: UUID
        let operation: String
        let durationMS: Double
        let timestamp: Date
        let metadata: String?
    }

    struct DogecoinKeypoolState: Codable {
        var nextExternalIndex: Int
        var nextChangeIndex: Int
        var reservedReceiveIndex: Int?
    }

    struct ChainKeypoolState: Codable {
        var nextExternalIndex: Int
        var nextChangeIndex: Int
        var reservedReceiveIndex: Int?
    }

    struct PersistedDogecoinKeypoolStore: Codable {
        let version: Int
        let keypoolByWalletID: [UUID: DogecoinKeypoolState]

        static let currentVersion = 1
    }

    struct PersistedChainKeypoolStore: Codable {
        let version: Int
        let keypoolByChain: [String: [UUID: ChainKeypoolState]]

        static let currentVersion = 1
    }

    struct DogecoinOwnedAddressRecord: Codable {
        let address: String?
        let walletID: UUID
        let derivationPath: String
        let index: Int
        let branch: String
    }

    struct ChainOwnedAddressRecord: Codable {
        let chainName: String
        let address: String?
        let walletID: UUID
        let derivationPath: String?
        let index: Int?
        let branch: String?
    }

    struct TransactionStatusTrackingState {
        var lastCheckedAt: Date?
        var nextCheckAt: Date
        var consecutiveFailures: Int
        var reachedFinality: Bool

        static func initial(now: Date = Date()) -> TransactionStatusTrackingState {
            TransactionStatusTrackingState(
                lastCheckedAt: nil,
                nextCheckAt: now,
                consecutiveFailures: 0,
                reachedFinality: false
            )
        }
    }

    typealias DogecoinStatusTrackingState = TransactionStatusTrackingState

    struct PendingTransactionStatusResolution {
        let status: TransactionStatus
        let receiptBlockNumber: Int?
        let confirmations: Int?
        let dogecoinNetworkFeeDOGE: Double?
    }

    struct PersistedDogecoinOwnedAddressStore: Codable {
        let version: Int
        let addressMap: [String: DogecoinOwnedAddressRecord]

        static let currentVersion = 1
    }

    struct PersistedChainOwnedAddressStore: Codable {
        let version: Int
        let addressMapByChain: [String: [String: ChainOwnedAddressRecord]]

        static let currentVersion = 1
    }

    struct ChainDegradedBanner: Identifiable {
        let chainName: String
        let message: String
        let lastGoodSyncAt: Date?

        var id: String { chainName }
    }

    struct PersistedChainSyncState: Codable {
        let version: Int
        let degradedMessages: [String: String]
        let lastGoodSyncUnix: [String: TimeInterval]

        static let currentVersion = 1
    }

    struct DogecoinKeypoolDiagnostic: Identifiable, Equatable {
        let walletID: UUID
        let walletName: String
        let reservedReceiveIndex: Int?
        let reservedReceivePath: String?
        let reservedReceiveAddress: String?
        let nextExternalIndex: Int
        let nextChangeIndex: Int

        var id: UUID { walletID }
    }

    struct ChainKeypoolDiagnostic: Identifiable, Equatable {
        let walletID: UUID
        let walletName: String
        let chainName: String
        let reservedReceiveIndex: Int?
        let reservedReceivePath: String?
        let reservedReceiveAddress: String?
        let nextExternalIndex: Int
        let nextChangeIndex: Int

        var id: String { "\(chainName):\(walletID.uuidString)" }
    }

    let portfolioState = WalletPortfolioState()
    let importDraft = WalletImportDraft()
    let flowState = WalletFlowState()
    let runtimeState = WalletRuntimeState()
    let sendState = WalletSendState()
    let chainDiagnosticsState = WalletChainDiagnosticsState()
    private(set) var recentPerformanceSamples: [PerformanceSample] = []

    var isOnboarded: Bool {
        !wallets.isEmpty
    }

    var dogecoinKeypoolDiagnostics: [DogecoinKeypoolDiagnostic] {
        wallets
            .filter { $0.selectedChain == "Dogecoin" }
            .map { wallet in
                let state = dogecoinKeypoolByWalletID[wallet.id] ?? baselineDogecoinKeypoolState(for: wallet)
                let reservedIndex = state.reservedReceiveIndex
                let reservedPath = reservedIndex.map {
                    WalletDerivationPath.dogecoin(
                        account: 0,
                        branch: .external,
                        index: UInt32($0)
                    )
                }
                let reservedAddress = reservedIndex.flatMap { index in
                    deriveDogecoinAddress(for: wallet, isChange: false, index: index)
                }

                return DogecoinKeypoolDiagnostic(
                    walletID: wallet.id,
                    walletName: wallet.name,
                    reservedReceiveIndex: reservedIndex,
                    reservedReceivePath: reservedPath,
                    reservedReceiveAddress: reservedAddress,
                    nextExternalIndex: state.nextExternalIndex,
                    nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }
    }

    func chainKeypoolDiagnostics(for chainName: String) -> [ChainKeypoolDiagnostic] {
        wallets
            .filter { wallet in
                wallet.selectedChain == chainName || walletHasAddress(for: wallet, chainName: chainName)
            }
            .compactMap { wallet in
                let state = keypoolState(for: wallet, chainName: chainName)
                let reservedIndex = state.reservedReceiveIndex
                return ChainKeypoolDiagnostic(
                    walletID: wallet.id,
                    walletName: wallet.name,
                    chainName: chainName,
                    reservedReceiveIndex: reservedIndex,
                    reservedReceivePath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
                    reservedReceiveAddress: reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false),
                    nextExternalIndex: state.nextExternalIndex,
                    nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }
    }
    @Published var pricingProvider: PricingProvider = .coinGecko {
        didSet {
            UserDefaults.standard.set(pricingProvider.rawValue, forKey: Self.pricingProviderDefaultsKey)
        }
    }
    @Published var selectedFiatCurrency: FiatCurrency = .usd {
        didSet {
            UserDefaults.standard.set(selectedFiatCurrency.rawValue, forKey: Self.selectedFiatCurrencyDefaultsKey)
            Task { @MainActor in
                await refreshFiatExchangeRatesIfNeeded(force: true)
            }
        }
    }
    @Published var fiatRateProvider: FiatRateProvider = .openER {
        didSet {
            UserDefaults.standard.set(fiatRateProvider.rawValue, forKey: Self.fiatRateProviderDefaultsKey)
            Task { @MainActor in
                await refreshFiatExchangeRatesIfNeeded(force: true)
            }
        }
    }
    @Published var coinGeckoAPIKey: String = "" {
        didSet {
            SecureStore.save(coinGeckoAPIKey, for: Self.coinGeckoAPIKeyAccount)
        }
    }
    @Published var ethereumRPCEndpoint: String = "" {
        didSet {
            UserDefaults.standard.set(ethereumRPCEndpoint, forKey: Self.ethereumRPCEndpointDefaultsKey)
        }
    }
    @Published var ethereumNetworkMode: EthereumNetworkMode = .mainnet {
        didSet {
            UserDefaults.standard.set(ethereumNetworkMode.rawValue, forKey: Self.ethereumNetworkModeDefaultsKey)
            ethereumHistoryPageByWallet = [:]
            exhaustedEthereumHistoryWalletIDs = []
        }
    }
    @Published var etherscanAPIKey: String = "" {
        didSet {
            UserDefaults.standard.set(etherscanAPIKey, forKey: Self.etherscanAPIKeyDefaultsKey)
        }
    }
    @Published var moneroBackendBaseURL: String = "" {
        didSet {
            UserDefaults.standard.set(moneroBackendBaseURL, forKey: MoneroBalanceService.backendBaseURLDefaultsKey)
        }
    }
    @Published var moneroBackendAPIKey: String = "" {
        didSet {
            UserDefaults.standard.set(moneroBackendAPIKey, forKey: MoneroBalanceService.backendAPIKeyDefaultsKey)
        }
    }
    @Published var isUserInitiatedRefreshInProgress: Bool = false
    @Published var priceAlerts: [PriceAlertRule] = [] {
        didSet {
            persistPriceAlerts()
        }
    }
    @Published var addressBook: [AddressBookEntry] = [] {
        didSet {
            persistAddressBook()
        }
    }
    @Published var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            persistTokenPreferences()
            rebuildTokenPreferenceDerivedState()
            rebuildWalletDerivedState()
            rebuildDashboardDerivedState()
        }
    }
    @Published var livePrices: [String: Double] = [:] {
        didSet {
            persistLivePrices()
            if shouldRebuildDashboardForLivePriceChange(from: oldValue, to: livePrices) {
                rebuildDashboardDerivedState()
            }
        }
    }
    @Published var fiatRatesFromUSD: [String: Double] = [FiatCurrency.usd.rawValue: 1.0]
    @Published var fiatRatesRefreshError: String?
    @Published var quoteRefreshError: String?
    let dashboardState = WalletDashboardState()
    var cachedResolvedTokenPreferences: [TokenPreferenceEntry] = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
    var cachedTokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] = [:]
    var cachedResolvedTokenPreferencesBySymbol: [String: [TokenPreferenceEntry]] = [:]
    var cachedEnabledTrackedTokenPreferences: [TokenPreferenceEntry] = []
    var cachedTokenPreferenceByChainAndSymbol: [String: TokenPreferenceEntry] = [:]
    var cachedCurrencyFormatters: [String: NumberFormatter] = [:]
    var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    @Published var useCustomEthereumFees: Bool = false
    @Published var customEthereumMaxFeeGwei: String = ""
    @Published var customEthereumPriorityFeeGwei: String = ""
    @Published var sendAdvancedMode: Bool = false
    @Published var sendUTXOMaxInputCount: Int = 0
    @Published var sendEnableRBF: Bool = true
    @Published var sendEnableCPFP: Bool = false
    @Published var sendLitecoinChangeStrategy: LitecoinWalletEngine.ChangeStrategy = .derivedChange
    @Published var ethereumManualNonceEnabled: Bool = false
    @Published var ethereumManualNonce: String = ""
    @Published var bitcoinNetworkMode: BitcoinNetworkMode = .mainnet {
        didSet {
            UserDefaults.standard.set(bitcoinNetworkMode.rawValue, forKey: Self.bitcoinNetworkModeDefaultsKey)
            applyBitcoinRuntimeConfiguration()
            bitcoinHistoryCursorByWallet = [:]
            exhaustedBitcoinHistoryWalletIDs = []
        }
    }
    @Published var dogecoinNetworkMode: DogecoinNetworkMode = .mainnet {
        didSet {
            UserDefaults.standard.set(dogecoinNetworkMode.rawValue, forKey: Self.dogecoinNetworkModeDefaultsKey)
        }
    }
    @Published var bitcoinEsploraEndpoints: String = "" {
        didSet {
            UserDefaults.standard.set(bitcoinEsploraEndpoints, forKey: Self.bitcoinEsploraEndpointsDefaultsKey)
            applyBitcoinRuntimeConfiguration()
            bitcoinHistoryCursorByWallet = [:]
            exhaustedBitcoinHistoryWalletIDs = []
        }
    }
    @Published var bitcoinStopGap: Int = 10 {
        didSet {
            let clamped = max(1, min(bitcoinStopGap, 200))
            if clamped != bitcoinStopGap {
                bitcoinStopGap = clamped
                return
            }
            UserDefaults.standard.set(bitcoinStopGap, forKey: Self.bitcoinStopGapDefaultsKey)
            applyBitcoinRuntimeConfiguration()
        }
    }
    @Published var bitcoinFeePriority: BitcoinFeePriority = .normal {
        didSet {
            UserDefaults.standard.set(bitcoinFeePriority.rawValue, forKey: Self.bitcoinFeePriorityDefaultsKey)
        }
    }
    @Published var dogecoinFeePriority: DogecoinWalletEngine.FeePriority = .normal {
        didSet {
            UserDefaults.standard.set(dogecoinFeePriority.rawValue, forKey: Self.dogecoinFeePriorityDefaultsKey)
        }
    }
    // Settings states
    @Published var hideBalances: Bool = false {
        didSet {
            UserDefaults.standard.set(hideBalances, forKey: Self.hideBalancesDefaultsKey)
        }
    }
    @Published var assetDisplayDecimalsByChain: [String: Int] = [:] {
        didSet {
            let normalized = assetDisplayDecimalsByChain.mapValues { min(max($0, 0), 30) }
            if normalized != assetDisplayDecimalsByChain {
                assetDisplayDecimalsByChain = normalized
                return
            }
            persistAssetDisplayDecimalsByChain()
            cachedDecimalFormatters = [:]
        }
    }
    @Published var useFaceID: Bool = true {
        didSet {
            UserDefaults.standard.set(useFaceID, forKey: Self.useFaceIDDefaultsKey)
            if !useFaceID {
                isAppLocked = false
                appLockError = nil
            }
        }
    }
    @Published var useAutoLock: Bool = false {
        didSet {
            UserDefaults.standard.set(useAutoLock, forKey: Self.useAutoLockDefaultsKey)
        }
    }
    @Published var useStrictRPCOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(useStrictRPCOnly, forKey: Self.useStrictRPCOnlyDefaultsKey)
        }
    }
    @Published var requireBiometricForSendActions: Bool = true {
        didSet {
            UserDefaults.standard.set(requireBiometricForSendActions, forKey: Self.requireBiometricForSendActionsDefaultsKey)
        }
    }
    @Published var usePriceAlerts: Bool = true {
        didSet {
            UserDefaults.standard.set(usePriceAlerts, forKey: Self.usePriceAlertsDefaultsKey)
        }
    }
    @Published var useTransactionStatusNotifications: Bool = true {
        didSet {
            UserDefaults.standard.set(useTransactionStatusNotifications, forKey: Self.useTransactionStatusNotificationsDefaultsKey)
            if useTransactionStatusNotifications {
                requestNotificationPermissionIfNeeded()
            }
        }
    }
    @Published var useLargeMovementNotifications: Bool = true {
        didSet {
            UserDefaults.standard.set(useLargeMovementNotifications, forKey: Self.useLargeMovementNotificationsDefaultsKey)
            if useLargeMovementNotifications {
                requestNotificationPermissionIfNeeded()
            }
        }
    }
    @Published var automaticRefreshFrequencyMinutes: Int = 5 {
        didSet {
            let clamped = min(max(automaticRefreshFrequencyMinutes, 5), 60)
            if clamped != automaticRefreshFrequencyMinutes {
                automaticRefreshFrequencyMinutes = clamped
                return
            }
            UserDefaults.standard.set(automaticRefreshFrequencyMinutes, forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey)
        }
    }
    @Published var backgroundSyncProfile: BackgroundSyncProfile = .balanced {
        didSet {
            UserDefaults.standard.set(backgroundSyncProfile.rawValue, forKey: Self.backgroundSyncProfileDefaultsKey)
        }
    }
    @Published var largeMovementAlertPercentThreshold: Double = 10 {
        didSet {
            let clamped = min(max(largeMovementAlertPercentThreshold, 1), 90)
            if clamped != largeMovementAlertPercentThreshold {
                largeMovementAlertPercentThreshold = clamped
                return
            }
            UserDefaults.standard.set(largeMovementAlertPercentThreshold, forKey: Self.largeMovementAlertPercentThresholdDefaultsKey)
        }
    }
    @Published var largeMovementAlertUSDThreshold: Double = 50 {
        didSet {
            let clamped = min(max(largeMovementAlertUSDThreshold, 1), 100_000)
            if clamped != largeMovementAlertUSDThreshold {
                largeMovementAlertUSDThreshold = clamped
                return
            }
            UserDefaults.standard.set(largeMovementAlertUSDThreshold, forKey: Self.largeMovementAlertUSDThresholdDefaultsKey)
        }
    }
    @Published var dogecoinKeypoolByWalletID: [UUID: DogecoinKeypoolState] = [:] {
        didSet {
            persistDogecoinKeypoolState()
        }
    }
    @Published var chainKeypoolByChain: [String: [UUID: ChainKeypoolState]] = [:] {
        didSet {
            persistChainKeypoolState()
        }
    }
    @Published var dogecoinOwnedAddressMap: [String: DogecoinOwnedAddressRecord] = [:] {
        didSet {
            persistDogecoinOwnedAddressMap()
        }
    }
    @Published var chainOwnedAddressMapByChain: [String: [String: ChainOwnedAddressRecord]] = [:] {
        didSet {
            persistChainOwnedAddressMap()
        }
    }
    var pendingEthereumSendPreviewRefresh: Bool = false
    var pendingDogecoinSendPreviewRefresh: Bool = false
    @Published var discoveredDogecoinAddressesByWallet: [UUID: [String]] = [:]
    @Published var discoveredUTXOAddressesByChain: [String: [UUID: [String]]] = [:]
    @Published var bitcoinHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedBitcoinHistoryWalletIDs: Set<UUID> = []
    @Published var bitcoinCashHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedBitcoinCashHistoryWalletIDs: Set<UUID> = []
    @Published var bitcoinSVHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedBitcoinSVHistoryWalletIDs: Set<UUID> = []
    @Published var litecoinHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedLitecoinHistoryWalletIDs: Set<UUID> = []
    @Published var dogecoinHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedDogecoinHistoryWalletIDs: Set<UUID> = []
    @Published var ethereumHistoryPageByWallet: [UUID: Int] = [:]
    @Published var exhaustedEthereumHistoryWalletIDs: Set<UUID> = []
    @Published var arbitrumHistoryPageByWallet: [UUID: Int] = [:]
    @Published var exhaustedArbitrumHistoryWalletIDs: Set<UUID> = []
    @Published var optimismHistoryPageByWallet: [UUID: Int] = [:]
    @Published var exhaustedOptimismHistoryWalletIDs: Set<UUID> = []
    @Published var bnbHistoryPageByWallet: [UUID: Int] = [:]
    @Published var exhaustedBNBHistoryWalletIDs: Set<UUID> = []
    @Published var hyperliquidHistoryPageByWallet: [UUID: Int] = [:]
    @Published var exhaustedHyperliquidHistoryWalletIDs: Set<UUID> = []
    @Published var tronHistoryCursorByWallet: [UUID: String] = [:]
    @Published var exhaustedTronHistoryWalletIDs: Set<UUID> = []
    @Published var isLoadingMoreOnChainHistory: Bool = false
    let diagnostics = WalletDiagnosticsState()
    @Published var chainOperationalEventsByChain: [String: [ChainOperationalEvent]] = [:] {
        didSet {
            persistChainOperationalEvents()
        }
    }
    @Published var selectedFeePriorityOptionRawByChain: [String: String] = [:] {
        didSet {
            persistSelectedFeePriorityOptions()
        }
    }
    @Published var isRunningBitcoinRescan: Bool = false
    @Published var bitcoinRescanLastRunAt: Date?
    @Published var isRunningBitcoinCashRescan: Bool = false
    @Published var bitcoinCashRescanLastRunAt: Date?
    @Published var isRunningBitcoinSVRescan: Bool = false
    @Published var bitcoinSVRescanLastRunAt: Date?
    @Published var isRunningLitecoinRescan: Bool = false
    @Published var litecoinRescanLastRunAt: Date?
    @Published var isRunningDogecoinRescan: Bool = false
    @Published var dogecoinRescanLastRunAt: Date?
    var suppressWalletSideEffects = false
    var userInitiatedRefreshTask: Task<Void, Never>?
    var importRefreshTask: Task<Void, Never>?
    var walletSideEffectsTask: Task<Void, Never>?
    var portfolioStateObservation: AnyCancellable?
    var walletCollectionObservation: AnyCancellable?
    var flowStateObservation: AnyCancellable?
    var runtimeStateObservation: AnyCancellable?
    var diagnosticsObservation: AnyCancellable?
    var chainDiagnosticsStateObservation: AnyCancellable?
    var sendStateObservation: AnyCancellable?
    var transactionStateObservation: AnyCancellable?
    var transactionMutationObservation: AnyCancellable?
    var lastHistoryRefreshAtByChain: [String: Date] = [:]
    var appIsActive = true
    var maintenanceTask: Task<Void, Never>?
    var lastObservedPortfolioTotalUSD: Double?
    var lastObservedPortfolioCompositionSignature: String?
#if canImport(Network)
    let networkPathMonitor = NWPathMonitor()
    let networkPathMonitorQueue = DispatchQueue(label: "spectra.network.monitor")
#endif
    
    static let pricingProviderDefaultsKey = "pricing.provider"
    static let selectedFiatCurrencyDefaultsKey = "pricing.selectedFiatCurrency"
    static let fiatRateProviderDefaultsKey = "pricing.fiatRateProvider"
    static let fiatRatesFromUSDDefaultsKey = "pricing.fiatRatesFromUSD.v1"
    static let coinGeckoAPIKeyAccount = "coingecko.api.key"
    static let ethereumRPCEndpointDefaultsKey = "ethereum.rpc.endpoint"
    static let etherscanAPIKeyDefaultsKey = "ethereum.etherscan.apiKey"
    static let ethereumNetworkModeDefaultsKey = "ethereum.network.mode"
    static let bitcoinNetworkModeDefaultsKey = "bitcoin.network.mode"
    static let dogecoinNetworkModeDefaultsKey = "dogecoin.network.mode"
    static let bitcoinEsploraEndpointsDefaultsKey = "bitcoin.esplora.endpoints"
    static let bitcoinStopGapDefaultsKey = "bitcoin.stopGap"
    static let bitcoinFeePriorityDefaultsKey = "bitcoin.feePriority"
    static let walletsAccount = "wallets.snapshot"
    static let walletsCoreSnapshotAccount = "wallets.core.snapshot.v1"
    static let priceAlertsDefaultsKey = "priceAlerts.snapshot"
    static let addressBookDefaultsKey = "addressBook.snapshot"
    static let tokenPreferencesDefaultsKey = "settings.tokenPreferences.v1"
    static let livePricesDefaultsKey = "pricing.livePrices.v1"
    static let hideBalancesDefaultsKey = "settings.hideBalances"
    static let assetDisplayDecimalsByChainDefaultsKey = "settings.assetDisplayDecimalsByChain.v1"
    static let useFaceIDDefaultsKey = "settings.useFaceID"
    static let useAutoLockDefaultsKey = "settings.useAutoLock"
    static let useStrictRPCOnlyDefaultsKey = "settings.useStrictRPCOnly"
    static let requireBiometricForSendActionsDefaultsKey = "settings.requireBiometricForSendActions"
    static let usePriceAlertsDefaultsKey = "settings.usePriceAlerts"
    static let useTransactionStatusNotificationsDefaultsKey = "settings.useTransactionStatusNotifications"
    static let useLargeMovementNotificationsDefaultsKey = "settings.useLargeMovementNotifications"
    static let automaticRefreshFrequencyMinutesDefaultsKey = "settings.automaticRefreshFrequencyMinutes"
    static let backgroundSyncProfileDefaultsKey = "settings.backgroundSyncProfile"
    static let largeMovementAlertPercentThresholdDefaultsKey = "settings.largeMovementAlertPercentThreshold"
    static let largeMovementAlertUSDThresholdDefaultsKey = "settings.largeMovementAlertUSDThreshold"
    static let selectedFeePriorityOptionsByChainDefaultsKey = "settings.feePriorityOptionsByChain.v1"
    static let chainOperationalEventsDefaultsKey = "chain.operational.events.v1"
    static let operationalLogsDefaultsKey = "operational.logs.v1"
    static let dogecoinFeePriorityDefaultsKey = "settings.dogecoinFeePriority"
    static let dogecoinKeypoolDefaultsKey = "dogecoin.keypool.snapshot"
    static let dogecoinOwnedAddressMapDefaultsKey = "dogecoin.ownedAddressMap.snapshot"
    static let chainKeypoolDefaultsKey = "chain.keypool.snapshot.v1"
    static let chainOwnedAddressMapDefaultsKey = "chain.ownedAddressMap.snapshot.v1"
    static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    static let installMarkerDefaultsKey = "app.install.marker.v1"
    static let dogecoinDiscoveryGapLimit = 3
    static let dogecoinDiscoveryMaxIndex = 40
    static let utxoDiscoveryGapLimit = 3
    static let utxoDiscoveryMaxIndex = 40
    static let pendingStatusPollSeconds: TimeInterval = 20
    static let confirmedStatusPollSeconds: TimeInterval = 300
    static let statusPollBackoffMaxSeconds: TimeInterval = 600
    static let standardFinalityConfirmations = 12
    static let pendingFailureTimeoutSeconds: TimeInterval = 60 * 60
    static let pendingFailureMinFailures = 6
    static let selfSendConfirmationWindowSeconds: TimeInterval = 20
    static let activeMaintenancePollSeconds: UInt64 = 30
    static let inactiveMaintenancePollSeconds: UInt64 = 60
    static let activePendingRefreshInterval: TimeInterval = 60
    static let activePriceRefreshInterval: TimeInterval = 300
    static let fiatRatesRefreshInterval: TimeInterval = 6 * 60 * 60
    static let backgroundMaintenanceInterval: TimeInterval = 15 * 60
    static let constrainedBackgroundMaintenanceInterval: TimeInterval = 30 * 60
    static let lowPowerBackgroundMaintenanceInterval: TimeInterval = 45 * 60
    static let lowBatteryBackgroundMaintenanceInterval: TimeInterval = 60 * 60
    static let foregroundFullRefreshStalenessInterval: TimeInterval = 2 * 60
    static let automaticChainRefreshStalenessInterval: TimeInterval = 10 * 60
    // MARK: - Seed and Endpoint Utilities
    static func seedPhraseAccount(for walletID: UUID) -> String {
        "wallet.seed.\(walletID.uuidString)"
    }

    static func seedPhrasePasswordAccount(for walletID: UUID) -> String {
        "wallet.seed.password.\(walletID.uuidString)"
    }

    static func privateKeyAccount(for walletID: UUID) -> String {
        "wallet.privatekey.\(walletID.uuidString)"
    }

    func resolvedSeedPhraseAccount(for walletID: UUID) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.seedPhraseStoreKey ?? Self.seedPhraseAccount(for: walletID)
    }

    func resolvedSeedPhrasePasswordAccount(for walletID: UUID) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.passwordStoreKey ?? Self.seedPhrasePasswordAccount(for: walletID)
    }

    func resolvedPrivateKeyAccount(for walletID: UUID) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.privateKeyStoreKey ?? Self.privateKeyAccount(for: walletID)
    }

    func applyWalletSecretIndex(_ index: WalletRustWalletSecretIndex) {
        cachedSigningMaterialWalletIDs = Set(index.signingMaterialWalletIDs.compactMap(UUID.init(uuidString:)))
        cachedPrivateKeyBackedWalletIDs = Set(index.privateKeyBackedWalletIDs.compactMap(UUID.init(uuidString:)))
        cachedPasswordProtectedWalletIDs = Set(index.passwordProtectedWalletIDs.compactMap(UUID.init(uuidString:)))
        cachedSecretDescriptorsByWalletID = Dictionary(
            uniqueKeysWithValues: index.descriptors.compactMap { descriptor in
                UUID(uuidString: descriptor.walletID).map { ($0, descriptor) }
            }
        )
    }

    func clearWalletSecretIndex() {
        cachedSigningMaterialWalletIDs = []
        cachedPrivateKeyBackedWalletIDs = []
        cachedPasswordProtectedWalletIDs = []
        cachedSecretDescriptorsByWalletID = [:]
    }

    // Reads seed phrase material for a wallet from the dedicated seed keychain namespace.
    // Returns nil when no seed exists, which is the expected state for some watched-address wallets.
    func storedSeedPhrase(for walletID: UUID) -> String? {
        let account = resolvedSeedPhraseAccount(for: walletID)
        guard let seedPhrase = try? SecureSeedStore.loadValue(for: account), !seedPhrase.isEmpty else {
            return nil
        }
        return seedPhrase
    }

    func storedPrivateKey(for walletID: UUID) -> String? {
        let account = resolvedPrivateKeyAccount(for: walletID)
        let privateKey = SecurePrivateKeyStore.loadValue(for: account)
        return privateKey.isEmpty ? nil : privateKey
    }

    func walletRequiresSeedPhrasePassword(_ walletID: UUID) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] {
            return descriptor.hasPassword
        }
        return SecureSeedPasswordStore.hasPassword(for: resolvedSeedPhrasePasswordAccount(for: walletID))
    }

    func signingMaterialAvailability(for walletID: UUID) -> (hasSigningMaterial: Bool, isPrivateKeyBacked: Bool) {
        let hasSeedPhrase = storedSeedPhrase(for: walletID) != nil
        let hasPrivateKey = storedPrivateKey(for: walletID) != nil
        return (hasSeedPhrase || hasPrivateKey, hasPrivateKey)
    }

    func walletHasSigningMaterial(_ walletID: UUID) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] {
            return descriptor.hasSigningMaterial
        }
        return signingMaterialAvailability(for: walletID).hasSigningMaterial
    }

    func isPrivateKeyBackedWallet(_ walletID: UUID) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] {
            return descriptor.hasPrivateKey
        }
        return signingMaterialAvailability(for: walletID).isPrivateKeyBacked
    }

    func deleteWalletSecrets(for walletID: UUID) {
        let seedAccount = resolvedSeedPhraseAccount(for: walletID)
        let seedPasswordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
        let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
        try? SecureSeedStore.deleteValue(for: seedAccount)
        try? SecureSeedPasswordStore.deleteValue(for: seedPasswordAccount)
        SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
        cachedSigningMaterialWalletIDs.remove(walletID)
        cachedPrivateKeyBackedWalletIDs.remove(walletID)
        cachedPasswordProtectedWalletIDs.remove(walletID)
        cachedSecretDescriptorsByWalletID[walletID] = nil
    }

    // Parses user-configured Esplora endpoints supporting comma/newline/semicolon separators.
    func parsedBitcoinEsploraEndpoints() -> [String] {
        bitcoinEsploraEndpoints
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // Effective endpoint resolver:
    // use configured endpoints when present, otherwise fall back to network-specific defaults.
    func effectiveBitcoinEsploraEndpoints() -> [String] {
        let configured = parsedBitcoinEsploraEndpoints()
        if !configured.isEmpty {
            return configured
        }
        return ChainBackendRegistry.BitcoinRuntimeEndpoints.walletStoreDefaultBaseURLs(for: bitcoinNetworkMode)
    }

    // Applies runtime Bitcoin settings to the engine without requiring app restart.
    func applyBitcoinRuntimeConfiguration() {
        BitcoinWalletEngine.configureRuntime(
            networkMode: self.bitcoinNetworkMode,
            esploraEndpoints: parsedBitcoinEsploraEndpoints(),
            stopGap: bitcoinStopGap
        )
    }

    var bitcoinEsploraEndpointsValidationError: String? {
        for endpoint in parsedBitcoinEsploraEndpoints() {
            guard let url = URL(string: endpoint),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                return "Bitcoin Esplora endpoints must be valid http(s) URLs separated by commas."
            }
        }
        return nil
    }

    func parseDogecoinAmountInput(_ amountText: String) -> Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d+(\.\d{1,8})?|\.\d{1,8})$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil,
              let amount = Double(trimmed),
              amount > 0 else {
            return nil
        }
        return amount
    }

    func recordPendingSentTransaction(_ transaction: TransactionRecord) {
        appendTransaction(transaction)
        lastSentTransaction = transaction
        noteSendBroadcastQueued(for: transaction)
        requestTransactionStatusNotificationPermission()
    }

    func clearSendVerificationNotice() {
        sendVerificationNotice = nil
        sendVerificationNoticeIsWarning = false
    }

    func setDeferredSendVerificationNotice(for chainName: String) {
        sendVerificationNotice = "Broadcast succeeded, but \(chainName) network verification is still catching up. Status will update shortly."
        sendVerificationNoticeIsWarning = false
    }

    func setFailedSendVerificationNotice(_ message: String) {
        sendVerificationNotice = "Warning: \(message)"
        sendVerificationNoticeIsWarning = true
    }

    func applySendVerificationStatus(_ verificationStatus: SendBroadcastVerificationStatus, chainName: String) {
        switch verificationStatus {
        case .verified:
            clearSendVerificationNotice()
        case .deferred:
            setDeferredSendVerificationNotice(for: chainName)
        case .failed(let message):
            setFailedSendVerificationNotice("Broadcast succeeded, but post-broadcast verification reported: \(message)")
        }
    }

    func updateSendVerificationNoticeForLastSentTransaction() {
        guard let lastSentTransaction, lastSentTransaction.kind == .send else {
            clearSendVerificationNotice()
            return
        }

        guard let transactionHash = lastSentTransaction.transactionHash?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !transactionHash.isEmpty else {
            clearSendVerificationNotice()
            return
        }

        if lastSentTransaction.status == .failed {
            let message = lastSentTransaction.failureReason ?? "Broadcast was not confirmed by the network."
            setFailedSendVerificationNotice(message)
            return
        }

        let wasObservedOnNetwork =
            lastSentTransaction.status == .confirmed ||
            lastSentTransaction.transactionHistorySource != nil ||
            lastSentTransaction.receiptBlockNumber != nil ||
            (lastSentTransaction.dogecoinConfirmations ?? 0) > 0

        if wasObservedOnNetwork {
            clearSendVerificationNotice()
            return
        }

        setDeferredSendVerificationNotice(for: lastSentTransaction.chainName)
    }

    func runPostSendRefreshActions(for chainName: String, verificationStatus: SendBroadcastVerificationStatus) async {
        applySendVerificationStatus(verificationStatus, chainName: chainName)
        noteSendBroadcastVerification(
            chainName: chainName,
            verificationStatus: verificationStatus,
            transactionHash: lastSentTransaction?.chainName == chainName ? lastSentTransaction?.transactionHash : nil
        )
        switch ChainBackendRegistry.appChain(for: chainName)?.id {
        case .bitcoin:
            await refreshBitcoinBalances()
            await refreshPendingBitcoinTransactions()
        case .bitcoinCash:
            await refreshBitcoinCashBalances()
            await refreshPendingBitcoinCashTransactions()
        case .bitcoinSV:
            await refreshBitcoinSVBalances()
            await refreshPendingBitcoinSVTransactions()
        case .litecoin:
            await refreshLitecoinBalances()
            await refreshPendingLitecoinTransactions()
        case .dogecoin:
            await refreshDogecoinBalances()
            await refreshPendingDogecoinTransactions()
        case .ethereum:
            await refreshEthereumBalances()
            await refreshPendingEthereumTransactions()
        case .ethereumClassic:
            await refreshETCBalances()
            await refreshPendingETCTransactions()
        case .arbitrum:
            await refreshArbitrumBalances()
            await refreshPendingArbitrumTransactions()
        case .optimism:
            await refreshOptimismBalances()
            await refreshPendingOptimismTransactions()
        case .bnb:
            await refreshBNBBalances()
            await refreshPendingBNBTransactions()
        case .avalanche:
            await refreshAvalancheBalances()
            await refreshPendingAvalancheTransactions()
        case .hyperliquid:
            await refreshHyperliquidBalances()
            await refreshPendingHyperliquidTransactions()
        case .tron:
            await refreshTronBalances()
            await refreshTronTransactions(loadMore: false)
        case .solana:
            await refreshSolanaBalances()
            await refreshSolanaTransactions(loadMore: false)
        case .cardano:
            await refreshCardanoBalances()
            await refreshCardanoTransactions(loadMore: false)
        case .xrp:
            await refreshXRPBalances()
            await refreshXRPTransactions(loadMore: false)
        case .stellar:
            await refreshStellarBalances()
            await refreshStellarTransactions(loadMore: false)
        case .monero:
            await refreshMoneroBalances()
            await refreshMoneroTransactions(loadMore: false)
        case .sui:
            await refreshSuiBalances()
            await refreshSuiTransactions(loadMore: false)
        case .aptos:
            await refreshAptosBalances()
            await refreshAptosTransactions(loadMore: false)
        case .ton:
            await refreshTONBalances()
            await refreshTONTransactions(loadMore: false)
        case .icp:
            await refreshICPBalances()
            await refreshICPTransactions(loadMore: false)
        case .near:
            await refreshNearBalances()
            await refreshNearTransactions(loadMore: false)
        case .polkadot:
            await refreshPolkadotBalances()
            await refreshPolkadotTransactions(loadMore: false)
        case .none:
            break
        }
        updateSendVerificationNoticeForLastSentTransaction()
    }

    func resetSendComposerState(afterSend extraReset: (() -> Void)? = nil) {
        sendAmount = ""
        sendAddress = ""
        extraReset?()
        sendError = nil
    }

    func recordPerformanceSample(
        _ operation: String,
        startedAt: CFAbsoluteTime,
        metadata: String? = nil
    ) {
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        recentPerformanceSamples.insert(
            PerformanceSample(
                id: UUID(),
                operation: operation,
                durationMS: durationMS,
                timestamp: Date(),
                metadata: metadata
            ),
            at: 0
        )
        if recentPerformanceSamples.count > 120 {
            recentPerformanceSamples = Array(recentPerformanceSamples.prefix(120))
        }
        balanceTelemetryLogger.info("perf \(operation, privacy: .public) \(durationMS, format: .fixed(precision: 2))ms \(metadata ?? "", privacy: .public)")
    }

    // Startup restore pipeline:
    // 1) run install hygiene to prevent stale secure data reuse,
    // 2) hydrate persisted settings/wallet snapshots/transactions,
    // 3) re-apply runtime engine configuration,
    // 4) start background maintenance loops and initial refreshes.
    init() {
        clearPersistedSecureDataOnFreshInstallIfNeeded()
        portfolioStateObservation = portfolioState.objectWillChange.sink { _ in
        }
        walletCollectionObservation = portfolioState.$wallets.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            guard !self.suppressWalletSideEffects else { return }
            self.applyWalletCollectionSideEffects()
        }
        runtimeStateObservation = runtimeState.objectWillChange.sink { _ in
        }
        transactionStateObservation = transactionState.objectWillChange.sink { _ in
        }
        transactionMutationObservation = transactionState.$transactions.dropFirst().sink { [weak self] newTransactions in
            guard let self else { return }
            let oldTransactions = self.transactionState.lastObservedTransactions
            self.transactionState.lastObservedTransactions = newTransactions
            guard !self.transactionState.suppressSideEffects else { return }
            self.persistTransactionsDelta(from: oldTransactions, to: newTransactions)
            self.rebuildTransactionDerivedState()
        }
        flowStateObservation = flowState.objectWillChange.sink { _ in
        }
        diagnosticsObservation = diagnostics.objectWillChange.sink { _ in
        }
        chainDiagnosticsStateObservation = chainDiagnosticsState.objectWillChange.sink { _ in
        }
        sendStateObservation = sendState.objectWillChange.sink { _ in
        }
        restorePersistedRuntimeConfigurationAndState()

        // Defer heavy startup work until first frame is rendered.
        Task { @MainActor in
            rebuildTransactionDerivedState()
            startMaintenanceLoopIfNeeded()
            await refreshFiatExchangeRates()
        }
    }

    deinit {
        maintenanceTask?.cancel()
        userInitiatedRefreshTask?.cancel()
        importRefreshTask?.cancel()
        walletSideEffectsTask?.cancel()
#if canImport(Network)
        networkPathMonitor.cancel()
#endif
    }

    // Executes mutations while suppressing expensive transaction-derived side effects.
    // Used during startup/load paths to avoid N intermediate recomputations.
    func withSuspendedTransactionSideEffects(_ body: () -> Void) {
        let previous = transactionState.suppressSideEffects
        transactionState.suppressSideEffects = true
        body()
        transactionState.lastObservedTransactions = transactions
        transactionState.suppressSideEffects = previous
    }

    var canImportWallet: Bool {
    importDraft.canImportWallet
}

    var resolvedTokenPreferences: [TokenPreferenceEntry] {
        cachedResolvedTokenPreferences
    }

    var tokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] {
        cachedTokenPreferencesByChain
    }

    var enabledTrackedTokenPreferences: [TokenPreferenceEntry] {
        cachedEnabledTrackedTokenPreferences
    }

    // Enables/disables a tracked token without deleting its definition.
    func setTokenPreferenceEnabled(id: UUID, isEnabled: Bool) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        tokenPreferences[index].isEnabled = isEnabled
    }

    func setTokenPreferencesEnabled(ids: [UUID], isEnabled: Bool) {
        let targetIDs = Set(ids)
        for index in tokenPreferences.indices where targetIDs.contains(tokenPreferences[index].id) {
            tokenPreferences[index].isEnabled = isEnabled
        }
    }

    // Deletes a user-added custom token tracking rule.
    func removeCustomTokenPreference(id: UUID) {
        guard let entry = tokenPreferences.first(where: { $0.id == id }),
              !entry.isBuiltIn else { return }
        tokenPreferences.removeAll { $0.id == id }
    }

    func updateCustomTokenPreferenceDecimals(id: UUID, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return }
        tokenPreferences[index].decimals = min(max(decimals, 0), 30)
        if let displayDecimals = tokenPreferences[index].displayDecimals {
            tokenPreferences[index].displayDecimals = min(displayDecimals, tokenPreferences[index].decimals)
        }
    }

    func updateTokenPreferenceDisplayDecimals(id: UUID, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        let supportedDecimals = max(tokenPreferences[index].decimals, 0)
        tokenPreferences[index].displayDecimals = min(max(decimals, 0), supportedDecimals)
    }

    func resetNativeAssetDisplayDecimals() {
        assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain()
    }

    func resetTrackedTokenDisplayDecimals() {
        guard !tokenPreferences.isEmpty else { return }
        for index in tokenPreferences.indices {
            tokenPreferences[index].displayDecimals = nil
        }
    }

    @discardableResult
    // Adds a custom token tracker entry after validating chain/contract format.
    // This only affects detection/tracking, not key derivation behavior.
    func addCustomTokenPreference(
        chain: TokenTrackingChain,
        symbol: String,
        name: String,
        contractAddress: String,
        marketDataID: String = "0",
        coinGeckoID: String = "",
        decimals: Int
    ) -> String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return localizedStoreString("Symbol is required.") }
        guard normalizedSymbol.count <= 12 else { return localizedStoreString("Symbol is too long.") }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return localizedStoreString("Token name is required.") }
        let normalizedContract = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContract.isEmpty else { return localizedStoreString("Contract address is required.") }

        switch chain {
        case .ethereum:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Ethereum token contract address.")
            }
        case .arbitrum:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Arbitrum token contract address.")
            }
        case .optimism:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Optimism token contract address.")
            }
        case .bnb:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid BNB Chain token contract address.")
            }
        case .avalanche:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Avalanche token contract address.")
            }
        case .hyperliquid:
            guard EthereumWalletEngine.isValidAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Hyperliquid token contract address.")
            }
        case .solana:
            guard AddressValidation.isValidSolanaAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Solana token mint address.")
            }
        case .sui:
            let isLikelySuiIdentifier = normalizedContract.hasPrefix("0x")
                && (normalizedContract.contains("::") || normalizedContract.count > 2)
            guard isLikelySuiIdentifier else {
                return localizedStoreString("Enter a valid Sui coin type or package address.")
            }
        case .aptos:
            guard AddressValidation.isValidAptosTokenType(normalizedContract) else {
                return localizedStoreString("Enter a valid Aptos coin type.")
            }
        case .ton:
            guard AddressValidation.isValidTONAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid TON jetton master address.")
            }
        case .near:
            guard AddressValidation.isValidNearAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid NEAR token contract account ID.")
            }
        case .tron:
            guard AddressValidation.isValidTronAddress(normalizedContract) else {
                return localizedStoreString("Enter a valid Tron TRC-20 contract address.")
            }
        }

        let duplicateExists = tokenPreferences.contains { entry in
            entry.chain == chain && normalizedTrackedTokenIdentifier(for: entry.chain, contractAddress: entry.contractAddress) == normalizedTrackedTokenIdentifier(for: chain, contractAddress: normalizedContract)
        }
        guard !duplicateExists else { return localizedStoreFormat("This token is already tracked for %@.", chain.rawValue) }

        tokenPreferences.append(
            TokenPreferenceEntry(
                chain: chain,
                name: normalizedName,
                symbol: normalizedSymbol,
                tokenStandard: chain.tokenStandard,
                contractAddress: normalizedContract,
                marketDataID: marketDataID.trimmingCharacters(in: .whitespacesAndNewlines),
                coinGeckoID: coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines),
                decimals: min(max(decimals, 0), 30),
                category: .custom,
                isBuiltIn: false,
                isEnabled: true
            )
        )
        tokenPreferences.sort { lhs, rhs in
            if lhs.chain != rhs.chain {
                return lhs.chain.rawValue < rhs.chain.rawValue
            }
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.symbol < rhs.symbol
        }
        return nil
    }

    // Returns only enabled token definitions for a specific chain.
    func enabledTokenPreferences(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        enabledTrackedTokenPreferences.filter { $0.chain == chain }
    }

    func normalizedTrackedTokenIdentifier(for chain: TokenTrackingChain, contractAddress: String) -> String {
        let trimmed = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chain {
        case .ethereum, .arbitrum, .bnb, .avalanche, .hyperliquid:
            return EthereumWalletEngine.normalizeAddress(trimmed)
        case .aptos:
            return normalizeAptosTokenIdentifier(trimmed)
        case .sui:
            return normalizeSuiTokenIdentifier(trimmed)
        case .ton:
            return TONBalanceService.normalizeJettonMasterAddress(trimmed)
        default:
            return trimmed.lowercased()
        }
    }

    func normalizeSuiTokenIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let components = trimmed.split(separator: "::", omittingEmptySubsequences: false)
        guard let first = components.first else { return trimmed }

        let normalizedPackage = normalizeSuiPackageComponent(String(first))
        guard components.count > 1 else { return normalizedPackage }
        return ([normalizedPackage] + components.dropFirst().map(String.init)).joined(separator: "::")
    }

    func normalizeSuiPackageComponent(_ value: String) -> String {
        guard value.hasPrefix("0x") else { return value }
        let hexPortion = value.dropFirst(2)
        let trimmedHex = hexPortion.drop { $0 == "0" }
        let canonicalHex = trimmedHex.isEmpty ? "0" : String(trimmedHex)
        return "0x" + canonicalHex
    }

    func normalizeAptosTokenIdentifier(_ value: String) -> String {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return "" }

        var result = ""
        var index = lowercased.startIndex
        while index < lowercased.endIndex {
            if lowercased[index...].hasPrefix("0x") {
                let start = index
                var end = lowercased.index(index, offsetBy: 2)
                while end < lowercased.endIndex, lowercased[end].isHexDigit {
                    end = lowercased.index(after: end)
                }
                result += canonicalAptosHexAddress(String(lowercased[start..<end]))
                index = end
            } else {
                result.append(lowercased[index])
                index = lowercased.index(after: index)
            }
        }
        return result
    }

    func canonicalAptosHexAddress(_ value: String) -> String {
        guard value.hasPrefix("0x") else { return value }
        let hexPortion = value.dropFirst(2)
        let trimmedHex = hexPortion.drop { $0 == "0" }
        let canonicalHex = trimmedHex.isEmpty ? "0" : String(trimmedHex)
        return "0x" + canonicalHex
    }

    func enabledEthereumTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .ethereum).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledBNBTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .bnb).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledArbitrumTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .arbitrum).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledOptimismTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .optimism).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledAvalancheTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .avalanche).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledHyperliquidTrackedTokens() -> [EthereumSupportedToken] {
        enabledTokenPreferences(for: .hyperliquid).map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: EthereumWalletEngine.normalizeAddress(entry.contractAddress),
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
    }

    func enabledTronTrackedTokens() -> [TronBalanceService.TrackedTRC20Token] {
        enabledTokenPreferences(for: .tron).map { entry in
            TronBalanceService.TrackedTRC20Token(
                symbol: entry.symbol,
                contractAddress: entry.contractAddress,
                decimals: entry.decimals
            )
        }
    }

    func solanaTrackedTokens(includeDisabled: Bool = false) -> [String: SolanaBalanceService.KnownTokenMetadata] {
        var result: [String: SolanaBalanceService.KnownTokenMetadata] = [:]
        let entries = includeDisabled ? tokenPreferences.filter { $0.chain == .solana } : enabledTokenPreferences(for: .solana)
        for entry in entries {
            result[entry.contractAddress] = SolanaBalanceService.KnownTokenMetadata(
                symbol: entry.symbol,
                name: entry.name,
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
        return result
    }

    func enabledSolanaTrackedTokens() -> [String: SolanaBalanceService.KnownTokenMetadata] {
        let configured = solanaTrackedTokens(includeDisabled: false)
        if configured.isEmpty {
            return SolanaBalanceService.knownTokenMetadataByMint
        }
        return configured
    }

    func enabledSuiTrackedTokens() -> [String: SuiBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .sui).map { entry in
                (
                    entry.contractAddress,
                    SuiBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol,
                        name: entry.name,
                        tokenStandard: entry.tokenStandard,
                        decimals: entry.decimals,
                        marketDataID: entry.marketDataID,
                        coinGeckoID: entry.coinGeckoID
                    )
                )
            }
        )
    }

    func enabledAptosTrackedTokens() -> [String: AptosBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .aptos).map { entry in
                (
                    normalizeAptosTokenIdentifier(entry.contractAddress),
                    AptosBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol,
                        name: entry.name,
                        tokenStandard: entry.tokenStandard,
                        decimals: entry.decimals,
                        marketDataID: entry.marketDataID,
                        coinGeckoID: entry.coinGeckoID
                    )
                )
            }
        )
    }

    func aptosPackageIdentifier(from value: String?) -> String {
        let normalized = normalizeAptosTokenIdentifier(value ?? "")
        guard let package = normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return normalized
        }
        return String(package)
    }

    func enabledNearTrackedTokens() -> [String: NearBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .near).map { entry in
                (
                    entry.contractAddress,
                    NearBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol,
                        name: entry.name,
                        tokenStandard: entry.tokenStandard,
                        decimals: entry.decimals,
                        marketDataID: entry.marketDataID,
                        coinGeckoID: entry.coinGeckoID
                    )
                )
            }
        )
    }

    func enabledTONTrackedTokens() -> [String: TONBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .ton).map { entry in
                (
                    TONBalanceService.normalizeJettonMasterAddress(entry.contractAddress),
                    TONBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol,
                        name: entry.name,
                        tokenStandard: entry.tokenStandard,
                        decimals: entry.decimals,
                        marketDataID: entry.marketDataID,
                        coinGeckoID: entry.coinGeckoID
                    )
                )
            }
        )
    }

    func isSupportedSolanaSendCoin(_ coin: Coin) -> Bool {
        guard coin.chainName == "Solana" else { return false }
        if coin.symbol == "SOL" {
            return true
        }
        guard coin.tokenStandard == TokenTrackingChain.solana.tokenStandard else {
            return false
        }
        let trackedTokens = solanaTrackedTokens(includeDisabled: true)
        guard let mintAddress = coin.contractAddress ?? SolanaBalanceService.mintAddress(for: coin.symbol) else {
            return false
        }
        return trackedTokens[mintAddress] != nil
    }

    var ethereumRPCEndpointValidationError: String? {
        let trimmedEndpoint = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return nil }
        guard let url = URL(string: trimmedEndpoint),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return "Enter a valid http or https RPC URL."
        }
        return nil
    }

    var moneroBackendBaseURLValidationError: String? {
        let trimmedEndpoint = moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return nil }
        guard let url = URL(string: trimmedEndpoint),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return "Enter a valid http or https Monero backend URL."
        }
        return nil
    }

    // Clears transient import form UI state and any previous import errors.

}
