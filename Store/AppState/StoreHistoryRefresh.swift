import Combine
import Foundation

// MARK: - Phase 2.3 History pagination helpers (delegates to Rust HistoryPaginationStore)
//
// Chain IDs mirror service.rs constants.  All writes call objectWillChange.send()
// so that SwiftUI views observing WalletStore re-render when pagination changes.

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

extension WalletStore {

    // MARK: Read

    func historyPaginationExhausted(chainId: UInt32, walletId: UUID) -> Bool {
        (try? WalletServiceBridge.shared.isHistoryExhausted(
            chainId: chainId, walletId: walletId.uuidString)) ?? false
    }

    func historyPaginationCursor(chainId: UInt32, walletId: UUID) -> String? {
        try? WalletServiceBridge.shared.historyNextCursor(
            chainId: chainId, walletId: walletId.uuidString)
    }

    /// Returns the stored page value (1-indexed for EVM chains, 0 if unset).
    func historyPaginationPage(chainId: UInt32, walletId: UUID) -> Int {
        Int((try? WalletServiceBridge.shared.historyNextPage(
            chainId: chainId, walletId: walletId.uuidString)) ?? 0)
    }

    // MARK: Write — cursor

    func setHistoryCursor(chainId: UInt32, walletId: UUID, cursor: String?) {
        try? WalletServiceBridge.shared.advanceHistoryCursor(
            chainId: chainId, walletId: walletId.uuidString, nextCursor: cursor)
        objectWillChange.send()
    }

    // MARK: Write — page

    func setHistoryPage(chainId: UInt32, walletId: UUID, page: Int) {
        try? WalletServiceBridge.shared.setHistoryPage(
            chainId: chainId, walletId: walletId.uuidString, page: UInt32(max(0, page)))
        objectWillChange.send()
    }

    // MARK: Write — exhaustion

    func markHistoryExhausted(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.setHistoryExhausted(
            chainId: chainId, walletId: walletId.uuidString, exhausted: true)
        objectWillChange.send()
    }

    func markHistoryActive(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.setHistoryExhausted(
            chainId: chainId, walletId: walletId.uuidString, exhausted: false)
        objectWillChange.send()
    }

    // MARK: Reset

    /// Clear cursor, page, and exhaustion for one (chain, wallet) pair.
    func resetHistoryPagination(chainId: UInt32, walletId: UUID) {
        try? WalletServiceBridge.shared.resetHistory(
            chainId: chainId, walletId: walletId.uuidString)
        objectWillChange.send()
    }

    /// Reset all chains for one wallet.
    func resetHistoryPaginationForWallet(_ walletId: UUID) {
        try? WalletServiceBridge.shared.resetHistoryForWallet(walletId: walletId.uuidString)
        objectWillChange.send()
    }

    /// Reset all history pagination state.
    func resetAllHistoryPagination() {
        try? WalletServiceBridge.shared.resetAllHistory()
        objectWillChange.send()
    }
}

extension WalletStore {
func canLoadMoreHistory(for walletID: UUID) -> Bool {
    guard let wallet = cachedWalletByID[walletID] else { return false }
    switch wallet.selectedChain {
    case "Bitcoin":
        return !historyPaginationExhausted(chainId: HistoryChainID.bitcoin, walletId: walletID)
    case "Bitcoin Cash":
        return !historyPaginationExhausted(chainId: HistoryChainID.bitcoinCash, walletId: walletID)
    case "Bitcoin SV":
        return !historyPaginationExhausted(chainId: HistoryChainID.bitcoinSV, walletId: walletID)
    case "Litecoin":
        return !historyPaginationExhausted(chainId: HistoryChainID.litecoin, walletId: walletID)
    case "Dogecoin":
        return !historyPaginationExhausted(chainId: HistoryChainID.dogecoin, walletId: walletID)
    case "Ethereum":
        return !historyPaginationExhausted(chainId: HistoryChainID.ethereum, walletId: walletID)
    case "Arbitrum":
        return !historyPaginationExhausted(chainId: HistoryChainID.arbitrum, walletId: walletID)
    case "Optimism":
        return !historyPaginationExhausted(chainId: HistoryChainID.optimism, walletId: walletID)
    case "BNB Chain":
        return !historyPaginationExhausted(chainId: HistoryChainID.bnb, walletId: walletID)
    case "Hyperliquid":
        return !historyPaginationExhausted(chainId: HistoryChainID.hyperliquid, walletId: walletID)
    case "Tron":
        return !historyPaginationExhausted(chainId: HistoryChainID.tron, walletId: walletID)
    default:
        return false
    }
}

func canLoadMoreOnChainHistory(for walletIDs: Set<UUID>) -> Bool {
    !isLoadingMoreOnChainHistory && walletIDs.contains(where: canLoadMoreHistory(for:))
}

// Pagination entry for history tab page stepping across chains that support fixed-size history pages.
// MARK: - History Pagination and Global Refresh
    func loadMoreOnChainHistory(for walletIDs: Set<UUID>) async {
        await WalletFetchLayer.loadMoreOnChainHistory(for: walletIDs, using: self)
    }

func fetchBitcoinHistoryPage(
    for wallet: ImportedWallet,
    limit: Int,
    cursor: String?
    ) async throws -> BitcoinHistoryPage {
    // Seed-phrase path: derive account xpub via Rust, then scan HD addresses.
    if cursor == nil,
       let seedPhrase = storedSeedPhrase(for: wallet.id),
       !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let pathParts = wallet.seedDerivationPaths.bitcoin.split(separator: "/")
        let accountPath = String(pathParts.prefix(4).joined(separator: "/"))
        if let xpub = try? await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
            mnemonicPhrase: seedPhrase,
            passphrase: "",
            accountPath: accountPath
        ) {
            let page = try await fetchBitcoinHDHistoryPage(xpub: xpub, limit: limit)
            if !page.snapshots.isEmpty { return page }
        }
    }

    // Single-address path (watch-only or imported address).
    if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
       !bitcoinAddress.isEmpty {
        let json = try await WalletServiceBridge.shared.fetchHistoryJSON(chainId: SpectraChainID.bitcoin, address: bitcoinAddress)
        return decodeBitcoinHistoryPageFromRust(json: json, limit: limit)
    }

    // xpub-only path: derive HD addresses via Rust and scan per-address.
    if let bitcoinXPub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines),
       !bitcoinXPub.isEmpty {
        return try await fetchBitcoinHDHistoryPage(xpub: bitcoinXPub, limit: limit)
    }

    throw URLError(.fileDoesNotExist)
}

