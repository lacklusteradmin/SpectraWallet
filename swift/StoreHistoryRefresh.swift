import Foundation

struct BitcoinHistoryPage {
    let snapshots: [CoreBitcoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

extension AppState {
    private var wsb: WalletServiceBridge { WalletServiceBridge.shared }
    private func notifyHistoryMutation() { bumpCachesRevision() }
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
        wsb.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: cursor); notifyHistoryMutation()
    }
    /// The page just fetched, and whether it was the last one.
    ///
    /// Was `setHistoryPage` plus `markHistoryExhausted`/`markHistoryActive` —
    /// two calls the one call site always made together, writing two fields of
    /// one cursor.
    func setHistoryPage(chainId: String, walletId: String, page: Int, isExhausted: Bool) {
        wsb.setHistoryPage(
            chainId: chainId, walletId: walletId, page: UInt32(max(0, page)), isExhausted: isExhausted)
        notifyHistoryMutation()
    }
    func resetHistoryPagination(chainId: String, walletId: String) {
        wsb.resetHistory(.chainAndWallet(chainId: chainId, walletId: walletId))
        notifyHistoryMutation()
    }
    func resetHistoryPaginationForWallet(_ walletId: String) {
        wsb.resetHistory(.wallet(walletId: walletId)); notifyHistoryMutation()
    }
    func resetHistoryPaginationForChain(_ chainId: String) {
        wsb.resetHistory(.chain(chainId: chainId)); notifyHistoryMutation()
    }
    func resetAllHistoryPagination() { wsb.resetHistory(.all); notifyHistoryMutation() }
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
            let chainId = historyPaginationChainId(chainName: wallet.selectedChain)
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
        // The chains to page are the ones the eligible wallets are on. Three
        // hand-written lists stood here — five UTXO names, twelve EVM names and
        // Tron — and `canLoadMoreHistory` says yes for *any* chain the registry
        // knows whose pagination is not exhausted. So "Load more" was offered
        // and did nothing on eleven EVM chains (Ethereum Classic, Sei, Celo,
        // Cronos, opBNB, zkSync Era, Sonic, Berachain, Unichain, Ink, X Layer)
        // and on every account-based chain: Solana, XRP Ledger, Stellar,
        // Cardano, Sui, Aptos, TON, Internet Computer, NEAR, Polkadot, Monero
        // and the rest.
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
            case .dogecoin:
                await refreshDogecoinTransactions(limit: limit, loadMore: true, targetWalletIDs: eligibleWalletIDs)
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
    func refreshNormalizedChainTransactions(
        chainName: String,
        chainId: String,
        resolveAddress: (ImportedWallet) -> String?,
        loadMore: Bool = false,
        targetWalletIDs: Set<String>? = nil
    ) async {
        let walletSnapshot = wallets
        let targets = coreRefreshTargets(
            request: RefreshTargetsRequest(
                chainName: chainName,
                wallets: walletSnapshot.map { wallet in
                    RefreshWalletInput(
                        walletId: wallet.id, selectedChain: wallet.selectedChain,
                        addresses: [resolveAddress(wallet)].compactMap { $0 })
                },
                allowedWalletIds: targetWalletIDs.map(Array.init)
            )
        )
        guard !targets.isEmpty else { return }
        let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id, $0) })
        let results: [(records: [TransactionRecord], error: Bool)] = await withTaskGroup(
            of: (records: [TransactionRecord], error: Bool).self,
            returning: [(records: [TransactionRecord], error: Bool)].self
        ) { group in
            for target in targets {
                // The single-address family supplies one entry; `plan_refresh_targets`
                // drops a wallet with none, so `first` is present.
                guard let wallet = walletByID[target.walletId], let address = target.addresses.first
                else { continue }
                let walletSnapshot = wallet
                group.addTask {
                    do {
                        let entries = try await WalletServiceBridge.shared.fetchNormalizedHistory(chainId: chainId, address: address)
                        let records = entries.map { entry in
                            TransactionRecord(
                                walletID: walletSnapshot.id,
                                kind: TransactionKind(rawValue: entry.kind) ?? .send,
                                status: TransactionStatus(rawValue: entry.status) ?? .confirmed,
                                walletName: walletSnapshot.name, assetName: entry.assetName, symbol: entry.symbol,
                                chainName: entry.chainName, amount: entry.amount, address: entry.counterparty,
                                transactionHash: entry.txHash.isEmpty ? nil : entry.txHash,
                                receiptBlockNumber: entry.blockHeight.map(Int.init), transactionHistorySource: "rust",
                                createdAt: entry.createdAtDate
                            )
                        }
                        return (records: records, error: false)
                    } catch { return (records: [], error: true) }
                }
            }
            var collected: [(records: [TransactionRecord], error: Bool)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var discovered: [TransactionRecord] = []
        var hadErrors = false
        for result in results {
            discovered.append(contentsOf: result.records)
            if result.error { hadErrors = true }
        }
        guard !discovered.isEmpty else {
            if hadErrors { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }
            return
        }
        upsertTransactions(discovered, chainName: chainName)
        if hadErrors {
            markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.")
        } else {
            markChainHealthy(chainName)
        }
    }

    /// Fetch one chain's history through the normalized path.
    ///
    /// Fifteen wrappers used to state this, each naming a chain, its id and a
    /// `resolved<Chain>Address` function — all three of which the callee can
    /// look up. Bitcoin, Dogecoin and the EVM family keep their own entry
    /// points below because their fetch genuinely differs.
    func refreshNormalizedTransactions(
        chainName: String, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
    ) async {
        let chainID = Chain(displayName: chainName)?.id ?? ""
        guard !chainID.isEmpty else { return }
        await refreshNormalizedChainTransactions(
            chainName: chainName, chainId: chainID,
            resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
            loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
}


// ────────────────────────────────────────────────────────────────────────────
// Bitcoin (special: HD xpub address expansion + single-address fallback)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    func fetchBitcoinHistoryPage(for wallet: ImportedWallet, limit: Int, cursor: String?) async throws -> BitcoinHistoryPage {
        if cursor == nil, let seedPhrase = storedSeedPhrase(for: wallet.id),
            !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let pathParts = wallet.seedDerivationPaths.path(for: .bitcoin).split(separator: "/")
            let accountPath = String(pathParts.prefix(4).joined(separator: "/"))
            if let xpub = try? WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                mnemonicPhrase: seedPhrase, passphrase: "", accountPath: accountPath
            ) {
                let page = try await fetchBitcoinHDHistoryPage(xpub: xpub, limit: limit)
                if !page.snapshots.isEmpty { return page }
            }
        }
        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty {
            let entries = try await WalletServiceBridge.shared.fetchNormalizedHistory(
                chainId: Chain.bitcoin.id, address: bitcoinAddress)
            return decodeBitcoinNormalizedPage(entries: entries, limit: limit)
        }
        if let bitcoinXpub = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinXpub.isEmpty {
            return try await fetchBitcoinHDHistoryPage(xpub: bitcoinXpub, limit: limit)
        }
        throw URLError(.fileDoesNotExist)
    }
    private func fetchBitcoinHDHistoryPage(xpub: String, limit: Int) async throws -> BitcoinHistoryPage {
        let mergedSnapshots = try await WalletServiceBridge.shared.fetchBitcoinHdHistoryPage(xpub: xpub, limit: UInt64(limit))
        return BitcoinHistoryPage(snapshots: mergedSnapshots, nextCursor: nil, sourceUsed: "rust.hd")
    }
    private func decodeBitcoinNormalizedPage(entries: [NormalizedHistoryItem], limit: Int) -> BitcoinHistoryPage {
        guard !entries.isEmpty else { return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust") }
        let snapshots: [CoreBitcoinHistorySnapshot] = Array(entries.prefix(limit)).map { e in
            CoreBitcoinHistorySnapshot(
                txid: e.txHash, amountBtc: e.amount, kind: e.kind, status: e.status,
                counterpartyAddress: e.counterparty, blockHeight: e.blockHeight,
                createdAtUnix: e.timestamp > 0 ? e.timestamp : Date().timeIntervalSince1970
            )
        }
        let nextCursor = entries.count > limit ? entries[limit - 1].txHash : nil
        return BitcoinHistoryPage(snapshots: snapshots, nextCursor: nextCursor, sourceUsed: "rust")
    }
    func refreshBitcoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        let walletSnapshot = wallets
        let bitcoinWallets = walletSnapshot.filter { wallet in
            guard wallet.selectedChain == "Bitcoin" else { return false }
            guard let targetWalletIDs else { return true }
            return targetWalletIDs.contains(wallet.id)
        }
        guard !bitcoinWallets.isEmpty else { return }
        let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))
        if !loadMore {
            for walletID in Set(bitcoinWallets.map(\.id)) { resetHistoryPagination(chainId: Chain.bitcoin.id, walletId: walletID) }
        }
        var discoveredTransactions: [TransactionRecord] = []
        var encounteredErrors = false
        for wallet in bitcoinWallets {
            if loadMore && historyPaginationExhausted(chainId: Chain.bitcoin.id, walletId: wallet.id) { continue }
            let cursor = loadMore ? historyPaginationCursor(chainId: Chain.bitcoin.id, walletId: wallet.id) : nil
            do {
                let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
                setHistoryCursor(chainId: Chain.bitcoin.id, walletId: wallet.id, cursor: page.nextCursor)
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(
                        walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed,
                        transactionCount: Int32(page.snapshots.count), nextCursor: page.nextCursor, error: nil))
                self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
                discoveredTransactions.append(
                    contentsOf: page.snapshots.map { snapshot in
                        TransactionRecord(
                            walletID: wallet.id, kind: TransactionKind(rawValue: snapshot.kind) ?? .send,
                            status: TransactionStatus(rawValue: snapshot.status) ?? .pending, walletName: wallet.name, assetName: "Bitcoin",
                            symbol: "BTC", chainName: "Bitcoin", amount: snapshot.amountBtc, address: snapshot.counterpartyAddress,
                            transactionHash: snapshot.txid, receiptBlockNumber: snapshot.blockHeight.map(Int.init),
                            transactionHistorySource: page.sourceUsed, createdAt: Date(timeIntervalSince1970: snapshot.createdAtUnix)
                        )
                    }
                )
            } catch {
                encounteredErrors = true
                setHistoryCursor(chainId: Chain.bitcoin.id, walletId: wallet.id, cursor: nil)
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? ""
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(
                        walletId: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0,
                        nextCursor: nil, error: error.localizedDescription))
                self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
            }
        }
        if !discoveredTransactions.isEmpty {
            upsertTransactions(discoveredTransactions, chainName: "Bitcoin")
            if encounteredErrors {
                markChainDegraded("Bitcoin", detail: "Bitcoin history loaded with partial provider failures.")
            } else {
                markChainHealthy("Bitcoin")
            }
        } else if encounteredErrors {
            markChainDegraded("Bitcoin", detail: "Bitcoin history refresh failed. Using cached history.")
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Dogecoin (special: multi-address per-wallet, UTXO aggregation)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    func refreshDogecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        let walletSnapshot = wallets
        // Explicit loops rather than compactMap: gathering a wallet's known
        // addresses now reads core's keypool, and map closures cannot await.
        var walletsToRefresh = await plannedDogecoinHistoryWallets(
            walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs) ?? []
        if walletsToRefresh.isEmpty {
            for wallet in walletSnapshot {
                guard wallet.selectedChain == "Dogecoin" else { continue }
                if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { continue }
                let addresses = await knownUTXOAddresses(for: wallet, chainName: "Dogecoin")
                guard !addresses.isEmpty else { continue }
                walletsToRefresh.append((wallet, addresses))
            }
        }
        guard !walletsToRefresh.isEmpty else { return }
        if !loadMore {
            for walletID in Set(walletsToRefresh.map { $0.0.id }) {
                resetHistoryPagination(chainId: Chain.dogecoin.id, walletId: walletID)
            }
        }
        var syncedTransactions: [TransactionRecord] = []
        var encounteredErrors = false
        for (wallet, dogecoinAddresses) in walletsToRefresh {
            if loadMore && historyPaginationExhausted(chainId: Chain.dogecoin.id, walletId: wallet.id) { continue }
            var collected: [NormalizedHistoryItem] = []
            for dogecoinAddress in dogecoinAddresses {
                do {
                    let entries = try await WalletServiceBridge.shared.fetchNormalizedHistory(
                        chainId: Chain.dogecoin.id, address: dogecoinAddress)
                    collected.append(contentsOf: entries)
                    // Dogecoin's fetch returns the whole history in one call,
                    // so the page it just wrote is also the last one.
                    setHistoryPage(
                        chainId: Chain.dogecoin.id, walletId: wallet.id, page: 1, isExhausted: true)
                } catch { encounteredErrors = true; continue }
            }
            let aggregates = historyAggregateDogecoin(input: DogecoinAggregateInput(ownAddresses: dogecoinAddresses, entries: collected))
            guard !aggregates.isEmpty else { continue }
            syncedTransactions.append(
                contentsOf: aggregates.map { agg in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: TransactionKind(rawValue: agg.kind) ?? .send,
                        status: TransactionStatus(rawValue: agg.status) ?? .confirmed,
                        walletName: wallet.name, assetName: "Dogecoin", symbol: "DOGE",
                        chainName: "Dogecoin", amount: agg.amount, address: agg.counterparty,
                        transactionHash: agg.hash, receiptBlockNumber: agg.blockNumber.map(Int.init),
                        transactionHistorySource: "dogecoin.providers",
                        createdAt: agg.createdAtUnix > 0 ? Date(timeIntervalSince1970: agg.createdAtUnix) : Date.distantPast
                    )
                })
        }
        guard !syncedTransactions.isEmpty else {
            if encounteredErrors { markChainDegraded("Dogecoin", detail: "Dogecoin history refresh failed. Using cached history.") }
            return
        }
        upsertTransactions(syncedTransactions, chainName: "Dogecoin")
        if encounteredErrors {
            markChainDegraded("Dogecoin", detail: "Dogecoin history loaded with partial provider failures.")
        } else {
            markChainHealthy("Dogecoin")
        }
    }
    private func plannedDogecoinHistoryWallets(
        walletSnapshot: [ImportedWallet], targetWalletIDs: Set<String>?
    ) async -> [(ImportedWallet, [String])]? {
        var inputs: [RefreshWalletInput] = []
        for wallet in walletSnapshot {
            inputs.append(
                RefreshWalletInput(
                    walletId: wallet.id, selectedChain: wallet.selectedChain,
                    addresses: await knownUTXOAddresses(for: wallet, chainName: "Dogecoin")
                ))
        }
        let targets = coreRefreshTargets(
            request: RefreshTargetsRequest(
                chainName: "Dogecoin", wallets: inputs,
                allowedWalletIds: targetWalletIDs.map(Array.init)))
        guard !targets.isEmpty else { return nil }
        let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id, $0) })
        return targets.compactMap { target in
            guard let wallet = walletByID[target.walletId] else { return nil }
            return (wallet, target.addresses)
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// EVM (special: token + native transfers, page-based pagination)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
    func refreshEVMTokenTransactions(
        chainName: String, maxResults: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
    ) async {
        guard evmChainContext(for: chainName) != nil else { return }
        let walletSnapshot = wallets
        let walletsToRefresh =
            plannedEVMHistoryWallets(
                chainName: chainName, walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs
            )
            ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, String)? in
                guard wallet.selectedChain == chainName, let address = resolvedEVMAddress(for: wallet, chainName: chainName) else {
                    return nil
                }
                if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { return nil }
                return (wallet, address)
            }
        guard !walletsToRefresh.isEmpty else { return }
        let refreshedWalletIDs = Set(walletsToRefresh.map { $0.0.id })
        let historyTargets: [([ImportedWallet], String, String)] =
            plannedEVMHistoryGroups(
                chainName: chainName, walletSnapshot: walletSnapshot, loadMore: loadMore, targetWalletIDs: targetWalletIDs
            )
            ?? {
                if loadMore {
                    return walletsToRefresh.map { ([$0.0], $0.1, normalizeEVMAddress($0.1)) }
                }
                return Dictionary(grouping: walletsToRefresh) {
                    normalizeEVMAddress($0.1)
                }
                .values.compactMap { group in
                    guard let first = group.first else { return nil }
                    return (group.map(\.0), first.1, normalizeEVMAddress(first.1))
                }
            }()
        var syncedTransactions: [TransactionRecord] = []
        var encounteredErrors = false
        let unknownTimestamp = Date.distantPast
        let requestedPageSize = max(20, min(maxResults ?? HistoryPaging.endpointBatchSize, 500))
        let evmChainId: String = historyPaginationChainId(chainName: chainName) ?? Chain.bnbChain.id
        if !loadMore {
            for walletID in Set(walletsToRefresh.map { $0.0.id }) {
                resetHistoryPagination(chainId: evmChainId, walletId: walletID)
                setHistoryPage(chainId: evmChainId, walletId: walletID, page: 1, isExhausted: false)
            }
        }
        for (targetWallets, _, normalizedAddress) in historyTargets {
            guard let representativeWallet = targetWallets.first else { continue }
            if loadMore && historyPaginationExhausted(chainId: evmChainId, walletId: representativeWallet.id) { continue }
            let currentPage = max(1, historyPaginationPage(chainId: evmChainId, walletId: representativeWallet.id))
            let page = loadMore ? (currentPage + 1) : currentPage
            let trackedTokens: [ChainTokenRegistryEntry]? =
                TokenTrackingChain.forChainName(chainName).map { enabledEVMTrackedTokens(for: $0) }
            var decodedPage = EvmHistoryPageDecoded(tokens: [], native: [])
            var tokenDiagnostics: EthereumTokenTransferHistoryDiagnostics?
            var tokenHistoryError: Error?
            guard let chainId = Chain(displayName: chainName)?.id else {
                encounteredErrors = true
                continue
            }
            let tokenDescriptors: [TokenDescriptor] =
                (trackedTokens ?? []).map { TokenDescriptor(contract: $0.contractAddress, symbol: $0.symbol, decimals: UInt8($0.decimals), name: $0.name) }
            do {
                decodedPage = try await WalletServiceBridge.shared.fetchEVMHistoryPage(
                    chainId: chainId, address: normalizedAddress, tokens: tokenDescriptors, page: page, pageSize: requestedPageSize
                )
                tokenDiagnostics = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizedAddress, rpcTransferCount: 0, rpcError: nil, blockscoutTransferCount: 0, blockscoutError: nil,
                    etherscanTransferCount: Int32(decodedPage.tokens.count), etherscanError: nil, ethplorerTransferCount: 0,
                    ethplorerError: nil, sourceUsed: "rust/etherscan", transferScanCount: 0, decodedTransferCount: 0,
                    unsupportedTransferDropCount: 0, decodingCompletenessRatio: 0
                )
            } catch {
                tokenHistoryError = error
                encounteredErrors = true
            }
            // The record above is built for *every* EVM chain, and this used to
            // decide where it went: Ethereum and its testnets to Ethereum,
            // Arbitrum to Arbitrum, Optimism to Optimism, and the other twenty
            // EVM mainnets nowhere — computed, then dropped. The diagnostics
            // registry is keyed by chain and takes any of them, so a chain's
            // token-transfer diagnostics go under its own mainnet. That is the
            // rule the Ethereum-family arm was already applying; it just had
            // two hand-written exceptions and no general case.
            let diagnosticsChainName: String? = Chain(displayName: chainName)?.mainnetCounterpart.displayName
            if let diagnosticsChainName {
                let entry =
                    tokenDiagnostics
                    ?? tokenHistoryError.map { error in
                        EthereumTokenTransferHistoryDiagnostics(
                            address: normalizedAddress, rpcTransferCount: 0,
                            rpcError: error.localizedDescription, blockscoutTransferCount: 0,
                            blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil,
                            ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "none",
                            transferScanCount: 0, decodedTransferCount: 0,
                            unsupportedTransferDropCount: 0, decodingCompletenessRatio: 0)
                    }
                if let entry {
                    for wallet in targetWallets {
                        recordEVMHistoryDiagnostics(
                            chainName: diagnosticsChainName, walletID: wallet.id, entry)
                    }
                }
                self[historyRunFor: diagnosticsChainName].lastUpdatedAt = Date()
            }
            let isLastPage = decodedPage.tokens.count < requestedPageSize && decodedPage.native.count < requestedPageSize
            for wallet in targetWallets {
                setHistoryPage(
                    chainId: evmChainId, walletId: wallet.id, page: page, isExhausted: isLastPage)
            }
            let nativeAsset = historyEvmNativeAsset(chainName: chainName) ?? EvmNativeAsset(assetName: "Ether", symbol: "ETH")
            let plannedRecords = planEvmTransactionRecords(
                request: EvmTransactionRecordRequest(
                    decodedPage: decodedPage,
                    normalizedAddress: normalizedAddress,
                    chainName: chainName,
                    tokenSourceUsed: tokenDiagnostics?.sourceUsed,
                    nativeAssetName: nativeAsset.assetName,
                    nativeAssetSymbol: nativeAsset.symbol,
                    wallets: targetWallets.map { EvmTransactionRecordWalletInput(walletId: $0.id, walletName: $0.name) },
                    unknownTimestampSentinelUnix: unknownTimestamp.timeIntervalSince1970
                )
            )
            syncedTransactions.append(
                contentsOf: plannedRecords.map { record in
                    let amount = (Decimal(string: record.amountDecimal) ?? 0) as NSDecimalNumber
                    return TransactionRecord(
                        walletID: record.walletId, kind: TransactionKind(rawValue: record.kind) ?? .send, status: .confirmed,
                        walletName: record.walletName, assetName: record.assetName, symbol: record.symbol, chainName: record.chainName,
                        amount: amount.doubleValue, address: record.counterparty, transactionHash: record.transactionHash,
                        receiptBlockNumber: Int(record.blockNumber), sourceAddress: record.sourceAddress,
                        transactionHistorySource: record.sourceUsed, createdAt: Date(timeIntervalSince1970: record.createdAtUnix)
                    )
                })
        }
        guard !syncedTransactions.isEmpty else {
            if encounteredErrors {
                let hasCachedHistory = transactions.contains { transaction in
                    guard transaction.chainName == chainName, let walletID = transaction.walletID else { return false }
                    return refreshedWalletIDs.contains(walletID)
                }
                if hasCachedHistory { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }
            }
            return
        }
        upsertTransactions(syncedTransactions, chainName: chainName)
        if encounteredErrors {
            markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.")
        } else {
            markChainHealthy(chainName)
        }
    }
    private func plannedEVMRefresh(
        chainName: String, walletSnapshot: [ImportedWallet], groupByNormalizedAddress: Bool, targetWalletIDs: Set<String>?
    ) -> EvmRefreshPlan? {
        let request = EvmRefreshTargetsRequest(
            chainName: chainName,
            wallets: walletSnapshot.map { wallet in
                RefreshWalletInput(
                    walletId: wallet.id, selectedChain: wallet.selectedChain,
                    addresses: [resolvedEVMAddress(for: wallet, chainName: chainName)].compactMap { $0 })
            },
            allowedWalletIds: targetWalletIDs.map(Array.init),
            groupByNormalizedAddress: groupByNormalizedAddress
        )
        return coreEvmRefreshTargets(request: request)
    }
    private func plannedEVMHistoryWallets(chainName: String, walletSnapshot: [ImportedWallet], targetWalletIDs: Set<String>?) -> [(
        ImportedWallet, String
    )]? {
        guard
            let plan = plannedEVMRefresh(
                chainName: chainName, walletSnapshot: walletSnapshot, groupByNormalizedAddress: false, targetWalletIDs: targetWalletIDs)
        else { return nil }
        return plan.walletTargets.compactMap { t in walletSnapshot.first(where: { $0.id == t.walletId }).map { ($0, t.address) } }
    }
    private func plannedEVMHistoryGroups(chainName: String, walletSnapshot: [ImportedWallet], loadMore: Bool, targetWalletIDs: Set<String>?)
        -> [([ImportedWallet], String, String)]?
    {
        guard
            let plan = plannedEVMRefresh(
                chainName: chainName, walletSnapshot: walletSnapshot, groupByNormalizedAddress: !loadMore, targetWalletIDs: targetWalletIDs)
        else { return nil }
        let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id, $0) })
        return plan.groupedTargets.compactMap { t in
            let wallets = t.walletIds.compactMap { walletByID[$0] }
            return wallets.isEmpty ? nil : (wallets, t.address, t.normalizedAddress)
        }
    }
}
