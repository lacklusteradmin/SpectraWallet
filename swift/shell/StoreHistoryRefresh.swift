import Combine
import Foundation
// HistoryChainID mapping authoritative in Rust (`history_pagination_chain_id`).
private enum HistoryChainID {
    static let bitcoin: UInt32     =  0
    static let ethereum: UInt32    =  1
    static let dogecoin: UInt32    =  3
    static let litecoin: UInt32    =  5
    static let bitcoinCash: UInt32 =  6
    static let tron: UInt32        =  7
    static let arbitrum: UInt32    = 11
    static let optimism: UInt32    = 12
    static let bitcoinSV: UInt32   = 22
    static let bnb: UInt32         = 23
    static let hyperliquid: UInt32 = 24
}
extension AppState {
    private var wsb: WalletServiceBridge { WalletServiceBridge.shared }
    private func notifyHistoryMutation() { objectWillChange.send() }
    func historyPaginationExhausted(chainId: UInt32, walletId: String) -> Bool { wsb.isHistoryExhausted(chainId: chainId, walletId: walletId) }
    func historyPaginationCursor(chainId: UInt32, walletId: String) -> String? { wsb.historyNextCursor(chainId: chainId, walletId: walletId) }
    func historyPaginationPage(chainId: UInt32, walletId: String) -> Int { Int(wsb.historyNextPage(chainId: chainId, walletId: walletId)) }
    func setHistoryCursor(chainId: UInt32, walletId: String, cursor: String?) { wsb.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: cursor); notifyHistoryMutation() }
    func setHistoryPage(chainId: UInt32, walletId: String, page: Int) { wsb.setHistoryPage(chainId: chainId, walletId: walletId, page: UInt32(max(0, page))); notifyHistoryMutation() }
    func markHistoryExhausted(chainId: UInt32, walletId: String) { wsb.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: true); notifyHistoryMutation() }
    func markHistoryActive(chainId: UInt32, walletId: String) { wsb.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: false); notifyHistoryMutation() }
    func resetHistoryPagination(chainId: UInt32, walletId: String) { wsb.resetHistory(chainId: chainId, walletId: walletId); notifyHistoryMutation() }
    func resetHistoryPaginationForWallet(_ walletId: String) { wsb.resetHistoryForWallet(walletId: walletId); notifyHistoryMutation() }
    func resetAllHistoryPagination() { wsb.resetAllHistory(); notifyHistoryMutation() }
}
// ────────────────────────────────────────────────────────────────────────────
// Normalized history fetch: a single function replaces all per-chain
// refresh methods for non-EVM, non-UTXO-HD chains.
// Rust normalizes and decodes; Swift maps the typed items to TransactionRecord.
// ────────────────────────────────────────────────────────────────────────────
private typealias NormalizedChainEntry = NormalizedHistoryItem
extension NormalizedHistoryItem {
    fileprivate var createdAtDate: Date { timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date() }
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
    func loadMoreOnChainHistory(for walletIDs: Set<String>) async { await WalletFetchLayer.loadMoreOnChainHistory(for: walletIDs, using: self) }

