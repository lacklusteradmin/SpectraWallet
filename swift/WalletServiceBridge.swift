import Foundation
@MainActor final class WalletServiceBridge {
    static let shared = WalletServiceBridge()
    private let suppliedService: WalletService?
    private let databasePath: String?
    private var stateIsOpen = false
    init(databasePath: String? = nil, service: WalletService? = nil) {
        self.databasePath = databasePath
        self.suppliedService = service
    }

    /// Every async operation waits for the same core-owned database binding.
    /// Core serializes concurrent opens and retries failures without caching them.
    private func readyService() async throws -> WalletService {
        let svc = try service()
        if !stateIsOpen {
            _ = try await svc.openState(databasePath: sqliteDbPath())
            if suppliedService == nil {
                _ = try await svc.configureNetworkRuntime(cacheDir: AppState.torCacheDirectory())
            }
            stateIsOpen = true
        }
        return svc
    }

    private var _service: WalletService?
    private var _balanceRefreshEngine: BalanceRefreshEngine?
    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let svc = try suppliedService ?? WalletService.newCatalog()
        if suppliedService == nil { svc.setSecretStore(store: SpectraSecretStoreAdapter()) }
        _service = svc
        return svc
    }
    // Wallet secrets. Synchronous Keychain reads using core-owned key names.

    func walletSecretState(walletId: String) -> WalletSecretState? {
        try? service().walletSecretState(walletId: walletId)
    }
    func walletSeedPhrase(walletId: String, password: String?) throws -> String {
        try service().walletSeedPhrase(walletId: walletId, password: password)
    }
    func resetData(scopes: [ResetScope]) async throws -> ResetOutcome {
        try await readyService().resetData(scopes: scopes)
    }

    func reconnectTor() async throws -> TorStatus {
        try await readyService().reconnectTor()
    }

    func evaluatePortfolioMovement(appIsActive: Bool) async throws -> LargeMovementEvaluation? {
        try await readyService().evaluatePortfolioMovement(appIsActive: appIsActive)
    }
    func runConfiguredSelfTests(chainId: String) async throws -> ConfiguredSelfTestReport {
        try await readyService().runConfiguredSelfTests(chainId: chainId)
    }
    func fetchStakingValidators(chainId: String) async throws -> [StakingValidator] {
        try await readyService().fetchStakingValidators(chainId: chainId)
    }
    func receiveAddress(walletId: String, chainId: String, reserve: Bool) async throws -> String? {
        try await readyService().receiveAddress(walletId: walletId, chainId: chainId, reserve: reserve)
    }

    func knownUTXOAddresses(walletId: String, chainId: String) async throws -> [String] {
        try await readyService().knownUtxoAddresses(walletId: walletId, chainId: chainId)
    }

    func refreshApp(intent: AppRefreshIntent, conditions: DeviceConditions) async throws -> AppRefreshResult {
        try await readyService().refreshApp(intent: intent, conditions: conditions)
    }
    func previewOwnedSend(walletId: String, holdingKey: String, amount: String, destination: String, explicitNonce: Int64?, customFees: EvmCustomFeeConfiguration?) async throws -> OwnedSendPreview? {
        try await readyService().previewOwnedSend(walletId: walletId, holdingKey: holdingKey, amount: amount, destination: destination, explicitNonce: explicitNonce, customFees: customFees)
    }
    func replacementDraft(transactionId: String, cancel: Bool) async throws -> OwnedReplacementDraft {
        try await readyService().replacementDraft(transactionId: transactionId, cancel: cancel)
    }
    func moneroSyncStatus(walletId: String) async throws -> MoneroSyncStatus? {
        try await readyService().moneroSyncStatus(walletId: walletId)
    }
    func syncMoneroWallet(walletId: String, password: String?, restoreHeight: UInt64?) async throws -> MoneroSyncStatus {
        try await readyService().syncMoneroWallet(walletId: walletId, password: password, restoreHeight: restoreHeight)
    }
    func buildOwnedSend(input: SendReviewInput) async throws -> SendArtifact {
        try await readyService().buildOwnedSend(input: input)
    }
    func signSend(id: String, reviewDigest: String, password: String?) async throws -> SendArtifact {
        try await readyService().signSend(id: id, reviewDigest: reviewDigest, password: password)
    }
    func broadcastSend(id: String, endpoints: [String]) async throws -> SendArtifact {
        try await readyService().broadcastSend(id: id, endpoints: endpoints)
    }
    func inspectSend(id: String) async throws -> SendArtifact {
        try await readyService().inspectSend(id: id)
    }
    func listSends() async throws -> [SendArtifact] { try await readyService().listSends() }
    func endpointDirectory() async throws -> [EndpointDirectoryEntry] { try await readyService().endpointDirectory() }
    func sendEndpoints(chainId: String) async throws -> [String] { try await readyService().sendEndpoints(chainId: chainId) }
    func resolveSendDestination(chainId: String, input: String, expectedAddress: String? = nil) async throws -> SendDestinationResolution {
        if let expectedAddress {
            return try await readyService().verifySendDestination(chainId: chainId, input: input, expectedAddress: expectedAddress)
        }
        return try await readyService().resolveSendDestination(chainId: chainId, input: input)
    }
    func sendDestinationRisk(walletId: String, holdingKey: String, destination: String) async throws -> SendDestinationRisk {
        try await readyService().sendDestinationRisk(
            walletId: walletId, holdingKey: holdingKey, destinationInput: destination)
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

    /// Bind core to its state database and return the stored state.
    /// Subsequent operations use that binding.
    @discardableResult
    func openState() async throws -> CoreAppState {
        // Use core's serialized open for launch snapshots too: an unlocked
        // appState read could overtake an in-flight settings commit.
        let svc = try await readyService()
        return try await svc.openState(databasePath: sqliteDbPath())
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
    func portfolioSnapshot() async throws -> PortfolioSnapshot { try await readyService().portfolioSnapshot() }
    func transactionSnapshot() async throws -> TransactionSnapshot { try await readyService().transactionSnapshot() }
    func historyPage(_ query: HistoryQuery) async throws -> HistoryPage { try await readyService().historyPage(query: query) }
    func transaction(id: String) async throws -> TransactionRecord? { try await readyService().transaction(id: id) }

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

    /// What to tell the user about a send, from its stored record.
    func sendVerificationNotice(transactionId: String) async throws -> SendVerificationNotice {
        try await readyService().sendVerificationNotice(transactionId: transactionId)
    }

    /// Every address a wallet is known to hold, on any chain.
    func knownWalletAddresses(walletId: String) async throws -> [String] {
        try await readyService().knownWalletAddresses(walletId: walletId)
    }

    // ── Confirmation-poll backoff ─────────────────────────────────────────
    /// Core validates and rechecks the stored transaction, then commits its result.
    func recheckTransactionStatus(id: String) async throws -> TransactionStatusChange {
        try await readyService().recheckTransactionStatus(transactionId: id)
    }

    /// Everything the wallet list implies, with holdings already resolved.

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
    func probeChainEndpoints(chainId: String) async throws -> [EndpointProbe] {
        try await readyService().probeChainEndpoints(chainId: chainId)
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

    // Where the next history fetch for this (chain, wallet) starts.
    func historyCursor(chainId: String, walletId: String) -> HistoryCursor {
        _service?.historyCursor(chainId: chainId, walletId: walletId)
            ?? HistoryCursor(nextCursor: nil, nextPage: 0, isExhausted: false)
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
