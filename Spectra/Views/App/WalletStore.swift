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
    private static let operationalLogTimestampFormatter = ISO8601DateFormatter()

    enum ResetScope: String, CaseIterable, Identifiable {
        case walletsAndSecrets
        case historyAndCache
        case alertsAndContacts
        case settingsAndEndpoints
        case dashboardCustomization
        case providerState

        var id: String { rawValue }

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
    private enum TimeoutError: LocalizedError {
        case timedOut(seconds: Double)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds):
                let format = NSLocalizedString("Timed out after %ds", comment: "")
                return String(format: format, locale: Locale.current, Int(seconds))
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
                return NSLocalizedString("No seed phrase is stored for this wallet.", comment: "")
            case .authenticationRequired:
                return NSLocalizedString("Face ID authentication is required to view this seed phrase.", comment: "")
            case .passwordRequired:
                return NSLocalizedString("Enter the wallet password to view this seed phrase.", comment: "")
            case .invalidPassword:
                return NSLocalizedString("The wallet password is incorrect.", comment: "")
            }
        }
    }
    enum BackgroundSyncProfile: String, CaseIterable, Identifiable {
        case conservative
        case balanced
        case aggressive

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .conservative: return localizedStoreString("Conservative")
            case .balanced: return localizedStoreString("Balanced")
            case .aggressive: return localizedStoreString("Aggressive")
            }
        }
    }
    let logger = Logger(subsystem: "com.spectra.wallet", category: "dogecoin")
    private let balanceTelemetryLogger = Logger(subsystem: "com.spectra.wallet", category: "balance.telemetry")
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

    private struct PendingTransactionStatusResolution {
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
    private var importRefreshTask: Task<Void, Never>?
    var walletSideEffectsTask: Task<Void, Never>?
    private var portfolioStateObservation: AnyCancellable?
    private var walletCollectionObservation: AnyCancellable?
    private var flowStateObservation: AnyCancellable?
    private var runtimeStateObservation: AnyCancellable?
    private var diagnosticsObservation: AnyCancellable?
    private var chainDiagnosticsStateObservation: AnyCancellable?
    private var sendStateObservation: AnyCancellable?
    private var transactionStateObservation: AnyCancellable?
    private var transactionMutationObservation: AnyCancellable?
    var lastHistoryRefreshAtByChain: [String: Date] = [:]
    var appIsActive = true
    private var maintenanceTask: Task<Void, Never>?
    var lastObservedPortfolioTotalUSD: Double?
    var lastObservedPortfolioCompositionSignature: String?
#if canImport(Network)
    private let networkPathMonitor = NWPathMonitor()
    private let networkPathMonitorQueue = DispatchQueue(label: "spectra.network.monitor")
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
    private static let dogecoinDiscoveryGapLimit = 3
    private static let dogecoinDiscoveryMaxIndex = 40
    private static let utxoDiscoveryGapLimit = 3
    private static let utxoDiscoveryMaxIndex = 40
    private static let pendingStatusPollSeconds: TimeInterval = 20
    private static let confirmedStatusPollSeconds: TimeInterval = 300
    private static let statusPollBackoffMaxSeconds: TimeInterval = 600
    private static let standardFinalityConfirmations = 12
    private static let pendingFailureTimeoutSeconds: TimeInterval = 60 * 60
    private static let pendingFailureMinFailures = 6
    private static let selfSendConfirmationWindowSeconds: TimeInterval = 20
    private static let activeMaintenancePollSeconds: UInt64 = 30
    private static let inactiveMaintenancePollSeconds: UInt64 = 60
    static let activePendingRefreshInterval: TimeInterval = 60
    private static let activePriceRefreshInterval: TimeInterval = 300
    private static let fiatRatesRefreshInterval: TimeInterval = 6 * 60 * 60
    private static let backgroundMaintenanceInterval: TimeInterval = 15 * 60
    static let constrainedBackgroundMaintenanceInterval: TimeInterval = 30 * 60
    static let lowPowerBackgroundMaintenanceInterval: TimeInterval = 45 * 60
    static let lowBatteryBackgroundMaintenanceInterval: TimeInterval = 60 * 60
    private static let foregroundFullRefreshStalenessInterval: TimeInterval = 2 * 60
    static let automaticChainRefreshStalenessInterval: TimeInterval = 10 * 60
    // MARK: - Seed and Endpoint Utilities
    private static func seedPhraseAccount(for walletID: UUID) -> String {
        "wallet.seed.\(walletID.uuidString)"
    }

    private static func seedPhrasePasswordAccount(for walletID: UUID) -> String {
        "wallet.seed.password.\(walletID.uuidString)"
    }

    private static func privateKeyAccount(for walletID: UUID) -> String {
        "wallet.privatekey.\(walletID.uuidString)"
    }

    // Reads seed phrase material for a wallet from the dedicated seed keychain namespace.
    // Returns nil when no seed exists, which is the expected state for some watched-address wallets.
    func storedSeedPhrase(for walletID: UUID) -> String? {
        let account = Self.seedPhraseAccount(for: walletID)
        guard let seedPhrase = try? SecureSeedStore.loadValue(for: account), !seedPhrase.isEmpty else {
            return nil
        }
        return seedPhrase
    }

    func storedPrivateKey(for walletID: UUID) -> String? {
        let account = Self.privateKeyAccount(for: walletID)
        let privateKey = SecurePrivateKeyStore.loadValue(for: account)
        return privateKey.isEmpty ? nil : privateKey
    }

    func walletRequiresSeedPhrasePassword(_ walletID: UUID) -> Bool {
        SecureSeedPasswordStore.hasPassword(for: Self.seedPhrasePasswordAccount(for: walletID))
    }

    func signingMaterialAvailability(for walletID: UUID) -> (hasSigningMaterial: Bool, isPrivateKeyBacked: Bool) {
        let hasSeedPhrase = storedSeedPhrase(for: walletID) != nil
        let hasPrivateKey = storedPrivateKey(for: walletID) != nil
        return (hasSeedPhrase || hasPrivateKey, hasPrivateKey)
    }

    func walletHasSigningMaterial(_ walletID: UUID) -> Bool {
        if cachedSigningMaterialWalletIDs.contains(walletID) {
            return true
        }
        if !cachedWalletByID.isEmpty || !cachedWalletByIDString.isEmpty {
            return false
        }
        return signingMaterialAvailability(for: walletID).hasSigningMaterial
    }

    private func isPrivateKeyBackedWallet(_ walletID: UUID) -> Bool {
        if cachedPrivateKeyBackedWalletIDs.contains(walletID) {
            return true
        }
        if !cachedWalletByID.isEmpty || !cachedWalletByIDString.isEmpty {
            return false
        }
        return signingMaterialAvailability(for: walletID).isPrivateKeyBacked
    }

    func deleteWalletSecrets(for walletID: UUID) {
        let seedAccount = Self.seedPhraseAccount(for: walletID)
        let seedPasswordAccount = Self.seedPhrasePasswordAccount(for: walletID)
        let privateKeyAccount = Self.privateKeyAccount(for: walletID)
        try? SecureSeedStore.deleteValue(for: seedAccount)
        try? SecureSeedPasswordStore.deleteValue(for: seedPasswordAccount)
        SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
    }

    // Parses user-configured Esplora endpoints supporting comma/newline/semicolon separators.
    private func parsedBitcoinEsploraEndpoints() -> [String] {
        bitcoinEsploraEndpoints
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // Effective endpoint resolver:
    // use configured endpoints when present, otherwise fall back to network-specific defaults.
    private func effectiveBitcoinEsploraEndpoints() -> [String] {
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

    private func applySendVerificationStatus(_ verificationStatus: SendBroadcastVerificationStatus, chainName: String) {
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
    // This only affects detection/tracking, not private key derivation behavior.
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
    private func enabledTokenPreferences(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
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

    private func normalizeSuiTokenIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let components = trimmed.split(separator: "::", omittingEmptySubsequences: false)
        guard let first = components.first else { return trimmed }

        let normalizedPackage = normalizeSuiPackageComponent(String(first))
        guard components.count > 1 else { return normalizedPackage }
        return ([normalizedPackage] + components.dropFirst().map(String.init)).joined(separator: "::")
    }

    private func normalizeSuiPackageComponent(_ value: String) -> String {
        guard value.hasPrefix("0x") else { return value }
        let hexPortion = value.dropFirst(2)
        let trimmedHex = hexPortion.drop { $0 == "0" }
        let canonicalHex = trimmedHex.isEmpty ? "0" : String(trimmedHex)
        return "0x" + canonicalHex
    }

    private func normalizeAptosTokenIdentifier(_ value: String) -> String {
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

    private func canonicalAptosHexAddress(_ value: String) -> String {
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

    private func enabledAvalancheTrackedTokens() -> [EthereumSupportedToken] {
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

    private func aptosPackageIdentifier(from value: String?) -> String {
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
    // MARK: - Import and Wallet Lifecycle
func resetImportForm() {
    importDraft.configureForNewWallet()
}

    // Opens import flow and prepares draft defaults for a new import action.
    func beginWalletImport() {
        importDraft.configureForNewWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }

    // Opens watch-address import flow and preconfigures the draft for public-address import.
    func beginWatchAddressesImport() {
        importDraft.configureForWatchAddressesImport()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }

    // Opens create-wallet flow and preconfigures the draft for generated wallets.
    func beginWalletCreation() {
        importDraft.configureForCreatedWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }

    func cancelWalletImport() {
        importDraft.configureForNewWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = false
    }

    // Populates import draft from an existing wallet for in-place editing.
    func beginEditingWallet(_ wallet: ImportedWallet) {
        editingWalletID = wallet.id
        importError = nil
        isImportingWallet = false
        importDraft.configureForEditing(wallet: wallet)
        isShowingWalletImporter = true
    }
    
    func confirmDeleteWallet(_ wallet: ImportedWallet) {
        walletPendingDeletion = wallet
    }
    
    // Deletes the selected wallet and triggers cleanup of related state/history.
    func deletePendingWallet() async {
        guard let walletPendingDeletion else { return }
        guard await authenticateForSensitiveAction(
            reason: "Authenticate to delete wallet",
            allowWhenAuthenticationUnavailable: true
        ) else {
            return
        }
        let deletedWalletID = walletPendingDeletion.id
        let deletedWalletIDString = deletedWalletID.uuidString
        let deletedChainName = normalizedWalletChainName(walletPendingDeletion.selectedChain)
        deleteWalletSecrets(for: deletedWalletID)
        wallets.removeAll { $0.id == walletPendingDeletion.id }
        let hasRemainingWalletsOnDeletedChain = wallets.contains {
            normalizedWalletChainName($0.selectedChain) == deletedChainName
        }
        resetLargeMovementAlertBaseline()
        transactions.removeAll { $0.walletID == walletPendingDeletion.id }
        dogecoinKeypoolByWalletID[walletPendingDeletion.id] = nil
        discoveredDogecoinAddressesByWallet[walletPendingDeletion.id] = nil
        for chainName in discoveredUTXOAddressesByChain.keys {
            discoveredUTXOAddressesByChain[chainName]?[walletPendingDeletion.id] = nil
        }
        clearHistoryTracking(for: walletPendingDeletion.id)
        clearDeletedWalletDiagnostics(
            walletID: deletedWalletID,
            chainName: deletedChainName,
            hasRemainingWalletsOnChain: hasRemainingWalletsOnDeletedChain
        )
        dogecoinOwnedAddressMap = dogecoinOwnedAddressMap.filter { _, value in
            value.walletID != walletPendingDeletion.id
        }
        if receiveWalletID == deletedWalletIDString {
            receiveWalletID = ""
            receiveChainName = ""
            receiveHoldingKey = ""
            receiveResolvedAddress = ""
            isResolvingReceiveAddress = false
        }
        if sendWalletID == deletedWalletIDString {
            cancelSend()
        }
        if editingWalletID == deletedWalletID {
            editingWalletID = nil
            isShowingWalletImporter = false
        }
        selectedMainTab = .home
        self.walletPendingDeletion = nil
        
        if wallets.isEmpty {
            cancelWalletImport()
        }
    }
    
    func wallet(for walletID: String) -> ImportedWallet? {
        cachedWalletByIDString[walletID]
    }

    func knownOwnedAddresses(for walletID: UUID) -> [String] {
        guard let wallet = cachedWalletByID[walletID] else { return [] }

        var ordered: [String] = []
        var seen: Set<String> = []

        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }

        appendAddress(wallet.bitcoinAddress)
        appendAddress(wallet.bitcoinCashAddress)
        appendAddress(wallet.bitcoinSVAddress)
        appendAddress(wallet.litecoinAddress)
        appendAddress(wallet.dogecoinAddress)
        appendAddress(wallet.ethereumAddress)
        appendAddress(wallet.tronAddress)
        appendAddress(wallet.solanaAddress)
        appendAddress(wallet.stellarAddress)
        appendAddress(wallet.xrpAddress)
        appendAddress(wallet.moneroAddress)
        appendAddress(wallet.cardanoAddress)
        appendAddress(wallet.suiAddress)
        appendAddress(wallet.aptosAddress)
        appendAddress(wallet.icpAddress)
        appendAddress(wallet.nearAddress)
        appendAddress(wallet.polkadotAddress)

        appendAddress(resolvedBitcoinCashAddress(for: wallet))
        appendAddress(resolvedBitcoinSVAddress(for: wallet))
        appendAddress(resolvedLitecoinAddress(for: wallet))
        appendAddress(resolvedDogecoinAddress(for: wallet))
        appendAddress(resolvedEthereumAddress(for: wallet))
        appendAddress(resolvedTronAddress(for: wallet))
        appendAddress(resolvedSolanaAddress(for: wallet))
        appendAddress(resolvedXRPAddress(for: wallet))
        appendAddress(resolvedStellarAddress(for: wallet))
        appendAddress(resolvedMoneroAddress(for: wallet))
        appendAddress(resolvedCardanoAddress(for: wallet))
        appendAddress(resolvedSuiAddress(for: wallet))
        appendAddress(resolvedAptosAddress(for: wallet))
        appendAddress(resolvedTONAddress(for: wallet))
        appendAddress(resolvedICPAddress(for: wallet))
        appendAddress(resolvedNearAddress(for: wallet))
        appendAddress(resolvedPolkadotAddress(for: wallet))

        for transaction in transactions where transaction.walletID == walletID {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }

        for addresses in chainOwnedAddressMapByChain.values {
            for value in addresses.values where value.walletID == walletID {
                appendAddress(value.address)
            }
        }

        return ordered
    }

    func canRevealSeedPhrase(for walletID: UUID) -> Bool {
        storedSeedPhrase(for: walletID) != nil
    }

    func verifySeedPhrasePassword(_ password: String, for walletID: UUID) -> Bool {
        let account = Self.seedPhrasePasswordAccount(for: walletID)
        return SecureSeedPasswordStore.verify(password, for: account)
    }

    func isWatchOnlyWallet(_ wallet: ImportedWallet) -> Bool {
        !walletHasSigningMaterial(wallet.id)
    }

    func isPrivateKeyWallet(_ wallet: ImportedWallet) -> Bool {
        isPrivateKeyBackedWallet(wallet.id)
    }

    func revealSeedPhrase(for wallet: ImportedWallet, password: String? = nil) async throws -> String {
        let authenticated = await authenticateForSeedPhraseReveal(reason: "Authenticate to view seed phrase for \(wallet.name)")
        guard authenticated else {
            throw SeedPhraseRevealError.authenticationRequired
        }

        if walletRequiresSeedPhrasePassword(wallet.id) {
            guard let providedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !providedPassword.isEmpty else {
                throw SeedPhraseRevealError.passwordRequired
            }
            guard verifySeedPhrasePassword(providedPassword, for: wallet.id) else {
                throw SeedPhraseRevealError.invalidPassword
            }
        }

        guard let seedPhrase = storedSeedPhrase(for: wallet.id),
              !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SeedPhraseRevealError.unavailable
        }
        return seedPhrase
    }

    // Computes current sendable assets for a wallet based on selected chains and holdings.
    func availableSendCoins(for walletID: String) -> [Coin] {
        cachedAvailableSendCoinsByWalletID[walletID] ?? []
    }
    
    func availableReceiveCoins(for walletID: String) -> [Coin] {
        cachedAvailableReceiveCoinsByWalletID[walletID] ?? []
    }

    func availableReceiveChains(for walletID: String) -> [String] {
        cachedAvailableReceiveChainsByWalletID[walletID] ?? []
    }

    func selectedReceiveCoin(for walletID: String) -> Coin? {
        let resolvedChainName = resolvedReceiveChainName(for: walletID)
        guard !resolvedChainName.isEmpty else { return nil }

        var firstMatchingCoin: Coin?
        for coin in availableReceiveCoins(for: walletID) where coin.chainName == resolvedChainName {
            if firstMatchingCoin == nil {
                firstMatchingCoin = coin
            }
            if coin.contractAddress == nil {
                return coin
            }
        }
        return firstMatchingCoin
    }

    private func resolvedReceiveChainName(for walletID: String) -> String {
        let availableChains = availableReceiveChains(for: walletID)
        if availableChains.contains(receiveChainName) {
            return receiveChainName
        }
        return availableChains.first ?? ""
    }

    var sendEnabledWallets: [ImportedWallet] {
        cachedSendEnabledWallets
    }

    var receiveEnabledWallets: [ImportedWallet] {
        cachedReceiveEnabledWallets
    }

    var canBeginSend: Bool {
        !sendEnabledWallets.isEmpty
    }

    var canBeginReceive: Bool {
        !receiveEnabledWallets.isEmpty
    }
    
    var alertableCoins: [Coin] {
        portfolio
    }

    var sendAddressBookEntries: [AddressBookEntry] {
        guard let selectedSendCoin else { return [] }
        return addressBook.filter { $0.chainName == selectedSendCoin.chainName }
    }

    var hasPendingEthereumSendForSelectedWallet: Bool {
        selectedPendingEthereumSendTransaction() != nil
    }

    var ethereumReplacementNonceStateMessage: String? {
        guard selectedSendCoin?.chainName == "Ethereum" else { return nil }
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            return localizedStoreString("No pending Ethereum send found for this wallet. Replacement and cancel are available only for pending transactions.")
        }

        var message = localizedStoreFormat("Pending %@ transaction detected", pendingTransaction.symbol)
        if let nonce = pendingTransaction.ethereumNonce {
            message += localizedStoreFormat("send.replacement.pendingNonceSuffix", nonce)
        } else {
            message += "."
        }
        if let transactionHash = pendingTransaction.transactionHash {
            let shortHash = transactionHash.count > 14
                ? "\(transactionHash.prefix(10))...\(transactionHash.suffix(4))"
                : transactionHash
            message += localizedStoreFormat("send.replacement.transactionSuffix", shortHash)
        }
        message += localizedStoreString(" Use Speed Up to resend with higher fees or Cancel to submit a 0-value self-transfer using the same nonce.")
        return message
    }
    
    // Initializes the send composer with defaults inferred from selected wallet/assets.
    // MARK: - Send Flow
    func beginSend() {
        guard let firstWallet = sendEnabledWallets.first else { return }
        sendWalletID = firstWallet.id.uuidString
        sendHoldingKey = availableSendCoins(for: sendWalletID).first?.holdingKey ?? ""
        sendAmount = ""
        sendAddress = ""
        sendError = nil
        sendDestinationRiskWarning = nil
        sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEthereumFees = false
        customEthereumMaxFeeGwei = ""
        customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false
        sendUTXOMaxInputCount = 0
        sendEnableRBF = true
        sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange
        ethereumManualNonceEnabled = false
        ethereumManualNonce = ""
        lastSentTransaction = nil
        bitcoinSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        bitcoinCashSendPreview = nil
        bitcoinSVSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        stellarSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        aptosSendPreview = nil
        tonSendPreview = nil
        icpSendPreview = nil
        nearSendPreview = nil
        polkadotSendPreview = nil
        isSendingBitcoin = false
        isSendingBitcoinCash = false
        isSendingBitcoinSV = false
        isSendingLitecoin = false
        isSendingDogecoin = false
        isSendingEthereum = false
        isSendingTron = false
        isSendingSolana = false
        isSendingXRP = false
        isSendingStellar = false
        isSendingMonero = false
        isSendingCardano = false
        isSendingSui = false
        isSendingAptos = false
        isSendingTON = false
        isSendingICP = false
        isSendingNear = false
        isSendingPolkadot = false
        isPreparingEthereumSend = false
        isPreparingDogecoinSend = false
        isPreparingTronSend = false
        isPreparingSolanaSend = false
        isPreparingXRPSend = false
        isPreparingStellarSend = false
        isPreparingMoneroSend = false
        isPreparingCardanoSend = false
        isPreparingSuiSend = false
        isPreparingAptosSend = false
        isPreparingTONSend = false
        isPreparingICPSend = false
        isPreparingNearSend = false
        isPreparingPolkadotSend = false
        pendingDogecoinSelfSendConfirmation = nil
        clearHighRiskSendConfirmation()
        syncSendAssetSelection()
        isShowingSendSheet = true
    }
    
    // Reconciles selected send asset when wallet/chain selection changes.
    func syncSendAssetSelection() {
        let availableHoldingKeys = availableSendCoins(for: sendWalletID).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendHoldingKey) {
            sendHoldingKey = availableHoldingKeys.first ?? ""
        }
        if selectedSendCoin?.chainName != "Ethereum" {
            useCustomEthereumFees = false
            customEthereumMaxFeeGwei = ""
            customEthereumPriorityFeeGwei = ""
            ethereumManualNonceEnabled = false
            ethereumManualNonce = ""
        }
        if selectedSendCoin?.chainName != "Litecoin" {
            sendLitecoinChangeStrategy = .derivedChange
        }
        lastSentTransaction = nil
        bitcoinSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        bitcoinCashSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        isSendingBitcoin = false
        isSendingBitcoinCash = false
        isSendingLitecoin = false
        isSendingDogecoin = false
        isSendingEthereum = false
        isSendingTron = false
        isSendingSolana = false
        isSendingXRP = false
        isSendingMonero = false
        isSendingCardano = false
        isSendingSui = false
        isPreparingEthereumSend = false
        isPreparingDogecoinSend = false
        isPreparingTronSend = false
        isPreparingSolanaSend = false
        isPreparingXRPSend = false
        isPreparingMoneroSend = false
        isPreparingCardanoSend = false
        isPreparingSuiSend = false
        pendingDogecoinSelfSendConfirmation = nil
        sendDestinationRiskWarning = nil
        sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
        clearHighRiskSendConfirmation()
    }
    
    // Closes send composer and clears all transient send state/error fields.
    func cancelSend() {
        isShowingSendSheet = false
        sendAmount = ""
        sendAddress = ""
        sendError = nil
        sendDestinationRiskWarning = nil
        sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEthereumFees = false
        customEthereumMaxFeeGwei = ""
        customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false
        sendUTXOMaxInputCount = 0
        sendEnableRBF = true
        sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange
        ethereumManualNonceEnabled = false
        ethereumManualNonce = ""
        lastSentTransaction = nil
        bitcoinSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        bitcoinCashSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        isSendingBitcoin = false
        isSendingBitcoinCash = false
        isSendingLitecoin = false
        isSendingDogecoin = false
        isSendingEthereum = false
        isSendingTron = false
        isSendingSolana = false
        isSendingXRP = false
        isSendingMonero = false
        isSendingCardano = false
        isSendingSui = false
        isPreparingEthereumSend = false
        isPreparingDogecoinSend = false
        isPreparingTronSend = false
        isPreparingSolanaSend = false
        isPreparingXRPSend = false
        isPreparingMoneroSend = false
        isPreparingCardanoSend = false
        isPreparingSuiSend = false
        pendingDogecoinSelfSendConfirmation = nil
        clearHighRiskSendConfirmation()
    }

    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendWalletID).first(where: { $0.holdingKey == sendHoldingKey })
    }

    func sendPreviewDetails(for coin: Coin) -> SendPreviewDetails? {
        switch coin.chainName {
        case "Bitcoin":
            guard let preview = bitcoinSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC),
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: preview.selectedInputCount,
                usesChangeOutput: preview.usesChangeOutput,
                maxSendable: preview.maxSendable ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC)
            )
        case "Bitcoin Cash":
            guard let preview = bitcoinCashSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC),
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: preview.selectedInputCount,
                usesChangeOutput: preview.usesChangeOutput,
                maxSendable: preview.maxSendable ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC)
            )
        case "Bitcoin SV":
            guard let preview = bitcoinSVSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC),
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: preview.selectedInputCount,
                usesChangeOutput: preview.usesChangeOutput,
                maxSendable: preview.maxSendable ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC)
            )
        case "Litecoin":
            guard let preview = litecoinSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC),
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: preview.selectedInputCount,
                usesChangeOutput: preview.usesChangeOutput,
                maxSendable: preview.maxSendable ?? max(0, coin.amount - preview.estimatedNetworkFeeBTC)
            )
        case "Dogecoin":
            guard let preview = dogecoinSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: preview.selectedInputCount,
                usesChangeOutput: preview.usesChangeOutput,
                maxSendable: preview.maxSendable
            )
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            guard let preview = ethereumSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Tron":
            guard let preview = tronSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Solana":
            guard let preview = solanaSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "XRP Ledger":
            guard let preview = xrpSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Stellar":
            guard let preview = stellarSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Monero":
            guard let preview = moneroSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Cardano":
            guard let preview = cardanoSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Sui":
            guard let preview = suiSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Aptos":
            guard let preview = aptosSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "TON":
            guard let preview = tonSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Internet Computer":
            guard let preview = icpSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "NEAR":
            guard let preview = nearSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        case "Polkadot":
            guard let preview = polkadotSendPreview else { return nil }
            return SendPreviewDetails(
                spendableBalance: preview.spendableBalance,
                feeRateDescription: preview.feeRateDescription,
                estimatedTransactionBytes: preview.estimatedTransactionBytes,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: preview.maxSendable
            )
        default:
            return nil
        }
    }

    var customEthereumFeeValidationError: String? {
        guard useCustomEthereumFees,
              selectedSendCoin?.chainName == "Ethereum" else {
            return nil
        }

        let trimmedMaxFee = customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPriorityFee = customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let maxFee = Double(trimmedMaxFee), maxFee > 0 else {
            return localizedStoreString("Enter a valid Max Fee in gwei.")
        }
        guard let priorityFee = Double(trimmedPriorityFee), priorityFee > 0 else {
            return localizedStoreString("Enter a valid Priority Fee in gwei.")
        }
        guard maxFee >= priorityFee else {
            return localizedStoreString("Max Fee must be greater than or equal to Priority Fee.")
        }
        return nil
    }

    func customEthereumFeeConfiguration() -> EthereumCustomFeeConfiguration? {
        guard useCustomEthereumFees else { return nil }
        guard customEthereumFeeValidationError == nil else { return nil }
        guard let maxFee = Double(customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)),
              let priorityFee = Double(customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return EthereumCustomFeeConfiguration(
            maxFeePerGasGwei: maxFee,
            maxPriorityFeePerGasGwei: priorityFee
        )
    }

    var customEthereumNonceValidationError: String? {
        guard ethereumManualNonceEnabled else { return nil }
        let trimmedNonce = ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNonce.isEmpty else {
            return localizedStoreString("Enter a nonce value for manual nonce mode.")
        }
        guard let nonceValue = Int(trimmedNonce), nonceValue >= 0 else {
            return localizedStoreString("Nonce must be a non-negative integer.")
        }
        if nonceValue > Int(Int32.max) {
            return localizedStoreString("Nonce value is too large.")
        }
        return nil
    }

    func explicitEthereumNonce() -> Int? {
        guard ethereumManualNonceEnabled else { return nil }
        guard customEthereumNonceValidationError == nil else { return nil }
        return Int(ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func selectedWalletForSend() -> ImportedWallet? {
        wallet(for: sendWalletID)
    }

    private func selectedPendingEthereumSendTransaction() -> TransactionRecord? {
        guard let wallet = selectedWalletForSend() else { return nil }
        return transactions.first { record in
            record.walletID == wallet.id
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }

    private func pendingEthereumSendTransaction(with transactionID: UUID) -> TransactionRecord? {
        transactions.first { record in
            record.id == transactionID
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }

    func prepareEthereumReplacementContext(cancel: Bool) async {
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
    }

    func openEthereumReplacementComposer(for transactionID: UUID, cancel: Bool) async -> String? {
        guard let pendingTransaction = pendingEthereumSendTransaction(with: transactionID) else {
            let message = localizedStoreString("This Ethereum transaction is no longer pending, so replacement/cancel is unavailable.")
            sendError = message
            return message
        }
        guard let walletID = pendingTransaction.walletID,
              wallets.contains(where: { $0.id == walletID }) else {
            let message = localizedStoreString("The wallet for this pending transaction is not available.")
            sendError = message
            return message
        }

        sendWalletID = walletID.uuidString
        if let ethereumHolding = availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" && $0.symbol == "ETH" })
            ?? availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" }) {
            sendHoldingKey = ethereumHolding.holdingKey
        }
        syncSendAssetSelection()
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
        return sendError
    }

    private func prepareEthereumReplacementContext(pendingTransaction: TransactionRecord, cancel: Bool) async {
        guard let txHash = pendingTransaction.transactionHash else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        isPreparingEthereumReplacementContext = true
        defer { isPreparingEthereumReplacementContext = false }
        do {
            let nonce = try await EthereumWalletEngine.fetchTransactionNonce(
                for: txHash,
                rpcEndpoint: configuredEthereumRPCEndpointURL()
            )
            guard let walletID = pendingTransaction.walletID,
                  let wallet = wallets.first(where: { $0.id == walletID }) else {
                sendError = localizedStoreString("Select a wallet first.")
                return
            }
            let selfAddress = wallet.ethereumAddress ?? ""
            sendAddress = cancel ? selfAddress : pendingTransaction.address
            sendAmount = cancel ? "0" : String(format: "%.8f", pendingTransaction.amount)
            ethereumManualNonceEnabled = true
            ethereumManualNonce = String(nonce)
            useCustomEthereumFees = true
            if customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customEthereumMaxFeeGwei = "4.0"
                customEthereumPriorityFeeGwei = "2.0"
            } else {
                let maxFee = (Double(customEthereumMaxFeeGwei) ?? 4.0) * 1.2
                let priority = (Double(customEthereumPriorityFeeGwei) ?? 2.0) * 1.2
                customEthereumMaxFeeGwei = String(format: "%.3f", max(maxFee, 0.1))
                customEthereumPriorityFeeGwei = String(format: "%.3f", max(priority, 0.1))
            }
            sendError = cancel
                ? localizedStoreString("Cancellation context loaded. Review fees and tap Send.")
                : localizedStoreString("Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            sendError = localizedStoreFormat("Unable to prepare replacement context: %@", error.localizedDescription)
        }
    }

    func prepareEthereumSpeedUpContext() async {
        await prepareEthereumReplacementContext(cancel: false)
    }

    func prepareEthereumCancelContext() async {
        await prepareEthereumReplacementContext(cancel: true)
    }

    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    func mapEthereumSendError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()

        if message.contains("nonce too low") {
            return localizedStoreString("Nonce too low. A newer transaction from this wallet is already known. Refresh and retry.")
        }
        if message.contains("replacement transaction underpriced") {
            return localizedStoreString("Replacement transaction underpriced. Increase fees and retry.")
        }
        if message.contains("already known") {
            return localizedStoreString("This transaction is already in the mempool.")
        }
        if message.contains("insufficient funds") {
            return localizedStoreString("Insufficient ETH to cover value plus network fee.")
        }
        if message.contains("max fee per gas less than block base fee") {
            return localizedStoreString("Max fee is below current base fee. Increase Max Fee and retry.")
        }
        if message.contains("intrinsic gas too low") {
            return localizedStoreString("Gas limit is too low for this transaction.")
        }
        return error.localizedDescription
    }

    func evmChainContext(for chainName: String) -> EVMChainContext? {
        switch chainName {
        case "Ethereum":
            switch ethereumNetworkMode {
            case .mainnet:
                return .ethereum
            case .sepolia:
                return .ethereumSepolia
            case .hoodi:
                return .ethereumHoodi
            }
        case "Ethereum Classic":
            return .ethereumClassic
        case "Arbitrum":
            return .arbitrum
        case "Optimism":
            return .optimism
        case "BNB Chain":
            return .bnb
        case "Avalanche":
            return .avalanche
        case "Hyperliquid":
            return .hyperliquid
        default:
            return nil
        }
    }

    func isEVMChain(_ chainName: String) -> Bool {
        evmChainContext(for: chainName) != nil
    }

    func configuredEVMRPCEndpointURL(for chainName: String) -> URL? {
        switch chainName {
        case "Ethereum":
            return configuredEthereumRPCEndpointURL()
        case "Arbitrum":
            return nil
        case "Optimism":
            return nil
        case "Ethereum Classic":
            return nil
        case "BNB Chain":
            return nil
        default:
            return nil
        }
    }

    func supportedEVMToken(for coin: Coin) -> EthereumSupportedToken? {
        guard let chain = evmChainContext(for: coin.chainName) else {
            return nil
        }
        if coin.chainName == "Ethereum", coin.symbol == "ETH" {
            return nil
        }
        if coin.chainName == "Ethereum Classic", coin.symbol == "ETC" {
            return nil
        }
        if coin.chainName == "Optimism", coin.symbol == "ETH" {
            return nil
        }
        if coin.chainName == "BNB Chain", coin.symbol == "BNB" {
            return nil
        }
        if coin.chainName == "Avalanche", coin.symbol == "AVAX" {
            return nil
        }
        if coin.chainName == "Hyperliquid", coin.symbol == "HYPE" {
            return nil
        }
        let chainTokens: [EthereumSupportedToken]
        if chain == .ethereum {
            chainTokens = enabledEthereumTrackedTokens()
        } else if chain == .bnb {
            chainTokens = enabledBNBTrackedTokens()
        } else if chain == .optimism {
            chainTokens = enabledOptimismTrackedTokens()
        } else if chain == .avalanche {
            chainTokens = enabledAvalancheTrackedTokens()
        } else {
            chainTokens = EthereumWalletEngine.supportedTokens(for: chain)
        }

        if let contractAddress = coin.contractAddress {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(contractAddress)
            return chainTokens.first {
                $0.symbol == coin.symbol && $0.contractAddress == normalizedContract
            }
        }

        return chainTokens.first { $0.symbol == coin.symbol }
    }

    func isValidDogecoinAddressForPolicy(
        _ address: String,
        networkMode: DogecoinNetworkMode? = nil
    ) -> Bool {
        AddressValidation.isValidDogecoinAddress(address, networkMode: networkMode ?? dogecoinNetworkMode)
    }

    private func isValidAddress(_ address: String, for chainName: String) -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return false }

        switch chainName {
        case "Bitcoin":
            return AddressValidation.isValidBitcoinAddress(trimmedAddress, networkMode: self.bitcoinNetworkMode)
        case "Bitcoin Cash":
            return AddressValidation.isValidBitcoinCashAddress(trimmedAddress)
        case "Bitcoin SV":
            return AddressValidation.isValidBitcoinSVAddress(trimmedAddress)
        case "Litecoin":
            return AddressValidation.isValidLitecoinAddress(trimmedAddress)
        case "Dogecoin":
            return isValidDogecoinAddressForPolicy(trimmedAddress)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return AddressValidation.isValidEthereumAddress(trimmedAddress)
        case "Tron":
            return AddressValidation.isValidTronAddress(trimmedAddress)
        case "Solana":
            return AddressValidation.isValidSolanaAddress(trimmedAddress)
        case "Cardano":
            return AddressValidation.isValidCardanoAddress(trimmedAddress)
        case "XRP Ledger":
            return AddressValidation.isValidXRPAddress(trimmedAddress)
        case "Stellar":
            return AddressValidation.isValidStellarAddress(trimmedAddress)
        case "Monero":
            return AddressValidation.isValidMoneroAddress(trimmedAddress)
        case "Sui":
            return AddressValidation.isValidSuiAddress(trimmedAddress)
        case "Aptos":
            return AddressValidation.isValidAptosAddress(trimmedAddress)
        case "TON":
            return AddressValidation.isValidTONAddress(trimmedAddress)
        case "Internet Computer":
            return AddressValidation.isValidICPAddress(trimmedAddress)
        case "NEAR":
            return AddressValidation.isValidNearAddress(trimmedAddress)
        case "Polkadot":
            return AddressValidation.isValidPolkadotAddress(trimmedAddress)
        default:
            return false
        }
    }

    private func normalizedAddress(_ address: String, for chainName: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chainName {
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return EthereumWalletEngine.normalizeAddress(trimmedAddress)
        case "Tron":
            return trimmedAddress
        case "Solana":
            return trimmedAddress
        case "Stellar":
            return trimmedAddress
        case "Sui", "Aptos":
            let normalized = trimmedAddress.lowercased()
            return normalized.hasPrefix("0x") ? normalized : "0x\(normalized)"
        case "TON":
            return trimmedAddress
        case "Internet Computer":
            return trimmedAddress.lowercased()
        case "NEAR":
            return trimmedAddress.lowercased()
        case "Polkadot":
            return trimmedAddress
        default:
            return trimmedAddress
        }
    }

    func isENSNameCandidate(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasSuffix(".eth")
            && !normalized.contains(" ")
            && !normalized.hasPrefix("0x")
    }

    // Resolves final EVM recipient address, including optional ENS resolution.
    func resolveEVMRecipientAddress(
        input: String,
        for chainName: String
    ) async throws -> (address: String, usedENS: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EthereumWalletEngineError.invalidAddress
        }

        if AddressValidation.isValidEthereumAddress(trimmed) {
            return (EthereumWalletEngine.normalizeAddress(trimmed), false)
        }

        guard chainName == "Ethereum", isENSNameCandidate(trimmed) else {
            throw EthereumWalletEngineError.invalidAddress
        }

        let cacheKey = trimmed.lowercased()
        if let cached = cachedResolvedENSAddresses[cacheKey] {
            return (cached, true)
        }

        guard let resolved = try await EthereumWalletEngine.resolveENSAddress(trimmed, chain: .ethereum) else {
            throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name '\(trimmed)'.")
        }
        cachedResolvedENSAddresses[cacheKey] = resolved
        return (resolved, true)
    }

    func evmRecipientPreflightReasons(
        holding: Coin,
        chain: EVMChainContext,
        destinationAddress: String
    ) async -> [String] {
        var reasons: [String] = []
        let rpcEndpoint = configuredEVMRPCEndpointURL(for: holding.chainName)

        do {
            let recipientCode = try await EthereumWalletEngine.fetchCode(
                at: destinationAddress,
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
            if EthereumWalletEngine.hasContractCode(recipientCode) {
                reasons.append(localizedStoreFormat("Recipient is a smart contract on %@. Confirm it can receive %@ safely.", holding.chainName, holding.symbol))
            }
        } catch {
            reasons.append(localizedStoreFormat("Could not verify recipient contract state on %@. Review destination carefully.", holding.chainName))
        }

        if let token = supportedEVMToken(for: holding) {
            do {
                let contractCode = try await EthereumWalletEngine.fetchCode(
                    at: token.contractAddress,
                    rpcEndpoint: rpcEndpoint,
                    chain: chain
                )
                if !EthereumWalletEngine.hasContractCode(contractCode) {
                    reasons.append(localizedStoreFormat("Token contract %@ appears missing on %@. This may be a wrong-network token selection.", token.symbol, holding.chainName))
                }
            } catch {
                reasons.append(localizedStoreFormat("Could not verify %@ contract bytecode on %@.", token.symbol, holding.chainName))
            }
        }

        return reasons
    }

    // Produces explainable risk flags for the confirmation gate in send flow.
    func evaluateHighRiskSendReasons(
        wallet: ImportedWallet,
        holding: Coin,
        amount: Double,
        destinationAddress: String,
        destinationInput: String,
        usedENSResolution: Bool = false
    ) -> [String] {
        var reasons: [String] = []
        let normalizedDestination = normalizedAddress(destinationAddress, for: holding.chainName)

        if !isValidAddress(destinationAddress, for: holding.chainName) {
            reasons.append(localizedStoreFormat("The destination address format does not match %@.", holding.chainName))
        }

        let hasKnownAddressBookEntry = addressBook.contains { entry in
            entry.chainName == holding.chainName
                && normalizedAddress(entry.address, for: holding.chainName).caseInsensitiveCompare(normalizedDestination) == .orderedSame
        }
        let hasTransactionHistoryWithAddress = transactions.contains { record in
            record.chainName == holding.chainName
                && normalizedAddress(record.address, for: holding.chainName).caseInsensitiveCompare(normalizedDestination) == .orderedSame
        }
        if !hasKnownAddressBookEntry && !hasTransactionHistoryWithAddress {
            reasons.append(localizedStoreString("This is a new destination address with no prior history in this wallet."))
        }

        if usedENSResolution {
            reasons.append(localizedStoreFormat("ENS name '%@' resolved to %@. Confirm this resolved address before sending.", destinationInput, destinationAddress))
        }

        if holding.amount > 0 {
            let ratio = amount / holding.amount
            if ratio >= 0.25 {
                let formattedPercent = ratio.formatted(.percent.precision(.fractionLength(0)))
                reasons.append(localizedStoreFormat("This send is %@ of your %@ balance.", formattedPercent, holding.symbol))
            }
        }

        if holding.chainName == "Ethereum" || holding.chainName == "Ethereum Classic" || holding.chainName == "Arbitrum" || holding.chainName == "Optimism" || holding.chainName == "BNB Chain" || holding.chainName == "Avalanche" || holding.chainName == "Hyperliquid" {
            let loweredInput = destinationInput.lowercased()
            if loweredInput.hasPrefix("bc1")
                || loweredInput.hasPrefix("tb1")
                || loweredInput.hasPrefix("ltc1")
                || loweredInput.hasPrefix("bnb1")
                || loweredInput.hasPrefix("t")
                || loweredInput.hasPrefix("d")
                || loweredInput.hasPrefix("a") {
                reasons.append(localizedStoreFormat("Destination appears to be a non-EVM address while sending on %@.", holding.chainName))
            }
            if (holding.chainName == "Arbitrum" || holding.chainName == "Optimism" || holding.chainName == "BNB Chain" || holding.chainName == "Avalanche" || holding.chainName == "Hyperliquid"), isENSNameCandidate(destinationInput) {
                reasons.append(localizedStoreFormat("ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", holding.chainName))
            }
        } else if holding.chainName == "Bitcoin" || holding.chainName == "Bitcoin Cash" || holding.chainName == "Litecoin" || holding.chainName == "Dogecoin" {
            if destinationInput.lowercased().hasPrefix("0x") || isENSNameCandidate(destinationInput) {
                reasons.append(localizedStoreFormat("Destination appears to be an Ethereum-style address while sending on %@.", holding.chainName))
            }
        } else if holding.chainName == "Tron" {
            if destinationInput.lowercased().hasPrefix("0x") || destinationInput.lowercased().hasPrefix("bc1") {
                reasons.append(localizedStoreString("Destination appears to be non-Tron format while sending on Tron."))
            }
        } else if holding.chainName == "Solana" {
            if destinationInput.lowercased().hasPrefix("0x")
                || destinationInput.lowercased().hasPrefix("bc1")
                || destinationInput.lowercased().hasPrefix("ltc1")
                || destinationInput.lowercased().hasPrefix("t") {
                reasons.append(localizedStoreString("Destination appears to be non-Solana format while sending on Solana."))
            }
        } else if holding.chainName == "XRP Ledger" {
            if destinationInput.lowercased().hasPrefix("0x")
                || destinationInput.lowercased().hasPrefix("bc1")
                || destinationInput.lowercased().hasPrefix("t") {
                reasons.append(localizedStoreString("Destination appears to be non-XRP format while sending on XRP Ledger."))
            }
        } else if holding.chainName == "Monero" {
            if destinationInput.lowercased().hasPrefix("0x")
                || destinationInput.lowercased().hasPrefix("bc1")
                || destinationInput.lowercased().hasPrefix("r") {
                reasons.append(localizedStoreString("Destination appears to be non-Monero format while sending on Monero."))
            }
        }

        if wallet.selectedChain != holding.chainName {
            reasons.append(localizedStoreString("Wallet-chain context mismatch detected for this send."))
        }

        return reasons
    }

    // Clears pending high-risk confirmation state after cancel/dismiss.
    func clearHighRiskSendConfirmation() {
        pendingHighRiskSendReasons = []
        isShowingHighRiskSendConfirmation = false
    }

    func confirmHighRiskSendAndSubmit() async {
        bypassHighRiskSendConfirmation = true
        isShowingHighRiskSendConfirmation = false
        await submitSend()
    }

    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAddress.isEmpty {
            switch chainName {
            case "Bitcoin":
                return localizedStoreString("Enter a Bitcoin address valid for the selected Bitcoin network mode.")
            case "Dogecoin":
                return localizedStoreString("Dogecoin addresses usually start with D, A, or 9.")
            case "Ethereum":
                return localizedStoreString("Ethereum addresses must start with 0x and include 40 hex characters.")
            case "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
                return localizedStoreFormat("%@ addresses use EVM format (0x + 40 hex characters).", chainName)
            case "Tron":
                return localizedStoreString("Tron addresses usually start with T and are Base58 encoded.")
            case "Solana":
                return localizedStoreString("Solana addresses are Base58 encoded and typically 32-44 characters.")
            case "Cardano":
                return localizedStoreString("Cardano addresses typically start with addr1 and use bech32 format.")
            case "XRP Ledger":
                return localizedStoreString("XRP Ledger addresses start with r and are Base58 encoded.")
            case "Stellar":
                return localizedStoreString("Stellar addresses start with G and are StrKey encoded.")
            case "Monero":
                return localizedStoreString("Monero addresses are Base58 encoded and usually start with 4 or 8.")
            case "Sui", "Aptos":
                return localizedStoreFormat("%@ addresses are hex and typically start with 0x.", chainName)
            case "TON":
                return localizedStoreString("TON addresses are usually user-friendly strings like UQ... or raw 0:<hex> addresses.")
            case "NEAR":
                return localizedStoreString("NEAR addresses can be named accounts or 64-character implicit account IDs.")
            case "Polkadot":
                return localizedStoreString("Polkadot addresses use SS58 encoding and usually start with 1.")
            default:
                return localizedStoreString("Enter an address for the selected chain.")
            }
        }

        return isValidAddress(trimmedAddress, for: chainName)
            ? localizedStoreFormat("Valid %@ address.", chainName)
            : {
                switch chainName {
                case "Bitcoin":
                    return localizedStoreString("Enter a valid Bitcoin address for the selected Bitcoin network mode.")
                case "Dogecoin":
                    return localizedStoreString("Enter a valid Dogecoin address beginning with D, A, or 9.")
                case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
                    return localizedStoreFormat("Enter a valid %@ address (0x + 40 hex characters).", chainName)
                case "Tron":
                    return localizedStoreString("Enter a valid Tron address (starts with T).")
                case "Solana":
                    return localizedStoreString("Enter a valid Solana address (Base58 format).")
                case "Cardano":
                    return localizedStoreString("Enter a valid Cardano address (starts with addr1).")
                case "XRP Ledger":
                    return localizedStoreString("Enter a valid XRP address (starts with r).")
                case "Stellar":
                    return localizedStoreString("Enter a valid Stellar address (starts with G).")
                case "Monero":
                    return localizedStoreString("Enter a valid Monero address (starts with 4 or 8).")
                case "Sui", "Aptos":
                    return localizedStoreFormat("Enter a valid %@ address (starts with 0x).", chainName)
                case "TON":
                    return localizedStoreString("Enter a valid TON address.")
                case "NEAR":
                    return localizedStoreString("Enter a valid NEAR account ID or implicit address.")
                case "Polkadot":
                    return localizedStoreString("Enter a valid Polkadot SS58 address.")
                default:
                    return localizedStoreFormat("Enter a valid %@ address.", chainName)
                }
            }()
    }

    func isDuplicateAddressBookAddress(_ address: String, chainName: String, excluding entryID: UUID? = nil) -> Bool {
        let normalizedAddress = normalizedAddress(address, for: chainName)
        guard !normalizedAddress.isEmpty else { return false }

        return addressBook.contains { entry in
            guard entry.id != entryID, entry.chainName == chainName else { return false }
            return entry.address.caseInsensitiveCompare(normalizedAddress) == .orderedSame
        }
    }

    // Validates whether an address-book entry is complete and non-duplicated.
    func canSaveAddressBookEntry(name: String, address: String, chainName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, isValidAddress(address, for: chainName) else {
            return false
        }

        return !isDuplicateAddressBookAddress(address, chainName: chainName)
    }

    // Persists a normalized address-book entry for quicker future send selection.
    func addAddressBookEntry(name: String, address: String, chainName: String, note: String = "") {
        guard canSaveAddressBookEntry(name: name, address: address, chainName: chainName) else {
            return
        }

        let entry = AddressBookEntry(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            chainName: chainName,
            address: normalizedAddress(address, for: chainName),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        addressBook.insert(entry, at: 0)
    }

    func canSaveLastSentRecipientToAddressBook() -> Bool {
        guard let lastSentTransaction,
              lastSentTransaction.kind == .send else {
            return false
        }

        return canSaveAddressBookEntry(
            name: "\(lastSentTransaction.symbol) Recipient",
            address: lastSentTransaction.address,
            chainName: lastSentTransaction.chainName
        )
    }

    func saveLastSentRecipientToAddressBook() {
        guard let lastSentTransaction,
              lastSentTransaction.kind == .send else {
            return
        }

        addAddressBookEntry(
            name: "\(lastSentTransaction.symbol) Recipient",
            address: lastSentTransaction.address,
            chainName: lastSentTransaction.chainName,
            note: "Saved from recent send"
        )
    }

    func renameAddressBookEntry(id: UUID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = addressBook.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = addressBook[index]
        addressBook[index] = AddressBookEntry(
            id: entry.id,
            name: trimmedName,
            chainName: entry.chainName,
            address: entry.address,
            note: entry.note
        )
    }

    func removeAddressBookEntry(id: UUID) {
        addressBook.removeAll { $0.id == id }
    }

    func runBitcoinSelfTests() {
        guard !isRunningBitcoinSelfTests else { return }
        isRunningBitcoinSelfTests = true
        bitcoinSelfTestResults = BitcoinSelfTestSuite.runAll()
        bitcoinSelfTestsLastRunAt = Date()
        isRunningBitcoinSelfTests = false
        let failedCount = bitcoinSelfTestResults.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Bitcoin", message: "BTC self-tests passed (\(bitcoinSelfTestResults.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Bitcoin", message: "BTC self-tests completed with \(failedCount) failure(s).")
        }
    }

    func runBitcoinCashSelfTests() {
        guard !isRunningBitcoinCashSelfTests else { return }
        isRunningBitcoinCashSelfTests = true
        bitcoinCashSelfTestResults = BitcoinCashSelfTestSuite.runAll()
        bitcoinCashSelfTestsLastRunAt = Date()
        isRunningBitcoinCashSelfTests = false
        let failedCount = bitcoinCashSelfTestResults.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Bitcoin Cash", message: "BCH self-tests passed (\(bitcoinCashSelfTestResults.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Bitcoin Cash", message: "BCH self-tests completed with \(failedCount) failure(s).")
        }
    }

    func runBitcoinSVSelfTests() {
        guard !isRunningBitcoinSVSelfTests else { return }
        isRunningBitcoinSVSelfTests = true
        bitcoinSVSelfTestResults = BitcoinSVSelfTestSuite.runAll()
        bitcoinSVSelfTestsLastRunAt = Date()
        isRunningBitcoinSVSelfTests = false
        let failedCount = bitcoinSVSelfTestResults.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Bitcoin SV", message: "BSV self-tests passed (\(bitcoinSVSelfTestResults.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Bitcoin SV", message: "BSV self-tests completed with \(failedCount) failure(s).")
        }
    }

    func runLitecoinSelfTests() {
        guard !isRunningLitecoinSelfTests else { return }
        isRunningLitecoinSelfTests = true
        litecoinSelfTestResults = LitecoinSelfTestSuite.runAll()
        litecoinSelfTestsLastRunAt = Date()
        isRunningLitecoinSelfTests = false
        let failedCount = litecoinSelfTestResults.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Litecoin", message: "LTC self-tests passed (\(litecoinSelfTestResults.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Litecoin", message: "LTC self-tests completed with \(failedCount) failure(s).")
        }
    }

    func runDogecoinSelfTests() {
        guard !isRunningDogecoinSelfTests else { return }
        isRunningDogecoinSelfTests = true
        dogecoinSelfTestResults = DogecoinChainSelfTestSuite.runAll()
        dogecoinSelfTestsLastRunAt = Date()
        isRunningDogecoinSelfTests = false
        let failedCount = dogecoinSelfTestResults.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE self-tests passed (\(dogecoinSelfTestResults.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE self-tests completed with \(failedCount) failure(s).")
        }
    }

    func runEthereumSelfTests() async {
        guard !isRunningEthereumSelfTests else { return }
        isRunningEthereumSelfTests = true
        defer { isRunningEthereumSelfTests = false }

        var results = EthereumChainSelfTestSuite.runAll()
        let rpcLabel = configuredEthereumRPCEndpointURL()?.absoluteString ?? "default RPC pool"

        do {
            let health = try await EthereumWalletEngine.fetchRPCHealth(
                rpcEndpoint: configuredEthereumRPCEndpointURL()
            )
            let chainPass = health.chainID == 1
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Chain ID",
                    passed: chainPass,
                    message: chainPass
                        ? "RPC reports Ethereum mainnet (chain id 1)."
                        : "RPC returned chain id \(health.chainID). Configure an Ethereum mainnet endpoint."
                )
            )
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Latest Block",
                    passed: health.latestBlockNumber > 0,
                    message: health.latestBlockNumber > 0
                        ? "RPC latest block height: \(health.latestBlockNumber) via \(rpcLabel)."
                        : "RPC returned an invalid latest block value."
                )
            )
        } catch {
            results.append(
                ChainSelfTestResult(
                    name: "ETH RPC Health",
                    passed: false,
                    message: "RPC health check failed for \(rpcLabel): \(error.localizedDescription)"
                )
            )
        }

        if let firstEthereumWallet = wallets.first(where: { $0.selectedChain == "Ethereum" }),
           let ethereumAddress = resolvedEthereumAddress(for: firstEthereumWallet) {
            do {
                _ = try await fetchEthereumPortfolio(for: ethereumAddress)
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe",
                        passed: true,
                        message: "Successfully fetched ETH/ERC-20 portfolio for \(firstEthereumWallet.name)."
                    )
                )
            } catch {
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe",
                        passed: false,
                        message: "Portfolio probe failed for \(firstEthereumWallet.name): \(error.localizedDescription)"
                    )
                )
            }
        } else {
            results.append(
                ChainSelfTestResult(
                    name: "ETH Portfolio Probe",
                    passed: true,
                    message: "Skipped: no imported wallet with Ethereum enabled."
                )
            )
        }

        let diagnosticsJSONResult: ChainSelfTestResult
        if let payload = ethereumDiagnosticsJSON(),
           let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["history"] != nil,
           object["endpoints"] != nil {
            diagnosticsJSONResult = ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape",
                passed: true,
                message: "Diagnostics JSON contains expected top-level keys."
            )
        } else {
            diagnosticsJSONResult = ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape",
                passed: false,
                message: "Diagnostics JSON missing expected keys (history/endpoints)."
            )
        }
        results.append(diagnosticsJSONResult)

        ethereumSelfTestResults = results
        ethereumSelfTestsLastRunAt = Date()

        let failedCount = results.filter { !$0.passed }.count
        if failedCount == 0 {
            appendChainOperationalEvent(.info, chainName: "Ethereum", message: "ETH diagnostics passed (\(results.count) checks).")
        } else {
            appendChainOperationalEvent(.warning, chainName: "Ethereum", message: "ETH diagnostics completed with \(failedCount) failure(s).")
        }
    }

    func operationalEvents(for chainName: String) -> [ChainOperationalEvent] {
        chainOperationalEventsByChain[chainName] ?? []
    }

    func feePriorityOption(for chainName: String) -> ChainFeePriorityOption {
        if chainName == "Bitcoin" {
            return mapBitcoinFeePriorityToChainOption(bitcoinFeePriority)
        }
        if chainName == "Dogecoin" {
            return mapDogecoinFeePriorityToChainOption(dogecoinFeePriority)
        }
        if let rawValue = selectedFeePriorityOptionRawByChain[chainName],
           let option = ChainFeePriorityOption(rawValue: rawValue) {
            return option
        }
        return .normal
    }

    func setFeePriorityOption(_ option: ChainFeePriorityOption, for chainName: String) {
        if chainName == "Bitcoin" {
            bitcoinFeePriority = mapChainOptionToBitcoinFeePriority(option)
            return
        }
        if chainName == "Dogecoin" {
            dogecoinFeePriority = mapChainOptionToDogecoinFeePriority(option)
            return
        }
        selectedFeePriorityOptionRawByChain[chainName] = option.rawValue
    }

    func bitcoinFeePriority(for chainName: String) -> BitcoinFeePriority {
        mapChainOptionToBitcoinFeePriority(feePriorityOption(for: chainName))
    }

    private func mapBitcoinFeePriorityToChainOption(_ priority: BitcoinFeePriority) -> ChainFeePriorityOption {
        switch priority {
        case .economy:
            return .economy
        case .normal:
            return .normal
        case .priority:
            return .priority
        }
    }

    private func mapChainOptionToBitcoinFeePriority(_ option: ChainFeePriorityOption) -> BitcoinFeePriority {
        switch option {
        case .economy:
            return .economy
        case .normal:
            return .normal
        case .priority:
            return .priority
        }
    }

    private func mapDogecoinFeePriorityToChainOption(_ priority: DogecoinWalletEngine.FeePriority) -> ChainFeePriorityOption {
        switch priority {
        case .economy:
            return .economy
        case .normal:
            return .normal
        case .priority:
            return .priority
        }
    }

    private func mapChainOptionToDogecoinFeePriority(_ option: ChainFeePriorityOption) -> DogecoinWalletEngine.FeePriority {
        switch option {
        case .economy:
            return .economy
        case .normal:
            return .normal
        case .priority:
            return .priority
        }
    }

    private func persistSelectedFeePriorityOptions() {
        UserDefaults.standard.set(selectedFeePriorityOptionRawByChain, forKey: Self.selectedFeePriorityOptionsByChainDefaultsKey)
    }

    func runDogecoinRescan() async {
        guard !isRunningDogecoinRescan else { return }
        isRunningDogecoinRescan = true
        defer { isRunningDogecoinRescan = false }
        logger.log("Starting Dogecoin rescan")
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rescan started.")

        await refreshDogecoinAddressDiscovery()
        await refreshDogecoinReceiveReservationState()
        await refreshDogecoinBalances()
        await refreshDogecoinTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingDogecoinTransactions()
        dogecoinRescanLastRunAt = Date()

        logger.log("Completed Dogecoin rescan")
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rescan completed.")
    }

    func runBitcoinRescan() async {
        guard !isRunningBitcoinRescan else { return }
        isRunningBitcoinRescan = true
        defer { isRunningBitcoinRescan = false }
        appendChainOperationalEvent(.info, chainName: "Bitcoin", message: "BTC rescan started.")
        await refreshBitcoinBalances()
        await refreshBitcoinTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingBitcoinTransactions()
        bitcoinRescanLastRunAt = Date()
        appendChainOperationalEvent(.info, chainName: "Bitcoin", message: "BTC rescan completed.")
    }

    func runBitcoinCashRescan() async {
        guard !isRunningBitcoinCashRescan else { return }
        isRunningBitcoinCashRescan = true
        defer { isRunningBitcoinCashRescan = false }
        appendChainOperationalEvent(.info, chainName: "Bitcoin Cash", message: "BCH rescan started.")
        await refreshBitcoinCashBalances()
        await refreshBitcoinCashTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingBitcoinCashTransactions()
        bitcoinCashRescanLastRunAt = Date()
        appendChainOperationalEvent(.info, chainName: "Bitcoin Cash", message: "BCH rescan completed.")
    }

    func runBitcoinSVRescan() async {
        guard !isRunningBitcoinSVRescan else { return }
        isRunningBitcoinSVRescan = true
        defer { isRunningBitcoinSVRescan = false }
        appendChainOperationalEvent(.info, chainName: "Bitcoin SV", message: "BSV rescan started.")
        await refreshBitcoinSVBalances()
        await refreshBitcoinSVTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingBitcoinSVTransactions()
        bitcoinSVRescanLastRunAt = Date()
        appendChainOperationalEvent(.info, chainName: "Bitcoin SV", message: "BSV rescan completed.")
    }

    func runLitecoinRescan() async {
        guard !isRunningLitecoinRescan else { return }
        isRunningLitecoinRescan = true
        defer { isRunningLitecoinRescan = false }
        appendChainOperationalEvent(.info, chainName: "Litecoin", message: "LTC rescan started.")
        await refreshLitecoinBalances()
        await refreshLitecoinTransactions(limit: HistoryPaging.endpointBatchSize)
        await refreshPendingLitecoinTransactions()
        litecoinRescanLastRunAt = Date()
        appendChainOperationalEvent(.info, chainName: "Litecoin", message: "LTC rescan completed.")
    }

    func runDogecoinHistoryDiagnostics() async {
        guard !isRunningDogecoinHistoryDiagnostics else { return }
        isRunningDogecoinHistoryDiagnostics = true
        defer { isRunningDogecoinHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Dogecoin",
                  let address = resolvedDogecoinAddress(for: wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            dogecoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            do {
                let page = try await withTimeout(seconds: 20) {
                    try await DogecoinBalanceService.fetchTransactionPage(
                        for: address,
                        limit: HistoryPaging.endpointBatchSize,
                        cursor: nil,
                        networkMode: self.dogecoinNetworkMode(for: wallet)
                    )
                }
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor,
                    error: nil
                )
            } catch {
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
            dogecoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    func runDogecoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingDogecoinEndpointHealth else { return }
        isCheckingDogecoinEndpointHealth = true
        defer { isCheckingDogecoinEndpointHealth = false }
        await runSimpleEndpointReachabilityDiagnostics(
            checks: DogecoinBalanceService.diagnosticsChecks(),
            profile: .diagnostics,
            setResults: { [weak self] in self?.dogecoinEndpointHealthResults = $0 },
            markUpdated: { [weak self] in self?.dogecoinEndpointHealthLastUpdatedAt = Date() }
        )
    }

    // Starts one network monitor used to gate maintenance tasks and degraded-mode messaging.
    func startNetworkPathMonitorIfNeeded() {
#if canImport(Network)
        networkPathMonitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            let constrained = path.isConstrained
            let expensive = path.isExpensive
            DispatchQueue.main.async {
                guard let self else { return }
                self.isNetworkReachable = reachable
                self.isConstrainedNetwork = constrained
                self.isExpensiveNetwork = expensive
            }
        }
        networkPathMonitor.start(queue: networkPathMonitorQueue)
#endif
    }

    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, useFaceID, useAutoLock {
            isAppLocked = true
            appLockError = nil
        }
        if !isActive {
            maintenanceTask?.cancel()
            maintenanceTask = nil
            return
        }
        startMaintenanceLoopIfNeeded()
    }

    func unlockApp() async {
        guard useFaceID else {
            isAppLocked = false
            appLockError = nil
            return
        }
        let authenticated = await authenticateForSensitiveAction(reason: "Authenticate to unlock Spectra")
        if authenticated {
            isAppLocked = false
            appLockError = nil
        }
    }

    private func startMaintenanceLoopIfNeeded() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runScheduledMaintenanceOnce()
                let pollSeconds = self.appIsActive
                    ? Self.activeMaintenancePollSeconds
                    : Self.inactiveMaintenancePollSeconds
                try? await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
            }
        }
    }

    // Periodic scheduler tick:
    // active mode focuses on freshness, inactive mode enforces conservative background cadence.
    private func runScheduledMaintenanceOnce(now: Date = Date()) async {
        if appIsActive {
            await runActiveScheduledMaintenance(now: now)
            return
        }

        let interval = backgroundMaintenanceInterval(now: now)
        guard WalletRefreshPlanner.shouldRunBackgroundMaintenance(
            now: now,
            isNetworkReachable: isNetworkReachable,
            lastBackgroundMaintenanceAt: lastBackgroundMaintenanceAt,
            interval: interval
        ) else {
            return
        }
        lastBackgroundMaintenanceAt = now
        await performBackgroundMaintenanceTick()
    }

    func authenticateForSensitiveAction(
        reason: String,
        allowWhenAuthenticationUnavailable: Bool = false
    ) async -> Bool {
        guard useFaceID, requireBiometricForSendActions else { return true }
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            if allowWhenAuthenticationUnavailable {
                return true
            }
            let message = "Device authentication unavailable: \(authError?.localizedDescription ?? "unknown error")"
            sendError = message
            appLockError = message
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                Task { @MainActor in
                    if success {
                        self.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? "Authentication cancelled."
                        self.sendError = message
                        self.appLockError = message
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func authenticateForSeedPhraseReveal(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func retryUTXOTransactionStatus(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else {
            return "Transaction not found."
        }
        let supportedChains = Set(["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"])
        guard supportedChains.contains(transaction.chainName), transaction.kind == .send else {
            return "Status recheck is only supported for UTXO send transactions."
        }
        guard transaction.transactionHash != nil else {
            return "This transaction has no hash to recheck."
        }

        if transaction.chainName == "Dogecoin" {
            var tracker = dogecoinStatusTrackingByTransactionID[transactionID] ?? DogecoinStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast
            tracker.reachedFinality = false
            dogecoinStatusTrackingByTransactionID[transactionID] = tracker
        } else {
            var tracker = statusTrackingByTransactionID[transactionID] ?? TransactionStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast
            statusTrackingByTransactionID[transactionID] = tracker
        }

        switch transaction.chainName {
        case "Bitcoin":
            await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash":
            await refreshPendingBitcoinCashTransactions()
        case "Bitcoin SV":
            await refreshPendingBitcoinSVTransactions()
        case "Litecoin":
            await refreshPendingLitecoinTransactions()
        case "Dogecoin":
            await refreshPendingDogecoinTransactions()
        default:
            break
        }

        guard let updated = transactions.first(where: { $0.id == transactionID }) else {
            return "Transaction status refresh completed."
        }

        if updated.status != transaction.status {
            return "Status updated: \(updated.statusText)."
        }
        if updated.status == .pending {
            return "No confirmation yet. Spectra will keep retrying automatically."
        }
        if updated.status == .failed {
            return updated.failureReason ?? "Transaction remains failed."
        }
        return "Transaction is confirmed."
    }

    func rebroadcastDogecoinTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else {
            return "Transaction not found."
        }
        guard transaction.chainName == "Dogecoin", transaction.kind == .send else {
            return "Rebroadcast is only supported for Dogecoin send transactions."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize Dogecoin rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        guard let rawTransactionHex = transaction.dogecoinRawTransactionHex,
              !rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "This transaction cannot be rebroadcast because raw signed data was not saved."
        }
        appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rebroadcast requested.", transactionHash: transaction.transactionHash)

        do {
            let walletNetworkMode = transaction.walletID
                .flatMap { walletID in wallets.first(where: { $0.id == walletID })?.dogecoinNetworkMode }
                ?? dogecoinNetworkMode
            let result = try await DogecoinWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: rawTransactionHex,
                expectedTransactionHash: transaction.transactionHash,
                networkMode: walletNetworkMode
            )

            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                let existing = transactions[index]
                transactions[index] = TransactionRecord(
                    id: existing.id,
                    walletID: existing.walletID,
                    kind: existing.kind,
                    status: .pending,
                    walletName: existing.walletName,
                    assetName: existing.assetName,
                    symbol: existing.symbol,
                    chainName: existing.chainName,
                    amount: existing.amount,
                    address: existing.address,
                    transactionHash: result.transactionHash,
                    receiptBlockNumber: existing.receiptBlockNumber,
                    receiptGasUsed: existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: existing.receiptNetworkFeeETH,
                    feePriorityRaw: existing.feePriorityRaw,
                    feeRateDescription: existing.feeRateDescription,
                    confirmationCount: existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: existing.sourceDerivationPath,
                    changeDerivationPath: existing.changeDerivationPath,
                    sourceAddress: existing.sourceAddress,
                    changeAddress: existing.changeAddress,
                    dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex,
                    failureReason: nil,
                    transactionHistorySource: existing.transactionHistorySource,
                    createdAt: existing.createdAt
                )
            }

            await refreshPendingDogecoinTransactions()
            switch result.verificationStatus {
            case .verified:
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: "DOGE rebroadcast verified by provider.", transactionHash: result.transactionHash)
                return "Transaction rebroadcasted and observed on network providers."
            case .deferred:
                appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE rebroadcast accepted; verification deferred.", transactionHash: result.transactionHash)
                return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message):
                appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE rebroadcast verification warning: \(message)", transactionHash: result.transactionHash)
                return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            appendChainOperationalEvent(.error, chainName: "Dogecoin", message: "DOGE rebroadcast failed: \(error.localizedDescription)", transactionHash: transaction.transactionHash)
            return error.localizedDescription
        }
    }

    func rebroadcastSignedTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else {
            return "Transaction not found."
        }
        guard transaction.kind == .send else {
            return "Rebroadcast is only supported for send transactions."
        }
        guard let payload = transaction.rebroadcastPayload,
              let format = transaction.rebroadcastPayloadFormat else {
            return "This transaction cannot be rebroadcast because signed payload data was not saved."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction rebroadcast") else {
            return sendError ?? "Authentication failed."
        }

        do {
            let (transactionHash, verificationStatus) = try await rebroadcastSignedTransaction(
                transaction: transaction,
                payload: payload,
                format: format
            )

            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                let existing = transactions[index]
                transactions[index] = TransactionRecord(
                    id: existing.id,
                    walletID: existing.walletID,
                    kind: existing.kind,
                    status: .pending,
                    walletName: existing.walletName,
                    assetName: existing.assetName,
                    symbol: existing.symbol,
                    chainName: existing.chainName,
                    amount: existing.amount,
                    address: existing.address,
                    transactionHash: transactionHash,
                    ethereumNonce: existing.ethereumNonce,
                    receiptBlockNumber: existing.receiptBlockNumber,
                    receiptGasUsed: existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: existing.receiptNetworkFeeETH,
                    feePriorityRaw: existing.feePriorityRaw,
                    feeRateDescription: existing.feeRateDescription,
                    confirmationCount: existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: existing.sourceDerivationPath,
                    changeDerivationPath: existing.changeDerivationPath,
                    sourceAddress: existing.sourceAddress,
                    changeAddress: existing.changeAddress,
                    dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex,
                    signedTransactionPayload: existing.signedTransactionPayload,
                    signedTransactionPayloadFormat: existing.signedTransactionPayloadFormat,
                    failureReason: nil,
                    transactionHistorySource: existing.transactionHistorySource,
                    createdAt: existing.createdAt
                )
            }

            if transaction.chainName == "Dogecoin" {
                await refreshPendingDogecoinTransactions()
            }

            switch verificationStatus {
            case .verified:
                return "Transaction rebroadcasted and observed on the network."
            case .deferred:
                return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message):
                return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            return error.localizedDescription
        }
    }

    private func rebroadcastSignedTransaction(
        transaction: TransactionRecord,
        payload: String,
        format: String
    ) async throws -> (transactionHash: String, verificationStatus: SendBroadcastVerificationStatus) {
        switch format {
        case "bitcoin.raw_hex":
            let result = try await BitcoinWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "bitcoin_cash.raw_hex":
            let result = try await BitcoinCashWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "bitcoin_sv.raw_hex":
            let result = try await BitcoinSVWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "litecoin.raw_hex":
            let result = try await LitecoinWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "dogecoin.raw_hex":
            let walletNetworkMode = transaction.walletID
                .flatMap { walletID in wallets.first(where: { $0.id == walletID })?.dogecoinNetworkMode }
                ?? dogecoinNetworkMode
            let result = try await DogecoinWalletEngine.rebroadcastSignedTransactionInBackground(
                rawTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash,
                networkMode: walletNetworkMode
            )
            let status: SendBroadcastVerificationStatus
            switch result.verificationStatus {
            case .verified:
                status = .verified
            case .deferred:
                status = .deferred
            case .failed(let message):
                status = .failed(message)
            }
            return (result.transactionHash, status)
        case "tron.signed_json":
            let result = try await TronWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionJSON: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "solana.base64":
            let result = try await SolanaWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionBase64: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "xrp.blob_hex":
            let result = try await XRPWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionBlobHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "stellar.xdr":
            let result = try await StellarWalletEngine.rebroadcastSignedTransactionInBackground(
                signedEnvelopeXDR: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "cardano.cbor_hex":
            let result = try await CardanoWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionCBORHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "near.base64":
            let result = try await NearWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionBase64: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "polkadot.extrinsic_hex":
            let result = try await PolkadotWalletEngine.rebroadcastSignedTransactionInBackground(
                signedExtrinsicHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "aptos.signed_json":
            let result = try await AptosWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionJSON: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "sui.signed_json":
            let result = try await SuiWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionPayloadJSON: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "ton.boc":
            let result = try await TONWalletEngine.rebroadcastSignedTransactionInBackground(
                signedBOC: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "icp.signed_hex":
            let result = try await ICPWalletEngine.rebroadcastSignedTransactionInBackground(
                signedTransactionHex: payload,
                expectedTransactionHash: transaction.transactionHash
            )
            return (result.transactionHash, result.verificationStatus)
        case "evm.raw_hex":
            guard let chain = evmChainContext(for: transaction.chainName) else {
                throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported EVM chain for rebroadcast."])
            }
            let transactionHash = try await EthereumWalletEngine.rebroadcastSignedTransaction(
                rawTransactionHex: payload,
                preferredRPCEndpoint: configuredEVMRPCEndpointURL(for: transaction.chainName),
                chain: chain
            )
            guard let verificationEndpoint = configuredEVMRPCEndpointURL(for: transaction.chainName)
                ?? URL(string: chain.defaultRPCEndpoints.first ?? "") else {
                return (transactionHash, .deferred)
            }
            let verificationStatus = await EthereumWalletEngine.verifyBroadcastedTransactionIfAvailable(
                transactionHash: transactionHash,
                rpcEndpoint: verificationEndpoint,
                chain: chain
            )
            return (transactionHash, verificationStatus)
        default:
            throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rebroadcast is not supported for this transaction format yet."])
        }
    }

    func walletDerivationPath(for wallet: ImportedWallet, chain: SeedDerivationChain) -> String {
        derivationResolution(for: wallet, chain: chain).normalizedPath
    }

    func derivationAccount(for wallet: ImportedWallet, chain: SeedDerivationChain) -> UInt32 {
        derivationResolution(for: wallet, chain: chain).accountIndex
    }

    private func derivationResolution(for wallet: ImportedWallet, chain: SeedDerivationChain) -> SeedDerivationResolution {
        chain.resolve(path: wallet.seedDerivationPaths.path(for: chain))
    }

    func bitcoinNetworkMode(for wallet: ImportedWallet) -> BitcoinNetworkMode {
        wallet.bitcoinNetworkMode
    }

    func dogecoinNetworkMode(for wallet: ImportedWallet) -> DogecoinNetworkMode {
        wallet.dogecoinNetworkMode
    }

    func displayNetworkName(for chainName: String) -> String {
        if chainName == "Bitcoin" {
            return bitcoinNetworkMode.displayName
        }
        if chainName == "Ethereum" {
            return ethereumNetworkMode.displayName
        }
        if chainName == "Dogecoin" {
            return dogecoinNetworkMode.displayName
        }
        return chainName
    }

    func displayChainTitle(for chainName: String) -> String {
        let networkName = displayNetworkName(for: chainName)
        if networkName == chainName || networkName == "Mainnet" {
            return chainName
        }
        return "\(chainName) \(networkName)"
    }

    func displayNetworkName(for wallet: ImportedWallet) -> String {
        if wallet.selectedChain == "Bitcoin" {
            return bitcoinNetworkMode(for: wallet).displayName
        }
        if wallet.selectedChain == "Dogecoin" {
            return dogecoinNetworkMode(for: wallet).displayName
        }
        return displayNetworkName(for: wallet.selectedChain)
    }

    func displayChainTitle(for wallet: ImportedWallet) -> String {
        let networkName = displayNetworkName(for: wallet)
        if networkName == wallet.selectedChain || networkName == "Mainnet" {
            return wallet.selectedChain
        }
        return "\(wallet.selectedChain) \(networkName)"
    }

    func displayNetworkName(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"),
           let walletID = transaction.walletID,
           let wallet = cachedWalletByID[walletID] {
            return displayNetworkName(for: wallet)
        }
        return displayNetworkName(for: transaction.chainName)
    }

    func displayChainTitle(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"),
           let walletID = transaction.walletID,
           let wallet = cachedWalletByID[walletID] {
            return displayChainTitle(for: wallet)
        }
        return displayChainTitle(for: transaction.chainName)
    }

    func solanaDerivationPreference(for wallet: ImportedWallet) -> SolanaWalletEngine.DerivationPreference {
        derivationResolution(for: wallet, chain: .solana).flavor == .legacy ? .legacy : .standard
    }

    private func resolvedEthereumAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedEthereumAddress(for: wallet, using: self)
    }

    private func resolvedBitcoinAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedBitcoinAddress(for: wallet, using: self)
    }

    func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        WalletDerivationLayer.resolvedEVMAddress(for: wallet, chainName: chainName, using: self)
    }

    func resolvedTronAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedTronAddress(for: wallet, using: self)
    }

    func resolvedSolanaAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedSolanaAddress(for: wallet, using: self)
    }

    func resolvedSuiAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedSuiAddress(for: wallet, using: self)
    }

    func resolvedAptosAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedAptosAddress(for: wallet, using: self)
    }

    func resolvedTONAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedTONAddress(for: wallet, using: self)
    }

    func resolvedICPAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedICPAddress(for: wallet, using: self)
    }

    func resolvedNearAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedNearAddress(for: wallet, using: self)
    }

    func resolvedPolkadotAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedPolkadotAddress(for: wallet, using: self)
    }

    func resolvedStellarAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedStellarAddress(for: wallet, using: self)
    }

    func resolvedCardanoAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedCardanoAddress(for: wallet, using: self)
    }

    func resolvedXRPAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedXRPAddress(for: wallet, using: self)
    }

    func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedMoneroAddress(for: wallet)
    }

    func resolvedDogecoinAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedDogecoinAddress(for: wallet, using: self)
    }

    func resolvedLitecoinAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedLitecoinAddress(for: wallet, using: self)
    }

    func resolvedBitcoinCashAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedBitcoinCashAddress(for: wallet, using: self)
    }

    func resolvedBitcoinSVAddress(for wallet: ImportedWallet) -> String? {
        WalletDerivationLayer.resolvedBitcoinSVAddress(for: wallet, using: self)
    }

    func walletWithResolvedDogecoinAddress(_ wallet: ImportedWallet) -> ImportedWallet {
        let resolvedAddress = resolvedDogecoinAddress(for: wallet) ?? wallet.dogecoinAddress
        return ImportedWallet(
            id: wallet.id,
            name: wallet.name,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSVAddress: wallet.bitcoinSVAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: resolvedAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            aptosAddress: wallet.aptosAddress,
            tonAddress: wallet.tonAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: wallet.holdings
        )
    }

    func knownDogecoinAddresses(for wallet: ImportedWallet) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        let networkMode = wallet.dogecoinNetworkMode

        func addIfValid(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidDogecoinAddressForPolicy(trimmed, networkMode: networkMode) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }

        addIfValid(resolvedDogecoinAddress(for: wallet))
        addIfValid(wallet.dogecoinAddress)

        for transaction in transactions where
            transaction.chainName == "Dogecoin"
            && transaction.walletID == wallet.id
        {
            addIfValid(transaction.sourceAddress)
            addIfValid(transaction.changeAddress)
        }

        for discoveredAddress in discoveredDogecoinAddressesByWallet[wallet.id] ?? [] {
            addIfValid(discoveredAddress)
        }

        for ownedAddress in ownedDogecoinAddresses(for: wallet.id) {
            addIfValid(ownedAddress)
        }

        addIfValid(dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: false))

        return ordered
    }

    func parseDogecoinDerivationIndex(path: String?, expectedPrefix: String) -> Int? {
        guard let path, path.hasPrefix(expectedPrefix) else { return nil }
        let suffix = String(path.dropFirst(expectedPrefix.count))
        return Int(suffix)
    }

    private func supportsDeepUTXODiscovery(chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin Cash", "Bitcoin SV", "Litecoin":
            return true
        default:
            return false
        }
    }

    private func utxoDiscoveryCoin(for chainName: String) -> WalletCoreSupportedCoin? {
        switch chainName {
        case "Bitcoin":
            return .bitcoin
        case "Bitcoin Cash":
            return .bitcoinCash
        case "Bitcoin SV":
            return .bitcoinSV
        case "Litecoin":
            return .litecoin
        default:
            return nil
        }
    }

    private func isValidUTXOAddressForPolicy(_ address: String, chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin":
            return AddressValidation.isValidBitcoinAddress(address, networkMode: bitcoinNetworkMode)
        case "Bitcoin Cash":
            return AddressValidation.isValidBitcoinCashAddress(address)
        case "Bitcoin SV":
            return AddressValidation.isValidBitcoinSVAddress(address)
        case "Litecoin":
            return AddressValidation.isValidLitecoinAddress(address)
        default:
            return false
        }
    }

    private func utxoDiscoveryDerivationPath(
        for wallet: ImportedWallet,
        chainName: String,
        branch: WalletDerivationBranch,
        index: Int
    ) -> String? {
        guard let derivationChain = seedDerivationChain(for: chainName),
              var segments = DerivationPathParser.parse(walletDerivationPath(for: wallet, chain: derivationChain)),
              segments.count >= 5 else {
            return nil
        }
        segments[segments.count - 2] = DerivationPathSegment(value: UInt32(branch.rawValue), isHardened: false)
        segments[segments.count - 1] = DerivationPathSegment(value: UInt32(max(0, index)), isHardened: false)
        return DerivationPathParser.string(from: segments)
    }

    private func parseUTXODiscoveryIndex(path: String?, chainName: String, branch: WalletDerivationBranch) -> Int? {
        guard let path,
              let derivationChain = seedDerivationChain(for: chainName),
              let pathSegments = DerivationPathParser.parse(path),
              var walletSegments = DerivationPathParser.parse(derivationChain.defaultPath),
              pathSegments.count == walletSegments.count,
              pathSegments.count >= 5 else {
            return nil
        }
        walletSegments[walletSegments.count - 2] = DerivationPathSegment(value: UInt32(branch.rawValue), isHardened: false)
        walletSegments[walletSegments.count - 1] = DerivationPathSegment(value: pathSegments.last?.value ?? 0, isHardened: false)
        let candidatePrefix = DerivationPathParser.string(from: Array(walletSegments.dropLast()))
        let pathPrefix = DerivationPathParser.string(from: Array(pathSegments.dropLast()))
        guard candidatePrefix == pathPrefix,
              pathSegments[pathSegments.count - 2].value == UInt32(branch.rawValue) else {
            return nil
        }
        return Int(pathSegments.last?.value ?? 0)
    }

    private func deriveUTXOAddress(
        for wallet: ImportedWallet,
        chainName: String,
        branch: WalletDerivationBranch,
        index: Int
    ) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id),
              let coin = utxoDiscoveryCoin(for: chainName),
              let derivationPath = utxoDiscoveryDerivationPath(
                for: wallet,
                chainName: chainName,
                branch: branch,
                index: index
              ),
              let address = try? WalletCoreDerivation.deriveMaterial(
                seedPhrase: seedPhrase,
                coin: coin,
                derivationPath: derivationPath
              ).address,
              isValidUTXOAddressForPolicy(address, chainName: chainName) else {
            return nil
        }
        return address
    }

    private func hasUTXOOnChainActivity(address: String, chainName: String) async -> Bool {
        switch chainName {
        case "Bitcoin":
            if let hasHistory = try? await BitcoinBalanceService.hasTransactionHistory(for: address, networkMode: bitcoinNetworkMode),
               hasHistory {
                return true
            }
            if let balance = try? await BitcoinBalanceService.fetchBalance(for: address, networkMode: bitcoinNetworkMode),
               balance > 0 {
                return true
            }
        case "Bitcoin Cash":
            if let hasHistory = try? await BitcoinCashBalanceService.hasTransactionHistory(for: address),
               hasHistory {
                return true
            }
            if let balance = try? await BitcoinCashBalanceService.fetchBalance(for: address),
               balance > 0 {
                return true
            }
        case "Bitcoin SV":
            if let hasHistory = try? await BitcoinSVBalanceService.hasTransactionHistory(for: address),
               hasHistory {
                return true
            }
            if let balance = try? await BitcoinSVBalanceService.fetchBalance(for: address),
               balance > 0 {
                return true
            }
        case "Litecoin":
            if let hasHistory = try? await LitecoinBalanceService.hasTransactionHistory(for: address),
               hasHistory {
                return true
            }
            if let balance = try? await LitecoinBalanceService.fetchBalance(for: address),
               balance > 0 {
                return true
            }
        default:
            return false
        }
        return false
    }

    private func knownUTXOAddresses(for wallet: ImportedWallet, chainName: String) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidUTXOAddressForPolicy(trimmed, chainName: chainName) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }

        switch chainName {
        case "Bitcoin":
            appendAddress(wallet.bitcoinAddress)
        case "Bitcoin Cash":
            appendAddress(wallet.bitcoinCashAddress)
        case "Bitcoin SV":
            appendAddress(wallet.bitcoinSVAddress)
        case "Litecoin":
            appendAddress(wallet.litecoinAddress)
        default:
            break
        }

        appendAddress(resolvedAddress(for: wallet, chainName: chainName))
        appendAddress(reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false))

        for transaction in transactions where transaction.chainName == chainName && transaction.walletID == wallet.id {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }

        for discoveredAddress in discoveredUTXOAddressesByChain[chainName]?[wallet.id] ?? [] {
            appendAddress(discoveredAddress)
        }

        for ownedAddress in ownedAddresses(for: wallet.id, chainName: chainName) {
            appendAddress(ownedAddress)
        }

        return ordered
    }

    private func discoverUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        var ordered = knownUTXOAddresses(for: wallet, chainName: chainName)
        var seen = Set(ordered.map { $0.lowercased() })

        guard supportsDeepUTXODiscovery(chainName: chainName),
              storedSeedPhrase(for: wallet.id) != nil else {
            return ordered
        }

        let state = keypoolState(for: wallet, chainName: chainName)
        let highestOwnedExternal = (chainOwnedAddressMapByChain[chainName] ?? [:]).values
            .filter { $0.walletID == wallet.id && $0.branch == "external" }
            .map(\.index)
            .compactMap { $0 }
            .max() ?? 0
        let reserved = state.reservedReceiveIndex ?? 0
        let scanUpperBound = min(
            Self.utxoDiscoveryMaxIndex,
            max(state.nextExternalIndex, max(highestOwnedExternal + 1, reserved + 1)) + Self.utxoDiscoveryGapLimit
        )

        guard scanUpperBound >= 0 else { return ordered }

        for index in 0 ... scanUpperBound {
            guard let derivedAddress = deriveUTXOAddress(
                for: wallet,
                chainName: chainName,
                branch: .external,
                index: index
            ) else {
                continue
            }
            let normalized = derivedAddress.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                ordered.append(derivedAddress)
            }
            if await hasUTXOOnChainActivity(address: derivedAddress, chainName: chainName) {
                registerOwnedAddress(
                    chainName: chainName,
                    address: derivedAddress,
                    walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet,
                        chainName: chainName,
                        branch: .external,
                        index: index
                    ),
                    index: index,
                    branch: "external"
                )
            }
        }

        return ordered
    }

    func refreshUTXOAddressDiscovery(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }

        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }

        let discovered = await withTaskGroup(of: (UUID, [String]).self, returning: [UUID: [String]].self) { group in
            for wallet in utxoWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverUTXOAddresses(for: wallet, chainName: chainName)
                    return (wallet.id, addresses)
                }
            }

            var mapping: [UUID: [String]] = [:]
            for await (walletID, addresses) in group {
                mapping[walletID] = addresses
            }
            return mapping
        }

        discoveredUTXOAddressesByChain[chainName] = discovered
    }

    func refreshUTXOReceiveReservationState(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else { return }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else { return }

        for wallet in utxoWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = reserveReceiveIndex(for: wallet, chainName: chainName)
            var state = keypoolState(for: wallet, chainName: chainName)
            guard let reservedIndex = state.reservedReceiveIndex,
                  let reservedAddress = deriveUTXOAddress(
                    for: wallet,
                    chainName: chainName,
                    branch: .external,
                    index: reservedIndex
                  ) else {
                continue
            }

            registerOwnedAddress(
                chainName: chainName,
                address: reservedAddress,
                walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet,
                    chainName: chainName,
                    branch: .external,
                    index: reservedIndex
                ),
                index: reservedIndex,
                branch: "external"
            )

            guard await hasUTXOOnChainActivity(address: reservedAddress, chainName: chainName) else {
                continue
            }

            let nextReserved = max(state.nextExternalIndex, reservedIndex + 1)
            state.reservedReceiveIndex = nextReserved
            state.nextExternalIndex = max(state.nextExternalIndex, nextReserved + 1)
            var perWallet = chainKeypoolByChain[chainName] ?? [:]
            perWallet[wallet.id] = state
            chainKeypoolByChain[chainName] = perWallet

            if let nextAddress = deriveUTXOAddress(
                for: wallet,
                chainName: chainName,
                branch: .external,
                index: nextReserved
            ) {
                registerOwnedAddress(
                    chainName: chainName,
                    address: nextAddress,
                    walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet,
                        chainName: chainName,
                        branch: .external,
                        index: nextReserved
                    ),
                    index: nextReserved,
                    branch: "external"
                )
            }
        }
    }

    private func seedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        switch chainName {
        case "Bitcoin":
            return .bitcoin
        case "Bitcoin Cash":
            return .bitcoinCash
        case "Bitcoin SV":
            return .bitcoinSV
        case "Litecoin":
            return .litecoin
        case "Dogecoin":
            return .dogecoin
        case "Ethereum":
            return .ethereum
        case "Ethereum Classic":
            return .ethereumClassic
        case "Arbitrum":
            return .arbitrum
        case "Optimism":
            return .optimism
        case "BNB Chain":
            return .ethereum
        case "Avalanche":
            return .avalanche
        case "Hyperliquid":
            return .hyperliquid
        case "Tron":
            return .tron
        case "Solana":
            return .solana
        case "Stellar":
            return .stellar
        case "XRP Ledger":
            return .xrp
        case "Cardano":
            return .cardano
        case "Sui":
            return .sui
        case "Aptos":
            return .aptos
        case "TON":
            return .ton
        case "Internet Computer":
            return .internetComputer
        case "NEAR":
            return .near
        case "Polkadot":
            return .polkadot
        default:
            return nil
        }
    }

    private func walletHasAddress(for wallet: ImportedWallet, chainName: String) -> Bool {
        resolvedAddress(for: wallet, chainName: chainName) != nil
    }

    private func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        switch chainName {
        case "Bitcoin":
            return resolvedBitcoinAddress(for: wallet)
        case "Bitcoin Cash":
            return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV":
            return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin":
            return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin":
            return resolvedDogecoinAddress(for: wallet)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return resolvedEVMAddress(for: wallet, chainName: chainName)
        case "Tron":
            return resolvedTronAddress(for: wallet)
        case "Solana":
            return resolvedSolanaAddress(for: wallet)
        case "Stellar":
            return resolvedStellarAddress(for: wallet)
        case "XRP Ledger":
            return resolvedXRPAddress(for: wallet)
        case "Monero":
            return resolvedMoneroAddress(for: wallet)
        case "Cardano":
            return resolvedCardanoAddress(for: wallet)
        case "Sui":
            return resolvedSuiAddress(for: wallet)
        case "Aptos":
            return resolvedAptosAddress(for: wallet)
        case "TON":
            return resolvedTONAddress(for: wallet)
        case "Internet Computer":
            return resolvedICPAddress(for: wallet)
        case "NEAR":
            return resolvedNearAddress(for: wallet)
        case "Polkadot":
            return resolvedPolkadotAddress(for: wallet)
        default:
            return nil
        }
    }

    private func normalizedOwnedAddressKey(chainName: String, address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chainName {
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return trimmed.lowercased()
        default:
            return trimmed.lowercased()
        }
    }

    private func registerOwnedAddress(
        chainName: String,
        address: String?,
        walletID: UUID?,
        derivationPath: String?,
        index: Int?,
        branch: String?
    ) {
        guard let address, let walletID else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = normalizedOwnedAddressKey(chainName: chainName, address: trimmed)
        var addresses = chainOwnedAddressMapByChain[chainName] ?? [:]
        addresses[key] = ChainOwnedAddressRecord(
            chainName: chainName,
            address: trimmed,
            walletID: walletID,
            derivationPath: derivationPath,
            index: index,
            branch: branch
        )
        chainOwnedAddressMapByChain[chainName] = addresses
    }

    private func ownedAddresses(for walletID: UUID, chainName: String) -> [String] {
        (chainOwnedAddressMapByChain[chainName] ?? [:]).compactMap { key, value in
            guard value.walletID == walletID else { return nil }
            return value.address ?? key
        }
    }

    private func normalizedDogecoinAddressKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func registerDogecoinOwnedAddress(
        address: String?,
        walletID: UUID?,
        derivationPath: String?,
        index: Int?,
        branch: String?,
        networkMode: DogecoinNetworkMode = .mainnet
    ) {
        guard let address,
              let walletID,
              let derivationPath,
              let index,
              let branch else {
            return
        }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddressForPolicy(trimmed, networkMode: networkMode) else { return }
        let key = normalizedDogecoinAddressKey(trimmed)
        dogecoinOwnedAddressMap[key] = DogecoinOwnedAddressRecord(
            address: trimmed,
            walletID: walletID,
            derivationPath: derivationPath,
            index: index,
            branch: branch
        )
        registerOwnedAddress(
            chainName: "Dogecoin",
            address: trimmed,
            walletID: walletID,
            derivationPath: derivationPath,
            index: index,
            branch: branch
        )
    }

    private func ownedDogecoinAddresses(for walletID: UUID) -> [String] {
        dogecoinOwnedAddressMap.compactMap { key, value in
            guard value.walletID == walletID else { return nil }
            return value.address ?? key
        }
    }

    private func baselineChainKeypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        if chainName == "Dogecoin" {
            let dogecoinState = baselineDogecoinKeypoolState(for: wallet)
            return ChainKeypoolState(
                nextExternalIndex: dogecoinState.nextExternalIndex,
                nextChangeIndex: dogecoinState.nextChangeIndex,
                reservedReceiveIndex: dogecoinState.reservedReceiveIndex
            )
        }

        if supportsDeepUTXODiscovery(chainName: chainName) {
            let chainTransactions = transactions.filter { $0.walletID == wallet.id && $0.chainName == chainName }
            let maxExternalIndex = chainTransactions
                .compactMap {
                    parseUTXODiscoveryIndex(
                        path: $0.sourceDerivationPath,
                        chainName: chainName,
                        branch: .external
                    )
                }
                .max() ?? -1
            let maxChangeIndex = chainTransactions
                .compactMap {
                    parseUTXODiscoveryIndex(
                        path: $0.changeDerivationPath,
                        chainName: chainName,
                        branch: .change
                    )
                }
                .max() ?? -1
            let maxOwnedExternalIndex = (chainOwnedAddressMapByChain[chainName] ?? [:]).values
                .filter { $0.walletID == wallet.id && $0.branch == "external" }
                .compactMap(\.index)
                .max() ?? 0
            let maxOwnedChangeIndex = (chainOwnedAddressMapByChain[chainName] ?? [:]).values
                .filter { $0.walletID == wallet.id && $0.branch == "change" }
                .compactMap(\.index)
                .max() ?? -1

            return ChainKeypoolState(
                nextExternalIndex: max(max(maxExternalIndex, maxOwnedExternalIndex) + 1, 1),
                nextChangeIndex: max(max(maxChangeIndex, maxOwnedChangeIndex) + 1, 0),
                reservedReceiveIndex: nil
            )
        }

        let hasResolvedAddress = resolvedAddress(for: wallet, chainName: chainName) != nil
        let nextExternalIndex = hasResolvedAddress ? 1 : 0
        return ChainKeypoolState(
            nextExternalIndex: nextExternalIndex,
            nextChangeIndex: 0,
            reservedReceiveIndex: hasResolvedAddress ? 0 : nil
        )
    }

    private func keypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        if chainName == "Dogecoin" {
            let dogecoinState = keypoolState(for: wallet)
            let mirrored = ChainKeypoolState(
                nextExternalIndex: dogecoinState.nextExternalIndex,
                nextChangeIndex: dogecoinState.nextChangeIndex,
                reservedReceiveIndex: dogecoinState.reservedReceiveIndex
            )
            var perWallet = chainKeypoolByChain[chainName] ?? [:]
            perWallet[wallet.id] = mirrored
            chainKeypoolByChain[chainName] = perWallet
            return mirrored
        }

        let baseline = baselineChainKeypoolState(for: wallet, chainName: chainName)
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        if var existing = perWallet[wallet.id] {
            existing.nextExternalIndex = max(existing.nextExternalIndex, baseline.nextExternalIndex)
            existing.nextChangeIndex = max(existing.nextChangeIndex, baseline.nextChangeIndex)
            if existing.reservedReceiveIndex == nil {
                existing.reservedReceiveIndex = baseline.reservedReceiveIndex
            }
            perWallet[wallet.id] = existing
            chainKeypoolByChain[chainName] = perWallet
            return existing
        }

        perWallet[wallet.id] = baseline
        chainKeypoolByChain[chainName] = perWallet
        return baseline
    }

    private func reserveReceiveIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        if chainName == "Dogecoin" {
            return reserveDogecoinReceiveIndex(for: wallet)
        }

        var state = keypoolState(for: wallet, chainName: chainName)
        if let reserved = state.reservedReceiveIndex {
            return reserved
        }

        let reserved = max(state.nextExternalIndex, 0)
        state.reservedReceiveIndex = reserved
        state.nextExternalIndex = reserved + 1
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        perWallet[wallet.id] = state
        chainKeypoolByChain[chainName] = perWallet
        return reserved
    }

    private func reserveChangeIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        if chainName == "Dogecoin" {
            return reserveDogecoinChangeIndex(for: wallet)
        }

        var state = keypoolState(for: wallet, chainName: chainName)
        let reserved = max(state.nextChangeIndex, 0)
        state.nextChangeIndex = reserved + 1
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        perWallet[wallet.id] = state
        chainKeypoolByChain[chainName] = perWallet
        return reserved
    }

    private func reservedReceiveDerivationPath(for wallet: ImportedWallet, chainName: String, index: Int?) -> String? {
        if chainName == "Dogecoin" {
            guard let index else { return nil }
            return WalletDerivationPath.dogecoin(
                account: 0,
                branch: .external,
                index: UInt32(index)
            )
        }

        if supportsDeepUTXODiscovery(chainName: chainName) {
            guard let index else { return nil }
            return utxoDiscoveryDerivationPath(
                for: wallet,
                chainName: chainName,
                branch: .external,
                index: index
            )
        }

        guard seedDerivationChain(for: chainName) != nil else { return nil }
        return seedDerivationChain(for: chainName).map { walletDerivationPath(for: wallet, chain: $0) }
    }

    private func reservedReceiveAddress(for wallet: ImportedWallet, chainName: String, reserveIfMissing: Bool) -> String? {
        if chainName == "Dogecoin" {
            return dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: reserveIfMissing)
        }

        if supportsDeepUTXODiscovery(chainName: chainName) {
            var state = keypoolState(for: wallet, chainName: chainName)
            if state.reservedReceiveIndex == nil, reserveIfMissing {
                let reserved = max(state.nextExternalIndex, 1)
                state.reservedReceiveIndex = reserved
                state.nextExternalIndex = max(state.nextExternalIndex, reserved + 1)
                var perWallet = chainKeypoolByChain[chainName] ?? [:]
                perWallet[wallet.id] = state
                chainKeypoolByChain[chainName] = perWallet
            }

            guard let reservedIndex = state.reservedReceiveIndex,
                  let address = deriveUTXOAddress(
                    for: wallet,
                    chainName: chainName,
                    branch: .external,
                    index: reservedIndex
                  ) else {
                return resolvedAddress(for: wallet, chainName: chainName)
            }

            registerOwnedAddress(
                chainName: chainName,
                address: address,
                walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet,
                    chainName: chainName,
                    branch: .external,
                    index: reservedIndex
                ),
                index: reservedIndex,
                branch: "external"
            )
            return address
        }

        if reserveIfMissing {
            _ = reserveReceiveIndex(for: wallet, chainName: chainName)
        }
        guard let address = resolvedAddress(for: wallet, chainName: chainName) else { return nil }
        let reservedIndex = keypoolState(for: wallet, chainName: chainName).reservedReceiveIndex
        registerOwnedAddress(
            chainName: chainName,
            address: address,
            walletID: wallet.id,
            derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
            index: reservedIndex,
            branch: "external"
        )
        return address
    }

    private func activateLiveReceiveAddress(
        _ address: String?,
        for wallet: ImportedWallet,
        chainName: String,
        derivationPath: String? = nil
    ) -> String {
        guard let address else { return "" }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
        registerOwnedAddress(
            chainName: chainName,
            address: trimmed,
            walletID: wallet.id,
            derivationPath: derivationPath ?? reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
            index: reservedIndex,
            branch: "external"
        )
        return trimmed
    }

    func syncChainOwnedAddressManagementState() {
        for wallet in wallets {
            for chainName in ChainBackendRegistry.diagnosticsChains.map(\.title) {
                guard let address = resolvedAddress(for: wallet, chainName: chainName) else { continue }
                let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
                registerOwnedAddress(
                    chainName: chainName,
                    address: address,
                    walletID: wallet.id,
                    derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
                    index: reservedIndex,
                    branch: "external"
                )
            }
        }
    }


    private func baselineDogecoinKeypoolState(for wallet: ImportedWallet) -> DogecoinKeypoolState {
        let dogecoinTransactions = transactions.filter {
            $0.chainName == "Dogecoin"
                && $0.walletID == wallet.id
        }

        let maxExternalIndex = dogecoinTransactions
            .compactMap {
                parseDogecoinDerivationIndex(
                    path: $0.sourceDerivationPath,
                    expectedPrefix: WalletDerivationPath.dogecoinExternalPrefix(account: 0)
                )
            }
            .max() ?? 0
        let maxChangeIndex = dogecoinTransactions
            .compactMap {
                parseDogecoinDerivationIndex(
                    path: $0.changeDerivationPath,
                    expectedPrefix: WalletDerivationPath.dogecoinChangePrefix(account: 0)
                )
            }
            .max() ?? -1
        let maxOwnedExternalIndex = dogecoinOwnedAddressMap.values
            .filter { $0.walletID == wallet.id && $0.branch == "external" }
            .map(\.index)
            .max() ?? 0
        let maxOwnedChangeIndex = dogecoinOwnedAddressMap.values
            .filter { $0.walletID == wallet.id && $0.branch == "change" }
            .map(\.index)
            .max() ?? -1

        return DogecoinKeypoolState(
            nextExternalIndex: max(max(maxExternalIndex, maxOwnedExternalIndex) + 1, 1),
            nextChangeIndex: max(max(maxChangeIndex, maxOwnedChangeIndex) + 1, 0),
            reservedReceiveIndex: nil
        )
    }

    private func keypoolState(for wallet: ImportedWallet) -> DogecoinKeypoolState {
        let baseline = baselineDogecoinKeypoolState(for: wallet)
        if var existing = dogecoinKeypoolByWalletID[wallet.id] {
            existing.nextExternalIndex = max(existing.nextExternalIndex, baseline.nextExternalIndex)
            existing.nextChangeIndex = max(existing.nextChangeIndex, baseline.nextChangeIndex)
            if let reserved = existing.reservedReceiveIndex {
                existing.nextExternalIndex = max(existing.nextExternalIndex, reserved + 1)
            }
            dogecoinKeypoolByWalletID[wallet.id] = existing
            return existing
        }
        dogecoinKeypoolByWalletID[wallet.id] = baseline
        return baseline
    }

    private func reserveDogecoinReceiveIndex(for wallet: ImportedWallet) -> Int {
        var state = keypoolState(for: wallet)
        if let reserved = state.reservedReceiveIndex {
            return reserved
        }
        let reserved = max(state.nextExternalIndex, 1)
        state.reservedReceiveIndex = reserved
        state.nextExternalIndex = reserved + 1
        dogecoinKeypoolByWalletID[wallet.id] = state
        var genericState = chainKeypoolByChain["Dogecoin"] ?? [:]
        genericState[wallet.id] = ChainKeypoolState(
            nextExternalIndex: state.nextExternalIndex,
            nextChangeIndex: state.nextChangeIndex,
            reservedReceiveIndex: state.reservedReceiveIndex
        )
        chainKeypoolByChain["Dogecoin"] = genericState
        return reserved
    }

    func reserveDogecoinChangeIndex(for wallet: ImportedWallet) -> Int {
        var state = keypoolState(for: wallet)
        let reserved = max(state.nextChangeIndex, 0)
        state.nextChangeIndex = reserved + 1
        dogecoinKeypoolByWalletID[wallet.id] = state
        var genericState = chainKeypoolByChain["Dogecoin"] ?? [:]
        genericState[wallet.id] = ChainKeypoolState(
            nextExternalIndex: state.nextExternalIndex,
            nextChangeIndex: state.nextChangeIndex,
            reservedReceiveIndex: state.reservedReceiveIndex
        )
        chainKeypoolByChain["Dogecoin"] = genericState
        return reserved
    }

    private func dogecoinReservedReceiveAddress(for wallet: ImportedWallet, reserveIfMissing: Bool) -> String? {
        var state = keypoolState(for: wallet)
        if state.reservedReceiveIndex == nil, reserveIfMissing {
            let reserved = max(state.nextExternalIndex, 1)
            state.reservedReceiveIndex = reserved
            state.nextExternalIndex = max(state.nextExternalIndex, reserved + 1)
            dogecoinKeypoolByWalletID[wallet.id] = state
        }

        guard let reservedIndex = state.reservedReceiveIndex else {
            return nil
        }

        if let derivedAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: reservedIndex),
           isValidDogecoinAddressForPolicy(derivedAddress, networkMode: wallet.dogecoinNetworkMode) {
            registerDogecoinOwnedAddress(
                address: derivedAddress,
                walletID: wallet.id,
                derivationPath: WalletDerivationPath.dogecoin(
                    account: 0,
                    branch: .external,
                    index: UInt32(reservedIndex)
                ),
                index: reservedIndex,
                branch: "external",
                networkMode: wallet.dogecoinNetworkMode
            )
            return derivedAddress
        }

        return resolvedDogecoinAddress(for: wallet)
    }

    func refreshDogecoinReceiveReservationState() async {
        let dogecoinWallets = wallets.filter { $0.selectedChain == "Dogecoin" }
        guard !dogecoinWallets.isEmpty else { return }

        for wallet in dogecoinWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = reserveDogecoinReceiveIndex(for: wallet)
            var state = keypoolState(for: wallet)
            guard let reservedIndex = state.reservedReceiveIndex else { continue }
            guard let reservedAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: reservedIndex),
                  isValidDogecoinAddressForPolicy(reservedAddress, networkMode: wallet.dogecoinNetworkMode) else {
                continue
            }

            registerDogecoinOwnedAddress(
                address: reservedAddress,
                walletID: wallet.id,
                derivationPath: WalletDerivationPath.dogecoin(
                    account: 0,
                    branch: .external,
                    index: UInt32(reservedIndex)
                ),
                index: reservedIndex,
                branch: "external",
                networkMode: wallet.dogecoinNetworkMode
            )

            let hasActivity = await hasDogecoinOnChainActivity(address: reservedAddress, networkMode: wallet.dogecoinNetworkMode)
            guard hasActivity else { continue }

            let nextReserved = max(state.nextExternalIndex, reservedIndex + 1)
            state.reservedReceiveIndex = nextReserved
            state.nextExternalIndex = max(state.nextExternalIndex, nextReserved + 1)
            dogecoinKeypoolByWalletID[wallet.id] = state

            if let nextAddress = deriveDogecoinAddress(for: wallet, isChange: false, index: nextReserved),
               isValidDogecoinAddressForPolicy(nextAddress, networkMode: wallet.dogecoinNetworkMode) {
                registerDogecoinOwnedAddress(
                    address: nextAddress,
                    walletID: wallet.id,
                    derivationPath: WalletDerivationPath.dogecoin(
                        account: 0,
                        branch: .external,
                        index: UInt32(nextReserved)
                    ),
                    index: nextReserved,
                    branch: "external",
                    networkMode: wallet.dogecoinNetworkMode
                )
            }
        }
    }

    private func hasDogecoinOnChainActivity(
        address: String,
        networkMode: DogecoinNetworkMode
    ) async -> Bool {
        if let snapshots = try? await DogecoinBalanceService.fetchRecentTransactions(for: address, limit: 1, networkMode: networkMode),
           !snapshots.isEmpty {
            return true
        }
        if let balance = try? await DogecoinBalanceService.fetchBalance(for: address, networkMode: networkMode),
           balance > 0 {
            return true
        }
        return false
    }

    private func discoverDogecoinAddresses(for wallet: ImportedWallet) async -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidDogecoinAddressForPolicy(trimmed) else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(trimmed)
        }

        appendAddress(wallet.dogecoinAddress)
        appendAddress(resolvedDogecoinAddress(for: wallet))
        appendAddress(dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: false))
        for transaction in transactions where
            transaction.chainName == "Dogecoin"
            && transaction.walletID == wallet.id
        {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }

        if let seedPhrase = storedSeedPhrase(for: wallet.id) {
            let state = keypoolState(for: wallet)
            let highestOwnedExternal = dogecoinOwnedAddressMap.values
                .filter { $0.walletID == wallet.id && $0.branch == "external" }
                .map(\.index)
                .max() ?? 0
            let reserved = state.reservedReceiveIndex ?? 0
            let scanUpperBound = min(
                Self.dogecoinDiscoveryMaxIndex,
                max(state.nextExternalIndex, max(highestOwnedExternal + 1, reserved + 1)) + Self.dogecoinDiscoveryGapLimit
            )
            if scanUpperBound >= 0 {
                for index in 0 ... scanUpperBound {
                    if let derived = try? DogecoinWalletEngine.derivedAddress(
                        for: seedPhrase,
                        networkMode: wallet.dogecoinNetworkMode,
                        isChange: false,
                        index: index,
                        account: Int(derivationAccount(for: wallet, chain: .dogecoin))
                    ) {
                        appendAddress(derived)
                    }
                }
            }
        }

        return ordered
    }

    private func deriveDogecoinAddress(for wallet: ImportedWallet, isChange: Bool, index: Int) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { return nil }
        return try? DogecoinWalletEngine.derivedAddress(
            for: seedPhrase,
            networkMode: wallet.dogecoinNetworkMode,
            isChange: isChange,
            index: index,
            account: Int(derivationAccount(for: wallet, chain: .dogecoin))
        )
    }

    func refreshDogecoinAddressDiscovery() async {
        let dogecoinWallets = wallets.filter { $0.selectedChain == "Dogecoin" }
        guard !dogecoinWallets.isEmpty else {
            discoveredDogecoinAddressesByWallet = [:]
            return
        }

        let discovered = await withTaskGroup(of: (UUID, [String]).self, returning: [UUID: [String]].self) { group in
            for wallet in dogecoinWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverDogecoinAddresses(for: wallet)
                    return (wallet.id, addresses)
                }
            }

            var mapping: [UUID: [String]] = [:]
            for await (walletID, addresses) in group {
                mapping[walletID] = addresses
            }
            return mapping
        }

        discoveredDogecoinAddressesByWallet = discovered
    }

    // Recomputes gas/fee and projected impact for ETH/BSC send composer.
    func refreshEthereumSendPreview() async {
        await WalletSendLayer.refreshEthereumSendPreview(using: self)
    }

    func refreshDogecoinSendPreview() async {
        await WalletSendLayer.refreshDogecoinSendPreview(using: self)
    }

    func refreshBitcoinSendPreview() async {
        await WalletSendLayer.refreshBitcoinSendPreview(using: self)
    }

    func refreshBitcoinCashSendPreview() async {
        await WalletSendLayer.refreshBitcoinCashSendPreview(using: self)
    }

    func refreshBitcoinSVSendPreview() async {
        await WalletSendLayer.refreshBitcoinSVSendPreview(using: self)
    }

    func refreshLitecoinSendPreview() async {
        await WalletSendLayer.refreshLitecoinSendPreview(using: self)
    }

    func refreshTronSendPreview() async {
        await WalletSendLayer.refreshTronSendPreview(using: self)
    }

    func refreshSolanaSendPreview() async {
        await WalletSendLayer.refreshSolanaSendPreview(using: self)
    }

    func refreshXRPSendPreview() async {
        await WalletSendLayer.refreshXRPSendPreview(using: self)
    }

    func refreshStellarSendPreview() async {
        await WalletSendLayer.refreshStellarSendPreview(using: self)
    }

    func refreshMoneroSendPreview() async {
        await WalletSendLayer.refreshMoneroSendPreview(using: self)
    }

    func refreshCardanoSendPreview() async {
        await WalletSendLayer.refreshCardanoSendPreview(using: self)
    }

    func refreshSuiSendPreview() async {
        await WalletSendLayer.refreshSuiSendPreview(using: self)
    }

    func refreshAptosSendPreview() async {
        await WalletSendLayer.refreshAptosSendPreview(using: self)
    }

    func refreshTONSendPreview() async {
        await WalletSendLayer.refreshTONSendPreview(using: self)
    }

    func refreshICPSendPreview() async {
        await WalletSendLayer.refreshICPSendPreview(using: self)
    }

    func refreshNearSendPreview() async {
        await WalletSendLayer.refreshNearSendPreview(using: self)
    }

    func refreshPolkadotSendPreview() async {
        await WalletSendLayer.refreshPolkadotSendPreview(using: self)
    }

    func refreshSendPreview() async {
        await WalletSendLayer.refreshSendPreview(using: self)
    }

    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let probeID = "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)"
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDestination.isEmpty else {
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }

        var destinationForProbe = trimmedDestination
        var ensResolutionInfo: String?
        if !isValidAddress(trimmedDestination, for: coin.chainName) {
            if (coin.chainName == "Ethereum" || coin.chainName == "Arbitrum" || coin.chainName == "Optimism" || coin.chainName == "BNB Chain" || coin.chainName == "Avalanche" || coin.chainName == "Hyperliquid"), isENSNameCandidate(trimmedDestination) {
                do {
                    let resolved = try await resolveEVMRecipientAddress(input: trimmedDestination, for: coin.chainName)
                    destinationForProbe = resolved.address
                    ensResolutionInfo = resolved.usedENS ? "Resolved ENS \(trimmedDestination) to \(resolved.address)." : nil
                } catch {
                    sendDestinationRiskWarning = nil
                    sendDestinationInfoMessage = nil
                    isCheckingSendDestinationBalance = false
                    return
                }
            } else {
                sendDestinationRiskWarning = nil
                sendDestinationInfoMessage = nil
                isCheckingSendDestinationBalance = false
                return
            }
        }

        let addressProbeKey = "\(coin.chainName)|\(coin.symbol)|\(destinationForProbe.lowercased())"
        if lastSendDestinationProbeKey == addressProbeKey {
            sendDestinationRiskWarning = lastSendDestinationProbeWarning
            if let ensResolutionInfo {
                sendDestinationInfoMessage = [lastSendDestinationProbeInfoMessage, ensResolutionInfo]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                sendDestinationInfoMessage = lastSendDestinationProbeInfoMessage
            }
            isCheckingSendDestinationBalance = false
            return
        }

        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }

        do {
            let warning: String?
            let infoMessage: String?
            switch coin.chainName {
            case "Bitcoin":
                let balance = try await BitcoinBalanceService.fetchBalance(for: destinationForProbe, networkMode: self.bitcoinNetworkMode)
                let hasHistory = try await BitcoinBalanceService.hasTransactionHistory(for: destinationForProbe, networkMode: self.bitcoinNetworkMode)
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Bitcoin address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Bitcoin address has transaction history but currently zero balance."
                    : nil
            case "Litecoin":
                let balance = try await LitecoinBalanceService.fetchBalance(for: destinationForProbe)
                let hasHistory = try await LitecoinBalanceService.hasTransactionHistory(for: destinationForProbe)
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Litecoin address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Litecoin address has transaction history but currently zero balance."
                    : nil
            case "Dogecoin":
                guard coin.symbol == "DOGE" else {
                    warning = nil
                    infoMessage = nil
                    break
                }
                let destinationNetworkMode = wallet(for: sendWalletID).map(dogecoinNetworkMode(for:)) ?? dogecoinNetworkMode
                let balance = try await DogecoinBalanceService.fetchBalance(for: destinationForProbe, networkMode: destinationNetworkMode)
                let hasHistory = !(try await DogecoinBalanceService.fetchRecentTransactions(for: destinationForProbe, limit: 1, networkMode: destinationNetworkMode)).isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Dogecoin address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Dogecoin address has transaction history but currently zero balance."
                    : nil
            case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
                guard let chain = evmChainContext(for: coin.chainName) else {
                    warning = nil
                    infoMessage = nil
                    break
                }
                let normalizedAddress = try EthereumWalletEngine.validateAddress(destinationForProbe)
                let transactionCount = try await EthereumWalletEngine.fetchTransactionCount(
                    for: normalizedAddress,
                    rpcEndpoint: configuredEVMRPCEndpointURL(for: coin.chainName),
                    chain: chain
                )
                let hasHistory = transactionCount > 0
                if coin.symbol == "ETH" || coin.symbol == "BNB" {
                    let snapshot = try await EthereumWalletEngine.fetchAccountSnapshot(
                        for: normalizedAddress,
                        rpcEndpoint: configuredEVMRPCEndpointURL(for: coin.chainName),
                        chain: chain
                    )
                    let nativeBalance = EthereumWalletEngine.nativeBalanceETH(from: snapshot)
                    warning = (nativeBalance <= 0 && !hasHistory)
                        ? "Warning: this \(coin.chainName) address has zero balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage = (nativeBalance <= 0 && hasHistory)
                        ? "Note: this \(coin.chainName) address has transaction history but currently zero \(coin.symbol) balance."
                        : nil
                } else if let token = supportedEVMToken(for: coin) {
                    let tokenBalances = try await EthereumWalletEngine.plannedTokenBalances(
                        for: normalizedAddress,
                        tokenContracts: [token.contractAddress],
                        rpcEndpoint: configuredEVMRPCEndpointURL(for: coin.chainName),
                        chain: chain
                    )
                    let tokenBalance = tokenBalances.first?.balance ?? .zero
                    warning = (tokenBalance <= .zero && !hasHistory)
                        ? "Warning: this address has zero \(coin.symbol) balance and no transaction history on \(coin.chainName). Double-check recipient details."
                        : nil
                    infoMessage = (tokenBalance <= .zero && hasHistory)
                        ? "Note: this address has transaction history but currently zero \(coin.symbol) balance on \(coin.chainName)."
                        : nil
                } else {
                    warning = nil
                    infoMessage = nil
                }
            case "Tron":
                if coin.symbol == "TRX" {
                    let result = try await TronBalanceService.fetchBalances(for: destinationForProbe)
                    let history = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                    let hasHistory = !history.snapshots.isEmpty
                    warning = (result.trxBalance <= 0 && !hasHistory)
                        ? "Warning: this Tron address has zero TRX balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage = (result.trxBalance <= 0 && hasHistory)
                        ? "Note: this Tron address has transaction history but currently zero TRX balance."
                        : nil
                } else if coin.symbol == "USDT" {
                    let result = try await TronBalanceService.fetchBalances(for: destinationForProbe)
                    let usdtBalance = result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0
                    let history = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                    let hasHistory = !history.snapshots.isEmpty
                    warning = (usdtBalance <= 0 && !hasHistory)
                        ? "Warning: this Tron address has zero USDT balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage = (usdtBalance <= 0 && hasHistory)
                        ? "Note: this Tron address has transaction history but currently zero USDT balance."
                        : nil
                } else {
                    warning = nil
                    infoMessage = nil
                }
            case "Solana":
                let balance = try await SolanaBalanceService.fetchBalance(for: destinationForProbe)
                let history = await SolanaBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Solana address has zero SOL balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Solana address has transaction history but currently zero SOL balance."
                    : nil
            case "XRP Ledger":
                let balance = try await XRPBalanceService.fetchBalance(for: destinationForProbe)
                let history = await XRPBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this XRP address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this XRP address has transaction history but currently zero XRP balance."
                    : nil
            case "Monero":
                let balance = try await MoneroBalanceService.fetchBalance(for: destinationForProbe)
                let history = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Monero address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Monero address has transaction history but currently zero XMR balance."
                    : nil
            case "Sui":
                let balance = try await SuiBalanceService.fetchBalance(for: destinationForProbe)
                let history = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Sui address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Sui address has transaction history but currently zero SUI balance."
                    : nil
            case "Aptos":
                let balance = try await AptosBalanceService.fetchBalance(for: destinationForProbe)
                let history = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this Aptos address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this Aptos address has transaction history but currently zero APT balance."
                    : nil
            case "NEAR":
                let balance = try await NearBalanceService.fetchBalance(for: destinationForProbe)
                let history = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: destinationForProbe, limit: 1)
                let hasHistory = !history.snapshots.isEmpty
                warning = (balance <= 0 && !hasHistory)
                    ? "Warning: this NEAR address has zero balance and no transaction history. Double-check recipient details."
                    : nil
                infoMessage = (balance <= 0 && hasHistory)
                    ? "Note: this NEAR address has transaction history but currently zero NEAR balance."
                    : nil
            default:
                warning = nil
                infoMessage = nil
            }

            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = warning
            sendDestinationInfoMessage = [infoMessage, ensResolutionInfo]
                .compactMap { $0 }
                .joined(separator: " ")
            lastSendDestinationProbeKey = addressProbeKey
            lastSendDestinationProbeWarning = warning
            lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
        } catch {
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
        }
    }
    
    func userFacingTronSendError(_ error: Error, symbol: String) -> String {
        if let tronError = error as? TronWalletEngineError {
            switch tronError {
            case .invalidAddress:
                return "Enter a valid Tron address (starts with T)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt(symbol)
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Tron signer."
            case .unsupportedTokenContract:
                return "Only official USDT on Tron is supported for now."
            case .createTransactionFailed(let message):
                return message
            case .signFailed(let message):
                return "Failed to sign Tron transaction: \(message)"
            case .broadcastFailed(let message):
                return message
            }
        }

        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("timed out") {
            return "Tron network request timed out. Please try again."
        }
        if message.localizedCaseInsensitiveContains("not connected")
            || message.localizedCaseInsensitiveContains("offline") {
            return "No network connection. Check your internet and retry."
        }
        return message
    }

    func recordTronSendDiagnosticError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tronLastSendErrorDetails = trimmed
        tronLastSendErrorAt = Date()
    }

    func userFacingXRPSendError(_ error: Error) -> String {
        if let xrpError = error as? XRPWalletEngineError {
            switch xrpError {
            case .invalidAddress:
                return "Enter a valid XRP address (starts with r)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("XRP")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid XRP signer."
            case .signingFailed(let message):
                return "Failed to sign XRP transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingStellarSendError(_ error: Error) -> String {
        if let stellarError = error as? StellarWalletEngineError {
            switch stellarError {
            case .invalidAddress:
                return "Enter a valid Stellar address (starts with G)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("XLM")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Stellar signer."
            case .invalidResponse:
                return "Invalid response from Stellar network."
            case .signingFailed(let message):
                return "Failed to sign Stellar transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingMoneroSendError(_ error: Error) -> String {
        if let moneroError = error as? MoneroWalletEngineError {
            switch moneroError {
            case .invalidAddress:
                return "Enter a valid Monero address (starts with 4 or 8)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("XMR")
            case .backendNotConfigured:
                return "Monero backend is not configured. Set monero.backend.baseURL in app defaults."
            case .backendRejected(let message):
                return message
            case .invalidResponse:
                return "Invalid response from Monero backend."
            }
        }
        return error.localizedDescription
    }

    func userFacingCardanoSendError(_ error: Error) -> String {
        if let cardanoError = error as? CardanoWalletEngineError {
            switch cardanoError {
            case .invalidAddress:
                return "Enter a valid Cardano address (starts with addr1)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("ADA")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Cardano signer."
            case .signingFailed(let message):
                return "Failed to sign Cardano transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingSuiSendError(_ error: Error) -> String {
        if let suiError = error as? SuiWalletEngineError {
            switch suiError {
            case .invalidAddress:
                return "Enter a valid Sui address (starts with 0x)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("SUI")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Sui signer."
            case .insufficientBalance:
                return "Insufficient SUI for amount plus network fee."
            case .invalidResponse:
                return "Invalid response from Sui network."
            case .signingFailed(let message):
                return "Failed to sign Sui transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingAptosSendError(_ error: Error) -> String {
        if let aptosError = error as? AptosWalletEngineError {
            switch aptosError {
            case .invalidAddress:
                return "Enter a valid Aptos address (starts with 0x)."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("APT")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Aptos signer."
            case .insufficientBalance:
                return "Insufficient APT for amount plus network fee."
            case .invalidResponse:
                return "Invalid response from Aptos network."
            case .signingFailed(let message):
                return "Failed to sign Aptos transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingTONSendError(_ error: Error) -> String {
        if let tonError = error as? TONWalletEngineError {
            switch tonError {
            case .invalidAddress:
                return localizedStoreString("Enter a valid TON address.")
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("TON")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid TON signer."
            case .invalidResponse:
                return "Invalid response from TON network."
            case .insufficientBalance:
                return "Insufficient TON for amount plus network fee."
            case .signingFailed(let message):
                return "Failed to sign TON transaction: \(message)"
            case .networkError(let message), .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingNearSendError(_ error: Error) -> String {
        if let nearError = error as? NearWalletEngineError {
            switch nearError {
            case .invalidAddress:
                return localizedStoreString("Enter a valid NEAR account ID or implicit address.")
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("NEAR")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid NEAR signer."
            case .invalidResponse:
                return "Invalid response from NEAR network."
            case .accessKeyUnavailable:
                return "No NEAR full-access key was found for this account."
            case .signingFailed(let message):
                return "Failed to sign NEAR transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingPolkadotSendError(_ error: Error) -> String {
        if let polkadotError = error as? PolkadotWalletEngineError {
            switch polkadotError {
            case .invalidAddress:
                return localizedStoreString("Enter a valid Polkadot SS58 address.")
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("DOT")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid Polkadot signer."
            case .invalidResponse:
                return "Invalid response from Polkadot network."
            case .signingFailed(let message):
                return "Failed to sign Polkadot transaction: \(message)"
            case .networkError(let message):
                return message
            case .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    func userFacingICPSendError(_ error: Error) -> String {
        if let icpError = error as? ICPWalletEngineError {
            switch icpError {
            case .invalidAddress:
                return "Enter a valid Internet Computer account identifier."
            case .invalidAmount:
                return CommonLocalization.invalidAssetAmountPrompt("ICP")
            case .invalidSeedPhrase:
                return "This wallet seed phrase cannot derive a valid ICP signer."
            case .invalidResponse:
                return "Invalid response from Internet Computer network."
            case .insufficientBalance:
                return "Insufficient ICP for amount plus network fee."
            case .signingFailed(let message), .networkError(let message), .broadcastFailed(let message):
                return message
            }
        }
        return error.localizedDescription
    }

    // Main send execution dispatcher.
    // Performs final validation, signs via chain engine, broadcasts, then records transaction.
    func submitSend() async {
        await WalletSendLayer.submitSend(using: self)
    }
    
    // Opens receive flow and prepares default receiving asset/chain context.
    // MARK: - Receive Flow
    func beginReceive() {
        guard let firstWallet = receiveEnabledWallets.first else { return }
        receiveWalletID = firstWallet.id.uuidString
        receiveChainName = availableReceiveChains(for: receiveWalletID).first ?? ""
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
        isShowingReceiveSheet = true
    }
    
    func syncReceiveAssetSelection() {
        let availableChains = availableReceiveChains(for: receiveWalletID)
        if !availableChains.contains(receiveChainName) {
            receiveChainName = availableChains.first ?? ""
        }
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    
    func refreshPendingTransactions(
        includeHistoryRefreshes: Bool = true,
        historyRefreshInterval: TimeInterval = 120
    ) async {
        guard !isRefreshingPendingTransactions else { return }
        let trackedChains = pendingTransactionMaintenanceChainIDs
        guard !trackedChains.isEmpty else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        isRefreshingPendingTransactions = true
        defer {
            isRefreshingPendingTransactions = false
            recordPerformanceSample(
                "refresh_pending_transactions",
                startedAt: startedAt,
                metadata: "chains=\(trackedChains.count) include_history=\(includeHistoryRefreshes)"
            )
        }

        lastPendingTransactionRefreshAt = Date()
        let trackedTransactionIDs = Set(
            transactions.compactMap { transaction -> UUID? in
                guard transaction.kind == .send, transaction.transactionHash != nil else { return nil }
                if transaction.status == .pending {
                    return transaction.id
                }
                if transaction.status == .confirmed {
                    return transaction.id
                }
                return nil
            }
        )
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedTransactionIDs.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            if trackedChains.contains(WalletChainID("Bitcoin")!) {
                group.addTask { await self.refreshPendingBitcoinTransactions() }
            }
            if trackedChains.contains(WalletChainID("Bitcoin Cash")!) {
                group.addTask { await self.refreshPendingBitcoinCashTransactions() }
            }
            if trackedChains.contains(WalletChainID("Litecoin")!) {
                group.addTask { await self.refreshPendingLitecoinTransactions() }
            }
            if trackedChains.contains(WalletChainID("Ethereum")!) {
                group.addTask { await self.refreshPendingEthereumTransactions() }
            }
            if trackedChains.contains(WalletChainID("Arbitrum")!) {
                group.addTask { await self.refreshPendingArbitrumTransactions() }
            }
            if trackedChains.contains(WalletChainID("Optimism")!) {
                group.addTask { await self.refreshPendingOptimismTransactions() }
            }
            if trackedChains.contains(WalletChainID("Ethereum Classic")!) {
                group.addTask { await self.refreshPendingETCTransactions() }
            }
            if trackedChains.contains(WalletChainID("BNB Chain")!) {
                group.addTask { await self.refreshPendingBNBTransactions() }
            }
            if trackedChains.contains(WalletChainID("Avalanche")!) {
                group.addTask { await self.refreshPendingAvalancheTransactions() }
            }
            if trackedChains.contains(WalletChainID("Hyperliquid")!) {
                group.addTask { await self.refreshPendingHyperliquidTransactions() }
            }
            if trackedChains.contains(WalletChainID("Dogecoin")!) {
                group.addTask { await self.refreshPendingDogecoinTransactions() }
            }
            if trackedChains.contains(WalletChainID("Tron")!) {
                group.addTask { await self.refreshPendingTronTransactions() }
            }
            if trackedChains.contains(WalletChainID("Solana")!) {
                group.addTask { await self.refreshPendingSolanaTransactions() }
            }
            if trackedChains.contains(WalletChainID("Cardano")!) {
                group.addTask { await self.refreshPendingCardanoTransactions() }
            }
            if trackedChains.contains(WalletChainID("XRP Ledger")!) {
                group.addTask { await self.refreshPendingXRPTransactions() }
            }
            if trackedChains.contains(WalletChainID("Stellar")!) {
                group.addTask { await self.refreshPendingStellarTransactions() }
            }
            if trackedChains.contains(WalletChainID("Monero")!) {
                group.addTask { await self.refreshPendingMoneroTransactions() }
            }
            if trackedChains.contains(WalletChainID("Sui")!) {
                group.addTask { await self.refreshPendingSuiTransactions() }
            }
            if trackedChains.contains(WalletChainID("Aptos")!) {
                group.addTask { await self.refreshPendingAptosTransactions() }
            }
            if trackedChains.contains(WalletChainID("TON")!) {
                group.addTask { await self.refreshPendingTONTransactions() }
            }
            if trackedChains.contains(WalletChainID("Internet Computer")!) {
                group.addTask { await self.refreshPendingICPTransactions() }
            }
            if trackedChains.contains(WalletChainID("NEAR")!) {
                group.addTask { await self.refreshPendingNearTransactions() }
            }
            if trackedChains.contains(WalletChainID("Polkadot")!) {
                group.addTask { await self.refreshPendingPolkadotTransactions() }
            }
            await group.waitForAll()
        }

        guard includeHistoryRefreshes else {
            if let lastSentTransaction,
               let refreshedTransaction = transactions.first(where: { $0.id == lastSentTransaction.id }) {
                self.lastSentTransaction = refreshedTransaction
                updateSendVerificationNoticeForLastSentTransaction()
            }
            return
        }

        await runPendingTransactionHistoryRefreshes(
            for: trackedChains,
            interval: historyRefreshInterval
        )

        if let lastSentTransaction,
           let refreshedTransaction = transactions.first(where: { $0.id == lastSentTransaction.id }) {
            self.lastSentTransaction = refreshedTransaction
            updateSendVerificationNoticeForLastSentTransaction()
        }
    }

    var pendingTransactionRefreshStatusText: String? {
        guard let lastPendingTransactionRefreshAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeText = formatter.localizedString(for: lastPendingTransactionRefreshAt, relativeTo: Date())
        return localizedStoreFormat("Last checked %@", relativeText)
    }
    
    // Returns best available receive address for active receive selection.
    // May use derived address, watched address, or chain-specific resolver output.
    func receiveAddress() -> String {
        guard let wallet = wallet(for: receiveWalletID),
              let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            return "Select a wallet and chain"
        }
        
        if receiveCoin.symbol == "BTC" {
            if !receiveResolvedAddress.isEmpty {
                return receiveResolvedAddress
            }
            if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bitcoinAddress.isEmpty {
                return bitcoinAddress
            }
            if storedSeedPhrase(for: wallet.id) == nil {
                return "Bitcoin receive unavailable. Open Edit Name and add the seed phrase or BTC watch address."
            }
            return isResolvingReceiveAddress
                ? "Loading Bitcoin receive address..."
                : "Tap Refresh or reopen Receive to resolve a Bitcoin address."
        }

        if receiveCoin.symbol == "BCH", receiveCoin.chainName == "Bitcoin Cash" {
            if !receiveResolvedAddress.isEmpty {
                return receiveResolvedAddress
            }
            if let bitcoinCashAddress = resolvedBitcoinCashAddress(for: wallet),
               !bitcoinCashAddress.isEmpty {
                return bitcoinCashAddress
            }
            if storedSeedPhrase(for: wallet.id) == nil {
                return "Bitcoin Cash receive unavailable. Open Edit Name and add the seed phrase or BCH watch address."
            }
            return isResolvingReceiveAddress
                ? "Loading Bitcoin Cash receive address..."
                : "Tap Refresh or reopen Receive to resolve a Bitcoin Cash address."
        }

        if receiveCoin.symbol == "BSV", receiveCoin.chainName == "Bitcoin SV" {
            if !receiveResolvedAddress.isEmpty {
                return receiveResolvedAddress
            }
            if let bitcoinSVAddress = resolvedBitcoinSVAddress(for: wallet),
               !bitcoinSVAddress.isEmpty {
                return bitcoinSVAddress
            }
            if storedSeedPhrase(for: wallet.id) == nil {
                return "Bitcoin SV receive unavailable. Open Edit Name and add the seed phrase or BSV watch address."
            }
            return isResolvingReceiveAddress
                ? "Loading Bitcoin SV receive address..."
                : "Tap Refresh or reopen Receive to resolve a Bitcoin SV address."
        }

        if receiveCoin.symbol == "LTC", receiveCoin.chainName == "Litecoin" {
            if !receiveResolvedAddress.isEmpty {
                return receiveResolvedAddress
            }
            if let litecoinAddress = resolvedLitecoinAddress(for: wallet),
               !litecoinAddress.isEmpty {
                return litecoinAddress
            }
            if storedSeedPhrase(for: wallet.id) == nil {
                return "Litecoin receive unavailable. Open Edit Name and add the seed phrase or LTC watch address."
            }
            return isResolvingReceiveAddress
                ? "Loading Litecoin receive address..."
                : "Tap Refresh or reopen Receive to resolve a Litecoin address."
        }

        if receiveCoin.symbol == "DOGE", receiveCoin.chainName == "Dogecoin" {
            if !receiveResolvedAddress.isEmpty {
                return receiveResolvedAddress
            }
            let hasSeed = storedSeedPhrase(for: wallet.id) != nil
            let hasWatchAddress = wallet.dogecoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasSeed || hasWatchAddress else {
                return "Dogecoin receive unavailable. Open Edit Name and add a seed phrase or DOGE watch address."
            }
            return isResolvingReceiveAddress
                ? "Loading Dogecoin receive address..."
                : "Tap Refresh or reopen Receive to resolve a Dogecoin address."
        }

        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else {
                return "\(receiveCoin.chainName) receive unavailable. Open Edit Name and add the seed phrase."
            }
            return receiveResolvedAddress.isEmpty ? evmAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Tron" {
            guard let tronAddress = resolvedTronAddress(for: wallet) else {
                return "Tron receive unavailable. Open Edit Name and add the seed phrase or TRON watch address."
            }
            return receiveResolvedAddress.isEmpty ? tronAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Solana" {
            guard let solanaAddress = resolvedSolanaAddress(for: wallet) else {
                return "Solana receive unavailable. Open Edit Name and add the seed phrase or SOL watch address."
            }
            return receiveResolvedAddress.isEmpty ? solanaAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Cardano" {
            guard let cardanoAddress = resolvedCardanoAddress(for: wallet) else {
                return "Cardano receive unavailable. Open Edit Name and add the seed phrase."
            }
            return receiveResolvedAddress.isEmpty ? cardanoAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "XRP Ledger" {
            guard let xrpAddress = resolvedXRPAddress(for: wallet) else {
                return "XRP receive unavailable. Open Edit Name and add the seed phrase or XRP watch address."
            }
            return receiveResolvedAddress.isEmpty ? xrpAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Stellar" {
            guard let stellarAddress = resolvedStellarAddress(for: wallet) else {
                return "Stellar receive unavailable. Open Edit Name and add the seed phrase or Stellar watch address."
            }
            return receiveResolvedAddress.isEmpty ? stellarAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Monero" {
            guard let moneroAddress = resolvedMoneroAddress(for: wallet) else {
                return "Monero receive unavailable. Open Edit Name and add a Monero address."
            }
            return receiveResolvedAddress.isEmpty ? moneroAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Sui" {
            guard let suiAddress = resolvedSuiAddress(for: wallet) else {
                return "Sui receive unavailable. Open Edit Name and add the seed phrase or Sui watch address."
            }
            return receiveResolvedAddress.isEmpty ? suiAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Aptos" {
            guard let aptosAddress = resolvedAptosAddress(for: wallet) else {
                return "Aptos receive unavailable. Open Edit Name and add the seed phrase or Aptos watch address."
            }
            return receiveResolvedAddress.isEmpty ? aptosAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "TON" {
            guard let tonAddress = resolvedTONAddress(for: wallet) else {
                return "TON receive unavailable. Open Edit Name and add the seed phrase or TON watch address."
            }
            return receiveResolvedAddress.isEmpty ? tonAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Internet Computer" {
            guard let icpAddress = resolvedICPAddress(for: wallet) else {
                return "Internet Computer receive unavailable. Open Edit Name and add the seed phrase or ICP watch address."
            }
            return receiveResolvedAddress.isEmpty ? icpAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "NEAR" {
            guard let nearAddress = resolvedNearAddress(for: wallet) else {
                return "NEAR receive unavailable. Open Edit Name and add the seed phrase or NEAR watch address."
            }
            return receiveResolvedAddress.isEmpty ? nearAddress : receiveResolvedAddress
        }

        if receiveCoin.chainName == "Polkadot" {
            guard let polkadotAddress = resolvedPolkadotAddress(for: wallet) else {
                return "Polkadot receive unavailable. Open Edit Name and add the seed phrase or Polkadot watch address."
            }
            return receiveResolvedAddress.isEmpty ? polkadotAddress : receiveResolvedAddress
        }
        
        return "Receive is not enabled for this chain."
    }

    // Refreshes/derives receive address when chain/address strategy requires async resolution.
    func refreshReceiveAddress() async {
        guard let wallet = wallet(for: receiveWalletID),
              let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            receiveResolvedAddress = ""
            return
        }
        
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else {
                receiveResolvedAddress = ""
                return
            }

            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }

            do {
                receiveResolvedAddress = activateLiveReceiveAddress(
                    try EthereumWalletEngine.receiveAddress(for: evmAddress),
                    for: wallet,
                    chainName: receiveCoin.chainName
                )
            } catch {
                receiveResolvedAddress = ""
            }
            return
        }

        if receiveCoin.chainName == "Tron" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedTronAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Solana" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedSolanaAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Cardano" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedCardanoAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "XRP Ledger" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedXRPAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Stellar" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedStellarAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Monero" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedMoneroAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Sui" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedSuiAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Aptos" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedAptosAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "TON" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedTONAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Internet Computer" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedICPAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "NEAR" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedNearAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.chainName == "Polkadot" {
            receiveResolvedAddress = activateLiveReceiveAddress(
                resolvedPolkadotAddress(for: wallet),
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if receiveCoin.symbol == "DOGE", receiveCoin.chainName == "Dogecoin" {
            guard let dogecoinAddress = dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: true) else {
                receiveResolvedAddress = ""
                return
            }
            receiveResolvedAddress = dogecoinAddress
            return
        }

        guard receiveCoin.symbol == "BTC" else {
            if receiveCoin.symbol == "BCH", receiveCoin.chainName == "Bitcoin Cash" {
                receiveResolvedAddress = reservedReceiveAddress(
                    for: wallet,
                    chainName: receiveCoin.chainName,
                    reserveIfMissing: true
                ) ?? ""
                return
            }
            if receiveCoin.symbol == "BSV", receiveCoin.chainName == "Bitcoin SV" {
                receiveResolvedAddress = reservedReceiveAddress(
                    for: wallet,
                    chainName: receiveCoin.chainName,
                    reserveIfMissing: true
                ) ?? ""
                return
            }
            if receiveCoin.symbol == "LTC", receiveCoin.chainName == "Litecoin" {
                receiveResolvedAddress = reservedReceiveAddress(
                    for: wallet,
                    chainName: receiveCoin.chainName,
                    reserveIfMissing: true
                ) ?? ""
                return
            }
            receiveResolvedAddress = ""
            return
        }

        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bitcoinAddress.isEmpty,
           storedSeedPhrase(for: wallet.id) == nil {
            receiveResolvedAddress = activateLiveReceiveAddress(
                bitcoinAddress,
                for: wallet,
                chainName: receiveCoin.chainName
            )
            return
        }

        if storedSeedPhrase(for: wallet.id) == nil,
           let bitcoinXPub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bitcoinXPub.isEmpty {
            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }

            do {
                receiveResolvedAddress = activateLiveReceiveAddress(
                    try await BitcoinBalanceService.fetchReceiveAddress(forExtendedPublicKey: bitcoinXPub),
                    for: wallet,
                    chainName: receiveCoin.chainName
                )
            } catch {
                receiveResolvedAddress = ""
            }
            return
        }

        guard !isResolvingReceiveAddress else { return }
        isResolvingReceiveAddress = true
        defer { isResolvingReceiveAddress = false }

        do {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else {
                receiveResolvedAddress = ""
                return
            }
            receiveResolvedAddress = activateLiveReceiveAddress(
                try await BitcoinWalletEngine.nextReceiveAddressInBackground(for: wallet, seedPhrase: seedPhrase),
                for: wallet,
                chainName: receiveCoin.chainName
            )
        } catch {
            receiveResolvedAddress = ""
        }
    }
    
    // Wallet import/edit entry point.
    // Handles validation, optional watched-address mode, deterministic address derivation,
    // initial portfolio hydration, secure seed persistence, and post-import sync kick-off.
    func importWallet() async {
        guard canImportWallet else { return }
        guard !isImportingWallet else { return }

        let trimmedWalletName = importDraft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingWalletID {
            renameWallet(id: editingWalletID, to: trimmedWalletName)
            return
        }

        if importDraft.requiresBackupVerification && !importDraft.isBackupVerificationComplete {
            importError = "Confirm your seed backup words before importing the wallet."
            return
        }

        isImportingWallet = true
        defer { isImportingWallet = false }

        let coins = importDraft.selectedCoins
        let trimmedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: importDraft.seedPhrase)
        let trimmedPrivateKey = WalletCoreDerivation.normalizedPrivateKeyHex(from: importDraft.privateKeyInput)
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let bitcoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinAddressInput)
        let trimmedBitcoinAddress = importDraft.bitcoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBitcoinXPub = importDraft.bitcoinXPubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let bitcoinCashAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinCashAddressInput)
        let typedBitcoinCashAddress = importDraft.bitcoinCashAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let bitcoinSVAddressEntries = importDraft.watchOnlyEntries(from: importDraft.bitcoinSVAddressInput)
        let typedBitcoinSVAddress = importDraft.bitcoinSVAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let litecoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.litecoinAddressInput)
        let typedLitecoinAddress = importDraft.litecoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let dogecoinAddressEntries = importDraft.watchOnlyEntries(from: importDraft.dogecoinAddressInput)
        let typedDogecoinAddress = importDraft.dogecoinAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let ethereumAddressEntries = importDraft.watchOnlyEntries(from: importDraft.ethereumAddressInput)
        let typedEthereumAddress = importDraft.ethereumAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let tronAddressEntries = importDraft.watchOnlyEntries(from: importDraft.tronAddressInput)
        let typedTronAddress = importDraft.tronAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let solanaAddressEntries = importDraft.watchOnlyEntries(from: importDraft.solanaAddressInput)
        let typedSolanaAddress = importDraft.solanaAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let xrpAddressEntries = importDraft.watchOnlyEntries(from: importDraft.xrpAddressInput)
        let typedXRPAddress = importDraft.xrpAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stellarAddressEntries = importDraft.watchOnlyEntries(from: importDraft.stellarAddressInput)
        let typedStellarAddress = importDraft.stellarAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedMoneroAddress = importDraft.moneroAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardanoAddressEntries = importDraft.watchOnlyEntries(from: importDraft.cardanoAddressInput)
        let typedCardanoAddress = importDraft.cardanoAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let suiAddressEntries = importDraft.watchOnlyEntries(from: importDraft.suiAddressInput)
        let typedSuiAddress = importDraft.suiAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let aptosAddressEntries = importDraft.watchOnlyEntries(from: importDraft.aptosAddressInput)
        let typedAptosAddress = importDraft.aptosAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let tonAddressEntries = importDraft.watchOnlyEntries(from: importDraft.tonAddressInput)
        let typedTonAddress = importDraft.tonAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let icpAddressEntries = importDraft.watchOnlyEntries(from: importDraft.icpAddressInput)
        let typedICPAddress = importDraft.icpAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let nearAddressEntries = importDraft.watchOnlyEntries(from: importDraft.nearAddressInput)
        let typedNearAddress = importDraft.nearAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let polkadotAddressEntries = importDraft.watchOnlyEntries(from: importDraft.polkadotAddressInput)
        let typedPolkadotAddress = importDraft.polkadotAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsBitcoinImport = importDraft.wantsBitcoin
        let wantsBitcoinCashImport = importDraft.wantsBitcoinCash
        let wantsBitcoinSVImport = importDraft.wantsBitcoinSV
        let wantsLitecoinImport = importDraft.wantsLitecoin
        let wantsDogecoinImport = importDraft.wantsDogecoin
        let wantsEthereumImport = importDraft.wantsEthereum
        let wantsEthereumClassicImport = importDraft.wantsEthereumClassic
        let wantsArbitrumImport = importDraft.wantsArbitrum
        let wantsOptimismImport = importDraft.wantsOptimism
        let wantsBNBImport = importDraft.wantsBNBChain
        let wantsAvalancheImport = importDraft.wantsAvalanche
        let wantsHyperliquidImport = importDraft.wantsHyperliquid
        let wantsTronImport = importDraft.wantsTron
        let wantsSolanaImport = importDraft.wantsSolana
        let wantsCardanoImport = importDraft.wantsCardano
        let wantsXRPImport = importDraft.wantsXRP
        let wantsStellarImport = importDraft.wantsStellar
        let wantsMoneroImport = importDraft.wantsMonero
        let wantsSuiImport = importDraft.wantsSui
        let wantsAptosImport = importDraft.wantsAptos
        let wantsTONImport = importDraft.wantsTON
        let wantsICPImport = importDraft.wantsICP
        let wantsNearImport = importDraft.wantsNear
        let wantsPolkadotImport = importDraft.wantsPolkadot
        let selectedDerivationPreset = importDraft.seedDerivationPreset
        let selectedDerivationPaths: SeedDerivationPaths = {
            var paths = importDraft.seedDerivationPaths
            paths.isCustomEnabled = true
            return paths
        }()
        let isWatchOnlyImport = importDraft.isWatchOnlyMode
        let isPrivateKeyImport = importDraft.isPrivateKeyImportMode
        let selectedChainNames = importDraft.selectedChainNames
        let defaultWalletNameStartIndex = nextDefaultWalletNameIndex()
        var importedWalletsForRefresh: [ImportedWallet] = []
        guard let primarySelectedChainName = selectedChainNames.first else {
            importError = "Select a chain first."
            return
        }
        let requiresSeedPhrase = (wantsBitcoinImport || wantsBitcoinCashImport || wantsBitcoinSVImport || wantsLitecoinImport || wantsDogecoinImport || wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport || wantsTronImport || wantsSolanaImport || wantsCardanoImport || wantsXRPImport || wantsStellarImport || wantsMoneroImport || wantsSuiImport || wantsAptosImport || wantsTONImport || wantsICPImport || wantsNearImport || wantsPolkadotImport) && !isWatchOnlyImport && !isPrivateKeyImport
        let resolvedBitcoinAddress: String? = wantsBitcoinImport
            ? (trimmedBitcoinAddress.isEmpty ? nil : trimmedBitcoinAddress)
            : nil
        let resolvedBitcoinXPub: String? = wantsBitcoinImport
            ? (trimmedBitcoinXPub.isEmpty ? nil : trimmedBitcoinXPub)
            : nil
        let resolvedBitcoinCashAddress: String? = wantsBitcoinCashImport
            ? (typedBitcoinCashAddress.isEmpty ? nil : typedBitcoinCashAddress)
            : nil
        let resolvedBitcoinSVAddress: String? = wantsBitcoinSVImport
            ? (typedBitcoinSVAddress.isEmpty ? nil : typedBitcoinSVAddress)
            : nil
        let resolvedLitecoinAddress: String? = wantsLitecoinImport
            ? (typedLitecoinAddress.isEmpty ? nil : typedLitecoinAddress)
            : nil
        let resolvedTronAddress: String? = wantsTronImport
            ? (typedTronAddress.isEmpty ? nil : typedTronAddress)
            : nil
        let resolvedSolanaAddress: String? = wantsSolanaImport
            ? (typedSolanaAddress.isEmpty ? nil : typedSolanaAddress)
            : nil
        let resolvedXRPAddress: String? = wantsXRPImport
            ? (typedXRPAddress.isEmpty ? nil : typedXRPAddress)
            : nil
        let resolvedStellarAddress: String? = wantsStellarImport
            ? (typedStellarAddress.isEmpty ? nil : typedStellarAddress)
            : nil
        let resolvedMoneroAddress: String? = wantsMoneroImport
            ? (typedMoneroAddress.isEmpty ? nil : typedMoneroAddress)
            : nil
        let resolvedCardanoAddress: String? = wantsCardanoImport
            ? (typedCardanoAddress.isEmpty ? nil : typedCardanoAddress)
            : nil
        let resolvedSuiAddress: String? = wantsSuiImport
            ? (typedSuiAddress.isEmpty ? nil : typedSuiAddress)
            : nil
        let resolvedAptosAddress: String? = wantsAptosImport
            ? (typedAptosAddress.isEmpty ? nil : typedAptosAddress)
            : nil
        let resolvedTONAddress: String? = wantsTONImport
            ? (typedTonAddress.isEmpty ? nil : typedTonAddress)
            : nil
        let resolvedICPAddress: String? = wantsICPImport
            ? (typedICPAddress.isEmpty ? nil : typedICPAddress)
            : nil
        let resolvedNearAddress: String? = wantsNearImport
            ? (typedNearAddress.isEmpty ? nil : typedNearAddress)
            : nil
        let resolvedPolkadotAddress: String? = wantsPolkadotImport
            ? (typedPolkadotAddress.isEmpty ? nil : typedPolkadotAddress)
            : nil

        if isPrivateKeyImport {
            guard WalletCoreDerivation.isLikelyPrivateKeyHex(trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex private key."
                return
            }
            let unsupportedPrivateKeyChains = selectedChainNames.filter {
                !["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot"].contains($0)
            }
            guard unsupportedPrivateKeyChains.isEmpty else {
                importError = "Private key import currently supports every chain in this build except Monero."
                return
            }
            let derivedAddress = derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
            guard derivedAddress.bitcoin != nil || derivedAddress.bitcoinCash != nil || derivedAddress.bitcoinSV != nil || derivedAddress.litecoin != nil || derivedAddress.dogecoin != nil || derivedAddress.evm != nil || derivedAddress.tron != nil || derivedAddress.solana != nil || derivedAddress.xrp != nil || derivedAddress.stellar != nil || derivedAddress.cardano != nil || derivedAddress.sui != nil || derivedAddress.aptos != nil || derivedAddress.ton != nil || derivedAddress.icp != nil || derivedAddress.near != nil || derivedAddress.polkadot != nil else {
                importError = "Unable to derive an address from this private key."
                return
            }
        }

        if isWatchOnlyImport && wantsBitcoinImport {
            let hasValidAddress = !bitcoinAddressEntries.isEmpty
                && bitcoinAddressEntries.allSatisfy { AddressValidation.isValidBitcoinAddress($0, networkMode: self.bitcoinNetworkMode) }
            let hasValidXPub = resolvedBitcoinXPub.map(BitcoinWalletEngine.isLikelyExtendedPublicKey) ?? false
            if !hasValidAddress && !hasValidXPub {
                importError = "Enter one valid Bitcoin address per line or a valid xpub/zpub for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsBitcoinCashImport {
            if bitcoinCashAddressEntries.isEmpty || !bitcoinCashAddressEntries.allSatisfy(AddressValidation.isValidBitcoinCashAddress) {
                importError = "Enter one valid Bitcoin Cash address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsBitcoinSVImport {
            if bitcoinSVAddressEntries.isEmpty || !bitcoinSVAddressEntries.allSatisfy(AddressValidation.isValidBitcoinSVAddress) {
                importError = "Enter one valid Bitcoin SV address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsLitecoinImport {
            if litecoinAddressEntries.isEmpty || !litecoinAddressEntries.allSatisfy(AddressValidation.isValidLitecoinAddress) {
                importError = "Enter one valid Litecoin address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsTronImport {
            if tronAddressEntries.isEmpty || !tronAddressEntries.allSatisfy(AddressValidation.isValidTronAddress) {
                importError = "Enter one valid Tron address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsSolanaImport {
            if solanaAddressEntries.isEmpty || !solanaAddressEntries.allSatisfy(AddressValidation.isValidSolanaAddress) {
                importError = "Enter one valid Solana address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsXRPImport {
            if xrpAddressEntries.isEmpty || !xrpAddressEntries.allSatisfy(AddressValidation.isValidXRPAddress) {
                importError = "Enter one valid XRP address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsStellarImport {
            if stellarAddressEntries.isEmpty || !stellarAddressEntries.allSatisfy(AddressValidation.isValidStellarAddress) {
                importError = "Enter one valid Stellar address per line for watched addresses."
                return
            }
        }
        if wantsMoneroImport {
            if (resolvedMoneroAddress?.isEmpty ?? true) || !AddressValidation.isValidMoneroAddress(resolvedMoneroAddress ?? "") {
                importError = localizedStoreString("Enter a valid Monero address.")
                return
            }
            if isWatchOnlyImport {
                importError = "Monero watched addresses are not supported in this build."
                return
            }
        }
        if isWatchOnlyImport && wantsCardanoImport {
            if cardanoAddressEntries.isEmpty || !cardanoAddressEntries.allSatisfy(AddressValidation.isValidCardanoAddress) {
                importError = "Enter one valid Cardano address per line for watched addresses."
                return
            }
        }
        if wantsCardanoImport && !isWatchOnlyImport {
            if let resolvedCardanoAddress, !resolvedCardanoAddress.isEmpty, !AddressValidation.isValidCardanoAddress(resolvedCardanoAddress) {
                importError = localizedStoreString("Enter a valid Cardano address.")
                return
            }
        }
        if isWatchOnlyImport && wantsSuiImport {
            if suiAddressEntries.isEmpty || !suiAddressEntries.allSatisfy(AddressValidation.isValidSuiAddress) {
                importError = "Enter one valid Sui address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsAptosImport {
            if aptosAddressEntries.isEmpty || !aptosAddressEntries.allSatisfy(AddressValidation.isValidAptosAddress) {
                importError = "Enter one valid Aptos address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsTONImport {
            if tonAddressEntries.isEmpty || !tonAddressEntries.allSatisfy(AddressValidation.isValidTONAddress) {
                importError = "Enter one valid TON address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsICPImport {
            if icpAddressEntries.isEmpty || !icpAddressEntries.allSatisfy(AddressValidation.isValidICPAddress) {
                importError = "Enter one valid Internet Computer account identifier per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsNearImport {
            if nearAddressEntries.isEmpty || !nearAddressEntries.allSatisfy(AddressValidation.isValidNearAddress) {
                importError = "Enter one valid NEAR address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsPolkadotImport {
            if polkadotAddressEntries.isEmpty || !polkadotAddressEntries.allSatisfy(AddressValidation.isValidPolkadotAddress) {
                importError = "Enter one valid Polkadot address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && wantsDogecoinImport {
            if dogecoinAddressEntries.isEmpty || !dogecoinAddressEntries.allSatisfy({ isValidDogecoinAddressForPolicy($0) }) {
                importError = "Enter one valid Dogecoin address per line for watched addresses."
                return
            }
        }
        if isWatchOnlyImport && (wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport) {
            if ethereumAddressEntries.isEmpty || !ethereumAddressEntries.allSatisfy(AddressValidation.isValidEthereumAddress) {
                importError = "Enter one valid EVM address per line for watched addresses."
                return
            }
        }
        if editingWalletID == nil {
            let bitcoinCashAddress: String?
            let bitcoinSVAddress: String?
            let litecoinAddress: String?
            let dogecoinAddress: String?
            let ethereumAddress: String?
            let ethereumClassicAddress: String?
            let tronAddress: String?
            let solanaAddress: String?
            let xrpAddress: String?
            let stellarAddress: String?
            let moneroAddress: String?
            let cardanoAddress: String?
            let suiAddress: String?
            let aptosAddress: String?
            let tonAddress: String?
            let icpAddress: String?
            let nearAddress: String?
            let polkadotAddress: String?
            let derivedBitcoinAddress: String?
            let createdWalletIDs = selectedChainNames.map { _ in UUID() }
            let bitcoinWalletID = zip(selectedChainNames, createdWalletIDs)
                .first(where: { $0.0 == "Bitcoin" })?
                .1
            if requiresSeedPhrase {
                async let derivedBitcoinCashAddressTask: String? = wantsBitcoinCashImport ? deriveBitcoinCashAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.bitcoinCash) : nil
                async let derivedBitcoinSVAddressTask: String? = wantsBitcoinSVImport ? deriveBitcoinSVAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.bitcoinSV) : nil
                async let derivedLitecoinAddressTask: String? = wantsLitecoinImport ? deriveLitecoinAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.litecoin) : nil
                async let derivedDogecoinAddressTask: String? = wantsDogecoinImport ? deriveDogecoinAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.dogecoin) : nil
                async let derivedEthereumAddressTask: String? = (wantsEthereumImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport) ? deriveEthereumAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.ethereum) : nil
                async let derivedEthereumClassicAddressTask: String? = wantsEthereumClassicImport ? deriveEthereumAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.ethereumClassic) : nil
                async let derivedTronAddressTask: String? = wantsTronImport ? deriveTronAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.tron) : nil
                async let derivedSolanaAddressTask: String? = wantsSolanaImport
                    ? deriveSolanaAddressInBackground(
                        seedPhrase: trimmedSeedPhrase,
                        derivationPath: selectedDerivationPaths.solana
                    )
                    : nil
                async let derivedCardanoAddressTask: String? = wantsCardanoImport ? deriveCardanoAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.cardano) : nil
                async let derivedXRPAddressTask: String? = wantsXRPImport ? deriveXRPAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.xrp) : nil
                async let derivedStellarAddressTask: String? = wantsStellarImport ? deriveStellarAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.stellar) : nil
                async let derivedSuiAddressTask: String? = wantsSuiImport ? deriveSuiAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.sui) : nil
                async let derivedAptosAddressTask: String? = wantsAptosImport ? deriveAptosAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.aptos) : nil
                async let derivedTONAddressTask: String? = wantsTONImport ? deriveTONAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.ton) : nil
                async let derivedICPAddressTask: String? = wantsICPImport ? deriveICPAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.internetComputer) : nil
                async let derivedNearAddressTask: String? = wantsNearImport ? deriveNearAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.near) : nil
                async let derivedPolkadotAddressTask: String? = wantsPolkadotImport ? derivePolkadotAddressInBackground(seedPhrase: trimmedSeedPhrase, derivationPath: selectedDerivationPaths.polkadot) : nil

                do {
                    if wantsBitcoinImport {
                        guard let bitcoinWalletID else {
                            importError = "Bitcoin wallet initialization failed."
                            return
                        }
                        derivedBitcoinAddress = try BitcoinWalletEngine.derivedAddress(
                            for: bitcoinWalletID,
                            seedPhrase: trimmedSeedPhrase,
                            derivationPath: selectedDerivationPaths.bitcoin
                        )
                    } else {
                        derivedBitcoinAddress = nil
                    }
                    bitcoinCashAddress = try await derivedBitcoinCashAddressTask
                    bitcoinSVAddress = try await derivedBitcoinSVAddressTask
                    litecoinAddress = try await derivedLitecoinAddressTask
                    dogecoinAddress = try await derivedDogecoinAddressTask
                    ethereumAddress = try await derivedEthereumAddressTask
                    ethereumClassicAddress = try await derivedEthereumClassicAddressTask
                    tronAddress = try await derivedTronAddressTask
                    solanaAddress = try await derivedSolanaAddressTask
                    cardanoAddress = try await derivedCardanoAddressTask
                    xrpAddress = try await derivedXRPAddressTask
                    stellarAddress = try await derivedStellarAddressTask
                    suiAddress = try await derivedSuiAddressTask
                    aptosAddress = try await derivedAptosAddressTask
                    tonAddress = try await derivedTONAddressTask
                    icpAddress = try await derivedICPAddressTask
                    nearAddress = try await derivedNearAddressTask
                    polkadotAddress = try await derivedPolkadotAddressTask
                    moneroAddress = resolvedMoneroAddress
                } catch {
                    let resolvedMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    if resolvedMessage.isEmpty || resolvedMessage == "(null)" {
                        importError = "Wallet initialization failed. Check the seed phrase."
                    } else {
                        importError = resolvedMessage
                    }
                    return
                }
            } else {
                let derivedPrivateKeyAddress = isPrivateKeyImport
                    ? derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
                    : PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
                derivedBitcoinAddress = derivedPrivateKeyAddress.bitcoin
                bitcoinCashAddress = derivedPrivateKeyAddress.bitcoinCash ?? (AddressValidation.isValidBitcoinCashAddress(typedBitcoinCashAddress) ? typedBitcoinCashAddress : nil)
                bitcoinSVAddress = derivedPrivateKeyAddress.bitcoinSV ?? (AddressValidation.isValidBitcoinSVAddress(typedBitcoinSVAddress) ? typedBitcoinSVAddress : nil)
                litecoinAddress = derivedPrivateKeyAddress.litecoin ?? (AddressValidation.isValidLitecoinAddress(typedLitecoinAddress) ? typedLitecoinAddress : nil)
                dogecoinAddress = derivedPrivateKeyAddress.dogecoin ?? (isValidDogecoinAddressForPolicy(typedDogecoinAddress) ? typedDogecoinAddress : nil)
                ethereumAddress = derivedPrivateKeyAddress.evm ?? (AddressValidation.isValidEthereumAddress(typedEthereumAddress)
                    ? EthereumWalletEngine.normalizeAddress(typedEthereumAddress)
                    : nil)
                ethereumClassicAddress = ethereumAddress
                tronAddress = derivedPrivateKeyAddress.tron ?? (AddressValidation.isValidTronAddress(typedTronAddress)
                    ? typedTronAddress
                    : nil)
                solanaAddress = derivedPrivateKeyAddress.solana ?? (AddressValidation.isValidSolanaAddress(typedSolanaAddress)
                    ? typedSolanaAddress
                    : nil)
                xrpAddress = derivedPrivateKeyAddress.xrp ?? (AddressValidation.isValidXRPAddress(typedXRPAddress)
                    ? typedXRPAddress
                    : nil)
                stellarAddress = derivedPrivateKeyAddress.stellar ?? (AddressValidation.isValidStellarAddress(typedStellarAddress)
                    ? typedStellarAddress
                    : nil)
                moneroAddress = AddressValidation.isValidMoneroAddress(typedMoneroAddress)
                    ? typedMoneroAddress
                    : nil
                cardanoAddress = derivedPrivateKeyAddress.cardano ?? (AddressValidation.isValidCardanoAddress(typedCardanoAddress)
                    ? typedCardanoAddress
                    : nil)
                suiAddress = derivedPrivateKeyAddress.sui ?? (AddressValidation.isValidSuiAddress(typedSuiAddress)
                    ? typedSuiAddress.lowercased()
                    : nil)
                aptosAddress = derivedPrivateKeyAddress.aptos ?? (AddressValidation.isValidAptosAddress(typedAptosAddress)
                    ? normalizedAddress(typedAptosAddress, for: "Aptos")
                    : nil)
                tonAddress = derivedPrivateKeyAddress.ton ?? (AddressValidation.isValidTONAddress(typedTonAddress)
                    ? normalizedAddress(typedTonAddress, for: "TON")
                    : nil)
                icpAddress = derivedPrivateKeyAddress.icp ?? (AddressValidation.isValidICPAddress(typedICPAddress)
                    ? normalizedAddress(typedICPAddress, for: "Internet Computer")
                    : nil)
                nearAddress = derivedPrivateKeyAddress.near ?? (AddressValidation.isValidNearAddress(typedNearAddress)
                    ? typedNearAddress.lowercased()
                    : nil)
                polkadotAddress = derivedPrivateKeyAddress.polkadot ?? (AddressValidation.isValidPolkadotAddress(typedPolkadotAddress)
                    ? typedPolkadotAddress
                    : nil)
            }
            let createdWallets: [ImportedWallet]
            if isWatchOnlyImport {
                typealias WatchOnlyWalletRequest = (
                    chainName: String,
                    bitcoinAddress: String?,
                    bitcoinXPub: String?,
                    bitcoinCashAddress: String?,
                    bitcoinSVAddress: String?,
                    litecoinAddress: String?,
                    dogecoinAddress: String?,
                    ethereumAddress: String?,
                    tronAddress: String?,
                    solanaAddress: String?,
                    xrpAddress: String?,
                    stellarAddress: String?,
                    moneroAddress: String?,
                    cardanoAddress: String?,
                    suiAddress: String?,
                    aptosAddress: String?,
                    tonAddress: String?,
                    icpAddress: String?,
                    nearAddress: String?,
                    polkadotAddress: String?
                )

                let watchOnlyRequests: [WatchOnlyWalletRequest] = {
                    switch primarySelectedChainName {
                    case "Bitcoin":
                        if let resolvedBitcoinXPub, !resolvedBitcoinXPub.isEmpty {
                            return [(
                                chainName: "Bitcoin",
                                bitcoinAddress: nil,
                                bitcoinXPub: resolvedBitcoinXPub,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )]
                        }
                        return bitcoinAddressEntries.map { address in
                            (
                                chainName: "Bitcoin",
                                bitcoinAddress: address,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Bitcoin Cash":
                        return bitcoinCashAddressEntries.map { address in
                            (
                                chainName: "Bitcoin Cash",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: address,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Bitcoin SV":
                        return bitcoinSVAddressEntries.map { address in
                            (
                                chainName: "Bitcoin SV",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: address,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Litecoin":
                        return litecoinAddressEntries.map { address in
                            (
                                chainName: "Litecoin",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: address,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Dogecoin":
                        return dogecoinAddressEntries.map { address in
                            (
                                chainName: "Dogecoin",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: address,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
                        return ethereumAddressEntries.map { address in
                            (
                                chainName: primarySelectedChainName,
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: EthereumWalletEngine.normalizeAddress(address),
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Tron":
                        return tronAddressEntries.map { address in
                            (
                                chainName: "Tron",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: address,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Solana":
                        return solanaAddressEntries.map { address in
                            (
                                chainName: "Solana",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: address,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "XRP Ledger":
                        return xrpAddressEntries.map { address in
                            (
                                chainName: "XRP Ledger",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: address,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Stellar":
                        return stellarAddressEntries.map { address in
                            (
                                chainName: "Stellar",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: address,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Cardano":
                        return cardanoAddressEntries.map { address in
                            (
                                chainName: "Cardano",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: address,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Sui":
                        return suiAddressEntries.map { address in
                            (
                                chainName: "Sui",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: address.lowercased(),
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Aptos":
                        return aptosAddressEntries.map { address in
                            (
                                chainName: "Aptos",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: normalizedAddress(address, for: "Aptos"),
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "TON":
                        return tonAddressEntries.map { address in
                            (
                                chainName: "TON",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: normalizedAddress(address, for: "TON"),
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "Internet Computer":
                        return icpAddressEntries.map { address in
                            (
                                chainName: "Internet Computer",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: normalizedAddress(address, for: "Internet Computer"),
                                nearAddress: nil,
                                polkadotAddress: nil
                            )
                        }
                    case "NEAR":
                        return nearAddressEntries.map { address in
                            (
                                chainName: "NEAR",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: address.lowercased(),
                                polkadotAddress: nil
                            )
                        }
                    case "Polkadot":
                        return polkadotAddressEntries.map { address in
                            (
                                chainName: "Polkadot",
                                bitcoinAddress: nil,
                                bitcoinXPub: nil,
                                bitcoinCashAddress: nil,
                                bitcoinSVAddress: nil,
                                litecoinAddress: nil,
                                dogecoinAddress: nil,
                                ethereumAddress: nil,
                                tronAddress: nil,
                                solanaAddress: nil,
                                xrpAddress: nil,
                                stellarAddress: nil,
                                moneroAddress: nil,
                                cardanoAddress: nil,
                                suiAddress: nil,
                                aptosAddress: nil,
                                tonAddress: nil,
                                icpAddress: nil,
                                nearAddress: nil,
                                polkadotAddress: address
                            )
                        }
                    default:
                        return []
                    }
                }()

                guard !watchOnlyRequests.isEmpty else {
                    importError = "Enter at least one valid address to import."
                    return
                }

                let watchOnlyWalletIDs = watchOnlyRequests.map { _ in UUID() }
                createdWallets = watchOnlyRequests.enumerated().map { offset, request in
                    walletForSingleChain(
                        id: watchOnlyWalletIDs[offset],
                        name: walletDisplayName(
                            baseName: trimmedWalletName,
                            batchPosition: offset + 1,
                            defaultWalletIndex: defaultWalletNameStartIndex + offset,
                            selectedChainCount: watchOnlyRequests.count
                        ),
                        chainName: request.chainName,
                        bitcoinAddress: request.bitcoinAddress,
                        bitcoinXPub: request.bitcoinXPub,
                        bitcoinCashAddress: request.bitcoinCashAddress,
                        bitcoinSVAddress: request.bitcoinSVAddress,
                        litecoinAddress: request.litecoinAddress,
                        dogecoinAddress: request.dogecoinAddress,
                        ethereumAddress: request.ethereumAddress,
                        tronAddress: request.tronAddress,
                        solanaAddress: request.solanaAddress,
                        xrpAddress: request.xrpAddress,
                        stellarAddress: request.stellarAddress,
                        moneroAddress: request.moneroAddress,
                        cardanoAddress: request.cardanoAddress,
                        suiAddress: request.suiAddress,
                        aptosAddress: request.aptosAddress,
                        tonAddress: request.tonAddress,
                        icpAddress: request.icpAddress,
                        nearAddress: request.nearAddress,
                        polkadotAddress: request.polkadotAddress,
                        seedDerivationPreset: selectedDerivationPreset,
                        seedDerivationPaths: selectedDerivationPaths,
                        holdings: coins
                    )
                }
            } else {
                createdWallets = selectedChainNames.enumerated().map { offset, chainName in
                    walletForSingleChain(
                        id: createdWalletIDs[offset],
                        name: walletDisplayName(
                            baseName: trimmedWalletName,
                            batchPosition: offset + 1,
                            defaultWalletIndex: defaultWalletNameStartIndex + offset,
                            selectedChainCount: selectedChainNames.count
                        ),
                        chainName: chainName,
                        bitcoinAddress: resolvedBitcoinAddress ?? derivedBitcoinAddress,
                        bitcoinXPub: resolvedBitcoinXPub,
                        bitcoinCashAddress: resolvedBitcoinCashAddress ?? bitcoinCashAddress,
                        bitcoinSVAddress: resolvedBitcoinSVAddress ?? bitcoinSVAddress,
                        litecoinAddress: resolvedLitecoinAddress ?? litecoinAddress,
                        dogecoinAddress: dogecoinAddress,
                        ethereumAddress: chainName == "Ethereum Classic" ? ethereumClassicAddress : ethereumAddress,
                        tronAddress: resolvedTronAddress ?? tronAddress,
                        solanaAddress: resolvedSolanaAddress ?? solanaAddress,
                        xrpAddress: resolvedXRPAddress ?? xrpAddress,
                        stellarAddress: resolvedStellarAddress ?? stellarAddress,
                        moneroAddress: resolvedMoneroAddress ?? moneroAddress,
                        cardanoAddress: resolvedCardanoAddress ?? cardanoAddress,
                        suiAddress: resolvedSuiAddress ?? suiAddress,
                        aptosAddress: resolvedAptosAddress ?? aptosAddress,
                        tonAddress: resolvedTONAddress ?? tonAddress,
                        icpAddress: resolvedICPAddress ?? icpAddress,
                        nearAddress: resolvedNearAddress ?? nearAddress,
                        polkadotAddress: resolvedPolkadotAddress ?? polkadotAddress,
                        seedDerivationPreset: selectedDerivationPreset,
                        seedDerivationPaths: selectedDerivationPaths,
                        holdings: coins
                    )
                }
            }

            for wallet in createdWallets {
                let account = Self.seedPhraseAccount(for: wallet.id)
                let passwordAccount = Self.seedPhrasePasswordAccount(for: wallet.id)
                let privateKeyAccount = Self.privateKeyAccount(for: wallet.id)
                if requiresSeedPhrase {
                    try? SecureSeedStore.save(trimmedSeedPhrase, for: account)
                    if let trimmedWalletPassword {
                        try? SecureSeedPasswordStore.save(trimmedWalletPassword, for: passwordAccount)
                    } else {
                        try? SecureSeedPasswordStore.deleteValue(for: passwordAccount)
                    }
                    SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
                } else if isPrivateKeyImport {
                    try? SecureSeedStore.deleteValue(for: account)
                    try? SecureSeedPasswordStore.deleteValue(for: passwordAccount)
                    SecurePrivateKeyStore.save(trimmedPrivateKey, for: privateKeyAccount)
                } else {
                    try? SecureSeedStore.deleteValue(for: account)
                    try? SecureSeedPasswordStore.deleteValue(for: passwordAccount)
                    SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
                }
            }
            wallets.append(contentsOf: createdWallets)
            importedWalletsForRefresh = createdWallets
        }

        finishWalletImportFlow()

        withAnimation {
        }

        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }

    private func renameWallet(id: UUID, to newName: String) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        let wallet = wallets[index]
        wallets[index] = ImportedWallet(
            id: wallet.id,
            name: newName,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSVAddress: wallet.bitcoinSVAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            aptosAddress: wallet.aptosAddress,
            tonAddress: wallet.tonAddress,
            icpAddress: wallet.icpAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: wallet.holdings,
            includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
        finishWalletImportFlow()
    }

    private func finishWalletImportFlow() {
        importError = nil
        importDraft.clearSensitiveInputs()
        resetImportForm()
        editingWalletID = nil
        isShowingWalletImporter = false
    }

    private enum WalletImportSyncError: Error {
        case bitcoin
        case bitcoinCash
        case bitcoinSV
        case litecoin
        case dogecoin
        case ethereum
        case ethereumClassic
        case bnb
        case tron
        case solana
        case cardano
        case xrp
        case stellar
        case monero
        case sui
        case near
        case polkadot
    }

    private struct PrivateKeyImportAddressResolution {
        let bitcoin: String?
        let bitcoinCash: String?
        let bitcoinSV: String?
        let litecoin: String?
        let dogecoin: String?
        let evm: String?
        let tron: String?
        let solana: String?
        let xrp: String?
        let stellar: String?
        let cardano: String?
        let sui: String?
        let aptos: String?
        let ton: String?
        let icp: String?
        let near: String?
        let polkadot: String?
    }

    private func deriveEthereumAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let address = try EthereumWalletEngine.derivedAddress(
                        for: seedPhrase,
                        account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0,
                        derivationPath: derivationPath
                    )
                    continuation.resume(returning: address)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deriveBitcoinSVAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let address = try BitcoinSVWalletEngine.derivedAddress(
                        for: seedPhrase,
                        derivationPath: derivationPath
                    )
                    continuation.resume(returning: address)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func derivePrivateKeyImportAddress(
        privateKeyHex: String,
        chainName: String?
    ) -> PrivateKeyImportAddressResolution {
        guard let chainName else {
            return PrivateKeyImportAddressResolution(
                bitcoin: nil,
                bitcoinCash: nil,
                bitcoinSV: nil,
                litecoin: nil,
                dogecoin: nil,
                evm: nil,
                tron: nil,
                solana: nil,
                xrp: nil,
                stellar: nil,
                cardano: nil,
                sui: nil,
                aptos: nil,
                ton: nil,
                icp: nil,
                near: nil,
                polkadot: nil
            )
        }

        switch chainName {
        case "Bitcoin":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .bitcoin).address
            return PrivateKeyImportAddressResolution(bitcoin: address, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Bitcoin Cash":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .bitcoinCash).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: address, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Bitcoin SV":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .bitcoinSV).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: address, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Litecoin":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .litecoin).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: address, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Dogecoin":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .dogecoin).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: address, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            let address = try? EthereumWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: address, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Tron":
            let address = try? TronWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: address, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Solana":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .solana).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: address, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "XRP Ledger":
            let address = try? XRPWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: address, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Stellar":
            let address = try? StellarWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: address, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Cardano":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .cardano).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: address, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Sui":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .sui).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: address?.lowercased(), aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        case "Aptos":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .aptos).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: address?.lowercased(), ton: nil, icp: nil, near: nil, polkadot: nil)
        case "TON":
            let address = try? TONWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: address, icp: nil, near: nil, polkadot: nil)
        case "Internet Computer":
            let address = try? ICPWalletEngine.derivedAddress(forPrivateKey: privateKeyHex)
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: address?.lowercased(), near: nil, polkadot: nil)
        case "NEAR":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .near).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: address?.lowercased(), polkadot: nil)
        case "Polkadot":
            let address = try? WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .polkadot).address
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: address)
        default:
            return PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
        }
    }

    static func deriveTronAddress(seedPhrase: String, wallet: ImportedWallet) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .tron,
            account: DerivationPathParser.segmentValue(at: 2, in: wallet.seedDerivationPaths.tron) ?? 0
        )
        return material.address
    }

    private func deriveTronAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .tron,
            account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0
        )
        return material.address
    }

    private func deriveSolanaAddressInBackground(
        seedPhrase: String,
        derivationPath: String
    ) async throws -> String {
        try SolanaWalletEngine.derivedAddress(
            for: seedPhrase,
            preference: (DerivationPathParser.parse(derivationPath)?.count == 3) ? .legacy : .standard,
            account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0
        )
    }

    private func deriveXRPAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try XRPWalletEngine.derivedAddress(for: seedPhrase, account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
    }

    private func deriveStellarAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try StellarWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func deriveSuiAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try SuiWalletEngine.derivedAddress(for: seedPhrase, account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
    }

    private func deriveAptosAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try AptosWalletEngine.derivedAddress(for: seedPhrase, account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
    }

    private func deriveTONAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try TONWalletEngine.derivedAddress(for: seedPhrase, account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
    }

    private func deriveICPAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try ICPWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func deriveCardanoAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try CardanoWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func deriveNearAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try NearWalletEngine.derivedAddress(for: seedPhrase, account: DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
    }

    private func derivePolkadotAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try PolkadotWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func deriveDogecoinAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try DogecoinWalletEngine.derivedAddress(
            for: seedPhrase,
            networkMode: dogecoinNetworkMode,
            account: Int(DerivationPathParser.segmentValue(at: 2, in: derivationPath) ?? 0)
        )
    }

    private func deriveLitecoinAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try LitecoinWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func deriveBitcoinCashAddressInBackground(seedPhrase: String, derivationPath: String) async throws -> String {
        try BitcoinCashWalletEngine.derivedAddress(for: seedPhrase, derivationPath: derivationPath)
    }

    private func walletDisplayName(
        baseName: String,
        batchPosition: Int,
        defaultWalletIndex: Int,
        selectedChainCount: Int
    ) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Wallet \(defaultWalletIndex)"
        }
        return selectedChainCount > 1 ? "\(trimmed) \(batchPosition)" : trimmed
    }

    private func nextDefaultWalletNameIndex() -> Int {
        let highestUsedIndex = wallets.reduce(into: 0) { currentHighest, wallet in
            guard wallet.name.hasPrefix("Wallet ") else { return }
            let suffix = wallet.name.dropFirst("Wallet ".count)
            guard let value = Int(suffix) else { return }
            currentHighest = max(currentHighest, value)
        }
        return highestUsedIndex + 1
    }

    private func walletForSingleChain(
        id: UUID,
        name: String,
        chainName: String,
        bitcoinAddress: String?,
        bitcoinXPub: String?,
        bitcoinCashAddress: String?,
        bitcoinSVAddress: String?,
        litecoinAddress: String?,
        dogecoinAddress: String?,
        ethereumAddress: String?,
        tronAddress: String?,
        solanaAddress: String?,
        xrpAddress: String?,
        stellarAddress: String?,
        moneroAddress: String?,
        cardanoAddress: String?,
        suiAddress: String?,
        aptosAddress: String?,
        tonAddress: String?,
        icpAddress: String?,
        nearAddress: String?,
        polkadotAddress: String?,
        seedDerivationPreset: SeedDerivationPreset,
        seedDerivationPaths: SeedDerivationPaths,
        holdings: [Coin]
    ) -> ImportedWallet {
        ImportedWallet(
            id: id,
            name: name,
            bitcoinNetworkMode: chainName == "Bitcoin" ? bitcoinNetworkMode : .mainnet,
            dogecoinNetworkMode: chainName == "Dogecoin" ? dogecoinNetworkMode : .mainnet,
            bitcoinAddress: chainName == "Bitcoin" ? bitcoinAddress : nil,
            bitcoinXPub: chainName == "Bitcoin" ? bitcoinXPub : nil,
            bitcoinCashAddress: chainName == "Bitcoin Cash" ? bitcoinCashAddress : nil,
            bitcoinSVAddress: chainName == "Bitcoin SV" ? bitcoinSVAddress : nil,
            litecoinAddress: chainName == "Litecoin" ? litecoinAddress : nil,
            dogecoinAddress: chainName == "Dogecoin" ? dogecoinAddress : nil,
            ethereumAddress: (chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid") ? ethereumAddress : nil,
            tronAddress: chainName == "Tron" ? tronAddress : nil,
            solanaAddress: chainName == "Solana" ? solanaAddress : nil,
            stellarAddress: chainName == "Stellar" ? stellarAddress : nil,
            xrpAddress: chainName == "XRP Ledger" ? xrpAddress : nil,
            moneroAddress: chainName == "Monero" ? moneroAddress : nil,
            cardanoAddress: chainName == "Cardano" ? cardanoAddress : nil,
            suiAddress: chainName == "Sui" ? suiAddress : nil,
            aptosAddress: chainName == "Aptos" ? aptosAddress : nil,
            tonAddress: chainName == "TON" ? tonAddress : nil,
            icpAddress: chainName == "Internet Computer" ? icpAddress : nil,
            nearAddress: chainName == "NEAR" ? nearAddress : nil,
            polkadotAddress: chainName == "Polkadot" ? polkadotAddress : nil,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths,
            selectedChain: chainName,
            holdings: holdings.filter { $0.chainName == chainName }
        )
    }

    // Initial post-import hydration pass to populate assets before regular maintenance cadence.
    private func hydrateImportedWalletBalances(
        wallet: ImportedWallet,
        seedPhrase: String,
        wantsBitcoinImport: Bool,
        wantsBitcoinCashImport: Bool,
        wantsBitcoinSVImport: Bool,
        wantsLitecoinImport: Bool,
        wantsDogecoinImport: Bool,
        wantsEthereumImport: Bool,
        wantsEthereumClassicImport: Bool,
        wantsBNBImport: Bool,
        wantsTronImport: Bool,
        wantsSolanaImport: Bool,
        wantsCardanoImport: Bool,
        wantsXRPImport: Bool,
        wantsStellarImport: Bool,
        wantsMoneroImport: Bool,
        wantsNearImport: Bool,
        wantsPolkadotImport: Bool
    ) async throws -> ImportedWallet {
        async let bitcoinBalanceTask: Double? = fetchBitcoinImportBalanceIfNeeded(
            wantsBitcoinImport,
            wallet: wallet,
            seedPhrase: seedPhrase
        )
        async let bitcoinCashBalanceTask: Double? = fetchBitcoinCashImportBalanceIfNeeded(
            wantsBitcoinCashImport,
            address: wallet.bitcoinCashAddress
        )
        async let bitcoinSVBalanceTask: Double? = fetchBitcoinSVImportBalanceIfNeeded(
            wantsBitcoinSVImport,
            address: wallet.bitcoinSVAddress
        )
        async let litecoinBalanceTask: Double? = fetchLitecoinImportBalanceIfNeeded(
            wantsLitecoinImport,
            address: wallet.litecoinAddress
        )
        async let dogecoinBalanceTask: Double? = fetchDogecoinImportBalanceIfNeeded(
            wantsDogecoinImport,
            address: wallet.dogecoinAddress
        )
        async let ethereumPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchEthereumImportPortfolioIfNeeded(
            wantsEthereumImport,
            address: wallet.ethereumAddress
        )
        async let ethereumClassicPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchETCImportBalanceIfNeeded(
            wantsEthereumClassicImport,
            address: wallet.ethereumAddress
        )
        async let bnbPortfolioTask: (Double, [EthereumTokenBalanceSnapshot])? = fetchBNBImportBalanceIfNeeded(
            wantsBNBImport,
            address: wallet.ethereumAddress
        )
        async let tronPortfolioTask: (Double, [TronTokenBalanceSnapshot])? = fetchTronImportBalanceIfNeeded(
            wantsTronImport,
            address: wallet.tronAddress
        )
        async let solanaPortfolioTask: SolanaPortfolioSnapshot? = fetchSolanaImportPortfolioIfNeeded(
            wantsSolanaImport,
            address: wallet.solanaAddress
        )
        async let cardanoBalanceTask: Double? = fetchCardanoImportBalanceIfNeeded(
            wantsCardanoImport,
            address: wallet.cardanoAddress
        )
        async let xrpBalanceTask: Double? = fetchXRPImportBalanceIfNeeded(
            wantsXRPImport,
            address: wallet.xrpAddress
        )
        async let stellarBalanceTask: Double? = fetchStellarImportBalanceIfNeeded(
            wantsStellarImport,
            address: wallet.stellarAddress
        )
        async let moneroBalanceTask: Double? = fetchMoneroImportBalanceIfNeeded(
            wantsMoneroImport,
            address: wallet.moneroAddress
        )
        async let nearBalanceTask: Double? = fetchNearImportBalanceIfNeeded(
            wantsNearImport,
            address: wallet.nearAddress
        )
        async let polkadotBalanceTask: Double? = fetchPolkadotImportBalanceIfNeeded(
            wantsPolkadotImport,
            address: wallet.polkadotAddress
        )

        var updatedHoldings = wallet.holdings

        do {
            if let bitcoinBalance = try await bitcoinBalanceTask {
                updatedHoldings = applyBitcoinBalance(bitcoinBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.bitcoin
        }

        do {
            if let bitcoinCashBalance = try await bitcoinCashBalanceTask {
                updatedHoldings = applyBitcoinCashBalance(bitcoinCashBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.bitcoinCash
        }

        do {
            if let bitcoinSVBalance = try await bitcoinSVBalanceTask {
                updatedHoldings = applyBitcoinSVBalance(bitcoinSVBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.bitcoinSV
        }

        do {
            if let litecoinBalance = try await litecoinBalanceTask {
                updatedHoldings = applyLitecoinBalance(litecoinBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.litecoin
        }

        do {
            if let dogecoinBalance = try await dogecoinBalanceTask {
                updatedHoldings = applyDogecoinBalance(dogecoinBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.dogecoin
        }

        do {
            if let (nativeBalance, tokenBalances) = try await ethereumPortfolioTask {
                updatedHoldings = applyEthereumBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: tokenBalances,
                    to: updatedHoldings
                )
            }
        } catch {
            throw WalletImportSyncError.ethereum
        }

        do {
            if let (nativeBalance, _) = try await ethereumClassicPortfolioTask {
                updatedHoldings = applyETCBalances(
                    nativeBalance: nativeBalance,
                    to: updatedHoldings
                )
            }
        } catch {
            throw WalletImportSyncError.ethereumClassic
        }

        do {
            if let (nativeBalance, tokenBalances) = try await bnbPortfolioTask {
                updatedHoldings = applyBNBBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: tokenBalances,
                    to: updatedHoldings
                )
            }
        } catch {
            throw WalletImportSyncError.bnb
        }

        do {
            if let (nativeBalance, tokenBalances) = try await tronPortfolioTask {
                updatedHoldings = applyTronBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: tokenBalances,
                    to: updatedHoldings
                )
            }
        } catch {
            throw WalletImportSyncError.tron
        }

        do {
            if let solanaPortfolio = try await solanaPortfolioTask {
                updatedHoldings = applySolanaPortfolio(
                    nativeBalance: solanaPortfolio.nativeBalance,
                    tokenBalances: solanaPortfolio.tokenBalances,
                    to: updatedHoldings
                )
            }
        } catch {
            throw WalletImportSyncError.solana
        }

        do {
            if let cardanoBalance = try await cardanoBalanceTask {
                updatedHoldings = applyCardanoBalance(cardanoBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.cardano
        }

        do {
            if let xrpBalance = try await xrpBalanceTask {
                updatedHoldings = applyXRPBalance(xrpBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.xrp
        }

        do {
            if let stellarBalance = try await stellarBalanceTask {
                updatedHoldings = applyStellarBalance(stellarBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.stellar
        }

        do {
            if let moneroBalance = try await moneroBalanceTask {
                updatedHoldings = applyMoneroBalance(moneroBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.monero
        }

        do {
            if let nearBalance = try await nearBalanceTask {
                updatedHoldings = applyNearBalance(nearBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.near
        }

        do {
            if let polkadotBalance = try await polkadotBalanceTask {
                updatedHoldings = applyPolkadotBalance(polkadotBalance, to: updatedHoldings)
            }
        } catch {
            throw WalletImportSyncError.polkadot
        }

        return walletByReplacingHoldings(wallet, with: updatedHoldings)
    }

    private func fetchBitcoinImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        wallet: ImportedWallet,
        seedPhrase: String
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        return try await BitcoinWalletEngine.syncBalanceInBackground(for: wallet, seedPhrase: seedPhrase)
    }

    private func fetchBitcoinCashImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.bitcoinCash
        }
        return try await BitcoinCashBalanceService.fetchBalance(for: address)
    }

    private func fetchBitcoinSVImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.bitcoinSV
        }
        return try await BitcoinSVBalanceService.fetchBalance(for: address)
    }

    func walletByReplacingHoldings(_ wallet: ImportedWallet, with holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id,
            name: wallet.name,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSVAddress: wallet.bitcoinSVAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            aptosAddress: wallet.aptosAddress,
            icpAddress: wallet.icpAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: holdings,
            includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
    }

    private func fetchDogecoinImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.dogecoin
        }
        return try await DogecoinBalanceService.fetchBalance(for: address, networkMode: dogecoinNetworkMode)
    }

    private func fetchLitecoinImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.litecoin
        }
        return try await LitecoinBalanceService.fetchBalance(for: address)
    }

    private func fetchEthereumImportPortfolioIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> (Double, [EthereumTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.ethereum
        }
        return try await fetchEthereumPortfolio(for: address)
    }

    private func fetchETCImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> (Double, [EthereumTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.ethereumClassic
        }
        let portfolio = try await fetchEVMNativePortfolio(for: address, chainName: "Ethereum Classic")
        return (portfolio.nativeBalance, portfolio.tokenBalances)
    }

    private func fetchBNBImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> (Double, [EthereumTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.bnb
        }
        let portfolio = try await fetchEVMNativePortfolio(for: address, chainName: "BNB Chain")
        return (portfolio.nativeBalance, portfolio.tokenBalances)
    }

    private func fetchTronImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> (Double, [TronTokenBalanceSnapshot])? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.tron
        }
        let balances = try await TronBalanceService.fetchBalances(
            for: address,
            trackedTokens: enabledTronTrackedTokens()
        )
        return (balances.trxBalance, balances.tokenBalances)
    }

    private func fetchCardanoImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else { return nil }
        return try await CardanoBalanceService.fetchBalance(for: address)
    }

    private func fetchXRPImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch, let address else { return nil }
        return try await XRPBalanceService.fetchBalance(for: address)
    }

    private func fetchStellarImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.stellar
        }
        return try await StellarBalanceService.fetchBalance(for: address)
    }

    private func fetchMoneroImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.monero
        }
        return try await MoneroBalanceService.fetchBalance(for: address)
    }

    private func fetchNearImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.near
        }
        return try await NearBalanceService.fetchBalance(for: address)
    }

    private func fetchPolkadotImportBalanceIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> Double? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.polkadot
        }
        return try await PolkadotBalanceService.fetchBalance(for: address)
    }

    private func fetchSolanaImportPortfolioIfNeeded(
        _ shouldFetch: Bool,
        address: String?
    ) async throws -> SolanaPortfolioSnapshot? {
        guard shouldFetch else { return nil }
        guard let address, !address.isEmpty else {
            throw WalletImportSyncError.solana
        }
        return try await SolanaBalanceService.fetchPortfolio(
            for: address,
            trackedTokenMetadataByMint: enabledSolanaTrackedTokens()
        )
    }

    var portfolio: [Coin] {
        cachedPortfolio
    }

    var priceRequestCoins: [Coin] {
        var grouped: [String: Coin] = [:]
        var order: [String] = []

        for coin in cachedUniqueWalletPriceRequestCoins where isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            grouped[key] = coin
            order.append(key)
        }

        for coin in dashboardPinnedAssetPricingPrototypes
        where selectedMainTab == .home && isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            guard grouped[key] == nil else { continue }
            grouped[key] = coin
            order.append(key)
        }

        return order.compactMap { grouped[$0] }
    }

    private var hasLivePriceRefreshWork: Bool {
        !priceRequestCoins.isEmpty
    }

    var shouldRunScheduledPriceRefresh: Bool {
        selectedMainTab == .home && hasLivePriceRefreshWork
    }

    var hasPendingTransactionMaintenanceWork: Bool {
        transactions.contains { transaction in
            guard transaction.kind == .send, transaction.transactionHash != nil else {
                return false
            }
            if transaction.status == .pending {
                return true
            }
            return transaction.status == .confirmed
        }
    }

    private var pendingTransactionMaintenanceChains: Set<String> {
        Set(
            transactions.compactMap { transaction -> String? in
                guard transaction.kind == .send, transaction.transactionHash != nil else {
                    return nil
                }
                if transaction.status == .pending {
                    return transaction.chainName
                }
                if transaction.chainName == "Dogecoin", transaction.status == .confirmed {
                    return transaction.chainName
                }
                return nil
            }
        )
    }

    var pendingTransactionMaintenanceChainIDs: Set<WalletChainID> {
        Set(pendingTransactionMaintenanceChains.compactMap(WalletChainID.init))
    }

    private var refreshableChainNames: Set<String> {
        cachedRefreshableChainNames
    }

    var refreshableChainIDs: Set<WalletChainID> {
        Set(refreshableChainNames.compactMap(WalletChainID.init))
    }

    var backgroundBalanceRefreshFrequencyMinutes: Int {
        max(automaticRefreshFrequencyMinutes * 3, 15)
    }

    func refreshForForegroundIfNeeded() async {
        guard shouldPerformForegroundFullRefresh else { return }
        await performUserInitiatedRefresh(forceChainRefresh: false)
    }

    private var shouldPerformForegroundFullRefresh: Bool {
        guard userInitiatedRefreshTask == nil else { return false }
        guard let lastFullRefreshAt else { return true }
        return Date().timeIntervalSince(lastFullRefreshAt) >= Self.foregroundFullRefreshStalenessInterval
    }

    var includedPortfolioWallets: [ImportedWallet] {
        cachedIncludedPortfolioWallets
    }

    func currentPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else {
            return nil
        }
        return livePrices[activePriceKey(for: coin)]
    }

    func currentOrFallbackPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else {
            return nil
        }
        if let livePrice = currentPriceIfAvailable(for: coin) {
            return livePrice
        }
        guard coin.priceUSD > 0 else {
            return nil
        }
        return coin.priceUSD
    }

    func currentPrice(for coin: Coin) -> Double {
        currentPriceIfAvailable(for: coin) ?? 0
    }
    
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd {
            return 1.0
        }
        guard let rate = fiatRatesFromUSD[currency.rawValue], rate > 0 else {
            return nil
        }
        return rate
    }

    func fiatRate(for currency: FiatCurrency) -> Double {
        fiatRateIfAvailable(for: currency) ?? (currency == .usd ? 1.0 : 0)
    }

    private func persistAssetDisplayDecimalsByChain() {
        persistCodableToUserDefaults(assetDisplayDecimalsByChain, key: Self.assetDisplayDecimalsByChainDefaultsKey)
    }

    // Refreshes USD quotes and re-evaluates dependent alerts/fiat values.
    // MARK: - Pricing and Fiat Conversion
    @discardableResult
    func refreshLivePrices() async -> Bool {
        guard !isRefreshingLivePrices else { return false }
        isRefreshingLivePrices = true
        defer {
            isRefreshingLivePrices = false
            lastLivePriceRefreshAt = Date()
        }

        var didUpdatePrices = false

        let requestedCoins = priceRequestCoins

        guard !requestedCoins.isEmpty else {
            quoteRefreshError = nil
            return false
        }

        do {
            let fetchedPrices = try await LivePriceService.fetchQuotes(
                for: requestedCoins,
                provider: pricingProvider,
                coinGeckoAPIKey: coinGeckoAPIKey
            )
            guard !fetchedPrices.isEmpty else {
                quoteRefreshError = localizedStoreFormat("%@ returned no supported asset quotes", pricingProvider.rawValue)
                return false
            }

            var updatedPrices = livePrices
            var sawMeaningfulPriceChange = false
            for (key, value) in fetchedPrices {
                if updatedPrices[key] != value {
                    updatedPrices[key] = value
                    sawMeaningfulPriceChange = true
                }
            }
            if sawMeaningfulPriceChange {
                livePrices = updatedPrices
            }
            quoteRefreshError = nil
            didUpdatePrices = sawMeaningfulPriceChange
        } catch {
            quoteRefreshError = localizedStoreFormat("%@ pricing unavailable", pricingProvider.rawValue)
        }

        if didUpdatePrices {
            evaluatePriceAlerts()
        }
        return didUpdatePrices
    }

    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        if !force, selectedFiatCurrency == .usd {
            return
        }
        if !force,
           let lastFiatRatesRefreshAt,
           Date().timeIntervalSince(lastFiatRatesRefreshAt) < Self.fiatRatesRefreshInterval {
            return
        }
        await refreshFiatExchangeRates()
    }

    private func refreshFiatExchangeRates() async {
        do {
            var rates: [String: Double] = [FiatCurrency.usd.rawValue: 1.0]
            let fetchedRates = try await FiatRateService.fetchRates(from: fiatRateProvider, currencies: FiatCurrency.allCases)
            for currency in FiatCurrency.allCases where currency != .usd {
                if let rate = fetchedRates[currency.rawValue], rate > 0 {
                    rates[currency.rawValue] = rate
                } else if let existingRate = fiatRatesFromUSD[currency.rawValue], existingRate > 0 {
                    rates[currency.rawValue] = existingRate
                }
            }
            fiatRatesFromUSD = rates
            UserDefaults.standard.set(rates, forKey: Self.fiatRatesFromUSDDefaultsKey)
            fiatRatesRefreshError = nil
            lastFiatRatesRefreshAt = Date()
        } catch {
            if fiatRatesFromUSD.isEmpty {
                fiatRatesFromUSD = [FiatCurrency.usd.rawValue: 1.0]
            } else {
                fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
            }
            fiatRatesRefreshError = localizedStoreFormat("%@ fiat exchange rates are unavailable. Using the last successful rates.", fiatRateProvider.rawValue)
        }
    }
    
    private func activePriceKey(for coin: Coin) -> String {
        assetIdentityKey(for: coin)
    }
    
    // Calculates the sum of all coins
    var totalBalance: Double {
        portfolio.reduce(0) { $0 + currentValue(for: $1) }
    }

    var totalBalanceIfAvailable: Double? {
        sumLiveQuotedValues(for: portfolio)
    }

    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: UUID) {
        guard let walletIndex = wallets.firstIndex(where: { $0.id == walletID }) else { return }
        let wallet = wallets[walletIndex]
        wallets[walletIndex] = ImportedWallet(
            id: wallet.id,
            name: wallet.name,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: wallet.holdings,
            includeInPortfolioTotal: isIncluded
        )
        resetLargeMovementAlertBaseline()
    }

    var hasDogecoinWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Dogecoin"
                && {
                    guard let address = wallet.dogecoinAddress else { return false }
                    return isValidDogecoinAddressForPolicy(address, networkMode: wallet.dogecoinNetworkMode)
                }()
        }
    }

    var hasEthereumWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Ethereum"
                && resolvedEthereumAddress(for: wallet) != nil
        }
    }

    var hasLitecoinWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Litecoin"
                && resolvedLitecoinAddress(for: wallet) != nil
        }
    }

    var hasBNBWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "BNB Chain"
                && resolvedEVMAddress(for: wallet, chainName: "BNB Chain") != nil
        }
    }

    var hasArbitrumWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Arbitrum"
                && resolvedEVMAddress(for: wallet, chainName: "Arbitrum") != nil
        }
    }

    var hasOptimismWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Optimism"
                && resolvedEVMAddress(for: wallet, chainName: "Optimism") != nil
        }
    }

    var hasAvalancheWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Avalanche"
                && resolvedEVMAddress(for: wallet, chainName: "Avalanche") != nil
        }
    }

    var hasMoneroWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Monero"
                && resolvedMoneroAddress(for: wallet) != nil
        }
    }

    var hasCardanoWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Cardano"
                && resolvedCardanoAddress(for: wallet) != nil
        }
    }

    var hasSuiWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Sui"
                && resolvedSuiAddress(for: wallet) != nil
        }
    }

    var hasBitcoinWallets: Bool {
        wallets.contains { wallet in
            guard wallet.selectedChain == "Bitcoin" else { return false }
            if let seedPhrase = storedSeedPhrase(for: wallet.id),
               !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if let address = wallet.bitcoinAddress,
               AddressValidation.isValidBitcoinAddress(address, networkMode: wallet.bitcoinNetworkMode) {
                return true
            }
            if let xpub = wallet.bitcoinXPub,
               BitcoinWalletEngine.isLikelyExtendedPublicKey(xpub) {
                return true
            }
            return false
        }
    }

    var hasBitcoinCashWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Bitcoin Cash"
                && resolvedBitcoinCashAddress(for: wallet) != nil
        }
    }

    var hasBitcoinSVWallets: Bool {
        wallets.contains { wallet in
            wallet.selectedChain == "Bitcoin SV"
                && resolvedBitcoinSVAddress(for: wallet) != nil
        }
    }


    // Core chain refresh scheduler.
    // Runs chains sequentially with per-chain timeouts to avoid shared-state races and
    // to prevent one degraded provider from freezing the entire refresh cycle.
    func refreshChainBalances(
        includeHistoryRefreshes: Bool = true,
        historyRefreshInterval: TimeInterval = 120,
        forceChainRefresh: Bool = true
    ) async {
        await WalletFetchLayer.refreshChainBalances(
            using: self,
            includeHistoryRefreshes: includeHistoryRefreshes,
            historyRefreshInterval: historyRefreshInterval,
            forceChainRefresh: forceChainRefresh
        )
    }

    func withBalanceRefreshWindow(_ operation: () async -> Void) async {
        let previousState = allowsBalanceNetworkRefresh
        allowsBalanceNetworkRefresh = true
        defer { allowsBalanceNetworkRefresh = previousState }
        await operation()
    }

    func refreshWalletBalance(_ walletID: UUID) async {
        await WalletFetchLayer.refreshWalletBalance(walletID, using: self)
    }

    func collectLimitedConcurrentIndexedResults<Item, Value>(
        from items: [Item],
        maxConcurrent: Int = 4,
        operation: @escaping (Item) async -> (Int, Value?)
    ) async -> [Int: Value] {
        guard !items.isEmpty else { return [:] }
        let concurrencyLimit = max(1, min(maxConcurrent, items.count))

        return await withTaskGroup(of: (Int, Value?).self, returning: [Int: Value].self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<concurrencyLimit {
                guard let item = iterator.next() else { break }
                group.addTask {
                    await operation(item)
                }
            }

            var results: [Int: Value] = [:]
            while let (index, value) = await group.next() {
                if let value {
                    results[index] = value
                }

                if let item = iterator.next() {
                    group.addTask {
                        await operation(item)
                    }
                }
            }

            return results
        }
    }


    private func scheduleImportedWalletRefresh(_ createdWallets: [ImportedWallet]) {
        guard !createdWallets.isEmpty else {
            resetLargeMovementAlertBaseline()
            return
        }

        let importedChains = Set(createdWallets.compactMap { WalletChainID($0.selectedChain) })
        importRefreshTask?.cancel()
        importRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.withBalanceRefreshWindow {
                await self.refreshImportedWalletBalances(forChains: Set(importedChains.map(\.displayName)))
                _ = await self.refreshLivePrices()
            }
            await MainActor.run {
                self.resetLargeMovementAlertBaseline()
                self.importRefreshTask = nil
            }
        }
    }

    private func shouldRefreshChainBalances(now: Date = Date()) -> Bool {
        guard !isRefreshingChainBalances else { return false }
        guard let lastChainBalanceRefreshAt else { return true }
        return now.timeIntervalSince(lastChainBalanceRefreshAt) >= 30
    }

