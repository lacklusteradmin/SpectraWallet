import Foundation

extension AppState {
    private var wsb: WalletServiceBridge { WalletServiceBridge.shared }
    func historyPaginationExhausted(chainId: String, walletId: String) -> Bool {
        wsb.historyCursor(chainId: chainId, walletId: walletId).isExhausted
    }
    func historyPaginationCursor(chainId: String, walletId: String) -> String? {
        wsb.historyCursor(chainId: chainId, walletId: walletId).nextCursor
    }
    func historyPaginationPage(chainId: String, walletId: String) -> Int {
        Int(wsb.historyCursor(chainId: chainId, walletId: walletId).nextPage)
    }
    func setHistoryCursor(chainId: String, walletId: String, cursor: String?) {
        wsb.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: cursor)
    }
    /// The page just fetched, and whether it was the last one.
    func setHistoryPage(chainId: String, walletId: String, page: Int, isExhausted: Bool) {
        wsb.setHistoryPage(
            chainId: chainId, walletId: walletId, page: UInt32(max(0, page)), isExhausted: isExhausted)
    }
    func resetHistoryPagination(chainId: String, walletId: String) {
        wsb.resetHistory(.chainAndWallet(chainId: chainId, walletId: walletId))
    }
    func resetHistoryPaginationForWallet(_ walletId: String) {
        wsb.resetHistory(.wallet(walletId: walletId))
    }
    func resetHistoryPaginationForChain(_ chainId: String) {
        wsb.resetHistory(.chain(chainId: chainId))
    }
    func resetAllHistoryPagination() { wsb.resetHistory(.all) }
}
// ────────────────────────────────────────────────────────────────────────────
// Normalized history fetch: a single function replaces all per-chain
// refresh methods for non-EVM, non-UTXO-HD chains.
// Rust normalizes and decodes; Swift maps the typed items to TransactionRecord.
// ────────────────────────────────────────────────────────────────────────────
extension NormalizedHistoryItem {
    nonisolated fileprivate var createdAtDate: Date { timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date() }
}
extension AppState {
    func canLoadMoreHistory(for walletID: String) -> Bool {
        guard let wallet = cachedWalletByID[walletID],
            let chainId = Chain(displayName: wallet.selectedChain)?.id
        else { return false }
        return !historyPaginationExhausted(chainId: chainId, walletId: walletID)
    }
    func canLoadMoreOnChainHistory(for walletIDs: Set<String>) -> Bool {
        !isLoadingMoreOnChainHistory && walletIDs.contains(where: canLoadMoreHistory(for:))
    }
    func loadMoreOnChainHistory(for walletIDs: Set<String>) async {
        guard canLoadMoreOnChainHistory(for: walletIDs) else { return }
        isLoadingMoreOnChainHistory = true
        defer { isLoadingMoreOnChainHistory = false }
        let eligibleWalletIDs = Set(walletIDs.filter(canLoadMoreHistory(for:)))
        let limit = AppState.HistoryPaging.endpointBatchSize
        // The chains to page are the ones the eligible wallets are on, not a
        // list of names: `canLoadMoreHistory` says yes for any chain the
        // registry knows whose pagination is not exhausted, so "Load more" must
        // reach all of them.
        //
        // Bitcoin and Dogecoin keep their own fetch — HD xpub expansion, and a
        // confirmed-fee path; every EVM chain pages through the token history;
        // everything else goes through the normalized one, which its own
        // comment already says covers "any future account-based chain".
        let chainsToPage = Set(eligibleWalletIDs.compactMap { cachedWalletByID[$0]?.selectedChain })
        for chain in Chain.all where chainsToPage.contains(chain.displayName) {
            switch chain {
            case .bitcoin:
                await refreshBitcoinTransactions(limit: limit, loadMore: true, targetWalletIDs: eligibleWalletIDs)
            case _ where chain.supportsDeepUTXODiscovery:
                await refreshMultiAddressUTXOTransactions(
                    chainName: chain.displayName, loadMore: true, targetWalletIDs: eligibleWalletIDs)
            case _ where chain.isEVM:
                await refreshEVMTokenTransactions(
                    chainName: chain.displayName, maxResults: limit, loadMore: true, targetWalletIDs: eligibleWalletIDs)
            default:
                await refreshNormalizedTransactions(
                    chainName: chain.displayName, loadMore: true, targetWalletIDs: eligibleWalletIDs)
            }
        }
    }

