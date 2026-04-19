import Foundation
import SwiftUI
import Combine
import os
import UIKit
#if canImport(Network)
import Network
#endif
@MainActor
class AppState: ObservableObject {
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
    // Nested enums (ResetScope, TimeoutError, SeedPhraseRevealError, BackgroundSyncProfile)
    // moved to Shell/AppStateTypes.swift via `extension AppState`.
    let logger = Logger(subsystem: "com.spectra.wallet", category: "dogecoin")
    let balanceTelemetryLogger = Logger(subsystem: "com.spectra.wallet", category: "balance.telemetry")
    var appSettingsPersistTask: Task<Void, Never>?
    private var priceAlertsPersistTask: Task<Void, Never>?
    private var addressBookPersistTask: Task<Void, Never>?
    private var livePricesPersistTask: Task<Void, Never>?
    private var tokenPreferenceRebuildTask: Task<Void, Never>?
    private var transactionRebuildTask: Task<Void, Never>?
    @Published var transactions: [TransactionRecord] = [] {
        didSet {
            transactionRevision &+= 1
            let old = lastObservedTransactions
            lastObservedTransactions = transactions
            if !suppressSideEffects {
                persistTransactionsDelta(from: old, to: transactions)
                transactionRebuildTask?.cancel()
                transactionRebuildTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000) // 30ms debounce
                    guard !Task.isCancelled, let self else { return }
                    self.rebuildTransactionDerivedState()
                }
            }}}
    @Published var normalizedHistoryIndex: [NormalizedHistoryEntry] = [] {
        didSet { normalizedHistoryRevision &+= 1 }}
    @Published private(set) var transactionRevision: UInt64 = 0
    @Published private(set) var normalizedHistoryRevision: UInt64 = 0
    var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    var cachedFirstActivityDateByWalletID: [String: Date] = [:]
    var lastNormalizedHistorySignature: Int?
    var suppressSideEffects = false
    var lastObservedTransactions: [TransactionRecord] = []
    // Nested value types (event records, persisted-store schemas, keypool / diagnostic
    // structs and associated typealiases) moved to Shell/AppStateTypes.swift.
    @Published var wallets: [ImportedWallet] = [] {
        didSet { walletsRevision &+= 1 }}
    @Published private(set) var walletsRevision: UInt64 = 0
    // Derived caches. Recomputed by `applyWalletCollectionSideEffects`,
    // `rebuildWalletDerivedState`, `rebuildDashboardDerivedState`, and
    // `rebuildTokenPreferenceDerivedState`. Each `didSet` bumps
    // `cachesRevision` so SwiftUI views observing it refresh; bulk rebuilds
    // wrap their work in `batchCacheUpdates` to coalesce into a single bump.
    @Published private(set) var cachesRevision: UInt64 = 0
    private var cacheBatchDepth: Int = 0
    private func bumpCachesRevision() {
        guard cacheBatchDepth == 0 else { return }
        cachesRevision &+= 1
    }
    func batchCacheUpdates(_ block: () -> Void) {
        cacheBatchDepth += 1
        block()
        cacheBatchDepth -= 1
        if cacheBatchDepth == 0 { cachesRevision &+= 1 }
    }
    var cachedWalletByID: [String: ImportedWallet] = [:] { didSet { bumpCachesRevision() } }
    var cachedWalletByIDString: [String: ImportedWallet] = [:] { didSet { bumpCachesRevision() } }
    var cachedIncludedPortfolioWallets: [ImportedWallet] = [] { didSet { bumpCachesRevision() } }
    var cachedIncludedPortfolioHoldings: [Coin] = [] { didSet { bumpCachesRevision() } }
    var cachedIncludedPortfolioHoldingsBySymbol: [String: [Coin]] = [:] { didSet { bumpCachesRevision() } }
    var cachedUniqueWalletPriceRequestCoins: [Coin] = [] { didSet { bumpCachesRevision() } }
    var cachedPortfolio: [Coin] = [] { didSet { bumpCachesRevision() } }
    var cachedAvailableSendCoinsByWalletID: [String: [Coin]] = [:] { didSet { bumpCachesRevision() } }
    var cachedAvailableReceiveCoinsByWalletID: [String: [Coin]] = [:] { didSet { bumpCachesRevision() } }
    var cachedAvailableReceiveChainsByWalletID: [String: [String]] = [:] { didSet { bumpCachesRevision() } }
    var cachedSendEnabledWallets: [ImportedWallet] = [] { didSet { bumpCachesRevision() } }
    var cachedReceiveEnabledWallets: [ImportedWallet] = [] { didSet { bumpCachesRevision() } }
    var cachedRefreshableChainNames: Set<String> = [] { didSet { bumpCachesRevision() } }
    var cachedSigningMaterialWalletIDs: Set<String> = [] { didSet { bumpCachesRevision() } }
    var cachedPrivateKeyBackedWalletIDs: Set<String> = [] { didSet { bumpCachesRevision() } }
    var cachedPasswordProtectedWalletIDs: Set<String> = [] { didSet { bumpCachesRevision() } }
    var cachedSecretDescriptorsByWalletID: [String: CoreWalletRustSecretMaterialDescriptor] = [:] { didSet { bumpCachesRevision() } }
    let importDraft = WalletImportDraft()
    @Published var importError: String? = nil
    @Published var isImportingWallet: Bool = false
    @Published var isShowingWalletImporter: Bool = false
    @Published var isShowingSendSheet: Bool = false
    @Published var isShowingReceiveSheet: Bool = false
    @Published var walletPendingDeletion: ImportedWallet?
    @Published var editingWalletID: String? = nil
    @Published var sendWalletID: String = ""
    @Published var sendHoldingKey: String = ""
    @Published var sendAmount: String = ""
    @Published var sendAddress: String = ""
    @Published var sendError: String? = nil
    @Published var sendDestinationRiskWarning: String? = nil
    @Published var sendDestinationInfoMessage: String? = nil
    @Published var isCheckingSendDestinationBalance: Bool = false
    @Published var pendingHighRiskSendReasons: [String] = []
    @Published var isShowingHighRiskSendConfirmation: Bool = false
    @Published var sendVerificationNotice: String? = nil
    @Published var sendVerificationNoticeIsWarning: Bool = false
    @Published var receiveWalletID: String = ""
    @Published var receiveChainName: String = ""
    @Published var receiveHoldingKey: String = ""
    @Published var receiveResolvedAddress: String = ""
    @Published var isResolvingReceiveAddress: Bool = false
    // Dedicated observable for tab selection — isolates MainTabView from
    // AppState.objectWillChange so swapping tabs doesn't re-render every
    // view that holds `@ObservedObject var store: AppState`.
    let tabSelection = AppTabSelection()
    var selectedMainTab: MainAppTab {
        get { tabSelection.value }
        set { tabSelection.value = newValue }
    }
    @Published var isAppLocked: Bool = false
    @Published var appLockError: String? = nil
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
    var statusTrackingByTransactionID: [UUID: AppState.TransactionStatusTrackingState] = [:]
    var pendingSelfSendConfirmation: AppState.PendingSelfSendConfirmation?
    var activeEthereumSendWalletIDs: Set<String> = []
    var lastSendDestinationProbeKey: String?
    var lastSendDestinationProbeWarning: String?
    var lastSendDestinationProbeInfoMessage: String?
    var cachedResolvedENSAddresses: [String: String] = [:] { didSet { bumpCachesRevision() } }
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
    @Published var lastSentTransaction: TransactionRecord?
    @Published var lastPendingTransactionRefreshAt: Date? = nil
    // Send previews live in a dedicated sub-store so updates during the send flow
    // do not invalidate every view that observes AppState. Views that need the
    // preview values should observe `sendPreviewStore` directly.
    let sendPreviewStore = SendPreviewStore()
    var ethereumSendPreview: EthereumSendPreview? { get { sendPreviewStore.ethereumSendPreview } set { sendPreviewStore.ethereumSendPreview = newValue } }
    var bitcoinSendPreview: BitcoinSendPreview? { get { sendPreviewStore.bitcoinSendPreview } set { sendPreviewStore.bitcoinSendPreview = newValue } }
    var bitcoinCashSendPreview: BitcoinSendPreview? { get { sendPreviewStore.bitcoinCashSendPreview } set { sendPreviewStore.bitcoinCashSendPreview = newValue } }
    var bitcoinSVSendPreview: BitcoinSendPreview? { get { sendPreviewStore.bitcoinSVSendPreview } set { sendPreviewStore.bitcoinSVSendPreview = newValue } }
    var litecoinSendPreview: BitcoinSendPreview? { get { sendPreviewStore.litecoinSendPreview } set { sendPreviewStore.litecoinSendPreview = newValue } }
    var dogecoinSendPreview: DogecoinSendPreview? { get { sendPreviewStore.dogecoinSendPreview } set { sendPreviewStore.dogecoinSendPreview = newValue } }
    var tronSendPreview: TronSendPreview? { get { sendPreviewStore.tronSendPreview } set { sendPreviewStore.tronSendPreview = newValue } }
    var solanaSendPreview: SolanaSendPreview? { get { sendPreviewStore.solanaSendPreview } set { sendPreviewStore.solanaSendPreview = newValue } }
    var xrpSendPreview: XrpSendPreview? { get { sendPreviewStore.xrpSendPreview } set { sendPreviewStore.xrpSendPreview = newValue } }
    var stellarSendPreview: StellarSendPreview? { get { sendPreviewStore.stellarSendPreview } set { sendPreviewStore.stellarSendPreview = newValue } }
    var moneroSendPreview: MoneroSendPreview? { get { sendPreviewStore.moneroSendPreview } set { sendPreviewStore.moneroSendPreview = newValue } }
    var cardanoSendPreview: CardanoSendPreview? { get { sendPreviewStore.cardanoSendPreview } set { sendPreviewStore.cardanoSendPreview = newValue } }
    var suiSendPreview: SuiSendPreview? { get { sendPreviewStore.suiSendPreview } set { sendPreviewStore.suiSendPreview = newValue } }
    var aptosSendPreview: AptosSendPreview? { get { sendPreviewStore.aptosSendPreview } set { sendPreviewStore.aptosSendPreview = newValue } }
    var tonSendPreview: TonSendPreview? { get { sendPreviewStore.tonSendPreview } set { sendPreviewStore.tonSendPreview = newValue } }
    var icpSendPreview: IcpSendPreview? { get { sendPreviewStore.icpSendPreview } set { sendPreviewStore.icpSendPreview = newValue } }
    var nearSendPreview: NearSendPreview? { get { sendPreviewStore.nearSendPreview } set { sendPreviewStore.nearSendPreview = newValue } }
    var polkadotSendPreview: PolkadotSendPreview? { get { sendPreviewStore.polkadotSendPreview } set { sendPreviewStore.polkadotSendPreview = newValue } }
    @Published var isSendingBitcoin: Bool = false
    @Published var isSendingBitcoinCash: Bool = false
    @Published var isSendingBitcoinSV: Bool = false
    @Published var isSendingLitecoin: Bool = false
    @Published var isSendingDogecoin: Bool = false
    @Published var isSendingEthereum: Bool = false
    @Published var isSendingTron: Bool = false
    @Published var isSendingSolana: Bool = false
    @Published var isSendingXRP: Bool = false
    @Published var isSendingStellar: Bool = false
    @Published var isSendingMonero: Bool = false
    @Published var isSendingCardano: Bool = false
    @Published var isSendingSui: Bool = false
    @Published var isSendingAptos: Bool = false
    @Published var isSendingTON: Bool = false
    @Published var isSendingICP: Bool = false
    @Published var isSendingNear: Bool = false
    @Published var isSendingPolkadot: Bool = false
    @Published var tronLastSendErrorDetails: String? = nil
    @Published var tronLastSendErrorAt: Date? = nil
    let chainDiagnosticsState = WalletChainDiagnosticsState()
    private(set) var recentPerformanceSamples: [PerformanceSample] = []
    var isOnboarded: Bool { !wallets.isEmpty }
    func chainKeypoolDiagnostics(for chainName: String) -> [ChainKeypoolDiagnostic] {
        wallets.filter { wallet in wallet.selectedChain == chainName || walletHasAddress(for: wallet, chainName: chainName) }
            .compactMap { wallet in
                let state = keypoolState(for: wallet, chainName: chainName)
                let reservedIndex = state.reservedReceiveIndex
                return ChainKeypoolDiagnostic(
                    walletID: wallet.id, walletName: wallet.name, chainName: chainName, reservedReceiveIndex: reservedIndex, reservedReceivePath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), reservedReceiveAddress: reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false), nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }}
    @Published var pricingProvider: PricingProvider = .coinGecko {
        didSet {
            guard pricingProvider != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var selectedFiatCurrency: FiatCurrency = .usd {
        didSet {
            guard selectedFiatCurrency != oldValue else { return }
            persistAppSettings()
            Task { @MainActor in await refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    @Published var fiatRateProvider: FiatRateProvider = .openER {
        didSet {
            guard fiatRateProvider != oldValue else { return }
            persistAppSettings()
            Task { @MainActor in await refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    @Published var coinGeckoAPIKey: String = "" {
        didSet {
            guard coinGeckoAPIKey != oldValue else { return }
            SecureStore.save(coinGeckoAPIKey, for: Self.coinGeckoAPIKeyAccount)
        }
    }
    @Published var ethereumRPCEndpoint: String = "" {
        didSet {
            guard ethereumRPCEndpoint != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var ethereumNetworkMode: EthereumNetworkMode = .mainnet {
        didSet {
            guard ethereumNetworkMode != oldValue else { return }
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 1)
        }
    }
    @Published var etherscanAPIKey: String = "" {
        didSet {
            guard etherscanAPIKey != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var moneroBackendBaseURL: String = "" {
        didSet {
            guard moneroBackendBaseURL != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var moneroBackendAPIKey: String = "" {
        didSet {
            guard moneroBackendAPIKey != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var isUserInitiatedRefreshInProgress: Bool = false
    @Published var priceAlerts: [PriceAlertRule] = [] {
        didSet {
            priceAlertsPersistTask?.cancel()
            priceAlertsPersistTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                guard !Task.isCancelled, let self else { return }
                self.persistPriceAlerts()
            }
        }}
    @Published var addressBook: [AddressBookEntry] = [] {
        didSet {
            addressBookPersistTask?.cancel()
            addressBookPersistTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                guard !Task.isCancelled, let self else { return }
                self.persistAddressBook()
            }
        }}
    @Published var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            persistTokenPreferences()
            tokenPreferenceRebuildTask?.cancel()
            tokenPreferenceRebuildTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms debounce
                guard !Task.isCancelled, let self else { return }
                self.rebuildTokenPreferenceDerivedState()
                self.rebuildWalletDerivedState()
                self.rebuildDashboardDerivedState()
            }
        }}
    @Published var livePrices: [String: Double] = [:] {
        didSet {
            guard livePrices != oldValue else { return }
            livePricesPersistTask?.cancel()
            livePricesPersistTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
                guard !Task.isCancelled, let self else { return }
                self.persistLivePrices()
            }
            if shouldRebuildDashboardForLivePriceChange(from: oldValue, to: livePrices) { rebuildDashboardDerivedState() }
        }
    }
    @Published var fiatRatesFromUSD: [String: Double] = [:]
    @Published var fiatRatesRefreshError: String? = nil
    @Published var quoteRefreshError: String? = nil
    var cachedPinnedDashboardAssetSymbols: [String] = [] { didSet { bumpCachesRevision() } }
    var cachedDashboardPinOptionBySymbol: [String: DashboardPinOption] = [:] { didSet { bumpCachesRevision() } }
    var cachedAvailableDashboardPinOptions: [DashboardPinOption] = [] { didSet { bumpCachesRevision() } }
    var cachedDashboardAssetGroups: [DashboardAssetGroup] = [] { didSet { bumpCachesRevision() } }
    var cachedDashboardRelevantPriceKeys: Set<String> = [] { didSet { bumpCachesRevision() } }
    var cachedDashboardSupportedTokenEntriesBySymbol: [String: [TokenPreferenceEntry]] = [:] { didSet { bumpCachesRevision() } }
    private var _cachedResolvedTokenPreferences: [TokenPreferenceEntry] = [] { didSet { bumpCachesRevision() } }
    var cachedResolvedTokenPreferences: [TokenPreferenceEntry] {
        get {
            _cachedResolvedTokenPreferences.isEmpty
                ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
                : _cachedResolvedTokenPreferences
        }
        set { _cachedResolvedTokenPreferences = newValue }
    }
    var cachedTokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] = [:] { didSet { bumpCachesRevision() } }
    var cachedResolvedTokenPreferencesBySymbol: [String: [TokenPreferenceEntry]] = [:] { didSet { bumpCachesRevision() } }
    var cachedEnabledTrackedTokenPreferences: [TokenPreferenceEntry] = [] { didSet { bumpCachesRevision() } }
    var cachedTokenPreferenceByChainAndSymbol: [String: TokenPreferenceEntry] = [:] { didSet { bumpCachesRevision() } }
    var cachedCurrencyFormatters: [String: NumberFormatter] = [:]
    var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    @Published var useCustomEthereumFees: Bool = false
    @Published var customEthereumMaxFeeGwei: String = ""
    @Published var customEthereumPriorityFeeGwei: String = ""
    @Published var sendAdvancedMode: Bool = false
    @Published var sendUTXOMaxInputCount: Int = 0
    @Published var sendEnableRBF: Bool = true
    @Published var sendEnableCPFP: Bool = false
    @Published var sendLitecoinChangeStrategy: LitecoinChangeStrategy = .derivedChange
    @Published var ethereumManualNonceEnabled: Bool = false
    @Published var ethereumManualNonce: String = ""
    @Published var bitcoinNetworkMode: BitcoinNetworkMode = .mainnet {
        didSet {
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
            Task {
                await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Bitcoin")
                await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Bitcoin")
            }
            chainKeypoolByChain.removeValue(forKey: "Bitcoin")
            chainOwnedAddressMapByChain.removeValue(forKey: "Bitcoin")
        }
    }
    @Published var dogecoinNetworkMode: DogecoinNetworkMode = .mainnet {
        didSet {
            persistAppSettings()
            Task {
                await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Dogecoin")
                await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Dogecoin")
            }
            chainKeypoolByChain["Dogecoin"] = [:]
            chainOwnedAddressMapByChain["Dogecoin"] = [:]
        }
    }
    @Published var bitcoinEsploraEndpoints: String = "" {
        didSet {
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
        }
    }
    @Published var bitcoinStopGap: Int = 10 {
        didSet {
            let clamped = max(1, min(bitcoinStopGap, 200))
            if clamped != bitcoinStopGap {
                bitcoinStopGap = clamped
                return
            }
            persistAppSettings()
        }
    }
    @Published var bitcoinFeePriority: BitcoinFeePriority = .normal {
        didSet {
            guard bitcoinFeePriority != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var dogecoinFeePriority: DogecoinFeePriority = .normal {
        didSet {
            guard dogecoinFeePriority != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var hideBalances: Bool = false {
        didSet {
            guard hideBalances != oldValue else { return }
            persistAppSettings()
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
            guard useFaceID != oldValue else { return }
            persistAppSettings()
            if !useFaceID {
                isAppLocked = false
                appLockError = nil
            }
        }
    }
    @Published var useAutoLock: Bool = false {
        didSet {
            guard useAutoLock != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var useStrictRPCOnly: Bool = false {
        didSet {
            guard useStrictRPCOnly != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var requireBiometricForSendActions: Bool = true {
        didSet {
            guard requireBiometricForSendActions != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var usePriceAlerts: Bool = true {
        didSet {
            guard usePriceAlerts != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var useTransactionStatusNotifications: Bool = true {
        didSet {
            guard useTransactionStatusNotifications != oldValue else { return }
            persistAppSettings()
            if useTransactionStatusNotifications { requestNotificationPermissionIfNeeded() }
        }
    }
    @Published var useLargeMovementNotifications: Bool = true {
        didSet {
            guard useLargeMovementNotifications != oldValue else { return }
            persistAppSettings()
            if useLargeMovementNotifications { requestNotificationPermissionIfNeeded() }
        }
    }
    @Published var automaticRefreshFrequencyMinutes: Int = 5 {
        didSet {
            let clamped = min(max(automaticRefreshFrequencyMinutes, 5), 60)
            if clamped != automaticRefreshFrequencyMinutes {
                automaticRefreshFrequencyMinutes = clamped
                return
            }
            guard automaticRefreshFrequencyMinutes != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var backgroundSyncProfile: BackgroundSyncProfile = .balanced {
        didSet {
            guard backgroundSyncProfile != oldValue else { return }
            persistAppSettings()
        }
    }
    @Published var largeMovementAlertPercentThreshold: Double = 10.0 {
        didSet {
            let clamped = min(max(largeMovementAlertPercentThreshold, 1), 90)
            if clamped != largeMovementAlertPercentThreshold {
                largeMovementAlertPercentThreshold = clamped
                return
            }
            persistAppSettings()
        }
    }
    @Published var largeMovementAlertUSDThreshold: Double = 50.0 {
        didSet {
            let clamped = min(max(largeMovementAlertUSDThreshold, 1), 100_000)
            if clamped != largeMovementAlertUSDThreshold {
                largeMovementAlertUSDThreshold = clamped
                return
            }
            persistAppSettings()
        }
    }
    @Published var chainKeypoolByChain: [String: [String: ChainKeypoolState]] = [:] {
        didSet {
            let changedChains = chainKeypoolByChain.keys.filter { chainKeypoolByChain[$0] != oldValue[$0] }
            for chainName in changedChains { persistKeypoolForChain(chainName) }
        }}
    @Published var chainOwnedAddressMapByChain: [String: [String: ChainOwnedAddressRecord]] = [:] {
        didSet {
            let changedChains = chainOwnedAddressMapByChain.keys.filter { chainOwnedAddressMapByChain[$0] != oldValue[$0] }
            for chainName in changedChains { persistOwnedAddressesForChain(chainName) }
        }}
    var pendingEthereumSendPreviewRefresh: Bool = false
    var pendingDogecoinSendPreviewRefresh: Bool = false
    @Published var discoveredUTXOAddressesByChain: [String: [String: [String]]] = [:]
    @Published var isLoadingMoreOnChainHistory: Bool = false
    let diagnostics = WalletDiagnosticsState()
    @Published var chainOperationalEventsByChain: [String: [ChainOperationalEvent]] = [:] {
        didSet {
            persistChainOperationalEvents()
        }}
    @Published var selectedFeePriorityOptionRawByChain: [String: String] = [:] {
        didSet {
            guard selectedFeePriorityOptionRawByChain != oldValue else { return }
            persistSelectedFeePriorityOptions()
        }
    }
    @Published var isRunningBitcoinRescan: Bool = false
    @Published var bitcoinRescanLastRunAt: Date? = nil
    @Published var isRunningBitcoinCashRescan: Bool = false
    @Published var bitcoinCashRescanLastRunAt: Date? = nil
    @Published var isRunningBitcoinSVRescan: Bool = false
    @Published var bitcoinSVRescanLastRunAt: Date? = nil
    @Published var isRunningLitecoinRescan: Bool = false
    @Published var litecoinRescanLastRunAt: Date? = nil
    @Published var isRunningDogecoinRescan: Bool = false
    @Published var dogecoinRescanLastRunAt: Date? = nil
    var suppressWalletSideEffects = false
    var userInitiatedRefreshTask: Task<Void, Never>?
    var importRefreshTask: Task<Void, Never>?
    var walletSideEffectsTask: Task<Void, Never>?
    var walletCollectionObservation: AnyCancellable?
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
    static let chainKeypoolDefaultsKey = "chain.keypool.snapshot.v1"
    static let chainOwnedAddressMapDefaultsKey = "chain.ownedAddressMap.snapshot.v1"
    static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    static let installMarkerDefaultsKey = "app.install.marker.v1"
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
    static func seedPhraseAccount(for walletID: String) -> String { "wallet.seed.\(walletID)" }
    static func seedPhrasePasswordAccount(for walletID: String) -> String { "wallet.seed.password.\(walletID)" }
    static func privateKeyAccount(for walletID: String) -> String { "wallet.privatekey.\(walletID)" }
    func resolvedSeedPhraseAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.seedPhraseStoreKey ?? Self.seedPhraseAccount(for: walletID) }
    func resolvedSeedPhrasePasswordAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.passwordStoreKey ?? Self.seedPhrasePasswordAccount(for: walletID) }
    func resolvedPrivateKeyAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.privateKeyStoreKey ?? Self.privateKeyAccount(for: walletID) }
    func clearWalletSecretIndex() {
        cachedSigningMaterialWalletIDs = []
        cachedPrivateKeyBackedWalletIDs = []
        cachedPasswordProtectedWalletIDs = []
        cachedSecretDescriptorsByWalletID = [:]
    }
    func storedSeedPhrase(for walletID: String) -> String? {
        let account = resolvedSeedPhraseAccount(for: walletID)
        guard let seedPhrase = try? SecureSeedStore.loadValue(for: account), !seedPhrase.isEmpty else { return nil }
        return seedPhrase
    }
    func storedPrivateKey(for walletID: String) -> String? {
        let account = resolvedPrivateKeyAccount(for: walletID)
        let privateKey = SecurePrivateKeyStore.loadValue(for: account)
        return privateKey.isEmpty ? nil : privateKey
    }
    func walletRequiresSeedPhrasePassword(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasPassword }
        return SecureSeedPasswordStore.hasPassword(for: resolvedSeedPhrasePasswordAccount(for: walletID))
    }
    func signingMaterialAvailability(for walletID: String) -> (hasSigningMaterial: Bool, isPrivateKeyBacked: Bool) {
        let hasSeedPhrase = storedSeedPhrase(for: walletID) != nil
        let hasPrivateKey = storedPrivateKey(for: walletID) != nil
        return (hasSeedPhrase || hasPrivateKey, hasPrivateKey)
    }
    func walletHasSigningMaterial(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasSigningMaterial }
        return signingMaterialAvailability(for: walletID).hasSigningMaterial
    }
    func isPrivateKeyBackedWallet(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasPrivateKey }
        return signingMaterialAvailability(for: walletID).isPrivateKeyBacked
    }
    func deleteWalletSecrets(for walletID: String) {
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
    func parsedBitcoinEsploraEndpoints() -> [String] { parseBitcoinEsploraEndpoints(raw: bitcoinEsploraEndpoints) }
    func effectiveBitcoinEsploraEndpoints() -> [String] {
        let configured = parsedBitcoinEsploraEndpoints()
        if !configured.isEmpty { return configured }
        return AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(for: bitcoinNetworkMode)
    }
    var bitcoinEsploraEndpointsValidationError: String? {
        Spectra.bitcoinEsploraEndpointsValidationError(raw: bitcoinEsploraEndpoints)
    }
    func parseDogecoinAmountInput(_ amountText: String) -> Double? {
        parseAmountInput(text: amountText, maxDecimals: 8)
    }
    func recordPendingSentTransaction(_ transaction: TransactionRecord) {
        appendTransaction(transaction)
        lastSentTransaction = transaction
        noteSendBroadcastQueued(for: transaction)
        requestTransactionStatusNotificationPermission()
    }
    private func applyVerificationNotice(_ n: SendVerificationNotice) {
        sendVerificationNotice = n.notice
        sendVerificationNoticeIsWarning = n.isWarning
    }
    func clearSendVerificationNotice() {
        applyVerificationNotice(SendVerificationNotice(notice: nil, isWarning: false))
    }
    func setDeferredSendVerificationNotice(for chainName: String) {
        applyVerificationNotice(verificationNoticeForStatus(status: .deferred, chainName: chainName))
    }
    func setFailedSendVerificationNotice(_ message: String) {
        sendVerificationNotice = "Warning: \(message)"
        sendVerificationNoticeIsWarning = true
    }
    func applySendVerificationStatus(_ verificationStatus: SendBroadcastVerificationStatus, chainName: String) {
        let coreStatus: CoreSendVerificationStatus
        switch verificationStatus {
        case .verified: coreStatus = .verified
        case .deferred: coreStatus = .deferred
        case .failed(let message):
            coreStatus = .failed(message: "Broadcast succeeded, but post-broadcast verification reported: \(message)")
        }
        applyVerificationNotice(verificationNoticeForStatus(status: coreStatus, chainName: chainName))
    }
    func updateSendVerificationNoticeForLastSentTransaction() {
        let snapshot: LastSentTransactionSnapshot? = lastSentTransaction.map { tx in
            LastSentTransactionSnapshot(
                kind: tx.kind == .send ? "send" : "other",
                status: {
                    switch tx.status {
                    case .pending: return "pending"
                    case .confirmed: return "confirmed"
                    case .failed: return "failed"
                    }
                }(),
                chainName: tx.chainName,
                transactionHash: tx.transactionHash,
                failureReason: tx.failureReason,
                transactionHistorySource: tx.transactionHistorySource,
                receiptBlockNumber: tx.receiptBlockNumber.map(Int64.init),
                dogecoinConfirmations: tx.dogecoinConfirmations.map(Int64.init)
            )
        }
        applyVerificationNotice(verificationNoticeForLastSent(snapshot: snapshot))
    }
    func runPostSendRefreshActions(for chainName: String, verificationStatus: SendBroadcastVerificationStatus) async {
        applySendVerificationStatus(verificationStatus, chainName: chainName)
        noteSendBroadcastVerification(
            chainName: chainName, verificationStatus: verificationStatus, transactionHash: lastSentTransaction?.chainName == chainName ? lastSentTransaction?.transactionHash : nil
        )
        async let balanceRefresh: () = refreshBalances()
        async let chainRefresh: () = {
            switch AppEndpointDirectory.appChain(for: chainName)?.id {
            case .bitcoin:          await self.refreshPendingBitcoinTransactions()
            case .bitcoinCash:      await self.refreshPendingBitcoinCashTransactions()
            case .bitcoinSV:        await self.refreshPendingBitcoinSVTransactions()
            case .litecoin:         await self.refreshPendingLitecoinTransactions()
            case .dogecoin:         await self.refreshPendingDogecoinTransactions()
            case .ethereum, .ethereumClassic, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
                                    await self.refreshPendingEVMTransactions(chainName: chainName)
            case .tron:             await self.refreshTronTransactions(loadMore: false)
            case .solana:           await self.refreshSolanaTransactions(loadMore: false)
            case .cardano:          await self.refreshCardanoTransactions(loadMore: false)
            case .xrp:              await self.refreshXRPTransactions(loadMore: false)
            case .stellar:          await self.refreshStellarTransactions(loadMore: false)
            case .monero:           await self.refreshMoneroTransactions(loadMore: false)
            case .sui:              await self.refreshSuiTransactions(loadMore: false)
            case .aptos:            await self.refreshAptosTransactions(loadMore: false)
            case .ton:              await self.refreshTONTransactions(loadMore: false)
            case .icp:              await self.refreshICPTransactions(loadMore: false)
            case .near:             await self.refreshNearTransactions(loadMore: false)
            case .polkadot:         await self.refreshPolkadotTransactions(loadMore: false)
            case .none:             break
            }
        }()
        _ = await (balanceRefresh, chainRefresh)
        updateSendVerificationNoticeForLastSentTransaction()
    }
    func resetSendComposerState(afterSend extraReset: (() -> Void)? = nil) {
        sendAmount = ""
        sendAddress = ""
        extraReset?()
        sendError = nil
    }
    func recordPerformanceSample(_ operation: String, startedAt: CFAbsoluteTime, metadata: String? = nil) {
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        recentPerformanceSamples.insert(
            PerformanceSample(
                id: UUID(), operation: operation, durationMS: durationMS, timestamp: Date(), metadata: metadata
            ), at: 0
        )
        if recentPerformanceSamples.count > 120 { recentPerformanceSamples = Array(recentPerformanceSamples.prefix(120)) }
        balanceTelemetryLogger.info("perf \(operation, privacy: .public) \(durationMS, format: .fixed(precision: 2))ms \(metadata ?? "", privacy: .public)")
    }
    init() {
        clearPersistedSecureDataOnFreshInstallIfNeeded()
        walletCollectionObservation = $wallets.dropFirst()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.suppressWalletSideEffects else { return }
                self.applyWalletCollectionSideEffects()
            }

        restorePersistedRuntimeConfigurationAndState()
        Task { @MainActor in
            rebuildTransactionDerivedState()
            startMaintenanceLoopIfNeeded()
            SpectraSecretStoreAdapter.registerWithBridge()
            setupRustRefreshEngine()
            // Network I/O runs concurrently — neither depends on the other.
            async let sqliteReload: () = reloadPersistedStateFromSQLite()
            async let fiatRefresh: () = refreshFiatExchangeRates()
            _ = await (sqliteReload, fiatRefresh)
        }}
    deinit {
        maintenanceTask?.cancel()
        userInitiatedRefreshTask?.cancel()
        importRefreshTask?.cancel()
        walletSideEffectsTask?.cancel()
#if canImport(Network)
        networkPathMonitor.cancel()
#endif
    }
    func withSuspendedTransactionSideEffects(_ body: () -> Void) {
        let previous = suppressSideEffects
        suppressSideEffects = true
        body()
        lastObservedTransactions = transactions
        suppressSideEffects = previous
    }
    var canImportWallet: Bool {
    importDraft.canImportWallet
}
    var resolvedTokenPreferences: [TokenPreferenceEntry] { cachedResolvedTokenPreferences }
    var tokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] { cachedTokenPreferencesByChain }
    var enabledTrackedTokenPreferences: [TokenPreferenceEntry] { cachedEnabledTrackedTokenPreferences }
    func setTokenPreferenceEnabled(id: String, isEnabled: Bool) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        tokenPreferences[index].isEnabled = isEnabled
    }
    func setTokenPreferencesEnabled(ids: [String], isEnabled: Bool) {
        let targetIDs = Set(ids)
        for index in tokenPreferences.indices where targetIDs.contains(tokenPreferences[index].id) { tokenPreferences[index].isEnabled = isEnabled }}
    func removeCustomTokenPreference(id: String) {
        guard let entry = tokenPreferences.first(where: { $0.id == id }), !entry.isBuiltIn else { return }
        tokenPreferences.removeAll { $0.id == id }}
    func updateCustomTokenPreferenceDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return }
        tokenPreferences[index].decimals = Int32(min(max(decimals, 0), 30))
        if let displayDecimals = tokenPreferences[index].displayDecimals { tokenPreferences[index].displayDecimals = min(displayDecimals, tokenPreferences[index].decimals) }}
    func updateTokenPreferenceDisplayDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        let supportedDecimals = max(tokenPreferences[index].decimals, 0)
        tokenPreferences[index].displayDecimals = min(Int32(max(decimals, 0)), supportedDecimals)
    }
    func resetNativeAssetDisplayDecimals() { assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain() }
    func resetTrackedTokenDisplayDecimals() {
        guard !tokenPreferences.isEmpty else { return }
        for index in tokenPreferences.indices { tokenPreferences[index].displayDecimals = nil }}
    @discardableResult
    func addCustomTokenPreference(chain: TokenTrackingChain, symbol: String, name: String, contractAddress: String, marketDataId: String = "0", coinGeckoId: String = "", decimals: Int) -> String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return localizedStoreString("Symbol is required.") }
        guard normalizedSymbol.count <= 12 else { return localizedStoreString("Symbol is too long.") }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return localizedStoreString("Token name is required.") }
        let normalizedContract = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContract.isEmpty else { return localizedStoreString("Contract address is required.") }
        switch chain {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: guard AddressValidation.isValid(normalizedContract, kind: "evm") else { return localizedStoreString("Enter a valid \(chain.rawValue) token contract address.") }
        case .solana: guard AddressValidation.isValid(normalizedContract, kind: "solana") else { return localizedStoreString("Enter a valid Solana token mint address.") }
        case .sui: let isLikelySuiIdentifier = normalizedContract.hasPrefix("0x")
                && (normalizedContract.contains("::") || normalizedContract.count > 2)
            guard isLikelySuiIdentifier else { return localizedStoreString("Enter a valid Sui coin type or package address.") }
        case .aptos: guard AddressValidation.isValidAptosTokenType(normalizedContract) else { return localizedStoreString("Enter a valid Aptos coin type.") }
        case .ton: guard AddressValidation.isValid(normalizedContract, kind: "ton") else { return localizedStoreString("Enter a valid TON jetton master address.") }
        case .near: guard AddressValidation.isValid(normalizedContract, kind: "near") else { return localizedStoreString("Enter a valid NEAR token contract account ID.") }
        case .tron: guard AddressValidation.isValid(normalizedContract, kind: "tron") else { return localizedStoreString("Enter a valid Tron TRC-20 contract address.") }}
        let duplicateExists = tokenPreferences.contains { entry in entry.chain == chain && normalizedTrackedTokenIdentifier(for: entry.chain, contractAddress: entry.contractAddress) == normalizedTrackedTokenIdentifier(for: chain, contractAddress: normalizedContract) }
        guard !duplicateExists else { return localizedStoreFormat("This token is already tracked for %@.", chain.rawValue) }
        tokenPreferences.append(
            TokenPreferenceEntry(
                chain: chain, name: normalizedName, symbol: normalizedSymbol, tokenStandard: chain.tokenStandard, contractAddress: normalizedContract, marketDataId: marketDataId.trimmingCharacters(in: .whitespacesAndNewlines), coinGeckoId: coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines), decimals: min(max(decimals, 0), 30), category: .custom, isBuiltIn: false, isEnabled: true
            )
        )
        tokenPreferences.sort { lhs, rhs in
            if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
            return lhs.symbol < rhs.symbol
        }
        return nil
    }
    func enabledTokenPreferences(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        enabledTrackedTokenPreferences.filter { $0.chain == chain }}
    func normalizedTrackedTokenIdentifier(for chain: TokenTrackingChain, contractAddress: String) -> String {
        let trimmed = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chain {
        case .ethereum, .arbitrum, .bnb, .avalanche, .hyperliquid: return normalizeEVMAddress(trimmed)
        case .aptos: return normalizeAptosTokenIdentifier(trimmed)
        case .sui: return normalizeSuiTokenIdentifier(trimmed)
        case .ton: return TONBalanceService.normalizeJettonMasterAddress(trimmed)
        default: return trimmed.lowercased()
        }}
    // Normalizers (Aptos / Sui) now live in Rust: `core/src/app_state/token_helpers.rs`.
    // Kept as instance-method forwarders so existing call sites (`self.foo(x)`) compile
    // without churn.
    func normalizeSuiTokenIdentifier(_ v: String) -> String { Spectra.normalizeSuiTokenIdentifier(value: v) }
    func normalizeSuiPackageComponent(_ v: String) -> String { Spectra.normalizeSuiPackageComponent(value: v) }
    func normalizeAptosTokenIdentifier(_ v: String) -> String { Spectra.normalizeAptosTokenIdentifier(value: v) }
    func canonicalAptosHexAddress(_ v: String) -> String { Spectra.canonicalAptosHexAddress(value: v) }
    // 6 identical EVM-chain tracked-token builders collapsed to a single helper.
    private func enabledEVMTrackedTokens(for chain: TokenTrackingChain) -> [ChainTokenRegistryEntry] {
        enabledTokenPreferences(for: chain).map { e in
            ChainTokenRegistryEntry(chain: e.chain, name: e.name, symbol: e.symbol, tokenStandard: e.tokenStandard, contractAddress: normalizeEVMAddress(e.contractAddress), marketDataId: e.marketDataId, coinGeckoId: e.coinGeckoId, decimals: Int(e.decimals), displayDecimals: e.displayDecimals.map(Int.init), category: e.category, isBuiltIn: e.isBuiltIn, isEnabledByDefault: e.isEnabled)
        }
    }
    func enabledEthereumTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .ethereum) }
    func enabledBNBTrackedTokens()        -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .bnb) }
    func enabledArbitrumTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .arbitrum) }
    func enabledOptimismTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .optimism) }
    func enabledAvalancheTrackedTokens()  -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .avalanche) }
    func enabledHyperliquidTrackedTokens()-> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .hyperliquid) }
    func enabledTronTrackedTokens() -> [TronBalanceService.TrackedTRC20Token] {
        enabledTokenPreferences(for: .tron).map { entry in
            TronBalanceService.TrackedTRC20Token(
                symbol: entry.symbol, contractAddress: entry.contractAddress, decimals: Int(entry.decimals)
            )
        }}
    func solanaTrackedTokens(includeDisabled: Bool = false) -> [String: SolanaBalanceService.KnownTokenMetadata] {
        var result: [String: SolanaBalanceService.KnownTokenMetadata] = [:]
        let entries = includeDisabled ? tokenPreferences.filter { $0.chain == .solana } : enabledTokenPreferences(for: .solana)
        for entry in entries {
            result[entry.contractAddress] = SolanaBalanceService.KnownTokenMetadata(
                symbol: entry.symbol, name: entry.name, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
            )
        }
        return result
    }
    func enabledSolanaTrackedTokens() -> [String: SolanaBalanceService.KnownTokenMetadata] {
        let configured = solanaTrackedTokens(includeDisabled: false)
        if configured.isEmpty { return SolanaBalanceService.knownTokenMetadataByMint }
        return configured
    }
    func enabledSuiTrackedTokens() -> [String: SuiBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .sui).map { entry in
                (
                    entry.contractAddress, SuiBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func enabledAptosTrackedTokens() -> [String: AptosBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .aptos).map { entry in
                (
                    normalizeAptosTokenIdentifier(entry.contractAddress), AptosBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func aptosPackageIdentifier(from value: String?) -> String { Spectra.aptosPackageIdentifier(value: value) }
    func enabledNearTrackedTokens() -> [String: NearBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .near).map { entry in
                (
                    entry.contractAddress, NearBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func enabledTONTrackedTokens() -> [String: TONBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .ton).map { entry in
                (
                    TONBalanceService.normalizeJettonMasterAddress(entry.contractAddress), TONBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func isSupportedSolanaSendCoin(_ coin: Coin) -> Bool {
        guard coin.chainName == "Solana" else { return false }
        if coin.symbol == "SOL" { return true }
        guard coin.tokenStandard == TokenTrackingChain.solana.tokenStandard else { return false }
        let trackedTokens = solanaTrackedTokens(includeDisabled: true)
        guard let mintAddress = coin.contractAddress ?? SolanaBalanceService.mintAddress(for: coin.symbol) else { return false }
        return trackedTokens[mintAddress] != nil
    }
    func isSupportedNearTokenSend(_ coin: Coin) -> Bool {
        guard coin.chainName == "NEAR", coin.symbol != "NEAR" else { return false }
        guard coin.tokenStandard == TokenTrackingChain.near.tokenStandard else { return false }
        guard let contract = coin.contractAddress else { return false }
        let prefs = cachedTokenPreferencesByChain[.near] ?? []
        return prefs.contains { $0.contractAddress.lowercased() == contract.lowercased() }
    }
    var ethereumRPCEndpointValidationError: String? { ethereumRpcEndpointValidationError(endpoint: ethereumRPCEndpoint) }
    var moneroBackendBaseURLValidationError: String? { moneroBackendBaseUrlValidationError(endpoint: moneroBackendBaseURL) }

    @discardableResult
    func setTransactionsIfChanged(_ newTransactions: [TransactionRecord]) -> Bool {
        guard !transactionSnapshotsMatch(transactions, newTransactions) else { return false }
        setTransactions(newTransactions)
        return true
    }
    private func transactionSnapshotsMatch(_ lhs: [TransactionRecord], _ rhs: [TransactionRecord]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.persistedSnapshot == $1.persistedSnapshot }
    }
}
