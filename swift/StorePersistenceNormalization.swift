import Foundation
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
        let derivedStatePlan = rustStoreDerivedStatePlan(for: wallets)
        let transferAvailabilityPlan = rustTransferAvailabilityPlan(for: wallets)
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let includedPortfolioWallets = wallets.filter(\.includeInPortfolioTotal)
        let includedPortfolioHoldings = derivedStatePlan.includedPortfolioHoldingRefs.compactMap { ref in
            resolveHolding(ref, in: wallets)
        }
        let uniquePriceRequestCoins = derivedStatePlan.uniquePriceRequestHoldingRefs.compactMap { ref in
            resolveHolding(ref, in: wallets)
        }
        let transferAvailabilityByWalletID = Dictionary(
            uniqueKeysWithValues: transferAvailabilityPlan.wallets.map { ($0.walletId, $0) }
        )
        let rustSendEnabledWalletIDs = Set(transferAvailabilityPlan.sendEnabledWalletIds)
        let rustReceiveEnabledWalletIDs = Set(transferAvailabilityPlan.receiveEnabledWalletIds)
        var sendCoinsByWalletID: [String: [Coin]] = [:]
        var receiveCoinsByWalletID: [String: [Coin]] = [:]
        var receiveChainsByWalletID: [String: [String]] = [:]
        var sendWallets: [ImportedWallet] = []
        var receiveWallets: [ImportedWallet] = []
        for wallet in wallets {
            let walletID = wallet.id
            let availability = transferAvailabilityByWalletID[walletID]
            sendCoinsByWalletID[walletID] = availability.map { a in
                a.sendHoldingIndices.compactMap { i in
                    let idx = Int(i); return wallet.holdings.indices.contains(idx) ? wallet.holdings[idx] : nil
                }
            } ?? []
            receiveCoinsByWalletID[walletID] = availability.map { a in
                a.receiveHoldingIndices.compactMap { i in
                    let idx = Int(i); return wallet.holdings.indices.contains(idx) ? wallet.holdings[idx] : nil
                }
            } ?? []
            receiveChainsByWalletID[walletID] = availability?.receiveChains ?? []
            if rustSendEnabledWalletIDs.contains(walletID) { sendWallets.append(wallet) }
            if rustReceiveEnabledWalletIDs.contains(walletID) { receiveWallets.append(wallet) }
        }
        let portfolio = derivedStatePlan.groupedPortfolio.compactMap { group -> Coin? in
            guard let rep = resolveHolding(
                WalletHoldingRef(walletId: group.walletId, holdingIndex: group.holdingIndex), in: wallets
            ) else { return nil }
            return Coin.makeCustom(
                name: rep.name, symbol: rep.symbol, coinGeckoId: rep.coinGeckoId, chainName: rep.chainName,
                tokenStandard: rep.tokenStandard, contractAddress: rep.contractAddress,
                amount: Double(group.totalAmount) ?? rep.amount, priceUsd: rep.priceUsd
            )
        }
        // Preserve fields that aren't derived from `wallets` directly — these
        // are populated by other code paths (e.g. password protection mapping
        // and secret descriptor mirroring).
        let preservedPasswordProtectedIDs = walletDerivedCache.passwordProtectedWalletIDs
        let preservedSecretDescriptors = walletDerivedCache.secretDescriptorsByWalletID
        walletDerivedCache = WalletDerivedCache(
            walletByID: walletByID,
            walletByIDString: walletByID,
            includedPortfolioWallets: includedPortfolioWallets,
            includedPortfolioHoldings: includedPortfolioHoldings,
            includedPortfolioHoldingsBySymbol: Dictionary(
                grouping: includedPortfolioHoldings, by: { $0.symbol.uppercased() }
            ),
            uniqueWalletPriceRequestCoins: uniquePriceRequestCoins,
            portfolio: portfolio,
            availableSendCoinsByWalletID: sendCoinsByWalletID,
            availableReceiveCoinsByWalletID: receiveCoinsByWalletID,
            availableReceiveChainsByWalletID: receiveChainsByWalletID,
            sendEnabledWallets: sendWallets,
            receiveEnabledWallets: receiveWallets,
            refreshableChainNames: Set(wallets.map(\.selectedChain)),
            signingMaterialWalletIDs: Set(derivedStatePlan.signingMaterialWalletIds),
            privateKeyBackedWalletIDs: Set(derivedStatePlan.privateKeyBackedWalletIds),
            passwordProtectedWalletIDs: preservedPasswordProtectedIDs,
            secretDescriptorsByWalletID: preservedSecretDescriptors
        )
    }
    /// Run after `wallets` mutates. Decomposed into three named phases so a
    /// reader chasing "why did X happen when wallets changed?" can grep the
    /// matching phase by name instead of skimming a 30-line debounce closure.
    ///   1. `rebuildWalletDerivedCaches` — observable derived state, sync, batched.
    ///   2. `persistWalletStateOptimistically` — non-network writes (SQLite, Keychain).
    ///   3. `reconcileBackgroundServices` — refresh engine + maintenance loop start/stop.
    /// Phases 2 and 3 run together inside a 200ms debounce so a fast cascade
    /// of edits costs one persist + one reconcile, not N.
    func applyWalletCollectionSideEffects() {
        rebuildWalletDerivedCaches()
        walletSideEffectsTask?.cancel()
        walletSideEffectsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.persistWalletStateOptimistically()
            await self.reconcileBackgroundServices()
            self.walletSideEffectsTask = nil
        }
    }

    /// Phase 1: rebuild the observable derived state in one batched pass so
    /// SwiftUI sees a single revision bump.
    private func rebuildWalletDerivedCaches() {
        batchCacheUpdates {
            rebuildWalletDerivedState()
            rebuildDashboardDerivedState()
        }
    }

    /// Phase 2: write the wallet collection to SQLite + Keychain and prune
    /// transactions that no longer reference an active wallet. No network I/O;
    /// safe to call inside the debounce.
    private func persistWalletStateOptimistically() {
        // Wallets persist themselves: every mutation goes through a
        // `StateCommand` that core writes before it returns.
        updateRefreshEngineEntries()
        pruneTransactionsForActiveWallets()
    }

    /// Phase 3: start or stop the Rust-side balance-refresh engine and
    /// maintenance loop based on whether any wallets exist. Both Rust calls
    /// early-exit if already running, so it's safe to invoke on every wallet
    /// mutation; calling `stopBalanceRefresh` when the last wallet is removed
    /// silences the tokio interval that would otherwise wake every N minutes
    /// to no-op.
    private func reconcileBackgroundServices() async {
        if wallets.isEmpty {
            try? WalletServiceBridge.shared.stopBalanceRefresh()
        } else {
            await startBalanceRefreshIfNeeded()
            startMaintenanceLoopIfNeeded()
        }
    }

    func appendTransaction(_ transaction: TransactionRecord) { recordTransaction(transaction) }
    /// Merge freshly fetched history for a chain into the store.
    ///
    /// One entry point for every chain: the merge strategy and whether the
    /// identity includes the asset symbol are per-chain facts core reads from
    /// its registry. This replaced eighteen wrappers that each named a chain
    /// and a strategy by hand.
    func upsertTransactions(_ newTransactions: [TransactionRecord], chainName: String) {
        let command = TransactionCommand.merge(
            incoming: newTransactions.map(\.rustBridgeRecord),
            chainName: chainName,
            // Account-based and EVM merges preserve a sentinel createdAt for
            // records the app created locally before the chain confirmed them.
            preserveCreatedAtSentinelUnix: Date.distantPast.timeIntervalSince1970
        )
        Task { @MainActor [weak self] in
            guard
                let change = try? await WalletServiceBridge.shared.applyTransactionCommand(command),
                !change.added.isEmpty || !change.updated.isEmpty || !change.removed.isEmpty
            else { return }
            await self?.refreshTransactionProjection()
        }
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
    /// Merge a fetched page into the store core owns, then adopt the result.
    ///
    /// Only the incoming page crosses the FFI. Core merges against its own
    /// records and writes just what changed; this then re-reads the projection.
    /// Previously the entire history went out, came back merged, and the
    /// changed subset went out again — three crossings of the whole list per
    /// refresh.
    /// Re-read the projection from core. Used after a change core made itself.
    func refreshTransactionProjection() async {
        guard let stored = try? await WalletServiceBridge.shared.storedTransactions() else { return }
        adoptTransactionsFromCore(stored.compactMap(TransactionRecord.init(snapshot:)))
        pruneTransactionsForActiveWallets()
        rebuildTransactionDerivedState()
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
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress,
            signedTransactionPayload: signedTransactionPayload,
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
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: usedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress, changeAddress: changeAddress,
            signedTransactionPayload: signedTransactionPayload,
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