    // ── Generic normalized refresh (covers BCH, BSV, LTC, XRP, XLM, ADA, DOT,
    //    SOL, TRX, SUI, APT, TON, NEAR, ICP, XMR and any future account-based chain)
    /// Fetch and merge one chain's history for its wallets.
    ///
    /// Core plans which wallets to fetch for, fetches them, builds the records
    /// and merges them. This used to do all four: it mapped its wallet
    /// projection into a planning request and handed it back for core to
    /// filter, fetched per target, minted a record per entry — id, wallet
    /// name, source tag and all — and sent the result back to be merged. What
    /// is left is the banner, which is presentation.
    func refreshNormalizedChainTransactions(
        chainName: String,
        chainId: String,
        loadMore: Bool = false,
        targetWalletIDs: Set<String>? = nil
    ) async {
        let outcome: HistoryRefreshOutcome
        do {
            outcome = try await WalletServiceBridge.shared.refreshChainHistory(
                chainId: chainId, walletIDs: targetWalletIDs.map(Array.init) ?? [])
        } catch {
            markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.")
            return
        }
        guard outcome.walletsRefreshed > 0 || outcome.walletsFailed > 0 else { return }
        if outcome.added > 0 || outcome.updated > 0 {
            await refreshTransactionProjection()
        }
        if outcome.walletsFailed > 0 {
            markChainDegraded(
                chainName,
                detail: outcome.walletsRefreshed == 0
                    ? "\(chainName) history refresh failed. Using cached history."
                    : "\(chainName) history loaded with partial provider failures.")
        } else {
            markChainHealthy(chainName)
        }
    }

    func refreshNormalizedTransactions(
        chainName: String, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
    ) async {
        let chainID = Chain(displayName: chainName)?.id ?? ""
        guard !chainID.isEmpty else { return }
        await refreshNormalizedChainTransactions(
            chainName: chainName, chainId: chainID,
            loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
}


// ────────────────────────────────────────────────────────────────────────────
// Bitcoin (special: HD xpub address expansion + single-address fallback)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    /// Fetch and merge Bitcoin history for its wallets.
    ///
    /// Bitcoin is the one chain with an account xpub, so its history is the HD
    /// range's rather than one address's. Three arms used to live here: read
    /// the seed out of the Keychain, cut the account path out of the wallet's
    /// derivation path by string surgery, derive the xpub and walk the range;
    /// fall back to the stored address; fall back to a stored xpub. All three
    /// are `refresh_bitcoin_history`, over the seed, paths and cursors core
    /// already holds. What is left is the diagnostics rows and the banner.
    func refreshBitcoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        let outcome: HistoryRefreshOutcome
        do {
            outcome = try await WalletServiceBridge.shared.refreshBitcoinHistory(
                walletIDs: targetWalletIDs.map(Array.init) ?? [],
                loadMore: loadMore,
                limit: limit.map { UInt32(max(0, $0)) })
        } catch {
            markChainDegraded("Bitcoin", detail: "Bitcoin history refresh failed. Using cached history.")
            return
        }
        recordBitcoinHistoryDiagnostics(outcome.diagnostics)
        guard outcome.walletsRefreshed > 0 || outcome.walletsFailed > 0 else { return }
        if outcome.added > 0 || outcome.updated > 0 {
            await refreshTransactionProjection()
        }
        if outcome.walletsFailed > 0 {
            markChainDegraded(
                "Bitcoin",
                detail: outcome.walletsRefreshed == 0
                    ? "Bitcoin history refresh failed. Using cached history."
                    : "Bitcoin history loaded with partial provider failures.")
        } else {
            markChainHealthy("Bitcoin")
        }
    }

