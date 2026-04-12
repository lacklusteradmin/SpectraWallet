import Foundation

extension WalletStore {
func canLoadMoreHistory(for walletID: UUID) -> Bool {
    guard let wallet = cachedWalletByID[walletID] else { return false }
    switch wallet.selectedChain {
    case "Bitcoin":
        return !exhaustedBitcoinHistoryWalletIDs.contains(walletID)
    case "Bitcoin Cash":
        return !exhaustedBitcoinCashHistoryWalletIDs.contains(walletID)
    case "Bitcoin SV":
        return !exhaustedBitcoinSVHistoryWalletIDs.contains(walletID)
    case "Litecoin":
        return !exhaustedLitecoinHistoryWalletIDs.contains(walletID)
    case "Dogecoin":
        return !exhaustedDogecoinHistoryWalletIDs.contains(walletID)
    case "Ethereum":
        return !exhaustedEthereumHistoryWalletIDs.contains(walletID)
    case "Arbitrum":
        return !exhaustedArbitrumHistoryWalletIDs.contains(walletID)
    case "Optimism":
        return !exhaustedOptimismHistoryWalletIDs.contains(walletID)
    case "BNB Chain":
        return !exhaustedBNBHistoryWalletIDs.contains(walletID)
    case "Hyperliquid":
        return !exhaustedHyperliquidHistoryWalletIDs.contains(walletID)
    case "Tron":
        return !exhaustedTronHistoryWalletIDs.contains(walletID)
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
            let entries = decodeRustHistoryJSON(json: json)
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

/// Parse a Rust JSON array of `{txid, amount_sat|amount_koin, block_height, timestamp, is_incoming}` objects.
func decodeSatHistoryFromRust(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return arr
}

/// Parse a Rust JSON array of `TronTransfer` objects.
func decodeTronTransfersFromRust(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return arr
}

/// Parse a Rust JSON array of `SolanaTransfer` objects.
func decodeSolanaTransfersFromRust(json: String) -> [[String: Any]] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return arr
}

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
        let walletIDs = Set(bitcoinWallets.map(\.id))
        bitcoinHistoryCursorByWallet = bitcoinHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedBitcoinHistoryWalletIDs = []
        for walletID in walletIDs {
            bitcoinHistoryCursorByWallet[walletID] = nil
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in bitcoinWallets {
        if loadMore && exhaustedBitcoinHistoryWalletIDs.contains(wallet.id) {
            continue
        }

        let cursor = loadMore ? bitcoinHistoryCursorByWallet[wallet.id] : nil
        do {
            let page = try await fetchBitcoinHistoryPage(for: wallet, limit: requestedLimit, cursor: cursor)
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name

            bitcoinHistoryCursorByWallet[wallet.id] = page.nextCursor
            if page.nextCursor == nil {
                exhaustedBitcoinHistoryWalletIDs.insert(wallet.id)
            } else {
                exhaustedBitcoinHistoryWalletIDs.remove(wallet.id)
            }

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
            bitcoinHistoryCursorByWallet[wallet.id] = nil
            exhaustedBitcoinHistoryWalletIDs.insert(wallet.id)
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

func refreshBitcoinCashTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let bitcoinCashWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Bitcoin Cash",
              resolvedBitcoinCashAddress(for: wallet) != nil else {
            return false
        }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !bitcoinCashWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))

    if !loadMore {
        let walletIDs = Set(bitcoinCashWallets.map(\.id))
        bitcoinCashHistoryCursorByWallet = bitcoinCashHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedBitcoinCashHistoryWalletIDs = []
        for walletID in walletIDs {
            bitcoinCashHistoryCursorByWallet[walletID] = nil
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in bitcoinCashWallets {
        if loadMore && exhaustedBitcoinCashHistoryWalletIDs.contains(wallet.id) {
            continue
        }

        guard let bitcoinCashAddress = resolvedBitcoinCashAddress(for: wallet) else { continue }
        if loadMore && bitcoinCashHistoryCursorByWallet[wallet.id] == nil {
            // Rust returns a flat list; treat first fetch as exhausting the page.
            exhaustedBitcoinCashHistoryWalletIDs.insert(wallet.id)
            continue
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.bitcoinCash, address: bitcoinCashAddress
            )
            bitcoinCashHistoryCursorByWallet[wallet.id] = nil
            exhaustedBitcoinCashHistoryWalletIDs.insert(wallet.id)

            let records = decodeSatHistoryFromRust(json: json).prefix(requestedLimit).compactMap { entry -> TransactionRecord? in
                guard let txid = entry["txid"] as? String else { return nil }
                let amountSat = (entry["amount_sat"] as? Int) ?? 0
                let blockHeight = entry["block_height"] as? Int
                let timestamp = (entry["timestamp"] as? Double) ?? 0
                let isIncoming = (entry["is_incoming"] as? Bool) ?? (amountSat >= 0)
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: blockHeight.map { $0 > 0 } ?? false ? .confirmed : .pending,
                    walletName: wallet.name,
                    assetName: "Bitcoin Cash",
                    symbol: "BCH",
                    chainName: "Bitcoin Cash",
                    amount: Double(abs(amountSat)) / 1e8,
                    address: "",
                    transactionHash: txid,
                    receiptBlockNumber: blockHeight,
                    transactionHistorySource: "rust",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
            bitcoinCashHistoryCursorByWallet[wallet.id] = nil
            exhaustedBitcoinCashHistoryWalletIDs.insert(wallet.id)
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertBitcoinCashTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Bitcoin Cash", detail: "Bitcoin Cash history loaded with partial provider failures.")
        } else {
            markChainHealthy("Bitcoin Cash")
        }
    } else if encounteredErrors {
        markChainDegraded("Bitcoin Cash", detail: "Bitcoin Cash history refresh failed. Using cached history.")
    }
}

func refreshBitcoinSVTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let bitcoinSVWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Bitcoin SV",
              resolvedBitcoinSVAddress(for: wallet) != nil else {
            return false
        }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !bitcoinSVWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))

    if !loadMore {
        let walletIDs = Set(bitcoinSVWallets.map(\.id))
        bitcoinSVHistoryCursorByWallet = bitcoinSVHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedBitcoinSVHistoryWalletIDs = []
        for walletID in walletIDs {
            bitcoinSVHistoryCursorByWallet[walletID] = nil
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in bitcoinSVWallets {
        if loadMore && exhaustedBitcoinSVHistoryWalletIDs.contains(wallet.id) {
            continue
        }

        guard let bitcoinSVAddress = resolvedBitcoinSVAddress(for: wallet) else { continue }
        if loadMore && bitcoinSVHistoryCursorByWallet[wallet.id] == nil {
            exhaustedBitcoinSVHistoryWalletIDs.insert(wallet.id)
            continue
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.bitcoinSv, address: bitcoinSVAddress
            )
            bitcoinSVHistoryCursorByWallet[wallet.id] = nil
            exhaustedBitcoinSVHistoryWalletIDs.insert(wallet.id)

            let records = decodeSatHistoryFromRust(json: json).prefix(requestedLimit).compactMap { entry -> TransactionRecord? in
                guard let txid = entry["txid"] as? String else { return nil }
                let amountSat = (entry["amount_sat"] as? Int) ?? 0
                let blockHeight = entry["block_height"] as? Int
                let timestamp = (entry["timestamp"] as? Double) ?? 0
                let isIncoming = (entry["is_incoming"] as? Bool) ?? (amountSat >= 0)
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: blockHeight.map { $0 > 0 } ?? false ? .confirmed : .pending,
                    walletName: wallet.name,
                    assetName: "Bitcoin SV",
                    symbol: "BSV",
                    chainName: "Bitcoin SV",
                    amount: Double(abs(amountSat)) / 1e8,
                    address: "",
                    transactionHash: txid,
                    receiptBlockNumber: blockHeight,
                    transactionHistorySource: "rust",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
            bitcoinSVHistoryCursorByWallet[wallet.id] = nil
            exhaustedBitcoinSVHistoryWalletIDs.insert(wallet.id)
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertBitcoinSVTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Bitcoin SV", detail: "Bitcoin SV history loaded with partial provider failures.")
        } else {
            markChainHealthy("Bitcoin SV")
        }
    } else if encounteredErrors {
        markChainDegraded("Bitcoin SV", detail: "Bitcoin SV history refresh failed. Using cached history.")
    }
}

func refreshLitecoinTransactions(limit: Int? = nil, loadMore: Bool = false, targetWalletIDs: Set<UUID>? = nil) async {
    let walletSnapshot = wallets
    let litecoinWallets = walletSnapshot.filter { wallet in
        guard wallet.selectedChain == "Litecoin",
              resolvedLitecoinAddress(for: wallet) != nil else {
            return false
        }
        guard let targetWalletIDs else { return true }
        return targetWalletIDs.contains(wallet.id)
    }
    guard !litecoinWallets.isEmpty else { return }
    let requestedLimit = max(10, min(limit ?? HistoryPaging.endpointBatchSize, 100))

    if !loadMore {
        let walletIDs = Set(litecoinWallets.map(\.id))
        litecoinHistoryCursorByWallet = litecoinHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedLitecoinHistoryWalletIDs = []
        for walletID in walletIDs {
            litecoinHistoryCursorByWallet[walletID] = nil
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in litecoinWallets {
        if loadMore && exhaustedLitecoinHistoryWalletIDs.contains(wallet.id) {
            continue
        }

        guard let litecoinAddress = resolvedLitecoinAddress(for: wallet) else { continue }
        if loadMore && litecoinHistoryCursorByWallet[wallet.id] == nil {
            exhaustedLitecoinHistoryWalletIDs.insert(wallet.id)
            continue
        }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.litecoin, address: litecoinAddress
            )
            litecoinHistoryCursorByWallet[wallet.id] = nil
            exhaustedLitecoinHistoryWalletIDs.insert(wallet.id)

            let records = decodeSatHistoryFromRust(json: json).prefix(requestedLimit).compactMap { entry -> TransactionRecord? in
                guard let txid = entry["txid"] as? String else { return nil }
                let amountSat = (entry["amount_sat"] as? Int) ?? 0
                let blockHeight = entry["block_height"] as? Int
                let timestamp = (entry["timestamp"] as? Double) ?? 0
                let isIncoming = (entry["is_incoming"] as? Bool) ?? (amountSat >= 0)
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: blockHeight.map { $0 > 0 } ?? false ? .confirmed : .pending,
                    walletName: wallet.name,
                    assetName: "Litecoin",
                    symbol: "LTC",
                    chainName: "Litecoin",
                    amount: Double(abs(amountSat)) / 1e8,
                    address: "",
                    transactionHash: txid,
                    receiptBlockNumber: blockHeight,
                    transactionHistorySource: "rust",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
            litecoinHistoryCursorByWallet[wallet.id] = nil
            exhaustedLitecoinHistoryWalletIDs.insert(wallet.id)
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertLitecoinTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded(
                "Litecoin",
                detail: "Litecoin history loaded with partial provider failures. Some recent transfers may be missing."
            )
        } else {
            markChainHealthy("Litecoin")
        }
    } else if encounteredErrors {
        markChainDegraded(
            "Litecoin",
            detail: "Litecoin history refresh failed. Showing cached history; try again from Diagnostics or pull to refresh."
        )
    }
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
        let walletIDs = Set(tronWallets.map(\.id))
        tronHistoryCursorByWallet = tronHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedTronHistoryWalletIDs = []
        for walletID in walletIDs {
            tronHistoryCursorByWallet[walletID] = nil
        }
    }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in tronWallets {
        if loadMore && exhaustedTronHistoryWalletIDs.contains(wallet.id) {
            continue
        }
        guard let tronAddress = resolvedTronAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.tron, address: tronAddress
            )
            let entries = decodeTronTransfersFromRust(json: json)
            if entries.isEmpty {
                exhaustedTronHistoryWalletIDs.insert(wallet.id)
            } else {
                exhaustedTronHistoryWalletIDs.remove(wallet.id)
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
            let entries = decodeSolanaTransfersFromRust(json: json)
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
    _ = loadMore
    let walletSnapshot = wallets
    let cardanoWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Cardano" && resolvedCardanoAddress(for: wallet) != nil
    }
    guard !cardanoWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in cardanoWallets {
        guard let cardanoAddress = resolvedCardanoAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.cardano, address: cardanoAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let lovelace = entry["amount_lovelace"] as? Int ?? 0
                let amount = Double(abs(lovelace)) / 1_000_000
                let blockTime = entry["block_time"] as? Double ?? 0
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Cardano",
                    symbol: "ADA",
                    chainName: "Cardano",
                    amount: amount,
                    address: "",
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "blockfrost",
                    createdAt: blockTime > 0 ? Date(timeIntervalSince1970: blockTime) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertCardanoTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Cardano", detail: "Cardano history loaded with partial provider failures.")
        } else {
            markChainHealthy("Cardano")
        }
    } else if encounteredErrors {
        markChainDegraded("Cardano", detail: "Cardano history refresh failed. Using cached history.")
    }
}

func refreshXRPTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let xrpWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "XRP Ledger" && resolvedXRPAddress(for: wallet) != nil
    }
    guard !xrpWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in xrpWallets {
        guard let xrpAddress = resolvedXRPAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.xrp, address: xrpAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let drops = entry["amount_drops"] as? Int ?? 0
                let amount = Double(drops) / 1_000_000
                let timestamp = entry["timestamp"] as? Double ?? 0
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "XRP",
                    symbol: "XRP",
                    chainName: "XRP Ledger",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "xrpscan",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertXRPTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("XRP Ledger", detail: "XRP history loaded with partial provider failures.")
        } else {
            markChainHealthy("XRP Ledger")
        }
    } else if encounteredErrors {
        markChainDegraded("XRP Ledger", detail: "XRP history refresh failed. Using cached history.")
    }
}

func refreshStellarTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let stellarWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Stellar" && resolvedStellarAddress(for: wallet) != nil
    }
    guard !stellarWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in stellarWallets {
        guard let stellarAddress = resolvedStellarAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.stellar, address: stellarAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let isoFormatter = ISO8601DateFormatter()
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let stroops = entry["amount_stroops"] as? Int ?? 0
                let amount = Double(abs(stroops)) / 10_000_000
                let timestampStr = entry["timestamp"] as? String ?? ""
                let date = isoFormatter.date(from: timestampStr) ?? Date()
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Stellar Lumens",
                    symbol: "XLM",
                    chainName: "Stellar",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "horizon",
                    createdAt: date
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertStellarTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Stellar", detail: "Stellar history loaded with partial provider failures.")
        } else {
            markChainHealthy("Stellar")
        }
    } else if encounteredErrors {
        markChainDegraded("Stellar", detail: "Stellar history refresh failed. Using cached history.")
    }
}

func refreshMoneroTransactions(loadMore: Bool = false) async {
    let walletSnapshot = wallets
    let moneroWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Monero" && resolvedMoneroAddress(for: wallet) != nil
    }
    guard !moneroWallets.isEmpty else { return }

    _ = loadMore
    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in moneroWallets {
        guard let moneroAddress = resolvedMoneroAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.monero, address: moneroAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let piconeros = entry["amount_piconeros"] as? Double ?? 0
                let amount = piconeros / 1_000_000_000_000
                let timestamp = entry["timestamp"] as? Double ?? 0
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Monero",
                    symbol: "XMR",
                    chainName: "Monero",
                    amount: amount,
                    address: "",
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "monero-rpc",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertMoneroTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Monero", detail: "Monero history loaded with partial provider failures.")
        } else {
            markChainHealthy("Monero")
        }
    } else if encounteredErrors {
        markChainDegraded("Monero", detail: "Monero history refresh failed. Using cached history.")
    }
}

func refreshSuiTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let suiWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Sui" && resolvedSuiAddress(for: wallet) != nil
    }
    guard !suiWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in suiWallets {
        guard let suiAddress = resolvedSuiAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.sui, address: suiAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let mist = entry["amount_mist"] as? Double ?? 0
                let amount = mist / 1_000_000_000
                let timestampMs = entry["timestamp_ms"] as? Double ?? 0
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Sui",
                    symbol: "SUI",
                    chainName: "Sui",
                    amount: amount,
                    address: "",
                    transactionHash: entry["digest"] as? String ?? "",
                    sourceAddress: suiAddress,
                    transactionHistorySource: "sui-rpc",
                    createdAt: timestampMs > 0 ? Date(timeIntervalSince1970: timestampMs / 1000) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertSuiTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Sui", detail: "Sui history loaded with partial provider failures.")
        } else {
            markChainHealthy("Sui")
        }
    } else if encounteredErrors {
        markChainDegraded("Sui", detail: "Sui history refresh failed. Using cached history.")
    }
}

func refreshICPTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let icpWallets = wallets.filter { wallet in
        wallet.selectedChain == "Internet Computer" && resolvedICPAddress(for: wallet) != nil
    }
    guard !icpWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in icpWallets {
        guard let address = resolvedICPAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.icp, address: address
            )
            let entries = decodeRustHistoryJSON(json: json)
            discoveredTransactions.append(contentsOf: entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let e8s = entry["amount_e8s"] as? Double ?? 0
                let amount = e8s / 100_000_000
                let timestampNs = entry["timestamp_ns"] as? Double ?? 0
                let blockIndex = entry["block_index"] as? Int ?? 0
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Internet Computer",
                    symbol: "ICP",
                    chainName: "Internet Computer",
                    amount: amount,
                    address: counterparty,
                    transactionHash: String(blockIndex),
                    transactionHistorySource: "rosetta",
                    createdAt: timestampNs > 0 ? Date(timeIntervalSince1970: timestampNs / 1_000_000_000) : Date()
                )
            })
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertICPTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Internet Computer", detail: "Internet Computer history loaded with partial provider failures.")
        } else {
            markChainHealthy("Internet Computer")
        }
    } else if encounteredErrors {
        markChainDegraded("Internet Computer", detail: "Internet Computer history refresh failed. Using cached history.")
    }
}

func refreshAptosTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let aptosWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Aptos" && resolvedAptosAddress(for: wallet) != nil
    }
    guard !aptosWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in aptosWallets {
        guard let aptosAddress = resolvedAptosAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.aptos, address: aptosAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let octas = entry["amount_octas"] as? Double ?? 0
                let amount = octas / 100_000_000
                let timestampUs = entry["timestamp_us"] as? Double ?? 0
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Aptos",
                    symbol: "APT",
                    chainName: "Aptos",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "aptos-rpc",
                    createdAt: timestampUs > 0 ? Date(timeIntervalSince1970: timestampUs / 1_000_000) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertAptosTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Aptos", detail: "Aptos history loaded with partial provider failures.")
        } else {
            markChainHealthy("Aptos")
        }
    } else if encounteredErrors {
        markChainDegraded("Aptos", detail: "Aptos history refresh failed. Using cached history.")
    }
}

func refreshTONTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let tonWallets = wallets.filter { wallet in
        wallet.selectedChain == "TON" && resolvedTONAddress(for: wallet) != nil
    }
    guard !tonWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in tonWallets {
        guard let address = resolvedTONAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.ton, address: address
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let nanotons = entry["amount_nanotons"] as? Double ?? 0
                let amount = nanotons / 1_000_000_000
                let timestamp = entry["timestamp"] as? Double ?? 0
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Toncoin",
                    symbol: "TON",
                    chainName: "TON",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "tonapi",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertTONTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("TON", detail: "TON history loaded with partial provider failures.")
        } else {
            markChainHealthy("TON")
        }
    } else if encounteredErrors {
        markChainDegraded("TON", detail: "TON history refresh failed. Using cached history.")
    }
}

func refreshNearTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let nearWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "NEAR" && resolvedNearAddress(for: wallet) != nil
    }
    guard !nearWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in nearWallets {
        guard let nearAddress = resolvedNearAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.near, address: nearAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let yoctoStr = entry["amount_yocto"] as? String ?? "0"
                let amount = (Double(yoctoStr) ?? 0) / 1e24
                let timestampNs = entry["timestamp_ns"] as? Double ?? 0
                let signer = entry["signer_id"] as? String ?? ""
                let receiver = entry["receiver_id"] as? String ?? ""
                let counterparty = isIncoming ? signer : receiver
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "NEAR Protocol",
                    symbol: "NEAR",
                    chainName: "NEAR",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "near-rpc",
                    createdAt: timestampNs > 0 ? Date(timeIntervalSince1970: timestampNs / 1_000_000_000) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertNearTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("NEAR", detail: "NEAR history loaded with partial provider failures.")
        } else {
            markChainHealthy("NEAR")
        }
    } else if encounteredErrors {
        markChainDegraded("NEAR", detail: "NEAR history refresh failed. Using cached history.")
    }
}

func refreshPolkadotTransactions(loadMore: Bool = false) async {
    _ = loadMore
    let walletSnapshot = wallets
    let polkadotWallets = walletSnapshot.filter { wallet in
        wallet.selectedChain == "Polkadot" && resolvedPolkadotAddress(for: wallet) != nil
    }
    guard !polkadotWallets.isEmpty else { return }

    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in polkadotWallets {
        guard let polkadotAddress = resolvedPolkadotAddress(for: wallet) else { continue }
        do {
            let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.polkadot, address: polkadotAddress
            )
            let entries = decodeRustHistoryJSON(json: json)
            let records = entries.map { entry -> TransactionRecord in
                let isIncoming = entry["is_incoming"] as? Bool ?? false
                let planck = entry["amount_planck"] as? Double ?? 0
                let amount = planck / 10_000_000_000
                let timestamp = entry["timestamp"] as? Double ?? 0
                let from = entry["from"] as? String ?? ""
                let to = entry["to"] as? String ?? ""
                let counterparty = isIncoming ? from : to
                return TransactionRecord(
                    walletID: wallet.id,
                    kind: isIncoming ? .receive : .send,
                    status: .confirmed,
                    walletName: wallet.name,
                    assetName: "Polkadot",
                    symbol: "DOT",
                    chainName: "Polkadot",
                    amount: amount,
                    address: counterparty,
                    transactionHash: entry["txid"] as? String ?? "",
                    transactionHistorySource: "subscan",
                    createdAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
                )
            }
            discoveredTransactions.append(contentsOf: records)
        } catch {
            encounteredErrors = true
        }
    }

    if !discoveredTransactions.isEmpty {
        upsertPolkadotTransactions(discoveredTransactions)
        if encounteredErrors {
            markChainDegraded("Polkadot", detail: "Polkadot history loaded with partial provider failures.")
        } else {
            markChainHealthy("Polkadot")
        }
    } else if encounteredErrors {
        markChainDegraded("Polkadot", detail: "Polkadot history refresh failed. Using cached history.")
    }
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
        if chain.isEthereumFamily {
            ethereumHistoryPageByWallet = ethereumHistoryPageByWallet.filter { walletIDs.contains($0.key) }
            exhaustedEthereumHistoryWalletIDs = []
            for walletID in walletIDs {
                ethereumHistoryPageByWallet[walletID] = 1
            }
        } else if chain == .arbitrum {
            arbitrumHistoryPageByWallet = arbitrumHistoryPageByWallet.filter { walletIDs.contains($0.key) }
            exhaustedArbitrumHistoryWalletIDs = []
            for walletID in walletIDs {
                arbitrumHistoryPageByWallet[walletID] = 1
            }
        } else if chain == .optimism {
            optimismHistoryPageByWallet = optimismHistoryPageByWallet.filter { walletIDs.contains($0.key) }
            exhaustedOptimismHistoryWalletIDs = []
            for walletID in walletIDs {
                optimismHistoryPageByWallet[walletID] = 1
            }
        } else if chain == .hyperliquid {
            hyperliquidHistoryPageByWallet = hyperliquidHistoryPageByWallet.filter { walletIDs.contains($0.key) }
            exhaustedHyperliquidHistoryWalletIDs = []
            for walletID in walletIDs {
                hyperliquidHistoryPageByWallet[walletID] = 1
            }
        } else {
            bnbHistoryPageByWallet = bnbHistoryPageByWallet.filter { walletIDs.contains($0.key) }
            exhaustedBNBHistoryWalletIDs = []
            for walletID in walletIDs {
                bnbHistoryPageByWallet[walletID] = 1
            }
        }
    }
    for (targetWallets, _, normalizedAddress) in historyTargets {
        guard let representativeWallet = targetWallets.first else { continue }
        if loadMore {
            if chain.isEthereumFamily, exhaustedEthereumHistoryWalletIDs.contains(representativeWallet.id) { continue }
            if chain == .arbitrum, exhaustedArbitrumHistoryWalletIDs.contains(representativeWallet.id) { continue }
            if chain == .optimism, exhaustedOptimismHistoryWalletIDs.contains(representativeWallet.id) { continue }
            if chain == .hyperliquid, exhaustedHyperliquidHistoryWalletIDs.contains(representativeWallet.id) { continue }
            if chain == .bnb, exhaustedBNBHistoryWalletIDs.contains(representativeWallet.id) { continue }
        }
        let currentPage: Int
        if chain.isEthereumFamily {
            currentPage = ethereumHistoryPageByWallet[representativeWallet.id] ?? 1
        } else if chain == .arbitrum {
            currentPage = arbitrumHistoryPageByWallet[representativeWallet.id] ?? 1
        } else if chain == .optimism {
            currentPage = optimismHistoryPageByWallet[representativeWallet.id] ?? 1
        } else if chain == .hyperliquid {
            currentPage = hyperliquidHistoryPageByWallet[representativeWallet.id] ?? 1
        } else {
            currentPage = bnbHistoryPageByWallet[representativeWallet.id] ?? 1
        }
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

        if tokenHistory.count < requestedPageSize && nativeTransfers.count < requestedPageSize {
            for wallet in targetWallets {
                if chain.isEthereumFamily {
                    exhaustedEthereumHistoryWalletIDs.insert(wallet.id)
                } else if chain == .arbitrum {
                    exhaustedArbitrumHistoryWalletIDs.insert(wallet.id)
                } else if chain == .optimism {
                    exhaustedOptimismHistoryWalletIDs.insert(wallet.id)
                } else if chain == .hyperliquid {
                    exhaustedHyperliquidHistoryWalletIDs.insert(wallet.id)
                } else {
                    exhaustedBNBHistoryWalletIDs.insert(wallet.id)
                }
            }
        } else {
            for wallet in targetWallets {
                if chain.isEthereumFamily {
                    exhaustedEthereumHistoryWalletIDs.remove(wallet.id)
                } else if chain == .arbitrum {
                    exhaustedArbitrumHistoryWalletIDs.remove(wallet.id)
                } else if chain == .optimism {
                    exhaustedOptimismHistoryWalletIDs.remove(wallet.id)
                } else if chain == .hyperliquid {
                    exhaustedHyperliquidHistoryWalletIDs.remove(wallet.id)
                } else {
                    exhaustedBNBHistoryWalletIDs.remove(wallet.id)
                }
            }
        }
        for wallet in targetWallets {
            if chain.isEthereumFamily {
                ethereumHistoryPageByWallet[wallet.id] = page
            } else if chain == .arbitrum {
                arbitrumHistoryPageByWallet[wallet.id] = page
            } else if chain == .optimism {
                optimismHistoryPageByWallet[wallet.id] = page
            } else if chain == .hyperliquid {
                hyperliquidHistoryPageByWallet[wallet.id] = page
            } else {
                bnbHistoryPageByWallet[wallet.id] = page
            }
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
        let walletIDs = Set(walletsToRefresh.map { $0.0.id })
        dogecoinHistoryCursorByWallet = dogecoinHistoryCursorByWallet.filter { walletIDs.contains($0.key) }
        exhaustedDogecoinHistoryWalletIDs = []
        for walletID in walletIDs {
            dogecoinHistoryCursorByWallet[walletID] = nil
        }
    }
    var syncedTransactions: [TransactionRecord] = []
    var encounteredErrors = false
    for (wallet, dogecoinAddresses) in walletsToRefresh {
        let ownAddressSet = Set(dogecoinAddresses.map { $0.lowercased() })
        var snapshotsByHash: [String: [DogecoinBalanceService.AddressTransactionSnapshot]] = [:]
        if loadMore && exhaustedDogecoinHistoryWalletIDs.contains(wallet.id) {
            continue
        }

        for dogecoinAddress in dogecoinAddresses {
            do {
                let json = try await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.dogecoin, address: dogecoinAddress
                )
                let entries = decodeSatHistoryFromRust(json: json)
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
                dogecoinHistoryCursorByWallet[wallet.id] = nil
                exhaustedDogecoinHistoryWalletIDs.insert(wallet.id)
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
