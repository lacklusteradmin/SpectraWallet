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
        return localizedStoreFormat("Last checked %@", f.localizedString(for: at, relativeTo: Date()))
    }
    func receiveAddress() -> String {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            return "Select a wallet and chain"
        }
        let isEvm = isEVMChain(receiveCoin.chainName)
        let chainAddress: String?
        switch CachedCoreHelpers.receiveAddressResolver(symbol: receiveCoin.symbol, chainName: receiveCoin.chainName, isEvmChain: isEvm) {
        case .bitcoinLegacy: chainAddress = wallet.bitcoinAddress
        case .bitcoinCash: chainAddress = resolvedBitcoinCashAddress(for: wallet)
        case .bitcoinSv: chainAddress = resolvedBitcoinSVAddress(for: wallet)
        case .litecoin: chainAddress = resolvedLitecoinAddress(for: wallet)
        case .dogecoinNone: chainAddress = nil
        case .evm: chainAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName)
        case .tron: chainAddress = resolvedTronAddress(for: wallet)
        case .solana: chainAddress = resolvedSolanaAddress(for: wallet)
        case .cardano: chainAddress = resolvedCardanoAddress(for: wallet)
        case .xrp: chainAddress = resolvedXRPAddress(for: wallet)
        case .stellar: chainAddress = resolvedStellarAddress(for: wallet)
        case .monero: chainAddress = resolvedMoneroAddress(for: wallet)
        case .sui: chainAddress = resolvedSuiAddress(for: wallet)
        case .aptos: chainAddress = resolvedAptosAddress(for: wallet)
        case .ton: chainAddress = resolvedTONAddress(for: wallet)
        case .icp: chainAddress = resolvedICPAddress(for: wallet)
        case .near: chainAddress = resolvedNearAddress(for: wallet)
        case .polkadot: chainAddress = resolvedPolkadotAddress(for: wallet)
        case .zcash: chainAddress = resolvedZcashAddress(for: wallet)
        case .bitcoinGold: chainAddress = resolvedBitcoinGoldAddress(for: wallet)
        case .decred: chainAddress = resolvedDecredAddress(for: wallet)
        case .kaspa: chainAddress = resolvedKaspaAddress(for: wallet)
        case .dash: chainAddress = resolvedDashAddress(for: wallet)
        case .bittensor: chainAddress = resolvedBittensorAddress(for: wallet)
        case .none: chainAddress = nil
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
        let liveResolvers: [(String, (ImportedWallet) -> String?)] = [
            ("Tron", { self.resolvedTronAddress(for: $0) }), ("Solana", { self.resolvedSolanaAddress(for: $0) }),
            ("Cardano", { self.resolvedCardanoAddress(for: $0) }), ("XRP Ledger", { self.resolvedXRPAddress(for: $0) }),
            ("Stellar", { self.resolvedStellarAddress(for: $0) }), ("Monero", { self.resolvedMoneroAddress(for: $0) }),
            ("Sui", { self.resolvedSuiAddress(for: $0) }), ("Aptos", { self.resolvedAptosAddress(for: $0) }),
            ("TON", { self.resolvedTONAddress(for: $0) }), ("Internet Computer", { self.resolvedICPAddress(for: $0) }),
            ("NEAR", { self.resolvedNearAddress(for: $0) }), ("Polkadot", { self.resolvedPolkadotAddress(for: $0) }),
            ("Zcash", { self.resolvedZcashAddress(for: $0) }),
            ("Bitcoin Gold", { self.resolvedBitcoinGoldAddress(for: $0) }),
            ("Decred", { self.resolvedDecredAddress(for: $0) }),
            ("Kaspa", { self.resolvedKaspaAddress(for: $0) }),
            ("Dash", { self.resolvedDashAddress(for: $0) }),
            ("Bittensor", { self.resolvedBittensorAddress(for: $0) }),
        ]
        for (chainName, resolver) in liveResolvers where receiveCoin.chainName == chainName {
            receiveResolvedAddress = await activateLiveReceiveAddress(resolver(wallet), for: wallet, chainName: chainName)
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
        func tr(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func entries(_ s: String) -> [String] { draft.watchOnlyEntries(from: s) }
        // The trimmed per-chain inputs, from the one table `ImportDraft`
        // keeps. This was 24 pairs of `let typedXAddress = tr(draft.xInput)`
        // and `let xAddressEntries = entries(draft.xInput)` — the same table
        // written out twice, by hand, in a file that already had two more
        // copies of it further down.
        let typedByChainName = draft.watchOnlyInputsByChainName.mapValues(tr)
        func typed(_ chainName: String) -> String { typedByChainName[chainName] ?? "" }
        let trimmedBitcoinXPub = tr(draft.bitcoinXpubInput)
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
        if isPrivateKeyImport {
            guard CachedCoreHelpers.privateKeyHexIsLikely(rawValue: trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex key."
                return
            }
            guard selectedChainNames.allSatisfy({ chainSupportsPrivateKeyImport(chainName: $0) }) else {
                importError = "Private key import currently supports every chain in this build except Monero."
                return
            }
            let derivedAddress = derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
            guard
                derivedAddress.bitcoin != nil || derivedAddress.bitcoinCash != nil || derivedAddress.bitcoinSV != nil
                    || derivedAddress.litecoin != nil || derivedAddress.dogecoin != nil || derivedAddress.evm != nil
                    || derivedAddress.tron != nil || derivedAddress.solana != nil || derivedAddress.xrp != nil
                    || derivedAddress.stellar != nil || derivedAddress.cardano != nil || derivedAddress.sui != nil
                    || derivedAddress.aptos != nil || derivedAddress.ton != nil || derivedAddress.icp != nil || derivedAddress.near != nil
                    || derivedAddress.polkadot != nil
            else {
                importError = "Unable to derive an address from this key."
                return
            }
        }
        if selectedChains.contains("Monero") {
            if typed("Monero").isEmpty || !AddressValidation.isValid(typed("Monero"), kind: "monero") {
                importError = localizedStoreString("Enter a valid Monero address.")
                return
            }
            if isWatchOnlyImport {
                importError = "Monero watched addresses are not supported in this build."
                return
            }
        }
        if selectedChains.contains("Cardano") && !isWatchOnlyImport {
            if !typed("Cardano").isEmpty,
                !AddressValidation.isValid(typed("Cardano"), kind: "cardano")
            {
                importError = localizedStoreString("Enter a valid Cardano address.")
                return
            }
        }
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
                // path, which is what `coreSeedDerivationPathKey` already
                // encodes — so this is a loop over the selection rather than a
                // 30-entry table of (isSelected, chainName, path) triples.
                var chainPaths: [String: String] = [:]
                for chainName in selectedChains {
                    guard let chain = SeedDerivationChain(rawValue: chainName) else { continue }
                    let path = selectedDerivationPaths.path(for: chain)
                    guard !path.isEmpty else { continue }
                    chainPaths[chainName] = path
                }
                // EVM chains share one derived address, produced under the
                // Ethereum entry, so ensure it is present whenever any EVM
                // chain is selected even if Ethereum itself is not.
                if chainPaths["Ethereum"] == nil, selectedChains.contains(where: { coreIsEvmChain(chainName: $0) }) {
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
                            guard let chain = SeedDerivationChain(rawValue: chainName) else { continue }
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
                    // Monero is not in the batch derivation, so the address the
                    // user supplied is its only source. The guard above has
                    // already refused an invalid one.
                    record("Monero", typed("Monero"))
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
            } else {
                let derivedPrivateKeyAddress =
                    isPrivateKeyImport
                    ? derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
                    : PrivateKeyImportAddressResolution(
                        bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil,
                        xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
                // The typed values are no longer filtered here: core drops
                // what does not validate and reports it, so a second copy of
                // the format rules on this side only risks disagreeing with it.
                record("Bitcoin", derivedPrivateKeyAddress.bitcoin)
                record("Bitcoin Cash", derivedPrivateKeyAddress.bitcoinCash ?? typed("Bitcoin Cash"))
                record("Bitcoin SV", derivedPrivateKeyAddress.bitcoinSV ?? typed("Bitcoin SV"))
                record("Litecoin", derivedPrivateKeyAddress.litecoin ?? typed("Litecoin"))
                record("Dogecoin", derivedPrivateKeyAddress.dogecoin ?? typed("Dogecoin"))
                let evmAddress = derivedPrivateKeyAddress.evm ?? typed("Ethereum")
                record("Ethereum", evmAddress)
                // Ethereum Classic has its own slot but the same key material.
                record("Ethereum Classic", evmAddress)
                record("Tron", derivedPrivateKeyAddress.tron ?? typed("Tron"))
                record("Solana", derivedPrivateKeyAddress.solana ?? typed("Solana"))
                record("XRP Ledger", derivedPrivateKeyAddress.xrp ?? typed("XRP Ledger"))
                record("Stellar", derivedPrivateKeyAddress.stellar ?? typed("Stellar"))
                record("Monero", typed("Monero"))
                record("Cardano", derivedPrivateKeyAddress.cardano ?? typed("Cardano"))
                record("Sui", derivedPrivateKeyAddress.sui ?? typed("Sui"))
                record("Aptos", derivedPrivateKeyAddress.aptos ?? typed("Aptos"))
                record("TON", derivedPrivateKeyAddress.ton ?? typed("TON"))
                record("Internet Computer", derivedPrivateKeyAddress.icp ?? typed("Internet Computer"))
                record("NEAR", derivedPrivateKeyAddress.near ?? typed("NEAR"))
                record("Polkadot", derivedPrivateKeyAddress.polkadot ?? typed("Polkadot"))
                record("Zcash", typed("Zcash"))
                record("Bitcoin Gold", typed("Bitcoin Gold"))
                record("Decred", typed("Decred"))
                record("Kaspa", typed("Kaspa"))
                record("Dash", typed("Dash"))
                record("Bittensor", typed("Bittensor"))
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
                        coreIsEvmChain(chainName: primarySelectedChainName) ? "Ethereum" : primarySelectedChainName
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
                    bySlot: WalletImportAddresses.slotMap(addressByChainName),
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
                        derivationOverrides: draft.resolvedDerivationOverrides ?? .empty,
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
    struct PrivateKeyImportAddressResolution {
        var bitcoin: String? = nil; var bitcoinCash: String? = nil; var bitcoinSV: String? = nil
        var litecoin: String? = nil; var dogecoin: String? = nil; var evm: String? = nil
        var tron: String? = nil; var solana: String? = nil; var xrp: String? = nil
        var stellar: String? = nil; var cardano: String? = nil; var sui: String? = nil
        var aptos: String? = nil; var ton: String? = nil; var icp: String? = nil
        var near: String? = nil; var polkadot: String? = nil
        static func only(
            bitcoin: String? = nil, bitcoinCash: String? = nil, bitcoinSV: String? = nil, litecoin: String? = nil, dogecoin: String? = nil,
            evm: String? = nil, tron: String? = nil, solana: String? = nil, xrp: String? = nil, stellar: String? = nil,
            cardano: String? = nil, sui: String? = nil, aptos: String? = nil, ton: String? = nil, icp: String? = nil, near: String? = nil,
            polkadot: String? = nil
        ) -> Self {
            Self(
                bitcoin: bitcoin, bitcoinCash: bitcoinCash, bitcoinSV: bitcoinSV, litecoin: litecoin, dogecoin: dogecoin, evm: evm,
                tron: tron, solana: solana, xrp: xrp, stellar: stellar, cardano: cardano, sui: sui, aptos: aptos, ton: ton, icp: icp,
                near: near, polkadot: polkadot)
        }
    }
    func derivePrivateKeyImportAddress(privateKeyHex: String, chainName: String?) -> PrivateKeyImportAddressResolution {
        guard let chainName else { return .only() }
        func derive(_ chain: SeedDerivationChain) -> String? {
            try? WalletRustDerivationBridge.deriveFromPrivateKey(chain: chain, privateKeyHex: privateKeyHex).address
        }
        switch chainName {
        case "Bitcoin": return .only(bitcoin: derive(.bitcoin))
        case "Bitcoin Cash": return .only(bitcoinCash: derive(.bitcoinCash))
        case "Bitcoin SV": return .only(bitcoinSV: derive(.bitcoinSV))
        case "Litecoin": return .only(litecoin: derive(.litecoin))
        case "Dogecoin": return .only(dogecoin: derive(.dogecoin))
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
            "Linea", "Scroll", "Blast", "Mantle":
            return .only(evm: derive(.ethereum))
        case "Tron": return .only(tron: derive(.tron))
        case "Solana": return .only(solana: derive(.solana))
        case "XRP Ledger": return .only(xrp: derive(.xrp))
        case "Stellar": return .only(stellar: derive(.stellar))
        case "Cardano": return .only(cardano: derive(.cardano))
        case "Sui": return .only(sui: derive(.sui))
        case "Aptos": return .only(aptos: derive(.aptos))
        case "TON": return .only(ton: derive(.ton))
        case "Internet Computer": return .only(icp: derive(.internetComputer))
        case "NEAR": return .only(near: derive(.near))
        case "Polkadot": return .only(polkadot: derive(.polkadot))
        default: return .only()
        }
    }
    static func deriveSeedPhraseAddress(
        seedPhrase: String, chain: SeedDerivationChain, derivationPath: String
    ) throws -> String {
        try WalletDerivationLayer.deriveAddress(seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath)
    }
    func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, derivationPath: String)
        throws -> String
    { try Self.deriveSeedPhraseAddress(seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath) }
    func utxoDiscoveryDerivationChain(for chainName: String) -> SeedDerivationChain? {
        [
            "Bitcoin": SeedDerivationChain.bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSV, "Litecoin": .litecoin,
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
    ///
    /// The 26 per-chain arguments this used to take, each filtered by
    /// `chainName == "..."`, are gone: `core_plan_wallet_import` already scopes
    /// a planned wallet's `addresses` to its own chain, so the map passes
    /// straight through.
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