    /// Put a refresh's own account of itself on the diagnostics screen.
    func recordBitcoinHistoryDiagnostics(_ rows: [HistoryWalletDiagnostics]) {
        guard !rows.isEmpty else { return }
        for row in rows {
            recordHistoryDiagnostics(
                chainName: "Bitcoin",
                HistoryDiagnostics(
                    walletId: row.walletId, identifier: row.identifier, sourceUsed: row.sourceUsed,
                    transactionCount: Int32(row.transactionCount), scannedCount: nil,
                    nextCursor: row.nextCursor, error: row.error, perSource: []))
        }
        self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Dogecoin (special: multi-address per-wallet, UTXO aggregation)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    /// History for a chain whose wallets hold many addresses.
    ///
    /// The five chains that walk their addresses are Bitcoin, Dogecoin,
    /// Litecoin, Bitcoin Cash and Bitcoin SV. Bitcoin has its own path — it is
    /// the only one with a stored xpub, so core expands the HD range for it.
    /// This served **Dogecoin alone**, under that name, while Litecoin,
    /// Bitcoin Cash and Bitcoin SV went through the single-address refresh:
    /// their wallets have many addresses and only the first one's history was
    /// ever fetched.
    /// Fetch and merge one UTXO chain's history across each wallet's known
    /// addresses.
    ///
    /// A UTXO wallet spends from many addresses, so one transaction arrives
    /// once per address it touched and the records are netted per transaction
    /// before they are stored. This used to ask core for the addresses, hand
    /// them straight back inside a planning request, fetch per address, call
    /// core's aggregator, build the records and send them to be merged — six
    /// crossings for data core already had. The addresses are its keypool.
    func refreshMultiAddressUTXOTransactions(
        chainName: String, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
    ) async {
        guard let chain = Chain(displayName: chainName) else { return }
        let outcome: HistoryRefreshOutcome
        do {
            outcome = try await WalletServiceBridge.shared.refreshUTXOChainHistory(
                chainId: chain.id,
                walletIDs: targetWalletIDs.map(Array.init) ?? [],
                loadMore: loadMore)
        } catch {
            markChainDegraded(
                chainName,
                detail: AppLocalization.format("%@ history refresh failed. Using cached history.", chainName))
            return
        }
        guard outcome.walletsRefreshed > 0 || outcome.walletsFailed > 0 else { return }
        if outcome.added > 0 || outcome.updated > 0 {
            await refreshTransactionProjection()
        }
        if outcome.walletsFailed > 0 {
            markChainDegraded(
                chainName,
                detail: AppLocalization.format(
                    outcome.walletsRefreshed == 0
                        ? "%@ history refresh failed. Using cached history."
                        : "%@ history loaded with partial provider failures.",
                    chainName))
        } else {
            markChainHealthy(chainName)
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// EVM (special: token + native transfers, page-based pagination)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    /// Fetch and merge one EVM chain's history page for its wallets.
    ///
    /// Eight steps used to be here: plan the wallets, group them by normalized
    /// address, reset or advance each group's page, build the token descriptor
    /// list from this mirror of the token preferences, fetch, plan the records,
    /// convert them, merge. All eight are `refresh_evm_chain_history` now, over
    /// the wallets, preferences and cursors core already owns. What is left is
    /// the diagnostics rows and the banner, which are this screen's.
    func refreshEVMTokenTransactions(
        chainName: String, maxResults: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
    ) async {
        guard let chain = Chain(displayName: chainName), chain.isEVM else { return }
        let outcome: HistoryRefreshOutcome
        do {
            outcome = try await WalletServiceBridge.shared.refreshEVMChainHistory(
                chainId: chain.id,
                walletIDs: targetWalletIDs.map(Array.init) ?? [],
                loadMore: loadMore,
                pageSize: maxResults.map { UInt32(max(0, $0)) })
        } catch {
            markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.")
            return
        }
        // The diagnostics registry is keyed by chain and takes any of them, so
        // a chain's token-transfer rows go under its own mainnet.
        let diagnosticsChainName = chain.mainnetCounterpart.displayName
        for row in outcome.diagnostics {
            recordHistoryDiagnostics(
                chainName: diagnosticsChainName,
                HistoryDiagnostics(
                    walletId: row.walletId, identifier: row.identifier,
                    sourceUsed: row.sourceUsed, transactionCount: Int32(row.transactionCount),
                    scannedCount: nil, nextCursor: nil, error: row.error,
                    perSource: [
                        HistoryDiagnosticsSource(
                            name: "etherscan", count: Int32(row.transactionCount), error: row.error)
                    ]))
        }
        if !outcome.diagnostics.isEmpty {
            self[historyRunFor: diagnosticsChainName].lastUpdatedAt = Date()
        }
        if outcome.added > 0 || outcome.updated > 0 {
            await refreshTransactionProjection()
        }
        if outcome.walletsFailed > 0 {
            markChainDegraded(
                chainName,
                detail: outcome.walletsRefreshed == 0
                    ? "\(chainName) history refresh failed. Using cached history."
                    : "\(chainName) history loaded with partial provider failures.")
        } else if outcome.walletsRefreshed > 0 {
            markChainHealthy(chainName)
        }
    }
}
