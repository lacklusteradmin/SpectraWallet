import Foundation
import SwiftUI
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
// `AppState` is the app's central `@Observable` store. Its methods live in one
// `AppState+<Domain>.swift` file per domain — send, receive, import, address
// book, networks, app lock, maintenance, reset and so on — and every extension
// attaches methods to the same instance: there is no per-extension state.
//
// The extensions hide the line count but not the coupling. Derived state that
// can be one value already is (`WalletDerivedCache`, rebuilt in one
// assignment); a domain that grows state of its own belongs in a composed type
// `AppState` owns, not in more properties here.
//
// Adding a method? Put it in its domain's file, or start one for a new domain,
// rather than growing this file or a neighbour's.
@MainActor
@Observable
final class AppState {
    @ObservationIgnored let bridge: WalletServiceBridge // Service identity is not view state.
    @ObservationIgnored let servicesEnabled: Bool // Controls automatic platform work.
    static let exportFilenameTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    // Each `DebouncedAction` captures its target's coalescing window at
    // construction so the interval is visible next to the field declaration
    // instead of being a magic number buried in an async closure.
    @ObservationIgnored private let tokenPreferenceRebuild = DebouncedAction(intervalMilliseconds: 30)
    /// Recorded transactions.
    ///
    /// Domain state: core owns the store and its persistence. This is a
    /// projection — assigning to it would only desynchronise the two, so it is
    /// `private(set)` and replaced only with what core returns
    /// (`adoptTransactionsFromCore`).
    private(set) var transactions: [TransactionRecord] = [] {
        didSet { transactionRevision &+= 1 }
    }

    /// The only place the transaction projection is written.
    func setTransactionProjection(_ records: [TransactionRecord]) {
        transactions = records
    }
    var historyReadError: String? = nil
    @ObservationIgnored var portfolioSnapshotRevision: UInt64 = 0 // Core snapshot order, not request order.
    @ObservationIgnored var transactionSnapshotRevision: UInt64 = 0 // Reject delayed history summaries.
    var portfolioValuation: PortfolioValuation?
    var transactionCount: UInt64 = 0
    /// The pending sends core says can still be replaced on their chain.
    /// Adopted with the rest of the transaction-derived views; observed,
    /// because the composer's Speed Up / Cancel buttons read it.
    var replaceableSends: [ReplaceableSend] = []
    private(set) var transactionRevision: UInt64 = 0
    @ObservationIgnored var cachedFirstActivityDateByWalletId: [String: Date] = [:]
    /// Imported wallets.
    ///
    /// Domain state: core owns the list and persists it. This is a projection
    /// of `CoreAppState.wallets`, rendered into the shape the views use — see
    /// `WalletState::to_wallet_view`. `private(set)`, because assigning to it
    /// would only desynchronise it from core; change it with import and field
    /// intents, wallet deletion, or a reset. Replacing it rebuilds the derived
    /// caches via `scheduleWalletCollectionSideEffects`.
    ///
    /// **Observation note for view code**: SwiftUI's `@Observable` tracks
    /// access to this property as a whole — any mutation invalidates every
    /// view that read `store.wallets` for any reason, even a single
    /// wallet's balance update. Prefer reading from `cachedWalletById[id]`
    /// (or another `walletDerivedCache` projection) when you only need a
    /// specific wallet — those projections are recomputed on rebuild but
    /// observed views see only the relevant change once SwiftUI's
    /// dictionary-key access tracking kicks in. New views that read from
    /// `wallets` directly should justify it (e.g. they actually iterate
    /// the entire collection).
    private(set) var wallets: [WalletView] = [] {
        didSet {
            walletsRevision &+= 1
            scheduleWalletCollectionSideEffects()
        }
    }

