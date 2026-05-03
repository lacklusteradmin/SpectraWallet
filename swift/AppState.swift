import Foundation
import Collections
import SwiftUI
import os
import UIKit
#if canImport(Network)
    import Network
#endif

// MARK: - @Observable opt-in convention
//
// Swift's `@Observable` macro turns every stored property into
// observation-tracked unless it's tagged `@ObservationIgnored`. The
// default-on / opt-out shape means new properties accidentally become
// observable unless the author remembers — and a SwiftUI view that
// reads any tracked property re-renders on its mutation.
//
// AppState's rule: every new stored property MUST be one of
//   1. observed by views (no annotation; the property genuinely drives UI)
//   2. `@ObservationIgnored` with a one-line comment naming why it's
//      excluded (caches, debounce handles, weak observers, persistence
//      task storage — anything views shouldn't see)
//
// Reviewing a new stored property: if the author can't justify "yes
// SwiftUI views observe this," it should be `@ObservationIgnored`. The
// existing properties already follow this — see the dense `@ObservationIgnored`
// block at the top for the catalog. New work that doesn't make a choice
// is a bug surface (silent over-invalidation).

// MARK: - Task capture convention
//
// `Task { … }` closures inside `AppState` and its extensions follow
// this rule: **always capture `[weak self]` unless a comment on the
// preceding line explains the strong capture.**
//
// Strong capture means the closure pins this `AppState` alive until the
// task completes. That's correct when the work *should* finish even if
// SwiftUI tears down the view tree (e.g. a fire-and-forget persist that
// must not be cancelled). It's incorrect for routine "check something
// later" work — those tasks should release `self` if the app is torn
// down mid-await, and `[weak self]` makes that explicit.
//
// Examples of legitimate strong capture (must include the comment):
//   Task { /* strong self: persist must complete past view teardown */
//       await self.persistAppSettings()
//   }
//
// Examples that should be `[weak self]`:
//   Task { @MainActor [weak self] in
//       try? await Task.sleep(nanoseconds: 100_000_000)
//       guard let self else { return }
//       self.doDeferredWork()
//   }
//
// Code review: any new `Task` block without `[weak self]` should be
// challenged — the author should either add `[weak self]` or land the
// strong-capture comment.