private func fetchBitcoinHDHistoryPage(xpub: String, limit: Int) async throws -> BitcoinHistoryPage {
    struct HdAddr: Decodable { let address: String }
    async let receiveTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(
        xpub: xpub, change: 0, startIndex: 0, count: 20)
    async let changeTask = WalletServiceBridge.shared.deriveBitcoinHdAddressesJSON(
        xpub: xpub, change: 1, startIndex: 0, count: 10)
    let (receiveJSON, changeJSON) = try await (receiveTask, changeTask)
    let receiveAddrs = (try? JSONDecoder().decode([HdAddr].self, from: Data(receiveJSON.utf8)))?.map(\.address) ?? []
    let changeAddrs = (try? JSONDecoder().decode([HdAddr].self, from: Data(changeJSON.utf8)))?.map(\.address) ?? []
    let allAddresses = receiveAddrs + changeAddrs
    guard !allAddresses.isEmpty else {
        return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust.hd")
    }
    let indexedAddresses = Array(allAddresses.enumerated())
    let fetchedSnapshots = await collectLimitedConcurrentIndexedResults(from: indexedAddresses, maxConcurrent: 4) { entry in
        let (index, address) = entry
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.bitcoin, address: address
            )
            let entries = self.decodeRustHistoryJSON(json: json)
            let payloads = entries.compactMap { obj -> WalletRustBitcoinHistorySnapshotPayload? in
                guard let txid = obj["txid"] as? String else { return nil }
                let netSats = obj["net_sats"] as? Int ?? 0
                let confirmed = obj["confirmed"] as? Bool ?? false
                return WalletRustBitcoinHistorySnapshotPayload(
                    txid: txid,
                    amountBTC: Double(abs(netSats)) / 100_000_000,
                    kind: netSats >= 0 ? "receive" : "send",
                    status: confirmed ? "confirmed" : "pending",
                    counterpartyAddress: "",
                    blockHeight: obj["block_height"] as? Int,
                    createdAtUnix: obj["block_time"] as? Double ?? 0
                )
            }
            return (index, payloads)
        } catch {
            return (index, nil)
        }
    }
    let mergedSnapshots = try WalletRustAppCoreBridge.mergeBitcoinHistorySnapshots(
        WalletRustMergeBitcoinHistorySnapshotsRequest(
            snapshots: fetchedSnapshots.sorted { $0.key < $1.key }.flatMap(\.value),
            ownedAddresses: allAddresses,
            limit: limit
        )
    )
    return BitcoinHistoryPage(
        snapshots: mergedSnapshots.map { snapshot in
            BitcoinHistorySnapshot(
                txid: snapshot.txid,
                amountBTC: snapshot.amountBTC,
                kind: TransactionKind(rawValue: snapshot.kind) ?? .send,
                status: TransactionStatus(rawValue: snapshot.status) ?? .pending,
                counterpartyAddress: snapshot.counterpartyAddress,
                blockHeight: snapshot.blockHeight,
                createdAt: Date(timeIntervalSince1970: snapshot.createdAtUnix)
            )
        },
        nextCursor: nil,
        sourceUsed: "rust.hd"
    )
}
func decodeBitcoinHistoryPageFromRust(json: String, limit: Int) -> BitcoinHistoryPage {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return BitcoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "rust")
    }
    let snapshots: [BitcoinHistorySnapshot] = arr.prefix(limit).compactMap { obj in
        guard let txid = obj["txid"] as? String else { return nil }
        let netSats = (obj["net_sats"] as? Int) ?? 0
        let confirmed = (obj["confirmed"] as? Bool) ?? false
        let blockHeight = obj["block_height"] as? Int
        let blockTime = obj["block_time"] as? Double
        let amountBTC = Double(abs(netSats)) / 100_000_000.0
        let kind: TransactionKind = netSats >= 0 ? .receive : .send
        let status: TransactionStatus = confirmed ? .confirmed : .pending
        let createdAt = blockTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
        return BitcoinHistorySnapshot(
            txid: txid,
            amountBTC: amountBTC,
            kind: kind,
            status: status,
            counterpartyAddress: "",
            blockHeight: blockHeight,
            createdAt: createdAt
        )
    }
    let nextCursor = arr.count > limit ? arr[limit - 1]["txid"] as? String : nil
    return BitcoinHistoryPage(snapshots: snapshots, nextCursor: nextCursor, sourceUsed: "rust")
}

// MARK: - Rust history decode helpers

/// Map a Tron token symbol to a display asset name.
func tronAssetName(symbol: String) -> String {
    switch symbol {
    case "TRX": return "Tron"
    case "USDT": return "Tether USD"
    case "USDC": return "USD Coin"
    case "BTT": return "BitTorrent"
    default: return symbol
    }
}

/// Resolve a Solana mint address to a (symbol, assetName) pair using the token registry.
func solanaSymbolAndAssetName(
    mint: String,
    rawSymbol: String,
    tokenMeta: [String: SolanaBalanceService.KnownTokenMetadata]
) -> (String, String) {
    if mint.isEmpty {
        return ("SOL", "Solana")
    }
    if let meta = tokenMeta[mint] {
        return (meta.symbol, meta.name)
    }
    // Mint address not in registry — rawSymbol is the mint address from Rust.
    // Fall back to a short label derived from the mint.
    return (rawSymbol, rawSymbol)
}

/// Collect enabled Solana tracked tokens keyed by mint address.
/// `enabledSolanaTrackedTokens()` already returns a mint-keyed dict.
func enabledSolanaTrackedTokensByMint() -> [String: SolanaBalanceService.KnownTokenMetadata] {
    enabledSolanaTrackedTokens()
}

/// Generic JSON array decoder for Rust history responses.
func decodeRustHistoryJSON(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return arr
}

func refreshBitcoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let bitcoinWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Bitcoin" else { return false }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !bitcoinWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))

    if !loadMore {
        for walletID in Set(bitcoinWallets.map(\.id)) {
            resetHistoryPagination(chainId: HistoryChainID.bitcoin, walletId: walletID)
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in bitcoinWallets {
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.bitcoin, walletId: wallet.id) {
            continue
        }

        let cursor = loadMore ? historyPaginationCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id) : nil
        do {
            let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name

            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: page.nextCursor)

            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: page.sourceUsed,
                transactionCount: page.snapshots.count,
                nextCursor: page.nextCursor,
                error: nil
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()

            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: snapshot.kind,
                        status: snapshot.status,
                        walletName: wallet.name,
                        assetName: "Bitcoin",
                        symbol: "BTC",
                        chainName: "Bitcoin",
                        amount: snapshot.amountBTC,
                        address: snapshot.counterpartyAddress,
                        transactionHash: snapshot.txid,
                        receiptBlockNumber: snapshot.blockHeight,
                        transactionHistorySource: page.sourceUsed,
                        createdAt: snapshot.createdAt
                    )
                }
            )
        } catch {
            encounteredErrors = true
            setHistoryCursor(chainId: HistoryChainID.bitcoin, walletId: wallet.id, cursor: nil)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? ""
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: "none",
                transactionCount: 0,
                nextCursor: nil,
                error: error.localizedDescription
            )
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertBitcoinTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Bitcoin", detail: "Bitcoin history loaded with partial provider failures.")
        } else {
            markChainHealthy("Bitcoin")
        }
    } else if encounteredErrors {
        markChainDegraded("Bitcoin", detail: "Bitcoin history refresh failed. Using cached history.")
    }
}

} // end extension WalletStore (Bitcoin history)

// MARK: - Generic simple-chain history (one fungible asset per chain, Rust-backed)

