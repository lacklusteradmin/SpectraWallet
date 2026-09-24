import Foundation
extension AppState {
    /// Core resolves the whole thing — grouping, price-request set, and which
    /// coins each wallet can send or receive on. It holds the wallets, so it
    /// hands back coins rather than indices into a list the caller has to
    /// re-walk.
    @discardableResult
    func rebuildWalletDerivedStateFromCore() async -> Bool {
        do {
            let snapshot = try await self.bridge.ready().portfolioSnapshot()
            applyPortfolioSnapshot(snapshot)
            return true
        } catch {
            appendOperationalLog(.error, category: "Portfolio", message: error.localizedDescription)
            return false
        }
    }
    /// Every wallet/quote/dashboard field is adopted together on the main actor.
    func applyPortfolioSnapshot(_ snapshot: PortfolioSnapshot) {
        guard snapshot.revision > portfolioSnapshotRevision else { return }
        guard applyCoreState(snapshot.state) else { return }
        portfolioSnapshotRevision = snapshot.revision
        applyQuoteProjection(snapshot.state)
        portfolioValuation = snapshot.valuation
        adoptAssetPrecision(snapshot.assetPrecision)
        let derived = snapshot.derived
        let walletById = Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0) })
        if wallets != snapshot.wallets { setWalletProjection(snapshot.wallets) }
        walletDerivedCache = WalletDerivedCache(
            walletById: walletById,
            portfolio: derived.portfolio,
            availableSendCoinsByWalletId: derived.sendCoinsByWalletId,
            availableReceiveCoinsByWalletId: derived.receiveCoinsByWalletId,
            sendEnabledWallets: derived.sendEnabledWalletIds.compactMap { walletById[$0] },
            receiveEnabledWallets: derived.receiveEnabledWalletIds.compactMap { walletById[$0] })
        cachedDashboardAssetGroups = snapshot.groups
        cachedAvailableDashboardPinOptions = snapshot.pinOptions
    }
    /// Reconcile background services after a changed wallet projection. Reading
    /// a projection never starts another projection read.
    func applyWalletCollectionSideEffects() {
        guard servicesEnabled else { return }
        walletSideEffectsTask?.cancel()
        walletSideEffectsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self.reconcileBackgroundServices()
            self.walletSideEffectsTask = nil
        }
    }

    /// Core refreshes only when fetch inputs change, and runs its loops only
    /// while there is something to fetch; balance-only updates must not
    /// trigger a sweep.
    private func reconcileBackgroundServices() async {
        _ = try? await self.bridge.refreshEngine().reconcileWallets()
    }

    /// Refresh the bounded recent/pending projection and indexed aggregates together.
    @discardableResult
    func refreshTransactionProjection() async -> Bool {
        do {
            let snapshot = try await self.bridge.ready().transactionSnapshot()
            guard snapshot.revision > transactionSnapshotRevision else { return true }
            transactionSnapshotRevision = snapshot.revision
            adoptTransactionsFromCore(snapshot.recentAndPending)
            replaceableSends = snapshot.replaceable
            transactionCount = snapshot.totalCount
            walletsWithMoreHistory = Set(snapshot.walletsWithMoreHistory)
            cachedFirstActivityDateByWalletId = Dictionary(uniqueKeysWithValues: snapshot.earliest.map {
                ($0.walletId, Date(timeIntervalSince1970: $0.earliestCreatedAtUnix))
            })
            historyReadError = nil
            return true
        } catch {
            historyReadError = localizedStoreString("Unable to read transaction history. Existing records have been kept.")
            return false
        }
    }
}
