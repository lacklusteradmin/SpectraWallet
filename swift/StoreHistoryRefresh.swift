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
        wsb.isHistoryExhausted(chainId: chainId, walletId: walletId)
    }
    func historyPaginationCursor(chainId: String, walletId: String) -> String? {
        wsb.historyNextCursor(chainId: chainId, walletId: walletId)
    }
    func historyPaginationPage(chainId: String, walletId: String) -> Int { Int(wsb.historyNextPage(chainId: chainId, walletId: walletId)) }
    func setHistoryCursor(chainId: String, walletId: String, cursor: String?) {
        wsb.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: cursor); notifyHistoryMutation()
    }
    func setHistoryPage(chainId: String, walletId: String, page: Int) {
        wsb.setHistoryPage(chainId: chainId, walletId: walletId, page: UInt32(max(0, page))); notifyHistoryMutation()
    }
    func markHistoryExhausted(chainId: String, walletId: String) {
        wsb.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: true); notifyHistoryMutation()
    }
    func markHistoryActive(chainId: String, walletId: String) {
        wsb.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: false); notifyHistoryMutation()
    }
    func resetHistoryPagination(chainId: String, walletId: String) {
        wsb.resetHistory(chainId: chainId, walletId: walletId); notifyHistoryMutation()
    }
    func resetHistoryPaginationForWallet(_ walletId: String) { wsb.resetHistoryForWallet(walletId: walletId); notifyHistoryMutation() }
    func resetAllHistoryPagination() { wsb.resetAllHistory(); notifyHistoryMutation() }
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
        // UTXO chains share `refresh<Chain>Transactions(limit:loadMore:targetWalletIDs:)`.
        let utxoChains: [(name: String, refresh: (Int?, Bool, Set<String>?) async -> Void)] = [
            ("Bitcoin",      refreshBitcoinTransactions),
            ("Bitcoin Cash", refreshBitcoinCashTransactions),
            ("Bitcoin SV",   refreshBitcoinSVTransactions),
            ("Litecoin",     refreshLitecoinTransactions),
            ("Dogecoin",     refreshDogecoinTransactions),
        ]
        for (name, refresh) in utxoChains where hasWalletForChain(name) {
            await refresh(limit, true, eligibleWalletIDs)
        }
        // EVM chains all dispatch through `refreshEVMTokenTransactions(chainName:...)`.
        let evmChainNames = [
            "Ethereum", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid",
            "Polygon", "Base", "Linea", "Scroll", "Blast", "Mantle",
        ]
        for chainName in evmChainNames where hasWalletForChain(chainName) {
            await refreshEVMTokenTransactions(
                chainName: chainName, maxResults: limit, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if hasWalletForChain("Tron") { await refreshTronTransactions(loadMore: true, targetWalletIDs: eligibleWalletIDs) }
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
        let targets = coreNormalizedRefreshTargets(
            request: NormalizedRefreshTargetsRequest(
                chainName: chainName,
                wallets: walletSnapshot.enumerated().map { index, wallet in
                    NormalizedRefreshWalletInput(
                        index: UInt64(index), walletId: wallet.id, selectedChain: wallet.selectedChain, address: resolveAddress(wallet)
                    )
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
                guard let wallet = walletByID[target.walletId] else { continue }
                let address = target.address
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

    // ── Per-chain refresh methods (thin wrappers over the generic above)
    func refreshBitcoinCashTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(
            chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash, resolveAddress: { resolvedBitcoinCashAddress(for: $0) }, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshBitcoinSVTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(
            chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv, resolveAddress: { resolvedBitcoinSVAddress(for: $0) }, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshLitecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(
            chainName: "Litecoin", chainId: SpectraChainID.litecoin, resolveAddress: { resolvedLitecoinAddress(for: $0) }, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshCardanoTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Cardano", chainId: SpectraChainID.cardano, resolveAddress: { resolvedCardanoAddress(for: $0) })
    }
    func refreshXRPTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "XRP Ledger", chainId: SpectraChainID.xrp, resolveAddress: { resolvedXRPAddress(for: $0) })
    }
    func refreshStellarTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Stellar", chainId: SpectraChainID.stellar, resolveAddress: { resolvedStellarAddress(for: $0) })
    }
    func refreshMoneroTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Monero", chainId: SpectraChainID.monero, resolveAddress: { resolvedMoneroAddress(for: $0) })
    }
    func refreshSuiTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Sui", chainId: SpectraChainID.sui, resolveAddress: { resolvedSuiAddress(for: $0) })
    }
    func refreshICPTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Internet Computer", chainId: SpectraChainID.icp, resolveAddress: { resolvedICPAddress(for: $0) })
    }
    func refreshAptosTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Aptos", chainId: SpectraChainID.aptos, resolveAddress: { resolvedAptosAddress(for: $0) })
    }
    func refreshTONTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "TON", chainId: SpectraChainID.ton, resolveAddress: { resolvedTONAddress(for: $0) })
    }
    func refreshNearTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "NEAR", chainId: SpectraChainID.near, resolveAddress: { resolvedNearAddress(for: $0) })
    }
    func refreshPolkadotTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Polkadot", chainId: SpectraChainID.polkadot, resolveAddress: { resolvedPolkadotAddress(for: $0) })
    }
    func refreshSolanaTransactions(loadMore: Bool = false) async {
        await refreshNormalizedChainTransactions(
            chainName: "Solana", chainId: SpectraChainID.solana, resolveAddress: { resolvedSolanaAddress(for: $0) })
    }
    func refreshTronTransactions(loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(
            chainName: "Tron", chainId: SpectraChainID.tron, resolveAddress: { resolvedTronAddress(for: $0) }, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
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
                chainId: SpectraChainID.bitcoin, address: bitcoinAddress)
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
            for walletID in Set(bitcoinWallets.map(\.id)) { resetHistoryPagination(chainId: SpectraChainID.bitcoin, walletId: walletID) }
        }
        var discoveredTransactions: [TransactionRecord] = []
        var encounteredErrors = false
        for wallet in bitcoinWallets {
            if loadMore && historyPaginationExhausted(chainId: SpectraChainID.bitcoin, walletId: wallet.id) { continue }
            let cursor = loadMore ? historyPaginationCursor(chainId: SpectraChainID.bitcoin, walletId: wallet.id) : nil
            do {
                let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
                setHistoryCursor(chainId: SpectraChainID.bitcoin, walletId: wallet.id, cursor: page.nextCursor)
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count),
                    nextCursor: page.nextCursor, error: nil
                )
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
                setHistoryCursor(chainId: SpectraChainID.bitcoin, walletId: wallet.id, cursor: nil)
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? ""
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0, nextCursor: nil,
                    error: error.localizedDescription
                )
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
                resetHistoryPagination(chainId: SpectraChainID.dogecoin, walletId: walletID)
            }
        }
        var syncedTransactions: [TransactionRecord] = []
        var encounteredErrors = false
        for (wallet, dogecoinAddresses) in walletsToRefresh {
            if loadMore && historyPaginationExhausted(chainId: SpectraChainID.dogecoin, walletId: wallet.id) { continue }
            var collected: [NormalizedHistoryItem] = []
            for dogecoinAddress in dogecoinAddresses {
                do {
                    let entries = try await WalletServiceBridge.shared.fetchNormalizedHistory(
                        chainId: SpectraChainID.dogecoin, address: dogecoinAddress)
                    collected.append(contentsOf: entries)
                    markHistoryExhausted(chainId: SpectraChainID.dogecoin, walletId: wallet.id)
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
        var inputs: [DogecoinRefreshWalletInput] = []
        for (index, wallet) in walletSnapshot.enumerated() {
            inputs.append(
                DogecoinRefreshWalletInput(
                    index: UInt64(index), walletId: wallet.id, selectedChain: wallet.selectedChain,
                    addresses: await knownUTXOAddresses(for: wallet, chainName: "Dogecoin")
                ))
        }
        let request = DogecoinRefreshTargetsRequest(
            wallets: inputs, allowedWalletIds: targetWalletIDs.map(Array.init)
        )
        let targets = coreDogecoinRefreshTargets(request: request)
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
        guard let chain = evmChainContext(for: chainName) else { return }
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
        let evmChainId: String = historyPaginationChainId(chainName: chainName) ?? SpectraChainID.bsc
        if !loadMore {
            for walletID in Set(walletsToRefresh.map { $0.0.id }) {
                resetHistoryPagination(chainId: evmChainId, walletId: walletID)
                setHistoryPage(chainId: evmChainId, walletId: walletID, page: 1)
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
            guard let chainId = SpectraChainID.id(for: chainName) else {
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
            typealias DiagsByWallet = [String: EthereumTokenTransferHistoryDiagnostics]
            let diagsKP: ReferenceWritableKeyPath<AppState, DiagsByWallet>? =
                chain.isEthereumFamily
                ? \.ethereumHistoryDiagnosticsByWallet
                : chain == .arbitrum
                    ? \.arbitrumHistoryDiagnosticsByWallet
                    : chain == .optimism
                        ? \.optimismHistoryDiagnosticsByWallet
                        : nil
            // The timestamp is keyed by chain now, so it needs a name rather
            // than a key path. A `?:` chain ending in `nil` also infers a
            // read-only `KeyPath`, which a subscript-backed path cannot satisfy.
            let historyRunChainName: String? =
                chain.isEthereumFamily
                ? "Ethereum"
                : chain == .arbitrum ? "Arbitrum" : chain == .optimism ? "Optimism" : nil
            if let diagsKP, let historyRunChainName {
                if let tokenDiagnostics {
                    var diags = self[keyPath: diagsKP]
                    for wallet in targetWallets { diags[wallet.id] = tokenDiagnostics }
                    self[keyPath: diagsKP] = diags
                } else if let tokenHistoryError {
                    let errDiag = EthereumTokenTransferHistoryDiagnostics(
                        address: normalizedAddress, rpcTransferCount: 0, rpcError: tokenHistoryError.localizedDescription,
                        blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil,
                        ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "none", transferScanCount: 0, decodedTransferCount: 0,
                        unsupportedTransferDropCount: 0, decodingCompletenessRatio: 0
                    )
                    var diags = self[keyPath: diagsKP]
                    for wallet in targetWallets { diags[wallet.id] = errDiag }
                    self[keyPath: diagsKP] = diags
                }
                self[historyRunFor: historyRunChainName].lastUpdatedAt = Date()
            }
            let isLastPage = decodedPage.tokens.count < requestedPageSize && decodedPage.native.count < requestedPageSize
            for wallet in targetWallets {
                if isLastPage {
                    markHistoryExhausted(chainId: evmChainId, walletId: wallet.id)
                } else {
                    markHistoryActive(chainId: evmChainId, walletId: wallet.id)
                }
                setHistoryPage(chainId: evmChainId, walletId: wallet.id, page: page)
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
            wallets: walletSnapshot.enumerated().map { index, wallet in
                EvmRefreshWalletInput(
                    index: UInt64(index), walletId: wallet.id, selectedChain: wallet.selectedChain,
                    address: resolvedEVMAddress(for: wallet, chainName: chainName))
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