private struct SimpleChainHistoryDescriptor {
    let chainName: String
    let chainId: UInt32
    let historyChainId: UInt32   // UInt32.max = no cursor-based pagination
    let assetName: String
    let symbol: String
    let historySource: String
    let resolveAddress: (WalletStore, ImportedWallet) -> String?
    /// Returns (amount, counterparty, txhash, blockHeight, timestampSec, isIncoming, isConfirmed) or nil to skip.
    let parseEntry: ([String: Any]) -> (amount: Double, counterparty: String, txhash: String,
                                        blockHeight: Int?, timestamp: Double,
                                        isIncoming: Bool, isConfirmed: Bool)?
    let upsert: (WalletStore, [TransactionRecord]) -> Void
}

// Module-level table — closures receive WalletStore explicitly so no self capture.
private let _simpleChainDescriptors: [SimpleChainHistoryDescriptor] = {
    let isoParser = ISO8601DateFormatter()
    return [
        // Bitcoin Cash — amount_sat / 1e8
        SimpleChainHistoryDescriptor(
            chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash,
            historyChainId: HistoryChainID.bitcoinCash,
            assetName: "Bitcoin Cash", symbol: "BCH", historySource: "rust",
            resolveAddress: { s, w in s.resolvedBitcoinCashAddress(for: w) },
            parseEntry: { e in
                guard let txid = e["txid"] as? String else { return nil }
                let sat = (e["amount_sat"] as? Int) ?? 0
                let bh = e["block_height"] as? Int
                return (Double(abs(sat)) / 1e8, "", txid, bh,
                        (e["timestamp"] as? Double) ?? 0,
                        (e["is_incoming"] as? Bool) ?? (sat >= 0), (bh ?? 0) > 0)
            },
            upsert: { s, r in s.upsertBitcoinCashTransactions(r) }
        ),
        // Bitcoin SV — amount_sat / 1e8
        SimpleChainHistoryDescriptor(
            chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv,
            historyChainId: HistoryChainID.bitcoinSV,
            assetName: "Bitcoin SV", symbol: "BSV", historySource: "rust",
            resolveAddress: { s, w in s.resolvedBitcoinSVAddress(for: w) },
            parseEntry: { e in
                guard let txid = e["txid"] as? String else { return nil }
                let sat = (e["amount_sat"] as? Int) ?? 0
                let bh = e["block_height"] as? Int
                return (Double(abs(sat)) / 1e8, "", txid, bh,
                        (e["timestamp"] as? Double) ?? 0,
                        (e["is_incoming"] as? Bool) ?? (sat >= 0), (bh ?? 0) > 0)
            },
            upsert: { s, r in s.upsertBitcoinSVTransactions(r) }
        ),
        // Litecoin — amount_sat / 1e8
        SimpleChainHistoryDescriptor(
            chainName: "Litecoin", chainId: SpectraChainID.litecoin,
            historyChainId: HistoryChainID.litecoin,
            assetName: "Litecoin", symbol: "LTC", historySource: "rust",
            resolveAddress: { s, w in s.resolvedLitecoinAddress(for: w) },
            parseEntry: { e in
                guard let txid = e["txid"] as? String else { return nil }
                let sat = (e["amount_sat"] as? Int) ?? 0
                let bh = e["block_height"] as? Int
                return (Double(abs(sat)) / 1e8, "", txid, bh,
                        (e["timestamp"] as? Double) ?? 0,
                        (e["is_incoming"] as? Bool) ?? (sat >= 0), (bh ?? 0) > 0)
            },
            upsert: { s, r in s.upsertLitecoinTransactions(r) }
        ),
        // Cardano — amount_lovelace / 1e6
        SimpleChainHistoryDescriptor(
            chainName: "Cardano", chainId: SpectraChainID.cardano,
            historyChainId: UInt32.max,
            assetName: "Cardano", symbol: "ADA", historySource: "blockfrost",
            resolveAddress: { s, w in s.resolvedCardanoAddress(for: w) },
            parseEntry: { e in
                let lovelace = (e["amount_lovelace"] as? Int) ?? 0
                return (Double(abs(lovelace)) / 1_000_000, "",
                        e["txid"] as? String ?? "", nil,
                        (e["block_time"] as? Double) ?? 0,
                        (e["is_incoming"] as? Bool) ?? false, true)
            },
            upsert: { s, r in s.upsertCardanoTransactions(r) }
        ),
        // XRP — amount_drops / 1e6
        SimpleChainHistoryDescriptor(
            chainName: "XRP Ledger", chainId: SpectraChainID.xrp,
            historyChainId: UInt32.max,
            assetName: "XRP", symbol: "XRP", historySource: "xrpscan",
            resolveAddress: { s, w in s.resolvedXRPAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let drops = (e["amount_drops"] as? Int) ?? 0
                return (Double(drops) / 1_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil,
                        (e["timestamp"] as? Double) ?? 0, isIncoming, true)
            },
            upsert: { s, r in s.upsertXRPTransactions(r) }
        ),
        // Stellar — amount_stroops / 1e7, ISO8601 timestamp
        SimpleChainHistoryDescriptor(
            chainName: "Stellar", chainId: SpectraChainID.stellar,
            historyChainId: UInt32.max,
            assetName: "Stellar Lumens", symbol: "XLM", historySource: "horizon",
            resolveAddress: { s, w in s.resolvedStellarAddress(for: w) },
            parseEntry: { [isoParser] e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let stroops = (e["amount_stroops"] as? Int) ?? 0
                let ts: Double
                if let str = e["timestamp"] as? String {
                    ts = isoParser.date(from: str)?.timeIntervalSince1970 ?? 0
                } else {
                    ts = (e["timestamp"] as? Double) ?? 0
                }
                return (Double(abs(stroops)) / 10_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil, ts, isIncoming, true)
            },
            upsert: { s, r in s.upsertStellarTransactions(r) }
        ),
        // Monero — amount_piconeros / 1e12
        SimpleChainHistoryDescriptor(
            chainName: "Monero", chainId: SpectraChainID.monero,
            historyChainId: UInt32.max,
            assetName: "Monero", symbol: "XMR", historySource: "monero-rpc",
            resolveAddress: { s, w in s.resolvedMoneroAddress(for: w) },
            parseEntry: { e in
                let piconeros = (e["amount_piconeros"] as? Double) ?? 0
                return (piconeros / 1_000_000_000_000, "",
                        e["txid"] as? String ?? "", nil,
                        (e["timestamp"] as? Double) ?? 0,
                        (e["is_incoming"] as? Bool) ?? false, true)
            },
            upsert: { s, r in s.upsertMoneroTransactions(r) }
        ),
        // Sui — amount_mist / 1e9, timestamp_ms / 1000, digest as txhash
        SimpleChainHistoryDescriptor(
            chainName: "Sui", chainId: SpectraChainID.sui,
            historyChainId: UInt32.max,
            assetName: "Sui", symbol: "SUI", historySource: "sui-rpc",
            resolveAddress: { s, w in s.resolvedSuiAddress(for: w) },
            parseEntry: { e in
                let mist = (e["amount_mist"] as? Double) ?? 0
                let tsMs = (e["timestamp_ms"] as? Double) ?? 0
                return (mist / 1_000_000_000, "",
                        e["digest"] as? String ?? "", nil,
                        tsMs / 1000, (e["is_incoming"] as? Bool) ?? false, true)
            },
            upsert: { s, r in s.upsertSuiTransactions(r) }
        ),
        // Internet Computer — amount_e8s / 1e8, timestamp_ns / 1e9, block_index as txhash
        SimpleChainHistoryDescriptor(
            chainName: "Internet Computer", chainId: SpectraChainID.icp,
            historyChainId: UInt32.max,
            assetName: "Internet Computer", symbol: "ICP", historySource: "rosetta",
            resolveAddress: { s, w in s.resolvedICPAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let e8s = (e["amount_e8s"] as? Double) ?? 0
                let blockIndex = (e["block_index"] as? Int) ?? 0
                let tsNs = (e["timestamp_ns"] as? Double) ?? 0
                return (e8s / 100_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        String(blockIndex), nil, tsNs / 1_000_000_000, isIncoming, true)
            },
            upsert: { s, r in s.upsertICPTransactions(r) }
        ),
        // Aptos — amount_octas / 1e8, timestamp_us / 1e6
        SimpleChainHistoryDescriptor(
            chainName: "Aptos", chainId: SpectraChainID.aptos,
            historyChainId: UInt32.max,
            assetName: "Aptos", symbol: "APT", historySource: "aptos-rpc",
            resolveAddress: { s, w in s.resolvedAptosAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let octas = (e["amount_octas"] as? Double) ?? 0
                let tsUs = (e["timestamp_us"] as? Double) ?? 0
                return (octas / 100_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil, tsUs / 1_000_000, isIncoming, true)
            },
            upsert: { s, r in s.upsertAptosTransactions(r) }
        ),
        // TON — amount_nanotons / 1e9
        SimpleChainHistoryDescriptor(
            chainName: "TON", chainId: SpectraChainID.ton,
            historyChainId: UInt32.max,
            assetName: "Toncoin", symbol: "TON", historySource: "tonapi",
            resolveAddress: { s, w in s.resolvedTONAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let nanotons = (e["amount_nanotons"] as? Double) ?? 0
                return (nanotons / 1_000_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil,
                        (e["timestamp"] as? Double) ?? 0, isIncoming, true)
            },
            upsert: { s, r in s.upsertTONTransactions(r) }
        ),
        // NEAR — amount_yocto (String) / 1e24, timestamp_ns / 1e9
        SimpleChainHistoryDescriptor(
            chainName: "NEAR", chainId: SpectraChainID.near,
            historyChainId: UInt32.max,
            assetName: "NEAR Protocol", symbol: "NEAR", historySource: "near-rpc",
            resolveAddress: { s, w in s.resolvedNearAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let yoctoStr = e["amount_yocto"] as? String ?? "0"
                let tsNs = (e["timestamp_ns"] as? Double) ?? 0
                return ((Double(yoctoStr) ?? 0) / 1e24,
                        isIncoming ? (e["signer_id"] as? String ?? "") : (e["receiver_id"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil, tsNs / 1_000_000_000, isIncoming, true)
            },
            upsert: { s, r in s.upsertNearTransactions(r) }
        ),
        // Polkadot — amount_planck / 1e10
        SimpleChainHistoryDescriptor(
            chainName: "Polkadot", chainId: SpectraChainID.polkadot,
            historyChainId: UInt32.max,
            assetName: "Polkadot", symbol: "DOT", historySource: "subscan",
            resolveAddress: { s, w in s.resolvedPolkadotAddress(for: w) },
            parseEntry: { e in
                let isIncoming = (e["is_incoming"] as? Bool) ?? false
                let planck = (e["amount_planck"] as? Double) ?? 0
                return (planck / 10_000_000_000,
                        isIncoming ? (e["from"] as? String ?? "") : (e["to"] as? String ?? ""),
                        e["txid"] as? String ?? "", nil,
                        (e["timestamp"] as? Double) ?? 0, isIncoming, true)
            },
            upsert: { s, r in s.upsertPolkadotTransactions(r) }
        ),
    ]
}()

extension WalletStore {

/// Generic refresh for any chain where Rust returns a flat JSON array of single-asset transfers.
private func refreshSimpleChainTransactions(
    descriptor d: SimpleChainHistoryDescriptor,
    limit: Int? = nil,
    loadMore: Bool = false,
    targetWalletIDs: Set<UUID>? = nil
) async {
    let walletSnapshot = wallets
    let filteredWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == d.chainName,
              d.resolveAddress(self, wallet) != nil else { return false }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !filteredWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))
    let usesPagination = d.historyChainId != UInt32.max

    if !loadMore && usesPagination {
        for walletID in Set(filteredWallets.map(\.id)) {
            resetHistoryPagination(chainId: d.historyChainId, walletId: walletID)
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in filteredWallets {
        if usesPagination && loadMore && historyPaginationExhausted(chainId: d.historyChainId, walletId: wallet.id) {
            continue
        }
        guard let address = d.resolveAddress(self, wallet) else { continue }
        if usesPagination && loadMore && historyPaginationCursor(chainId: d.historyChainId, walletId: wallet.id) == nil {
            markHistoryExhausted(chainId: d.historyChainId, walletId: wallet.id)
            continue
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(chainId: d.chainId, address: address)
            if usesPagination { markHistoryExhausted(chainId: d.historyChainId, walletId: wallet.id) }
            let records = decodeRustHistoryJSON(json: json).prefix(requestedLimit).compactMap { entry -> TransactionRecord? in
                guard let parsed = d.parseEntry(entry) else { return nil }
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: parsed.isIncoming ? .receive : .send,
                    status: parsed.isConfirmed ? .confirmed : .pending,
                    walletName: wallet.name,
                    assetName: d.assetName,
                    symbol: d.symbol,
                    chainName: d.chainName,
                    amount: parsed.amount,
                    address: parsed.counterparty,
                    transactionHash: parsed.txhash,
                    receiptBlockNumber: parsed.blockHeight,
                    transactionHistorySource: d.historySource,
                    createdAt: parsed.timestamp > 0 ? Date(timeIntervalSince1970: parsed.timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
            if usesPagination { markHistoryExhausted(chainId: d.historyChainId, walletId: wallet.id) }
        }
    }

    if !discoveredTransactions.isEmpty {
        d.upsert(self, discoveredTransactions)
        if encounteredErrors {
            markChainDegraded(d.chainName, detail: "\(d.chainName) history loaded with partial provider failures.")
        } else {
            markChainHealthy(d.chainName)
        }
    } else if encounteredErrors {
        markChainDegraded(d.chainName, detail: "\(d.chainName) history refresh failed. Using cached history.")
    }
}

// MARK: - Per-chain refresh wrappers (delegates to generic engine)

func refreshBitcoinCashTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[0], limit: limit, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
}

func refreshBitcoinSVTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[1], limit: limit, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
}

func refreshLitecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[2], limit: limit, loadMore: loadMore, targetWalletIDs: targetWalletIDs)
}

func refreshTronTransactions(loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let tronWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Tron",
              resolvedTronAddress(for: wallet) != nil else {
            return false
        }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !tronWallets.isEmpty else { return }

    if !loadMore {
        for walletID in Set(tronWallets.map(\.id)) {
            resetHistoryPagination(chainId: HistoryChainID.tron, walletId: walletID)
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in tronWallets {
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.tron, walletId: wallet.id) {
            continue
        }
        guard let tronAddress = resolvedTronAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.tron, address: tronAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            if entries.isEmpty {
                markHistoryExhausted(chainId: HistoryChainID.tron, walletId: wallet.id)
            } else {
                markHistoryActive(chainId: HistoryChainID.tron, walletId: wallet.id)
            }
            let records = entries.map { entry -> TransactionRecord in
                let symbol = entry["symbol"] as? String ?? "TRX"
                let amount = Double(entry["amount_display"] as? String ?? "0") ?? 0
                let isIncoming = (entry["is_incoming"] as? Bool) ?? false
                let timestampMs = (entry["timestamp_ms"] as? Double) ?? 0
                let txid = entry["txid"] as? String ?? ""
                let counterparty = isIncoming ? (entry["from"] as? String ?? "") : (entry["to"] as? String ?? "")
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: tronAssetName(symbol: symbol),
                    symbol: symbol,
                    chainName: "Tron",
                    amount: amount,
                    address: counterparty,
                    transactionHash: txid,
                    transactionHistorySource: "tronscan",
                    createdAt: timestampMs > 0 ? Date(timeIntervalSince1970: timestampMs / 1000) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertTronTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Tron", detail: "Tron history loaded with partial provider failures.")
        } else {
            markChainHealthy("Tron")
        }
    } else if encounteredErrors {
        markChainDegraded("Tron", detail: "Tron history refresh failed. Using cached history.")
    }
}

func refreshSolanaTransactions(loadMore: Bool = false) async {
    let walletSnapshot = wallets
    let solanaWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Solana" && resolvedSolanaAddress(for: wallet) != nil
    }
    guard !solanaWallets.isEmpty else { return }
    let refreshedWalletIDs = Set(solanaWallets.map(\.id))

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in solanaWallets {
        guard let solanaAddress = resolvedSolanaAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.solana, address: solanaAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let tokenMeta = enabledSolanaTrackedTokensByMint()
            let records = entries.compactMap { entry -> TransactionRecord? in
                let symbol = entry["symbol"] as? String ?? "SOL"
                let mint = entry["mint"] as? String ?? ""
                let isIncoming = (entry["is_incoming"] as? Bool) ?? false
                let amountDisplay = entry["amount_display"] as? String ?? "0"
                let amount = Double(amountDisplay) ?? 0
                let timestampSec = (entry["timestamp"] as? Double) ?? 0
                let sig = entry["signature"] as? String ?? ""
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                let (resolvedSymbol, assetName) = solanaSymbolAndAssetName(
                    mint: mint, rawSymbol: symbol, tokenMeta: tokenMeta
                )
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: assetName,
                    symbol: resolvedSymbol,
                    chainName: "Solana",
                    amount: amount,
                    address: counterparty,
                    transactionHash: sig,
                    transactionHistorySource: "solana-rpc",
                    createdAt: timestampSec > 0 ? Date(timeIntervalSince1970: timestampSec) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertSolanaTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Solana", detail: "Solana history loaded with partial provider failures.")
        } else {
            markChainHealthy("Solana")
        }
    } else if encounteredErrors {
        let hasCachedHistory = transactions.contains { transaction in
            guard transaction.chainName == "Solana",
                  let walletID = transaction.walletID else {
                return false
            }
            return refreshedWalletIDs.contains(walletID)
        }
        if hasCachedHistory {
            markChainDegraded("Solana", detail: "Solana history refresh failed. Using cached history.")
        }
    }
}

func refreshCardanoTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[3], loadMore: loadMore)
}

func refreshXRPTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[4], loadMore: loadMore)
}

func refreshStellarTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[5], loadMore: loadMore)
}

func refreshMoneroTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[6], loadMore: loadMore)
}

func refreshSuiTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[7], loadMore: loadMore)
}

func refreshICPTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[8], loadMore: loadMore)
}

func refreshAptosTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[9], loadMore: loadMore)
}

func refreshTONTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[10], loadMore: loadMore)
}

func refreshNearTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[11], loadMore: loadMore)
}

func refreshPolkadotTransactions(loadMore: Bool = false) async {
    await refreshSimpleChainTransactions(descriptor: _simpleChainDescriptors[12], loadMore: loadMore)
}

func refreshEVMTokenTransactions(
    chainName: String,
    maxResults: Int? = nil,
    loadMore: Bool = false,
    targetWalletIDs: Set<UUID>? = nil
) async {
    guard let chain = evmChainContext(for: chainName) else { return }
    let walletSnapshot = wallets
    let walletsToRefresh = plannedEVMHistoryWallets(
        chainName: chainName,
        walletSnapshot: walletSnapshot,
        targetWalletIDs: targetWalletIDs
    ) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, String)? in
        guard wallet.selectedChain == chainName,
              let address = resolvedEVMAddress(for: wallet, chainName: chainName) else {
            return nil
        }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) {
            return nil
        }
        return (wallet, address)
    }

    guard !walletsToRefresh.isEmpty else { return }
    let refreshedWalletIDs = Set(walletsToRefresh.map { $0.0.id })
    let historyTargets: [([ImportedWallet], String, String)] = plannedEVMHistoryGroups(
        chainName: chainName,
        walletSnapshot: walletSnapshot,
        loadMore: loadMore,
        targetWalletIDs: targetWalletIDs
    ) ?? {
        if loadMore {
            return walletsToRefresh.map { ([$0.0], $0.1, normalizeEVMAddress($0.1)) }
        }
        return Dictionary(grouping: walletsToRefresh) {
            normalizeEVMAddress($0.1)
        }
        .values
        .compactMap { group in
            guard let first = group.first else { return nil }
            return (group.map(\.0), first.1, normalizeEVMAddress(first.1))
        }
    }()

    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    let unknownTimestamp = Date.distantPast
    let requestedPageSize = max(20, min(maxResults ?? HistoryPaging.endpointBatchSize, 500))
    if !loadMore {
        let walletIDs = Set(walletsToRefresh.map { $0.0.id })
        let evmChainId: UInt32 = chain.isEthereumFamily ? HistoryChainID.ethereum
            : chain == .arbitrum ? HistoryChainID.arbitrum
            : chain == .optimism ? HistoryChainID.optimism
            : chain == .hyperliquid ? HistoryChainID.hyperliquid
            : HistoryChainID.bnb
        for walletID in walletIDs {
            resetHistoryPagination(chainId: evmChainId, walletId: walletID)
            setHistoryPage(chainId: evmChainId, walletId: walletID, page: 1)
        }
    }
    let evmChainId: UInt32 = chain.isEthereumFamily ? HistoryChainID.ethereum
        : chain == .arbitrum ? HistoryChainID.arbitrum
        : chain == .optimism ? HistoryChainID.optimism
        : chain == .hyperliquid ? HistoryChainID.hyperliquid
        : HistoryChainID.bnb
    for (targetWallets, _, normalizedAddress) in historyTargets {
        guard let representativeWallet = targetWallets.first else { continue }
        if loadMore && historyPaginationExhausted(chainId: evmChainId, walletId: representativeWallet.id) { continue }
        let currentPage = max(1, historyPaginationPage(chainId: evmChainId, walletId: representativeWallet.id))
        let page = loadMore ? (currentPage + 1) : currentPage
        let trackedTokens: [EthereumSupportedToken]? = if chain.isEthereumMainnet {
            enabledEthereumTrackedTokens()
        } else if chain == .arbitrum {
            enabledArbitrumTrackedTokens()
        } else if chain == .optimism {
            enabledOptimismTrackedTokens()
        } else if chain == .hyperliquid {
            enabledHyperliquidTrackedTokens()
        } else if chain == .bnb {
            enabledBNBTrackedTokens()
        } else {
            nil
        }

        var tokenHistory: [EthereumTokenTransferSnapshot] = []
        var tokenDiagnostics: EthereumTokenTransferHistoryDiagnostics?
        var tokenHistoryError: Error?
        var nativeTransfers: [EthereumNativeTransferSnapshot] = []

        // Fetch both native and token transfers via Rust for all Etherscan-indexed EVM chains.
        guard let chainId = SpectraChainID.id(for: chainName) else {
            encounteredErrors = true
            continue
        }
        let tokenTuples: [(contract: String, symbol: String, name: String, decimals: Int)] =
            (trackedTokens ?? []).map { ($0.contractAddress, $0.symbol, $0.name, $0.decimals) }
        do {
            let json = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(
                chainId: chainId,
                address: normalizedAddress,
                tokens: tokenTuples,
                page: page,
                pageSize: requestedPageSize
            )
            let (decodedToken, decodedNative) = decodeEvmHistoryPageJSON(json)
            tokenHistory = decodedToken
            nativeTransfers = decodedNative
            tokenDiagnostics = EthereumTokenTransferHistoryDiagnostics(
                address: normalizedAddress,
                rpcTransferCount: 0, rpcError: nil,
                blockscoutTransferCount: 0, blockscoutError: nil,
                etherscanTransferCount: decodedToken.count, etherscanError: nil,
                ethplorerTransferCount: 0, ethplorerError: nil,
                sourceUsed: "rust/etherscan"
            )
        } catch {
            tokenHistoryError = error
            encounteredErrors = true
        }

        if chain.isEthereumFamily {
            if let tokenDiagnostics {
                for wallet in targetWallets {
                    ethereumHistoryDiagnosticsByWallet[wallet.id] = tokenDiagnostics
                }
            } else if let tokenHistoryError {
                for wallet in targetWallets {
                    ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                        address: normalizedAddress,
                        rpcTransferCount: 0,
                        rpcError: tokenHistoryError.localizedDescription,
                        blockscoutTransferCount: 0,
                        blockscoutError: nil,
                        etherscanTransferCount: 0,
                        etherscanError: nil,
                        ethplorerTransferCount: 0,
                        ethplorerError: nil,
                        sourceUsed: "none"
                    )
                }
            }
            ethereumHistoryDiagnosticsLastUpdatedAt = Date()
        } else if chain == .arbitrum {
            if let tokenDiagnostics {
                for wallet in targetWallets {
                    arbitrumHistoryDiagnosticsByWallet[wallet.id] = tokenDiagnostics
                }
            } else if let tokenHistoryError {
                for wallet in targetWallets {
                    arbitrumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                        address: normalizedAddress,
                        rpcTransferCount: 0,
                        rpcError: tokenHistoryError.localizedDescription,
                        blockscoutTransferCount: 0,
                        blockscoutError: nil,
                        etherscanTransferCount: 0,
                        etherscanError: nil,
                        ethplorerTransferCount: 0,
                        ethplorerError: nil,
                        sourceUsed: "none"
                    )
                }
            }
            arbitrumHistoryDiagnosticsLastUpdatedAt = Date()
        } else if chain == .optimism {
            if let tokenDiagnostics {
                for wallet in targetWallets {
                    optimismHistoryDiagnosticsByWallet[wallet.id] = tokenDiagnostics
                }
            } else if let tokenHistoryError {
                for wallet in targetWallets {
                    optimismHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                        address: normalizedAddress,
                        rpcTransferCount: 0,
                        rpcError: tokenHistoryError.localizedDescription,
                        blockscoutTransferCount: 0,
                        blockscoutError: nil,
                        etherscanTransferCount: 0,
                        etherscanError: nil,
                        ethplorerTransferCount: 0,
                        ethplorerError: nil,
                        sourceUsed: "none"
                    )
                }
            }
            optimismHistoryDiagnosticsLastUpdatedAt = Date()
        }

        let isLastPage = tokenHistory.count < requestedPageSize && nativeTransfers.count < requestedPageSize
        for wallet in targetWallets {
            if isLastPage {
                markHistoryExhausted(chainId: evmChainId, walletId: wallet.id)
            } else {
                markHistoryActive(chainId: evmChainId, walletId: wallet.id)
            }
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
                        walletID: wallet.id,
                        kind: isOutgoing ? .send : .receive,
                        status: .confirmed,
                        walletName: wallet.name,
                        assetName: transfer.tokenName,
                        symbol: transfer.symbol,
                        chainName: chainName,
                        amount: NSDecimalNumber(decimal: transfer.amount).doubleValue,
                        address: counterparty,
                        transactionHash: transfer.transactionHash,
                        receiptBlockNumber: transfer.blockNumber,
                        sourceAddress: walletSideAddress,
                        transactionHistorySource: tokenDiagnostics?.sourceUsed ?? "none",
                        createdAt: createdAt
                    )
                )
            }
        }
        for wallet in targetWallets {
            for transfer in nativeTransfers {
                let isOutgoing = transfer.fromAddress == normalizedAddress
                let isIncoming = transfer.toAddress == normalizedAddress
                guard isOutgoing || isIncoming else { continue }

                let counterparty = isOutgoing ? transfer.toAddress : transfer.fromAddress
                let walletSideAddress = isOutgoing ? transfer.fromAddress : transfer.toAddress
                let createdAt = transfer.timestamp ?? unknownTimestamp
                let nativeAssetName: String
                let nativeSymbol: String
                switch chain {
                case .ethereum, .ethereumSepolia, .ethereumHoodi:
                    nativeAssetName = "Ether"
                    nativeSymbol = "ETH"
                case .arbitrum:
                    nativeAssetName = "Ether"
                    nativeSymbol = "ETH"
                case .optimism:
                    nativeAssetName = "Ether"
                    nativeSymbol = "ETH"
                case .avalanche:
                    nativeAssetName = "Avalanche"
                    nativeSymbol = "AVAX"
                case .bnb:
                    nativeAssetName = "BNB"
                    nativeSymbol = "BNB"
                case .ethereumClassic:
                    nativeAssetName = "Ethereum Classic"
                    nativeSymbol = "ETC"
                case .hyperliquid:
                    nativeAssetName = "Hyperliquid"
                    nativeSymbol = "HYPE"
                }
                syncedTransactions.append(
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: isOutgoing ? .send : .receive,
                        status: .confirmed,
                        walletName: wallet.name,
                        assetName: nativeAssetName,
                        symbol: nativeSymbol,
                        chainName: chainName,
                        amount: NSDecimalNumber(decimal: transfer.amount).doubleValue,
                        address: counterparty,
                        transactionHash: transfer.transactionHash,
                        receiptBlockNumber: transfer.blockNumber,
                        sourceAddress: walletSideAddress,
                        transactionHistorySource: "etherscan",
                        createdAt: createdAt
                    )
                )
            }
        }
    }

    guard !syncedTransactions.isEmpty else {
        if encounteredErrors {
            let hasCachedHistory = transactions.contains { transaction in
                guard transaction.chainName == chainName,
                      let walletID = transaction.walletID else {
                    return false
                }
                return refreshedWalletIDs.contains(walletID)
            }
            if hasCachedHistory {
                markChainDegraded(chainName, detail: "\(chainName) history refresh failed. Using cached history.")
            }
        }
        return
    }
    switch chain {
    case .ethereum, .ethereumSepolia, .ethereumHoodi:
        upsertEthereumTransactions(syncedTransactions)
    case .arbitrum:
        upsertArbitrumTransactions(syncedTransactions)
    case .optimism:
        upsertOptimismTransactions(syncedTransactions)
    case .bnb:
        upsertBNBTransactions(syncedTransactions)
    case .avalanche:
        upsertAvalancheTransactions(syncedTransactions)
    case .ethereumClassic:
        upsertETCTransactions(syncedTransactions)
    case .hyperliquid:
        upsertHyperliquidTransactions(syncedTransactions)
    }
    if encounteredErrors {
        markChainDegraded(chainName, detail: "\(chainName) history loaded with partial provider failures.")
    } else {
        markChainHealthy(chainName)
    }
}

func refreshDogecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let walletsToRefresh = plannedDogecoinHistoryWallets(
        walletSnapshot: walletSnapshot,
        targetWalletIDs: targetWalletIDs
    ) ?? walletSnapshot.compactMap { wallet -> (ImportedWallet, [String])? in
        guard wallet.selectedChain == "Dogecoin",
              !knownDogecoinAddresses(for: wallet).isEmpty else {
            return nil
        }
        if let targetWalletIDs, !targetWalletIDs.contains(wallet.id) {
            return nil
        }
        return (wallet, knownDogecoinAddresses(for: wallet))
    }

    guard !walletsToRefresh.isEmpty else { return }

    let fetchLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 200))
    if !loadMore {
        for walletID in Set(walletsToRefresh.map { $0.0.id }) {
            resetHistoryPagination(chainId: HistoryChainID.dogecoin, walletId: walletID)
        }
    }
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for (wallet, dogecoinAddresses) in walletsToRefresh {
        let ownAddressSet = Set(dogecoinAddresses.map { $0.lowercased() })
        var snapshotsByHash: [String: [DogecoinBalanceService.AddressTransactionSnapshot]] = [:]
        if loadMore && historyPaginationExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id) {
            continue
        }

        for dogecoinAddress in dogecoinAddresses {
            do {
                let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.dogecoin, address: dogecoinAddress
                )
                let entries = decodeRustHistoryJSON(json: json)
                for entry in entries {
                    guard let txid = entry["txid"] as? String else { continue }
                    let amountKoin = (entry["amount_koin"] as? Int) ?? 0
                    let blockHeight = entry["block_height"] as? Int
                    let timestamp = (entry["timestamp"] as? Double) ?? 0
                    let isIncoming = (entry["is_incoming"] as? Bool) ?? (amountKoin >= 0)
                    snapshotsByHash[txid, default: []].append(
                        DogecoinBalanceService.AddressTransactionSnapshot(
                            hash: txid,
                            kind: isIncoming ? .receive : .send,
                            status: (blockHeight ?? 0) > 0 ? .confirmed : .pending,
                            amount: Double(abs(amountKoin)) / 1e8,
                            counterpartyAddress: "",
                            createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date.distantPast,
                            blockNumber: blockHeight
                        )
                    )
                }
                // Rust returns flat list — always exhaust after first page.
                markHistoryExhausted(chainId: HistoryChainID.dogecoin, walletId: wallet.id)
            } catch {
                encounteredErrors = true
                continue
            }
        }

        guard !snapshotsByHash.isEmpty else { continue }

        let mapped: [TransactionRecord] = snapshotsByHash.values.compactMap { groupedSnapshots -> TransactionRecord? in
            guard let first = groupedSnapshots.first else { return nil }

            let signedAmount = groupedSnapshots.reduce(0.0) { partialResult, snapshot in
                partialResult + (snapshot.kind == .receive ? snapshot.amount : -snapshot.amount)
            }
            guard abs(signedAmount) > 0 else { return nil }

            let effectiveKind: TransactionKind = signedAmount > 0 ? .receive : .send
            let effectiveAmount = abs(signedAmount)
            let effectiveStatus: TransactionStatus = groupedSnapshots.contains(where: { $0.status == .pending }) ? .pending : .confirmed
            let effectiveBlockNumber = groupedSnapshots.compactMap(\.blockNumber).max()
            let knownDates = groupedSnapshots.map(\.createdAt).filter { $0 != Date.distantPast }
            let effectiveCreatedAt = knownDates.min() ?? first.createdAt

            let preferredCounterparty = groupedSnapshots
                .map(\.counterpartyAddress)
                .first(where: { !ownAddressSet.contains($0.lowercased()) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                ?? first.counterpartyAddress

            return TransactionRecord(
                walletID: wallet.id,
                kind: effectiveKind,
                status: effectiveStatus,
                walletName: wallet.name,
                assetName: "Dogecoin",
                symbol: "DOGE",
                chainName: "Dogecoin",
                amount: effectiveAmount,
                address: preferredCounterparty,
                transactionHash: first.hash,
                receiptBlockNumber: effectiveBlockNumber,
                receiptGasUsed: nil,
                receiptEffectiveGasPriceGwei: nil,
                receiptNetworkFeeETH: nil,
                failureReason: nil,
                transactionHistorySource: "dogecoin.providers",
                createdAt: effectiveCreatedAt
            )
        }

        syncedTransactions.append(contentsOf: mapped)
    }

    guard !syncedTransactions.isEmpty else {
        if encounteredErrors {
                markChainDegraded("Dogecoin", detail: "Dogecoin history refresh failed. Using cached history.")
        }
        return
    }
    upsertDogecoinTransactions(syncedTransactions)
    if encounteredErrors {
        markChainDegraded("Dogecoin", detail: "Dogecoin history loaded with partial provider failures.")
    } else {
        markChainHealthy("Dogecoin")
    }
}

