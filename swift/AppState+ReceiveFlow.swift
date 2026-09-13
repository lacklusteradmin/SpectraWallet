import Foundation
import SwiftUI
import OrderedCollections
@MainActor
extension AppState {
    func beginReceive() {
        guard let firstWallet = receiveEnabledWallets.first else { return }
        receiveWalletID = firstWallet.id
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestID = UUID()
        isResolvingReceiveAddress = false
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestID = UUID()
        isResolvingReceiveAddress = false
    }
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestID = UUID()
        isResolvingReceiveAddress = false
    }
    func refreshPendingTransactions() async {
        guard !isRefreshingPendingTransactions else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        isRefreshingPendingTransactions = true
        defer {
            isRefreshingPendingTransactions = false
            recordPerformanceSample("refresh_pending_transactions", startedAt: startedAt)
        }
        let result: PendingMaintenanceResult
        do {
            result = try await WalletServiceBridge.shared.refreshPendingTransactions()
        } catch {
            appendOperationalLog(.error, category: "Pending Transactions", message: error.localizedDescription)
            return
        }
        lastPendingTransactionRefreshAt = Date()
        for failure in result.failures {
            appendOperationalLog(.error, category: "Pending Transactions", message: failure.message,
                chainName: WalletChainID(failure.chainId)?.displayName)
        }
        if !result.changes.isEmpty { await applyPendingStatusChanges(result.changes) }
        let refreshLastSent: () -> Void = {
            if let lastSentTransaction = self.lastSentTransaction,
                let refreshed = self.transactions.first(where: { $0.id == lastSentTransaction.id })
            {
                self.lastSentTransaction = refreshed
                self.updateSendVerificationNoticeForLastSentTransaction()
            }
        }
        refreshLastSent()
    }
    var pendingTransactionRefreshStatusText: String? {
        guard let at = lastPendingTransactionRefreshAt else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return AppLocalization.format("Last checked %@", f.localizedString(for: at, relativeTo: Date()))
    }
    func refreshReceiveAddress() async {
        let requestID = UUID()
        receiveAddressRequestID = requestID
        receiveResolvedAddress = ""
        receiveAddressError = nil
        isResolvingReceiveAddress = false
        guard let wallet = wallet(for: receiveWalletID),
            let coin = selectedReceiveCoin(for: receiveWalletID),
            let chain = Chain(displayName: coin.chainName) else { return }
        isResolvingReceiveAddress = true
        defer {
            if receiveAddressRequestID == requestID { isResolvingReceiveAddress = false }
        }
        do {
            let address = try await WalletServiceBridge.shared.receiveAddress(
                walletID: wallet.id, chainId: chain.id, reserve: true)
            guard !Task.isCancelled, receiveAddressRequestID == requestID,
                receiveWalletID == wallet.id, receiveHoldingKey == coin.holdingKey else { return }
            receiveResolvedAddress = address ?? ""
            if address == nil { receiveAddressError = AppLocalization.string("No receive address is available for this wallet and network.") }
        } catch {
            guard !Task.isCancelled, receiveAddressRequestID == requestID else { return }
            receiveAddressError = error.localizedDescription
        }
    }
    func importWallet() async {
        guard canImportWallet else { return }
        guard !isImportingWallet else { return }
        let trimmedWalletName = importDraft.walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingWalletID {
            await renameWallet(id: editingWalletID, to: trimmedWalletName)
            return
        }
        if importDraft.requiresBackupVerification && !importDraft.isBackupVerificationComplete {
            importError = "Confirm your seed backup words before importing the wallet."
            return
        }
        isImportingWallet = true
        defer { isImportingWallet = false }
        let coins = importDraft.selectedCoins
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let draft = importDraft
        let selectedDerivationPreset = importDraft.seedDerivationPreset
        let selectedDerivationPaths: SeedDerivationPaths = {
            var paths = importDraft.seedDerivationPaths
            paths.isCustomEnabled = true
            return paths
        }()
        let isWatchOnlyImport = importDraft.isWatchOnlyMode
        let isPrivateKeyImport = importDraft.isPrivateKeyImportMode
        let selectedChainNames = importDraft.selectedChainNames
        var importedWalletsForRefresh: [WalletView] = []
        guard let primarySelectedChainName = selectedChainNames.first else {
            importError = "Select a chain first."
            return
        }
        if editingWalletID == nil {
            // One table keyed by chain display name, not 25 optionals and a
            // 25-row slot map restating them. Both branches below fill it and
            // `WalletImportAddresses.slotMap` turns it into slots, so adding a
            // chain touches neither.
            // Neither a seed import nor a private-key import fills this: core
            // derives from whichever secret the commit carries, so the
            // address-slot rules stay in core rather than in the importer.
            // Only the watch-only path supplies addresses, and it supplies
            // typed ones, through `watchOnlyEntries`.
            let addressByChainName: [String: String] = [:]
            // Core mints the ids for the wallets it creates. Supplying them
            // meant predicting how many there would be — which for a
            // watch-only import meant parsing the address entries the same way
            // the planner does, under a second copy of the "which chain's
            // input holds them" rule, and being refused when the two counts
            // disagreed. An import with no valid entry is still refused, by
            // the planner that read them.
            let importPlanRequest = WalletImportRequest(
                walletName: trimmedWalletName,
                primarySelectedChainName: primarySelectedChainName, selectedChainNames: selectedChainNames,
                plannedWalletIds: [], isWatchOnlyImport: isWatchOnlyImport,
                isPrivateKeyImport: isPrivateKeyImport, hasWalletPassword: trimmedWalletPassword != nil,
                resolvedAddresses: WalletImportAddresses(
                    bySlot: addressSlotMap(addressByChainName),
                    bitcoinXpub: draft.bitcoinXpubInput
                ),
                // `ImportDraft` already keeps the per-chain inputs as one
                // table and maps it to slots, so this restated all 23 rows for
                // nothing. The per-chain normalising that came with them is
                // gone too: core normalises every address it accepts, and
                // `the_send_normaliser_and_the_import_normaliser_agree` pins
                // that its answer matches the `normalizedSendAddress` these
                // call sites were using.
                watchOnlyEntries: WalletImportWatchOnlyEntries(
                    bySlot: draft.watchOnlyEntriesBySlot,
                    bitcoinXpub: draft.bitcoinXpubInput
                )
            )
            // Core derives addresses, stores secrets through the registered
            // callback and commits the entire wallet batch before returning.
            let outcome: WalletImportOutcome
            do {
                outcome = try await WalletServiceBridge.shared.importWallets(
                    WalletImportCommit(
                        password: trimmedWalletPassword,
                        request: importPlanRequest,
                        holdings: coins,
                        seedDerivationPreset: selectedDerivationPreset,
                        seedDerivationPaths: selectedDerivationPaths,
                        derivationOverrides: draft.resolvedDerivationOverrides,
                        networkChainByFamily: networkChainByFamily,
                        seedPhrase: draft.seedPhrase,
                        privateKey: draft.privateKeyInput
                    )
                )
            } catch {
                importError = error.localizedDescription
                return
            }
            // Core refuses addresses that do not parse for their chain. Wallets
            // it did create are already stored, so this is a notice rather than
            // a failure — but it has to be shown. Dropping it silently is how a
            // typo becomes a wallet whose receive address is missing.
            if !outcome.rejectedAddresses.isEmpty {
                // Interpolation rather than a `+` chain: a multi-line `+`
                // concatenation in this function is enough to time out the
                // type-checker and produce phantom errors elsewhere in the file.
                let refused = outcome.rejectedAddresses.joined(separator: ", ")
                importError = "These addresses were not valid and were not imported: \(refused)"
            }
            let createdWallets = outcome.wallets
            if let stored = try? await WalletServiceBridge.shared.storedWallets() {
                adoptWalletsFromCore(stored)
            }
            importedWalletsForRefresh = createdWallets
        }
        await rebuildWalletDerivedStateFromCore()
        finishWalletImportFlow()
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: String, to newName: String) async {
        changeWallet(.renameWallet(walletId: id, name: newName))
        await walletMutationTask?.value
        if importError == nil { finishWalletImportFlow() }
    }
    func finishWalletImportFlow() {
        importError = nil
        importDraft.clearSensitiveInputs()
        resetImportForm()
        editingWalletID = nil
        isShowingWalletImporter = false
        // Also pop the Add Wallet entry page so the user lands back on
        // Dashboard after a successful import — they started on Dashboard,
        // pushed Add Wallet, pushed the Importer, and shouldn't be stranded
        // on the intermediate Add Wallet page after finishing.
        isShowingAddWalletEntry = false
    }
    /// The address a raw private key yields on `chain`, or `nil` when the key
    /// does not produce one there.
    ///
    /// Build a wallet for one chain from the slot-keyed addresses Rust planned.

    var portfolio: [Coin] { cachedPortfolio }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home }
    var refreshableChainNames: Set<String> { cachedRefreshableChainNames }
    var refreshableChainIDs: Set<WalletChainID> { Set(refreshableChainNames.compactMap(WalletChainID.init)) }
    func refreshForForegroundIfNeeded() async {
        await performCoreRefresh(.foreground)
    }
    var includedPortfolioWallets: [WalletView] { cachedIncludedPortfolioWallets }
    func currentPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        return livePrices[activePriceKey(for: coin)]
    }
    func currentPrice(for coin: Coin) -> Double { currentPriceIfAvailable(for: coin) ?? 0 }
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd { return 1.0 }
        guard let rate = fiatRatesFromUSD[currency.rawValue], rate > 0 else { return nil }
        return rate
    }
    func fiatRate(for currency: FiatCurrency) -> Double { fiatRateIfAvailable(for: currency) ?? (currency == .usd ? 1.0 : 0) }
}
