import Foundation
/// Test seam: tests that don't want to talk to a real Rust service can
/// inject a stub conforming to `WalletServiceBridgeProtocol`. Existing
/// production call sites continue to use `WalletServiceBridge.shared`.
/// Adoption is incremental — protocol-typed parameters in new code
/// accept either implementation; legacy `WalletServiceBridge.shared.foo()`
/// call sites can migrate when their tests need it.
protocol WalletServiceBridgeProtocol: Sendable {}

@MainActor final class WalletServiceBridge: WalletServiceBridgeProtocol {
    static let shared = WalletServiceBridge()
    private var _service: WalletService?
    private static var _syncService: WalletService?
    private static var _pendingEtherscanAPIKey: String = ""
    private var _balanceRefreshEngine: BalanceRefreshEngine?
    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let svc = try WalletService.newTyped(endpoints: Self.buildEndpoints())
        svc.setEtherscanApiKey(key: Self._pendingEtherscanAPIKey)
        _service = svc
        WalletServiceBridge._syncService = svc
        return svc
    }
    func fetchNativeBalanceSummary(chainId: String, address: String) async throws -> NativeBalanceSummary {
        try await service().fetchNativeBalanceSummary(chainId: chainId, address: address)
    }
    func fetchHistorySummary(chainId: String, address: String) async throws -> HistorySummary {
        try await service().fetchHistorySummary(chainId: chainId, address: address)
    }
    func fetchBitcoinHdHistoryPage(xpub: String, limit: UInt64) async throws -> [CoreBitcoinHistorySnapshot] {
        try await service().fetchBitcoinHdHistoryPage(xpub: xpub, limit: limit)
    }
    func fetchEVMHistoryPage(
        chainId: String, address: String, tokens: [TokenDescriptor], page: Int, pageSize: Int
    ) async throws -> EvmHistoryPageDecoded {
        try await service().fetchEvmHistoryPage(
            chainId: chainId, address: address, tokens: tokens,
            page: UInt32(max(1, page)), pageSize: UInt32(max(1, pageSize))
        )
    }
    func fetchEVMHistoryDiagnostics(
        chainId: String, walletID: String, address: String
    ) async throws -> HistoryDiagnostics {
        try await service().fetchEvmHistoryDiagnostics(
            chainId: chainId, walletId: walletID, address: address)
    }
    func executeSend(_ request: SendExecutionRequest) async throws -> SendExecutionResult { try await service().executeSend(request: request) }
    /// Token balances for any chain that has them, EVM included.
    ///
    /// There were two of these with the same signature and complementary chain
    /// sets, so a caller had to know which family it was holding.
    func fetchTokenBalances(
        chainId: String, address: String, tokens: [TokenDescriptor]
    ) async throws -> [TokenBalanceResult] {
        guard !tokens.isEmpty else { return [] }
        return try await service().fetchTokenBalances(
            chainId: chainId, address: address, tokens: tokens)
    }
    func deriveBitcoinAccountXpub(mnemonicPhrase: String, passphrase: String = "", accountPath: String) throws -> String {
        try service().deriveBitcoinAccountXpubTyped(mnemonicPhrase: mnemonicPhrase, passphrase: passphrase, accountPath: accountPath)
    }
    func resolveENSName(_ name: String) async throws -> String? {
        try await service().resolveEnsNameTyped(name: name)
    }
    func fetchEVMTxNonce(chainId: String, txHash: String) async throws -> Int {
        Int(try await service().fetchEvmTxNonceTyped(chainId: chainId, txHash: txHash))
    }
    func fetchEvmSendPreviewTyped(
        chainId: String, from: String, to: String, valueWei: String, dataHex: String,
        explicitNonce: Int64?, customFees: EvmCustomFeeConfiguration?
    ) async throws -> EvmSendPreview? {
        try await service().fetchEvmSendPreviewTyped(
            chainId: chainId, from: from, to: to, valueWei: valueWei, dataHex: dataHex,
            explicitNonce: explicitNonce, customFees: customFees)
    }
    func fetchEvmAddressProbe(chainId: String, address: String) async throws -> EvmAddressProbe {
        try await service().fetchEvmAddressProbe(chainId: chainId, address: address)
    }
    func fetchTronSendPreviewTyped(address: String, symbol: String, contractAddress: String) async throws -> TronSendPreview? {
        try await service().fetchTronSendPreviewTyped(address: address, symbol: symbol, contractAddress: contractAddress)
    }
    func fetchUtxoFeePreviewTyped(chainId: String, address: String, feeRateSvb: UInt64) async throws -> BitcoinSendPreview? {
        try await service().fetchUtxoFeePreviewTyped(chainId: chainId, address: address, feeRateSvb: feeRateSvb)
    }
    func fetchDogecoinSendPreviewTyped(address: String, requestedAmount: Double, feePriority: String) async throws -> DogecoinSendPreview? {
        try await service().fetchDogecoinSendPreviewTyped(address: address, requestedAmount: requestedAmount, feePriority: feePriority)
    }
    func fetchBitcoinHdSendPreviewTyped(xpub: String, receiveCount: UInt32 = 20, changeCount: UInt32 = 20) async throws -> BitcoinSendPreview? {
        try await service().fetchBitcoinHdSendPreviewTyped(xpub: xpub, receiveCount: receiveCount, changeCount: changeCount)
    }
    func fetchSimpleChainSendPreviewTyped(chainId: String, address: String) async throws -> SimpleChainPreview {
        try await service().fetchSimpleChainSendPreviewTyped(chainId: chainId, address: address)
    }
    nonisolated func rustGenerateMnemonic(wordCount: Int) -> String { MainActor.assumeIsolated { generateMnemonic(wordCount: UInt32(wordCount)) } }
    nonisolated func rustValidateMnemonic(_ phrase: String) -> Bool { MainActor.assumeIsolated { validateMnemonic(phrase: phrase) } }
    func broadcastRawExtract(chainId: String, payload: String, resultField: String) async throws -> String {
        try await service().broadcastRawExtract(chainId: chainId, payload: payload, resultField: resultField)
    }
    func fetchBitcoinNextUnusedAddressTyped(xpub: String, change: UInt32 = 0, gapLimit: UInt32 = 20) async throws -> String? {
        try await service().fetchBitcoinNextUnusedAddressTyped(xpub: xpub, change: change, gapLimit: gapLimit)
    }
    func fetchPricesViaRust(coins: [PriceRequestCoin]) async throws -> [String: Double] {
        try await service().fetchPricesTyped(coins: coins)
    }
    func fetchFiatRatesViaRust(currencies: [String]) async throws -> [String: Double] {
        try await service().fetchFiatRatesTyped(currencies: currencies)
    }
    func registerSecretStore(_ store: SecretStore) throws { try service().setSecretStore(store: store) }
    nonisolated func setEtherscanAPIKey(_ key: String) {
        MainActor.assumeIsolated {
            Self._pendingEtherscanAPIKey = key
            Self._syncService?.setEtherscanApiKey(key: key)
        }
    }
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
        try await service().openState(dbPath: sqliteDbPath())
    }

    /// Apply a command to the owned state. Core persists before returning.
    @discardableResult
    func applyStateCommand(_ command: StateCommand) async throws -> StateTransition {
        try await service().applyStateCommand(command: command)
    }

    /// Current snapshot of the owned state.
    func appState() async throws -> CoreAppState { try await service().appState() }
    /// Core evaluates its own alerts and returns only what to notify about.
    func evaluatePriceAlerts(prices: [PriceAlertEvaluationPrice]) async throws
        -> [PriceAlertNotification]
    {
        try await service().evaluatePriceAlerts(prices: prices)
    }
    /// The dashboard's rows. Only the live prices go out — core holds the
    /// holdings, the known tokens, the pins and the selected networks.
    func dashboardAssetGroups(prices: [String: Double]) async throws -> [CoreDashboardAssetGroup] {
        try await service().dashboardAssetGroups(prices: prices)
    }
    /// Record something that happened on a chain. Core stamps and caps it.
    func appendChainOperationalEvent(
        chainName: String, level: ChainOperationalEventLevel, message: String, transactionHash: String?
    ) async throws {
        try await service().appendChainOperationalEvent(
            chainName: chainName, level: level, message: message, transactionHash: transactionHash)
    }
    func sendSubmitPreflight(
        walletID: String, holdingKey: String, destinationAddress: String, amountInput: String
    ) async throws -> SendSubmitPreflightPlan {
        try await service().sendSubmitPreflight(
            walletId: walletID, holdingKey: holdingKey, destinationAddress: destinationAddress,
            amountInput: amountInput)
    }

    /// How core routes this holding's send and preview, or `nil` if it cannot
    /// find the wallet or the holding.
    func sendAssetRouting(walletID: String, holdingKey: String) async -> SendAssetRoutingPlan? {
        guard let service = try? service() else { return nil }
        return await service.sendAssetRouting(walletId: walletID, holdingKey: holdingKey)
    }

    /// Why this send looks risky, as codes to localize.
    func highRiskSendReasons(
        walletID: String, holdingKey: String, amount: Double, destinationAddress: String,
        destinationInput: String, usedENSResolution: Bool
    ) async -> [HighRiskSendWarning] {
        guard let service = try? service() else { return [] }
        return await service.highRiskSendReasons(
            walletId: walletID, holdingKey: holdingKey, amount: amount,
            destinationAddress: destinationAddress, destinationInput: destinationInput,
            usedEnsResolution: usedENSResolution)
    }
    /// Warnings about an EVM recipient. Core makes the contract-code probes.
    func evmRecipientPreflight(
        walletID: String, holdingKey: String, destinationAddress: String
    ) async -> [EvmRecipientPreflightWarning] {
        guard let service = try? service() else { return [] }
        return await service.evmRecipientPreflight(
            walletId: walletID, holdingKey: holdingKey, destinationAddress: destinationAddress)
    }

    // ── Views of the transaction store, derived where the store is ────────
    func normalizedHistory(unknownLabel: String) async -> [CoreNormalizedHistoryEntry] {
        guard let service = try? service() else { return [] }
        return await service.normalizedHistory(unknownLabel: unknownLabel)
    }
    func earliestTransactionDates() async -> [WalletEarliestTransactionDate] {
        guard let service = try? service() else { return [] }
        return await service.earliestTransactionDates()
    }
    func activeWalletTransactionIDs() async -> [String] {
        guard let service = try? service() else { return [] }
        return await service.activeWalletTransactionIds()
    }

    // ── Maintenance ───────────────────────────────────────────────────────
    /// What core says should happen this tick. Returns a do-nothing plan if the
    /// service will not start, which is the same answer as "no work".
    func maintenancePlan(conditions: DeviceConditions) async -> MaintenancePlan {
        guard let service = try? service() else {
            return MaintenancePlan(
                refreshPendingTransactions: false, refreshLivePrices: false,
                runBackgroundTick: false, allowHeavyBackgroundWork: false, pollSeconds: 60)
        }
        return await service.maintenancePlan(conditions: conditions)
    }
    func recordRefresh(kind: RefreshKind) async {
        guard let service = try? service() else { return }
        await service.recordRefresh(kind: kind)
    }
    func historyRefreshPlans(chainIDs: [String], intervalSecs: Double) async -> [String] {
        guard let service = try? service() else { return [] }
        return await service.historyRefreshPlans(chainIds: chainIDs, intervalSecs: intervalSecs)
    }
    func recordHistoryRefresh(chainID: String) async {
        guard let service = try? service() else { return }
        await service.recordHistoryRefresh(chainId: chainID)
    }

    func operationalEvents(chainName: String) async -> [ChainOperationalEventRecord] {
        guard let service = try? service() else { return [] }
        return await service.operationalEvents(chainName: chainName)
    }
    /// Pass `nil` to clear every chain.
    func clearOperationalEvents(chainName: String?) async throws {
        try await service().clearOperationalEvents(chainName: chainName)
    }
    /// Fold this build's built-in token catalog into the stored preferences.
    func mergeBuiltInTokenPreferences() async throws -> CoreAppState {
        try await service().mergeBuiltInTokenPreferences()
    }

    /// Change the core-owned transaction store. Returns which ids changed.
    @discardableResult
    /// Push a rebuilt endpoint list into the service.
    ///
    /// `update_endpoints_typed` had existed unreachable since it was written,
    /// and the service was built once and never reconfigured — so a custom RPC
    /// the user set in Settings reached exactly one thing, the diagnostics
    /// reachability probe. Balances, history and sends all used the catalog's
    /// list and never saw it.
    func updateEndpoints(custom: [String: String]) async {
        guard let service = try? service() else { return }
        try? await service.updateEndpointsTyped(endpoints: Self.buildEndpoints(custom: custom))
    }

    func applyTransactionCommand(_ command: TransactionCommand) async throws -> TransactionChange {
        try await service().applyTransactionCommand(command: command)
    }

    /// The wallets core holds, in the shape the views render.
    func storedWallets() async throws -> [ImportedWallet] {
        try await service().walletsForDisplay()
    }

    /// Every stored transaction, newest first.
    func storedTransactions() async throws -> [CorePersistedTransactionRecord] {
        try await service().transactions()
    }

    // ── Confirmation-poll backoff ─────────────────────────────────────────
    // Core owns the tracker table, the schedule and the clock; these forward
    // intent, not computed state. They used to carry `now` and a six-field
    // `TransactionStatusPollConfig` on every call — how often to re-poll and
    // when to give up, decided on this side and handed over each time.

    func transactionsDueForStatusPoll(ids: [String]) async throws -> [String] {
        try await service().transactionsDueForStatusPoll(transactionIds: ids)
    }

    /// Record what one confirmation poll found.
    func recordStatusPoll(id: String, outcome: StatusPollOutcome) async throws {
        try await service().recordStatusPoll(transactionId: id, outcome: outcome)
    }

    func resetStatusTracker(id: String, clearFinality: Bool) async throws {
        try await service().resetStatusTracker(
            transactionId: id, clearFinality: clearFinality)
    }

    func pruneStatusTrackers() async throws {
        try await service().pruneStatusTrackers()
    }


    /// Everything the wallet list implies, with holdings already resolved.
    func walletDerivedState(
        signingMaterialWalletIDs: [String], privateKeyBackedWalletIDs: [String],
    ) async throws -> WalletDerivedState {
        try await service().walletDerivedState(
            signingMaterialWalletIds: signingMaterialWalletIDs,
            privateKeyBackedWalletIds: privateKeyBackedWalletIDs)
    }

    // ── Keypool ───────────────────────────────────────────────────────────
    // Reservation is read-modify-write, so it happens inside core under one
    // lock, over a baseline it computes from its own tables.

    func keypoolState(walletID: String, chainName: String) async -> KeypoolState {
        guard let service = try? service() else {
            return KeypoolState(nextExternalIndex: 0, nextChangeIndex: 0, reservedReceiveIndex: nil)
        }
        return await service.keypoolState(walletId: walletID, chainName: chainName)
    }

    func reserveReceiveIndex(walletID: String, chainName: String, minimumIndex: Int64) async throws
        -> Int64
    {
        try await service().reserveReceiveIndex(
            walletId: walletID, chainName: chainName, minimumIndex: minimumIndex)
    }

    func reserveChangeIndex(walletID: String, chainName: String) async throws -> Int64 {
        try await service().reserveChangeIndex(walletId: walletID, chainName: chainName)
    }

    func clearReservedReceiveIndex(walletID: String, chainName: String) async throws {
        try await service().clearReservedReceiveIndex(walletId: walletID, chainName: chainName)
    }


    /// Import wallets into core. Returns what was created, plus the Keychain
    /// writes the caller still owns.
    func importWallets(_ commit: WalletImportCommit) async throws -> WalletImportOutcome {
        try await service().importWallets(commit: commit)
    }

    func applyResolvedPendingStatuses(
        chainName: String, resolutions: [ResolvedPendingStatus]
    ) async throws -> [TransactionStatusChange] {
        try await service().applyResolvedPendingStatuses(chainName: chainName, resolutions: resolutions)
    }


    func loadState(key: String) async throws -> String { try await service().loadState(key: key) }
    func saveState(key: String, stateJSON: String) async throws {
        try await service().saveState(key: key, stateJson: stateJSON)
    }
    func fetchNormalizedHistory(chainId: String, address: String) async throws -> [NormalizedHistoryItem] {
        try await service().fetchNormalizedHistory(chainId: chainId, address: address)
    }
    func deleteKeypoolForWallet(walletId: String) async throws {
        try await service().deleteKeypoolForWallet(walletId: walletId)
    }
    func deleteKeypoolForChain(chainName: String) async throws {
        try await service().deleteKeypoolForChain(chainName: chainName)
    }
    func registerOwnedAddress(
        walletID: String, chainName: String, address: String, derivationPath: String?,
        branch: String?, branchIndex: Int64?
    ) async throws {
        try await service().registerOwnedAddress(
            walletId: walletID, chainName: chainName, address: address,
            derivationPath: derivationPath, branch: branch, branchIndex: branchIndex)
    }
    /// Omit `chainName` for every chain.
    func ownedAddresses(walletID: String, chainName: String? = nil) async -> [String] {
        guard let service = try? service() else { return [] }
        return await service.ownedAddressesForWallet(walletId: walletID, chainName: chainName)
    }
    func deleteOwnedAddressesForChain(chainName: String) async throws {
        try await service().deleteOwnedAddressesForChain(chainName: chainName)
    }
    func deleteWalletRelationalData(walletId: String) async throws {
        try await service().deleteWalletRelationalData(walletId: walletId)
    }
    // ── Transaction history persistence (Rust SQLite) ──────────────────────────
    func fetchAllHistoryRecordsTyped() async throws -> [HistoryRecord] { try await service().fetchAllHistoryRecordsTyped() }
    /// Empty the history table.
    ///
    /// Went through `replaceAllHistoryRecords([])`, which was a third spelling
    /// of a command `TransactionCommand` already has.
    func clearAllHistoryRecords() async throws {
        _ = try await applyTransactionCommand(.clear)
    }
    /// Where the next history fetch for this (chain, wallet) starts.
    ///
    /// One call rather than three getters. `advanceHistoryPage` went with them:
    /// it had a wrapper here and no caller anywhere.
    nonisolated func historyCursor(chainId: String, walletId: String) -> HistoryCursor {
        MainActor.assumeIsolated {
            WalletServiceBridge._syncService?.historyCursor(chainId: chainId, walletId: walletId)
                ?? HistoryCursor(nextCursor: nil, nextPage: 0, isExhausted: false)
        }
    }
    nonisolated func advanceHistoryCursor(chainId: String, walletId: String, nextCursor: String?) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: nextCursor) } }
    nonisolated func setHistoryPage(chainId: String, walletId: String, page: UInt32, isExhausted: Bool) {
        MainActor.assumeIsolated {
            WalletServiceBridge._syncService?.setHistoryPage(
                chainId: chainId, walletId: walletId, page: page, isExhausted: isExhausted)
        }
    }
    /// Forget history pagination, for as much of it as `scope` names. Four
    /// methods stood for the four cases.
    nonisolated func resetHistory(_ scope: HistoryScope) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.resetHistory(scope: scope) } }
    func fetchUtxoTxStatusTyped(chainId: String, txid: String) async throws -> UtxoTxStatus {
        try await service().fetchUtxoTxStatusTyped(chainId: chainId, txid: txid)
    }
    private func sqliteDbPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
        return "\(docs)/spectra_state.db"
    }
}
private extension WalletServiceBridge {
    static func buildEndpoints(custom: [String: String] = [:]) -> [ChainEndpoints] {
        var payloads: [ChainEndpoints] = []
        // A chain's id is its name, resolved by the registry — stating both was
        // 30 rows of `chainId: <id>, chainName: "X"`. Whether its endpoints come
        // from the EVM list or the generic record list is `coreIsEvmChain`.
        for chainName in AppEndpointDirectory.liveChainNames {
            var payload =
                (Chain(displayName: chainName)?.isEVM ?? false)
                ? evmPayloads(chainName: chainName) : rpcPayloads(chainName: chainName)
            // The user's own endpoint goes first: `with_fallback` walks the list
            // in order, so "configured" means tried before the catalog's, not
            // instead of it — a typo in the field degrades to the catalog rather
            // than taking the chain offline.
            if let configured = custom[chainName]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !configured.isEmpty, !payload.isEmpty
            {
                payload[0] = ChainEndpoints(
                    chainId: payload[0].chainId,
                    endpoints: [configured] + payload[0].endpoints.filter { $0 != configured },
                    apiKey: payload[0].apiKey)
            }
            payloads += payload
        }
        // Supplemental explorer endpoints. Which chains have one is data — the
        // catalog answers, and `explorerPayloads` returns nothing for a chain
        // without — and which slot it lands in is a registry column.
        //
        // A sixteen-name table stood here. Twelve of its names have no
        // supplement at all, and Hyperliquid, which does, was not in it.
        for chain in Chain.all {
            payloads += explorerPayloads(
                chainId: endpointSlotId(chain.id, chain.supplementalEndpointSlot),
                chainName: chain.displayName)
        }
        let tonV3URLs = AppEndpointDirectory.endpoints(for: ["ton.api.v3"])
        if !tonV3URLs.isEmpty {
            payloads.append(
                ChainEndpoints(
                    chainId: endpointSlotId(Chain.ton.id, .secondary), endpoints: tonV3URLs,
                    apiKey: nil))
        }
        return payloads
    }
    static func endpointSlotId(_ chainId: String, _ slot: AppCoreEndpointSlot) -> String {
        coreEndpointStrId(chainId: chainId, slot: slot) ?? chainId
    }
    static func rpcPayloads(chainName: String) -> [ChainEndpoints] {
        let chainId = Chain(displayName: chainName)?.id ?? ""
        guard !chainId.isEmpty else { return [] }
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: [.rpc, .balance, .backend], settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func evmPayloads(chainName: String) -> [ChainEndpoints] {
        let chainId = Chain(displayName: chainName)?.id ?? ""
        guard !chainId.isEmpty else { return [] }
        let endpoints = AppEndpointDirectory.evmRPCEndpoints(for: chainName)
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func explorerPayloads(chainId: String, chainName: String) -> [ChainEndpoints] {
        let endpoints = AppEndpointDirectory.explorerSupplementalEndpoints(for: chainName)
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
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
    func setRefreshEntriesTyped(_ entries: [RefreshEntry]) throws {
        try balanceRefreshEngine().setEntriesTyped(entries: entries)
    }
    func startBalanceRefresh(intervalSecs: UInt64) async throws { try await balanceRefreshEngine().start(intervalSecs: intervalSecs) }
    func stopBalanceRefresh() throws { try balanceRefreshEngine().stop() }
    func triggerImmediateBalanceRefresh() async throws { try await balanceRefreshEngine().triggerImmediate() }
}