    // ── Generic normalized refresh (covers BCH, BSV, LTC, XRP, XLM, ADA, DOT,
    //    SOL, TRX, SUI, APT, TON, NEAR, ICP, XMR and any future account-based chain)
    func refreshNormalizedChainTransactions(
        chainName: String,
        chainId: UInt32,
        resolveAddress: (ImportedWallet) -> String?,
        upsert: ([TransactionRecord]) -> Void,
        loadMore: Bool = false,
        targetWalletIDs: Set<String>? = nil
    ) async {
        let walletSnapshot = wallets
        let filtered = walletSnapshot.filter { wallet in
            guard wallet.selectedChain == chainName, resolveAddress(wallet) != nil else { return false }
            guard let targetWalletIDs else { return true }
            return targetWalletIDs.contains(wallet.id)
        }
        guard !filtered.isEmpty else { return }
        var discovered: [TransactionRecord] = []
        var hadErrors = false
        for wallet in filtered {
            guard let address = resolveAddress(wallet) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: chainId, address: address)
                let entries = decodeNormalizedHistory(json)
                discovered.append(contentsOf: entries.map { entry in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: TransactionKind(rawValue: entry.kind) ?? .send,
                        status: TransactionStatus(rawValue: entry.status) ?? .confirmed,
                        walletName: wallet.name, assetName: entry.assetName, symbol: entry.symbol,
                        chainName: entry.chainName, amount: entry.amount, address: entry.counterparty,
                        transactionHash: entry.txHash.isEmpty ? nil : entry.txHash,
                        receiptBlockNumber: entry.blockHeight.map(Int.init), transactionHistorySource: "rust",
                        createdAt: entry.createdAtDate
                    )
                })
            } catch { hadErrors = true }
        }
        guard !discovered.isEmpty else {
            if hadErrors { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }
            return
        }
        upsert(discovered)
        if hadErrors { markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.") } else { markChainHealthy(chainName) }
    }

    private func decodeNormalizedHistory(_ json: String) -> [NormalizedChainEntry] {
        historyDecodeNormalized(json: json)
    }

    // ── Per-chain refresh methods (thin wrappers over the generic above)
    func refreshBitcoinCashTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash, resolveAddress: { resolvedBitcoinCashAddress(for: $0) }, upsert: upsertBitcoinCashTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshBitcoinSVTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv, resolveAddress: { resolvedBitcoinSVAddress(for: $0) }, upsert: upsertBitcoinSVTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshLitecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
        await refreshNormalizedChainTransactions(chainName: "Litecoin", chainId: SpectraChainID.litecoin, resolveAddress: { resolvedLitecoinAddress(for: $0) }, upsert: upsertLitecoinTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
    }
    func refreshCardanoTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Cardano", chainId: SpectraChainID.cardano, resolveAddress: { resolvedCardanoAddress(for: $0) }, upsert: upsertCardanoTransactions) }
    func refreshXRPTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "XRP Ledger", chainId: SpectraChainID.xrp, resolveAddress: { resolvedXRPAddress(for: $0) }, upsert: upsertXRPTransactions) }
    func refreshStellarTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Stellar", chainId: SpectraChainID.stellar, resolveAddress: { resolvedStellarAddress(for: $0) }, upsert: upsertStellarTransactions) }
    func refreshMoneroTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Monero", chainId: SpectraChainID.monero, resolveAddress: { resolvedMoneroAddress(for: $0) }, upsert: upsertMoneroTransactions) }
    func refreshSuiTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Sui", chainId: SpectraChainID.sui, resolveAddress: { resolvedSuiAddress(for: $0) }, upsert: upsertSuiTransactions) }
    func refreshICPTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Internet Computer", chainId: SpectraChainID.icp, resolveAddress: { resolvedICPAddress(for: $0) }, upsert: upsertICPTransactions) }
    func refreshAptosTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Aptos", chainId: SpectraChainID.aptos, resolveAddress: { resolvedAptosAddress(for: $0) }, upsert: upsertAptosTransactions) }
    func refreshTONTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "TON", chainId: SpectraChainID.ton, resolveAddress: { resolvedTONAddress(for: $0) }, upsert: upsertTONTransactions) }
    func refreshNearTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "NEAR", chainId: SpectraChainID.near, resolveAddress: { resolvedNearAddress(for: $0) }, upsert: upsertNearTransactions) }
    func refreshPolkadotTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Polkadot", chainId: SpectraChainID.polkadot, resolveAddress: { resolvedPolkadotAddress(for: $0) }, upsert: upsertPolkadotTransactions) }
    func refreshSolanaTransactions(loadMore: Bool = false) async { await refreshNormalizedChainTransactions(chainName: "Solana", chainId: SpectraChainID.solana, resolveAddress: { resolvedSolanaAddress(for: $0) }, upsert: upsertSolanaTransactions) }
    func refreshTronTransactions(loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async { await refreshNormalizedChainTransactions(chainName: "Tron", chainId: SpectraChainID.tron, resolveAddress: { resolvedTronAddress(for: $0) }, upsert: upsertTronTransactions, loadMore: loadMore, targetWalletIDs: targetWalletIDs) }
}

