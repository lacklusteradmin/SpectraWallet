import Foundation
@MainActor final class WalletServiceBridge {
    static let shared = WalletServiceBridge()
    private let databasePath: String?
    private var stateIsOpen = false
    init(databasePath: String? = nil) { self.databasePath = databasePath }

    /// Every async operation waits for the same core-owned database binding.
    /// Core serializes concurrent opens and retries failures without caching them.
    private func readyService() async throws -> WalletService {
        let svc = try service()
        if !stateIsOpen {
            _ = try await svc.openState(databasePath: sqliteDbPath())
            stateIsOpen = true
        }
        return svc
    }

    private var _service: WalletService?
    private static var _syncService: WalletService?
    private var _balanceRefreshEngine: BalanceRefreshEngine?
    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let svc = try WalletService.newCatalog()
        svc.setSecretStore(store: SpectraSecretStoreAdapter())
        _service = svc
        if self === Self.shared { WalletServiceBridge._syncService = svc }
        return svc
    }
    // ── Wallet secrets ──────────────────────────────────────────────────────
    //
    // Synchronous on purpose: these are Keychain reads behind core's own key
    // layout, and the callers are the same places that used to reach into
    // `SecureSeedStore` directly. Nothing here computes a key — core does,
    // because there were two layouts for as long as this side owned one.

    func walletSecretState(walletID: String) -> WalletSecretState? {
        try? service().walletSecretState(walletId: walletID)
    }
    func walletSeedPhrase(walletID: String, password: String?) throws -> String {
        try service().walletSeedPhrase(walletId: walletID, password: password)
    }
    func resetData(scopes: [ResetScope]) async throws -> ResetOutcome {
        try await readyService().resetData(scopes: scopes)
    }

    func evaluatePortfolioMovement(appIsActive: Bool) async throws -> LargeMovementEvaluation? {
        try await readyService().evaluatePortfolioMovement(appIsActive: appIsActive)
    }
    func fetchStakingValidators(chainId: String) async throws -> [StakingValidator] {
        try await readyService().fetchStakingValidators(chainId: chainId)
    }
    func receiveAddress(walletID: String, chainId: String, reserve: Bool) async throws -> String? {
        try await readyService().receiveAddress(walletId: walletID, chainId: chainId, reserve: reserve)
    }

    func knownUTXOAddresses(walletID: String, chainId: String) async throws -> [String] {
        try await readyService().knownUtxoAddresses(walletId: walletID, chainId: chainId)
    }

    func refreshApp(intent: AppRefreshIntent, conditions: DeviceConditions) async throws -> AppRefreshResult {
        try await readyService().refreshApp(intent: intent, conditions: conditions)
    }
    func previewOwnedSend(walletID: String, holdingKey: String, amount: String, destination: String, explicitNonce: Int64?, customFees: EvmCustomFeeConfiguration?) async throws -> SendPreview? {
        try await readyService().previewOwnedSend(walletId: walletID, holdingKey: holdingKey, amount: amount, destination: destination, explicitNonce: explicitNonce, customFees: customFees)
    }
    func replacementDraft(transactionID: String, cancel: Bool) async throws -> OwnedReplacementDraft {
        try await readyService().replacementDraft(transactionId: transactionID, cancel: cancel)
    }
    func reviewOwnedSend(input: SendReviewInput) async throws -> OwnedSendReview {
        try await readyService().reviewOwnedSend(input: input)
    }
    func executeOwnedSend(reviewID: String, input: SendReviewInput) async throws -> SendExecutionResult {
        try await readyService().executeOwnedSend(reviewId: reviewID, input: input, password: nil)
    }

    func resolveSendDestination(chainId: String, input: String, expectedAddress: String? = nil) async throws -> SendDestinationResolution {
        if let expectedAddress {
            return try await readyService().verifySendDestination(chainId: chainId, input: input, expectedAddress: expectedAddress)
        }
        return try await readyService().resolveSendDestination(chainId: chainId, input: input)
    }
    func sendDestinationRisk(walletID: String, holdingKey: String, destination: String) async throws -> SendDestinationRisk {
        try await readyService().sendDestinationRisk(
            walletId: walletID, holdingKey: holdingKey, destinationInput: destination)
    }
    /// `destinationAddress` prices an extra output where the chain has one —
    /// Litecoin's MWEB peg-in — so the preview core builds already includes it.
    /// `nil` when core refuses the length: BIP-39 defines five, and core will
    /// not substitute twelve words for a count it does not recognize. The
    /// length picker already shows core's warning for such a count.
    nonisolated func rustGenerateMnemonic(wordCount: Int) -> String? {
        MainActor.assumeIsolated { try? generateMnemonic(wordCount: UInt32(wordCount)) }
    }

    func refreshOwnedPrices(force: Bool) async throws -> CoreAppState {
        try await readyService().refreshOwnedPrices(force: force)
    }
    func refreshOwnedFiatRates(force: Bool) async throws -> CoreAppState {
        try await readyService().refreshOwnedFiatRates(force: force)
    }
    func registerSecretStore(_ store: SecretStore) throws { try service().setSecretStore(store: store) }

}
extension WalletServiceBridge {
    // ── Owned application state ───────────────────────────────────────────
    //
    // `CoreAppState` is the domain state and Rust owns it. Swift sends a
    // command and renders the state it gets back; it does not keep its own
    // copy and mutate it. See PLAN.md.

