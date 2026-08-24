import Foundation
import SwiftUI
import OrderedCollections
@MainActor
extension AppState {
    func beginReceive() {
        guard let firstWallet = receiveEnabledWallets.first else { return }
        receiveWalletID = firstWallet.id
        receiveChainName = availableReceiveChains(for: receiveWalletID).first ?? ""
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        let availableChains = availableReceiveChains(for: receiveWalletID)
        if !availableChains.contains(receiveChainName) { receiveChainName = availableChains.first ?? "" }
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
        let trackedChains = pendingTransactionMaintenanceChainIDs
        guard !trackedChains.isEmpty else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        isRefreshingPendingTransactions = true
        defer {
            isRefreshingPendingTransactions = false
            recordPerformanceSample(
                "refresh_pending_transactions", startedAt: startedAt,
                metadata: "chains=\(trackedChains.count) include_history=\(includeHistoryRefreshes)"
            )
        }
        lastPendingTransactionRefreshAt = Date()
        let trackedTransactionIDs = Set(
            transactions.compactMap { t -> UUID? in
                guard t.kind == .send, t.transactionHash != nil, t.status == .pending || t.status == .confirmed else { return nil }
                return t.id
            })
        try? await WalletServiceBridge.shared.retainStatusTrackers(
            ids: trackedTransactionIDs.map(\.uuidString))
        await withTaskGroup(of: Void.self) { group in
            for descriptor in Self.chainRefreshDescriptors.values {
                guard trackedChains.contains(descriptor.chainID), let pending = descriptor.executePendingOnly else { continue }
                group.addTask { await pending(self) }
            }
            await group.waitForAll()
        }
        let refreshLastSent: () -> Void = {
            if let lastSentTransaction = self.lastSentTransaction,
                let refreshed = self.transactions.first(where: { $0.id == lastSentTransaction.id })
            {
                self.lastSentTransaction = refreshed
                self.updateSendVerificationNoticeForLastSentTransaction()
            }
        }
        guard includeHistoryRefreshes else { refreshLastSent(); return }
        await runPendingTransactionHistoryRefreshes(for: trackedChains, interval: historyRefreshInterval)
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
        let isEvm = isEVMChain(receiveCoin.chainName)
        let chainAddress: String?
        // Twenty-four arms stood here and twenty of them were
        // `resolved<Chain>Address(for:)`, which is `resolvedChainAddress(for:chain:)`
        // with the chain the case already names. What is left is the four that
        // genuinely differ: Bitcoin reads its stored address rather than
        // deriving, Dogecoin and the unmatched case have none, and the EVM
        // family needs the chain name to pick a network.
        //
        // Through `mainnetCounterpart` because that is what
        // `core_receive_address_resolver` dispatches on — a testnet coin gets
        // its mainnet's case, so it needs its mainnet's resolver.
        switch CachedCoreHelpers.receiveAddressResolver(symbol: receiveCoin.symbol, chainName: receiveCoin.chainName, isEvmChain: isEvm) {
        case .bitcoinLegacy: chainAddress = wallet.bitcoinAddress
        case .dogecoinNone, .none: chainAddress = nil
        case .evm: chainAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName)
        default:
            chainAddress = resolvedAddress(
                for: wallet,
                chainName: Chain(displayName: receiveCoin.chainName)?.mainnetCounterpart.displayName
                    ?? receiveCoin.chainName)
        }
        let hasWatchAddress = wallet.dogecoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return receiveAddressMessage(
            input: ReceiveAddressMessageInput(
                chainName: receiveCoin.chainName, symbol: receiveCoin.symbol, isEvmChain: isEvm, resolvedAddress: receiveResolvedAddress,
                chainAddress: chainAddress, hasSeed: storedSeedPhrase(for: wallet.id) != nil, hasWatchAddress: hasWatchAddress,
                isResolving: isResolvingReceiveAddress
            ))
    }
    func refreshReceiveAddress() async {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            receiveResolvedAddress = ""; return
        }
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else {
                receiveResolvedAddress = ""; return
            }
            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }
            receiveResolvedAddress =
                (try? await activateLiveReceiveAddress(receiveEVMAddress(for: evmAddress), for: wallet, chainName: receiveCoin.chainName)) ?? ""
            return
        }
        // Eighteen `(chainName, resolvedXAddress)` pairs stood here and a linear
        // scan picked the one matching the coin's chain — which is
        // `resolvedAddress(for:chainName:)`, the function that already states
        // the four exceptions (Bitcoin and Dogecoin pick their derivation chain
        // from the selected network, Cardano prefers a stored address, Monero
        // only ever has one). The EVM family returned above; what is left is
        // the UTXO five, which reserve a receive index below, and everything
        // else, which resolves.
        if let chain = Chain(displayName: receiveCoin.chainName), !chain.supportsDeepUTXODiscovery {
            receiveResolvedAddress = await activateLiveReceiveAddress(
                resolvedAddress(for: wallet, chainName: receiveCoin.chainName),
                for: wallet, chainName: receiveCoin.chainName)
            return
        }
        guard receiveCoin.symbol == "BTC" else {
            if (receiveCoin.symbol == "BCH" && receiveCoin.chainName == "Bitcoin Cash")
                || (receiveCoin.symbol == "BSV" && receiveCoin.chainName == "Bitcoin SV")
                || (receiveCoin.symbol == "LTC" && receiveCoin.chainName == "Litecoin")
                || (receiveCoin.symbol == "DOGE" && receiveCoin.chainName == "Dogecoin")
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
            renameWallet(id: editingWalletID, to: trimmedWalletName)
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
        let trimmedPrivateKey = corePrivateKeyHexNormalized(rawValue: importDraft.privateKeyInput)
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
        // A private-key import selects exactly one chain — core's
        // `plan_signing_import` refuses more — so this is one address, derived
        // once here and recorded below rather than derived twice.
        var privateKeyAddress: String?
        if isPrivateKeyImport {
            guard CachedCoreHelpers.privateKeyHexIsLikely(rawValue: trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex key."
                return
            }
            // The picker is built from `coreSupportedPrivateKeyChainNames`, so
            // this can only fire if a selection outlived the list it came from.
            // Kept because it is a key path: refuse before deriving.
            let unsupported = importDraft.unsupportedPrivateKeyChainNames
            guard unsupported.isEmpty else {
                importError = AppLocalization.format(
                    "Private key import is not available for: %@.", unsupported.joined(separator: ", "))
                return
            }
            guard
                let primaryChain = Chain(displayName: primarySelectedChainName),
                let address = derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chain: primaryChain)
            else {
                importError = "Unable to derive an address from this key."
                return
            }
            privateKeyAddress = address
        }
        // Monero derives from the seed like every other chain; what it does not
        // have is a *watched* form, which is what `supports_watch_only_import`
        // says and what this refuses.
        if selectedChains.contains("Monero"), isWatchOnlyImport {
            importError = "Monero watched addresses are not supported in this build."
            return
        }
        // The Cardano guard that stood here validated `typed("Cardano")` on the
        // *non*-watch-only path, where that value is always empty: the per-chain
        // address fields exist only on the watch-addresses page, and all three
        // writers of `isWatchOnlyMode` call `reset()` first, which clears them.
        // So the guard could not fire, and Cardano's address comes from
        // derivation like every other chain's. Watch-only entries are validated
        // by core on the way in.
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
            var addressByChainName: [String: String] = [:]
            func record(_ chainName: String, _ address: String?) {
                guard let address, !address.isEmpty else { return }
                addressByChainName[chainName] = address
            }
            let createdWalletIDs = selectedChainNames.map { _ in UUID() }
            let bitcoinWalletID = zip(selectedChainNames, createdWalletIDs).first(where: { $0.0 == "Bitcoin" })?.1
            if requiresSeedPhrase {
                // Derivation paths for the chains being imported, keyed by
                // chain display name. Every EVM chain derives from Ethereum's
                // path, which is what `Chain.seedDerivationPathKey` already
                // encodes — so this is a loop over the selection rather than a
                // 30-entry table of (isSelected, chainName, path) triples.
                //
                // An empty path is not a reason to skip a chain. Monero has
                // none — its keys come from the seed — and skipping it here is
                // what made a Monero import impossible: the batch produced no
                // address for it, so the guard below demanded a typed one, and
                // the only field to type it into was on the watch-only page a
                // seed import never sees.
                var chainPaths: [String: String] = [:]
                for chainName in selectedChains {
                    guard let chain = Chain(displayName: chainName) else { continue }
                    chainPaths[chainName] = selectedDerivationPaths.path(for: chain)
                }
                // EVM chains share one derived address, produced under the
                // Ethereum entry, so ensure it is present whenever any EVM
                // chain is selected even if Ethereum itself is not.
                if chainPaths["Ethereum"] == nil, selectedChains.contains(where: { (Chain(displayName: $0)?.isEVM ?? false) }) {
                    let ethereumPath = selectedDerivationPaths.path(for: .ethereum)
                    if !ethereumPath.isEmpty { chainPaths["Ethereum"] = ethereumPath }
                }
                do {
                    let overrides = draft.resolvedDerivationOverrides
                    let derived: [String: String]
                    if overrides.isEmpty {
                        // Fast path: Rust batch-derives all chains with preset defaults.
                        derived = try WalletRustDerivationBridge.deriveAllAddresses(
                            seedPhrase: trimmedSeedPhrase, chainPaths: chainPaths)
                    } else {
                        // Advanced mode: re-derive each chain individually so the power-user
                        // overrides (passphrase / wordlist / iteration count / algorithm
                        // overrides) actually affect the produced addresses.
                        var perChain: [String: String] = [:]
                        for (chainName, path) in chainPaths {
                            guard let chain = Chain(displayName: chainName) else { continue }
                            if let address = try? WalletDerivationLayer.deriveAddress(
                                seedPhrase: trimmedSeedPhrase, chain: chain,
                                derivationPath: path, overrides: overrides
                            ) {
                                perChain[chainName] = address
                            }
                        }
                        derived = perChain
                    }
                    if selectedChains.contains("Bitcoin") {
                        guard let bitcoinWalletID else {
                            importError = "Bitcoin wallet initialization failed."
                            return
                        }
                        _ = bitcoinWalletID
                    }
                    // `derived` is already keyed by chain display name, so
                    // unpacking it into 24 locals and repacking it was pure
                    // transcription.
                    addressByChainName = derived
                } catch {
                    let resolvedMessage =
                        (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    if resolvedMessage.isEmpty || resolvedMessage == "(null)" {
                        importError = "Wallet initialization failed. Check the seed phrase."
                    } else {
                        importError = resolvedMessage
                    }
                    return
                }
            } else if let privateKeyAddress {
                // Core dispatches private-key derivation by chain, so there is
                // nothing to switch on: one address, for the one chain a
                // private-key import may select.
                record(primarySelectedChainName, privateKeyAddress)
                // An EVM key is the same address on both EVM slots. Ethereum
                // Classic has its own — `Chain::address_slot` says so — and
                // `addresses_for_chain` reads whichever slot the planned
                // wallet's chain names, so fill both and let core pick.
                if Chain(displayName: primarySelectedChainName)?.isEVM == true {
                    record("Ethereum", privateKeyAddress)
                    record("Ethereum Classic", privateKeyAddress)
                }
            }
            let plannedWalletIDs: [UUID]
            if isWatchOnlyImport {
                // `ImportDraft` already keeps the inputs as one table, and
                // `coreIsEvmChain` already answers EVM membership — the 22-row
                // copy and the 23-name EVM set that used to be here restated
                // both. An EVM chain's entries live under Ethereum because the
                // whole family shares that address slot.
                let watchOnlyWalletCount: Int = {
                    if primarySelectedChainName == "Bitcoin", let x = resolvedBitcoinXPub, !x.isEmpty { return 1 }
                    let sourceChain =
                        (Chain(displayName: primarySelectedChainName)?.isEVM ?? false) ? "Ethereum" : primarySelectedChainName
                    let input = draft.watchOnlyInputsByChainName[sourceChain] ?? ""
                    return draft.watchOnlyEntries(from: input).count
                }()
                guard watchOnlyWalletCount > 0 else {
                    importError = "Enter at least one valid address to import."
                    return
                }
                plannedWalletIDs = (0..<watchOnlyWalletCount).map { _ in UUID() }
            } else {
                plannedWalletIDs = selectedChainNames.map { _ in UUID() }
            }
            let importPlanRequest = WalletImportRequest(
                walletName: trimmedWalletName, defaultWalletNameStartIndex: UInt64(defaultWalletNameStartIndex),
                primarySelectedChainName: primarySelectedChainName, selectedChainNames: selectedChainNames,
                plannedWalletIds: plannedWalletIDs.map(\.uuidString), isWatchOnlyImport: isWatchOnlyImport,
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
            // Core plans, builds and stores the wallets in one call. What comes
            // back is what it created, plus the Keychain writes below — the only
            // part of an import that is genuinely platform work.
            let outcome: WalletImportOutcome
            do {
                outcome = try await WalletServiceBridge.shared.importWallets(
                    WalletImportCommit(
                        request: importPlanRequest,
                        holdings: coins,
                        seedDerivationPreset: selectedDerivationPreset,
                        seedDerivationPaths: selectedDerivationPaths,
                        derivationOverrides: draft.resolvedDerivationOverrides,
                        networkChainByFamily: networkChainByFamily
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
            // The Keychain writes are the one part of an import that can fail
            // after core has already committed the wallets. A failure here is
            // reported, never swallowed: a wallet that looks imported but whose
            // seed was never stored is worse than a visible error.
            var secretStorageFailure: Error? = nil
            for instruction in outcome.secretInstructions {
                let walletID = instruction.walletId
                let account = resolvedSeedPhraseAccount(for: walletID)
                let passwordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
                let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
                do {
                    if instruction.shouldStoreSeedPhrase {
                        try SecureSeedStore.save(trimmedSeedPhrase, for: account)
                    } else {
                        try SecureSeedStore.deleteValue(for: account)
                    }
                    if instruction.shouldStorePasswordVerifier, let trimmedWalletPassword {
                        try SecureSeedPasswordStore.save(trimmedWalletPassword, for: passwordAccount)
                    } else {
                        try SecureSeedPasswordStore.deleteValue(for: passwordAccount)
                    }
                    if instruction.shouldStorePrivateKey {
                        try SecurePrivateKeyStore.save(trimmedPrivateKey, for: privateKeyAccount)
                    } else {
                        try SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
                    }
                } catch {
                    secretStorageFailure = error
                    break
                }
            }
            // Core already stored them; re-read the projection from core rather
            // than appending locally, so the two cannot disagree. This runs even
            // when the Keychain writes failed, so the list the user is looking
            // at matches what core actually holds.
            if let stored = try? await WalletServiceBridge.shared.storedWallets() {
                setWalletProjection(stored)
            }
            if let secretStorageFailure {
                let detail = secretStorageFailure.localizedDescription
                importError = """
                    The wallet was created, but its signing secret could not be saved to the Keychain, so it cannot sign \
                    transactions and the seed phrase cannot be revealed. Delete the wallet and import it again. (\(detail))
                    """
                return
            }
            importedWalletsForRefresh = createdWallets
        }
        finishWalletImportFlow()
        withAnimation {
        }
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: String, to newName: String) {
        guard var wallet = wallets.first(where: { $0.id == id }) else { return }
        wallet.name = newName
        recordWalletDetached(wallet)
        finishWalletImportFlow()
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
    /// Was a seventeen-field record and a twenty-arm switch on chain names —
    /// twelve of whose arms named chains core cannot derive from a key, and
    /// which was missing Decred, which core can. `Chain::derives_from_private_key`
    /// is the one answer now, and the picker is built from it, so a chain the
    /// user can select is a chain this returns an address for.
    func derivePrivateKeyImportAddress(privateKeyHex: String, chain: Chain) -> String? {
        try? WalletRustDerivationBridge.deriveFromPrivateKey(chain: chain, privateKeyHex: privateKeyHex).address
    }
    static func deriveSeedPhraseAddress(
        seedPhrase: String, chain: Chain, derivationPath: String
    ) throws -> String {
        try WalletDerivationLayer.deriveAddress(seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath)
    }
    func deriveSeedPhraseAddress(seedPhrase: String, chain: Chain, derivationPath: String)
        throws -> String
    { try Self.deriveSeedPhraseAddress(seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) }
    func utxoDiscoveryDerivationChain(for chainName: String) -> Chain? {
        [
            "Bitcoin": Chain.bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSv, "Litecoin": .litecoin,
            "Dogecoin": .dogecoin,
        ][chainName]
    }
    func walletDisplayName(baseName: String, batchPosition: Int, defaultWalletIndex: Int, selectedChainCount: Int) -> String {
        // Delegates to Rust `wallet_display_name`. Swift keeps the `Int` overload
        // so callers don't have to convert.
        let baseTrimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseTrimmed.isEmpty { return "Wallet \(defaultWalletIndex)" }
        return selectedChainCount > 1 ? "\(baseTrimmed) \(batchPosition)" : baseTrimmed
    }
    func nextDefaultWalletNameIndex() -> Int {
        (wallets.compactMap { $0.name.hasPrefix("Wallet ") ? Int($0.name.dropFirst(7)) : nil }.max() ?? 0) + 1
    }
    /// Build a wallet for one chain from the slot-keyed addresses Rust planned.
    func walletByReplacingHoldings(_ wallet: ImportedWallet, with holdings: [Coin]) -> ImportedWallet {
        var updated = wallet
        updated.holdings = holdings
        return updated
    }
    var portfolio: [Coin] { cachedPortfolio }
    var priceRequestCoins: [Coin] {
        var grouped: [String: Coin] = [:]
        var order: [String] = []
        for coin in cachedUniqueWalletPriceRequestCoins where isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            grouped[key] = coin
            order.append(key)
        }
        for coin in dashboardPinnedAssetPricingPrototypes
        where selectedMainTab == .home && isPricedAsset(coin) {
            let key = activePriceKey(for: coin)
            guard grouped[key] == nil else { continue }
            grouped[key] = coin
            order.append(key)
        }
        return order.compactMap { grouped[$0] }
    }
    var hasLivePriceRefreshWork: Bool { !priceRequestCoins.isEmpty }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home && hasLivePriceRefreshWork }
    var hasPendingTransactionMaintenanceWork: Bool {
        transactions.contains { transaction in
            guard transaction.kind == .send, transaction.transactionHash != nil else { return false }
            if transaction.status == .pending { return true }
            return transaction.status == .confirmed
        }
    }
    var pendingTransactionMaintenanceChains: Set<String> {
        Set(
            transactions.compactMap { transaction -> String? in
                guard transaction.kind == .send, transaction.transactionHash != nil else { return nil }
                if transaction.status == .pending { return transaction.chainName }
                if transaction.chainName == "Dogecoin", transaction.status == .confirmed { return transaction.chainName }
                return nil
            }
        )
    }
    var pendingTransactionMaintenanceChainIDs: Set<WalletChainID> {
        Set(pendingTransactionMaintenanceChains.compactMap(WalletChainID.init))
    }
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
    func currentOrFallbackPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        if let livePrice = currentPriceIfAvailable(for: coin) { return livePrice }
        guard coin.priceUsd > 0 else { return nil }
        return coin.priceUsd
    }
    func currentPrice(for coin: Coin) -> Double { currentPriceIfAvailable(for: coin) ?? 0 }
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd { return 1.0 }
        guard let rate = fiatRatesFromUSD[currency.rawValue], rate > 0 else { return nil }
        return rate
    }
    func fiatRate(for currency: FiatCurrency) -> Double { fiatRateIfAvailable(for: currency) ?? (currency == .usd ? 1.0 : 0) }
    func persistAssetDisplayDecimalsByChain() {
        persistCodableToSQLite(assetDisplayDecimalsByChain, key: Self.assetDisplayDecimalsByChainDefaultsKey)
    }
}