// ────────────────────────────────────────────────────────────────────────────
// Bitcoin (special: HD xpub address expansion + single-address fallback)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
func fetchBitcoinHistoryPage(for wallet: ImportedWallet, limit: Int, cursor: String?) async throws -> BitcoinHistoryPage {
    if cursor == nil, let seedPhrase = storedSeedPhrase(for: wallet.id), !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let pathParts = wallet.seedDerivationPaths.bitcoin.split(separator: "/")
        let accountPath = String(pathParts.prefix(4).joined(separator: "/"))
        if let xpub = try? await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
            mnemonicPhrase: seedPhrase, passphrase: "", accountPath: accountPath
        ) {
            let page = try await fetchBitcoinHDHistoryPage(xpub: xpub, limit: limit)
            if !page.snapshots.isEmpty { return page }}}
    if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty {
        let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: SpectraChainID.bitcoin, address: bitcoinAddress)
        return decodeBitcoinNormalizedPage(json: json, limit: limit)
    }
    if let bitcoinXpub = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinXpub.isEmpty { return try await fetchBitcoinHDHistoryPage(xpub: bitcoinXpub, limit: limit) }
    throw URLError(.fileDoesNotExist)
}
private func fetchBitcoinHDHistoryPage(xpub: String, limit: Int) async throws -> BitcoinHistoryPage {
    async let receiveTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(xpub: xpub, change: 0, startIndex: 0, count: 20)
    async let changeTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(xpub: xpub, change: 1, startIndex: 0, count: 10)
    let (receiveJSON, changeJSON) = try await (receiveTask, changeTask)
    let allAddresses = historyDecodeHdAddresses(json: receiveJSON) + historyDecodeHdAddresses(json: changeJSON)
    guard !allAddresses.isEmpty else { return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust.hd") }
    let indexedAddresses = Array(allAddresses.enumerated())
    let fetchedSnapshots = await collectLimitedConcurrentIndexedResults(from: indexedAddresses, maxConcurrent: 4) { entry in
        let (index, address) = entry
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.bitcoin, address: address)
            let payloads = historyDecodeBitcoinRawSnapshots(json: json).map { s in
                WalletRustBitcoinHistorySnapshotPayload(
                    txid: s.txid, amountBtc: s.amountBtc, kind: s.kind, status: s.status,
                    counterpartyAddress: s.counterpartyAddress,
                    blockHeight: s.blockHeight, createdAtUnix: s.createdAtUnix
                )
            }
            return (index, payloads)
        } catch { return (index, nil) }
    }
    let mergedSnapshots = try WalletRustAppCoreBridge.mergeBitcoinHistorySnapshots(
        WalletRustMergeBitcoinHistorySnapshotsRequest(
            snapshots: fetchedSnapshots.sorted { $0.key < $1.key }.flatMap(\.value), ownedAddresses: allAddresses, limit: limit
        )
    )
    return BitcoinHistoryPage(
        snapshots: mergedSnapshots.map { snapshot in
            BitcoinHistorySnapshot(
                txid: snapshot.txid, amountBTC: snapshot.amountBtc, kind: TransactionKind(rawValue: snapshot.kind) ?? .send, status: TransactionStatus(rawValue: snapshot.status) ?? .pending, counterpartyAddress: snapshot.counterpartyAddress, blockHeight: snapshot.blockHeight.map(Int.init), createdAt: Date(timeIntervalSince1970: snapshot.createdAtUnix)
            )
        }, nextCursor: nil, sourceUsed: "rust.hd"
    )
}
private func decodeBitcoinNormalizedPage(json: String, limit: Int) -> BitcoinHistoryPage {
    let entries = historyDecodeNormalized(json: json)
    guard !entries.isEmpty else { return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust") }
    let snapshots: [BitcoinHistorySnapshot] = Array(entries.prefix(limit)).map { e in
        BitcoinHistorySnapshot(
            txid: e.txHash, amountBTC: e.amount,
            kind: TransactionKind(rawValue: e.kind) ?? .send,
            status: TransactionStatus(rawValue: e.status) ?? .confirmed,
            counterpartyAddress: e.counterparty,
            blockHeight: e.blockHeight.map(Int.init),
            createdAt: e.timestamp > 0 ? Date(timeIntervalSince1970: e.timestamp) : Date()
        )
    }
    let nextCursor = entries.count > limit ? entries[limit - 1].txHash : nil
    return BitcoinHistoryPage(snapshots: snapshots, nextCursor: nextCursor, sourceUsed: "rust")
}
func decodeRustHistoryJSON(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return arr
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
        for walletID in Set(bitcoinWallets.map(\.id)) { resetHistoryPagination(chainId: HistoryChainID.bitcoin, walletId: walletID) }}
    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for wallet in bitcoinWallets {
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.bitcoin, walletId: wallet.id) { continue }
        let cursor = loadMore ? historyPaginationCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id) : nil
        do {
            let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: page.nextCursor)
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count), nextCursor: page.nextCursor, error: nil
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id, kind: snapshot.kind, status: snapshot.status, walletName: wallet.name, assetName: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", amount: snapshot.amountBTC, address: snapshot.counterpartyAddress, transactionHash: snapshot.txid, receiptBlockNumber: snapshot.blockHeight, transactionHistorySource: page.sourceUsed, createdAt: snapshot.createdAt
                    )
                }
            )
        } catch {
            encounteredErrors = true
            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: nil)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? ""
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletId: wallet.id, identifier: identifier, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }}
    if !discoveredTransactions.isEmpty {
        upsertBitcoinTransactions(discoveredTransactions)
        if encounteredErrors { markChainDegraded("Bitcoin", detail: "Bitcoin history loaded with partial provider failures.") } else { markChainHealthy("Bitcoin") }
    } else if encounteredErrors { markChainDegraded("Bitcoin", detail: "Bitcoin history refresh failed. Using cached history.") }
}
}