private func plannedEVMHistoryWallets(
    chainName: String,
    walletSnapshot: [ImportedWallet],
    targetWalletIDs: Set<UUID>?
) -> [(ImportedWallet, String)]? {
    let allowedWalletIDs = targetWalletIDs?.map(\.uuidString)
    let request = WalletRustEVMRefreshTargetsRequest(
        chainName: chainName,
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustEVMRefreshWalletInput(
                index: index,
                walletID: wallet.id.uuidString,
                selectedChain: wallet.selectedChain,
                address: resolvedEVMAddress(for: wallet, chainName: chainName)
            )
        },
        allowedWalletIDs: allowedWalletIDs,
        groupByNormalizedAddress: false
    )

    guard let plan = try? WalletRustAppCoreBridge.planEVMRefreshTargets(request) else {
        return nil
    }

    return plan.walletTargets.compactMap { target in
        guard let wallet = walletSnapshot.first(where: { $0.id.uuidString == target.walletID }) else {
            return nil
        }
        return (wallet, target.address)
    }
}

private func plannedEVMHistoryGroups(
    chainName: String,
    walletSnapshot: [ImportedWallet],
    loadMore: Bool,
    targetWalletIDs: Set<UUID>?
) -> [([ImportedWallet], String, String)]? {
    let allowedWalletIDs = targetWalletIDs?.map(\.uuidString)
    let request = WalletRustEVMRefreshTargetsRequest(
        chainName: chainName,
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustEVMRefreshWalletInput(
                index: index,
                walletID: wallet.id.uuidString,
                selectedChain: wallet.selectedChain,
                address: resolvedEVMAddress(for: wallet, chainName: chainName)
            )
        },
        allowedWalletIDs: allowedWalletIDs,
        groupByNormalizedAddress: !loadMore
    )

    guard let plan = try? WalletRustAppCoreBridge.planEVMRefreshTargets(request) else {
        return nil
    }

    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id.uuidString, $0) })
    return plan.groupedTargets.compactMap { target in
        let wallets = target.walletIDs.compactMap { walletByID[$0] }
        guard !wallets.isEmpty else { return nil }
        return (wallets, target.address, target.normalizedAddress)
    }
}

