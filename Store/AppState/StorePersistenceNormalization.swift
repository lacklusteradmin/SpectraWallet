import Foundation

extension WalletStore {
    // Centralized side-effects whenever wallet collection changes.
    // Keeps onboarding flag, persistence, and transaction pruning synchronized.
    // MARK: - Persistence and Normalization
    func rebuildTokenPreferenceDerivedState() {
        let resolvedPreferences = tokenPreferences.isEmpty
            ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
            : tokenPreferences
        cachedResolvedTokenPreferences = resolvedPreferences
        cachedTokenPreferencesByChain = Dictionary(grouping: resolvedPreferences, by: \.chain)
        cachedResolvedTokenPreferencesBySymbol = Dictionary(
            grouping: resolvedPreferences,
            by: { $0.symbol.uppercased() }
        )
        cachedEnabledTrackedTokenPreferences = resolvedPreferences.filter(\.isEnabled)
        cachedTokenPreferenceByChainAndSymbol = resolvedPreferences.reduce(into: [:]) { partialResult, entry in
            partialResult[tokenPreferenceLookupKey(chainName: entry.chain.rawValue, symbol: entry.symbol)] = entry
        }
    }

    func rebuildWalletDerivedState() {
        cachedWalletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        cachedWalletByIDString = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id.uuidString, $0) })
        cachedRefreshableChainNames = Set(wallets.map(\.selectedChain))
        cachedIncludedPortfolioWallets = wallets.filter(\.includeInPortfolioTotal)
        let derivedStatePlan = rustStoreDerivedStatePlan(for: wallets)
        cachedIncludedPortfolioHoldings = derivedStatePlan.includedPortfolioHoldingRefs.compactMap { reference in
            resolveHolding(reference, in: wallets)
        }
        cachedIncludedPortfolioHoldingsBySymbol = Dictionary(
            grouping: cachedIncludedPortfolioHoldings,
            by: { $0.symbol.uppercased() }
        )
        cachedUniqueWalletPriceRequestCoins = derivedStatePlan.uniquePriceRequestHoldingRefs.compactMap { reference in
            resolveHolding(reference, in: wallets)
        }

        var sendCoinsByWalletID: [String: [Coin]] = [:]
        var receiveCoinsByWalletID: [String: [Coin]] = [:]
        var receiveChainsByWalletID: [String: [String]] = [:]
        var sendWallets: [ImportedWallet] = []
        var receiveWallets: [ImportedWallet] = []

        let transferAvailabilityPlan = rustTransferAvailabilityPlan(for: wallets)
        let transferAvailabilityByWalletID = Dictionary(
            uniqueKeysWithValues: transferAvailabilityPlan.wallets.map { ($0.walletID, $0) }
        )
        let rustSendEnabledWalletIDs = Set(transferAvailabilityPlan.sendEnabledWalletIDs)
        let rustReceiveEnabledWalletIDs = Set(transferAvailabilityPlan.receiveEnabledWalletIDs)

        for wallet in wallets {
            let walletID = wallet.id.uuidString
            let sendCoins = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.sendHoldingIndices.compactMap { index in
                        wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil
                    }
                }
                ?? []
            sendCoinsByWalletID[walletID] = sendCoins
            if rustSendEnabledWalletIDs.contains(walletID) {
                sendWallets.append(wallet)
            }

            let receiveCoins = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.receiveHoldingIndices.compactMap { index in
                        wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil
                    }
                }
                ?? []
            receiveCoinsByWalletID[walletID] = receiveCoins

            let receiveChains = transferAvailabilityByWalletID[walletID]?.receiveChains
                ?? []
            receiveChainsByWalletID[walletID] = receiveChains
            if rustReceiveEnabledWalletIDs.contains(walletID) {
                receiveWallets.append(wallet)
            }
        }

        cachedSigningMaterialWalletIDs = Set(
            derivedStatePlan.signingMaterialWalletIDs.compactMap(UUID.init(uuidString:))
        )
        cachedPrivateKeyBackedWalletIDs = Set(
            derivedStatePlan.privateKeyBackedWalletIDs.compactMap(UUID.init(uuidString:))
        )

        cachedPortfolio = derivedStatePlan.groupedPortfolio.compactMap { group in
            guard let representative = resolveHolding(
                WalletRustWalletHoldingRef(walletID: group.walletID, holdingIndex: group.holdingIndex),
                in: wallets
            ) else {
                return nil
            }
            return Coin(
                name: representative.name,
                symbol: representative.symbol,
                marketDataID: representative.marketDataID,
                coinGeckoID: representative.coinGeckoID,
                chainName: representative.chainName,
                tokenStandard: representative.tokenStandard,
                contractAddress: representative.contractAddress,
                amount: Double(group.totalAmount) ?? representative.amount,
                priceUSD: representative.priceUSD,
                mark: representative.mark,
                color: representative.color
            )
        }
        cachedAvailableSendCoinsByWalletID = sendCoinsByWalletID
        cachedAvailableReceiveCoinsByWalletID = receiveCoinsByWalletID
        cachedAvailableReceiveChainsByWalletID = receiveChainsByWalletID
        cachedSendEnabledWallets = sendWallets
        cachedReceiveEnabledWallets = receiveWallets
    }

    func applyWalletCollectionSideEffects() {
        rebuildWalletDerivedState()
        rebuildDashboardDerivedState()
        updateRefreshEngineEntries()
        walletSideEffectsTask?.cancel()
        walletSideEffectsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.persistWallets()
            self.pruneTransactionsForActiveWallets()
            self.walletSideEffectsTask = nil
        }
    }

    func appendTransaction(_ transaction: TransactionRecord) {
        transactions.insert(transaction, at: 0)
    }

    func upsertBitcoinTransactions(_ newTransactions: [TransactionRecord]) {
        upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin")
    }

    func upsertBitcoinCashTransactions(_ newTransactions: [TransactionRecord]) {
        upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin Cash")
    }

    func upsertBitcoinSVTransactions(_ newTransactions: [TransactionRecord]) {
        upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin SV")
    }

    func upsertLitecoinTransactions(_ newTransactions: [TransactionRecord]) {
        upsertStandardUTXOTransactions(newTransactions, chainName: "Litecoin")
    }

    func upsertStandardUTXOTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        if let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions,
            incomingTransactions: newTransactions,
            strategy: .standardUTXO,
            chainName: chainName
        ) {
            setTransactionsIfChanged(mergedTransactions)
            return
        }

        var mergedTransactions = transactions

        for incoming in newTransactions {
            guard incoming.chainName == chainName,
                  let transactionHash = incoming.transactionHash else {
                continue
            }

            if let existingIndex = mergedTransactions.firstIndex(where: { existing in
                existing.chainName == chainName
                    && existing.walletID == incoming.walletID
                    && existing.transactionHash == transactionHash
                    && existing.kind == incoming.kind
            }) {
                let existing = mergedTransactions[existingIndex]
                mergedTransactions[existingIndex] = TransactionRecord(
                    id: existing.id,
                    walletID: incoming.walletID ?? existing.walletID,
                    kind: incoming.kind,
                    status: incoming.status,
                    walletName: incoming.walletName,
                    assetName: incoming.assetName,
                    symbol: incoming.symbol,
                    chainName: incoming.chainName,
                    amount: incoming.amount,
                    address: incoming.address,
                    transactionHash: incoming.transactionHash,
                    ethereumNonce: incoming.ethereumNonce ?? existing.ethereumNonce,
                    receiptBlockNumber: incoming.receiptBlockNumber ?? existing.receiptBlockNumber,
                    receiptGasUsed: existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: existing.receiptNetworkFeeETH,
                    feePriorityRaw: incoming.feePriorityRaw ?? existing.feePriorityRaw,
                    feeRateDescription: incoming.feeRateDescription ?? existing.feeRateDescription,
                    confirmationCount: incoming.confirmationCount ?? existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: incoming.usedChangeOutput ?? existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: existing.sourceDerivationPath,
                    changeDerivationPath: existing.changeDerivationPath,
                    sourceAddress: incoming.sourceAddress ?? existing.sourceAddress,
                    changeAddress: incoming.changeAddress ?? existing.changeAddress,
                    dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex,
                    signedTransactionPayload: incoming.signedTransactionPayload ?? existing.signedTransactionPayload,
                    signedTransactionPayloadFormat: incoming.signedTransactionPayloadFormat ?? existing.signedTransactionPayloadFormat,
                    failureReason: existing.failureReason,
                    transactionHistorySource: incoming.transactionHistorySource ?? existing.transactionHistorySource,
                    createdAt: incoming.createdAt
                )
            } else {
                mergedTransactions.append(incoming)
            }
        }

        let sortedTransactions = mergedTransactions.sorted(by: { $0.createdAt > $1.createdAt })
        setTransactionsIfChanged(sortedTransactions)
    }

    func upsertDogecoinTransactions(_ newTransactions: [TransactionRecord]) {
        if let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions,
            incomingTransactions: newTransactions,
            strategy: .dogecoin,
            chainName: "Dogecoin"
        ) {
            setTransactionsIfChanged(mergedTransactions)
            return
        }

        var mergedTransactions = transactions

        for incoming in newTransactions {
            guard incoming.chainName == "Dogecoin",
                  let incomingWalletID = incoming.walletID,
                  let transactionHash = incoming.transactionHash else {
                continue
            }

            if let existingIndex = mergedTransactions.firstIndex(where: { existing in
                existing.chainName == "Dogecoin"
                    && existing.walletID == incomingWalletID
                    && existing.transactionHash == transactionHash
                    && existing.kind == incoming.kind
            }) {
                let existing = mergedTransactions[existingIndex]
                mergedTransactions[existingIndex] = TransactionRecord(
                    id: existing.id,
                    walletID: incoming.walletID ?? existing.walletID,
                    kind: incoming.kind,
                    status: incoming.status,
                    walletName: incoming.walletName,
                    assetName: incoming.assetName,
                    symbol: incoming.symbol,
                    chainName: incoming.chainName,
                    amount: incoming.amount,
                    address: incoming.address,
                    transactionHash: incoming.transactionHash,
                    ethereumNonce: incoming.ethereumNonce ?? existing.ethereumNonce,
                    receiptBlockNumber: incoming.receiptBlockNumber ?? existing.receiptBlockNumber,
                    receiptGasUsed: existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: existing.receiptNetworkFeeETH,
                    feePriorityRaw: incoming.feePriorityRaw ?? existing.feePriorityRaw,
                    feeRateDescription: incoming.feeRateDescription ?? existing.feeRateDescription,
                    confirmationCount: incoming.confirmationCount ?? existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: incoming.dogecoinConfirmedNetworkFeeDOGE ?? existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: incoming.dogecoinConfirmations ?? existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: incoming.dogecoinFeePriorityRaw ?? existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: incoming.dogecoinEstimatedFeeRateDOGEPerKB ?? existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: incoming.usedChangeOutput ?? existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: incoming.dogecoinUsedChangeOutput ?? existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: incoming.sourceDerivationPath ?? existing.sourceDerivationPath,
                    changeDerivationPath: incoming.changeDerivationPath ?? existing.changeDerivationPath,
                    sourceAddress: incoming.sourceAddress ?? existing.sourceAddress,
                    changeAddress: incoming.changeAddress ?? existing.changeAddress,
                    dogecoinRawTransactionHex: incoming.dogecoinRawTransactionHex ?? existing.dogecoinRawTransactionHex,
                    signedTransactionPayload: incoming.signedTransactionPayload ?? existing.signedTransactionPayload,
                    signedTransactionPayloadFormat: incoming.signedTransactionPayloadFormat ?? existing.signedTransactionPayloadFormat,
                    failureReason: incoming.failureReason ?? existing.failureReason,
                    transactionHistorySource: incoming.transactionHistorySource ?? existing.transactionHistorySource,
                    createdAt: incoming.createdAt
                )
            } else {
                mergedTransactions.append(incoming)
            }
        }

        mergedTransactions.sort { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
        setTransactionsIfChanged(mergedTransactions)
    }

    func upsertEthereumTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Ethereum")
    }

    func upsertArbitrumTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Arbitrum")
    }

    func upsertOptimismTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Optimism")
    }

    func upsertBNBTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "BNB Chain")
    }

    func upsertAvalancheTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Avalanche")
    }

    func upsertETCTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Ethereum Classic")
    }

    func upsertHyperliquidTransactions(_ newTransactions: [TransactionRecord]) {
        upsertEVMTransactions(newTransactions, chainName: "Hyperliquid")
    }

    func upsertTronTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Tron", includeSymbolInIdentity: true)
    }

    func upsertSolanaTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Solana")
    }

    func upsertCardanoTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Cardano")
    }

    func upsertXRPTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "XRP Ledger")
    }

    func upsertStellarTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Stellar")
    }

    func upsertMoneroTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Monero")
    }

    func upsertSuiTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Sui")
    }

    func upsertAptosTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Aptos")
    }

    func upsertTONTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "TON")
    }

    func upsertICPTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Internet Computer")
    }

    func upsertNearTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "NEAR")
    }

    func upsertPolkadotTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Polkadot")
    }

    func upsertAccountBasedTransactions(
        _ newTransactions: [TransactionRecord],
        chainName: String,
        includeSymbolInIdentity: Bool = false
    ) {
        if let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions,
            incomingTransactions: newTransactions,
            strategy: .accountBased,
            chainName: chainName,
            includeSymbolInIdentity: includeSymbolInIdentity,
            preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
        ) {
            setTransactionsIfChanged(mergedTransactions)
            return
        }

        var mergedTransactions = transactions

        for incoming in newTransactions {
            guard incoming.chainName == chainName,
                  let incomingWalletID = incoming.walletID,
                  let transactionHash = incoming.transactionHash else {
                continue
            }

            if let existingIndex = mergedTransactions.firstIndex(where: { existing in
                existing.chainName == chainName
                    && existing.transactionHash == transactionHash
                    && existing.kind == incoming.kind
                    && (!includeSymbolInIdentity || existing.symbol == incoming.symbol)
                    && existing.walletID == incomingWalletID
            }) {
                let existing = mergedTransactions[existingIndex]
                mergedTransactions[existingIndex] = TransactionRecord(
                    id: existing.id,
                    walletID: incoming.walletID ?? existing.walletID,
                    kind: incoming.kind,
                    status: incoming.status,
                    walletName: incoming.walletName,
                    assetName: incoming.assetName,
                    symbol: incoming.symbol,
                    chainName: incoming.chainName,
                    amount: incoming.amount,
                    address: incoming.address,
                    transactionHash: incoming.transactionHash,
                    ethereumNonce: existing.ethereumNonce,
                    receiptBlockNumber: incoming.receiptBlockNumber ?? existing.receiptBlockNumber,
                    receiptGasUsed: existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: existing.receiptNetworkFeeETH,
                    feePriorityRaw: incoming.feePriorityRaw ?? existing.feePriorityRaw,
                    feeRateDescription: incoming.feeRateDescription ?? existing.feeRateDescription,
                    confirmationCount: incoming.confirmationCount ?? existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: incoming.usedChangeOutput ?? existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: existing.sourceDerivationPath,
                    changeDerivationPath: existing.changeDerivationPath,
                    sourceAddress: incoming.sourceAddress ?? existing.sourceAddress,
                    changeAddress: incoming.changeAddress ?? existing.changeAddress,
                    dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex,
                    signedTransactionPayload: incoming.signedTransactionPayload ?? existing.signedTransactionPayload,
                    signedTransactionPayloadFormat: incoming.signedTransactionPayloadFormat ?? existing.signedTransactionPayloadFormat,
                    failureReason: incoming.failureReason ?? existing.failureReason,
                    transactionHistorySource: incoming.transactionHistorySource ?? existing.transactionHistorySource,
                    createdAt: incoming.createdAt == Date.distantPast ? existing.createdAt : incoming.createdAt
                )
            } else {
                mergedTransactions.append(incoming)
            }
        }

        mergedTransactions.sort { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
        setTransactionsIfChanged(mergedTransactions)
    }

    func upsertEVMTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        if let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions,
            incomingTransactions: newTransactions,
            strategy: .evm,
            chainName: chainName,
            preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
        ) {
            setTransactionsIfChanged(mergedTransactions)
            return
        }

        var mergedTransactions = transactions

        for incoming in newTransactions {
            guard incoming.chainName == chainName,
                  let incomingWalletID = incoming.walletID,
                  let transactionHash = incoming.transactionHash else {
                continue
            }

            if let existingIndex = mergedTransactions.firstIndex(where: { existing in
                existing.chainName == chainName
                    && existing.transactionHash == transactionHash
                    && existing.kind == incoming.kind
                    && existing.symbol == incoming.symbol
                    && normalizeEVMAddress(existing.address) == normalizeEVMAddress(incoming.address)
                    && abs(existing.amount - incoming.amount) < 0.0000000001
                    && existing.walletID == incomingWalletID
            }) {
                let existing = mergedTransactions[existingIndex]
                mergedTransactions[existingIndex] = TransactionRecord(
                    id: existing.id,
                    walletID: incoming.walletID ?? existing.walletID,
                    kind: incoming.kind,
                    status: incoming.status,
                    walletName: incoming.walletName,
                    assetName: incoming.assetName,
                    symbol: incoming.symbol,
                    chainName: incoming.chainName,
                    amount: incoming.amount,
                    address: incoming.address,
                    transactionHash: incoming.transactionHash,
                    ethereumNonce: incoming.ethereumNonce ?? existing.ethereumNonce,
                    receiptBlockNumber: incoming.receiptBlockNumber ?? existing.receiptBlockNumber,
                    receiptGasUsed: incoming.receiptGasUsed ?? existing.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: incoming.receiptEffectiveGasPriceGwei ?? existing.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: incoming.receiptNetworkFeeETH ?? existing.receiptNetworkFeeETH,
                    feePriorityRaw: incoming.feePriorityRaw ?? existing.feePriorityRaw,
                    feeRateDescription: incoming.feeRateDescription ?? existing.feeRateDescription,
                    confirmationCount: incoming.confirmationCount ?? existing.confirmationCount,
                    dogecoinConfirmedNetworkFeeDOGE: existing.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: existing.dogecoinConfirmations,
                    dogecoinFeePriorityRaw: existing.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: existing.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: incoming.usedChangeOutput ?? existing.usedChangeOutput,
                    dogecoinUsedChangeOutput: existing.dogecoinUsedChangeOutput,
                    sourceDerivationPath: existing.sourceDerivationPath,
                    changeDerivationPath: existing.changeDerivationPath,
                    sourceAddress: existing.sourceAddress,
                    changeAddress: existing.changeAddress,
                    dogecoinRawTransactionHex: existing.dogecoinRawTransactionHex,
                    signedTransactionPayload: incoming.signedTransactionPayload ?? existing.signedTransactionPayload,
                    signedTransactionPayloadFormat: incoming.signedTransactionPayloadFormat ?? existing.signedTransactionPayloadFormat,
                    failureReason: incoming.failureReason ?? existing.failureReason,
                    transactionHistorySource: incoming.transactionHistorySource ?? existing.transactionHistorySource,
                    createdAt: incoming.createdAt == Date.distantPast ? existing.createdAt : incoming.createdAt
                )
            } else {
                mergedTransactions.append(incoming)
            }
        }

        mergedTransactions.sort { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
        setTransactionsIfChanged(mergedTransactions)
    }

    func markChainHealthy(_ chainName: String) {
        diagnostics.markChainHealthy(chainName)
    }

    func noteChainSuccessfulSync(_ chainName: String) {
        diagnostics.noteChainSuccessfulSync(chainName)
    }

    func normalizedWalletChainName(_ chainName: String) -> String {
        WalletChainID(chainName)?.displayName ?? chainName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearDeletedWalletDiagnostics(
        walletID: UUID,
        chainName: String,
        hasRemainingWalletsOnChain: Bool
    ) {
        diagnostics.operationalLogs.removeAll { event in
            if event.walletID == walletID {
                return true
            }
            guard !hasRemainingWalletsOnChain else { return false }
            return normalizedWalletChainName(event.chainName ?? "") == chainName
        }

        guard !hasRemainingWalletsOnChain else { return }
        markChainHealthy(chainName)
        chainOperationalEventsByChain[chainName] = nil
        lastHistoryRefreshAtByChain[chainName] = nil
    }

    func clearHistoryTracking(for walletID: UUID) {
        resetHistoryPaginationForWallet(walletID)
        dogecoinHistoryDiagnosticsByWallet[walletID] = nil
        bitcoinHistoryDiagnosticsByWallet[walletID] = nil
        bitcoinCashHistoryDiagnosticsByWallet[walletID] = nil
        bitcoinSVHistoryDiagnosticsByWallet[walletID] = nil
        litecoinHistoryDiagnosticsByWallet[walletID] = nil
        ethereumHistoryDiagnosticsByWallet[walletID] = nil
        arbitrumHistoryDiagnosticsByWallet[walletID] = nil
        optimismHistoryDiagnosticsByWallet[walletID] = nil
        etcHistoryDiagnosticsByWallet[walletID] = nil
        bnbHistoryDiagnosticsByWallet[walletID] = nil
        avalancheHistoryDiagnosticsByWallet[walletID] = nil
        hyperliquidHistoryDiagnosticsByWallet[walletID] = nil
        tronHistoryDiagnosticsByWallet[walletID] = nil
        solanaHistoryDiagnosticsByWallet[walletID] = nil
        cardanoHistoryDiagnosticsByWallet[walletID] = nil
        xrpHistoryDiagnosticsByWallet[walletID] = nil
        stellarHistoryDiagnosticsByWallet[walletID] = nil
        moneroHistoryDiagnosticsByWallet[walletID] = nil
        suiHistoryDiagnosticsByWallet[walletID] = nil
        aptosHistoryDiagnosticsByWallet[walletID] = nil
        tonHistoryDiagnosticsByWallet[walletID] = nil
        icpHistoryDiagnosticsByWallet[walletID] = nil
        nearHistoryDiagnosticsByWallet[walletID] = nil
        polkadotHistoryDiagnosticsByWallet[walletID] = nil
    }

    private func mergeTransactionsUsingRust(
        existingTransactions: [TransactionRecord],
        incomingTransactions: [TransactionRecord],
        strategy: WalletRustTransactionMergeStrategy,
        chainName: String,
        includeSymbolInIdentity: Bool = false,
        preserveCreatedAtSentinelUnix: Double? = nil
    ) -> [TransactionRecord]? {
        let request = WalletRustTransactionMergeRequest(
            existingTransactions: existingTransactions.map(\.rustBridgeRecord),
            incomingTransactions: incomingTransactions.map(\.rustBridgeRecord),
            strategy: strategy,
            chainName: chainName,
            includeSymbolInIdentity: includeSymbolInIdentity,
            preserveCreatedAtSentinelUnix: preserveCreatedAtSentinelUnix
        )

        guard let mergedRecords = try? WalletRustAppCoreBridge.mergeTransactions(request) else {
            return nil
        }
        var resolvedTransactions: [TransactionRecord] = []
        resolvedTransactions.reserveCapacity(mergedRecords.count)
        for record in mergedRecords {
            guard let transaction = record.transactionRecord else {
                return nil
            }
            resolvedTransactions.append(transaction)
        }
        return resolvedTransactions
    }

    func persistTransactionsFullSync() {
        do {
            let snapshots = transactions.map(\.persistedSnapshot)
            try HistoryDatabaseStore.shared.replaceAll(with: snapshots)

        } catch {
        }
    }

    func persistTransactionsDelta(from oldRecords: [TransactionRecord], to newRecords: [TransactionRecord]) {
        let oldIDs = Set(oldRecords.map(\.id))
        let newIDs = Set(newRecords.map(\.id))
        let deletedIDs = Array(oldIDs.subtracting(newIDs))
        let upsertSnapshots = newRecords.map(\.persistedSnapshot)

        if deletedIDs.isEmpty && upsertSnapshots.isEmpty {
            return
        }

        do {
            try HistoryDatabaseStore.shared.delete(ids: deletedIDs)
            try HistoryDatabaseStore.shared.upsert(records: upsertSnapshots)

        } catch {
            persistTransactionsFullSync()
        }
    }

    func loadPersistedTransactions() -> [TransactionRecord] {
        do {
            let persistedFromDatabase = try HistoryDatabaseStore.shared.fetchAll()
            return persistedFromDatabase.map(TransactionRecord.init(snapshot:))
        } catch {
            return []
        }
    }

    func persistDogecoinKeypoolState() {
        // Legacy UserDefaults write (kept as fallback during SQLite migration).
        let payload = PersistedDogecoinKeypoolStore(
            version: PersistedDogecoinKeypoolStore.currentVersion,
            keypoolByWalletID: dogecoinKeypoolByWalletID
        )
        persistCodableToUserDefaults(payload, key: Self.dogecoinKeypoolDefaultsKey)
        // Write-through to Rust SQLite (authoritative on next launch).
        persistKeypoolToRust(chainName: "Dogecoin", walletMap: dogecoinKeypoolByWalletID.mapValues {
            ChainKeypoolState(nextExternalIndex: $0.nextExternalIndex, nextChangeIndex: $0.nextChangeIndex, reservedReceiveIndex: $0.reservedReceiveIndex)
        })
    }

    func loadDogecoinKeypoolState() -> [UUID: DogecoinKeypoolState] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedDogecoinKeypoolStore.self,
            key: Self.dogecoinKeypoolDefaultsKey
        ) else {
            return [:]
        }
        guard payload.version == PersistedDogecoinKeypoolStore.currentVersion else {
            return [:]
        }
        return payload.keypoolByWalletID
    }

    func persistChainKeypoolState() {
        // Legacy UserDefaults write (kept as fallback during SQLite migration).
        let payload = PersistedChainKeypoolStore(
            version: PersistedChainKeypoolStore.currentVersion,
            keypoolByChain: chainKeypoolByChain
        )
        persistCodableToUserDefaults(payload, key: Self.chainKeypoolDefaultsKey)
        // Write-through to Rust SQLite.
        for (chainName, walletMap) in chainKeypoolByChain {
            persistKeypoolToRust(chainName: chainName, walletMap: walletMap)
        }
    }

    func loadChainKeypoolState() -> [String: [UUID: ChainKeypoolState]] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedChainKeypoolStore.self,
            key: Self.chainKeypoolDefaultsKey
        ) else {
            return [:]
        }
        guard payload.version == PersistedChainKeypoolStore.currentVersion else {
            return [:]
        }
        return payload.keypoolByChain
    }

    func persistDogecoinOwnedAddressMap() {
        // Legacy UserDefaults write (kept as fallback during SQLite migration).
        let payload = PersistedDogecoinOwnedAddressStore(
            version: PersistedDogecoinOwnedAddressStore.currentVersion,
            addressMap: dogecoinOwnedAddressMap
        )
        persistCodableToUserDefaults(payload, key: Self.dogecoinOwnedAddressMapDefaultsKey)
        // Write-through to Rust SQLite.
        for (_, record) in dogecoinOwnedAddressMap {
            persistOwnedAddressToRust(
                walletId: record.walletID.uuidString,
                chainName: "Dogecoin",
                address: record.address ?? "",
                derivationPath: record.derivationPath,
                branch: record.branch,
                branchIndex: record.index
            )
        }
    }

    func loadDogecoinOwnedAddressMap() -> [String: DogecoinOwnedAddressRecord] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedDogecoinOwnedAddressStore.self,
            key: Self.dogecoinOwnedAddressMapDefaultsKey
        ) else {
            return [:]
        }
        guard payload.version == PersistedDogecoinOwnedAddressStore.currentVersion else {
            return [:]
        }
        return payload.addressMap
    }

    func persistChainOwnedAddressMap() {
        // Legacy UserDefaults write (kept as fallback during SQLite migration).
        let payload = PersistedChainOwnedAddressStore(
            version: PersistedChainOwnedAddressStore.currentVersion,
            addressMapByChain: chainOwnedAddressMapByChain
        )
        persistCodableToUserDefaults(payload, key: Self.chainOwnedAddressMapDefaultsKey)
        // Write-through to Rust SQLite.
        for (chainName, addressMap) in chainOwnedAddressMapByChain {
            for (_, record) in addressMap {
                persistOwnedAddressToRust(
                    walletId: record.walletID.uuidString,
                    chainName: chainName,
                    address: record.address ?? "",
                    derivationPath: record.derivationPath,
                    branch: record.branch,
                    branchIndex: record.index
                )
            }
        }
    }

    func loadChainOwnedAddressMap() -> [String: [String: ChainOwnedAddressRecord]] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedChainOwnedAddressStore.self,
            key: Self.chainOwnedAddressMapDefaultsKey
        ) else {
            return [:]
        }
        guard payload.version == PersistedChainOwnedAddressStore.currentVersion else {
            return [:]
        }
        return payload.addressMapByChain
    }

    // MARK: - Rust SQLite write-through helpers

    /// Persist all wallets' keypool state for one chain to Rust SQLite.
    private func persistKeypoolToRust(chainName: String, walletMap: [UUID: ChainKeypoolState]) {
        for (walletID, state) in walletMap {
            // Rust expects camelCase JSON matching the KeypoolState struct.
            let json = """
            {"nextExternalIndex":\(state.nextExternalIndex),"nextChangeIndex":\(state.nextChangeIndex),"reservedReceiveIndex":\(state.reservedReceiveIndex.map(String.init) ?? "null")}
            """
            WalletServiceBridge.shared.saveKeypoolState(
                walletId: walletID.uuidString, chainName: chainName, stateJSON: json
            )
        }
    }

    /// Persist a single owned address record to Rust SQLite.
    private func persistOwnedAddressToRust(
        walletId: String,
        chainName: String,
        address: String,
        derivationPath: String?,
        branch: String?,
        branchIndex: Int?
    ) {
        guard !address.isEmpty else { return }
        let pathJSON = derivationPath.map { "\"\($0)\"" } ?? "null"
        let branchJSON = branch.map { "\"\($0)\"" } ?? "null"
        let indexJSON = branchIndex.map(String.init) ?? "null"
        let json = """
        {"walletId":"\(walletId)","chainName":"\(chainName)","address":"\(address)","derivationPath":\(pathJSON),"branch":\(branchJSON),"branchIndex":\(indexJSON)}
        """
        WalletServiceBridge.shared.saveOwnedAddress(recordJSON: json)
    }
}