// ────────────────────────────────────────────────────────────────────────────
// Dogecoin (special: multi-address per-wallet, UTXO aggregation)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
func refreshDogecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil) async {
    let walletSnapshot = wallets
    let walletsToRefresh = plannedDogecoinHistoryWallets(walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, [String])? in
        guard wallet.selectedChain == "Dogecoin", !knownDogecoinAddresses(for: wallet).isEmpty else { return nil }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { return nil }
        return (wallet, knownDogecoinAddresses(for: wallet))
    }
    guard !walletsToRefresh.isEmpty else { return }
    if !loadMore {
        for walletID in Set(walletsToRefresh.map { $0.0.id }) {
            resetHistoryPagination(chainId: HistoryChainID.dogecoin, walletId: walletID)
        }}
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for (wallet, dogecoinAddresses) in walletsToRefresh {
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id) { continue }
        var collected: [NormalizedHistoryItem] = []
        for dogecoinAddress in dogecoinAddresses {
            do {
                let json = try await WalletServiceBridge.shared.fetchNormalizedHistoryJSON(chainId: SpectraChainID.dogecoin, address: dogecoinAddress)
                collected.append(contentsOf: decodeNormalizedHistory(json))
                markHistoryExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id)
            } catch { encounteredErrors = true; continue }
        }
        let aggregates = historyAggregateDogecoin(input: DogecoinAggregateInput(ownAddresses: dogecoinAddresses, entries: collected))
        guard !aggregates.isEmpty else { continue }
        syncedTransactions.append(contentsOf: aggregates.map { agg in
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
    upsertDogecoinTransactions(syncedTransactions)
    if encounteredErrors { markChainDegraded("Dogecoin", detail: "Dogecoin history loaded with partial provider failures.") } else { markChainHealthy("Dogecoin") }
}
private func plannedDogecoinHistoryWallets(
    walletSnapshot: [ImportedWallet], targetWalletIDs: Set<String>?
) -> [(ImportedWallet, [String])]? {
    let request = WalletRustDogecoinRefreshTargetsRequest(
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustDogecoinRefreshWalletInput(
                index: index, walletID: wallet.id, selectedChain: wallet.selectedChain, addresses: knownDogecoinAddresses(for: wallet)
            )
        }, allowedWalletIDs: targetWalletIDs.map(Array.init)
    )
    guard let targets = try? WalletRustAppCoreBridge.planDogecoinRefreshTargets(request) else { return nil }
    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id, $0) })
    return targets.compactMap { target in
        guard let wallet = walletByID[target.walletID] else { return nil }
        return (wallet, target.addresses)
    }
}
}