    /// Bind the core to its state database and return what is stored.
    ///
    /// The only place this path crosses. Twelve other methods used to take it
    /// as an argument, so a caller could aim a write at a file core was not
    /// opened on — core reads its own binding now.
    @discardableResult
    func openState() async throws -> CoreAppState {
        // Use core's serialized open for launch snapshots too: an unlocked
        // appState read could overtake an in-flight settings commit.
        let state = try await service().openState(databasePath: sqliteDbPath())
        stateIsOpen = true
        return state
    }

    /// Apply a command to the owned state. Core persists before returning.
    @discardableResult
    func applyStateCommand(_ command: StateCommand) async throws -> StateTransition {
        try await readyService().applyStateCommand(command: command)
    }

    /// Current snapshot of the owned state.
    func appState() async throws -> CoreAppState { try await readyService().appState() }
    /// Core evaluates its own alerts and returns only what to notify about.
    func evaluatePriceAlerts() async throws
        -> [PriceAlertNotification]
    {
        try await readyService().evaluatePriceAlerts()
    }
    /// The dashboard rows, computed from core holdings, settings and quotes.
    func dashboardPinOptions() async throws -> [CoreDashboardPinOption] {
        try await readyService().dashboardPinOptions()
    }

    func dashboardAssetGroups() async throws -> [CoreDashboardAssetGroup] {
        try await readyService().dashboardAssetGroups()
    }

    func normalizedHistory(unknownLabel: String) async throws -> [CoreNormalizedHistoryEntry] {
        return try await readyService().normalizedHistory(unknownLabel: unknownLabel)
    }
    func earliestTransactionDates() async throws -> [WalletEarliestTransactionDate] {
        return try await readyService().earliestTransactionDates()
    }

    /// The pending sends core says are still replaceable, newest first.
    func replaceableSends() async throws -> [ReplaceableSend] {
        return try await readyService().replaceableSends()
    }

    // ── Maintenance ───────────────────────────────────────────────────────
    /// What core says should happen this tick. Returns a do-nothing plan if the
    /// service will not start, which is the same answer as "no work".
    func maintenancePlan(conditions: DeviceConditions) async -> MaintenancePlan {
        guard let service = try? await readyService() else {
            return MaintenancePlan(
                refreshPendingTransactions: false, refreshLivePrices: false,
                runBackgroundTick: false, allowHeavyBackgroundWork: false, pollSeconds: 60)
        }
        return await service.maintenancePlan(conditions: conditions)
    }

    func operationalEvents(chainName: String) async -> [DiagnosticLog] {
        guard let service = try? await readyService() else { return [] }
        return await service.operationalEvents(chainName: chainName)
    }
    /// Fold this build's built-in token catalog into the stored preferences.
    func mergeBuiltInTokenPreferences() async throws -> CoreAppState {
        try await readyService().mergeBuiltInTokenPreferences()
    }

    /// Push a rebuilt endpoint list into the service.
    ///
    func applyTransactionCommand(_ command: TransactionCommand) async throws -> TransactionChange {
        try await readyService().applyTransactionCommand(command: command)
    }

    /// The wallets core holds, in the shape the views render.
    func storedWallets() async throws -> [WalletView] {
        try await readyService().walletsForDisplay()
    }

    /// Every stored transaction, newest first.
    func storedTransactions() async throws -> [CorePersistedTransactionRecord] {
        try await readyService().transactions()
    }

