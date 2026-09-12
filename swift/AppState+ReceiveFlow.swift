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
        isResolvingReceiveAddress = false
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
    }
    func refreshPendingTransactions(includeHistoryRefreshes: Bool = true, historyRefreshInterval: TimeInterval = 120) async {
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
        let tokenHostingChains = Set(result.chains.compactMap(WalletChainID.init))
        let refreshLastSent: () -> Void = {
            if let lastSentTransaction = self.lastSentTransaction,
                let refreshed = self.transactions.first(where: { $0.id == lastSentTransaction.id })
            {
                self.lastSentTransaction = refreshed
                self.updateSendVerificationNoticeForLastSentTransaction()
            }
        }
        guard includeHistoryRefreshes else { refreshLastSent(); return }
        await runPendingTransactionHistoryRefreshes(for: tokenHostingChains, interval: historyRefreshInterval)
        refreshLastSent()
    }
    var pendingTransactionRefreshStatusText: String? {
        guard let at = lastPendingTransactionRefreshAt else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return AppLocalization.format("Last checked %@", f.localizedString(for: at, relativeTo: Date()))
    }
    func receiveAddress() -> String {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            return "Select a wallet and chain"
        }
        let chainAddress: String?
        // Three rules, which is what the twenty-five-variant resolver this
        // switch replaced actually distinguished: Bitcoin reads its stored
        // account address rather than deriving, Dogecoin resolves nothing of
        // its own, and everything else reads the address stored for the chain.
        //
        // Through `mainnetCounterpart` because a testnet shares its family's
        // slot, and the EVM family shares Ethereum's — which is the same
        // address the chain's own name resolved to before.
        switch CachedCoreHelpers.receiveAddressSource(chainName: receiveCoin.chainName) {
        case .bitcoinAccount: chainAddress = wallet.bitcoinAddress
        case .unavailable: chainAddress = nil
        case .storedForChain:
            chainAddress = resolvedAddress(
                for: wallet,
                chainName: Chain(displayName: receiveCoin.chainName)?.mainnetCounterpart.displayName
                    ?? receiveCoin.chainName)
        }
        // This chain's watch address, not Dogecoin's. The flag is named for
        // the chain being shown and was filled from `dogecoinAddress` whatever
        // that chain was; only core's Dogecoin arm reads it, so the two agreed
        // by luck rather than by construction.
        let hasWatchAddress =
            wallet.address(forChainNamed: receiveCoin.chainName)?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return receiveAddressMessage(
            input: ReceiveAddressMessageInput(
                chainName: receiveCoin.chainName, resolvedAddress: receiveResolvedAddress,
                chainAddress: chainAddress, hasSeed: storedSeedPhrase(for: wallet.id) != nil,
                hasWatchAddress: hasWatchAddress, isResolving: isResolvingReceiveAddress
            ))
    }
    func refreshReceiveAddress() async {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            receiveResolvedAddress = ""; return
        }
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedAddress(for: wallet, chainName: receiveCoin.chainName) else {
                receiveResolvedAddress = ""; return
            }
            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }
            receiveResolvedAddress =
                (try? await activateLiveReceiveAddress(receiveEVMAddress(for: evmAddress), for: wallet, chainName: receiveCoin.chainName)) ?? ""
            return
        }
        // `resolvedAddress(for:chainName:)` states the four exceptions itself
        // (Bitcoin and Dogecoin pick their derivation chain from the selected
        // network, Cardano prefers a stored address, Monero only ever has one).
        // The EVM family returned above; what is left is
        // the UTXO five, which reserve a receive index below, and everything
        // else, which resolves.
        if let chain = Chain(displayName: receiveCoin.chainName), !chain.supportsDeepUTXODiscovery {
            receiveResolvedAddress = await activateLiveReceiveAddress(
                resolvedAddress(for: wallet, chainName: receiveCoin.chainName),
                for: wallet, chainName: receiveCoin.chainName)
            return
        }
        guard receiveCoin.symbol == "BTC" else {
            // The native coin of a chain that hands out reserved receive
            // indices. `supportsDeepUTXODiscovery` is the same fact that decides
            // whether an index is reserved at all.
            let receiveChain = Chain(displayName: receiveCoin.chainName)
            if let receiveChain, receiveChain.supportsDeepUTXODiscovery,
                receiveCoin.symbol == receiveChain.gasTokenSymbol
            {
                receiveResolvedAddress = await reservedReceiveAddress(for: wallet, chainName: receiveCoin.chainName, reserveIfMissing: true) ?? ""
                return
            }
            receiveResolvedAddress = ""
            return
        }
        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty,
            storedSeedPhrase(for: wallet.id) == nil
        {
            receiveResolvedAddress = await activateLiveReceiveAddress(bitcoinAddress, for: wallet, chainName: receiveCoin.chainName)
            return
        }
        guard !isResolvingReceiveAddress else { return }
        isResolvingReceiveAddress = true
        defer { isResolvingReceiveAddress = false }
        do {
            let xpub: String
            if let stored = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
                xpub = stored
            } else if let seedPhrase = storedSeedPhrase(for: wallet.id) {
                xpub = try WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                    mnemonicPhrase: seedPhrase, passphrase: "", accountPath: "m/84'/0'/0'")
            } else {
                receiveResolvedAddress = ""
                return
            }
            let address = try await WalletServiceBridge.shared.fetchBitcoinNextUnusedAddressTyped(xpub: xpub)
            receiveResolvedAddress = await activateLiveReceiveAddress(
                address ?? wallet.bitcoinAddress ?? "", for: wallet, chainName: receiveCoin.chainName
            )
        } catch {
            receiveResolvedAddress = ""
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
        let trimmedSeedPhrase = importDraft.seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }.joined(
            separator: " ")
        // One call, not two: `corePrivateKeyHex` returns the normalised key
        // or nil, so the normaliser and the "is it one" predicate cannot
        // disagree about what normalised means.
        let trimmedPrivateKey = corePrivateKeyHex(rawValue: importDraft.privateKeyInput) ?? ""
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let draft = importDraft
        // Bitcoin's account xpub is the one typed value this flow still reads:
        // it is not an address and has no derived counterpart. The two helpers
        // that stood beside it — a trimmer and an entry splitter — served the
        // per-chain address fields, and those are core's input now.
        let trimmedBitcoinXPub = draft.bitcoinXpubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedChains = Set(draft.selectedChainNames)
        let selectedDerivationPreset = importDraft.seedDerivationPreset
        let selectedDerivationPaths: SeedDerivationPaths = {
            var paths = importDraft.seedDerivationPaths
            paths.isCustomEnabled = true
            return paths
        }()
        let isWatchOnlyImport = importDraft.isWatchOnlyMode
        let isPrivateKeyImport = importDraft.isPrivateKeyImportMode
        let selectedChainNames = importDraft.selectedChainNames
        let defaultWalletNameStartIndex = nextDefaultWalletNameIndex()
        var importedWalletsForRefresh: [ImportedWallet] = []
        guard let primarySelectedChainName = selectedChainNames.first else {
            importError = "Select a chain first."
            return
        }
        let requiresSeedPhrase = !selectedChains.isEmpty && !isWatchOnlyImport && !isPrivateKeyImport
        // Bitcoin's account xpub is not an address and has no derived
        // counterpart, so it stays a typed value. Every other chain's address
        // comes from derivation or validation below — see the slot map.
        let resolvedBitcoinXPub =
            (selectedChains.contains("Bitcoin") && !trimmedBitcoinXPub.isEmpty) ? trimmedBitcoinXPub : nil
        // The key's shape is a field rule, so it is checked while the user is
        // still on the form. Whether the key derives an address is core's, and
        // core refuses the commit — deriving here as well was the last place
        // either front end still derived an import address itself.
        if isPrivateKeyImport {
            guard CachedCoreHelpers.privateKeyHexIsLikely(rawValue: trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex key."
                return
            }
        }
        // Monero derives from the seed like every other chain; what it does not
        // have is a *watched* form, which is what `supports_watch_only_import`
        // says and what this refuses.
        if selectedChains.contains("Monero"), isWatchOnlyImport {
            importError = "Monero watched addresses are not supported in this build."
            return
        }
        // No per-chain address guard belongs here: on the non-watch-only path
        // the typed per-chain fields are always empty — they exist only on the
        // watch-addresses page, and every writer of `isWatchOnlyMode` calls
        // `reset()` first. Watch-only entries are validated by core on the way
        // in.
        // The 16-row watch-only validation table, the Bitcoin address/xpub
        // guard and the seven-chain EVM guard that used to sit here are gone.
        // All three restated per-chain address formats the registry already
        // holds, and core applies the same rule on the way in — including the
        // network mode, which `ImportNetworks` now carries so a testnet watch
        // address is still judged as testnet.
        //
        // What changes: core keeps the valid entries and reports the rest in
        // `rejectedAddresses` instead of refusing the whole import on one bad
        // line. An import with nothing left still fails.
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
                walletName: trimmedWalletName, defaultWalletNameStartIndex: UInt64(defaultWalletNameStartIndex),
                primarySelectedChainName: primarySelectedChainName, selectedChainNames: selectedChainNames,
                plannedWalletIds: [], isWatchOnlyImport: isWatchOnlyImport,
                isPrivateKeyImport: isPrivateKeyImport, hasWalletPassword: trimmedWalletPassword != nil,
                resolvedAddresses: WalletImportAddresses(
                    bySlot: addressSlotMap(addressByChainName),
                    bitcoinXpub: resolvedBitcoinXPub
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
                    bitcoinXpub: resolvedBitcoinXPub
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
                        seedPhrase: requiresSeedPhrase ? trimmedSeedPhrase : nil,
                        privateKey: isPrivateKeyImport ? trimmedPrivateKey : nil
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
        finishWalletImportFlow()
        withAnimation {
        }
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
    func nextDefaultWalletNameIndex() -> Int {
        (wallets.compactMap { $0.name.hasPrefix("Wallet ") ? Int($0.name.dropFirst(7)) : nil }.max() ?? 0) + 1
    }
    /// Build a wallet for one chain from the slot-keyed addresses Rust planned.

    var portfolio: [Coin] { cachedPortfolio }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home }
    var refreshableChainNames: Set<String> { cachedRefreshableChainNames }
    var refreshableChainIDs: Set<WalletChainID> { Set(refreshableChainNames.compactMap(WalletChainID.init)) }
    var backgroundBalanceRefreshFrequencyMinutes: Int { max(preferences.automaticRefreshFrequencyMinutes * 3, 15) }
    func refreshForForegroundIfNeeded() async {
        guard shouldPerformForegroundFullRefresh else { return }
        await performUserInitiatedRefresh(forceChainRefresh: false)
    }
    var shouldPerformForegroundFullRefresh: Bool {
        guard userInitiatedRefreshTask == nil else { return false }
        guard let lastFullRefreshAt else { return true }
        return Date().timeIntervalSince(lastFullRefreshAt) >= Self.foregroundFullRefreshStalenessInterval
    }
    var includedPortfolioWallets: [ImportedWallet] { cachedIncludedPortfolioWallets }
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