// ────────────────────────────────────────────────────────────────────────────
// EVM (special: token + native transfers, page-based pagination)
// ────────────────────────────────────────────────────────────────────────────
extension AppState {
@MainActor func refreshEVMTokenTransactions(
    chainName: String, maxResults: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<String>? = nil
) async {
    guard let chain = evmChainContext(for: chainName) else { return }
    let walletSnapshot = wallets
    let walletsToRefresh = plannedEVMHistoryWallets(
        chainName: chainName, walletSnapshot: walletSnapshot, targetWalletIDs: targetWalletIDs
    ) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, String)? in
        guard wallet.selectedChain == chainName, let address = resolvedEVMAddress(for: wallet, chainName: chainName) else { return nil }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) { return nil }
        return (wallet, address)
    }
    guard !walletsToRefresh.isEmpty else { return }
    let refreshedWalletIDs = Set(walletsToRefresh.map { $0.0.id })
    let historyTargets: [([ImportedWallet], String, String)] = plannedEVMHistoryGroups(
        chainName: chainName, walletSnapshot: walletSnapshot, loadMore: loadMore, targetWalletIDs: targetWalletIDs
    ) ?? {
        if loadMore {
            return walletsToRefresh.map { ([$0.0], $0.1, normalizeEVMAddress($0.1)) }}
        return Dictionary(grouping: walletsToRefresh) {
            normalizeEVMAddress($0.1)
        }
        .values.compactMap { group in
            guard let first = group.first else { return nil }
            return (group.map(\.0), first.1, normalizeEVMAddress(first.1))
        }}()
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    let unknownTimestamp = Date.distantPast
    let requestedPageSize = max(20, min(maxResults ?? HistoryPaging.endpointBatchSize, 500))
    let evmChainId: UInt32 = historyPaginationChainId(chainName: chainName) ?? HistoryChainID.bnb
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
        let trackedTokens: [EthereumSupportedToken]? = if chain.isEthereumMainnet { enabledEthereumTrackedTokens() } else if chain == .arbitrum { enabledArbitrumTrackedTokens() } else if chain == .optimism { enabledOptimismTrackedTokens() } else if chain == .hyperliquid { enabledHyperliquidTrackedTokens() } else if chain == .bnb { enabledBNBTrackedTokens() } else { nil }
        var tokenHistory: [EthereumTokenTransferSnapshot] = []
        var tokenDiagnostics: EthereumTokenTransferHistoryDiagnostics?
        var tokenHistoryError: Error?
        var nativeTransfers: [EthereumNativeTransferSnapshot] = []
        guard let chainId = SpectraChainID.id(for: chainName) else {
            encounteredErrors = true
            continue
        }
        let tokenTuples: [(contract: String, symbol: String, name: String, decimals: Int)] =
            (trackedTokens ?? []).map { ($0.contractAddress, $0.symbol, $0.name, Int($0.decimals)) }
        do {
            let json = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(
                chainId: chainId, address: normalizedAddress, tokens: tokenTuples, page: page, pageSize: requestedPageSize
            )
            let (decodedToken, decodedNative) = decodeEvmHistoryPageJSON(json)
            tokenHistory = decodedToken
            nativeTransfers = decodedNative
            tokenDiagnostics = EthereumTokenTransferHistoryDiagnostics(
                address: normalizedAddress, rpcTransferCount: 0, rpcError: nil, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: Int32(decodedToken.count), etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "rust/etherscan", transferScanCount: 0, decodedTransferCount: 0, unsupportedTransferDropCount: 0, decodingCompletenessRatio: 0
            )
        } catch {
            tokenHistoryError = error
            encounteredErrors = true
        }
        typealias DiagsByWallet = [String: EthereumTokenTransferHistoryDiagnostics]
        let diagsKP: ReferenceWritableKeyPath<AppState, DiagsByWallet>? =
            chain.isEthereumFamily ? \.ethereumHistoryDiagnosticsByWallet
            : chain == .arbitrum   ? \.arbitrumHistoryDiagnosticsByWallet
            : chain == .optimism   ? \.optimismHistoryDiagnosticsByWallet
            : nil
        let tsKP: ReferenceWritableKeyPath<AppState, Date?>? =
            chain.isEthereumFamily ? \.ethereumHistoryDiagnosticsLastUpdatedAt
            : chain == .arbitrum   ? \.arbitrumHistoryDiagnosticsLastUpdatedAt
            : chain == .optimism   ? \.optimismHistoryDiagnosticsLastUpdatedAt
            : nil
        if let diagsKP, let tsKP {
            if let tokenDiagnostics {
                var diags = self[keyPath: diagsKP]
                for wallet in targetWallets { diags[wallet.id] = tokenDiagnostics }
                self[keyPath: diagsKP] = diags
            } else if let tokenHistoryError {
                let errDiag = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizedAddress, rpcTransferCount: 0, rpcError: tokenHistoryError.localizedDescription, blockscoutTransferCount: 0, blockscoutError: nil, etherscanTransferCount: 0, etherscanError: nil, ethplorerTransferCount: 0, ethplorerError: nil, sourceUsed: "none", transferScanCount: 0, decodedTransferCount: 0, unsupportedTransferDropCount: 0, decodingCompletenessRatio: 0
                )
                var diags = self[keyPath: diagsKP]
                for wallet in targetWallets { diags[wallet.id] = errDiag }
                self[keyPath: diagsKP] = diags
            }
            self[keyPath: tsKP] = Date()
        }
        let isLastPage = tokenHistory.count < requestedPageSize && nativeTransfers.count < requestedPageSize
        for wallet in targetWallets {
            if isLastPage { markHistoryExhausted(chainId: evmChainId, walletId: wallet.id) } else { markHistoryActive(chainId: evmChainId, walletId: wallet.id) }
            setHistoryPage(chainId: evmChainId, walletId: wallet.id, page: page)
        }
        for wallet in targetWallets {
            for transfer in tokenHistory {
                let isOutgoing = transfer.fromAddress == normalizedAddress
                let isIncoming = transfer.toAddress == normalizedAddress
                guard isOutgoing || isIncoming else { continue }
                let counterparty = isOutgoing ? transfer.toAddress : transfer.fromAddress
                let walletSideAddress = isOutgoing ? transfer.fromAddress : transfer.toAddress
                let createdAt = transfer.timestamp ?? unknownTimestamp
                syncedTransactions.append(
                    TransactionRecord(
                        walletID: wallet.id, kind: isOutgoing ? .send : .receive, status: .confirmed, walletName: wallet.name, assetName: transfer.tokenName, symbol: transfer.symbol, chainName: chainName, amount: NSDecimalNumber(decimal: transfer.amount).doubleValue, address: counterparty, transactionHash: transfer.transactionHash, receiptBlockNumber: transfer.blockNumber, sourceAddress: walletSideAddress, transactionHistorySource: tokenDiagnostics?.sourceUsed ?? "none", createdAt: createdAt
                    )
                )
            }}
        for wallet in targetWallets {
            for transfer in nativeTransfers {
                let isOutgoing = transfer.fromAddress == normalizedAddress
                let isIncoming = transfer.toAddress == normalizedAddress
                guard isOutgoing || isIncoming else { continue }
                let counterparty = isOutgoing ? transfer.toAddress : transfer.fromAddress
                let walletSideAddress = isOutgoing ? transfer.fromAddress : transfer.toAddress
                let createdAt = transfer.timestamp ?? unknownTimestamp
                let nativeAsset = historyEvmNativeAsset(chainName: chainName) ?? EvmNativeAsset(assetName: "Ether", symbol: "ETH")
                let nativeAssetName = nativeAsset.assetName
                let nativeSymbol = nativeAsset.symbol
                syncedTransactions.append(
                    TransactionRecord(
                        walletID: wallet.id, kind: isOutgoing ? .send : .receive, status: .confirmed, walletName: wallet.name, assetName: nativeAssetName, symbol: nativeSymbol, chainName: chainName, amount: NSDecimalNumber(decimal: transfer.amount).doubleValue, address: counterparty, transactionHash: transfer.transactionHash, receiptBlockNumber: transfer.blockNumber, sourceAddress: walletSideAddress, transactionHistorySource: "etherscan", createdAt: createdAt
                    )
                )
            }}}
    guard !syncedTransactions.isEmpty else {
        if encounteredErrors {
            let hasCachedHistory = transactions.contains { transaction in
                guard transaction.chainName == chainName, let walletID = transaction.walletID else { return false }
                return refreshedWalletIDs.contains(walletID)
            }
            if hasCachedHistory { markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.") }}
        return
    }
    switch chain {
    case .ethereum, .ethereumSepolia, .ethereumHoodi: upsertEthereumTransactions(syncedTransactions)
    case .arbitrum: upsertArbitrumTransactions(syncedTransactions)
    case .optimism: upsertOptimismTransactions(syncedTransactions)
    case .bnb: upsertBNBTransactions(syncedTransactions)
    case .avalanche: upsertAvalancheTransactions(syncedTransactions)
    case .ethereumClassic: upsertETCTransactions(syncedTransactions)
    case .hyperliquid: upsertHyperliquidTransactions(syncedTransactions)
    }
    if encounteredErrors { markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.") } else { markChainHealthy(chainName) }
}
private func plannedEVMRefresh(chainName: String, walletSnapshot: [ImportedWallet], groupByNormalizedAddress: Bool, targetWalletIDs: Set<String>?) -> WalletRustEVMRefreshPlan? {
    let request = WalletRustEVMRefreshTargetsRequest(
        chainName: chainName,
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustEVMRefreshWalletInput(index: index, walletID: wallet.id, selectedChain: wallet.selectedChain, address: resolvedEVMAddress(for: wallet, chainName: chainName))
        },
        allowedWalletIDs: targetWalletIDs.map(Array.init),
        groupByNormalizedAddress: groupByNormalizedAddress
    )
    return try? WalletRustAppCoreBridge.planEVMRefreshTargets(request)
}
private func plannedEVMHistoryWallets(chainName: String, walletSnapshot: [ImportedWallet], targetWalletIDs: Set<String>?) -> [(ImportedWallet, String)]? {
    guard let plan = plannedEVMRefresh(chainName: chainName, walletSnapshot: walletSnapshot, groupByNormalizedAddress: false, targetWalletIDs: targetWalletIDs) else { return nil }
    return plan.walletTargets.compactMap { t in walletSnapshot.first(where: { $0.id == t.walletID }).map { ($0, t.address) } }
}
private func plannedEVMHistoryGroups(chainName: String, walletSnapshot: [ImportedWallet], loadMore: Bool, targetWalletIDs: Set<String>?) -> [([ImportedWallet], String, String)]? {
    guard let plan = plannedEVMRefresh(chainName: chainName, walletSnapshot: walletSnapshot, groupByNormalizedAddress: !loadMore, targetWalletIDs: targetWalletIDs) else { return nil }
    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id, $0) })
    return plan.groupedTargets.compactMap { t in
        let wallets = t.walletIDs.compactMap { walletByID[$0] }
        return wallets.isEmpty ? nil : (wallets, t.address, t.normalizedAddress)
    }
}
}