    /// The only place the wallet projection is written. Everything else goes
    /// through a `StateCommand` and lands back here.
    func setWalletProjection(_ records: [WalletView]) {
        wallets = records
    }
    @ObservationIgnored private let walletSideEffectsDebounce = DebouncedAction(intervalMilliseconds: 30)
    @ObservationIgnored var balanceFlushTask: Task<Void, Never>?
    /// Debounce wallet side effects from `wallets.didSet`. Use a cancellable
    /// task: cancelling an observation-backed checked continuation does not
    /// resume it and can retain the state indefinitely.
    private func scheduleWalletCollectionSideEffects() {
        walletSideEffectsDebounce.fire { [weak self] in
            self?.applyWalletCollectionSideEffects()
        }
    }
    private(set) var walletsRevision: UInt64 = 0
    // Derived caches. Recomputed by `applyWalletCollectionSideEffects`,
    // `rebuildWalletDerivedState` and
    // `rebuildTokenPreferenceDerivedState`.
    //
    // No revision counter here. Under `@Observable` a view already tracks the
    // properties it reads, so a counter bumped on every cache write could only
    // make things worse: a view that observed it would invalidate on every
    // unrelated write. `walletsRevision` above is different — two views watch
    // it with `onChange`, which needs a value that changes.
    /// Bundled derived state of the wallet collection. Rebuilt as a single
    /// value, so the rebuild is one assignment rather than 17 mutations; the
    /// `cached*` properties below read fields out of it.
    var walletDerivedCache: WalletDerivedCache = .empty
    var cachedWalletById: [String: WalletView] { walletDerivedCache.walletById }
    var cachedIncludedPortfolioWallets: [WalletView] { walletDerivedCache.includedPortfolioWallets }
    var cachedPortfolio: [Coin] { walletDerivedCache.portfolio }
    var cachedAvailableSendCoinsByWalletId: [String: [Coin]] { walletDerivedCache.availableSendCoinsByWalletId }
    var cachedAvailableReceiveCoinsByWalletId: [String: [Coin]] { walletDerivedCache.availableReceiveCoinsByWalletId }
    var cachedSendEnabledWallets: [WalletView] { walletDerivedCache.sendEnabledWallets }
    var cachedReceiveEnabledWallets: [WalletView] { walletDerivedCache.receiveEnabledWallets }
    var cachedRefreshableChainNames: Set<String> { walletDerivedCache.refreshableChainNames }
    let importDraft = WalletImportDraft()
    var importError: String? = nil
    var isImportingWallet: Bool = false
    var isShowingWalletImporter: Bool = false
    var isShowingAddWalletEntry: Bool = false
    var isShowingSendSheet: Bool = false
    var isShowingReceiveSheet: Bool = false
    var walletPendingDeletion: WalletView?
    var editingWalletId: String? = nil
    var sendWalletId: String = ""
    var sendHoldingKey: String = ""
    var sendAmount: String = ""
    var sendAddress: String = ""
    var sendError: String? {
        get { sendSession.error }
        set { sendSession.error = newValue }
    }
    var sendDestinationRiskWarning: String? = nil
    var sendDestinationInfoMessage: String? = nil
    var isCheckingSendDestinationBalance: Bool = false
    var isShowingHighRiskSendConfirmation: Bool = false
    var sendVerificationNotice: String? = nil
    var sendVerificationNoticeIsWarning: Bool = false
    var receiveWalletId: String = ""
    var receiveHoldingKey: String = ""
    var receiveResolvedAddress: String = ""
    var receiveAddressError: String?
    @ObservationIgnored var receiveAddressRequestId = UUID() // Reject stale asynchronous results.
    var isResolvingReceiveAddress: Bool = false
    var selectedMainTab: MainAppTab = .home
    var isAppLocked: Bool = false
    var appLockError: String? = nil
    /// Set when core could not be given the keychain-backed secret store.
    /// Observed: nothing that touches a seed or a private key works without
    /// it, so the failure has to reach the user rather than only the log.
    var secretStoreRegistrationError: String? = nil
    var isPreparingReplacementContext: Bool = false
    /// Chains currently computing a send fee preview. Observed by send UI to show loading state.
    var preparingChains: Set<String> = []
    @ObservationIgnored var sendDestinationProbeRequestId = UUID() // Reject stale recipient probes.
    let sendSession = SendSession()
    var sendArtifact: SendArtifact? { sendSession.artifact }
    var savedSendArtifacts: [SendArtifact] = []
    var sendEndpointChoices: [String] { sendSession.endpoints }
    var selectedSendEndpoints: Set<String> {
        get { sendSession.selectedEndpoints }
        set { sendSession.selectedEndpoints = newValue }
    }
    @ObservationIgnored var isRefreshingLivePrices = false
    @ObservationIgnored var isRefreshingFiatRates = false
    /// How long the maintenance loop sleeps before asking core again, as supplied by core.
    @ObservationIgnored var lastMaintenancePollSeconds: UInt64 = 30
    @ObservationIgnored var isNetworkReachable: Bool = true
    @ObservationIgnored var isConstrainedNetwork: Bool = false
    @ObservationIgnored var isExpensiveNetwork: Bool = false
    var stagedSendTransaction: TransactionRecord? {
        guard let id = sendArtifact?.id else { return nil }
        return transactions.first { $0.id == id }
    }
    var lastPendingTransactionRefreshAt: Date? = nil
    // Send previews live in a dedicated sub-store so updates during the send flow
    // do not invalidate every view that observes AppState. Views that need the
    // preview values should observe `sendPreviewStore` directly.
    let sendPreviewStore = SendPreviewStore()
    var isSending: Bool { sendSession.operation != nil }
    let chainDiagnosticsState = WalletChainDiagnosticsState()

