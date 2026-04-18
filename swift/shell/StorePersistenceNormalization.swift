import Foundation
private func encodeHistoryRecords(_ snapshots: [CorePersistedTransactionRecord]) -> String? {
    try? WalletRustAppCoreBridge.encodeHistoryRecordsFromPersisted(snapshots)
}
extension AppState {
    func rebuildTokenPreferenceDerivedState() { batchCacheUpdates {
        let resolvedPreferences = tokenPreferences.isEmpty ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry) : tokenPreferences
        cachedResolvedTokenPreferences = resolvedPreferences
        cachedTokenPreferencesByChain = Dictionary(grouping: resolvedPreferences, by: \.chain)
        cachedResolvedTokenPreferencesBySymbol = Dictionary(
            grouping: resolvedPreferences, by: { $0.symbol.uppercased() }
        )
        cachedEnabledTrackedTokenPreferences = resolvedPreferences.filter(\.isEnabled)
        cachedTokenPreferenceByChainAndSymbol = resolvedPreferences.reduce(into: [:]) { partialResult, entry in
            partialResult[tokenPreferenceLookupKey(chainName: entry.chain.rawValue, symbol: entry.symbol)] = entry
        }
    }}
    func rebuildWalletDerivedState() { batchCacheUpdates { _rebuildWalletDerivedStateBody() } }
    private func _rebuildWalletDerivedStateBody() {
        cachedWalletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        cachedWalletByIDString = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        cachedRefreshableChainNames = Set(wallets.map(\.selectedChain))
        cachedIncludedPortfolioWallets = wallets.filter(\.includeInPortfolioTotal)
        let derivedStatePlan = rustStoreDerivedStatePlan(for: wallets)
        cachedIncludedPortfolioHoldings = derivedStatePlan.includedPortfolioHoldingRefs.compactMap { reference in resolveHolding(reference, in: wallets) }
        cachedIncludedPortfolioHoldingsBySymbol = Dictionary(
            grouping: cachedIncludedPortfolioHoldings, by: { $0.symbol.uppercased() }
        )
        cachedUniqueWalletPriceRequestCoins = derivedStatePlan.uniquePriceRequestHoldingRefs.compactMap { reference in resolveHolding(reference, in: wallets) }
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
            let walletID = wallet.id
            let sendCoins: [Coin] = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.sendHoldingIndices.compactMap { i -> Coin? in let index = Int(i); return wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil }}
                ?? []
            sendCoinsByWalletID[walletID] = sendCoins
            if rustSendEnabledWalletIDs.contains(walletID) { sendWallets.append(wallet) }
            let receiveCoins: [Coin] = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.receiveHoldingIndices.compactMap { i -> Coin? in let index = Int(i); return wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil }}
                ?? []
            receiveCoinsByWalletID[walletID] = receiveCoins
            let receiveChains = transferAvailabilityByWalletID[walletID]?.receiveChains
                ?? []
            receiveChainsByWalletID[walletID] = receiveChains
            if rustReceiveEnabledWalletIDs.contains(walletID) { receiveWallets.append(wallet) }}
        cachedSigningMaterialWalletIDs = Set(derivedStatePlan.signingMaterialWalletIDs)
        cachedPrivateKeyBackedWalletIDs = Set(derivedStatePlan.privateKeyBackedWalletIDs)
        cachedPortfolio = derivedStatePlan.groupedPortfolio.compactMap { group in
            guard let representative = resolveHolding(
                WalletRustWalletHoldingRef(walletId: group.walletID, holdingIndex: group.holdingIndex), in: wallets
            ) else {
                return nil
            }
            return Coin.makeCustom(
                name: representative.name, symbol: representative.symbol, marketDataId: representative.marketDataId, coinGeckoId: representative.coinGeckoId, chainName: representative.chainName, tokenStandard: representative.tokenStandard, contractAddress: representative.contractAddress, amount: Double(group.totalAmount) ?? representative.amount, priceUsd: representative.priceUsd, mark: representative.mark, color: representative.color
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
            self.walletSideEffectsTask = nil
        }}
    func appendTransaction(_ transaction: TransactionRecord) { prependTransaction(transaction) }
    func upsertBitcoinTransactions(_ newTransactions: [TransactionRecord]) { upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin") }
    func upsertBitcoinCashTransactions(_ newTransactions: [TransactionRecord]) { upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin Cash") }
    func upsertBitcoinSVTransactions(_ newTransactions: [TransactionRecord]) { upsertStandardUTXOTransactions(newTransactions, chainName: "Bitcoin SV") }
    func upsertLitecoinTransactions(_ newTransactions: [TransactionRecord]) { upsertStandardUTXOTransactions(newTransactions, chainName: "Litecoin") }
    func upsertStandardUTXOTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        guard let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .standardUTXO, chainName: chainName
        ) else {
            assertionFailure("Rust transaction merge failed for standardUTXO chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func upsertDogecoinTransactions(_ newTransactions: [TransactionRecord]) {
        guard let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .dogecoin, chainName: "Dogecoin"
        ) else {
            assertionFailure("Rust transaction merge failed for Dogecoin")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func upsertTronTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Tron", includeSymbolInIdentity: true) }
    func upsertSolanaTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Solana") }
    func upsertCardanoTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Cardano") }
    func upsertXRPTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "XRP Ledger") }
    func upsertStellarTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Stellar") }
    func upsertMoneroTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Monero") }
    func upsertSuiTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Sui") }
    func upsertAptosTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Aptos") }
    func upsertTONTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "TON") }
    func upsertICPTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Internet Computer") }
    func upsertNearTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "NEAR") }
    func upsertPolkadotTransactions(_ newTransactions: [TransactionRecord]) { upsertAccountBasedTransactions(newTransactions, chainName: "Polkadot") }
    func upsertAccountBasedTransactions(_ newTransactions: [TransactionRecord], chainName: String, includeSymbolInIdentity: Bool = false) {
        guard let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .accountBased, chainName: chainName, includeSymbolInIdentity: includeSymbolInIdentity, preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
        ) else {
            assertionFailure("Rust transaction merge failed for accountBased chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func upsertEVMTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        guard let mergedTransactions = mergeTransactionsUsingRust(
            existingTransactions: transactions, incomingTransactions: newTransactions, strategy: .evm, chainName: chainName, preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
        ) else {
            assertionFailure("Rust transaction merge failed for EVM chain \(chainName)")
            return
        }
        setTransactionsIfChanged(mergedTransactions)
    }
    func markChainHealthy(_ chainName: String) { diagnostics.markChainHealthy(chainName) }
    func noteChainSuccessfulSync(_ chainName: String) { diagnostics.noteChainSuccessfulSync(chainName) }
    func normalizedWalletChainName(_ chainName: String) -> String { WalletChainID(chainName)?.displayName ?? chainName.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private func mergeTransactionsUsingRust(existingTransactions: [TransactionRecord], incomingTransactions: [TransactionRecord], strategy: WalletRustTransactionMergeStrategy, chainName: String, includeSymbolInIdentity: Bool = false, preserveCreatedAtSentinelUnix: Double? = nil) -> [TransactionRecord]? {
        let request = WalletRustTransactionMergeRequest(
            existingTransactions: existingTransactions.map(\.rustBridgeRecord), incomingTransactions: incomingTransactions.map(\.rustBridgeRecord), strategy: strategy, chainName: chainName, includeSymbolInIdentity: includeSymbolInIdentity, preserveCreatedAtSentinelUnix: preserveCreatedAtSentinelUnix
        )
        let mergedRecords = WalletRustAppCoreBridge.mergeTransactions(request)
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
        if let json = encodeHistoryRecords(snapshots) { Task { await WalletServiceBridge.shared.replaceAllHistoryRecords(recordsJSON: json) } }
    }
    func persistTransactionsDelta(from oldRecords: [TransactionRecord], to newRecords: [TransactionRecord]) {
        let oldIDs = Set(oldRecords.map(\.id))
        let newIDs = Set(newRecords.map(\.id))
        let deletedIDs = oldIDs.subtracting(newIDs).map { $0.uuidString.lowercased() }
        let upsertSnapshots = newRecords.map(\.persistedSnapshot)
        if !deletedIDs.isEmpty, let idsData = try? JSONEncoder().encode(deletedIDs), let idsJSON = String(data: idsData, encoding: .utf8) {
            Task { await WalletServiceBridge.shared.deleteHistoryRecords(idsJSON: idsJSON) }
        }
        if !upsertSnapshots.isEmpty, let json = encodeHistoryRecords(upsertSnapshots) { Task { await WalletServiceBridge.shared.upsertHistoryRecords(recordsJSON: json) } }
    }
    func persistChainKeypoolState() {
        for (chainName, walletMap) in chainKeypoolByChain { persistKeypoolToRust(chainName: chainName, walletMap: walletMap) }}
    func persistKeypoolForChain(_ chainName: String) {
        guard let walletMap = chainKeypoolByChain[chainName] else { return }
        persistKeypoolToRust(chainName: chainName, walletMap: walletMap)
    }
    func loadChainKeypoolState() -> [String: [String: ChainKeypoolState]] {
        guard let payload = loadCodableFromUserDefaults(PersistedChainKeypoolStore.self, key: Self.chainKeypoolDefaultsKey) else { return [:] }
        guard payload.version == PersistedChainKeypoolStore.currentVersion else { return [:] }
        return payload.keypoolByChain
    }
    func persistChainOwnedAddressMap() {
        for (chainName, addressMap) in chainOwnedAddressMapByChain {
            for (_, record) in addressMap {
                persistOwnedAddressToRust(
                    walletId: record.walletID, chainName: chainName, address: record.address ?? "", derivationPath: record.derivationPath, branch: record.branch, branchIndex: record.index
                )
            }}}
    func persistOwnedAddressesForChain(_ chainName: String) {
        guard let addressMap = chainOwnedAddressMapByChain[chainName] else { return }
        for (_, record) in addressMap {
            persistOwnedAddressToRust(
                walletId: record.walletID, chainName: chainName, address: record.address ?? "", derivationPath: record.derivationPath, branch: record.branch, branchIndex: record.index
            )
        }
    }
    func loadChainOwnedAddressMap() -> [String: [String: ChainOwnedAddressRecord]] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedChainOwnedAddressStore.self, key: Self.chainOwnedAddressMapDefaultsKey
        ) else {
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
            Task { await WalletServiceBridge.shared.saveKeypoolStateTyped(walletId: walletID, chainName: chainName, state: typed) }
        }}
    private func persistOwnedAddressToRust(
        walletId: String, chainName: String, address: String, derivationPath: String?, branch: String?, branchIndex: Int? ) {
        guard !address.isEmpty else { return }
        let record = OwnedAddressRecord(
            walletId: walletId,
            chainName: chainName,
            address: address,
            derivationPath: derivationPath,
            branch: branch,
            branchIndex: branchIndex.map { Int64($0) }
        )
        Task { await WalletServiceBridge.shared.saveOwnedAddressTyped(record: record) }
    }
}
private extension TransactionRecord {
    var rustBridgeRecord: WalletRustTransactionRecord {
        WalletRustTransactionRecord(
            id: id.uuidString, walletId: walletID, kind: kind.rawValue, status: status.rawValue, walletName: walletName, assetName: assetName, symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce.map { Int64($0) }, receiptBlockNumber: receiptBlockNumber.map { Int64($0) }, receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount.map { Int64($0) }, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: dogecoinConfirmations.map { Int64($0) }, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput, dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress, dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload, signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason, transactionHistorySource: transactionHistorySource, createdAtUnix: createdAt.timeIntervalSince1970
        )
    }
}
private extension WalletRustTransactionRecord {
    var transactionRecord: TransactionRecord? {
        guard let resolvedID = UUID(uuidString: id) else { return nil }
        let resolvedKind = TransactionKind(rawValue: kind) ?? .receive
        let resolvedStatus = TransactionStatus(rawValue: status) ?? .pending
        return TransactionRecord(
            id: resolvedID, walletID: walletId, kind: resolvedKind, status: resolvedStatus, walletName: walletName, assetName: assetName, symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce.map { Int($0) }, receiptBlockNumber: receiptBlockNumber.map { Int($0) }, receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount.map { Int($0) }, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: dogecoinConfirmations.map { Int($0) }, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput, dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress, dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload, signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason, transactionHistorySource: transactionHistorySource, createdAt: Date(timeIntervalSince1970: createdAtUnix)
        )
    }
}
private extension AppState {
    func rustStoreDerivedStatePlan(for wallets: [ImportedWallet]) -> WalletRustStoreDerivedStatePlan {
        let request = WalletRustStoreDerivedStateRequest(
            wallets: wallets.map { wallet in
                let signingMaterial = signingMaterialAvailability(for: wallet.id)
                return WalletRustStoreDerivedWalletInput(
                    walletId: wallet.id, includeInPortfolioTotal: wallet.includeInPortfolioTotal, hasSigningMaterial: signingMaterial.hasSigningMaterial, isPrivateKeyBacked: signingMaterial.isPrivateKeyBacked, holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustStoreDerivedHoldingInput(
                            holdingIndex: UInt64(index), assetIdentityKey: assetIdentityKey(for: holding), symbolUpper: holding.symbol.uppercased(), amount: String(holding.amount), isPricedAsset: isPricedAsset(holding)
                        )
                    }
                )
            }
        )
        return WalletRustAppCoreBridge.planStoreDerivedState(request)
    }
    func resolveHolding(_ reference: WalletRustWalletHoldingRef, in wallets: [ImportedWallet]) -> Coin? {
        let idx = Int(reference.holdingIndex)
        guard let wallet = cachedWalletByIDString[reference.walletID]
            ?? wallets.first(where: { $0.id == reference.walletID }), wallet.holdings.indices.contains(idx) else {
            return nil
        }
        return wallet.holdings[idx]
    }
    func rustTransferAvailabilityPlan(for wallets: [ImportedWallet]) -> WalletRustTransferAvailabilityPlan {
        let request = WalletRustTransferAvailabilityRequest(
            wallets: wallets.map { wallet in
                let hasSigningMaterial = signingMaterialAvailability(for: wallet.id).hasSigningMaterial
                return WalletRustTransferWalletInput(
                    walletId: wallet.id, hasSigningMaterial: hasSigningMaterial, holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustTransferHoldingInput(
                            index: UInt64(index), chainName: holding.chainName, symbol: holding.symbol, supportsSend: AppEndpointDirectory.supportsSend(for: holding.chainName), supportsReceiveAddress: AppEndpointDirectory.supportsReceiveAddress(for: holding.chainName), isLiveChain: AppEndpointDirectory.liveChainNames.contains(holding.chainName), supportsEvmToken: supportedEVMToken(for: holding) != nil, supportsSolanaSendCoin: isSupportedSolanaSendCoin(holding)
                        )
                    }
                )
            }
        )
        return WalletRustAppCoreBridge.planTransferAvailability(request)
    }
}
