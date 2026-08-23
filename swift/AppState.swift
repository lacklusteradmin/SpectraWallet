import Foundation
import DequeModule
import OrderedCollections
import SwiftUI
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
    static let exportFilenameTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    // Nested enums (ResetScope, TimeoutError, SeedPhraseRevealError, BackgroundSyncProfile)
    // moved to Shell/AppStateTypes.swift via `extension AppState`.
    @ObservationIgnored let appSettingsPersist = DebouncedAction(intervalMilliseconds: 100)
    /// Core's last word on the settings it owns, for `commitAppSettings` to
    /// diff against. `nil` until the first state lands, which is what makes a
    /// fresh install send everything once.
    @ObservationIgnored var lastAppliedAppSettings: AppSettings?
    /// Claimed when a settings edit is scheduled, cleared when it lands. Held
    /// across the debounce so `awaitPendingCoreStateWrites` covers the wait,
    /// and so an in-flight load cannot adopt over an edit not yet sent.
    @ObservationIgnored var pendingAppSettingsEpoch: UInt64?
    // Each `DebouncedAction` captures its target's coalescing window at
    // construction so the interval is visible next to the field declaration
    // instead of being a magic number buried in an async closure.
    @ObservationIgnored private let priceAlertsPersist = DebouncedAction(intervalMilliseconds: 100)
    @ObservationIgnored private let livePricesPersist = DebouncedAction(intervalMilliseconds: 200)
    @ObservationIgnored private let tokenPreferencesPersist = DebouncedAction(intervalMilliseconds: 50)
    @ObservationIgnored private let tokenPreferenceRebuild = DebouncedAction(intervalMilliseconds: 30)
    @ObservationIgnored private let transactionRebuild = DebouncedAction(intervalMilliseconds: 30)
    /// Recorded transactions.
    ///
    /// Domain state: core owns the store and its persistence. This is a
    /// projection — assigning to it would only desynchronise the two, so it is
    /// `private(set)` and changed through `recordTransactions` /
    /// `removeTransactions` / `clearAllTransactions`, which send commands.
    private(set) var transactions: [TransactionRecord] = [] {
        didSet {
            transactionRevision &+= 1
            lastObservedTransactions = transactions
            if !suppressSideEffects {
                transactionRebuild.fire { [weak self] in
                    Task { @MainActor [weak self] in await self?.rebuildTransactionDerivedState() }
                }
            }
        }
    }

    /// The only place the transaction projection is written. Everything else
    /// goes through the command helpers in `AppState+CoreStateStore.swift`,
    /// which keep the store in step with it.
    func setTransactionProjection(_ records: [TransactionRecord]) {
        transactions = records
    }
    var normalizedHistoryIndex: [NormalizedHistoryEntry] = [] {
        didSet { normalizedHistoryRevision &+= 1 }
    }
    private(set) var transactionRevision: UInt64 = 0
    private(set) var normalizedHistoryRevision: UInt64 = 0
    @ObservationIgnored var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    @ObservationIgnored var cachedFirstActivityDateByWalletID: [String: Date] = [:]
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
    /// Imported wallets.
    ///
    /// Domain state: core owns the list and persists it. This is a projection
    /// of `CoreAppState.wallets`, rendered into the shape the views use — see
    /// `WalletSummary::to_imported_wallet`. `private(set)`, because assigning
    /// to it would only desynchronise it from core; change it with
    /// `recordWallets` / `removeWallet` / `clearAllWallets`.
    private(set) var wallets: [ImportedWallet] = [] {
        didSet {
            walletsRevision &+= 1
            scheduleWalletCollectionSideEffects()
        }
    }

    /// The only place the wallet projection is written. Everything else goes
    /// through a `StateCommand` and lands back here.
    func setWalletProjection(_ records: [ImportedWallet]) {
        wallets = records
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
    /// How long the maintenance loop sleeps before asking core again. Core
    /// answers it with the plan; the loop used to work it out from two
    /// constants and a derived flag.
    @ObservationIgnored var lastMaintenancePollSeconds: UInt64 = 30
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

    // ── Funds Finder backing storage ───────────────────────────────────────
    // Observed by FundsFinderView via AppState+FundsFinder.swift computed vars.
    var _isFundsFinderScanning: Bool = false
    var _fundsFinderProgress: Double = 0
    var _fundsFinderHits: [FundsFinderHit] = []
    var _fundsFinderCheckedCount: Int = 0
    var _fundsFinderTotalCount: Int = 0
    var _fundsFinderScanError: String? = nil
    @ObservationIgnored var _fundsFinderScanTask: Task<Void, Never>? = nil
    var isShowingFundsFinder: Bool = false
    /// Read-only view of the keypool for the diagnostics screen.
    ///
    /// Core answers without recording, so reporting the state never reserves
    /// anything.
    func chainKeypoolDiagnostics(for chainName: String) async -> [ChainKeypoolDiagnostic] {
        var rows: [ChainKeypoolDiagnostic] = []
        for wallet in wallets where wallet.selectedChain == chainName || walletHasAddress(for: wallet, chainName: chainName) {
            let state = await keypoolStateForDisplay(for: wallet, chainName: chainName)
            let reservedIndex = state.reservedReceiveIndex
            rows.append(
                ChainKeypoolDiagnostic(
                    walletID: wallet.id, walletName: wallet.name, chainName: chainName, reservedReceiveIndex: reservedIndex,
                    reservedReceivePath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
                    reservedReceiveAddress: await reservedReceiveAddressForDisplay(
                        for: wallet, chainName: chainName),
                    nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex
                ))
        }
        return rows
        .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }
    }
    var pricingProvider: PricingProvider = .coinGecko {
        didSet {
            guard pricingProvider != oldValue else { return }
            commitAppSettingsSoon()
        }
    }
    /// Display currency for prices and totals.
    ///
    /// Domain state: core owns it, persists it, and the CLI reads and writes the
    /// same value. This is a mirror of core's copy — reading it is free, and
    /// assigning to it sends a command rather than storing anything. The mirror
    /// updates when core answers, which is what re-renders observers.
    ///
    /// Do not add a `didSet` that persists here. One owner.
    var selectedFiatCurrency: FiatCurrency {
        get { coreFiatCurrency }
        set {
            guard newValue != coreFiatCurrency else { return }
            Task { @MainActor [weak self] in await self?.setFiatCurrency(newValue) }
        }
    }
    private(set) var coreFiatCurrency: FiatCurrency = .usd

    // Core round-trips are async and can overlap: the launch reload runs
    // concurrently with whatever the user is doing. Each one claims an epoch
    // before it awaits, and a result from an epoch older than the last applied
    // is dropped — otherwise a slow reload lands after a command and reverts
    // the mirror to what core held before that command ran.
    @ObservationIgnored private var coreStateEpoch: UInt64 = 0
    @ObservationIgnored private var appliedCoreStateEpoch: UInt64 = 0

    /// Claim an epoch before awaiting core. Pass it back to `applyCoreState`.
    func beginCoreStateRead() -> UInt64 {
        coreStateEpoch &+= 1
        return coreStateEpoch
    }

    /// Mark an epoch settled without adopting a state — the command failed.
    /// Without this a failed write would leave `awaitPendingCoreStateWrites`
    /// waiting forever.
    func finishCoreStateRead(_ epoch: UInt64) {
        if epoch > appliedCoreStateEpoch { appliedCoreStateEpoch = epoch }
    }

    /// Wait until every command sent so far has come back and been applied.
    ///
    /// Mirrors settle a runloop hop after the assignment that sends them, which
    /// is fine for a UI and awkward for a test asserting the effect. Tests
    /// await this rather than each deriving the rule locally.
    func awaitPendingCoreStateWrites() async {
        while appliedCoreStateEpoch < coreStateEpoch {
            await Task.yield()
        }
    }

    /// The only place the core-owned mirrors are written. Everything else goes
    /// through a `StateCommand` and lands back here.
    func applyCoreState(_ state: CoreAppState, epoch: UInt64) {
        guard epoch >= appliedCoreStateEpoch else { return }
        appliedCoreStateEpoch = epoch
        coreFiatCurrency = FiatCurrency(rawValue: state.settings.fiatCurrencyCode) ?? .usd
        adoptAppSettings(state.settings)
        coreAddressBook = state.addressBook
        if state.tokenPreferences != tokenPreferences { tokenPreferences = state.tokenPreferences }
        if state.priceAlerts != priceAlerts { priceAlerts = state.priceAlerts }
        // Synchronous on purpose: the render path reads this, and adopting it a
        // tick later quotes a testnet at mainnet prices in between.
        let unpriced = Set(coreUnpricedChainNames(settings: state.settings))
        if unpriced != unpricedChainNames { unpricedChainNames = unpriced }
        if state.settings.feePriorityByChain != feePriorityByChain {
            feePriorityByChain = state.settings.feePriorityByChain
        }
        if state.settings.networkChainByFamily != networkChainByFamily {
            networkChainByFamily = state.settings.networkChainByFamily
        }
        let pins = state.settings.pinnedDashboardAssetSymbols
        if pins != cachedPinnedDashboardAssetSymbols {
            cachedPinnedDashboardAssetSymbols = pins
            rebuildDashboardDerivedState()
        }
    }
    var fiatRateProvider: FiatRateProvider = .openER {
        didSet {
            guard fiatRateProvider != oldValue else { return }
            commitAppSettingsSoon()
            Task { @MainActor [weak self] in await self?.refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    var ethereumRPCEndpoint: String = "" {
        didSet {
            guard ethereumRPCEndpoint != oldValue else { return }
            commitAppSettingsSoon()
        }
    }
    /// Which network each chain family is on, as `mainnet id -> selected id`.
    ///
    /// Core owns it; this is the mirror the UI binds to, same shape as
    /// `tokenPreferences`. Absent means mainnet. It replaced three typed
    /// properties, each with its own enum and its own `didSet` — so adding a
    /// fourth family meant a fourth of each.
    private(set) var networkChainByFamily: [String: String] = [:] {
        didSet {
            guard networkChainByFamily != oldValue else { return }
            for family in Set(networkChainByFamily.keys).union(oldValue.keys)
            where networkChainByFamily[family] != oldValue[family] {
                onNetworkChainChanged(family: family)
            }
        }
    }

    /// Core owns it; this is the mirror the fee pickers bind to. Absent means
    /// `.normal`, so the map is empty until the user picks something.
    ///
    /// It replaced three stores of one preference: Bitcoin and Dogecoin each
    /// had a settings field and a Swift enum of their own, and the other
    /// seventy-six shared a dictionary this class persisted itself.
    private(set) var feePriorityByChain: [String: String] = [:] {
        didSet {
            guard feePriorityByChain != oldValue else { return }
            commitAppSettingsSoon()
        }
    }

    /// Forget every chain's preference, on a wipe.
    func clearFeePriorities() { feePriorityByChain = [:] }

    /// Pick a chain's confirmation preference. Core normalizes the value and
    /// drops it again when it is the default.
    func setFeePriority(_ rawValue: String, forChain chainName: String) {
        if rawValue == "normal" {
            feePriorityByChain.removeValue(forKey: chainName)
        } else {
            feePriorityByChain[chainName] = rawValue
        }
    }

    /// The chain id this family is on.
    func networkChainID(forFamily family: String) -> NetworkChainID {
        networkChainByFamily[family] ?? family
    }

    /// Switch a family's network. Core stores it and hands the list back.
    func selectNetworkChain(_ chainID: NetworkChainID) {
        commitNetworkChain(chainID)
    }

    /// The chain-scoped work a network switch implies. Reserved indices and
    /// discovered addresses belong to the network they were derived on.
    private func onNetworkChainChanged(family: String) {
        let name = (Chain(id: family)?.displayName ?? family)
        resetHistoryPaginationForChain(family)
        Task {
            try? await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: name)
            try? await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: name)
        }
    }
    var etherscanAPIKey: String = "" {
        didSet {
            guard etherscanAPIKey != oldValue else { return }
            commitAppSettingsSoon()
            WalletServiceBridge.shared.setEtherscanAPIKey(etherscanAPIKey)
        }
    }
    var moneroBackendBaseURL: String = "" {
        didSet {
            guard moneroBackendBaseURL != oldValue else { return }
            commitAppSettingsSoon()
        }
    }
    var moneroBackendAPIKey: String = "" {
        didSet {
            guard moneroBackendAPIKey != oldValue else { return }
            commitAppSettingsSoon()
        }
    }
    var isUserInitiatedRefreshInProgress: Bool = false
    /// Price alerts.
    ///
    /// Domain state: core owns the list, the rule that a target must be
    /// positive, and the persistence. Same mirror shape as `tokenPreferences`
    /// — assigning sends `SetPriceAlerts` and the stored list lands back here
    /// through `applyCoreState`, where the guard stops the second pass.
    var priceAlerts: [PriceAlertRule] = [] {
        didSet {
            guard priceAlerts != oldValue else { return }
            priceAlertsPersist.fire { [weak self] in self?.commitPriceAlerts() }
        }
    }
    /// Saved recipients.
    ///
    /// Domain state: core owns the list, the rules about what may be saved, and
    /// the persistence. This is a mirror — see `coreFiatCurrency` for the same
    /// pattern. Mutate it with `addAddressBookEntry` / `renameAddressBookEntry`
    /// / `removeAddressBookEntry`, which send commands.
    var addressBook: [AddressBookEntry] { coreAddressBook }
    private(set) var coreAddressBook: [AddressBookEntry] = []
    /// Why core refused the last address-book change, if it did.
    var addressBookError: String?
    var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            guard tokenPreferences != oldValue else { return }
            // Core is the store. It also clamps the decimal fields, so the
            // normalised list comes back and lands here again — the guard above
            // stops that second pass, since by then it matches.
            tokenPreferencesPersist.fire { [weak self] in self?.commitTokenPreferences() }
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
            // Prices only change on a refresh cycle and the rebuild is an
            // in-memory pass, so it is cheaper to do than to decide about.
            rebuildDashboardDerivedState()
        }
    }
    var fiatRatesFromUSD: [String: Double] = [:]
    var fiatRatesRefreshError: String? = nil
    var quoteRefreshError: String? = nil
    /// Projection of `CoreAppState.settings.pinnedDashboardAssetSymbols`.
    /// Written only by `applyCoreState`; change it with `setPinnedDashboardAssets`.
    private(set) var cachedPinnedDashboardAssetSymbols: [String] = [] {
        didSet { bumpCachesRevision() }
    }
    var cachedDashboardPinOptionBySymbol: [String: DashboardPinOption] = [:] { didSet { bumpCachesRevision() } }
    var cachedAvailableDashboardPinOptions: [DashboardPinOption] = [] { didSet { bumpCachesRevision() } }
    var cachedDashboardAssetGroups: [DashboardAssetGroup] = [] { didSet { bumpCachesRevision() } }
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
    @ObservationIgnored var cachedAssetDecimalsResolutions: [String: (supported: UInt32, display: UInt32)] = [:]