    /// Read-only keypool diagnostics. Reading does not reserve an address.
    /// The reserved address and path are those recorded when the index was handed out.
    func chainKeypoolDiagnostics(for chainName: String) async throws -> [KeypoolDiagnostic] {
        try await self.bridge.keypoolDiagnostics(chainName: chainName)
    }
    /// Display currency for prices and totals.
    ///
    /// Core's setting: reading it reads `appSettings`, and assigning to it
    /// sends a command rather than storing anything.
    var selectedFiatCurrency: FiatCurrency {
        get { appSettings.fiatCurrency }
        set {
            guard newValue != appSettings.fiatCurrency else { return }
            Task { @MainActor [weak self] in await self?.setFiatCurrency(newValue) }
        }
    }

    /// The last committed core settings, with pending edits applied by core's rule.
    /// Views change fields through `updateSetting`.
    private(set) var appSettings: AppSettings = appSettingsDefaults()
    @ObservationIgnored private(set) var committedAppSettings: AppSettings = appSettingsDefaults() // Runtime effects use only core-committed settings.
    /// Pending edits protect the optimistic form from readback. Committed
    /// settings still advance independently to drive runtime effects.
    @ObservationIgnored private var settingCommandsInFlight = 0
    @ObservationIgnored private var settingCommandTask: Task<Void, Never>?