#if DEBUG
    func logBalanceTelemetry(
        source: String,
        chainName: String,
        wallet: ImportedWallet,
        holdings: [Coin]
    ) {
        let nonZeroAssets = holdings.reduce(into: 0) { partialResult, coin in
            if abs(coin.amount) > 0 {
                partialResult += 1
            }
        }
        let totalUnits = holdings.reduce(0) { $0 + $1.amount }
        balanceTelemetryLogger.debug(
            """
            balance_update source=\(source, privacy: .public) \
            chain=\(chainName, privacy: .public) \
            wallet_id=\(wallet.id.uuidString, privacy: .public) \
            wallet_name=\(wallet.name, privacy: .public) \
            non_zero_assets=\(nonZeroAssets, privacy: .public) \
            total_units=\(totalUnits, privacy: .public)
            """
        )
        appendOperationalLog(
            .debug,
            category: "Balance Telemetry",
            message: "Balance updated",
            chainName: chainName,
            walletID: wallet.id,
            source: source,
            metadata: "non_zero_assets=\(nonZeroAssets), total_units=\(totalUnits)"
        )
    }
#endif
    
    // BTC balance refresh pipeline with seed-based primary source and safe fallbacks.
    // MARK: - Per-Chain Balance Refresh
    func refreshBitcoinBalances() async {
        await WalletFetchLayer.refreshBitcoinBalances(using: self)
    }

    func refreshBitcoinCashBalances() async {
        await WalletFetchLayer.refreshBitcoinCashBalances(using: self)
    }

    func refreshBitcoinSVBalances() async {
        await WalletFetchLayer.refreshBitcoinSVBalances(using: self)
    }

    // LTC balance refresh pipeline with deterministic derivation and API fallback behavior.
    func refreshLitecoinBalances() async {
        await WalletFetchLayer.refreshLitecoinBalances(using: self)
    }

    // DOGE balance refresh with discovery/keypool awareness and ledger-derived fallback support.
    func refreshDogecoinBalances() async {
        await WalletFetchLayer.refreshDogecoinBalances(using: self)
    }

    func ledgerDerivedDogecoinBalance(for walletID: UUID) -> Double? {
        ledgerDerivedNativeBalanceIfAvailable(for: walletID, chainName: "Dogecoin", symbol: "DOGE")
    }

    func ledgerDerivedNativeBalanceIfAvailable(
        for walletID: UUID,
        chainName: String,
        symbol: String
    ) -> Double? {
        _ = walletID
        _ = chainName
        _ = symbol
        return nil
    }

    func resolvedTronNativeBalance(
        fetchedNativeBalance: Double,
        tokenBalances: [TronTokenBalanceSnapshot],
        wallet: ImportedWallet
    ) -> Double {
        _ = tokenBalances
        _ = wallet
        return fetchedNativeBalance
    }

    // ETH native + tracked token refresh, then holdings merge into wallet snapshot.
    func refreshEthereumBalances() async {
        await WalletFetchLayer.refreshEthereumBalances(using: self)
    }

    func refreshBNBBalances() async {
        await WalletFetchLayer.refreshBNBBalances(using: self)
    }

    func refreshArbitrumBalances() async {
        await WalletFetchLayer.refreshArbitrumBalances(using: self)
    }

    func refreshOptimismBalances() async {
        await WalletFetchLayer.refreshOptimismBalances(using: self)
    }

    func refreshETCBalances() async {
        await WalletFetchLayer.refreshETCBalances(using: self)
    }

    func refreshAvalancheBalances() async {
        await WalletFetchLayer.refreshAvalancheBalances(using: self)
    }

    func refreshHyperliquidBalances() async {
        await WalletFetchLayer.refreshHyperliquidBalances(using: self)
    }

    func refreshTronBalances() async {
        await WalletFetchLayer.refreshTronBalances(using: self)
    }

    // SOL native + SPL token refresh path.
    // This is where tracked contract/mint preferences directly affect asset visibility.
    func refreshSolanaBalances() async {
        await WalletFetchLayer.refreshSolanaBalances(using: self)
    }

    // ADA balance refresh for selected wallets/chains.
    func refreshCardanoBalances() async {
        await WalletFetchLayer.refreshCardanoBalances(using: self)
    }

    // XRP balance refresh for selected wallets/chains.
    func refreshXRPBalances() async {
        await WalletFetchLayer.refreshXRPBalances(using: self)
    }

    func refreshStellarBalances() async {
        await WalletFetchLayer.refreshStellarBalances(using: self)
    }

    // XMR balance refresh for selected wallets/chains.
    func refreshMoneroBalances() async {
        await WalletFetchLayer.refreshMoneroBalances(using: self)
    }

    // SUI balance refresh for selected wallets/chains.
    func refreshSuiBalances() async {
        await WalletFetchLayer.refreshSuiBalances(using: self)
    }

    func refreshAptosBalances() async {
        await WalletFetchLayer.refreshAptosBalances(using: self)
    }

    func refreshTONBalances() async {
        await WalletFetchLayer.refreshTONBalances(using: self)
    }

    func refreshICPBalances() async {
        await WalletFetchLayer.refreshICPBalances(using: self)
    }

    func refreshNearBalances() async {
        await WalletFetchLayer.refreshNearBalances(using: self)
    }

    func refreshPolkadotBalances() async {
        await WalletFetchLayer.refreshPolkadotBalances(using: self)
    }


    func applyBitcoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BTC",
            chainName: "Bitcoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin",
                symbol: "BTC",
                marketDataID: "1",
                coinGeckoID: "bitcoin",
                chainName: "Bitcoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 64000,
                mark: "B",
                color: .orange
            )
        )
    }

    func applyBitcoinCashBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BCH",
            chainName: "Bitcoin Cash",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin Cash",
                symbol: "BCH",
                marketDataID: "1831",
                coinGeckoID: "bitcoin-cash",
                chainName: "Bitcoin Cash",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 420,
                mark: "BC",
                color: .orange
            )
        )
    }

    func applyBitcoinSVBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BSV",
            chainName: "Bitcoin SV",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin SV",
                symbol: "BSV",
                marketDataID: "3602",
                coinGeckoID: "bitcoin-cash-sv",
                chainName: "Bitcoin SV",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 80,
                mark: "BS",
                color: .orange
            )
        )
    }

    func applyLitecoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "LTC",
            chainName: "Litecoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Litecoin",
                symbol: "LTC",
                marketDataID: "2",
                coinGeckoID: "litecoin",
                chainName: "Litecoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 90,
                mark: "L",
                color: .gray
            )
        )
    }

    func applyDogecoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "DOGE",
            chainName: "Dogecoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Dogecoin",
                symbol: "DOGE",
                marketDataID: "74",
                coinGeckoID: "dogecoin",
                chainName: "Dogecoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.15,
                mark: "D",
                color: .brown
            )
        )
    }

    func applyEthereumNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Ethereum",
            amount: balance,
            defaultCoin: Coin(
                name: "Ethereum",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Ethereum",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "E",
                color: .blue
            )
        )
    }

    func applyETCNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETC",
            chainName: "Ethereum Classic",
            amount: balance,
            defaultCoin: Coin(
                name: "Ethereum Classic",
                symbol: "ETC",
                marketDataID: "1321",
                coinGeckoID: "ethereum-classic",
                chainName: "Ethereum Classic",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 30,
                mark: "EC",
                color: .green
            )
        )
    }

    func applyBNBNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BNB",
            chainName: "BNB Chain",
            amount: balance,
            defaultCoin: Coin(
                name: "BNB",
                symbol: "BNB",
                marketDataID: "1839",
                coinGeckoID: "binancecoin",
                chainName: "BNB Chain",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 450,
                mark: "BN",
                color: .yellow
            )
        )
    }

    func applyArbitrumNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Arbitrum",
            amount: balance,
            defaultCoin: Coin(
                name: "Ether",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Arbitrum",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "AR",
                color: .cyan
            )
        )
    }

    func applyOptimismNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Optimism",
            amount: balance,
            defaultCoin: Coin(
                name: "Ether",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Optimism",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "OP",
                color: .red
            )
        )
    }

    func applyAvalancheNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "AVAX",
            chainName: "Avalanche",
            amount: balance,
            defaultCoin: Coin(
                name: "Avalanche",
                symbol: "AVAX",
                marketDataID: "5805",
                coinGeckoID: "avalanche-2",
                chainName: "Avalanche",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 35,
                mark: "AV",
                color: .red
            )
        )
    }

    func applyHyperliquidNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "HYPE",
            chainName: "Hyperliquid",
            amount: balance,
            defaultCoin: Coin(
                name: "Hyperliquid",
                symbol: "HYPE",
                marketDataID: "0",
                coinGeckoID: "hyperliquid",
                chainName: "Hyperliquid",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0,
                mark: "HY",
                color: .mint
            )
        )
    }

    func applyETCBalances(
        nativeBalance: Double,
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = holdings.filter { $0.chainName != "Ethereum Classic" || $0.symbol == "ETC" }
        if let etcIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETC" && $0.chainName == "Ethereum Classic" }) {
            let existing = updatedHoldings[etcIndex]
            updatedHoldings[etcIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyETCNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }
        return updatedHoldings
    }

    func applyAvalancheBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledAvalancheTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Avalanche" || $0.symbol == "AVAX" }
        if let avaxIndex = updatedHoldings.firstIndex(where: { $0.symbol == "AVAX" && $0.chainName == "Avalanche" }) {
            let existing = updatedHoldings[avaxIndex]
            updatedHoldings[avaxIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyAvalancheNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Avalanche",
                    tokenStandard: "ARC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyArbitrumBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledArbitrumTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Arbitrum" || $0.symbol == "ETH" }
        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Arbitrum" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyArbitrumNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Arbitrum",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" || token.symbol == "USD1" || token.symbol == "USDE" || token.symbol == "USDD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyOptimismBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledOptimismTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Optimism" || $0.symbol == "ETH" }
        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Optimism" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyOptimismNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Optimism",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" || token.symbol == "USD1" || token.symbol == "USDE" || token.symbol == "USDD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyHyperliquidBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledHyperliquidTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Hyperliquid" || $0.symbol == "HYPE" }
        if let hypeIndex = updatedHoldings.firstIndex(where: { $0.symbol == "HYPE" && $0.chainName == "Hyperliquid" }) {
            let existing = updatedHoldings[hypeIndex]
            updatedHoldings[hypeIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyHyperliquidNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Hyperliquid",
                    tokenStandard: TokenTrackingChain.hyperliquid.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "USDE" || token.symbol == "USDB" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyTronNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "TRX",
            chainName: "Tron",
            amount: balance,
            defaultCoin: Coin(
                name: "Tron",
                symbol: "TRX",
                marketDataID: "1958",
                coinGeckoID: "tron",
                chainName: "Tron",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.12,
                mark: "T",
                color: .teal
            )
        )
    }

    func applySolanaNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "SOL",
            chainName: "Solana",
            amount: balance,
            defaultCoin: Coin(
                name: "Solana",
                symbol: "SOL",
                marketDataID: "5426",
                coinGeckoID: "solana",
                chainName: "Solana",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 150,
                mark: "S",
                color: .purple
            )
        )
    }

    func applyEthereumBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledEthereumTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Ethereum" && holding.symbol != "ETH")
        }

        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Ethereum" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Ethereum",
                    symbol: "ETH",
                    marketDataID: "1027",
                    coinGeckoID: "ethereum",
                    chainName: "Ethereum",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 3500,
                    mark: "E",
                    color: .blue
                )
            )
        }

        for token in trackedTokens {
            let contract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let amount = tokenBalanceLookup[contract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Ethereum",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyBNBBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledBNBTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
        )

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "BNB Chain" && holding.symbol != "BNB")
        }

        if !updatedHoldings.contains(where: { $0.symbol == "BNB" && $0.chainName == "BNB Chain" }) {
            updatedHoldings.append(
                Coin(
                    name: "BNB",
                    symbol: "BNB",
                    marketDataID: "1839",
                    coinGeckoID: "binancecoin",
                    chainName: "BNB Chain",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 450,
                    mark: "BN",
                    color: .yellow
                )
            )
        }

        if let bnbIndex = updatedHoldings.firstIndex(where: { $0.symbol == "BNB" && $0.chainName == "BNB Chain" }) {
            let existing = updatedHoldings[bnbIndex]
            updatedHoldings[bnbIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        }

        for token in trackedTokens {
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
            let tokenBalance = tokenBalanceLookup[normalizedContract]
            let amount = tokenBalance.map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "BNB Chain",
                    tokenStandard: "BEP-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyTronBalances(
        nativeBalance: Double,
        tokenBalances: [TronTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledTokenPreferences(for: .tron)
        let tokenBalanceLookup: [String: Double] = Dictionary(uniqueKeysWithValues: tokenBalances.compactMap { snapshot in
            guard let contract = snapshot.contractAddress else { return nil }
            return (contract.lowercased(), snapshot.balance)
        })

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Tron" && holding.symbol != "TRX")
        }

        if let trxIndex = updatedHoldings.firstIndex(where: { $0.symbol == "TRX" && $0.chainName == "Tron" }) {
            let existing = updatedHoldings[trxIndex]
            updatedHoldings[trxIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Tron",
                    symbol: "TRX",
                    marketDataID: "1958",
                    coinGeckoID: "tron",
                    chainName: "Tron",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 0.12,
                    mark: "T",
                    color: .teal
                )
            )
        }

        for token in trackedTokens {
            let balance = tokenBalanceLookup[token.contractAddress.lowercased()] ?? 0
            guard balance > 0 else { continue }
            let stableSymbols = Set(["USDT", "USDC", "USDD", "TUSD", "FDUSD"])
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Tron",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: balance,
                    priceUSD: stableSymbols.contains(token.symbol) ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyCardanoBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ADA",
            chainName: "Cardano",
            amount: balance,
            defaultCoin: Coin(
                name: "Cardano",
                symbol: "ADA",
                marketDataID: "2010",
                coinGeckoID: "cardano",
                chainName: "Cardano",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.55,
                mark: "A",
                color: .indigo
            )
        )
    }

    func applyXRPBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XRP",
            chainName: "XRP Ledger",
            amount: balance,
            defaultCoin: Coin(
                name: "XRP",
                symbol: "XRP",
                marketDataID: "52",
                coinGeckoID: "ripple",
                chainName: "XRP Ledger",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.6,
                mark: "X",
                color: .cyan
            )
        )
    }

    func applyStellarBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XLM",
            chainName: "Stellar",
            amount: balance,
            defaultCoin: Coin(
                name: "Stellar Lumens",
                symbol: "XLM",
                marketDataID: "171",
                coinGeckoID: "stellar",
                chainName: "Stellar",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.12,
                mark: "X",
                color: .blue
            )
        )
    }

    func applyMoneroBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XMR",
            chainName: "Monero",
            amount: balance,
            defaultCoin: Coin(
                name: "Monero",
                symbol: "XMR",
                marketDataID: "328",
                coinGeckoID: "monero",
                chainName: "Monero",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 120,
                mark: "M",
                color: .indigo
            )
        )
    }

    private func applySuiBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "SUI",
            chainName: "Sui",
            amount: balance,
            defaultCoin: Coin(
                name: "Sui",
                symbol: "SUI",
                marketDataID: "20947",
                coinGeckoID: "sui",
                chainName: "Sui",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 1.0,
                mark: "S",
                color: .mint
            )
        )
    }

    func applySuiBalances(
        nativeBalance: Double,
        tokenBalances: [SuiTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledTokenPreferences(for: .sui)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeSuiTokenIdentifier($0.coinType), $0) }
        )
        let packageBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (suiPackageIdentifier(from: $0.coinType), $0) }
        )

        var updatedHoldings = applySuiBalance(nativeBalance, to: holdings).filter { holding in
            !(holding.chainName == "Sui" && holding.symbol != "SUI")
        }

        for token in trackedTokens {
            let normalizedCoinType = normalizeSuiTokenIdentifier(token.contractAddress)
            guard let snapshot = tokenBalanceLookup[normalizedCoinType]
                ?? packageBalanceLookup[suiPackageIdentifier(from: token.contractAddress)],
                  snapshot.balance > 0 else {
                continue
            }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Sui",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    private func suiPackageIdentifier(from value: String?) -> String {
        let normalized = normalizeSuiTokenIdentifier(value ?? "")
        guard let package = normalized.split(separator: "::", omittingEmptySubsequences: false).first else {
            return normalized
        }
        return String(package)
    }

    private func applyAptosBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "APT",
            chainName: "Aptos",
            amount: balance,
            defaultCoin: Coin(
                name: "Aptos",
                symbol: "APT",
                marketDataID: "21794",
                coinGeckoID: "aptos",
                chainName: "Aptos",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 8,
                mark: "AP",
                color: .cyan
            )
        )
    }

    func applyAptosBalances(
        nativeBalance: Double,
        tokenBalances: [AptosTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = applyAptosBalance(nativeBalance, to: holdings)
        let trackedTokens = enabledTokenPreferences(for: .aptos)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeAptosTokenIdentifier($0.coinType), $0) }
        )
        let tokenBalanceLookupByPackage = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (aptosPackageIdentifier(from: $0.coinType), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "Aptos" && holding.symbol != "APT")
        }

        for token in trackedTokens {
            let normalizedIdentifier = normalizeAptosTokenIdentifier(token.contractAddress)
            guard let snapshot = tokenBalanceLookup[normalizedIdentifier]
                ?? tokenBalanceLookupByPackage[aptosPackageIdentifier(from: normalizedIdentifier)],
                  snapshot.balance > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Aptos",
                    tokenStandard: token.tokenStandard,
                    contractAddress: snapshot.coinType,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" || token.symbol == "TUSD" || token.symbol == "USDE"
                        ? 1.0
                        : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    private func applyTONBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "TON",
            chainName: "TON",
            amount: balance,
            defaultCoin: Coin(
                name: "Toncoin",
                symbol: "TON",
                marketDataID: "11419",
                coinGeckoID: "the-open-network",
                chainName: "TON",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 7,
                mark: "TN",
                color: .blue
            )
        )
    }

    func applyTONBalances(
        nativeBalance: Double,
        tokenBalances: [TONJettonBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = applyTONBalance(nativeBalance, to: holdings)
        let trackedTokens = enabledTokenPreferences(for: .ton)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (TONBalanceService.normalizeJettonMasterAddress($0.masterAddress), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "TON" && holding.symbol != "TON")
        }

        for token in trackedTokens {
            guard let snapshot = tokenBalanceLookup[TONBalanceService.normalizeJettonMasterAddress(token.contractAddress)],
                  snapshot.balance > 0 else {
                continue
            }

            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "TON",
                    tokenStandard: token.tokenStandard,
                    contractAddress: snapshot.masterAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "FDUSD" || token.symbol == "TUSD" || token.symbol == "USD1" || token.symbol == "USDE"
                        ? 1.0
                        : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyICPBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ICP",
            chainName: "Internet Computer",
            amount: balance,
            defaultCoin: Coin(
                name: "Internet Computer",
                symbol: "ICP",
                marketDataID: "2416",
                coinGeckoID: "internet-computer",
                chainName: "Internet Computer",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 12,
                mark: "IC",
                color: .indigo
            )
        )
    }

    private func applyNearBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "NEAR",
            chainName: "NEAR",
            amount: balance,
            defaultCoin: Coin(
                name: "NEAR Protocol",
                symbol: "NEAR",
                marketDataID: "6535",
                coinGeckoID: "near",
                chainName: "NEAR",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 6,
                mark: "N",
                color: .indigo
            )
        )
    }

    func applyNearBalances(
        nativeBalance: Double?,
        tokenBalances: [NearTokenBalanceSnapshot]?,
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = holdings
        if let nativeBalance {
            updatedHoldings = applyNearBalance(nativeBalance, to: updatedHoldings)
        }

        guard let tokenBalances else { return updatedHoldings }

        let trackedTokens = enabledTokenPreferences(for: .near)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { ($0.contractAddress.lowercased(), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "NEAR" && holding.symbol != "NEAR")
        }

        for token in trackedTokens {
            guard let snapshot = tokenBalanceLookup[token.contractAddress.lowercased()],
                  snapshot.balance > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "NEAR",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" || token.symbol == "TUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyPolkadotBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "DOT",
            chainName: "Polkadot",
            amount: balance,
            defaultCoin: Coin(
                name: "Polkadot",
                symbol: "DOT",
                marketDataID: "6636",
                coinGeckoID: "polkadot",
                chainName: "Polkadot",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 7,
                mark: "P",
                color: .pink
            )
        )
    }

    private func upsertNativeHolding(
        in holdings: [Coin],
        symbol: String,
        chainName: String,
        amount: Double,
        defaultCoin: Coin
    ) -> [Coin] {
        if let index = holdings.firstIndex(where: { $0.symbol == symbol && $0.chainName == chainName }) {
            var updatedHoldings = holdings
            let existing = holdings[index]
            updatedHoldings[index] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: amount,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
            return updatedHoldings
        }

        var updatedHoldings = holdings
        updatedHoldings.append(defaultCoin)
        return updatedHoldings
    }

    // Merges SOL + SPL token snapshots into canonical coin holdings for one wallet.
    func applySolanaPortfolio(
        nativeBalance: Double,
        tokenBalances: [SolanaSPLTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let existingSolanaTokensByMint = Dictionary(
            uniqueKeysWithValues: holdings.compactMap { holding -> (String, Coin)? in
                guard holding.chainName == "Solana",
                      holding.symbol != "SOL",
                      let mint = holding.contractAddress else {
                    return nil
                }
                return (mint, holding)
            }
        )
        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Solana" && holding.symbol != "SOL")
        }

        if let solanaIndex = updatedHoldings.firstIndex(where: { $0.symbol == "SOL" && $0.chainName == "Solana" }) {
            let solana = updatedHoldings[solanaIndex]
            updatedHoldings[solanaIndex] = Coin(
                name: solana.name,
                symbol: solana.symbol,
                marketDataID: solana.marketDataID,
                coinGeckoID: solana.coinGeckoID,
                chainName: solana.chainName,
                tokenStandard: solana.tokenStandard,
                contractAddress: solana.contractAddress,
                amount: nativeBalance,
                priceUSD: solana.priceUSD,
                mark: solana.mark,
                color: solana.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Solana",
                    symbol: "SOL",
                    marketDataID: "5426",
                    coinGeckoID: "solana",
                    chainName: "Solana",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 150,
                    mark: "S",
                    color: .purple
                )
            )
        }

        for token in tokenBalances where token.balance > 0 {
            let existing = existingSolanaTokensByMint[token.mintAddress]
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Solana",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.mintAddress,
                    amount: token.balance,
                    priceUSD: existing?.priceUSD ?? defaultPriceUSDForSolanaToken(symbol: token.symbol),
                    mark: String(token.symbol.prefix(1)).uppercased(),
                    color: .mint
                )
            )
        }

        return updatedHoldings
    }

    private func defaultPriceUSDForSolanaToken(symbol: String) -> Double {
        switch symbol.uppercased() {
        case "USDT", "USDC", "FDUSD":
            return 1.0
        default:
            return 0
        }
    }

    private func configuredEthereumRPCEndpointURL() -> URL? {
        guard ethereumRPCEndpointValidationError == nil else { return nil }
        let trimmedEndpoint = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return nil }
        return URL(string: trimmedEndpoint)
    }

    func normalizedEtherscanAPIKey() -> String? {
        let trimmed = etherscanAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        let ethereumContext = evmChainContext(for: "Ethereum") ?? .ethereum
        // If a custom endpoint is invalid, fall back to built-in provider rotation instead of hard-failing ETH.
        let useFallbackEndpoint = ethereumRPCEndpointValidationError != nil
            && !ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rpcEndpoint = useFallbackEndpoint ? nil : configuredEVMRPCEndpointURL(for: "Ethereum")
        let accountSnapshot = try await EthereumWalletEngine.fetchAccountSnapshot(
            for: address,
            rpcEndpoint: rpcEndpoint,
            chainID: ethereumContext.expectedChainID,
            chain: ethereumContext
        )
        let tokenBalances = ethereumContext.isEthereumMainnet
            ? ((try? await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledEthereumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: ethereumContext
            )) ?? [])
            : []
        return (
            EthereumWalletEngine.nativeBalanceETH(from: accountSnapshot),
            tokenBalances
        )
    }

    func fetchEVMNativePortfolio(
        for address: String,
        chainName: String
    ) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        guard let chain = evmChainContext(for: chainName) else {
            throw EthereumWalletEngineError.invalidResponse
        }
        let useFallbackEndpoint = chain.isEthereumFamily
            && ethereumRPCEndpointValidationError != nil
            && !ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rpcEndpoint = useFallbackEndpoint ? nil : configuredEVMRPCEndpointURL(for: chainName)
        let accountSnapshot = try await EthereumWalletEngine.fetchAccountSnapshot(
            for: address,
            rpcEndpoint: rpcEndpoint,
            chainID: chain.expectedChainID,
            chain: chain
        )
        let tokenBalances: [EthereumTokenBalanceSnapshot]
        if chain.isEthereumMainnet {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledEthereumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .arbitrum {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledArbitrumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .optimism {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledOptimismTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .bnb {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledBNBTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .avalanche {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledAvalancheTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .hyperliquid {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledHyperliquidTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else {
            tokenBalances = try await EthereumWalletEngine.fetchSupportedTokenBalances(
                for: address,
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        }
        return (
            EthereumWalletEngine.nativeBalanceETH(from: accountSnapshot),
            tokenBalances
        )
    }

    // MARK: - Pending Transaction Polling
    func refreshPendingEthereumTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Ethereum")
    }

    func refreshPendingArbitrumTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Arbitrum")
    }

    func refreshPendingOptimismTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Optimism")
    }

    func refreshPendingETCTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Ethereum Classic")
    }

    func refreshPendingBNBTransactions() async {
        await refreshPendingEVMTransactions(chainName: "BNB Chain")
    }

    func refreshPendingAvalancheTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Avalanche")
    }

    func refreshPendingHyperliquidTransactions() async {
        await refreshPendingEVMTransactions(chainName: "Hyperliquid")
    }

    // Polls pending EVM tx statuses and upgrades local records to confirmed/failed as receipts arrive.
    private func refreshPendingEVMTransactions(chainName: String) async {
        let now = Date()
        guard let chain = evmChainContext(for: chainName) else { return }
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedReceipts: [UUID: (TransactionStatus, EthereumTransactionReceipt)] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let receipt = try await EthereumWalletEngine.fetchTransactionReceipt(
                    transactionHash: transactionHash,
                    rpcEndpoint: configuredEVMRPCEndpointURL(for: chainName),
                    chain: chain
                )
                if let receipt, receipt.isConfirmed {
                    let resolvedStatus: TransactionStatus = receipt.isFailed ? .failed : .confirmed
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                    resolvedReceipts[transaction.id] = (resolvedStatus, receipt)
                } else {
                    markTransactionStatusPollSuccess(for: transaction, resolvedStatus: .pending, now: now)
                }
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let resolvedStatuses = resolvedReceipts.mapValues { resolvedStatus, receipt in
            PendingTransactionStatusResolution(
                status: resolvedStatus,
                receiptBlockNumber: receipt.blockNumber,
                confirmations: nil,
                dogecoinNetworkFeeDOGE: nil
            )
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    // Fetches token transfer history and maps provider records into normalized transaction model.

    // Diagnostics runners:
    // Each chain has history + endpoint probes so users can distinguish
    // "provider reachable" from "provider returning usable chain data".
    // MARK: - Diagnostics and Endpoint Health
    func runBitcoinHistoryDiagnostics() async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }

        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else {
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for wallet in btcWallets {
            do {
                let page = try await withTimeout(seconds: 20) {
                    try await self.fetchBitcoinHistoryPage(
                        for: wallet,
                        limit: HistoryPaging.endpointBatchSize,
                        cursor: nil
                    )
                }
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
                if identifier.isEmpty {
                    bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                        walletID: wallet.id,
                        identifier: "missing address/xpub",
                        sourceUsed: "none",
                        transactionCount: 0,
                        nextCursor: nil,
                        error: "Wallet has no BTC address or xpub configured."
                    )
                    continue
                }

                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: identifier,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor,
                    error: nil
                )
            } catch {
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: identifier,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    func runBitcoinHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Bitcoin" else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }

        do {
            let page = try await withTimeout(seconds: 20) {
                try await self.fetchBitcoinHistoryPage(
                    for: wallet,
                    limit: HistoryPaging.endpointBatchSize,
                    cursor: nil
                )
            }
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
            if identifier.isEmpty {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: "missing address/xpub",
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: "Wallet has no BTC address or xpub configured."
                )
                bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
                return
            }

            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: page.sourceUsed,
                transactionCount: page.snapshots.count,
                nextCursor: page.nextCursor,
                error: nil
            )
        } catch {
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: "none",
                transactionCount: 0,
                nextCursor: nil,
                error: error.localizedDescription
            )
        }
        bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinEndpointHealth else { return }
        isCheckingBitcoinEndpointHealth = true
        defer { isCheckingBitcoinEndpointHealth = false }

        let endpoints = effectiveBitcoinEsploraEndpoints()
        var results: [BitcoinEndpointHealthResult] = []

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probeTarget = url.appending(path: "blocks/tip/height")
            let probe = await probeHTTP(probeTarget)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
            bitcoinEndpointHealthResults = results
            bitcoinEndpointHealthLastUpdatedAt = Date()
        }
    }

    func runLitecoinHistoryDiagnostics() async {
        guard !isRunningLitecoinHistoryDiagnostics else { return }
        isRunningLitecoinHistoryDiagnostics = true
        defer { isRunningLitecoinHistoryDiagnostics = false }

        let ltcWallets = wallets.filter { $0.selectedChain == "Litecoin" }
        guard !ltcWallets.isEmpty else {
            litecoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for wallet in ltcWallets {
            guard let litecoinAddress = resolvedLitecoinAddress(for: wallet) else {
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: "missing litecoin address",
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: "Wallet has no LTC address configured."
                )
                continue
            }

            do {
                let page = try await withTimeout(seconds: 20) {
                    try await LitecoinBalanceService.fetchTransactionPage(
                        for: litecoinAddress,
                        limit: HistoryPaging.endpointBatchSize,
                        cursor: nil
                    )
                }
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: litecoinAddress,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor,
                    error: nil
                )
            } catch {
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: litecoinAddress,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
            litecoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    func runLitecoinHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningLitecoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Litecoin",
              let litecoinAddress = resolvedLitecoinAddress(for: wallet) else { return }
        isRunningLitecoinHistoryDiagnostics = true
        defer { isRunningLitecoinHistoryDiagnostics = false }

        do {
            let page = try await withTimeout(seconds: 20) {
                try await LitecoinBalanceService.fetchTransactionPage(
                    for: litecoinAddress,
                    limit: HistoryPaging.endpointBatchSize,
                    cursor: nil
                )
            }
            litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: litecoinAddress,
                sourceUsed: page.sourceUsed,
                transactionCount: page.snapshots.count,
                nextCursor: page.nextCursor,
                error: nil
            )
        } catch {
            litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: litecoinAddress,
                sourceUsed: "none",
                transactionCount: 0,
                nextCursor: nil,
                error: error.localizedDescription
            )
        }
        litecoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runLitecoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingLitecoinEndpointHealth else { return }
        isCheckingLitecoinEndpointHealth = true
        defer { isCheckingLitecoinEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: LitecoinBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.litecoinEndpointHealthResults = $0 },
            markUpdated: { self.litecoinEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBitcoinCashHistoryDiagnostics() async {
        guard !isRunningBitcoinCashHistoryDiagnostics else { return }
        isRunningBitcoinCashHistoryDiagnostics = true
        defer { isRunningBitcoinCashHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin Cash",
                  let address = resolvedBitcoinCashAddress(for: wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: address,
                sourceUsed: "running",
                transactionCount: 0,
                nextCursor: nil,
                error: "Running..."
            )
            bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let page = try await withTimeout(seconds: 15) {
                    try await BitcoinCashBalanceService.fetchTransactionPage(
                        for: address,
                        limit: HistoryPaging.endpointBatchSize
                    )
                }
                bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor ?? "",
                    error: nil
                )
            } catch {
                bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
        }

        bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinCashEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinCashEndpointHealth else { return }
        isCheckingBitcoinCashEndpointHealth = true
        defer { isCheckingBitcoinCashEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: BitcoinCashBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.bitcoinCashEndpointHealthResults = $0 },
            markUpdated: { self.bitcoinCashEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBitcoinSVHistoryDiagnostics() async {
        guard !isRunningBitcoinSVHistoryDiagnostics else { return }
        isRunningBitcoinSVHistoryDiagnostics = true
        defer { isRunningBitcoinSVHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin SV",
                  let address = resolvedBitcoinSVAddress(for: wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: address,
                sourceUsed: "running",
                transactionCount: 0,
                nextCursor: nil,
                error: "Running..."
            )
            bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let page = try await withTimeout(seconds: 15) {
                    try await BitcoinSVBalanceService.fetchTransactionPage(
                        for: address,
                        limit: HistoryPaging.endpointBatchSize
                    )
                }
                bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor ?? "",
                    error: nil
                )
            } catch {
                bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
        }

        bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinSVEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinSVEndpointHealth else { return }
        isCheckingBitcoinSVEndpointHealth = true
        defer { isCheckingBitcoinSVEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: BitcoinSVBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.bitcoinSVEndpointHealthResults = $0 },
            markUpdated: { self.bitcoinSVEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runTronHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningTronHistoryDiagnostics },
            setRunning: { self.isRunningTronHistoryDiagnostics = $0 },
            chainName: "Tron",
            resolveAddress: { self.resolvedTronAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tronHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tronHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTronHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningTronHistoryDiagnostics },
            setRunning: { self.isRunningTronHistoryDiagnostics = $0 },
            chainName: "Tron",
            resolveAddress: { self.resolvedTronAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tronHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tronHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTronEndpointReachabilityDiagnostics() async {
        guard !isCheckingTronEndpointHealth else { return }
        isCheckingTronEndpointHealth = true
        defer { isCheckingTronEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: TronBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.tronEndpointHealthResults = $0 },
            markUpdated: { self.tronEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runSolanaHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningSolanaHistoryDiagnostics },
            setRunning: { self.isRunningSolanaHistoryDiagnostics = $0 },
            chainName: "Solana",
            resolveAddress: { self.resolvedSolanaAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await SolanaBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.solanaHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.solanaHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSolanaHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningSolanaHistoryDiagnostics },
            setRunning: { self.isRunningSolanaHistoryDiagnostics = $0 },
            chainName: "Solana",
            resolveAddress: { self.resolvedSolanaAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await SolanaBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.solanaHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.solanaHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSolanaEndpointReachabilityDiagnostics() async {
        guard !isCheckingSolanaEndpointHealth else { return }
        isCheckingSolanaEndpointHealth = true
        defer { isCheckingSolanaEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: SolanaBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.solanaEndpointHealthResults = $0 },
            markUpdated: { self.solanaEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runCardanoHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningCardanoHistoryDiagnostics },
            setRunning: { self.isRunningCardanoHistoryDiagnostics = $0 },
            chainName: "Cardano",
            resolveAddress: { self.resolvedCardanoAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.cardanoHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.cardanoHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runCardanoHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningCardanoHistoryDiagnostics },
            setRunning: { self.isRunningCardanoHistoryDiagnostics = $0 },
            chainName: "Cardano",
            resolveAddress: { self.resolvedCardanoAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.cardanoHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.cardanoHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runCardanoEndpointReachabilityDiagnostics() async {
        guard !isCheckingCardanoEndpointHealth else { return }
        isCheckingCardanoEndpointHealth = true
        defer { isCheckingCardanoEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: CardanoBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.cardanoEndpointHealthResults = $0 },
            markUpdated: { self.cardanoEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runXRPHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningXRPHistoryDiagnostics },
            setRunning: { self.isRunningXRPHistoryDiagnostics = $0 },
            chainName: "XRP Ledger",
            resolveAddress: { self.resolvedXRPAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await XRPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.xrpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.xrpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runXRPHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningXRPHistoryDiagnostics },
            setRunning: { self.isRunningXRPHistoryDiagnostics = $0 },
            chainName: "XRP Ledger",
            resolveAddress: { self.resolvedXRPAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await XRPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.xrpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.xrpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runXRPEndpointReachabilityDiagnostics() async {
        guard !isCheckingXRPEndpointHealth else { return }
        isCheckingXRPEndpointHealth = true
        defer { isCheckingXRPEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: XRPBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.xrpEndpointHealthResults = $0 },
            markUpdated: { self.xrpEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runStellarHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningStellarHistoryDiagnostics },
            setRunning: { self.isRunningStellarHistoryDiagnostics = $0 },
            chainName: "Stellar",
            resolveAddress: { self.resolvedStellarAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await StellarBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.stellarHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.stellarHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runStellarHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningStellarHistoryDiagnostics },
            setRunning: { self.isRunningStellarHistoryDiagnostics = $0 },
            chainName: "Stellar",
            resolveAddress: { self.resolvedStellarAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await StellarBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.stellarHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.stellarHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runStellarEndpointReachabilityDiagnostics() async {
        guard !isCheckingStellarEndpointHealth else { return }
        isCheckingStellarEndpointHealth = true
        defer { isCheckingStellarEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: StellarBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.stellarEndpointHealthResults = $0 },
            markUpdated: { self.stellarEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runMoneroHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningMoneroHistoryDiagnostics },
            setRunning: { self.isRunningMoneroHistoryDiagnostics = $0 },
            chainName: "Monero",
            resolveAddress: { self.resolvedMoneroAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.moneroHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.moneroHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runMoneroHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningMoneroHistoryDiagnostics },
            setRunning: { self.isRunningMoneroHistoryDiagnostics = $0 },
            chainName: "Monero",
            resolveAddress: { self.resolvedMoneroAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.moneroHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.moneroHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runMoneroEndpointReachabilityDiagnostics() async {
        guard !isCheckingMoneroEndpointHealth else { return }
        isCheckingMoneroEndpointHealth = true
        defer { isCheckingMoneroEndpointHealth = false }

        guard let baseURL = MoneroBalanceService.configuredBackendBaseURL() else {
            moneroEndpointHealthResults = [
                BitcoinEndpointHealthResult(
                    endpoint: "monero.backend.baseURL",
                    reachable: false,
                    statusCode: nil,
                    detail: "Monero backend is not configured."
                )
            ]
            moneroEndpointHealthLastUpdatedAt = Date()
            return
        }

        let probeURL = baseURL.appendingPathComponent("v1/monero/balance")
        let probe = await probeHTTP(probeURL, profile: .litecoinDiagnostics)
        moneroEndpointHealthResults = [
            BitcoinEndpointHealthResult(
                endpoint: baseURL.absoluteString,
                reachable: probe.reachable,
                statusCode: probe.statusCode,
                detail: probe.detail
            )
        ]
        moneroEndpointHealthLastUpdatedAt = Date()
    }

    func runSuiHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningSuiHistoryDiagnostics },
            setRunning: { self.isRunningSuiHistoryDiagnostics = $0 },
            chainName: "Sui",
            resolveAddress: { self.resolvedSuiAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.suiHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.suiHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSuiHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningSuiHistoryDiagnostics },
            setRunning: { self.isRunningSuiHistoryDiagnostics = $0 },
            chainName: "Sui",
            resolveAddress: { self.resolvedSuiAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.suiHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.suiHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runAptosHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningAptosHistoryDiagnostics },
            setRunning: { self.isRunningAptosHistoryDiagnostics = $0 },
            chainName: "Aptos",
            resolveAddress: { self.resolvedAptosAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.aptosHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.aptosHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runAptosHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningAptosHistoryDiagnostics },
            setRunning: { self.isRunningAptosHistoryDiagnostics = $0 },
            chainName: "Aptos",
            resolveAddress: { self.resolvedAptosAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.aptosHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.aptosHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTONHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningTONHistoryDiagnostics },
            setRunning: { self.isRunningTONHistoryDiagnostics = $0 },
            chainName: "TON",
            resolveAddress: { self.resolvedTONAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await TONBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tonHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tonHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTONHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningTONHistoryDiagnostics },
            setRunning: { self.isRunningTONHistoryDiagnostics = $0 },
            chainName: "TON",
            resolveAddress: { self.resolvedTONAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await TONBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tonHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tonHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runICPHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningICPHistoryDiagnostics },
            setRunning: { self.isRunningICPHistoryDiagnostics = $0 },
            chainName: "Internet Computer",
            resolveAddress: { self.resolvedICPAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.icpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.icpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runICPHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningICPHistoryDiagnostics },
            setRunning: { self.isRunningICPHistoryDiagnostics = $0 },
            chainName: "Internet Computer",
            resolveAddress: { self.resolvedICPAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.icpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.icpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runNearHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningNearHistoryDiagnostics },
            setRunning: { self.isRunningNearHistoryDiagnostics = $0 },
            chainName: "NEAR",
            resolveAddress: { self.resolvedNearAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.nearHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.nearHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runNearHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningNearHistoryDiagnostics },
            setRunning: { self.isRunningNearHistoryDiagnostics = $0 },
            chainName: "NEAR",
            resolveAddress: { self.resolvedNearAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.nearHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.nearHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runPolkadotHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningPolkadotHistoryDiagnostics },
            setRunning: { self.isRunningPolkadotHistoryDiagnostics = $0 },
            chainName: "Polkadot",
            resolveAddress: { self.resolvedPolkadotAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.polkadotHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.polkadotHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runPolkadotHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningPolkadotHistoryDiagnostics },
            setRunning: { self.isRunningPolkadotHistoryDiagnostics = $0 },
            chainName: "Polkadot",
            resolveAddress: { self.resolvedPolkadotAddress(for: $0) },
            fetchDiagnostics: { address in
                let result = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
                return result.diagnostics
            },
            storeDiagnostics: { walletID, diagnostics in
                self.polkadotHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.polkadotHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    private func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(
        isRunning: () -> Bool,
        setRunning: (Bool) -> Void,
        chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics,
        storeDiagnostics: (UUID, Diagnostics) -> Void,
        markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        setRunning(true)
        defer { setRunning(false) }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName,
                  let address = resolveAddress(wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            markUpdated()
            return
        }

        for (wallet, address) in walletsToRefresh {
            let diagnostics = await fetchDiagnostics(address)
            storeDiagnostics(wallet.id, diagnostics)
        }
        markUpdated()
    }

    private func runAddressHistoryDiagnosticsForWallet<Diagnostics>(
        walletID: UUID,
        isRunning: () -> Bool,
        setRunning: (Bool) -> Void,
        chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics,
        storeDiagnostics: (UUID, Diagnostics) -> Void,
        markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == chainName,
              let address = resolveAddress(wallet) else { return }

        setRunning(true)
        defer { setRunning(false) }

        let diagnostics = await fetchDiagnostics(address)
        storeDiagnostics(wallet.id, diagnostics)
        markUpdated()
    }

    func runSuiEndpointReachabilityDiagnostics() async {
        guard !isCheckingSuiEndpointHealth else { return }
        isCheckingSuiEndpointHealth = true
        defer { isCheckingSuiEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: SuiBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.suiEndpointHealthResults = $0 },
            markUpdated: { self.suiEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runAptosEndpointReachabilityDiagnostics() async {
        guard !isCheckingAptosEndpointHealth else { return }
        isCheckingAptosEndpointHealth = true
        defer { isCheckingAptosEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: AptosBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.aptosEndpointHealthResults = $0 },
            markUpdated: { self.aptosEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runTONEndpointReachabilityDiagnostics() async {
        guard !isCheckingTONEndpointHealth else { return }
        isCheckingTONEndpointHealth = true
        defer { isCheckingTONEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: TONBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.tonEndpointHealthResults = $0 },
            markUpdated: { self.tonEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runICPEndpointReachabilityDiagnostics() async {
        guard !isCheckingICPEndpointHealth else { return }
        isCheckingICPEndpointHealth = true
        defer { isCheckingICPEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: ICPBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.icpEndpointHealthResults = $0 },
            markUpdated: { self.icpEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runNearEndpointReachabilityDiagnostics() async {
        guard !isCheckingNearEndpointHealth else { return }
        isCheckingNearEndpointHealth = true
        defer { isCheckingNearEndpointHealth = false }

        var results: [BitcoinEndpointHealthResult] = []
        let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())

        for (endpoint, probeURL) in NearBalanceService.diagnosticsChecks() {
            if rpcEndpoints.contains(endpoint) {
                guard let url = URL(string: endpoint) else {
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: false,
                            statusCode: nil,
                            detail: "Invalid URL"
                        )
                    )
                    continue
                }
                do {
                    let payload = try JSONSerialization.data(withJSONObject: [
                        "jsonrpc": "2.0",
                        "id": "spectra-near-health",
                        "method": "status",
                        "params": []
                    ])
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 15
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = payload
                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                    let detail = reachable
                        ? "OK"
                        : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: reachable,
                            statusCode: http?.statusCode,
                            detail: detail
                        )
                    )
                } catch {
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: false,
                            statusCode: nil,
                            detail: error.localizedDescription
                        )
                    )
                }
                continue
            }

            guard let url = URL(string: probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probe = await probeHTTP(url, profile: .litecoinDiagnostics)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }

        nearEndpointHealthResults = results
        nearEndpointHealthLastUpdatedAt = Date()
    }

    func runPolkadotEndpointReachabilityDiagnostics() async {
        guard !isCheckingPolkadotEndpointHealth else { return }
        isCheckingPolkadotEndpointHealth = true
        defer { isCheckingPolkadotEndpointHealth = false }

        var results: [BitcoinEndpointHealthResult] = []

        for (endpoint, probeURL) in PolkadotBalanceService.diagnosticsChecks() {
            if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                guard let url = URL(string: probeURL) else {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                    continue
                }
                do {
                    let (_, response) = try await ProviderHTTP.data(from: url, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } ?? false
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: reachable ? "OK" : "HTTP \(http?.statusCode ?? -1)"))
                } catch {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
                }
                continue
            }

            guard let url = URL(string: endpoint) else {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            do {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0",
                    "id": "spectra-dot-health",
                    "method": "chain_getHeader",
                    "params": []
                ])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                let http = response as? HTTPURLResponse
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                let detail = reachable ? "OK" : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: detail))
            } catch {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
            }
        }

        polkadotEndpointHealthResults = results
        polkadotEndpointHealthLastUpdatedAt = Date()
    }

    func runEthereumHistoryDiagnostics() async {
        guard !isRunningEthereumHistoryDiagnostics else { return }
        isRunningEthereumHistoryDiagnostics = true
        defer { isRunningEthereumHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Ethereum",
                  let ethereumAddress = resolvedEthereumAddress(for: wallet) else {
                return nil
            }
            return (wallet, ethereumAddress)
        }
        guard !walletsToRefresh.isEmpty else {
            ethereumHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEthereumRPCEndpointURL()
        for (wallet, address) in walletsToRefresh {
            ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            ethereumHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150
                    )
                }
                ethereumHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        ethereumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runEthereumHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningEthereumHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Ethereum",
              let address = resolvedEthereumAddress(for: wallet) else { return }

        isRunningEthereumHistoryDiagnostics = true
        defer { isRunningEthereumHistoryDiagnostics = false }

        let rpcEndpoint = configuredEthereumRPCEndpointURL()
        ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
            address: EthereumWalletEngine.normalizeAddress(address),
            rpcTransferCount: 0,
            rpcError: "Running...",
            blockscoutTransferCount: 0,
            blockscoutError: nil,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "running"
        )
        ethereumHistoryDiagnosticsLastUpdatedAt = Date()

        do {
            let result = try await withTimeout(seconds: 20) {
                try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                    for: address,
                    rpcEndpoint: rpcEndpoint,
                    etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                    maxResults: 150
                )
            }
            ethereumHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
        } catch {
            ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: error.localizedDescription,
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "none"
            )
        }
        ethereumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runETCHistoryDiagnostics() async {
        guard !isRunningETCHistoryDiagnostics else { return }
        isRunningETCHistoryDiagnostics = true
        defer { isRunningETCHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Ethereum Classic",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Ethereum Classic") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            etcHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "Ethereum Classic")
        for (wallet, address) in walletsToRefresh {
            etcHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            etcHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        chain: .ethereumClassic
                    )
                }
                etcHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                etcHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        etcHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBNBHistoryDiagnostics() async {
        guard !isRunningBNBHistoryDiagnostics else { return }
        isRunningBNBHistoryDiagnostics = true
        defer { isRunningBNBHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "BNB Chain",
                  let address = resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bnbHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "BNB Chain")
        for (wallet, address) in walletsToRefresh {
            bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            bnbHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        chain: .bnb
                    )
                }
                bnbHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        bnbHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runArbitrumHistoryDiagnostics() async {
        guard !isRunningArbitrumHistoryDiagnostics else { return }
        isRunningArbitrumHistoryDiagnostics = true
        defer { isRunningArbitrumHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Arbitrum",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Arbitrum") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            arbitrumHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "Arbitrum")
        for (wallet, address) in walletsToRefresh {
            arbitrumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            arbitrumHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        trackedTokens: self.enabledArbitrumTrackedTokens(),
                        chain: .arbitrum
                    )
                }
                arbitrumHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                arbitrumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        arbitrumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runOptimismHistoryDiagnostics() async {
        guard !isRunningOptimismHistoryDiagnostics else { return }
        isRunningOptimismHistoryDiagnostics = true
        defer { isRunningOptimismHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Optimism",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Optimism") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            optimismHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "Optimism")
        for (wallet, address) in walletsToRefresh {
            optimismHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            optimismHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        trackedTokens: self.enabledOptimismTrackedTokens(),
                        chain: .optimism
                    )
                }
                optimismHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                optimismHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        optimismHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runAvalancheHistoryDiagnostics() async {
        guard !isRunningAvalancheHistoryDiagnostics else { return }
        isRunningAvalancheHistoryDiagnostics = true
        defer { isRunningAvalancheHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Avalanche",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Avalanche") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            avalancheHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "Avalanche")
        for (wallet, address) in walletsToRefresh {
            avalancheHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            avalancheHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        chain: .avalanche
                    )
                }
                avalancheHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                avalancheHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        avalancheHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runHyperliquidHistoryDiagnostics() async {
        guard !isRunningHyperliquidHistoryDiagnostics else { return }
        isRunningHyperliquidHistoryDiagnostics = true
        defer { isRunningHyperliquidHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Hyperliquid",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Hyperliquid") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "Hyperliquid")
        for (wallet, address) in walletsToRefresh {
            hyperliquidHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let result = try await withTimeout(seconds: 20) {
                    try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                        for: address,
                        rpcEndpoint: rpcEndpoint,
                        etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                        maxResults: 150,
                        trackedTokens: self.enabledHyperliquidTrackedTokens(),
                        chain: .hyperliquid
                    )
                }
                hyperliquidHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
            } catch {
                hyperliquidHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: EthereumWalletEngine.normalizeAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBNBHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningBNBHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "BNB Chain",
              let address = resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else { return }

        isRunningBNBHistoryDiagnostics = true
        defer { isRunningBNBHistoryDiagnostics = false }

        let rpcEndpoint = configuredEVMRPCEndpointURL(for: "BNB Chain")
        bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
            address: EthereumWalletEngine.normalizeAddress(address),
            rpcTransferCount: 0,
            rpcError: "Running...",
            blockscoutTransferCount: 0,
            blockscoutError: nil,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "running"
        )
        bnbHistoryDiagnosticsLastUpdatedAt = Date()

        do {
            let result = try await withTimeout(seconds: 20) {
                try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryWithDiagnostics(
                    for: address,
                    rpcEndpoint: rpcEndpoint,
                    etherscanAPIKey: self.normalizedEtherscanAPIKey(),
                    maxResults: 150,
                    chain: .bnb
                )
            }
            bnbHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
        } catch {
            bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: EthereumWalletEngine.normalizeAddress(address),
                rpcTransferCount: 0,
                rpcError: error.localizedDescription,
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "none"
            )
        }
        bnbHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !isCheckingEthereumEndpointHealth else { return }
        isCheckingEthereumEndpointHealth = true
        defer { isCheckingEthereumEndpointHealth = false }

        let context = evmChainContext(for: "Ethereum") ?? .ethereum
        var checks = evmEndpointChecks(chainName: "Ethereum", context: context)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.ethereumChainName).map { ($0.0, $0.1, false) })

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.ethereumEndpointHealthResults = $0 },
            markUpdated: { self.ethereumEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runETCEndpointReachabilityDiagnostics() async {
        guard !isCheckingETCEndpointHealth else { return }
        isCheckingETCEndpointHealth = true
        defer { isCheckingETCEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Ethereum Classic", context: .ethereumClassic)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.etcEndpointHealthResults = $0 },
            markUpdated: { self.etcEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBNBEndpointReachabilityDiagnostics() async {
        guard !isCheckingBNBEndpointHealth else { return }
        isCheckingBNBEndpointHealth = true
        defer { isCheckingBNBEndpointHealth = false }

        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.bnbChainName).map { ($0.0, $0.1, false) })

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.bnbEndpointHealthResults = $0 },
            markUpdated: { self.bnbEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runArbitrumEndpointReachabilityDiagnostics() async {
        guard !isCheckingArbitrumEndpointHealth else { return }
        isCheckingArbitrumEndpointHealth = true
        defer { isCheckingArbitrumEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Arbitrum", context: .arbitrum)
        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.arbitrumEndpointHealthResults = $0 },
            markUpdated: { self.arbitrumEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runOptimismEndpointReachabilityDiagnostics() async {
        guard !isCheckingOptimismEndpointHealth else { return }
        isCheckingOptimismEndpointHealth = true
        defer { isCheckingOptimismEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Optimism", context: .optimism)
        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.optimismEndpointHealthResults = $0 },
            markUpdated: { self.optimismEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runAvalancheEndpointReachabilityDiagnostics() async {
        guard !isCheckingAvalancheEndpointHealth else { return }
        isCheckingAvalancheEndpointHealth = true
        defer { isCheckingAvalancheEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Avalanche", context: .avalanche)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.avalancheEndpointHealthResults = $0 },
            markUpdated: { self.avalancheEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runHyperliquidEndpointReachabilityDiagnostics() async {
        guard !isCheckingHyperliquidEndpointHealth else { return }
        isCheckingHyperliquidEndpointHealth = true
        defer { isCheckingHyperliquidEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Hyperliquid", context: .hyperliquid)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.hyperliquidEndpointHealthResults = $0 },
            markUpdated: { self.hyperliquidEndpointHealthLastUpdatedAt = Date() }
        )
    }

    private func evmEndpointChecks(
        chainName: String,
        context: EVMChainContext
    ) -> [(label: String, endpoint: URL, isRPC: Bool)] {
        var checks: [(label: String, endpoint: URL, isRPC: Bool)] = []
        if let configured = configuredEVMRPCEndpointURL(for: chainName) {
            checks.append(("Configured RPC", configured, true))
        }
        for rpc in context.defaultRPCEndpoints {
            guard let url = URL(string: rpc),
                  !checks.contains(where: { $0.endpoint == url }) else {
                continue
            }
            checks.append(("Fallback RPC", url, true))
        }
        return checks
    }

    private func runSimpleEndpointReachabilityDiagnostics(
        checks: [(endpoint: String, probeURL: String)],
        profile: NetworkRetryProfile,
        setResults: ([BitcoinEndpointHealthResult]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [BitcoinEndpointHealthResult] = []
        for check in checks {
            guard let url = URL(string: check.probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: check.endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: check.endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }

    private func runLabeledEVMEndpointDiagnostics(
        checks: [(label: String, endpoint: URL, isRPC: Bool)],
        setResults: ([EthereumEndpointHealthResult]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [EthereumEndpointHealthResult] = []
        for check in checks {
            let probe: (reachable: Bool, statusCode: Int?, detail: String)
            if check.isRPC {
                probe = await probeEthereumRPC(check.endpoint)
            } else {
                probe = await probeHTTP(check.endpoint)
            }
            results.append(
                EthereumEndpointHealthResult(
                    label: check.label,
                    endpoint: check.endpoint.absoluteString,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }

    // Utility wrapper to cap the duration of provider/network calls during refresh.
    func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut(seconds: seconds)
            }

            guard let firstResult = try await group.next() else {
                throw TimeoutError.timedOut(seconds: seconds)
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func probeHTTP(
        _ url: URL,
        profile: NetworkRetryProfile = .diagnostics
    ) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (_, response) = try await NetworkResilience.data(for: request, profile: profile)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                if let statusCode {
                    let isSuccess = (200 ..< 300).contains(statusCode)
                    return (isSuccess, statusCode, "HTTP \(statusCode)")
                }
                return (true, nil, "Connected")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    private func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = """
                {"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}
                """.data(using: .utf8)

                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                if let statusCode, (200 ..< 300).contains(statusCode) {
                    let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode ?? -1)")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    func refreshPendingBitcoinTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let walletNetworkMode = transaction.walletID
                    .flatMap { walletID in wallets.first(where: { $0.id == walletID })?.bitcoinNetworkMode }
                    ?? self.bitcoinNetworkMode
                let status = try await BitcoinBalanceService.fetchTransactionStatus(txid: transactionHash, networkMode: walletNetworkMode)
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: status.blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingBitcoinCashTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin Cash"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let status = try await BitcoinCashBalanceService.fetchTransactionStatus(txid: transactionHash)
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: status.blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingBitcoinSVTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin SV"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let status = try await BitcoinSVBalanceService.fetchTransactionStatus(txid: transactionHash)
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: status.blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingLitecoinTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.chainName == "Litecoin"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let status = try await LitecoinBalanceService.fetchTransactionStatus(txid: transactionHash)
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: status.blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    // Updates status/confirmations for pending DOGE sends and records operational telemetry.
    func refreshPendingDogecoinTransactions() async {
        let now = Date()
        let trackedTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Dogecoin"
                && (transaction.status == .pending || transaction.status == .confirmed)
                && transaction.transactionHash != nil
        }

        guard !trackedTransactions.isEmpty else {
            dogecoinStatusTrackingByTransactionID = [:]
            return
        }

        let trackedIDs = Set(trackedTransactions.map(\.id))
        dogecoinStatusTrackingByTransactionID = dogecoinStatusTrackingByTransactionID.filter { trackedIDs.contains($0.key) }

        var resolvedStatuses: [UUID: DogecoinTransactionStatus] = [:]

        for transaction in trackedTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }

            if !shouldPollDogecoinStatus(for: transaction, now: now) {
                continue
            }

            do {
                let walletNetworkMode = transaction.walletID
                    .flatMap { walletID in wallets.first(where: { $0.id == walletID })?.dogecoinNetworkMode }
                    ?? dogecoinNetworkMode
                let status = try await DogecoinBalanceService.fetchTransactionStatus(txid: transactionHash, networkMode: walletNetworkMode)
                resolvedStatuses[transaction.id] = status
                markDogecoinStatusPollSuccess(
                    for: transaction,
                    status: status,
                    now: now
                )
            } catch {
                markDogecoinStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let staleFailureCandidates = trackedTransactions.filter { transaction in
            guard transaction.status == .pending else { return false }
            let age = now.timeIntervalSince(transaction.createdAt)
            guard age >= Self.pendingFailureTimeoutSeconds else { return false }
            let tracker = dogecoinStatusTrackingByTransactionID[transaction.id]
            return (tracker?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures
        }
        let staleFailureIDs = Set(staleFailureCandidates.map { $0.id })

        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }

        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        transactions = transactions.map { transaction in
            if let status = resolvedStatuses[transaction.id] {
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                let resolvedConfirmations = status.confirmations ?? transaction.dogecoinConfirmations
                let reachedFinality = (resolvedConfirmations ?? 0) >= Self.standardFinalityConfirmations
                if reachedFinality {
                    var tracker = dogecoinStatusTrackingByTransactionID[transaction.id] ?? DogecoinStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = true
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    dogecoinStatusTrackingByTransactionID[transaction.id] = tracker
                }

                return TransactionRecord(
                    id: transaction.id,
                    walletID: transaction.walletID,
                    kind: transaction.kind,
                    status: resolvedStatus,
                    walletName: transaction.walletName,
                    assetName: transaction.assetName,
                    symbol: transaction.symbol,
                    chainName: transaction.chainName,
                    amount: transaction.amount,
                    address: transaction.address,
                    transactionHash: transaction.transactionHash,
                    receiptBlockNumber: status.blockHeight,
                    receiptGasUsed: transaction.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
                    feePriorityRaw: transaction.feePriorityRaw,
                    feeRateDescription: transaction.feeRateDescription,
                    confirmationCount: resolvedConfirmations,
                    dogecoinConfirmedNetworkFeeDOGE: status.networkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: resolvedConfirmations,
                    dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: transaction.usedChangeOutput,
                    dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
                    dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
                    failureReason: nil,
                    transactionHistorySource: transaction.transactionHistorySource,
                    createdAt: transaction.createdAt
                )
            }

            guard staleFailureIDs.contains(transaction.id) else { return transaction }

            return TransactionRecord(
                id: transaction.id,
                walletID: transaction.walletID,
                kind: transaction.kind,
                status: .failed,
                walletName: transaction.walletName,
                assetName: transaction.assetName,
                symbol: transaction.symbol,
                chainName: transaction.chainName,
                amount: transaction.amount,
                address: transaction.address,
                transactionHash: transaction.transactionHash,
                receiptBlockNumber: transaction.receiptBlockNumber,
                receiptGasUsed: transaction.receiptGasUsed,
                receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
                receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
                feePriorityRaw: transaction.feePriorityRaw,
                feeRateDescription: transaction.feeRateDescription,
                confirmationCount: transaction.confirmationCount,
                dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
                dogecoinConfirmations: transaction.dogecoinConfirmations,
                dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
                dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
                usedChangeOutput: transaction.usedChangeOutput,
                dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
                dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
                failureReason: transaction.failureReason ?? localizedStoreString("Dogecoin transaction appears stuck and could not be confirmed after extended retries."),
                transactionHistorySource: transaction.transactionHistorySource,
                createdAt: transaction.createdAt
            )
        }

        for (transactionID, status) in resolvedStatuses {
            guard let oldTransaction = oldByID[transactionID],
                  let newTransaction = transactions.first(where: { $0.id == transactionID }) else {
                continue
            }

            if oldTransaction.status != .confirmed, status.confirmed {
                appendChainOperationalEvent(
                    .info,
                    chainName: "Dogecoin",
                    message: localizedStoreString("DOGE transaction confirmed."),
                    transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }

            if oldTransaction.dogecoinConfirmations != newTransaction.dogecoinConfirmations,
               newTransaction.status == .confirmed,
               let confirmations = newTransaction.dogecoinConfirmations,
               confirmations >= Self.standardFinalityConfirmations,
               oldTransaction.dogecoinConfirmations ?? 0 < Self.standardFinalityConfirmations {
                appendChainOperationalEvent(
                    .info,
                    chainName: "Dogecoin",
                    message: localizedStoreFormat("DOGE transaction reached finality (%d confirmations).", confirmations),
                    transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }
        }

        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID],
                  oldTransaction.status != .failed else {
                continue
            }
            appendChainOperationalEvent(
                .error,
                chainName: "Dogecoin",
                message: localizedStoreString("DOGE transaction marked failed after extended retries."),
                transactionHash: oldTransaction.transactionHash
            )
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }
    }

    func refreshPendingTronTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Tron",
            addressResolver: { self.resolvedTronAddress(for: $0) }
        ) { address in
            let result = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingSolanaTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Solana",
            addressResolver: { self.resolvedSolanaAddress(for: $0) }
        ) { address in
            let result = await SolanaBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingCardanoTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Cardano",
            addressResolver: { self.resolvedCardanoAddress(for: $0) }
        ) { address in
            let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingXRPTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "XRP Ledger",
            addressResolver: { self.resolvedXRPAddress(for: $0) }
        ) { address in
            let result = await XRPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingStellarTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Stellar",
            addressResolver: { self.resolvedStellarAddress(for: $0) }
        ) { address in
            let result = await StellarBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingMoneroTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Monero",
            addressResolver: { self.resolvedMoneroAddress(for: $0) }
        ) { address in
            let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingSuiTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Sui",
            addressResolver: { self.resolvedSuiAddress(for: $0) }
        ) { address in
            let result = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingAptosTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Aptos",
            addressResolver: { self.resolvedAptosAddress(for: $0) }
        ) { address in
            let result = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingTONTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "TON",
            addressResolver: { self.resolvedTONAddress(for: $0) }
        ) { address in
            let result = await TONBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingICPTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Internet Computer",
            addressResolver: { self.resolvedICPAddress(for: $0) }
        ) { address in
            let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingNearTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "NEAR",
            addressResolver: { self.resolvedNearAddress(for: $0) }
        ) { address in
            let result = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    func refreshPendingPolkadotTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Polkadot",
            addressResolver: { self.resolvedPolkadotAddress(for: $0) }
        ) { address in
            let result = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: 80)
            let statusByHash = self.statusMapByTransactionHash(from: result.snapshots, hash: \.transactionHash, status: \.status)
            return (statusByHash, result.diagnostics.error != nil)
        }
    }

    // MARK: - Operational Logs and Telemetry
    // Clears user-visible runtime telemetry logs in Settings.
    // This does not affect wallet data, balances, or transaction history.
    func clearOperationalLogs() {
        diagnostics.clearOperationalLogs()
    }

    var networkSyncStatusText: String {
        let reachability = isNetworkReachable ? localizedStoreString("reachable") : localizedStoreString("offline")
        let constrained = isConstrainedNetwork ? localizedStoreString("constrained") : localizedStoreString("unconstrained")
        let expensive = isExpensiveNetwork ? localizedStoreString("expensive") : localizedStoreString("non-expensive")
        return localizedStoreFormat(
            "Network: %@, %@, %@ • Auto refresh: %d min",
            reachability,
            constrained,
            expensive,
            automaticRefreshFrequencyMinutes
        )
    }

    // Produces a plain-text export suitable for support/debug sharing.
    // Output is chronologically ordered and includes level/category/source context.
    func exportOperationalLogsText(events: [OperationalLogEvent]? = nil) -> String {
        diagnostics.exportOperationalLogsText(
            networkSyncStatusText: networkSyncStatusText,
            events: events
        )
    }

    // Central structured log sink used by diagnostics page and export.
    func appendOperationalLog(
        _ level: OperationalLogEvent.Level,
        category: String,
        message: String,
        chainName: String? = nil,
        walletID: UUID? = nil,
        transactionHash: String? = nil,
        source: String? = nil,
        metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level,
            category: category,
            message: message,
            chainName: chainName,
            walletID: walletID,
            transactionHash: transactionHash,
            source: source,
            metadata: metadata
        )
    }

    func appendChainOperationalEvent(
        _ level: ChainOperationalEvent.Level,
        chainName: String,
        message: String,
        transactionHash: String? = nil
    ) {
        let event = ChainOperationalEvent(
            id: UUID(),
            timestamp: Date(),
            chainName: chainName,
            level: level,
            message: message,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var events = chainOperationalEventsByChain[chainName] ?? []
        events.insert(event, at: 0)
        if events.count > 200 {
            events = Array(events.prefix(200))
        }
        chainOperationalEventsByChain[chainName] = events

        let mappedLevel: OperationalLogEvent.Level
        switch level {
        case .info:
            mappedLevel = .info
        case .warning:
            mappedLevel = .warning
        case .error:
            mappedLevel = .error
        }
        appendOperationalLog(
            mappedLevel,
            category: "\(chainName) Broadcast",
            message: message,
            chainName: chainName,
            transactionHash: transactionHash
        )
    }

    func loadChainOperationalEvents() -> [String: [ChainOperationalEvent]] {
        guard let data = UserDefaults.standard.data(forKey: Self.chainOperationalEventsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [ChainOperationalEvent]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistChainOperationalEvents() {
        guard let data = try? JSONEncoder().encode(chainOperationalEventsByChain) else { return }
        UserDefaults.standard.set(data, forKey: Self.chainOperationalEventsDefaultsKey)
    }

    private func noteSendBroadcastQueued(for transaction: TransactionRecord) {
        appendChainOperationalEvent(
            .info,
            chainName: transaction.chainName,
            message: "\(transaction.symbol) send broadcast accepted.",
            transactionHash: transaction.transactionHash
        )
    }

    private func noteSendBroadcastVerification(
        chainName: String,
        verificationStatus: SendBroadcastVerificationStatus,
        transactionHash: String?
    ) {
        switch verificationStatus {
        case .verified:
            appendChainOperationalEvent(
                .info,
                chainName: chainName,
                message: "Broadcast verified by provider.",
                transactionHash: transactionHash
            )
        case .deferred:
            appendChainOperationalEvent(
                .warning,
                chainName: chainName,
                message: "Broadcast accepted; verification deferred.",
                transactionHash: transactionHash
            )
        case .failed(let message):
            appendChainOperationalEvent(
                .warning,
                chainName: chainName,
                message: "Broadcast verification warning: \(message)",
                transactionHash: transactionHash
            )
        }
    }

    func noteSendBroadcastFailure(for chainName: String, message: String) {
        appendChainOperationalEvent(.error, chainName: chainName, message: "Send failed: \(message)")
    }

    func decoratePendingSendTransaction(
        _ transaction: TransactionRecord,
        holding: Coin,
        confirmationCount: Int? = 0
    ) -> TransactionRecord {
        let previewDetails = sendPreviewDetails(for: holding)
        return TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: transaction.status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw ?? feePriorityOption(for: holding.chainName).rawValue,
            feeRateDescription: transaction.feeRateDescription ?? previewDetails?.feeRateDescription,
            confirmationCount: transaction.confirmationCount ?? confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput ?? previewDetails?.usesChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
    }

    private func registerPendingSelfSendConfirmation(
        walletID: UUID,
        chainName: String,
        symbol: String,
        destinationAddress: String,
        amount: Double
    ) {
        pendingSelfSendConfirmation = PendingSelfSendConfirmation(
            walletID: walletID,
            chainName: chainName,
            symbol: symbol,
            destinationAddressLowercased: destinationAddress.lowercased(),
            amount: amount,
            createdAt: Date()
        )
    }

    private func consumePendingSelfSendConfirmation(
        walletID: UUID,
        chainName: String,
        symbol: String,
        destinationAddress: String,
        amount: Double
    ) -> Bool {
        guard let pendingSelfSendConfirmation else { return false }

        let isExpired = Date().timeIntervalSince(pendingSelfSendConfirmation.createdAt) > Self.selfSendConfirmationWindowSeconds
        guard !isExpired else {
            self.pendingSelfSendConfirmation = nil
            return false
        }

        let sameWallet = pendingSelfSendConfirmation.walletID == walletID
        let sameChain = pendingSelfSendConfirmation.chainName == chainName
        let sameSymbol = pendingSelfSendConfirmation.symbol == symbol
        let sameDestination = pendingSelfSendConfirmation.destinationAddressLowercased == destinationAddress.lowercased()
        let sameAmount = abs(pendingSelfSendConfirmation.amount - amount) < 0.00000001
        guard sameWallet, sameChain, sameSymbol, sameDestination, sameAmount else {
            self.pendingSelfSendConfirmation = nil
            return false
        }

        self.pendingSelfSendConfirmation = nil
        return true
    }

    func requiresSelfSendConfirmation(
        wallet: ImportedWallet,
        holding: Coin,
        destinationAddress: String,
        amount: Double
    ) -> Bool {
        let ownAddressSet: Set<String>
        if holding.chainName == "Dogecoin" {
            ownAddressSet = Set(knownDogecoinAddresses(for: wallet).map { $0.lowercased() })
        } else {
            ownAddressSet = Set(knownOwnedAddresses(for: wallet.id).map { $0.lowercased() })
        }
        guard ownAddressSet.contains(destinationAddress.lowercased()) else { return false }

        if consumePendingSelfSendConfirmation(
            walletID: wallet.id,
            chainName: holding.chainName,
            symbol: holding.symbol,
            destinationAddress: destinationAddress,
            amount: amount
        ) {
            return false
        }

        registerPendingSelfSendConfirmation(
            walletID: wallet.id,
            chainName: holding.chainName,
            symbol: holding.symbol,
            destinationAddress: destinationAddress,
            amount: amount
        )
        sendError = "This \(holding.symbol) destination belongs to your wallet. Tap Send again within \(Int(Self.selfSendConfirmationWindowSeconds))s to confirm intentional self-send."
        if holding.chainName == "Dogecoin" {
            appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE self-send confirmation required.")
        }
        return true
    }

    private func finalityConfirmations(for chainName: String) -> Int {
        Self.standardFinalityConfirmations
    }

    private func updatedTransaction(
        _ transaction: TransactionRecord,
        status: TransactionStatus,
        receiptBlockNumber: Int? = nil,
        failureReason: String? = nil,
        dogecoinConfirmations: Int? = nil,
        dogecoinConfirmedNetworkFeeDOGE: Double? = nil
    ) -> TransactionRecord {
        TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: receiptBlockNumber ?? transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw,
            feeRateDescription: transaction.feeRateDescription,
            confirmationCount: dogecoinConfirmations ?? transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations ?? transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
    }

    private func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        localizedStoreFormat(
            "%@ transaction appears stuck and could not be confirmed after extended retries.",
            transaction.chainName
        )
    }

    private func shouldPollTransactionStatus(for transaction: TransactionRecord, now: Date) -> Bool {
        let tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        if tracker.reachedFinality {
            return false
        }
        return now >= tracker.nextCheckAt
    }

    private func markTransactionStatusPollSuccess(
        for transaction: TransactionRecord,
        resolvedStatus: TransactionStatus,
        confirmations: Int? = nil,
        now: Date
    ) {
        var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        tracker.lastCheckedAt = now
        tracker.consecutiveFailures = 0

        let reachedFinality: Bool
        if resolvedStatus == .pending {
            reachedFinality = false
        } else {
            reachedFinality = (confirmations ?? finalityConfirmations(for: transaction.chainName)) >= finalityConfirmations(for: transaction.chainName)
        }

        if reachedFinality {
            tracker.reachedFinality = true
            tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
        } else if resolvedStatus == .confirmed {
            tracker.nextCheckAt = now.addingTimeInterval(Self.confirmedStatusPollSeconds)
        } else {
            tracker.nextCheckAt = now.addingTimeInterval(Self.pendingStatusPollSeconds)
        }

        statusTrackingByTransactionID[transaction.id] = tracker
    }

    private func markTransactionStatusPollFailure(for transaction: TransactionRecord, now: Date) {
        var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        tracker.lastCheckedAt = now
        tracker.consecutiveFailures += 1

        let exponentialBackoff = min(
            Self.pendingStatusPollSeconds * pow(2, Double(max(0, tracker.consecutiveFailures - 1))),
            Self.statusPollBackoffMaxSeconds
        )
        tracker.nextCheckAt = now.addingTimeInterval(exponentialBackoff)
        statusTrackingByTransactionID[transaction.id] = tracker
    }

    private func stalePendingFailureIDs(from trackedTransactions: [TransactionRecord], now: Date) -> Set<UUID> {
        Set(
            trackedTransactions.compactMap { transaction in
                guard transaction.status == .pending else { return nil }
                let age = now.timeIntervalSince(transaction.createdAt)
                guard age >= Self.pendingFailureTimeoutSeconds else { return nil }
                let tracker = statusTrackingByTransactionID[transaction.id]
                guard (tracker?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures else { return nil }
                return transaction.id
            }
        )
    }

    private func applyResolvedPendingTransactionStatuses(
        _ resolvedStatuses: [UUID: PendingTransactionStatusResolution],
        staleFailureIDs: Set<UUID>,
        now: Date
    ) {
        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }

        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        transactions = transactions.map { transaction in
            if let resolution = resolvedStatuses[transaction.id] {
                if resolution.status != .pending {
                    var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = (resolution.confirmations ?? finalityConfirmations(for: transaction.chainName)) >= finalityConfirmations(for: transaction.chainName)
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    statusTrackingByTransactionID[transaction.id] = tracker
                }
                return updatedTransaction(
                    transaction,
                    status: resolution.status,
                    receiptBlockNumber: resolution.receiptBlockNumber,
                    failureReason: resolution.status == .failed ? (transaction.failureReason ?? statusPollFailureMessage(for: transaction)) : nil,
                    dogecoinConfirmations: resolution.confirmations,
                    dogecoinConfirmedNetworkFeeDOGE: resolution.dogecoinNetworkFeeDOGE
                )
            }

            guard staleFailureIDs.contains(transaction.id) else { return transaction }
            return updatedTransaction(
                transaction,
                status: .failed,
                failureReason: transaction.failureReason ?? statusPollFailureMessage(for: transaction)
            )
        }

        for (transactionID, resolution) in resolvedStatuses {
            guard let oldTransaction = oldByID[transactionID],
                  let newTransaction = transactions.first(where: { $0.id == transactionID }),
                  oldTransaction.status != newTransaction.status else {
                continue
            }
            if resolution.status == .confirmed {
                appendChainOperationalEvent(
                    .info,
                    chainName: newTransaction.chainName,
                    message: "Transaction confirmed on-chain.",
                    transactionHash: newTransaction.transactionHash
                )
            } else if resolution.status == .failed {
                appendChainOperationalEvent(
                    .error,
                    chainName: newTransaction.chainName,
                    message: newTransaction.failureReason ?? statusPollFailureMessage(for: newTransaction),
                    transactionHash: newTransaction.transactionHash
                )
            }
            sendTransactionStatusNotification(for: oldTransaction, newStatus: resolution.status)
        }

        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID],
                  oldTransaction.status != .failed else {
                continue
            }
            appendChainOperationalEvent(
                .error,
                chainName: oldTransaction.chainName,
                message: oldTransaction.failureReason ?? statusPollFailureMessage(for: oldTransaction),
                transactionHash: oldTransaction.transactionHash
            )
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }
    }

    private func refreshPendingHistoryBackedTransactions(
        chainName: String,
        addressResolver: (ImportedWallet) -> String?,
        fetchStatuses: @escaping (String) async -> ([String: TransactionStatus], Bool)
    ) async {
        let now = Date()
        let trackedTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }
        guard !trackedTransactions.isEmpty else { return }

        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let groupedTransactions = Dictionary(grouping: trackedTransactions) { transaction in
            transaction.walletID.flatMap { walletsByID[$0] }.flatMap(addressResolver)
        }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for (address, group) in groupedTransactions {
            guard let address else { continue }
            let (statusByHash, hadError) = await fetchStatuses(address)
            if hadError {
                for transaction in group {
                    markTransactionStatusPollFailure(for: transaction, now: now)
                }
                continue
            }

            for transaction in group {
                guard shouldPollTransactionStatus(for: transaction, now: now),
                      let transactionHash = transaction.transactionHash?.lowercased() else {
                    continue
                }
                let resolvedStatus = statusByHash[transactionHash] ?? .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: nil,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            }
        }

        let staleFailureIDs = stalePendingFailureIDs(from: trackedTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    private func statusMapByTransactionHash<S: Sequence>(
        from snapshots: S,
        hash: (S.Element) -> String,
        status: (S.Element) -> TransactionStatus
    ) -> [String: TransactionStatus] {
        var statusByHash: [String: TransactionStatus] = [:]
        for snapshot in snapshots {
            let transactionHash = hash(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transactionHash.isEmpty else { continue }
            statusByHash[transactionHash.lowercased()] = status(snapshot)
        }
        return statusByHash
    }

    private func shouldPollDogecoinStatus(for transaction: TransactionRecord, now: Date) -> Bool {
        shouldPollTransactionStatus(for: transaction, now: now)
    }

    private func markDogecoinStatusPollSuccess(
        for transaction: TransactionRecord,
        status: DogecoinTransactionStatus,
        now: Date
    ) {
        markTransactionStatusPollSuccess(
            for: transaction,
            resolvedStatus: status.confirmed ? .confirmed : .pending,
            confirmations: status.confirmations ?? transaction.dogecoinConfirmations,
            now: now
        )
    }

    private func markDogecoinStatusPollFailure(for transaction: TransactionRecord, now: Date) {
        markTransactionStatusPollFailure(for: transaction, now: now)
    }

    
    func updateTransactionStatus(id: UUID, to status: TransactionStatus) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { return }
        let transaction = transactions[index]
        if transaction.chainName == "Dogecoin" {
            return
        }
        transactions[index] = TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            receiptBlockNumber: transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw,
            feeRateDescription: transaction.feeRateDescription,
            confirmationCount: transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
    }
    
    func addPriceAlert(for coin: Coin, targetPrice: Double, condition: PriceAlertCondition) {
        let normalizedTargetPrice = (targetPrice * 100).rounded() / 100
        let isDuplicate = priceAlerts.contains { alert in
            alert.holdingKey == coin.holdingKey
                && alert.condition == condition
                && abs(alert.targetPrice - normalizedTargetPrice) < 0.0001
        }
        
        guard !isDuplicate else { return }
        
        let alert = PriceAlertRule(
            holdingKey: coin.holdingKey,
            assetName: coin.name,
            symbol: coin.symbol,
            chainName: coin.chainName,
            targetPrice: normalizedTargetPrice,
            condition: condition
        )
        priceAlerts.insert(alert, at: 0)
        requestPriceAlertNotificationPermission()
    }
    
    func togglePriceAlertEnabled(id: UUID) {
        guard let index = priceAlerts.firstIndex(where: { $0.id == id }) else { return }
        priceAlerts[index].isEnabled.toggle()
        if !priceAlerts[index].isEnabled {
            priceAlerts[index].hasTriggered = false
        }
    }
    
    func removePriceAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
    }

}