/// Chains whose selected network is a testnet, so their coins are not quoted.
    ///
    /// Core decides; this is the projection the render path reads.
    private(set) var unpricedChainNames: Set<String> = []
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
    var bitcoinEsploraEndpoints: String = "" {
        didSet {
            commitAppSettingsSoon()
            resetHistoryPaginationForChain(Chain.bitcoin.id)
        }
    }
    /// Bounded by core, which refuses a gap outside 1...200 — a gap of zero
    /// finds no addresses. The clamp used to be here, and only here.
    var bitcoinStopGap: Int = 10 {
        didSet {
            guard bitcoinStopGap != oldValue else { return }
            commitAppSettingsSoon()
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
            commitAppSettingsSoon()
        }
    }
    @ObservationIgnored var pendingSendPreviewRefreshChains: Set<String> = []
    var discoveredUTXOAddressesByChain: [String: [String: [String]]] = [:]
    var isLoadingMoreOnChainHistory: Bool = false
    let diagnostics = WalletDiagnosticsState()
    /// Whether a chain's deep rescan is running, and when it last finished.
    ///
    /// Ten forwarding accessors used to name five chains twice each, over this
    /// same keyed table.
    struct UTXORescanState { var isRunning: Bool = false; var lastRunAt: Date? = nil }
    var utxoRescanStateByChain: [String: UTXORescanState] = [:]
    subscript(rescanFor chainName: String) -> UTXORescanState {
        get { utxoRescanStateByChain[chainName] ?? .init() }
        set { utxoRescanStateByChain[chainName] = newValue }
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
    /// Whether Tor is turned on. Persisted via UserDefaults; default false.
    var torEnabled: Bool = false {
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
    static let fiatRatesFromUSDDefaultsKey = "pricing.fiatRatesFromUSD.v1"
    static let livePricesDefaultsKey = "pricing.livePrices.v1"

    static let walletsAccount = "wallets.snapshot"
    static let walletsCoreSnapshotAccount = "wallets.core.snapshot.v1"


    static let tokenPreferencesDefaultsKey = "settings.tokenPreferences.v1"
    /// The four preferences this platform keeps for itself — see
    /// `PlatformPreferences`. The twenty keys that stood beside it, one per
    /// setting, went with the settings into core.
    static let platformPreferencesDefaultsKey = "settings.platform.v1"
    static let assetDisplayDecimalsByChainDefaultsKey = "settings.assetDisplayDecimalsByChain.v1"

    static let torEnabledDefaultsKey = "tor.enabled"
    static let torUseCustomProxyDefaultsKey = "tor.useCustomProxy"
    static let torCustomProxyAddressDefaultsKey = "tor.customProxyAddress"
    static let torKillSwitchDefaultsKey = "tor.killSwitch"

    static let operationalLogsDefaultsKey = "operational.logs.v1"
    static let chainKeypoolDefaultsKey = "chain.keypool.snapshot.v1"
    static let chainOwnedAddressMapDefaultsKey = "chain.ownedAddressMap.snapshot.v1"
    static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    static let installMarkerDefaultsKey = "app.install.marker.v1"
    static let utxoDiscoveryGapLimit = 3
    static let utxoDiscoveryMaxIndex = 40
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
        try? SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
        cachedSigningMaterialWalletIDs.remove(walletID)
        cachedPrivateKeyBackedWalletIDs.remove(walletID)
        cachedPasswordProtectedWalletIDs.remove(walletID)
        cachedSecretDescriptorsByWalletID[walletID] = nil
    }
    func parsedBitcoinEsploraEndpoints() -> [String] { parseBitcoinEsploraEndpoints(raw: bitcoinEsploraEndpoints) }
    func effectiveBitcoinEsploraEndpoints() -> [String] {
        let configured = parsedBitcoinEsploraEndpoints()
        if !configured.isEmpty { return configured }
        return AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(forChainID: networkChainID(forFamily: "bitcoin"))
    }
    var bitcoinEsploraEndpointsValidationError: String? {
        endpointValidationError(field: .bitcoinEsploraList, raw: bitcoinEsploraEndpoints)
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
    private static let utxoPostSendChains: Set<String> = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"
    ]
    func runPostSendRefreshActions(for chainName: String, verificationStatus: SendBroadcastVerificationStatus) async {
        applySendVerificationStatus(verificationStatus, chainName: chainName)
        noteSendBroadcastVerification(
            chainName: chainName, verificationStatus: verificationStatus,
            transactionHash: lastSentTransaction?.chainName == chainName ? lastSentTransaction?.transactionHash : nil
        )
        let usePending = isEVMChain(chainName) || Self.utxoPostSendChains.contains(chainName)
        let descriptor = WalletChainID(chainName).flatMap { Self.chainRefreshDescriptors[$0] }
        async let balanceRefresh: () = refreshBalances()
        async let chainRefresh: () = {
            guard let descriptor else { return }
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
    }
    init() {
        // Wire preferences' side-effect closures back to AppState. Using
        // closures (rather than an observation loop) keeps the coupling
        // explicit and keeps the preferences class cleanly isolated.
        preferences.persistHandler = { [weak self] in self?.commitAppSettingsSoon() }
        preferences.platformPersistHandler = { [weak self] in self?.persistPlatformPreferences() }
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
        await rebuildTransactionDerivedState()
        startMaintenanceLoopIfNeeded()
        SpectraSecretStoreAdapter.registerWithBridge()
        setupRustRefreshEngine()
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
        tokenPreferencesPersist.cancel()
        livePricesPersist.cancel()
        priceAlertsPersist.cancel()
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
                return localizedStoreFormat("Enter a valid %@ token contract address.", chain.rawValue)
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
    /// The canonical form of a tracked token's contract address.
    ///
    /// Was a twelve-name EVM arm, then Aptos, Sui, TON and a lowercase default
    /// — a second copy of `normalize_token_identifier`, which core keys by
    /// chain. The two disagreed about TON: this side trimmed, core lowercased,
    /// and a jetton master address is case-significant. Core states the TON rule
    /// now and this asks it.
    func normalizedTrackedTokenIdentifier(for chain: TokenTrackingChain, contractAddress: String) -> String {
        normalizeTokenIdentifier(contractAddress: contractAddress, chainName: chain.rawValue) ?? ""
    }
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
                    normalizedTrackedTokenIdentifier(for: .aptos, contractAddress: entry.contractAddress),
                    AptosBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals),
                        coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
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
    var ethereumRPCEndpointValidationError: String? {
        endpointValidationError(field: .ethereumRpc, raw: ethereumRPCEndpoint)
    }
    var moneroBackendBaseURLValidationError: String? {
        endpointValidationError(field: .moneroBackend, raw: moneroBackendBaseURL)
    }

}