    /// Change one setting.
    ///
    /// Shown at once — `appSettingsApplying` is the reducer's rule, so the value
    /// shown is the value core will store — and sent to core in order. Core's
    /// committed settings replace the shown ones when the last edit in flight
    /// lands, or when one fails.
    func updateSetting(_ update: AppSettingUpdate) {
        let before = appSettings
        let after = appSettingsApplying(settings: before, update: update)
        guard after != before else { return }
        appSettings = after
        settingCommandsInFlight += 1
        let previous = settingCommandTask
        settingCommandTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let transition = try await self.bridge.applyStateCommand(.setAppSetting(update: update))
                self.settingCommandsInFlight -= 1
                self.applyCoreState(transition.state)
            } catch {
                self.settingCommandsInFlight -= 1
                // A failed write never changes runtime services. Restore the
                // committed projection even if storage cannot be read again.
                if self.settingCommandsInFlight == 0 { self.appSettings = self.committedAppSettings }
                self.appendOperationalLog(.error, category: "Settings", message: error.localizedDescription)
                if let state = try? await self.bridge.appState() {
                    self.applyCoreState(state)
                }
            }
        }
    }

    /// Wait until every setting edit sent so far has been answered.
    func awaitPendingSettingCommands() async {
        await settingCommandTask?.value
    }

    /// A two-way binding onto one setting, for a toggle, picker or slider.
    func settingBinding<Value>(
        _ keyPath: KeyPath<AppSettings, Value>, _ update: @escaping (Value) -> AppSettingUpdate
    ) -> Binding<Value> {
        Binding(
            get: { self.appSettings[keyPath: keyPath] },
            set: { self.updateSetting(update($0)) })
    }

    /// What a settings change sets in motion on this platform: Tor's client,
    /// and the notification permission a newly enabled alert needs.
    private func reactToSettingsChange(from before: AppSettings) {
        let appSettings = committedAppSettings
        if (appSettings.useTransactionStatusNotifications && !before.useTransactionStatusNotifications)
            || (appSettings.useLargeMovementNotifications && !before.useLargeMovementNotifications)
        {
            requestNotificationPermissionIfNeeded()
        }
    }

    @ObservationIgnored private(set) var appliedCoreStateRevision: UInt64 = 0

    /// The only place the core-owned mirrors are written. Everything else goes
    /// through a `StateCommand` and lands back here.
    @discardableResult
    func applyCoreState(_ state: CoreAppState, refreshPortfolio: Bool = true) -> Bool {
        guard state.revision >= appliedCoreStateRevision else { return false }
        appliedCoreStateRevision = state.revision
        if state.settings != committedAppSettings {
            let before = committedAppSettings
            committedAppSettings = state.settings
            reactToSettingsChange(from: before)
        }
        if settingCommandsInFlight == 0 { appSettings = state.settings }
        coreAddressBook = state.addressBook
        if state.tokenPreferences != tokenPreferences { tokenPreferences = state.tokenPreferences }
        if state.priceAlerts != priceAlerts { priceAlerts = state.priceAlerts }
        if refreshPortfolio { rebuildWalletDerivedState() }
        // Synchronous on purpose: the render path reads this, and adopting it a
        // tick later quotes a testnet at mainnet prices in between.
        let unpriced = Set(Spectra.unpricedChainNames())
        if unpriced != unpricedChainNames { unpricedChainNames = unpriced }
        return true
    }
    /// A chain with no stored pick confirms at the default rate.
    func feePriority(forChain chainName: String) -> FeePriority {
        appSettings.feePriorityByChain[chainName] ?? .normal
    }
    func setFeePriority(_ priority: FeePriority, forChain chainName: String) {
        updateSetting(.feePriority(chain: chainName, value: priority))
    }
    /// A family with no selection reports itself, so the mainnet id is the
    /// default without being stored as one.
    func selectedChainId(forFamily family: String) -> String {
        appSettings.selectedChainByFamily[family] ?? family
    }
    var isUserInitiatedRefreshInProgress: Bool = false
    /// Read-only projection adopted from core; edits send individual intents.
    private(set) var priceAlerts: [PriceAlertRule] = []
    /// Saved recipients.
    ///
    /// Domain state: core owns the list, the rules about what may be saved, and
    /// the persistence. This is core's list as last adopted. Mutate it with
    /// `addAddressBookEntry` / `renameAddressBookEntry` /
    /// `removeAddressBookEntry`, which send commands.
    var addressBook: [AddressBookEntry] { coreAddressBook }
    private(set) var coreAddressBook: [AddressBookEntry] = []
    /// Why core refused the last address-book change, if it did.
    var addressBookError: String?
    @ObservationIgnored var addressBookCommandTask: Task<Void, Never>?
    /// The tracked-token projection. Change it through `addCustomTokenPreference`,
    /// `removeCustomTokenPreference`, or `setTokenPreferencesEnabled`.
    private(set) var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            guard tokenPreferences != oldValue else { return }
            // Token-decimals overrides feed into the Rust asset-decimals
            // resolver, so drop the memoized cache when the overrides change.
            tokenPreferenceRebuild.fire { [weak self] in
                guard let self else { return }
                self.rebuildTokenPreferenceDerivedState()
            }
        }
    }
    /// Why core refused the last token-preference change, if it did.
    var tokenPreferenceError: String?
    @ObservationIgnored var stateCommandTask: Task<Void, Never>?
    // Prices and groups are adopted together from the same core snapshot.
    var livePrices: [String: Double] = [:]
    /// USD → display-currency rates, as core holds them. A projection: core
    /// fetches, merges and stores them, and `applyCoreState` adopts the result.
    var fiatRatesFromUSD: [String: Double] = [:]
    var fiatRatesRefreshError: String? = nil
    var quoteRefreshError: String? = nil
    var cachedAvailableDashboardPinOptions: [DashboardPinOption] = []
    var cachedDashboardAssetGroups: [DashboardAssetGroup] = []

    var cachedTokenPreferenceByDeploymentId: [String: TokenPreferenceEntry] = [:]
    @ObservationIgnored var cachedCurrencyFormatters: [FiatCurrency: NumberFormatter] = [:]
    @ObservationIgnored var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    /// Concrete testnets are never quoted.
    ///
    /// Core decides; this is the projection the render path reads.
    private(set) var unpricedChainNames: Set<String> = []
    var useCustomEvmFees: Bool = false
    var customEvmMaxFeeGwei: String = ""
    var customEvmPriorityFeeGwei: String = ""
    var evmManualNonceEnabled: Bool = false
    var evmManualNonce: String = ""
    /// The five preferences this platform keeps for itself. Split out so views
    /// that only read them are not invalidated by wallet or balance changes.
    let preferences = AppUserPreferences()
    @ObservationIgnored var sendPreviewRequestId = UUID() // Reject every completion of a superseded preview.
    var isLoadingMoreOnChainHistory: Bool = false
    let diagnostics: WalletDiagnosticsState
    /// Whether a chain's deep rescan is running, and when it last finished.
    struct UTXORescanState { var isRunning: Bool = false; var lastRunAt: Date? = nil }
    var utxoRescanStateByChain: [String: UTXORescanState] = [:]
    subscript(rescanFor chainName: String) -> UTXORescanState {
        get { utxoRescanStateByChain[chainName] ?? .init() }
        set { utxoRescanStateByChain[chainName] = newValue }
    }
    @ObservationIgnored var userInitiatedRefreshTask: Task<Bool, Never>?
    @ObservationIgnored var importRefreshTask: Task<Void, Never>?
    @ObservationIgnored var walletSideEffectsTask: Task<Void, Never>?
    @ObservationIgnored var appIsActive = true
    @ObservationIgnored var maintenanceTask: Task<Void, Never>?

    // ── Tor routing ───────────────────────────────────────────────────────
    /// Live Tor bootstrap/connection state polled from Rust. Drives the
    /// dashboard indicator and the settings status row.
    var torStatus: TorStatus = .stopped
    /// Background task that polls `torStatus()` from Rust every second.
    @ObservationIgnored var torStatusPollingTask: Task<Void, Never>?
    #if canImport(Network)
        let networkPathMonitor = NWPathMonitor()
        let networkPathMonitorQueue = DispatchQueue(label: "spectra.network.monitor")
    #endif
    func walletRequiresSeedPhrasePassword(_ walletId: String) -> Bool {
        self.bridge.walletSecretState(walletId: walletId)?.isSealed ?? false
    }
    /// Whether this wallet can sign, and with what.
    ///
    /// Read from the store rather than from a cached descriptor: a sealed
    /// wallet has signing material even though a seed reveal cannot
    /// produce it without a password, and deriving this from that read would
    /// report such a wallet as watch-only.
    func walletHasSigningMaterial(_ walletId: String) -> Bool {
        self.bridge.walletSecretState(walletId: walletId)?.hasSigningMaterial ?? false
    }
    func isPrivateKeyBackedWallet(_ walletId: String) -> Bool {
        self.bridge.walletSecretState(walletId: walletId)?.hasPrivateKey ?? false
    }

    private func applyVerificationNotice(_ n: SendVerificationNotice) {
        sendVerificationNotice = n.notice
        sendVerificationNoticeIsWarning = n.isWarning
    }
    func clearSendVerificationNotice() {
        applyVerificationNotice(SendVerificationNotice(notice: nil, isWarning: false))
    }
    /// What core says about the last send, from its stored record.
    ///
    /// This rebuilt a snapshot of the record from the projection, with the
    /// kind and status spelled as strings, and handed it back to be judged.
    func updateStagedSendVerificationNotice() async {
        let session = sendSession.id
        guard let transactionId = stagedSendTransaction?.id else {
            clearSendVerificationNotice()
            return
        }
        guard let notice = try? await self.bridge.sendVerificationNotice(transactionId: transactionId),
            sendSession.isCurrent(session), stagedSendTransaction?.id == transactionId
        else { return }
        applyVerificationNotice(notice)
    }
    /// Refresh after broadcast and report the stored transaction status.
    /// Broadcast acceptance alone does not establish confirmation.
    func runPostSendRefreshActions(for chainName: String) async {
        if let chain = Chain(displayName: chainName) {
            await performCoreRefresh(.afterSend(chainId: chain.id))
        }
        await updateStagedSendVerificationNotice()
    }
    init(bridge: WalletServiceBridge = .shared, startServices: Bool = true) {
        self.bridge = bridge
        self.servicesEnabled = startServices
        self.diagnostics = WalletDiagnosticsState(bridge: bridge)
        guard startServices else { return }
        // Wire the preferences' side effect back to AppState. A closure rather
        // than an observation loop keeps the coupling explicit.
        preferences.useFaceIDDisabledHandler = { [weak self] in
            self?.isAppLocked = false
            self?.appLockError = nil
        }
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
    /// Registers the secret store before any launch work that might read a
    /// seed or a private key, and records the failure where both the user and
    /// a diagnostics export can see it.
    private func registerSecretStoreWithBridge() async {
        do {
            try SpectraSecretStoreAdapter.registerWithBridge(bridge)
            secretStoreRegistrationError = nil
        } catch {
            let message = String(describing: error)
            secretStoreRegistrationError = message
            appendOperationalLog(
                .error, category: "Secret Store", message: "Secret store registration failed: \(message)",
                source: "SpectraSecretStoreAdapter.registerWithBridge")
        }
    }
    private func warmUpAfterLaunch() async {
        await refreshTransactionProjection()
        startMaintenanceLoopIfNeeded()
        await registerSecretStoreWithBridge()
        setupRustRefreshEngine()
        observeTorStatus()
        async let projectionReload: () = reloadCoreProjections()
        async let fiatRefresh: () = refreshFiatExchangeRatesIfNeeded()
        _ = await (projectionReload, fiatRefresh)
        // Configuring the engine starts it; its first tick performs the launch sweep.
    }
    deinit {
        torStatusPollingTask?.cancel()
        maintenanceTask?.cancel()
        userInitiatedRefreshTask?.cancel()
        importRefreshTask?.cancel()
        walletSideEffectsTask?.cancel()
        balanceFlushTask?.cancel()
        settingCommandTask?.cancel()
        walletSideEffectsDebounce.cancel()
        tokenPreferenceRebuild.cancel()
        #if canImport(Network)
            networkPathMonitor.cancel()
        #endif
    }
    var canImportWallet: Bool {
        importDraft.canImportWallet
    }

    /// A token is addressed by what it is — its contract on its chain —
    /// rather than by an id this side and core would each have to spell the
    /// same way.
    private func tokenKey(_ entry: TokenPreferenceEntry) -> CoreTokenPreferenceKey {
        CoreTokenPreferenceKey(chainName: Chain(id: entry.token.chainId)?.displayName ?? entry.token.chainId, contract: entry.token.contract)
    }
    func setTokenPreferenceEnabled(_ entry: TokenPreferenceEntry, isEnabled: Bool) {
        setTokenPreferencesEnabled([entry], isEnabled: isEnabled)
    }
    func setTokenPreferencesEnabled(_ entries: [TokenPreferenceEntry], isEnabled: Bool) {
        let keys = entries.map(tokenKey)
        guard !keys.isEmpty else { return }
        Task { @MainActor [weak self] in
            await self?.sendTokenPreferenceCommand(
                .setTokenPreferencesEnabled(tokens: keys, isEnabled: isEnabled))
        }
    }
    func removeCustomTokenPreference(_ entry: TokenPreferenceEntry) {
        Task { @MainActor [weak self] in
            await self?.sendTokenPreferenceCommand(
                .removeCustomToken(chainName: Chain(id: entry.token.chainId)?.displayName ?? entry.token.chainId, contract: entry.token.contract))
        }
    }
    /// Send a token-preference command and mirror the result.
    ///
    /// Same shape as `sendAddressBookCommand`: core decides, the refusal comes
    /// back as an event carrying its reason, and this side supplies the words.
    private func sendTokenPreferenceCommand(_ command: StateCommand) async {
        guard let transition = try? await self.bridge.applyStateCommand(command)
        else {
            tokenPreferenceError = localizedStoreString("This token could not be saved.")
            return
        }
        applyCoreState(transition.state)
        tokenPreferenceError = tokenPreferenceRejection(in: transition.events)
            .map(tokenPreferenceRejectionMessage)
    }
    private func tokenPreferenceRejection(in events: [StateEvent]) -> TokenPreferenceRejection? {
        events.lazy.compactMap { event -> TokenPreferenceRejection? in
            guard case .tokenPreferenceRejected(let reason) = event else { return nil }
            return reason
        }.first
    }
    func tokenPreferenceRejectionMessage(_ reason: TokenPreferenceRejection) -> String {
        switch reason {
        case .unknownChain: return localizedStoreString("That network cannot hold tokens.")
        case .emptySymbol: return localizedStoreString("Symbol is required.")
        case .symbolTooLong: return localizedStoreString("Symbol is too long.")
        case .invalidPriceId: return localizedStoreString("Enter a price provider ID, not a URL or name.")
        case .emptyName: return localizedStoreString("Token name is required.")
        case .emptyContract: return localizedStoreString("Token identifier is required.")
        case .invalidContract: return localizedStoreString("That token identifier is not valid for this network.")
        case .duplicateToken: return localizedStoreString("This network already knows this token.")
        case .tooManyDecimals: return localizedStoreString("That is more decimal places than a token has.")
        case .builtInToken: return localizedStoreString("Built-in tokens cannot be edited or removed.")
        case .unknownToken: return localizedStoreString("That token is no longer in the list.")
        }
    }
    /// Teach the wallet a token the catalog does not ship.
    ///
    /// Returns the refusal to show beside the form, or `nil` once core has
    /// accepted it. Every rule behind that answer — the symbol, the contract's
    /// format for the chain that would host it, the duplicate, the precision,
    /// and where the row sorts — is the reducer's. This method held all of
    /// them, including a seven-arm switch over the hosting chains whose
    /// `default` assumed EVM.
    func addCustomTokenPreference(
        chain: TokenHostingChain, symbol: String, name: String, contractAddress: String,
        coingeckoId: String = "", coinpaprikaId: String = "", decimals: Int, editing: TokenPreferenceEntry? = nil
    ) async -> String? {
        guard decimals >= 0 else { return localizedStoreString("That is not a number of decimal places.") }

        let command: StateCommand
        if let editing {
            command = .updateCustomToken(
                chainName: Chain(id: editing.token.chainId)?.displayName ?? editing.token.chainId,
                contract: editing.token.contract, symbol: symbol, name: name,
                coingeckoId: coingeckoId, coinpaprikaId: coinpaprikaId, decimals: UInt32(decimals))
        } else {
            command = .addCustomToken(
                chainName: chain.rawValue, symbol: symbol, name: name,
                contract: contractAddress, coingeckoId: coingeckoId,
                coinpaprikaId: coinpaprikaId, decimals: UInt32(decimals))
        }
        guard
            let transition = try? await self.bridge.applyStateCommand(command)
        else { return localizedStoreString("This token could not be saved.") }
        applyCoreState(transition.state)
        guard let reason = tokenPreferenceRejection(in: transition.events) else {
            tokenPreferenceError = nil
            return nil
        }
        let message = tokenPreferenceRejectionMessage(reason)
        tokenPreferenceError = message
        return message
    }
}
