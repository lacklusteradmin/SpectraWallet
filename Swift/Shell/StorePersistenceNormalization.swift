import Foundation
private func encodeHistoryRecords(_ snapshots: [CorePersistedTransactionRecord]) -> String? {
    let inputs = snapshots.compactMap { snap -> HistoryRecordEncodeInput? in
        guard let payloadJSON = try? encodePersistedTransactionRecordJson(value: snap) else { return nil }
        // createdAt is seconds since Swift reference date (2001-01-01) — convert to epoch.
        let createdAtUnix = Date(timeIntervalSinceReferenceDate: snap.createdAt).timeIntervalSince1970
        return HistoryRecordEncodeInput(
            id: snap.id.lowercased(),
            walletId: snap.walletId?.lowercased(),
            chainName: snap.chainName,
            txHash: snap.transactionHash?.lowercased(),
            createdAt: createdAtUnix,
            payloadJson: payloadJSON
        )
    }
    return try? WalletRustAppCoreBridge.encodeHistoryRecordsJSON(inputs)
}
extension AppState {
    func rebuildTokenPreferenceDerivedState() {
        let resolvedPreferences = tokenPreferences.isEmpty ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry) : tokenPreferences
        cachedResolvedTokenPreferences = resolvedPreferences
        cachedTokenPreferencesByChain = Dictionary(grouping: resolvedPreferences, by: \.chain)
        cachedResolvedTokenPreferencesBySymbol = Dictionary(
            grouping: resolvedPreferences, by: { $0.symbol.uppercased() }
        )
        cachedEnabledTrackedTokenPreferences = resolvedPreferences.filter(\.isEnabled)
        cachedTokenPreferenceByChainAndSymbol = resolvedPreferences.reduce(into: [:]) { partialResult, entry in
            partialResult[tokenPreferenceLookupKey(chainName: entry.chain.rawValue, symbol: entry.symbol)] = entry
        }}
    func rebuildWalletDerivedState() {
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
            let sendCoins = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.sendHoldingIndices.compactMap { index in wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil }}
                ?? []
            sendCoinsByWalletID[walletID] = sendCoins
            if rustSendEnabledWalletIDs.contains(walletID) { sendWallets.append(wallet) }
            let receiveCoins = transferAvailabilityByWalletID[walletID]
                .map { availability in
                    availability.receiveHoldingIndices.compactMap { index in wallet.holdings.indices.contains(index) ? wallet.holdings[index] : nil }}
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
                WalletRustWalletHoldingRef(walletID: group.walletID, holdingIndex: group.holdingIndex), in: wallets
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
    func upsertEthereumTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Ethereum") }
    func upsertArbitrumTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Arbitrum") }
    func upsertOptimismTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Optimism") }
    func upsertBNBTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "BNB Chain") }
    func upsertAvalancheTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Avalanche") }
    func upsertETCTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Ethereum Classic") }
    func upsertHyperliquidTransactions(_ newTransactions: [TransactionRecord]) { upsertEVMTransactions(newTransactions, chainName: "Hyperliquid") }
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
        guard let mergedRecords = try? WalletRustAppCoreBridge.mergeTransactions(request) else { return nil }
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
    func persistDogecoinKeypoolState() {
        persistKeypoolToRust(chainName: "Dogecoin", walletMap: dogecoinKeypoolByWalletID.mapValues { ChainKeypoolState(nextExternalIndex: $0.nextExternalIndex, nextChangeIndex: $0.nextChangeIndex, reservedReceiveIndex: $0.reservedReceiveIndex) })
    }
    func loadDogecoinKeypoolState() -> [String: DogecoinKeypoolState] {
        guard let payload = loadCodableFromUserDefaults(PersistedDogecoinKeypoolStore.self, key: Self.dogecoinKeypoolDefaultsKey) else { return [:] }
        guard payload.version == PersistedDogecoinKeypoolStore.currentVersion else { return [:] }
        return payload.keypoolByWalletID
    }
    func persistChainKeypoolState() {
        for (chainName, walletMap) in chainKeypoolByChain { persistKeypoolToRust(chainName: chainName, walletMap: walletMap) }}
    func loadChainKeypoolState() -> [String: [String: ChainKeypoolState]] {
        guard let payload = loadCodableFromUserDefaults(PersistedChainKeypoolStore.self, key: Self.chainKeypoolDefaultsKey) else { return [:] }
        guard payload.version == PersistedChainKeypoolStore.currentVersion else { return [:] }
        return payload.keypoolByChain
    }
    func persistDogecoinOwnedAddressMap() {
        for (_, record) in dogecoinOwnedAddressMap {
            persistOwnedAddressToRust(
                walletId: record.walletID, chainName: "Dogecoin", address: record.address ?? "", derivationPath: record.derivationPath, branch: record.branch, branchIndex: record.index
            )
        }}
    func loadDogecoinOwnedAddressMap() -> [String: DogecoinOwnedAddressRecord] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedDogecoinOwnedAddressStore.self, key: Self.dogecoinOwnedAddressMapDefaultsKey
        ) else {
            return [:]
        }
        guard payload.version == PersistedDogecoinOwnedAddressStore.currentVersion else { return [:] }
        return payload.addressMap
    }
    func persistChainOwnedAddressMap() {
        for (chainName, addressMap) in chainOwnedAddressMapByChain {
            for (_, record) in addressMap {
                persistOwnedAddressToRust(
                    walletId: record.walletID, chainName: chainName, address: record.address ?? "", derivationPath: record.derivationPath, branch: record.branch, branchIndex: record.index
                )
            }}}
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
        let encoder = JSONEncoder()
        for (walletID, state) in walletMap {
            let payload = RustKeypoolStatePayload(
                nextExternalIndex: state.nextExternalIndex,
                nextChangeIndex: state.nextChangeIndex,
                reservedReceiveIndex: state.reservedReceiveIndex
            )
            guard let data = try? encoder.encode(payload),
                  let json = String(data: data, encoding: .utf8) else { continue }
            Task { await WalletServiceBridge.shared.saveKeypoolState(walletId: walletID, chainName: chainName, stateJSON: json) }
        }}
    private func persistOwnedAddressToRust(
        walletId: String, chainName: String, address: String, derivationPath: String?, branch: String?, branchIndex: Int? ) {
        guard !address.isEmpty else { return }
        let payload = RustOwnedAddressPayload(
            walletId: walletId,
            chainName: chainName,
            address: address,
            derivationPath: derivationPath,
            branch: branch,
            branchIndex: branchIndex
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }
        Task { await WalletServiceBridge.shared.saveOwnedAddress(recordJSON: json) }
    }
}
private struct RustKeypoolStatePayload: Encodable {
    let nextExternalIndex: Int
    let nextChangeIndex: Int
    let reservedReceiveIndex: Int?
}
private struct RustOwnedAddressPayload: Encodable {
    let walletId: String
    let chainName: String
    let address: String
    let derivationPath: String?
    let branch: String?
    let branchIndex: Int?
}
private extension TransactionRecord {
    var rustBridgeRecord: WalletRustTransactionRecord {
        WalletRustTransactionRecord(
            id: id.uuidString, walletID: walletID, kind: kind.rawValue, status: status.rawValue, walletName: walletName, assetName: assetName, symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce, receiptBlockNumber: receiptBlockNumber, receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: dogecoinConfirmations, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput, dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress, dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload, signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason, transactionHistorySource: transactionHistorySource, createdAtUnix: createdAt.timeIntervalSince1970
        )
    }
}
private extension WalletRustTransactionRecord {
    var transactionRecord: TransactionRecord? {
        guard let resolvedID = UUID(uuidString: id) else { return nil }
        let resolvedWalletID = walletID
        let resolvedKind = TransactionKind(rawValue: kind) ?? .receive
        let resolvedStatus = TransactionStatus(rawValue: status) ?? .pending
        return TransactionRecord(
            id: resolvedID, walletID: resolvedWalletID, kind: resolvedKind, status: resolvedStatus, walletName: walletName, assetName: assetName, symbol: symbol, chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce, receiptBlockNumber: receiptBlockNumber, receiptGasUsed: receiptGasUsed, receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth, feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount, dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: dogecoinConfirmations, dogecoinFeePriorityRaw: dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput, dogecoinUsedChangeOutput: dogecoinUsedChangeOutput, sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress, dogecoinRawTransactionHex: dogecoinRawTransactionHex, signedTransactionPayload: signedTransactionPayload, signedTransactionPayloadFormat: signedTransactionPayloadFormat, failureReason: failureReason, transactionHistorySource: transactionHistorySource, createdAt: Date(timeIntervalSince1970: createdAtUnix)
        )
    }
}
private extension AppState {
    func rustStoreDerivedStatePlan(for wallets: [ImportedWallet]) -> WalletRustStoreDerivedStatePlan {
        let request = WalletRustStoreDerivedStateRequest(
            wallets: wallets.map { wallet in
                let signingMaterial = signingMaterialAvailability(for: wallet.id)
                return WalletRustStoreDerivedWalletInput(
                    walletID: wallet.id, includeInPortfolioTotal: wallet.includeInPortfolioTotal, hasSigningMaterial: signingMaterial.hasSigningMaterial, isPrivateKeyBacked: signingMaterial.isPrivateKeyBacked, holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustStoreDerivedHoldingInput(
                            holdingIndex: index, assetIdentityKey: assetIdentityKey(for: holding), symbolUpper: holding.symbol.uppercased(), amount: String(holding.amount), isPricedAsset: isPricedAsset(holding)
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
                includedPortfolioHoldingRefs: [], uniquePriceRequestHoldingRefs: [], groupedPortfolio: [], signingMaterialWalletIDs: [], privateKeyBackedWalletIDs: []
            )
        }}
    func resolveHolding(_ reference: WalletRustWalletHoldingRef, in wallets: [ImportedWallet]) -> Coin? {
        guard let wallet = cachedWalletByIDString[reference.walletID]
            ?? wallets.first(where: { $0.id == reference.walletID }), wallet.holdings.indices.contains(reference.holdingIndex) else {
            return nil
        }
        return wallet.holdings[reference.holdingIndex]
    }
    func rustTransferAvailabilityPlan(for wallets: [ImportedWallet]) -> WalletRustTransferAvailabilityPlan {
        let request = WalletRustTransferAvailabilityRequest(
            wallets: wallets.map { wallet in
                let hasSigningMaterial = signingMaterialAvailability(for: wallet.id).hasSigningMaterial
                return WalletRustTransferWalletInput(
                    walletID: wallet.id, hasSigningMaterial: hasSigningMaterial, holdings: wallet.holdings.enumerated().map { index, holding in
                        WalletRustTransferHoldingInput(
                            index: index, chainName: holding.chainName, symbol: holding.symbol, supportsSend: ChainBackendRegistry.supportsSend(for: holding.chainName), supportsReceiveAddress: ChainBackendRegistry.supportsReceiveAddress(for: holding.chainName), isLiveChain: ChainBackendRegistry.liveChainNames.contains(holding.chainName), supportsEVMToken: supportedEVMToken(for: holding) != nil, supportsSolanaSendCoin: isSupportedSolanaSendCoin(holding)
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
                wallets: [], sendEnabledWalletIDs: [], receiveEnabledWalletIDs: []
            )
        }}
}
