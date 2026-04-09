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
        cachedIncludedPortfolioHoldings = cachedIncludedPortfolioWallets.flatMap(\.holdings)
        cachedIncludedPortfolioHoldingsBySymbol = Dictionary(
            grouping: cachedIncludedPortfolioHoldings,
            by: { $0.symbol.uppercased() }
        )
        var uniqueWalletPriceRequestCoinsByHoldingKey: [String: Coin] = [:]
        var uniqueWalletPriceRequestCoinOrder: [String] = []
        for coin in wallets.flatMap(\.holdings) where isPricedAsset(coin) {
            let key = assetIdentityKey(for: coin)
            guard uniqueWalletPriceRequestCoinsByHoldingKey[key] == nil else { continue }
            uniqueWalletPriceRequestCoinsByHoldingKey[key] = coin
            uniqueWalletPriceRequestCoinOrder.append(key)
        }
        cachedUniqueWalletPriceRequestCoins = uniqueWalletPriceRequestCoinOrder.compactMap { uniqueWalletPriceRequestCoinsByHoldingKey[$0] }

        var groupedPortfolio: [String: Coin] = [:]
        var portfolioOrder: [String] = []
        var sendCoinsByWalletID: [String: [Coin]] = [:]
        var receiveCoinsByWalletID: [String: [Coin]] = [:]
        var receiveChainsByWalletID: [String: [String]] = [:]
        var sendWallets: [ImportedWallet] = []
        var receiveWallets: [ImportedWallet] = []
        var signingMaterialWalletIDs: Set<UUID> = []
        var privateKeyBackedWalletIDs: Set<UUID> = []

        for wallet in wallets {
            let walletID = wallet.id.uuidString
            let signingMaterial = signingMaterialAvailability(for: wallet.id)
            if signingMaterial.hasSigningMaterial {
                signingMaterialWalletIDs.insert(wallet.id)
            }
            if signingMaterial.isPrivateKeyBacked {
                privateKeyBackedWalletIDs.insert(wallet.id)
            }
            let sendCoins = WalletTransferAvailabilityCoordinator.availableSendCoins(
                in: wallet,
                hasSigningMaterial: signingMaterial.hasSigningMaterial,
                supportsEVMToken: { [self] coin in supportedEVMToken(for: coin) != nil },
                supportsSolanaSendCoin: { [self] coin in isSupportedSolanaSendCoin(coin) }
            )
            sendCoinsByWalletID[walletID] = sendCoins
            if !sendCoins.isEmpty {
                sendWallets.append(wallet)
            }

            let receiveCoins = WalletTransferAvailabilityCoordinator.availableReceiveCoins(in: wallet)
            receiveCoinsByWalletID[walletID] = receiveCoins

            let receiveChains = WalletTransferAvailabilityCoordinator.availableReceiveChains(for: receiveCoins)
            receiveChainsByWalletID[walletID] = receiveChains
            if !receiveCoins.isEmpty {
                receiveWallets.append(wallet)
            }
        }

        cachedSigningMaterialWalletIDs = signingMaterialWalletIDs
        cachedPrivateKeyBackedWalletIDs = privateKeyBackedWalletIDs

        for coin in cachedIncludedPortfolioHoldings {
            let key = assetIdentityKey(for: coin)
            if let existing = groupedPortfolio[key] {
                groupedPortfolio[key] = Coin(
                    name: existing.name,
                    symbol: existing.symbol,
                    marketDataID: existing.marketDataID,
                    coinGeckoID: existing.coinGeckoID,
                    chainName: existing.chainName,
                    tokenStandard: existing.tokenStandard,
                    contractAddress: existing.contractAddress,
                    amount: existing.amount + coin.amount,
                    priceUSD: coin.priceUSD,
                    mark: existing.mark,
                    color: existing.color
                )
            } else {
                groupedPortfolio[key] = coin
                portfolioOrder.append(key)
            }
        }

        cachedPortfolio = portfolioOrder.compactMap { groupedPortfolio[$0] }
        cachedAvailableSendCoinsByWalletID = sendCoinsByWalletID
        cachedAvailableReceiveCoinsByWalletID = receiveCoinsByWalletID
        cachedAvailableReceiveChainsByWalletID = receiveChainsByWalletID
        cachedSendEnabledWallets = sendWallets
        cachedReceiveEnabledWallets = receiveWallets
    }

    func applyWalletCollectionSideEffects() {
        rebuildWalletDerivedState()
        rebuildDashboardDerivedState()
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
                    && EthereumWalletEngine.normalizeAddress(existing.address) == EthereumWalletEngine.normalizeAddress(incoming.address)
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
        bitcoinHistoryCursorByWallet[walletID] = nil
        bitcoinCashHistoryCursorByWallet[walletID] = nil
        bitcoinSVHistoryCursorByWallet[walletID] = nil
        litecoinHistoryCursorByWallet[walletID] = nil
        dogecoinHistoryCursorByWallet[walletID] = nil
        tronHistoryCursorByWallet[walletID] = nil
        ethereumHistoryPageByWallet[walletID] = nil
        arbitrumHistoryPageByWallet[walletID] = nil
        optimismHistoryPageByWallet[walletID] = nil
        bnbHistoryPageByWallet[walletID] = nil
        hyperliquidHistoryPageByWallet[walletID] = nil
        exhaustedBitcoinHistoryWalletIDs.remove(walletID)
        exhaustedBitcoinCashHistoryWalletIDs.remove(walletID)
        exhaustedBitcoinSVHistoryWalletIDs.remove(walletID)
        exhaustedLitecoinHistoryWalletIDs.remove(walletID)
        exhaustedDogecoinHistoryWalletIDs.remove(walletID)
        exhaustedEthereumHistoryWalletIDs.remove(walletID)
        exhaustedArbitrumHistoryWalletIDs.remove(walletID)
        exhaustedOptimismHistoryWalletIDs.remove(walletID)
        exhaustedBNBHistoryWalletIDs.remove(walletID)
        exhaustedHyperliquidHistoryWalletIDs.remove(walletID)
        exhaustedTronHistoryWalletIDs.remove(walletID)
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
        let payload = PersistedDogecoinKeypoolStore(
            version: PersistedDogecoinKeypoolStore.currentVersion,
            keypoolByWalletID: dogecoinKeypoolByWalletID
        )
        persistCodableToUserDefaults(payload, key: Self.dogecoinKeypoolDefaultsKey)
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
        let payload = PersistedChainKeypoolStore(
            version: PersistedChainKeypoolStore.currentVersion,
            keypoolByChain: chainKeypoolByChain
        )
        persistCodableToUserDefaults(payload, key: Self.chainKeypoolDefaultsKey)
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
        let payload = PersistedDogecoinOwnedAddressStore(
            version: PersistedDogecoinOwnedAddressStore.currentVersion,
            addressMap: dogecoinOwnedAddressMap
        )
        persistCodableToUserDefaults(payload, key: Self.dogecoinOwnedAddressMapDefaultsKey)
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
        let payload = PersistedChainOwnedAddressStore(
            version: PersistedChainOwnedAddressStore.currentVersion,
            addressMapByChain: chainOwnedAddressMapByChain
        )
        persistCodableToUserDefaults(payload, key: Self.chainOwnedAddressMapDefaultsKey)
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
