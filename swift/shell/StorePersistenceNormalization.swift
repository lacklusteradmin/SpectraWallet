import Foundation
private nonisolated func historyRecordEncodeInputs(
    _ snapshots: [CorePersistedTransactionRecord]
) -> [HistoryRecordEncodeInput]? {
    do {
        return try snapshots.map { snap in
            HistoryRecordEncodeInput(
                id: snap.id.lowercased(),
                walletId: snap.walletId?.lowercased(),
                chainName: snap.chainName,
                txHash: snap.transactionHash?.lowercased(),
                createdAt: Date(timeIntervalSinceReferenceDate: snap.createdAt).timeIntervalSince1970,
                payloadJson: try encodePersistedTransactionRecordJson(value: snap)
            )
        }
    } catch {
        return nil
    }
}
extension AppState {
    func rebuildTokenPreferenceDerivedState() {
        batchCacheUpdates {
            let resolvedPreferences =
                tokenPreferences.isEmpty ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry) : tokenPreferences
            cachedResolvedTokenPreferences = resolvedPreferences
            cachedTokenPreferencesByChain = Dictionary(grouping: resolvedPreferences, by: \.chain)
            cachedResolvedTokenPreferencesBySymbol = Dictionary(
                grouping: resolvedPreferences, by: { $0.symbol.uppercased() }
            )
            cachedEnabledTrackedTokenPreferences = resolvedPreferences.filter(\.isEnabled)
            cachedTokenPreferenceByChainAndSymbol = resolvedPreferences.reduce(into: [:]) { partialResult, entry in
                partialResult[tokenPreferenceLookupKey(chainName: entry.chain.rawValue, symbol: entry.symbol)] = entry
            }
        }
    }
    func rebuildWalletDerivedState() { batchCacheUpdates { _rebuildWalletDerivedStateBody() } }
    private func _rebuildWalletDerivedStateBody() {
        cachedWalletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        cachedWalletByIDString = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        cachedRefreshableChainNames = Set(wallets.map(\.selectedChain))
        cachedIncludedPortfolioWallets = wallets.filter(\.includeInPortfolioTotal)
        let derivedStatePlan = rustStoreDerivedStatePlan(for: wallets)
        cachedIncludedPortfolioHoldings = derivedStatePlan.includedPortfolioHoldingRefs.compactMap { reference in
            resolveHolding(reference, in: wallets)
        }
        cachedIncludedPortfolioHoldingsBySymbol = Dictionary(
            grouping: cachedIncludedPortfolioHoldings, by: { $0.symbol.uppercased() }
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
            uniqueKeysWithValues: transferAvailabilityPlan.wallets.map { ($0.walletId, $0) }
        )
        let rustSendEnabledWalletIDs = Set(transferAvailabilityPlan.sendEnabledWalletIds)
        let rustReceiveEnabledWalletIDs = Set(transferAvailabilityPlan.receiveEnabledWalletIds)
        for wallet in wallets {
            let walletID = wallet.id
            let sendCoins: [Coin] =
                transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.sendHoldingIndices.compactMap { i -> Coin? in
                        let index = Int(i); return wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil
                    }
                }
                ?? []
            sendCoinsByWalletID[walletID] = sendCoins
            if rustSendEnabledWalletIDs.contains(walletID) { sendWallets.append(wallet) }
            let receiveCoins: [Coin] =
                transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.receiveHoldingIndices.compactMap { i -> Coin? in
                        let index = Int(i); return wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil
                    }
                }
                ?? []
            receiveCoinsByWalletID[walletID] = receiveCoins
            let receiveChains =
                transferAvailabilityByWalletID[walletID]?.receiveChains
                ?? []
            receiveChainsByWalletID[walletID] = receiveChains
            if rustReceiveEnabledWalletIDs.contains(walletID) { receiveWallets.append(wallet) }
        }
        cachedSigningMaterialWalletIDs = Set(derivedStatePlan.signingMaterialWalletIds)
        cachedPrivateKeyBackedWalletIDs = Set(derivedStatePlan.privateKeyBackedWalletIds)
        cachedPortfolio = derivedStatePlan.groupedPortfolio.compactMap { group in
            guard
                let representative = resolveHolding(
                    WalletHoldingRef(walletId: group.walletId, holdingIndex: group.holdingIndex), in: wallets
                )
            else {
                return nil
            }
            return Coin.makeCustom(
                name: representative.name, symbol: representative.symbol,
                coinGeckoId: representative.coinGeckoId, chainName: representative.chainName, tokenStandard: representative.tokenStandard,
                contractAddress: representative.contractAddress, amount: Double(group.totalAmount) ?? representative.amount,
                priceUsd: representative.priceUsd
            )
        }
        cachedAvailableSendCoinsByWalletID = sendCoinsByWalletID
        cachedAvailableReceiveCoinsByWalletID = receiveCoinsByWalletID
        cachedAvailableReceiveChainsByWalletID = receiveChainsByWalletID
        cachedSendEnabledWallets = sendWallets
        cachedReceiveEnabledWallets = receiveWallets
    }
    func applyWalletCollectionSideEffects() {
        batchCacheUpdates {
            rebuildWalletDerivedState()
            rebuildDashboardDerivedState()
        }
        walletSideEffectsTask?.cancel()
        walletSideEffectsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.updateRefreshEngineEntries()
            self.persistWallets()
            self.pruneTransactionsForActiveWallets()
            // Kick the refresh engine + maintenance loop — both are skipped
            // at startup when `wallets` is empty and need to come alive once
            // a wallet exists. Rust's `start()` and `startMaintenanceLoop`
            // both early-exit if already running, so calling on every
            // wallet mutation is safe. Conversely, when the user just
            // deleted the last wallet, stop the Rust tokio interval so it
            // isn't waking every N minutes to no-op.
            if self.wallets.isEmpty {
                try? await WalletServiceBridge.shared.stopBalanceRefresh()
            } else {
                await self.startBalanceRefreshIfNeeded()
                self.startMaintenanceLoopIfNeeded()
            }
            self.walletSideEffectsTask = nil
        }
    }
    func appendTransaction(_ transaction: TransactionRecord) { prependTransaction(transaction) }
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
        guard
            let mergedTransactions = mergeTransactionsUsingRust(
                existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .standardUtxo, chainName: chainName
            )
        else {
            assertionFailure("Rust transaction merge failed for standardUTXO chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func upsertDogecoinTransactions(_ newTransactions: [TransactionRecord]) {
        guard
            let mergedTransactions = mergeTransactionsUsingRust(
                existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .dogecoin, chainName: "Dogecoin"
            )
        else {
            assertionFailure("Rust transaction merge failed for Dogecoin")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
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
    func upsertSuiTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Sui") }
    func upsertAptosTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Aptos")
    }
    func upsertTONTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "TON") }
    func upsertICPTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Internet Computer")
    }
    func upsertNearTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "NEAR")
    }
    func upsertPolkadotTransactions(_ newTransactions: [TransactionRecord]) {
        upsertAccountBasedTransactions(newTransactions, chainName: "Polkadot")
    }
    func upsertAccountBasedTransactions(_ newTransactions: [TransactionRecord], chainName: String, includeSymbolInIdentity: Bool = false) {
        guard
            let mergedTransactions = mergeTransactionsUsingRust(
                existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .accountBased, chainName: chainName,
                includeSymbolInIdentity: includeSymbolInIdentity, preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
            )
        else {
            assertionFailure("Rust transaction merge failed for accountBased chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func upsertEVMTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        guard
            let mergedTransactions = mergeTransactionsUsingRust(
                existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .evm, chainName: chainName,
                preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
            )
        else {
            assertionFailure("Rust transaction merge failed for EVM chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func markChainHealthy(_ chainName: String) { diagnostics.markChainHealthy(chainName) }
    func noteChainSuccessfulSync(_ chainName: String) { diagnostics.noteChainSuccessfulSync(chainName) }
    func normalizedWalletChainName(_ chainName: String) -> String {
        WalletChainID(chainName)?.displayName ?? chainName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func clearDeletedWalletDiagnostics(walletID: String, chainName: String, hasRemainingWalletsOnChain: Bool) {
        diagnostics.operationalLogs.removeAll { event in
            if event.walletID == walletID { return true }
            guard !hasRemainingWalletsOnChain else { return false }
            return normalizedWalletChainName(event.chainName ?? "") == chainName
        }
        guard !hasRemainingWalletsOnChain else { return }
        markChainHealthy(chainName)
        chainOperationalEventsByChain[chainName] = nil
        lastHistoryRefreshAtByChain[chainName] = nil
    }
    func clearHistoryTracking(for walletID: String) {
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
        existingTransactions: [TransactionRecord], incomingTransactions: [TransactionRecord], strategy: TransactionMergeStrategy,
        chainName: String, includeSymbolInIdentity: Bool = false, preserveCreatedAtSentinelUnix: Double? = nil
    ) -> [TransactionRecord]? {
        let request = TransactionMergeRequest(
            existingTransactions: existingTransactions.map(\.rustBridgeRecord),
            incomingTransactions: incomingTransactions.map(\.rustBridgeRecord), strategy: strategy, chainName: chainName,
            includeSymbolInIdentity: includeSymbolInIdentity, preserveCreatedAtSentinelUnix: preserveCreatedAtSentinelUnix
        )
        let mergedRecords = coreMergeTransactions(request: request)
        var resolvedTransactions: [TransactionRecord] = []
        resolvedTransactions.reserveCapacity(mergedRecords.count)
        for record in mergedRecords {
            guard let transaction = record.transactionRecord else { return nil }
            resolvedTransactions.append(transaction)
        }
        return resolvedTransactions
    }
    func persistTransactionsFullSync() {
        let snapshots = transactions.map(\.persistedSnapshot)
        Task.detached(priority: .utility) {
            guard let records = historyRecordEncodeInputs(snapshots) else { return }
            try? await WalletServiceBridge.shared.replaceAllHistoryRecords(records)
        }
    }
    func persistTransactionsDelta(from oldRecords: [TransactionRecord], to newRecords: [TransactionRecord]) {
        let oldIDs = Set(oldRecords.map(\.id))
        let newIDs = Set(newRecords.map(\.id))
        let deletedIDs = oldIDs.subtracting(newIDs).map { $0.uuidString.lowercased() }
        let upsertSnapshots = newRecords.map(\.persistedSnapshot)
        if !deletedIDs.isEmpty {
            Task.detached(priority: .utility) {
                try? await WalletServiceBridge.shared.deleteHistoryRecords(ids: deletedIDs)
            }
        }
        if !upsertSnapshots.isEmpty {
            Task.detached(priority: .utility) {
                guard let records = historyRecordEncodeInputs(upsertSnapshots) else { return }
                try? await WalletServiceBridge.shared.upsertHistoryRecords(records)
            }
        }
    }
    func persistChainKeypoolState() {
        for (chainName, walletMap) in chainKeypoolByChain { persistKeypoolToRust(chainName: chainName, walletMap: walletMap) }
    }
    func persistKeypoolForChain(_ chainName: String) {
        guard let walletMap = chainKeypoolByChain[chainName] else { return }
        persistKeypoolToRust(chainName: chainName, walletMap: walletMap)
    }
    func loadChainKeypoolState() -> [String: [String: ChainKeypoolState]] {
        guard let payload = loadCodableFromUserDefaults(PersistedChainKeypoolStore.self, key: Self.chainKeypoolDefaultsKey) else {
            return [:]
        }
        guard payload.version == PersistedChainKeypoolStore.currentVersion else { return [:] }
        return payload.keypoolByChain
    }
    func persistChainOwnedAddressMap() {
        for (chainName, addressMap) in chainOwnedAddressMapByChain {
            for (_, record) in addressMap {
                persistOwnedAddressToRust(
                    walletId: record.walletID, chainName: chainName, address: record.address ?? "", derivationPath: record.derivationPath,
                    branch: record.branch, branchIndex: record.index
                )
            }
        }
    }
    func persistOwnedAddressesForChain(_ chainName: String) {
        guard let addressMap = chainOwnedAddressMapByChain[chainName] else { return }
        for (_, record) in addressMap {
            persistOwnedAddressToRust(
                walletId: record.walletID, chainName: chainName, address: record.address ?? "", derivationPath: record.derivationPath,
                branch: record.branch, branchIndex: record.index
            )
        }
    }
    func loadChainOwnedAddressMap() -> [String: [String: ChainOwnedAddressRecord]] {
        guard
            let payload = loadCodableFromUserDefaults(
                PersistedChainOwnedAddressStore.self, key: Self.chainOwnedAddressMapDefaultsKey
            )
        else {
            return [:]
        }
        guard payload.version == PersistedChainOwnedAddressStore.currentVersion else { return [:] }
        return payload.addressMapByChain
    }
    private func persistKeypoolToRust(chainName: String, walletMap: [String: ChainKeypoolState]) {
        for (walletID, state) in walletMap {
            let typed = KeypoolState(
                nextExternalIndex: Int64(state.nextExternalIndex),
                nextChangeIndex: Int64(state.nextChangeIndex),
                reservedReceiveIndex: state.reservedReceiveIndex.map { Int64($0) }
            )
            Task { try? await WalletServiceBridge.shared.saveKeypoolStateTyped(walletId: walletID, chainName: chainName, state: typed) }
        }
    }
    private func persistOwnedAddressToRust(
        walletId: String, chainName: String, address: String, derivationPath: String?, branch: String?, branchIndex: Int?
    ) {
        guard !address.isEmpty else { return }
        let record = OwnedAddressRecord(
            walletId: walletId,
            chainName: chainName,
            address: address,
            derivationPath: derivationPath,
            branch: branch,
            branchIndex: branchIndex.map { Int64($0) }
        )
        Task { try? await WalletServiceBridge.shared.saveOwnedAddressTyped(record: record) }
    }
}
private extension TransactionRecord {
    var rustBridgeRecord: CoreTransactionRecord {
        CoreTransactionRecord(
            id: id.uuidString, walletId: walletID, kind: kind.rawValue, status: status.rawValue, walletName: walletName,
            assetName: assetName, symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int64($0) }, receiptBlockNumber: receiptBlockNumber.map { Int64($0) },
            receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int64($0) }, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge,
            dogecoinConfirmations: dogecoinConfirmations.map { Int64($0) }, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason,
            transactionHistorySource: transactionHistorySource, createdAtUnix: createdAt.timeIntervalSince1970
        )
    }
}
private extension CoreTransactionRecord {
    var transactionRecord: TransactionRecord? {
        guard let resolvedID = UUID(uuidString: id) else { return nil }
        let resolvedKind = TransactionKind(rawValue: kind) ?? .receive
        let resolvedStatus = TransactionStatus(rawValue: status) ?? .pending
        return TransactionRecord(
            id: resolvedID, walletID: walletId, kind: resolvedKind, status: resolvedStatus, walletName: walletName, assetName: assetName,
            symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int($0) }, receiptBlockNumber: receiptBlockNumber.map { Int($0) },
            receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int($0) }, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge,
            dogecoinConfirmations: dogecoinConfirmations.map { Int($0) }, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason,
            transactionHistorySource: transactionHistorySource, createdAt: Date(timeIntervalSince1970: createdAtUnix)
        )
    }
}
private extension AppState {
    func rustStoreDerivedStatePlan(for wallets: [ImportedWallet]) -> StoreDerivedStatePlan {
        let request = StoreDerivedStateRequest(
            wallets: wallets.map { wallet in
                let signingMaterial = signingMaterialAvailability(for: wallet.id)
                return StoreDerivedWalletInput(
                    walletId: wallet.id, includeInPortfolioTotal: wallet.includeInPortfolioTotal,
                    hasSigningMaterial: signingMaterial.hasSigningMaterial, isPrivateKeyBacked: signingMaterial.isPrivateKeyBacked,
                    holdings: wallet.holdings.enumerated().map { index, holding in
                        StoreDerivedHoldingInput(
                            holdingIndex: UInt64(index), assetIdentityKey: assetIdentityKey(for: holding),
                            symbolUpper: holding.symbol.uppercased(), amount: String(holding.amount), isPricedAsset: isPricedAsset(holding)
                        )
                    }
                )
            }
        )
        return corePlanStoreDerivedState(request: request)
    }
    func resolveHolding(_ reference: WalletHoldingRef, in wallets: [ImportedWallet]) -> Coin? {
        let idx = Int(reference.holdingIndex)
        guard
            let wallet = cachedWalletByIDString[reference.walletId]
                ?? wallets.first(where: { $0.id == reference.walletId }), wallet.holdings.indices.contains(idx)
        else {
            return nil
        }
        return wallet.holdings[idx]
    }
    func rustTransferAvailabilityPlan(for wallets: [ImportedWallet]) -> TransferAvailabilityPlan {
        let request = TransferAvailabilityRequest(
            wallets: wallets.map { wallet in
                let hasSigningMaterial = signingMaterialAvailability(for: wallet.id).hasSigningMaterial
                return TransferWalletInput(
                    walletId: wallet.id, hasSigningMaterial: hasSigningMaterial,
                    holdings: wallet.holdings.enumerated().map { index, holding in
                        TransferHoldingInput(
                            index: UInt64(index), chainName: holding.chainName, symbol: holding.symbol,
                            supportsSend: AppEndpointDirectory.supportsSend(for: holding.chainName),
                            supportsReceiveAddress: AppEndpointDirectory.supportsReceiveAddress(for: holding.chainName),
                            isLiveChain: AppEndpointDirectory.liveChainNames.contains(holding.chainName),
                            supportsEvmToken: supportedEVMToken(for: holding) != nil,
                            supportsSolanaSendCoin: isSupportedSolanaSendCoin(holding)
                        )
                    }
                )
            }
        )
        return corePlanTransferAvailability(request: request)
    }
}