private extension TransactionRecord {
    var rustBridgeRecord: WalletRustTransactionRecord {
        WalletRustTransactionRecord(
            id: id.uuidString,
            walletID: walletID?.uuidString,
            kind: kind.rawValue,
            status: status.rawValue,
            walletName: walletName,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber,
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: receiptNetworkFeeETH,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations,
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAtUnix: createdAt.timeIntervalSince1970
        )
    }
}

private extension WalletRustTransactionRecord {
    var transactionRecord: TransactionRecord? {
        guard let resolvedID = UUID(uuidString: id) else {
            return nil
        }

        let resolvedWalletID = walletID.flatMap(UUID.init(uuidString:))
        let resolvedKind = TransactionKind(rawValue: kind) ?? .receive
        let resolvedStatus = TransactionStatus(rawValue: status) ?? .pending

        return TransactionRecord(
            id: resolvedID,
            walletID: resolvedWalletID,
            kind: resolvedKind,
            status: resolvedStatus,
            walletName: walletName,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber,
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: receiptNetworkFeeETH,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations,
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAt: Date(timeIntervalSince1970: createdAtUnix)
        )
    }
}

private extension WalletStore {
    func rustStoreDerivedStatePlan(
        for wallets: [ImportedWallet]
    ) -> WalletRustStoreDerivedStatePlan {
        let request = WalletRustStoreDerivedStateRequest(
            wallets: wallets.map { wallet in
                let signingMaterial = signingMaterialAvailability(for: wallet.id)
                return WalletRustStoreDerivedWalletInput(
                    walletID: wallet.id.uuidString,
                    includeInPortfolioTotal: wallet.includeInPortfolioTotal,
                    hasSigningMaterial: signingMaterial.hasSigningMaterial,
                    isPrivateKeyBacked: signingMaterial.isPrivateKeyBacked,
                    holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustStoreDerivedHoldingInput(
                            holdingIndex: index,
                            assetIdentityKey: assetIdentityKey(for: holding),
                            symbolUpper: holding.symbol.uppercased(),
                            amount: String(holding.amount),
                            isPricedAsset: isPricedAsset(holding)
                        )
                    }
                )
            }
        )
        do {
            return try WalletRustAppCoreBridge.planStoreDerivedState(request)
        } catch {
            assertionFailure("Rust store derived-state planning failed: \(error)")
            return WalletRustStoreDerivedStatePlan(
                includedPortfolioHoldingRefs: [],
                uniquePriceRequestHoldingRefs: [],
                groupedPortfolio: [],
                signingMaterialWalletIDs: [],
                privateKeyBackedWalletIDs: []
            )
        }
    }

    func resolveHolding(
        _ reference: WalletRustWalletHoldingRef,
        in wallets: [ImportedWallet]
    ) -> Coin? {
        guard let wallet = cachedWalletByIDString[reference.walletID]
            ?? wallets.first(where: { $0.id.uuidString == reference.walletID }),
              wallet.holdings.indices.contains(reference.holdingIndex) else {
            return nil
        }
        return wallet.holdings[reference.holdingIndex]
    }

    func rustTransferAvailabilityPlan(
        for wallets: [ImportedWallet]
    ) -> WalletRustTransferAvailabilityPlan {
        let request = WalletRustTransferAvailabilityRequest(
            wallets: wallets.map { wallet in
                let hasSigningMaterial = signingMaterialAvailability(for: wallet.id).hasSigningMaterial
                return WalletRustTransferWalletInput(
                    walletID: wallet.id.uuidString,
                    hasSigningMaterial: hasSigningMaterial,
                    holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustTransferHoldingInput(
                            index: index,
                            chainName: holding.chainName,
                            symbol: holding.symbol,
                            supportsSend: ChainBackendRegistry.supportsSend(for: holding.chainName),
                            supportsReceiveAddress: ChainBackendRegistry.supportsReceiveAddress(for: holding.chainName),
                            isLiveChain: ChainBackendRegistry.liveChainNames.contains(holding.chainName),
                            supportsEVMToken: supportedEVMToken(for: holding) != nil,
                            supportsSolanaSendCoin: isSupportedSolanaSendCoin(holding)
                        )
                    }
                )
            }
        )
        do {
            return try WalletRustAppCoreBridge.planTransferAvailability(request)
        } catch {
            assertionFailure("Rust transfer availability planning failed: \(error)")
            return WalletRustTransferAvailabilityPlan(
                wallets: [],
                sendEnabledWalletIDs: [],
                receiveEnabledWalletIDs: []
            )
        }
    }
}