    /// What to tell the user about a send, from its stored record.
    func sendVerificationNotice(transactionID: String) async throws -> SendVerificationNotice {
        try await readyService().sendVerificationNotice(transactionId: transactionID)
    }

    /// Every address a wallet is known to hold, on any chain.
    func knownWalletAddresses(walletID: String) async throws -> [String] {
        try await readyService().knownWalletAddresses(walletId: walletID)
    }

    // ── Confirmation-poll backoff ─────────────────────────────────────────
    /// Core validates and rechecks the stored transaction, then commits its result.
    func recheckTransactionStatus(id: String) async throws -> TransactionStatusChange {
        try await readyService().recheckTransactionStatus(transactionId: id)
    }

    /// Everything the wallet list implies, with holdings already resolved.
    func walletDerivedState() async throws -> WalletDerivedState {
        try await readyService().walletDerivedState()
    }
    func beginFundsScan(request: FundsFinderRequest) throws -> FundsScan {
        try service().beginFundsScan(request: request, chainId: nil)
    }
    func diagnosticState() async throws -> DiagnosticState {
        try await readyService().diagnosticState()
    }
    func applyDiagnosticCommand(_ command: DiagnosticCommand) async throws -> DiagnosticState {
        try await readyService().applyDiagnosticCommand(command: command)
    }
    func rebroadcastTransaction(id: String) async throws -> String {
        try await readyService().rebroadcastTransaction(transactionId: id)
    }
    func probeChainEndpoints(chainID: String) async throws -> [EndpointProbe] {
        try await readyService().probeChainEndpoints(chainId: chainID)
    }

    // ── Keypool ───────────────────────────────────────────────────────────
    // Reservation is read-modify-write, so it happens inside core under one
    // lock, over a baseline it computes from its own tables.

    /// Every wallet's keypool on a chain, with the reserved address as recorded.
    func keypoolDiagnostics(chainName: String) async throws -> [KeypoolDiagnostic] {
        try await readyService().keypoolDiagnostics(chainName: chainName)
    }

    /// Import wallets into core. Returns what was created, plus the Keychain
    /// writes the caller still owns.
    func importWallets(_ commit: WalletImportCommit) async throws -> WalletImportOutcome {
        try await readyService().importWallets(commit: commit)
    }

    // ── Transaction history persistence (Rust SQLite) ──────────────────────────
    /// Empty the history table.
    ///
    /// Went through `replaceAllHistoryRecords([])`, which was a third spelling
    /// of a command `TransactionCommand` already has.
    /// Where the next history fetch for this (chain, wallet) starts.
    ///
    /// One call rather than three getters.
    nonisolated func historyCursor(chainId: String, walletId: String) -> HistoryCursor {
        MainActor.assumeIsolated {
            WalletServiceBridge._syncService?.historyCursor(chainId: chainId, walletId: walletId)
                ?? HistoryCursor(nextCursor: nil, nextPage: 0, isExhausted: false)
        }
    }
    private func sqliteDbPath() -> String {
        if let databasePath { return databasePath }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
        return "\(docs)/spectra_state.db"
    }
}
extension WalletServiceBridge {
    private func balanceRefreshEngine() throws -> BalanceRefreshEngine {
        if let engine = _balanceRefreshEngine { return engine }
        let engine = BalanceRefreshEngine(walletService: try service())
        _balanceRefreshEngine = engine
        return engine
    }
    func setBalanceObserver(_ observer: BalanceObserver) throws { try balanceRefreshEngine().setObserver(observer: observer) }
    func refreshHistory(scope: HistoryRefreshScope, loadMore: Bool, interval: Double) async throws -> [ChainHistoryRefresh] {
        try await readyService().refreshHistory(scope: scope, loadMore: loadMore, limit: nil, intervalSecs: interval)
    }

    /// Adopt the wallets core holds; core refreshes only if what it fetches changed.
    func reconcileBalanceRefresh(appIsActive: Bool) async throws -> Bool {
        _ = try await readyService()
        return try await balanceRefreshEngine().reconcileWallets(appIsActive: appIsActive)
    }
    func configureBalanceRefresh(appIsActive: Bool) async throws { _ = try await readyService(); try await balanceRefreshEngine().configureForDevice(appIsActive: appIsActive) }
    func triggerImmediateBalanceRefresh() async throws { _ = try await readyService(); try await balanceRefreshEngine().triggerImmediate() }
}
