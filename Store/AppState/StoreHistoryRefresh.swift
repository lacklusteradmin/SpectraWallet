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
    if cursor == nil,
       let seedPhrase = storedSeedPhrase(for: wallet.id),
       !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let inventory = try? BitcoinWalletEngine.addressInventory(for: wallet, seedPhrase: seedPhrase, scanLimit: 20) {
        let ownedAddresses = inventory.entries.map(\.address)
        let indexedAddresses = Array(ownedAddresses.enumerated())
        let fetchedSnapshots = await collectLimitedConcurrentIndexedResults(from: indexedAddresses, maxConcurrent: 4) { entry in
            let (index, address) = entry
            do {
                let page = try await BitcoinBalanceService.fetchTransactionPage(
                    for: address,
                    networkMode: wallet.bitcoinNetworkMode,
                    limit: limit,
                    cursor: nil
                )
                return (index, page.snapshots)
            } catch {
                return (index, nil)
            }
        }

        let mergedSnapshots = try WalletRustAppCoreBridge.mergeBitcoinHistorySnapshots(
            WalletRustMergeBitcoinHistorySnapshotsRequest(
                snapshots: fetchedSnapshots
                    .sorted { $0.key < $1.key }
                    .flatMap(\.value)
                    .map { snapshot in
                        WalletRustBitcoinHistorySnapshotPayload(
                            txid: snapshot.txid,
                            amountBTC: snapshot.amountBTC,
                            kind: snapshot.kind.rawValue,
                            status: snapshot.status.rawValue,
                            counterpartyAddress: snapshot.counterpartyAddress,
                            blockHeight: snapshot.blockHeight,
                            createdAtUnix: snapshot.createdAt.timeIntervalSince1970
                        )
                    },
                ownedAddresses: ownedAddresses,
                limit: limit
            )
        )
        if !mergedSnapshots.isEmpty {
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
                sourceUsed: "wallet.inventory"
            )
        }
    }

    if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
       !bitcoinAddress.isEmpty {
        return try await BitcoinBalanceService.fetchTransactionPage(
            for: bitcoinAddress,
            networkMode: wallet.bitcoinNetworkMode,
            limit: limit,
            cursor: cursor
        )
    }

    if let bitcoinXPub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines),
       !bitcoinXPub.isEmpty {
        return try await BitcoinBalanceService.fetchTransactionPage(
            forExtendedPublicKey: bitcoinXPub,
            limit: limit,
            cursor: cursor
        )
    }

    throw URLError(.fileDoesNotExist)
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
        let cursor = loadMore ? bitcoinCashHistoryCursorByWallet[wallet.id] : nil
        do {
            let page = try await BitcoinCashBalanceService.fetchTransactionPage(
                for: bitcoinCashAddress,
                limit: requestedLimit,
                cursor: cursor
            )
            bitcoinCashHistoryCursorByWallet[wallet.id] = page.nextCursor
            if page.nextCursor == nil {
                exhaustedBitcoinCashHistoryWalletIDs.insert(wallet.id)
            } else {
                exhaustedBitcoinCashHistoryWalletIDs.remove(wallet.id)
            }

            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: snapshot.kind,
                        status: snapshot.status,
                        walletName: wallet.name,
                        assetName: "Bitcoin Cash",
                        symbol: "BCH",
                        chainName: "Bitcoin Cash",
                        amount: snapshot.amountBCH,
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
        let cursor = loadMore ? bitcoinSVHistoryCursorByWallet[wallet.id] : nil
        do {
            let page = try await BitcoinSVBalanceService.fetchTransactionPage(
                for: bitcoinSVAddress,
                limit: requestedLimit,
                cursor: cursor
            )
            bitcoinSVHistoryCursorByWallet[wallet.id] = page.nextCursor
            if page.nextCursor == nil {
                exhaustedBitcoinSVHistoryWalletIDs.insert(wallet.id)
            } else {
                exhaustedBitcoinSVHistoryWalletIDs.remove(wallet.id)
            }

            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: snapshot.kind,
                        status: snapshot.status,
                        walletName: wallet.name,
                        assetName: "Bitcoin SV",
                        symbol: "BSV",
                        chainName: "Bitcoin SV",
                        amount: snapshot.amountBSV,
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
        let cursor = loadMore ? litecoinHistoryCursorByWallet[wallet.id] : nil
        do {
            let page = try await LitecoinBalanceService.fetchTransactionPage(
                for: litecoinAddress,
                limit: requestedLimit,
                cursor: cursor
            )
            litecoinHistoryCursorByWallet[wallet.id] = page.nextCursor
            if page.nextCursor == nil {
                exhaustedLitecoinHistoryWalletIDs.insert(wallet.id)
            } else {
                exhaustedLitecoinHistoryWalletIDs.remove(wallet.id)
            }

            discoveredTransactions.append(
                contentsOf: page.snapshots.map { snapshot in
                    TransactionRecord(
                        walletID: wallet.id,
                        kind: snapshot.kind,
                        status: snapshot.status,
                        walletName: wallet.name,
                        assetName: "Litecoin",
                        symbol: "LTC",
                        chainName: "Litecoin",
                        amount: snapshot.amountLTC,
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
        let result = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: tronAddress, limit: HistoryPaging.endpointBatchSize)
        tronHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
        tronHistoryDiagnosticsLastUpdatedAt = Date()

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        if result.snapshots.isEmpty {
            exhaustedTronHistoryWalletIDs.insert(wallet.id)
        } else {
            exhaustedTronHistoryWalletIDs.remove(wallet.id)
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: item.symbol == "USDT" ? "Tether USD" : "Tron",
                symbol: item.symbol,
                chainName: "Tron",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: "tronscan",
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await SolanaBalanceService.fetchRecentHistoryWithDiagnostics(for: solanaAddress, limit: HistoryPaging.endpointBatchSize)
        solanaHistoryDiagnosticsByWallet[wallet.id] = result.diagnostics
        solanaHistoryDiagnosticsLastUpdatedAt = Date()

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: item.assetName,
                symbol: item.symbol,
                chainName: "Solana",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: "solana-rpc",
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await CardanoBalanceService.fetchRecentHistoryWithDiagnostics(for: cardanoAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Cardano",
                symbol: "ADA",
                chainName: "Cardano",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await XRPBalanceService.fetchRecentHistoryWithDiagnostics(for: xrpAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "XRP",
                symbol: "XRP",
                chainName: "XRP Ledger",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: "xrpscan",
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await StellarBalanceService.fetchRecentHistoryWithDiagnostics(for: stellarAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Stellar Lumens",
                symbol: "XLM",
                chainName: "Stellar",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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

    let requestedLimit = max(20, min(loadMore ? HistoryPaging.endpointBatchSize * 2 : HistoryPaging.endpointBatchSize, 300))
    var discoveredTransactions: [TransactionRecord] = []
    var encounteredErrors = false

    for wallet in moneroWallets {
        guard let moneroAddress = resolvedMoneroAddress(for: wallet) else { continue }
        let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: moneroAddress, limit: requestedLimit)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Monero",
                symbol: "XMR",
                chainName: "Monero",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: suiAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Sui",
                symbol: "SUI",
                chainName: "Sui",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                sourceAddress: suiAddress,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: HistoryPaging.endpointBatchSize)
        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        discoveredTransactions.append(contentsOf: result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Internet Computer",
                symbol: "ICP",
                chainName: "Internet Computer",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        })
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
        let result = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: aptosAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Aptos",
                symbol: "APT",
                chainName: "Aptos",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await TONBalanceService.fetchRecentHistoryWithDiagnostics(for: address, limit: HistoryPaging.endpointBatchSize)
        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Toncoin",
                symbol: "TON",
                chainName: "TON",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: nearAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "NEAR Protocol",
                symbol: "NEAR",
                chainName: "NEAR",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
        let result = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: polkadotAddress, limit: HistoryPaging.endpointBatchSize)

        if let error = result.diagnostics.error, !error.isEmpty {
            encounteredErrors = true
        }

        let records = result.snapshots.map { item in
            TransactionRecord(
                walletID: wallet.id,
                kind: item.kind,
                status: item.status,
                walletName: wallet.name,
                assetName: "Polkadot",
                symbol: "DOT",
                chainName: "Polkadot",
                amount: item.amount,
                address: item.counterpartyAddress,
                transactionHash: item.transactionHash,
                transactionHistorySource: result.diagnostics.sourceUsed,
                createdAt: item.createdAt
            )
        }
        discoveredTransactions.append(contentsOf: records)
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
            return walletsToRefresh.map { ([$0.0], $0.1, EthereumWalletEngine.normalizeAddress($0.1)) }
        }
        return Dictionary(grouping: walletsToRefresh) {
            EthereumWalletEngine.normalizeAddress($0.1)
        }
        .values
        .compactMap { group in
            guard let first = group.first else { return nil }
            return (group.map(\.0), first.1, EthereumWalletEngine.normalizeAddress(first.1))
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
    let rpcEndpoint = configuredEVMRPCEndpointURL(for: chainName)
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
        do {
            let result = try await EthereumWalletEngine.fetchSupportedTokenTransferHistoryPageWithDiagnostics(
                for: normalizedAddress,
                rpcEndpoint: rpcEndpoint,
                etherscanAPIKey: normalizedEtherscanAPIKey(),
                page: page,
                pageSize: requestedPageSize,
                trackedTokens: trackedTokens,
                chain: chain
            )
            tokenHistory = result.snapshots
            tokenDiagnostics = result.diagnostics
        } catch {
            tokenHistoryError = error
            encounteredErrors = true
        }

        let nativeTransfers: [EthereumNativeTransferSnapshot]
        do {
            if chain.isEthereumMainnet {
                let blockscoutNativeTransfers = try? await EthereumWalletEngine.fetchNativeTransferHistoryPageFromBlockscout(
                    for: normalizedAddress,
                    page: page,
                    pageSize: requestedPageSize,
                    chain: chain
                )
                if let blockscoutNativeTransfers, !blockscoutNativeTransfers.isEmpty {
                    nativeTransfers = blockscoutNativeTransfers
                } else {
                    nativeTransfers = try await EthereumWalletEngine.fetchNativeTransferHistoryPageFromEtherscan(
                        for: normalizedAddress,
                        apiKey: normalizedEtherscanAPIKey(),
                        page: page,
                        pageSize: requestedPageSize,
                        chain: chain
                    )
                }
            } else if chain == .arbitrum || chain == .optimism || chain == .bnb || chain == .avalanche || chain == .hyperliquid {
                nativeTransfers = try await EthereumWalletEngine.fetchNativeTransferHistoryPageFromEtherscan(
                    for: normalizedAddress,
                    apiKey: normalizedEtherscanAPIKey(),
                    page: page,
                    pageSize: requestedPageSize,
                    chain: chain
                )
            } else {
                nativeTransfers = []
            }
        } catch {
            encounteredErrors = true
            nativeTransfers = []
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
                let page = try await DogecoinBalanceService.fetchTransactionPage(
                    for: dogecoinAddress,
                    limit: fetchLimit,
                    cursor: loadMore ? dogecoinHistoryCursorByWallet[wallet.id] : nil,
                    networkMode: wallet.dogecoinNetworkMode
                )
                let snapshots = page.snapshots
                for snapshot in snapshots {
                    snapshotsByHash[snapshot.hash, default: []].append(snapshot)
                }
                if let nextCursor = page.nextCursor {
                    dogecoinHistoryCursorByWallet[wallet.id] = nextCursor
                    exhaustedDogecoinHistoryWalletIDs.remove(wallet.id)
                } else {
                    dogecoinHistoryCursorByWallet[wallet.id] = nil
                    exhaustedDogecoinHistoryWalletIDs.insert(wallet.id)
                }
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