// MARK: - AppState architecture
//
// `AppState` is the app's central `@Observable` store. To keep this file
// readable, large method clusters live in `AppState+<Domain>.swift` files
// (ImportLifecycle, ReceiveFlow, SendFlow, PricingFiat, BalanceRefresh,
// AddressResolution, OperationalTelemetry, DiagnosticsEndpoints,
// CoreStateStore, RustObserver). Every extension is a method-only attachment
// to the same `AppState` instance — there is no per-extension state.
//
// This is a known god-object split: the extensions hide the line count but
// don't reduce coupling. The migration target is to lift each domain into a
// small composed type (e.g. `WalletAddressResolver`, `LivePricesController`,
// `ImportFlowCoordinator`) that AppState owns by composition. The first
// step in that direction is `WalletDerivedCache` — see `walletDerivedCache`
// below; it bundles 17 derived-state fields into a single value type so the
// rebuild path reads as one assignment instead of 17 sequential mutations.
//
// Adding a new method? Place it in the matching `+<Domain>.swift` extension
// and resist the temptation to grow this file. New domains warrant their own
// extension file rather than landing in one of the existing ones.
@MainActor
@Observable
final class AppState {
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
    @ObservationIgnored let appSettingsPersist = DebouncedAction(intervalMilliseconds: 100)
    // Each `DebouncedAction` captures its target's coalescing window at
    // construction so the interval is visible next to the field declaration
    // instead of being a magic number buried in an async closure.
    @ObservationIgnored private let priceAlertsPersist = DebouncedAction(intervalMilliseconds: 100)
    @ObservationIgnored private let addressBookPersist = DebouncedAction(intervalMilliseconds: 100)
    @ObservationIgnored private let livePricesPersist = DebouncedAction(intervalMilliseconds: 200)
    @ObservationIgnored private let tokenPreferenceRebuild = DebouncedAction(intervalMilliseconds: 30)
    @ObservationIgnored private let transactionRebuild = DebouncedAction(intervalMilliseconds: 30)
    var transactions: [TransactionRecord] = [] {
        didSet {
            transactionRevision &+= 1
            let old = lastObservedTransactions
            lastObservedTransactions = transactions
            if !suppressSideEffects {
                persistTransactionsDelta(from: old, to: transactions)
                transactionRebuild.fire { [weak self] in self?.rebuildTransactionDerivedState() }
            }
        }
    }
    var normalizedHistoryIndex: [NormalizedHistoryEntry] = [] {
        didSet { normalizedHistoryRevision &+= 1 }
    }
    private(set) var transactionRevision: UInt64 = 0
    private(set) var normalizedHistoryRevision: UInt64 = 0
    @ObservationIgnored var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    @ObservationIgnored var cachedFirstActivityDateByWalletID: [String: Date] = [:]
    @ObservationIgnored var lastNormalizedHistorySignature: Int?
    @ObservationIgnored var suppressSideEffects = false
    @ObservationIgnored var lastObservedTransactions: [TransactionRecord] = []
    // Nested value types (event records, persisted-store schemas, keypool / diagnostic
    // structs and associated typealiases) moved to Shell/AppStateTypes.swift.
    /// Canonical wallet collection. Mutating it triggers a derived-cache
    /// rebuild via `scheduleWalletCollectionSideEffects`.
    ///
    /// **Observation note for view code**: SwiftUI's `@Observable` tracks
    /// access to this property as a whole — any mutation invalidates every
    /// view that read `store.wallets` for any reason, even a single
    /// wallet's balance update. Prefer reading from `cachedWalletByID[id]`
    /// (or another `walletDerivedCache` projection) when you only need a
    /// specific wallet — those projections are recomputed on rebuild but
    /// observed views see only the relevant change once SwiftUI's
    /// dictionary-key access tracking kicks in. New views that read from
    /// `wallets` directly should justify it (e.g. they actually iterate
    /// the entire collection).
    var wallets: [ImportedWallet] = [] {
        didSet {
            walletsRevision &+= 1
            scheduleWalletCollectionSideEffects()
        }
    }
    @ObservationIgnored private let walletSideEffectsDebounce = DebouncedAction(intervalMilliseconds: 30)
    @ObservationIgnored var pendingBalanceUpdates: [PendingBalanceUpdate] = []
    @ObservationIgnored var balanceFlushTask: Task<Void, Never>?
    struct PendingBalanceUpdate {
        let walletId: String
        let summary: WalletSummary
    }
    /// Debounced trigger for `applyWalletCollectionSideEffects`. Replaces the
    /// old `withObservationTracking`-based observation loop, which leaked
    /// `self` on cancel (its `withCheckedContinuation` never resumed when the
    /// task was cancelled mid-wait). Driving side-effects directly off
    /// `wallets.didSet` is the native Apple pattern and lets `deinit` release
    /// cleanly.
    private func scheduleWalletCollectionSideEffects() {
        walletSideEffectsDebounce.fire { [weak self] in
            guard let self, !self.suppressWalletSideEffects else { return }
            self.applyWalletCollectionSideEffects()
        }
    }
    private(set) var walletsRevision: UInt64 = 0
    // Derived caches. Recomputed by `applyWalletCollectionSideEffects`,
    // `rebuildWalletDerivedState`, `rebuildDashboardDerivedState`, and
    // `rebuildTokenPreferenceDerivedState`. Each `didSet` bumps
    // `cachesRevision` so SwiftUI views observing it refresh; bulk rebuilds
    // wrap their work in `batchCacheUpdates` to coalesce into a single bump.
    var cachesRevision: UInt64 = 0
    @ObservationIgnored private var cacheBatchDepth: Int = 0
    func bumpCachesRevision() {
        guard cacheBatchDepth == 0 else { return }
        cachesRevision &+= 1
    }
    func batchCacheUpdates(_ block: () -> Void) {
        cacheBatchDepth += 1
        block()
        cacheBatchDepth -= 1
        if cacheBatchDepth == 0 { cachesRevision &+= 1 }
    }
    /// Bundled derived state of the wallet collection. Recomputed by
    /// `_rebuildWalletDerivedStateBody` as a single value, so the rebuild
    /// reads as one assignment instead of 17 sequential mutations. The
    /// individual `cached*` properties below are thin computed accessors
    /// preserved for call-site compatibility.
    var walletDerivedCache: WalletDerivedCache = .empty { didSet { bumpCachesRevision() } }
    var cachedWalletByID: [String: ImportedWallet] { walletDerivedCache.walletByID }
    var cachedWalletByIDString: [String: ImportedWallet] { walletDerivedCache.walletByIDString }
    var cachedIncludedPortfolioWallets: [ImportedWallet] { walletDerivedCache.includedPortfolioWallets }
    var cachedIncludedPortfolioHoldings: [Coin] { walletDerivedCache.includedPortfolioHoldings }
    var cachedIncludedPortfolioHoldingsBySymbol: [String: [Coin]] { walletDerivedCache.includedPortfolioHoldingsBySymbol }
    var cachedUniqueWalletPriceRequestCoins: [Coin] { walletDerivedCache.uniqueWalletPriceRequestCoins }
    var cachedPortfolio: [Coin] {
        get { walletDerivedCache.portfolio }
        set { walletDerivedCache.portfolio = newValue }
    }
    var cachedAvailableSendCoinsByWalletID: [String: [Coin]] { walletDerivedCache.availableSendCoinsByWalletID }
    var cachedAvailableReceiveCoinsByWalletID: [String: [Coin]] { walletDerivedCache.availableReceiveCoinsByWalletID }
    var cachedAvailableReceiveChainsByWalletID: [String: [String]] { walletDerivedCache.availableReceiveChainsByWalletID }
    var cachedSendEnabledWallets: [ImportedWallet] { walletDerivedCache.sendEnabledWallets }
    var cachedReceiveEnabledWallets: [ImportedWallet] { walletDerivedCache.receiveEnabledWallets }
    var cachedRefreshableChainNames: Set<String> { walletDerivedCache.refreshableChainNames }
    var cachedSigningMaterialWalletIDs: Set<String> {
        get { walletDerivedCache.signingMaterialWalletIDs }
        set { walletDerivedCache.signingMaterialWalletIDs = newValue }
    }
    var cachedPrivateKeyBackedWalletIDs: Set<String> {
        get { walletDerivedCache.privateKeyBackedWalletIDs }
        set { walletDerivedCache.privateKeyBackedWalletIDs = newValue }
    }
    var cachedPasswordProtectedWalletIDs: Set<String> {
        get { walletDerivedCache.passwordProtectedWalletIDs }
        set { walletDerivedCache.passwordProtectedWalletIDs = newValue }
    }
    var cachedSecretDescriptorsByWalletID: [String: CoreWalletRustSecretMaterialDescriptor] {
        get { walletDerivedCache.secretDescriptorsByWalletID }
        set { walletDerivedCache.secretDescriptorsByWalletID = newValue }
    }
    let importDraft = WalletImportDraft()
    var importError: String? = nil
    var isImportingWallet: Bool = false
    var isShowingWalletImporter: Bool = false
    var isShowingAddWalletEntry: Bool = false
    var isShowingSendSheet: Bool = false
    var isShowingReceiveSheet: Bool = false
    var walletPendingDeletion: ImportedWallet?
    var editingWalletID: String? = nil
    var sendWalletID: String = ""
    var sendHoldingKey: String = ""
    var sendAmount: String = ""
    var sendAddress: String = ""
    var sendError: String? = nil
    var sendDestinationRiskWarning: String? = nil
    var sendDestinationInfoMessage: String? = nil
    var isCheckingSendDestinationBalance: Bool = false
    var pendingHighRiskSendReasons: [String] = []
    var isShowingHighRiskSendConfirmation: Bool = false
    var sendVerificationNotice: String? = nil
    var sendVerificationNoticeIsWarning: Bool = false
    var receiveWalletID: String = ""
    var receiveChainName: String = ""
    var receiveHoldingKey: String = ""
    var receiveResolvedAddress: String = ""
    var isResolvingReceiveAddress: Bool = false
    var selectedMainTab: MainAppTab = .home
    var isAppLocked: Bool = false
    var appLockError: String? = nil
    var isPreparingEthereumReplacementContext: Bool = false
    /// Chains currently computing a send fee preview. Observed by send UI to show loading state.
    var preparingChains: Set<String> = []
    @ObservationIgnored var statusTrackingByTransactionID: [UUID: AppState.TransactionStatusTrackingState] = [:]
    @ObservationIgnored var pendingSelfSendConfirmation: AppState.PendingSelfSendConfirmation?
    @ObservationIgnored var activeEthereumSendWalletIDs: Set<String> = []
    @ObservationIgnored var lastSendDestinationProbeKey: String?
    @ObservationIgnored var lastSendDestinationProbeWarning: String?
    @ObservationIgnored var lastSendDestinationProbeInfoMessage: String?
    var cachedResolvedENSAddresses: [String: String] = [:] { didSet { bumpCachesRevision() } }
    @ObservationIgnored var bypassHighRiskSendConfirmation = false
    @ObservationIgnored var isRefreshingLivePrices = false
    @ObservationIgnored var isRefreshingFiatRates = false
    @ObservationIgnored var isRefreshingChainBalances = false
    @ObservationIgnored var allowsBalanceNetworkRefresh = false
    @ObservationIgnored var isRefreshingPendingTransactions = false
    @ObservationIgnored var lastLivePriceRefreshAt: Date?
    @ObservationIgnored var lastFiatRatesRefreshAt: Date?
    @ObservationIgnored var lastFiatRatesAttemptAt: Date?
    @ObservationIgnored var lastFullRefreshAt: Date?
    @ObservationIgnored var lastChainBalanceRefreshAt: Date?
    @ObservationIgnored var lastBackgroundMaintenanceAt: Date?
    @ObservationIgnored var isNetworkReachable: Bool = true
    @ObservationIgnored var isConstrainedNetwork: Bool = false
    @ObservationIgnored var isExpensiveNetwork: Bool = false
    var lastSentTransaction: TransactionRecord?
    var lastPendingTransactionRefreshAt: Date? = nil
    // Send previews live in a dedicated sub-store so updates during the send flow
    // do not invalidate every view that observes AppState. Views that need the
    // preview values should observe `sendPreviewStore` directly.
    let sendPreviewStore = SendPreviewStore()
    /// Chains currently broadcasting a send transaction. Observed by send UI to show loading state.
    var sendingChains: Set<String> = []
    var tronLastSendErrorDetails: String? = nil
    var tronLastSendErrorAt: Date? = nil
    let chainDiagnosticsState = WalletChainDiagnosticsState()
    @ObservationIgnored private(set) var recentPerformanceSamples: Deque<PerformanceSample> = []
    var isOnboarded: Bool { !wallets.isEmpty }
    func chainKeypoolDiagnostics(for chainName: String) -> [ChainKeypoolDiagnostic] {
        wallets.filter { wallet in wallet.selectedChain == chainName || walletHasAddress(for: wallet, chainName: chainName) }
            .compactMap { wallet in
                let state = keypoolState(for: wallet, chainName: chainName)
                let reservedIndex = state.reservedReceiveIndex
                return ChainKeypoolDiagnostic(
                    walletID: wallet.id, walletName: wallet.name, chainName: chainName, reservedReceiveIndex: reservedIndex,
                    reservedReceivePath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
                    reservedReceiveAddress: reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false),
                    nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }
    }
    var pricingProvider: PricingProvider = .coinGecko {
        didSet {
            guard pricingProvider != oldValue else { return }
            persistAppSettings()
        }
    }
    var selectedFiatCurrency: FiatCurrency = .usd {
        didSet {
            guard selectedFiatCurrency != oldValue else { return }
            persistAppSettings()
            Task { @MainActor [weak self] in await self?.refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    var fiatRateProvider: FiatRateProvider = .openER {
        didSet {
            guard fiatRateProvider != oldValue else { return }
            persistAppSettings()
            Task { @MainActor [weak self] in await self?.refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    var ethereumRPCEndpoint: String = "" {
        didSet {
            guard ethereumRPCEndpoint != oldValue else { return }
            persistAppSettings()
        }
    }
    var ethereumNetworkMode: EthereumNetworkMode = .mainnet {
        didSet {
            guard ethereumNetworkMode != oldValue else { return }
            persistAppSettings()
            cachedPricedChainByKey = [:]  // Rust `isPricedChain` answer depends on this
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 1)
        }
    }
    var etherscanAPIKey: String = "" {
        didSet {
            guard etherscanAPIKey != oldValue else { return }
            persistAppSettings()
            WalletServiceBridge.shared.setEtherscanAPIKey(etherscanAPIKey)
        }
    }
    var moneroBackendBaseURL: String = "" {
        didSet {
            guard moneroBackendBaseURL != oldValue else { return }
            persistAppSettings()
        }
    }
    var moneroBackendAPIKey: String = "" {
        didSet {
            guard moneroBackendAPIKey != oldValue else { return }
            persistAppSettings()
        }
    }
    var isUserInitiatedRefreshInProgress: Bool = false
    var priceAlerts: [PriceAlertRule] = [] {
        didSet { priceAlertsPersist.fire { [weak self] in self?.persistPriceAlerts() } }
    }
    var addressBook: [AddressBookEntry] = [] {
        didSet { addressBookPersist.fire { [weak self] in self?.persistAddressBook() } }
    }
    var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            persistTokenPreferences()
            // Token-decimals overrides feed into the Rust asset-decimals
            // resolver, so drop the memoized cache when the overrides change.
            cachedAssetDecimalsResolutions = [:]
            tokenPreferenceRebuild.fire { [weak self] in
                guard let self else { return }
                self.rebuildTokenPreferenceDerivedState()
                self.rebuildWalletDerivedState()
                self.rebuildDashboardDerivedState()
            }
        }
    }
    var livePrices: [String: Double] = [:] {
        didSet {
            guard livePrices != oldValue else { return }
            livePricesPersist.fire { [weak self] in self?.persistLivePrices() }
            if shouldRebuildDashboardForLivePriceChange(from: oldValue, to: livePrices) { rebuildDashboardDerivedState() }
        }
    }
    var fiatRatesFromUSD: [String: Double] = [:]
    var fiatRatesRefreshError: String? = nil
    var quoteRefreshError: String? = nil
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
    @ObservationIgnored var cachedCurrencyFormatters: [String: NumberFormatter] = [:]
    @ObservationIgnored var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    // ── Memoized Rust-FFI lookups (hot path). Every asset row / wallet card
    // / transaction row used to cross the Swift→Rust boundary 2-4 times per
    // body eval via these helpers; we now cache the pure results and only
    // invalidate when the inputs (display-decimals prefs, token prefs,
    // selected fiat currency) change.
    @ObservationIgnored var cachedFiatAmountRules: [String: FiatAmountRules] = [:]
    @ObservationIgnored var cachedAssetMinimumVisibleAmounts: [UInt32: Double] = [:]
    @ObservationIgnored var cachedAssetDecimalsResolutions: [String: (supported: UInt32, display: UInt32)] = [:]
    /// Memoizes `corePlanPricedChain`. Called once per coin per body render
    /// via `isPricedAsset` (portfolio totals, asset rows, wallet cards). Key
    /// composes chain name + both network modes because the Rust answer
    /// depends on all three. Invalidated from the network-mode `didSet`s.
    @ObservationIgnored var cachedPricedChainByKey: [String: Bool] = [:]
    /// Memoizes `formattingTokenPreferenceLookupKey`. Keyed by
    /// `chainName|symbol`; the Rust side is a pure function of those two
    /// inputs, so the cache is good for the app lifetime.
    @ObservationIgnored var cachedTokenPreferenceLookupKeys: [String: String] = [:]
    var useCustomEthereumFees: Bool = false
    var customEthereumMaxFeeGwei: String = ""
    var customEthereumPriorityFeeGwei: String = ""
    var sendAdvancedMode: Bool = false
    var sendUTXOMaxInputCount: Int = 0
    var sendEnableRBF: Bool = true
    var sendEnableCPFP: Bool = false
    var sendLitecoinChangeStrategy: LitecoinChangeStrategy = .derivedChange
    var ethereumManualNonceEnabled: Bool = false
    var ethereumManualNonce: String = ""
    var bitcoinNetworkMode: BitcoinNetworkMode = .mainnet {
        didSet {
            persistAppSettings()
            cachedPricedChainByKey = [:]  // Rust `isPricedChain` answer depends on this
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
            Task {
                try? await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Bitcoin")
                try? await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Bitcoin")
            }
            chainKeypoolByChain.removeValue(forKey: "Bitcoin")
            chainOwnedAddressMapByChain.removeValue(forKey: "Bitcoin")
        }
    }
    var dogecoinNetworkMode: DogecoinNetworkMode = .mainnet {
        didSet {
            persistAppSettings()
            Task {
                try? await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Dogecoin")
                try? await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Dogecoin")
            }
            chainKeypoolByChain["Dogecoin"] = [:]
            chainOwnedAddressMapByChain["Dogecoin"] = [:]
        }
    }
    var bitcoinEsploraEndpoints: String = "" {
        didSet {
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
        }
    }
    var bitcoinStopGap: Int = 10 {
        didSet {
            let clamped = max(1, min(bitcoinStopGap, 200))
            if clamped != bitcoinStopGap {
                bitcoinStopGap = clamped
                return
            }
            persistAppSettings()
        }
    }
    var bitcoinFeePriority: BitcoinFeePriority = .normal {
        didSet {
            guard bitcoinFeePriority != oldValue else { return }
            persistAppSettings()
        }
    }
    var dogecoinFeePriority: DogecoinFeePriority = .normal {
        didSet {
            guard dogecoinFeePriority != oldValue else { return }
            persistAppSettings()
        }
    }
    /// User-facing preferences (UI / security / notifications / refresh cadence).
    /// Split out so views that only care about preferences stop getting
    /// invalidated whenever wallets / balances / transactions mutate.
    let preferences = AppUserPreferences()
    var assetDisplayDecimalsByChain: [String: Int] = [:] {
        didSet {
            let normalized = assetDisplayDecimalsByChain.mapValues { min(max($0, 0), 30) }
            if normalized != assetDisplayDecimalsByChain {
                assetDisplayDecimalsByChain = normalized
                return
            }
            persistAssetDisplayDecimalsByChain()
            cachedDecimalFormatters = [:]
            cachedAssetDecimalsResolutions = [:]
        }
    }
    var backgroundSyncProfile: BackgroundSyncProfile = .balanced {
        didSet {
            guard backgroundSyncProfile != oldValue else { return }
            persistAppSettings()
        }
    }
    var chainKeypoolByChain: [String: [String: ChainKeypoolState]] = [:] {
        didSet {
            let changedChains = chainKeypoolByChain.keys.filter { chainKeypoolByChain[$0] != oldValue[$0] }
            for chainName in changedChains { persistKeypoolForChain(chainName) }
        }
    }
    var chainOwnedAddressMapByChain: [String: [String: ChainOwnedAddressRecord]] = [:] {
        didSet {
            let changedChains = chainOwnedAddressMapByChain.keys.filter { chainOwnedAddressMapByChain[$0] != oldValue[$0] }
            for chainName in changedChains { persistOwnedAddressesForChain(chainName) }
        }
    }
    @ObservationIgnored var pendingSendPreviewRefreshChains: Set<String> = []
    var discoveredUTXOAddressesByChain: [String: [String: [String]]] = [:]
    var isLoadingMoreOnChainHistory: Bool = false
    let diagnostics = WalletDiagnosticsState()
    var chainOperationalEventsByChain: [String: [ChainOperationalEvent]] = [:] {
        didSet {
            persistChainOperationalEvents()
        }
    }
    var selectedFeePriorityOptionRawByChain: [String: String] = [:] {
        didSet {
            guard selectedFeePriorityOptionRawByChain != oldValue else { return }
            persistSelectedFeePriorityOptions()
        }
    }
    private struct UTXORescanState { var isRunning: Bool = false; var lastRunAt: Date? = nil }
    private var utxoRescanStateByChain: [String: UTXORescanState] = [:]
    var isRunningBitcoinRescan: Bool {
        get { utxoRescanStateByChain["Bitcoin"]?.isRunning ?? false }
        set { utxoRescanStateByChain["Bitcoin", default: UTXORescanState()].isRunning = newValue }
    }
    var bitcoinRescanLastRunAt: Date? {
        get { utxoRescanStateByChain["Bitcoin"]?.lastRunAt }
        set { utxoRescanStateByChain["Bitcoin", default: UTXORescanState()].lastRunAt = newValue }
    }
    var isRunningBitcoinCashRescan: Bool {
        get { utxoRescanStateByChain["Bitcoin Cash"]?.isRunning ?? false }
        set { utxoRescanStateByChain["Bitcoin Cash", default: UTXORescanState()].isRunning = newValue }
    }
    var bitcoinCashRescanLastRunAt: Date? {
        get { utxoRescanStateByChain["Bitcoin Cash"]?.lastRunAt }
        set { utxoRescanStateByChain["Bitcoin Cash", default: UTXORescanState()].lastRunAt = newValue }
    }
    var isRunningBitcoinSVRescan: Bool {
        get { utxoRescanStateByChain["Bitcoin SV"]?.isRunning ?? false }
        set { utxoRescanStateByChain["Bitcoin SV", default: UTXORescanState()].isRunning = newValue }
    }
    var bitcoinSVRescanLastRunAt: Date? {
        get { utxoRescanStateByChain["Bitcoin SV"]?.lastRunAt }
        set { utxoRescanStateByChain["Bitcoin SV", default: UTXORescanState()].lastRunAt = newValue }
    }
    var isRunningLitecoinRescan: Bool {
        get { utxoRescanStateByChain["Litecoin"]?.isRunning ?? false }
        set { utxoRescanStateByChain["Litecoin", default: UTXORescanState()].isRunning = newValue }
    }
    var litecoinRescanLastRunAt: Date? {
        get { utxoRescanStateByChain["Litecoin"]?.lastRunAt }
        set { utxoRescanStateByChain["Litecoin", default: UTXORescanState()].lastRunAt = newValue }
    }
    var isRunningDogecoinRescan: Bool {
        get { utxoRescanStateByChain["Dogecoin"]?.isRunning ?? false }
        set { utxoRescanStateByChain["Dogecoin", default: UTXORescanState()].isRunning = newValue }
    }
    var dogecoinRescanLastRunAt: Date? {
        get { utxoRescanStateByChain["Dogecoin"]?.lastRunAt }
        set { utxoRescanStateByChain["Dogecoin", default: UTXORescanState()].lastRunAt = newValue }
    }
    @ObservationIgnored var suppressWalletSideEffects = false
    @ObservationIgnored var userInitiatedRefreshTask: Task<Void, Never>?
    @ObservationIgnored var importRefreshTask: Task<Void, Never>?
    @ObservationIgnored var walletSideEffectsTask: Task<Void, Never>?
    @ObservationIgnored var lastHistoryRefreshAtByChain: [String: Date] = [:]
    @ObservationIgnored var appIsActive = true
    @ObservationIgnored var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored var lastObservedPortfolioTotalUSD: Double?
    @ObservationIgnored var lastObservedPortfolioCompositionSignature: String?

    // ── Tor routing ───────────────────────────────────────────────────────
    /// Live Tor bootstrap/connection state polled from Rust. Drives the
    /// dashboard indicator and the settings status row.
    var torStatus: TorStatus = .stopped
    /// Whether Tor is turned on. Persisted via UserDefaults; default true.
    var torEnabled: Bool = true {
        didSet {
            guard torEnabled != oldValue else { return }
            UserDefaults.standard.set(torEnabled, forKey: Self.torEnabledDefaultsKey)
            handleTorEnabledChange()
        }
    }
    /// Route through a user-supplied SOCKS5 address instead of embedded Arti.
    var torUseCustomProxy: Bool = false {
        didSet {
            guard torUseCustomProxy != oldValue else { return }
            UserDefaults.standard.set(torUseCustomProxy, forKey: Self.torUseCustomProxyDefaultsKey)
            handleTorEnabledChange()
        }
    }
    /// SOCKS5 URL for the custom proxy mode. Defaults to Orbot's port.
    var torCustomProxyAddress: String = "socks5://127.0.0.1:9150" {
        didSet {
            guard torCustomProxyAddress != oldValue else { return }
            UserDefaults.standard.set(torCustomProxyAddress, forKey: Self.torCustomProxyAddressDefaultsKey)
        }
    }
    /// Kill switch: block all outbound requests when Tor is not ready.
    var torKillSwitch: Bool = false {
        didSet {
            guard torKillSwitch != oldValue else { return }
            UserDefaults.standard.set(torKillSwitch, forKey: Self.torKillSwitchDefaultsKey)
        }
    }
    /// Background task that polls `torStatus()` from Rust every second.
    @ObservationIgnored var torStatusPollingTask: Task<Void, Never>?
    #if canImport(Network)
        let networkPathMonitor = NWPathMonitor()
        let networkPathMonitorQueue = DispatchQueue(label: "spectra.network.monitor")
    #endif
    // ── Persistence keys ──────────────────────────────────────────────
    //
    // Listed here as the single inventory of *what this app persists* —
    // a reader can answer "what state survives a relaunch?" by reading
    // this block. Keys are referenced via `Self.<name>`. New persisted
    // values land here, not at the call site.
    //
    // Versioned keys end in `.vN` and bump when the codable shape changes
    // incompatibly; the previous key is left here briefly for any
    // migration-read code that still references it.
    static let pricingProviderDefaultsKey = "pricing.provider"
    static let selectedFiatCurrencyDefaultsKey = "pricing.selectedFiatCurrency"
    static let fiatRateProviderDefaultsKey = "pricing.fiatRateProvider"
    static let fiatRatesFromUSDDefaultsKey = "pricing.fiatRatesFromUSD.v1"
    static let livePricesDefaultsKey = "pricing.livePrices.v1"
    static let priceAlertsDefaultsKey = "priceAlerts.snapshot"
    static let addressBookDefaultsKey = "addressBook.snapshot"

    static let walletsAccount = "wallets.snapshot"
    static let walletsCoreSnapshotAccount = "wallets.core.snapshot.v1"

    static let ethereumRPCEndpointDefaultsKey = "ethereum.rpc.endpoint"
    static let etherscanAPIKeyDefaultsKey = "ethereum.etherscan.apiKey"
    static let ethereumNetworkModeDefaultsKey = "ethereum.network.mode"
    static let bitcoinNetworkModeDefaultsKey = "bitcoin.network.mode"
    static let dogecoinNetworkModeDefaultsKey = "dogecoin.network.mode"
    static let bitcoinEsploraEndpointsDefaultsKey = "bitcoin.esplora.endpoints"
    static let bitcoinStopGapDefaultsKey = "bitcoin.stopGap"
    static let bitcoinFeePriorityDefaultsKey = "bitcoin.feePriority"
    static let dogecoinFeePriorityDefaultsKey = "settings.dogecoinFeePriority"

    static let tokenPreferencesDefaultsKey = "settings.tokenPreferences.v1"
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

    static let torEnabledDefaultsKey = "tor.enabled"
    static let torUseCustomProxyDefaultsKey = "tor.useCustomProxy"
    static let torCustomProxyAddressDefaultsKey = "tor.customProxyAddress"
    static let torKillSwitchDefaultsKey = "tor.killSwitch"

    static let chainOperationalEventsDefaultsKey = "chain.operational.events.v1"
    static let operationalLogsDefaultsKey = "operational.logs.v1"
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
    /// Failure backoff so a degraded provider isn't hammered every maintenance
    /// tick. Without this, a fetch that errors out leaves `lastFiatRatesRefreshAt`
    /// nil, so the cooldown gate never trips and every caller re-fetches.
    static let fiatRatesRetryBackoff: TimeInterval = 60
    static let backgroundMaintenanceInterval: TimeInterval = 15 * 60
    static let constrainedBackgroundMaintenanceInterval: TimeInterval = 30 * 60
    static let lowPowerBackgroundMaintenanceInterval: TimeInterval = 45 * 60
    static let lowBatteryBackgroundMaintenanceInterval: TimeInterval = 60 * 60
    static let foregroundFullRefreshStalenessInterval: TimeInterval = 2 * 60
    static let automaticChainRefreshStalenessInterval: TimeInterval = 10 * 60
    static func seedPhraseAccount(for walletID: String) -> String { "wallet.seed.\(walletID)" }
    static func seedPhrasePasswordAccount(for walletID: String) -> String { "wallet.seed.password.\(walletID)" }
    static func privateKeyAccount(for walletID: String) -> String { "wallet.privatekey.\(walletID)" }
    func resolvedSeedPhraseAccount(for walletID: String) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.seedPhraseStoreKey ?? Self.seedPhraseAccount(for: walletID)
    }
    func resolvedSeedPhrasePasswordAccount(for walletID: String) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.passwordStoreKey ?? Self.seedPhrasePasswordAccount(for: walletID)
    }
    func resolvedPrivateKeyAccount(for walletID: String) -> String {
        cachedSecretDescriptorsByWalletID[walletID]?.privateKeyStoreKey ?? Self.privateKeyAccount(for: walletID)
    }
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
                confirmationCount: tx.confirmationCount.map(Int64.init)
            )
        }
        applyVerificationNotice(verificationNoticeForLastSent(snapshot: snapshot))
    }
    nonisolated(unsafe) private static let utxoPostSendChains: Set<String> = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"
    ]
    func runPostSendRefreshActions(for chainName: String, verificationStatus: SendBroadcastVerificationStatus) async {
        applySendVerificationStatus(verificationStatus, chainName: chainName)
        noteSendBroadcastVerification(
            chainName: chainName, verificationStatus: verificationStatus,
            transactionHash: lastSentTransaction?.chainName == chainName ? lastSentTransaction?.transactionHash : nil
        )
        async let balanceRefresh: () = refreshBalances()
        async let chainRefresh: () = {
            guard let id = WalletChainID(chainName), let descriptor = Self.chainRefreshDescriptors[id] else { return }
            let usePending = isEVMChain(chainName) || Self.utxoPostSendChains.contains(chainName)
            if usePending { await descriptor.executePendingOnly?(self) } else { await descriptor.executeHistoryOnly?(self) }
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
        recentPerformanceSamples.prepend(
            PerformanceSample(id: UUID(), operation: operation, durationMS: durationMS, timestamp: Date(), metadata: metadata)
        )
        if recentPerformanceSamples.count > 120 { recentPerformanceSamples.removeLast() }
        balanceTelemetryLogger.info(
            "perf \(operation, privacy: .public) \(durationMS, format: .fixed(precision: 2))ms \(metadata ?? "", privacy: .public)")
    }
    init() {
        // Wire preferences' side-effect closures back to AppState. Using
        // closures (rather than an observation loop) keeps the coupling
        // explicit and keeps the preferences class cleanly isolated.
        preferences.persistHandler = { [weak self] in self?.persistAppSettings() }
        preferences.useFaceIDDisabledHandler = { [weak self] in
            self?.isAppLocked = false
            self?.appLockError = nil
        }
        preferences.notificationPermissionRequestHandler = { [weak self] in
            self?.requestNotificationPermissionIfNeeded()
        }
        preferences.refreshFrequencyChangedHandler = { [weak self] in
            guard let self else { return }
            Task { await self.restartBalanceRefreshForCurrentConfiguration() }
        }
        clearPersistedSecureDataOnFreshInstallIfNeeded()
        restorePersistedRuntimeConfigurationAndState()
        // Use [weak self] so that if SwiftUI/Xcode discards this AppState
        // while the init task is still awaiting SQLite / HTTP, the old
        // instance can release promptly instead of being pinned alive by a
        // strong capture on `self` through the awaited method calls.
        Task { @MainActor [weak self] in await self?.warmUpAfterLaunch() }
    }

    /// Boot-time lifecycle phase: runs once after `init`, in order.
    ///
    /// Phase 1 (sync): observable derived-state rebuild + main-loop kicks
    /// that views need before the first frame renders.
    /// Phase 2 (concurrent async): non-UI-blocking I/O — SQLite reload
    /// and fiat-rate refresh run in parallel since neither depends on
    /// the other.
    ///
    /// Distinct from per-interaction handlers (`refreshLivePrices`,
    /// `applyWalletCollectionSideEffects`) so a reader can answer
    /// "called once per launch" vs "called per user tap" by file
    /// position. New launch-only work belongs here; new per-interaction
    /// work belongs on the relevant `+*` extension.
    private func warmUpAfterLaunch() async {
        rebuildTransactionDerivedState()
        startMaintenanceLoopIfNeeded()
        SpectraSecretStoreAdapter.registerWithBridge()
        setupRustRefreshEngine()
        Task(priority: .utility) { await BundleImageLoader.warmRasterCache() }
        async let sqliteReload: () = reloadPersistedStateFromSQLite()
        async let fiatRefresh: () = refreshFiatExchangeRatesIfNeeded()
        _ = await (sqliteReload, fiatRefresh)
        // Rust wallet state is now initialized; the earlier triggerImmediate fired before
        // initWalletStateDirect and returned None for every wallet. Re-trigger now.
        await refreshBalances()
    }
    deinit {
        maintenanceTask?.cancel()
        userInitiatedRefreshTask?.cancel()
        importRefreshTask?.cancel()
        walletSideEffectsTask?.cancel()
        balanceFlushTask?.cancel()
        appSettingsPersist.cancel()
        // Debounced actions and registry-owned tasks each cancel via one
        // call instead of N — see DebouncedAction / ManagedTaskRegistry.
        walletSideEffectsDebounce.cancel()
        transactionRebuild.cancel()
        tokenPreferenceRebuild.cancel()
        livePricesPersist.cancel()
        priceAlertsPersist.cancel()
        addressBookPersist.cancel()
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
        for index in tokenPreferences.indices where targetIDs.contains(tokenPreferences[index].id) {
            tokenPreferences[index].isEnabled = isEnabled
        }
    }
    func removeCustomTokenPreference(id: String) {
        guard let entry = tokenPreferences.first(where: { $0.id == id }), !entry.isBuiltIn else { return }
        tokenPreferences.removeAll { $0.id == id }
    }
    func updateCustomTokenPreferenceDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return }
        tokenPreferences[index].decimals = Int32(min(max(decimals, 0), 30))
        if let displayDecimals = tokenPreferences[index].displayDecimals {
            tokenPreferences[index].displayDecimals = min(displayDecimals, tokenPreferences[index].decimals)
        }
    }
    func updateTokenPreferenceDisplayDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        let supportedDecimals = max(tokenPreferences[index].decimals, 0)
        tokenPreferences[index].displayDecimals = min(Int32(max(decimals, 0)), supportedDecimals)
    }
    func resetNativeAssetDisplayDecimals() { assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain() }
    func resetTrackedTokenDisplayDecimals() {
        guard !tokenPreferences.isEmpty else { return }
        for index in tokenPreferences.indices { tokenPreferences[index].displayDecimals = nil }
    }
    @discardableResult
    func addCustomTokenPreference(
        chain: TokenTrackingChain, symbol: String, name: String, contractAddress: String,
        coinGeckoId: String = "", decimals: Int
    ) -> String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return localizedStoreString("Symbol is required.") }
        guard normalizedSymbol.count <= 12 else { return localizedStoreString("Symbol is too long.") }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return localizedStoreString("Token name is required.") }
        let normalizedContract = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContract.isEmpty else { return localizedStoreString("Contract address is required.") }
        switch chain {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid, .polygon, .base, .linea, .scroll, .blast, .mantle:
            guard AddressValidation.isValid(normalizedContract, kind: "evm") else {
                return localizedStoreString("Enter a valid \(chain.rawValue) token contract address.")
            }
        case .solana:
            guard AddressValidation.isValid(normalizedContract, kind: "solana") else {
                return localizedStoreString("Enter a valid Solana token mint address.")
            }
        case .sui:
            let isLikelySuiIdentifier =
                normalizedContract.hasPrefix("0x")
                && (normalizedContract.contains("::") || normalizedContract.count > 2)
            guard isLikelySuiIdentifier else { return localizedStoreString("Enter a valid Sui coin type or package address.") }
        case .aptos:
            guard AddressValidation.isValidAptosTokenType(normalizedContract) else {
                return localizedStoreString("Enter a valid Aptos coin type.")
            }
        case .ton:
            guard AddressValidation.isValid(normalizedContract, kind: "ton") else {
                return localizedStoreString("Enter a valid TON jetton master address.")
            }
        case .near:
            guard AddressValidation.isValid(normalizedContract, kind: "near") else {
                return localizedStoreString("Enter a valid NEAR token contract account ID.")
            }
        case .tron:
            guard AddressValidation.isValid(normalizedContract, kind: "tron") else {
                return localizedStoreString("Enter a valid Tron TRC-20 contract address.")
            }
        }
        let duplicateExists = tokenPreferences.contains { entry in
            entry.chain == chain
                && normalizedTrackedTokenIdentifier(for: entry.chain, contractAddress: entry.contractAddress)
                    == normalizedTrackedTokenIdentifier(for: chain, contractAddress: normalizedContract)
        }
        guard !duplicateExists else { return localizedStoreFormat("This token is already tracked for %@.", chain.rawValue) }
        tokenPreferences.append(
            TokenPreferenceEntry(
                chain: chain, name: normalizedName, symbol: normalizedSymbol, tokenStandard: chain.tokenStandard,
                contractAddress: normalizedContract,
                coinGeckoId: coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines), decimals: min(max(decimals, 0), 30),
                category: .custom, isBuiltIn: false, isEnabled: true
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
        enabledTrackedTokenPreferences.filter { $0.chain == chain }
    }
    func normalizedTrackedTokenIdentifier(for chain: TokenTrackingChain, contractAddress: String) -> String {
        let trimmed = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chain {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid, .polygon, .base, .linea, .scroll, .blast, .mantle:
            return normalizeEVMAddress(trimmed)
        case .aptos: return normalizeAptosTokenIdentifier(trimmed)
        case .sui: return normalizeSuiTokenIdentifier(trimmed)
        case .ton: return TONBalanceService.normalizeJettonMasterAddress(trimmed)
        default: return trimmed.lowercased()
        }
    }
    // Normalizers (Aptos / Sui) now live in Rust: `core/src/app_state/token_helpers.rs`.
    // Kept as instance-method forwarders so existing call sites (`self.foo(x)`) compile
    // without churn.
    func normalizeSuiTokenIdentifier(_ v: String) -> String { Spectra.normalizeSuiTokenIdentifier(value: v) }
    func normalizeSuiPackageComponent(_ v: String) -> String { Spectra.normalizeSuiPackageComponent(value: v) }
    func normalizeAptosTokenIdentifier(_ v: String) -> String { Spectra.normalizeAptosTokenIdentifier(value: v) }
    func canonicalAptosHexAddress(_ v: String) -> String { Spectra.canonicalAptosHexAddress(value: v) }
    /// Map a `TokenTrackingChain` to the user's currently-enabled tracked tokens for that chain.
    /// All 12 EVM chains share this helper; routing via `TokenTrackingChain.forChainName(...)`
    /// at the call site picks the right chain.
    func enabledEVMTrackedTokens(for chain: TokenTrackingChain) -> [ChainTokenRegistryEntry] {
        enabledTokenPreferences(for: chain).map { e in
            ChainTokenRegistryEntry(
                chain: e.chain, name: e.name, symbol: e.symbol, tokenStandard: e.tokenStandard,
                contractAddress: normalizeEVMAddress(e.contractAddress), coinGeckoId: e.coinGeckoId,
                decimals: Int(e.decimals), displayDecimals: e.displayDecimals.map(Int.init), category: e.category, isBuiltIn: e.isBuiltIn,
                isEnabledByDefault: e.isEnabled)
        }
    }
    func enabledTronTrackedTokens() -> [TronBalanceService.TrackedTRC20Token] {
        enabledTokenPreferences(for: .tron).map { entry in
            TronBalanceService.TrackedTRC20Token(
                symbol: entry.symbol, contractAddress: entry.contractAddress, decimals: Int(entry.decimals)
            )
        }
    }
    func solanaTrackedTokens(includeDisabled: Bool = false) -> [String: SolanaBalanceService.KnownTokenMetadata] {
        var result: [String: SolanaBalanceService.KnownTokenMetadata] = [:]
        let entries = includeDisabled ? tokenPreferences.filter { $0.chain == .solana } : enabledTokenPreferences(for: .solana)
        for entry in entries {
            result[entry.contractAddress] = SolanaBalanceService.KnownTokenMetadata(
                symbol: entry.symbol, name: entry.name, decimals: Int(entry.decimals),
                coinGeckoId: entry.coinGeckoId
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
                    entry.contractAddress,
                    SuiBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals),
                        coinGeckoId: entry.coinGeckoId
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
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals),
                        coinGeckoId: entry.coinGeckoId
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
                    entry.contractAddress,
                    NearBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals),
                        coinGeckoId: entry.coinGeckoId
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
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals),
                        coinGeckoId: entry.coinGeckoId
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