private func plannedDogecoinHistoryWallets(
    walletSnapshot: [ImportedWallet],
    targetWalletIDs: Set<UUID>?
) -> [(ImportedWallet, [String])]? {
    let request = WalletRustDogecoinRefreshTargetsRequest(
        wallets: walletSnapshot.enumerated().map { index, wallet in
            WalletRustDogecoinRefreshWalletInput(
                index: index,
                walletID: wallet.id.uuidString,
                selectedChain: wallet.selectedChain,
                addresses: knownDogecoinAddresses(for: wallet)
            )
        },
        allowedWalletIDs: targetWalletIDs?.map(\.uuidString)
    )

    guard let targets = try? WalletRustAppCoreBridge.planDogecoinRefreshTargets(request) else {
        return nil
    }

    let walletByID = Dictionary(uniqueKeysWithValues: walletSnapshot.map { ($0.id.uuidString, $0) })
    return targets.compactMap { target in
        guard let wallet = walletByID[target.walletID] else { return nil }
        return (wallet, target.addresses)
    }
}
}

// MARK: - EVM history JSON decoding (Rust response → Swift typed snapshots)

/// Decode the JSON produced by `WalletServiceBridge.fetchEVMHistoryPageJSON` into
/// typed `EthereumTokenTransferSnapshot` and `EthereumNativeTransferSnapshot` arrays.
///
/// Expected JSON shape:
/// ```json
/// {
///   "native": [{"txid":"0x…","block_number":N,"timestamp":N,"from":"0x…","to":"0x…","value_wei":"N","fee_wei":"N","is_incoming":true}],
///   "tokens": [{"contract":"0x…","symbol":"…","token_name":"…","decimals":N,"from":"0x…","to":"0x…","amount_raw":"N","amount_display":"1.5","txid":"0x…","block_number":N,"log_index":N,"timestamp":N}]
/// }
/// ```
private func decodeEvmHistoryPageJSON(_ json: String) -> (
    tokens: [EthereumTokenTransferSnapshot],
    native: [EthereumNativeTransferSnapshot]
) {
    guard
        let data = json.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ([], []) }

    // ── Token transfers ────────────────────────────────────────────────────
    var tokens: [EthereumTokenTransferSnapshot] = []
    if let rawTokens = obj["tokens"] as? [[String: Any]] {
        for item in rawTokens {
            guard
                let contract   = item["contract"]     as? String,
                let symbol     = item["symbol"]       as? String,
                let tokenName  = item["token_name"]   as? String,
                let fromAddr   = item["from"]         as? String,
                let toAddr     = item["to"]           as? String,
                let txid       = item["txid"]         as? String,
                let blockNum   = item["block_number"] as? Int,
                let logIdx     = item["log_index"]    as? Int,
                let tsecs      = item["timestamp"]    as? TimeInterval
            else { continue }

            let decimals = item["decimals"] as? Int ?? 18
            // Prefer the pre-formatted display string from Rust.
            let amountDecimal: Decimal
            if let display = item["amount_display"] as? String, let d = Decimal(string: display) {
                amountDecimal = d
            } else if let raw = item["amount_raw"] as? String, let rawDec = Decimal(string: raw) {
                let scale = decimalPow(Decimal(10), decimals)
                amountDecimal = rawDec / scale
            } else {
                amountDecimal = 0
            }

            tokens.append(EthereumTokenTransferSnapshot(
                contractAddress: contract,
                tokenName: tokenName,
                symbol: symbol,
                decimals: decimals,
                fromAddress: fromAddr,
                toAddress: toAddr,
                amount: amountDecimal,
                transactionHash: txid,
                blockNumber: blockNum,
                logIndex: logIdx,
                timestamp: tsecs > 0 ? Date(timeIntervalSince1970: tsecs) : nil
            ))
        }
    }

    // ── Native transfers ───────────────────────────────────────────────────
    var native: [EthereumNativeTransferSnapshot] = []
    if let rawNative = obj["native"] as? [[String: Any]] {
        let weiPerCoin = Decimal(string: "1000000000000000000")! // 1e18
        for item in rawNative {
            guard
                let fromAddr = item["from"]         as? String,
                let toAddr   = item["to"]           as? String,
                let txid     = item["txid"]         as? String,
                let blockNum = item["block_number"] as? Int,
                let tsecs    = item["timestamp"]    as? TimeInterval,
                let weiStr   = item["value_wei"]    as? String,
                let weiDec   = Decimal(string: weiStr)
            else { continue }

            let amount = weiDec / weiPerCoin
            native.append(EthereumNativeTransferSnapshot(
                fromAddress: fromAddr,
                toAddress: toAddr,
                amount: amount,
                transactionHash: txid,
                blockNumber: blockNum,
                timestamp: tsecs > 0 ? Date(timeIntervalSince1970: tsecs) : nil
            ))
        }
    }

    return (tokens, native)
}

private func decimalPow(_ base: Decimal, _ exponent: Int) -> Decimal {
    var result = Decimal(1)
    for _ in 0 ..< exponent { result *= base }
    return result
}