private func decodeEvmHistoryPageJSON(_ json: String) -> (
    tokens: [EthereumTokenTransferSnapshot], native: [EthereumNativeTransferSnapshot]
) {
    let decoded = historyDecodeEvmPage(json: json)
    let tokens = decoded.tokens.map { item in
        EthereumTokenTransferSnapshot(
            contractAddress: item.contractAddress, tokenName: item.tokenName, symbol: item.symbol,
            decimals: Int(item.decimals), fromAddress: item.fromAddress, toAddress: item.toAddress,
            amount: Decimal(string: item.amountDecimal) ?? 0,
            transactionHash: item.transactionHash, blockNumber: Int(item.blockNumber),
            logIndex: Int(item.logIndex),
            timestamp: item.timestamp > 0 ? Date(timeIntervalSince1970: item.timestamp) : nil
        )
    }
    let native = decoded.native.map { item in
        EthereumNativeTransferSnapshot(
            fromAddress: item.fromAddress, toAddress: item.toAddress,
            amount: Decimal(string: item.amountDecimal) ?? 0,
            transactionHash: item.transactionHash, blockNumber: Int(item.blockNumber),
            timestamp: item.timestamp > 0 ? Date(timeIntervalSince1970: item.timestamp) : nil
        )
    }
    return (tokens, native)
}
