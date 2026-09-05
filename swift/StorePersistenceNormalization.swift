import Foundation
extension AppState {
    func rebuildTokenPreferenceDerivedState() {
        let resolvedPreferences =
            tokenPreferences.isEmpty ? TokenPreferenceEntry.builtIn : tokenPreferences
        cachedResolvedTokenPreferences = resolvedPreferences
        cachedTokenPreferencesByChain = Dictionary(grouping: resolvedPreferences, by: { TokenHostingChain.forChainName($0.token.chain) ?? .ethereum })
        cachedResolvedTokenPreferencesBySymbol = Dictionary(
            grouping: resolvedPreferences, by: { $0.token.symbol.uppercased() }
        )
        cachedEnabledKnownTokenPreferences = resolvedPreferences.filter(\.isEnabled)
        cachedTokenPreferenceByChainAndSymbol = resolvedPreferences.reduce(into: [:]) { partialResult, entry in
            partialResult[tokenPreferenceLookupKey(chainName: entry.token.chain, symbol: entry.token.symbol)] = entry
        }
    }
    func rebuildWalletDerivedState() {
        Task { @MainActor [weak self] in await self?.rebuildWalletDerivedStateFromCore() }
    }
    /// Core resolves the whole thing — grouping, price-request set, and which
    /// coins each wallet can send or receive on. It holds the wallets, so it
    /// hands back coins rather than indices into a list the caller has to
    /// re-walk.
    private func rebuildWalletDerivedStateFromCore() async {
        let signing = wallets.map { wallet -> (String, (hasSigningMaterial: Bool, isPrivateKeyBacked: Bool)) in
            let state = WalletServiceBridge.shared.walletSecretState(walletID: wallet.id)
            return (wallet.id, (state?.hasSigningMaterial ?? false, state?.hasPrivateKey ?? false))
        }
        guard
            let derived = try? await WalletServiceBridge.shared.walletDerivedState(
                signingMaterialWalletIDs: signing.filter(\.1.hasSigningMaterial).map(\.0),
                privateKeyBackedWalletIDs: signing.filter(\.1.isPrivateKeyBacked).map(\.0)
            )
        else { return }
        applyWalletDerivedState(derived)
    }
    private func applyWalletDerivedState(_ derived: WalletDerivedState) {
        let walletByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        // Not derived from `wallets`, so they survive the rebuild: other paths
        // populate them (password mapping, secret descriptor mirroring).
        let preservedPasswordProtectedIDs = walletDerivedCache.passwordProtectedWalletIDs
        let preservedSecretDescriptors = walletDerivedCache.secretDescriptorsByWalletID
        walletDerivedCache = WalletDerivedCache(
            walletByID: walletByID,
            walletByIDString: walletByID,
            includedPortfolioWallets: wallets.filter(\.includeInPortfolioTotal),
            includedPortfolioHoldings: derived.includedPortfolioHoldings,
            includedPortfolioHoldingsBySymbol: Dictionary(
                grouping: derived.includedPortfolioHoldings, by: { $0.symbol.uppercased() }
            ),
            uniqueWalletPriceRequestCoins: derived.uniquePriceRequestCoins,
            portfolio: derived.portfolio,
            availableSendCoinsByWalletID: derived.sendCoinsByWalletId,
            availableReceiveCoinsByWalletID: derived.receiveCoinsByWalletId,
            sendEnabledWallets: derived.sendEnabledWalletIds.compactMap { walletByID[$0] },
            receiveEnabledWallets: derived.receiveEnabledWalletIds.compactMap { walletByID[$0] },
            refreshableChainNames: Set(derived.refreshableChainNames),
            signingMaterialWalletIDs: Set(derived.signingMaterialWalletIds),
            privateKeyBackedWalletIDs: Set(derived.privateKeyBackedWalletIds),
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

    /// Phase 1: rebuild the observable derived state.
    private func rebuildWalletDerivedCaches() {
        rebuildWalletDerivedState()
        rebuildDashboardDerivedState()
    }

    /// Phase 2: write the wallet collection to SQLite + Keychain and prune
    /// transactions that no longer reference an active wallet. No network I/O;
    /// safe to call inside the debounce.
    private func persistWalletStateOptimistically() {
        // Wallets persist themselves: every mutation goes through a
        // `StateCommand` that core writes before it returns.
        updateRefreshEngineEntries()
        // Which transactions are orphaned is core's answer now, so this is a
        // round trip rather than a local filter. It runs inside a debounce, so
        // deferring it costs nothing this side was relying on.
        Task { @MainActor [weak self] in await self?.pruneTransactionsForActiveWallets() }
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
        Task { try? await WalletServiceBridge.shared.clearOperationalEvents(chainName: chainName) }
        lastHistoryRefreshAtByChain[chainName] = nil
    }
    /// Drop a deleted wallet's history diagnostics.
    func clearHistoryTracking(for walletID: String) {
        resetHistoryPaginationForWallet(walletID)
        diagnosticsForgetWallet(walletId: walletID)
        chainDiagnosticsState.diagnosticsRevision &+= 1
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
        await pruneTransactionsForActiveWallets()
        await rebuildTransactionDerivedState()
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
}
private extension AppState {
}
