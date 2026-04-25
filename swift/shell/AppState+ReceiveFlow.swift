import Foundation
import SwiftUI
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
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedTransactionIDs.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            let allPendingChains = [
                "Bitcoin", "Bitcoin Cash", "Litecoin", "Ethereum", "Arbitrum", "Optimism", "Ethereum Classic", "BNB Chain", "Avalanche",
                "Hyperliquid", "Dogecoin", "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Monero", "Sui", "Aptos", "TON",
                "Internet Computer", "NEAR", "Polkadot",
            ]
            for chainName in allPendingChains {
                guard let chainID = WalletChainID(chainName), trackedChains.contains(chainID) else { continue }
                group.addTask { await self.refreshPendingTransactionsForChain(chainName) }
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
    private func refreshPendingTransactionsForChain(_ chainName: String) async {
        switch chainName {
        case "Bitcoin": await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash": await refreshPendingBitcoinCashTransactions()
        case "Litecoin": await refreshPendingLitecoinTransactions()
        case "Ethereum", "Arbitrum", "Optimism", "Ethereum Classic", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
            "Linea", "Scroll", "Blast", "Mantle":
            await refreshPendingEVMTransactions(chainName: chainName)
        case "Dogecoin": await refreshPendingDogecoinTransactions()
        case "Tron": await refreshPendingTronTransactions()
        case "Solana": await refreshPendingSolanaTransactions()
        case "Cardano": await refreshPendingCardanoTransactions()
        case "XRP Ledger": await refreshPendingXRPTransactions()
        case "Stellar": await refreshPendingStellarTransactions()
        case "Monero": await refreshPendingMoneroTransactions()
        case "Sui": await refreshPendingSuiTransactions()
        case "Aptos": await refreshPendingAptosTransactions()
        case "TON": await refreshPendingTONTransactions()
        case "Internet Computer": await refreshPendingICPTransactions()
        case "NEAR": await refreshPendingNearTransactions()
        case "Polkadot": await refreshPendingPolkadotTransactions()
        default: break
        }
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
                (try? activateLiveReceiveAddress(receiveEVMAddress(for: evmAddress), for: wallet, chainName: receiveCoin.chainName)) ?? ""
            return
        }
        let liveResolvers: [(String, (ImportedWallet) -> String?)] = [
            ("Tron", { self.resolvedTronAddress(for: $0) }), ("Solana", { self.resolvedSolanaAddress(for: $0) }),
            ("Cardano", { self.resolvedCardanoAddress(for: $0) }), ("XRP Ledger", { self.resolvedXRPAddress(for: $0) }),
            ("Stellar", { self.resolvedStellarAddress(for: $0) }), ("Monero", { self.resolvedMoneroAddress(for: $0) }),
            ("Sui", { self.resolvedSuiAddress(for: $0) }), ("Aptos", { self.resolvedAptosAddress(for: $0) }),
            ("TON", { self.resolvedTONAddress(for: $0) }), ("Internet Computer", { self.resolvedICPAddress(for: $0) }),
            ("NEAR", { self.resolvedNearAddress(for: $0) }), ("Polkadot", { self.resolvedPolkadotAddress(for: $0) }),
        ]
        for (chainName, resolver) in liveResolvers where receiveCoin.chainName == chainName {
            receiveResolvedAddress = activateLiveReceiveAddress(resolver(wallet), for: wallet, chainName: chainName)
            return
        }
        guard receiveCoin.symbol == "BTC" else {
            if (receiveCoin.symbol == "BCH" && receiveCoin.chainName == "Bitcoin Cash")
                || (receiveCoin.symbol == "BSV" && receiveCoin.chainName == "Bitcoin SV")
                || (receiveCoin.symbol == "LTC" && receiveCoin.chainName == "Litecoin")
                || (receiveCoin.symbol == "DOGE" && receiveCoin.chainName == "Dogecoin")
            {
                receiveResolvedAddress = reservedReceiveAddress(for: wallet, chainName: receiveCoin.chainName, reserveIfMissing: true) ?? ""
                return
            }
            receiveResolvedAddress = ""
            return
        }
        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty,
            storedSeedPhrase(for: wallet.id) == nil
        {
            receiveResolvedAddress = activateLiveReceiveAddress(bitcoinAddress, for: wallet, chainName: receiveCoin.chainName)
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
                xpub = try await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                    mnemonicPhrase: seedPhrase, passphrase: "", accountPath: "m/84'/0'/0'")
            } else {
                receiveResolvedAddress = ""
                return
            }
            let address = try await WalletServiceBridge.shared.fetchBitcoinNextUnusedAddressTyped(xpub: xpub)
            receiveResolvedAddress = activateLiveReceiveAddress(
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
        let bitcoinAddressEntries = entries(draft.bitcoinAddressInput); let trimmedBitcoinAddress = tr(draft.bitcoinAddressInput);
        let trimmedBitcoinXPub = tr(draft.bitcoinXpubInput)
        let bitcoinCashAddressEntries = entries(draft.bitcoinCashAddressInput);
        let typedBitcoinCashAddress = tr(draft.bitcoinCashAddressInput)
        let bitcoinSvAddressEntries = entries(draft.bitcoinSvAddressInput); let typedBitcoinSVAddress = tr(draft.bitcoinSvAddressInput)
        let litecoinAddressEntries = entries(draft.litecoinAddressInput); let typedLitecoinAddress = tr(draft.litecoinAddressInput)
        let dogecoinAddressEntries = entries(draft.dogecoinAddressInput); let typedDogecoinAddress = tr(draft.dogecoinAddressInput)
        let ethereumAddressEntries = entries(draft.ethereumAddressInput); let typedEthereumAddress = tr(draft.ethereumAddressInput)
        let tronAddressEntries = entries(draft.tronAddressInput); let typedTronAddress = tr(draft.tronAddressInput)
        let solanaAddressEntries = entries(draft.solanaAddressInput); let typedSolanaAddress = tr(draft.solanaAddressInput)
        let xrpAddressEntries = entries(draft.xrpAddressInput); let typedXRPAddress = tr(draft.xrpAddressInput)
        let stellarAddressEntries = entries(draft.stellarAddressInput); let typedStellarAddress = tr(draft.stellarAddressInput)
        let typedMoneroAddress = tr(draft.moneroAddressInput)
        let cardanoAddressEntries = entries(draft.cardanoAddressInput); let typedCardanoAddress = tr(draft.cardanoAddressInput)
        let suiAddressEntries = entries(draft.suiAddressInput); let typedSuiAddress = tr(draft.suiAddressInput)
        let aptosAddressEntries = entries(draft.aptosAddressInput); let typedAptosAddress = tr(draft.aptosAddressInput)
        let tonAddressEntries = entries(draft.tonAddressInput); let typedTonAddress = tr(draft.tonAddressInput)
        let icpAddressEntries = entries(draft.icpAddressInput); let typedICPAddress = tr(draft.icpAddressInput)
        let nearAddressEntries = entries(draft.nearAddressInput); let typedNearAddress = tr(draft.nearAddressInput)
        let polkadotAddressEntries = entries(draft.polkadotAddressInput); let typedPolkadotAddress = tr(draft.polkadotAddressInput)
        let wantsBitcoinImport = draft.wantsBitcoin
        let wantsBitcoinCashImport = draft.wantsBitcoinCash
        let wantsBitcoinSVImport = draft.wantsBitcoinSV
        let wantsLitecoinImport = draft.wantsLitecoin
        let wantsDogecoinImport = draft.wantsDogecoin
        let wantsEthereumImport = draft.wantsEthereum
        let wantsEthereumClassicImport = draft.wantsEthereumClassic
        let wantsArbitrumImport = draft.wantsArbitrum
        let wantsOptimismImport = draft.wantsOptimism
        let wantsBNBImport = draft.wantsBNBChain
        let wantsAvalancheImport = draft.wantsAvalanche
        let wantsHyperliquidImport = draft.wantsHyperliquid
        let wantsTronImport = draft.wantsTron
        let wantsSolanaImport = draft.wantsSolana
        let wantsCardanoImport = draft.wantsCardano
        let wantsXRPImport = draft.wantsXRP
        let wantsStellarImport = draft.wantsStellar
        let wantsMoneroImport = draft.wantsMonero
        let wantsSuiImport = draft.wantsSui
        let wantsAptosImport = draft.wantsAptos
        let wantsTONImport = draft.wantsTON
        let wantsICPImport = draft.wantsICP
        let wantsNearImport = draft.wantsNear
        let wantsPolkadotImport = draft.wantsPolkadot
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
        let requiresSeedPhrase =
            (wantsBitcoinImport || wantsBitcoinCashImport || wantsBitcoinSVImport || wantsLitecoinImport || wantsDogecoinImport
                || wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport
                || wantsAvalancheImport || wantsHyperliquidImport || wantsTronImport || wantsSolanaImport || wantsCardanoImport
                || wantsXRPImport || wantsStellarImport || wantsMoneroImport || wantsSuiImport || wantsAptosImport || wantsTONImport
                || wantsICPImport || wantsNearImport || wantsPolkadotImport) && !isWatchOnlyImport && !isPrivateKeyImport
        // Per-chain "resolved" optional: keep the typed value only when the chain
        // is selected for import AND the value is non-empty.
        func res(_ wants: Bool, _ v: String) -> String? { (wants && !v.isEmpty) ? v : nil }
        let resolvedBitcoinAddress = res(wantsBitcoinImport, trimmedBitcoinAddress)
        let resolvedBitcoinXPub = res(wantsBitcoinImport, trimmedBitcoinXPub)
        let resolvedBitcoinCashAddress = res(wantsBitcoinCashImport, typedBitcoinCashAddress)
        let resolvedBitcoinSVAddress = res(wantsBitcoinSVImport, typedBitcoinSVAddress)
        let resolvedLitecoinAddress = res(wantsLitecoinImport, typedLitecoinAddress)
        let resolvedTronAddress = res(wantsTronImport, typedTronAddress)
        let resolvedSolanaAddress = res(wantsSolanaImport, typedSolanaAddress)
        let resolvedXRPAddress = res(wantsXRPImport, typedXRPAddress)
        let resolvedStellarAddress = res(wantsStellarImport, typedStellarAddress)
        let resolvedMoneroAddress = res(wantsMoneroImport, typedMoneroAddress)
        let resolvedCardanoAddress = res(wantsCardanoImport, typedCardanoAddress)
        let resolvedSuiAddress = res(wantsSuiImport, typedSuiAddress)
        let resolvedAptosAddress = res(wantsAptosImport, typedAptosAddress)
        let resolvedTONAddress = res(wantsTONImport, typedTonAddress)
        let resolvedICPAddress = res(wantsICPImport, typedICPAddress)
        let resolvedNearAddress = res(wantsNearImport, typedNearAddress)
        let resolvedPolkadotAddress = res(wantsPolkadotImport, typedPolkadotAddress)
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
        if isWatchOnlyImport && wantsBitcoinImport {
            let hasValidAddress =
                !bitcoinAddressEntries.isEmpty
                && bitcoinAddressEntries.allSatisfy {
                    AddressValidation.isValid($0, kind: "bitcoin", networkMode: self.bitcoinNetworkMode.rawValue)
                }
            let hasValidXPub = resolvedBitcoinXPub.map { $0.hasPrefix("xpub") || $0.hasPrefix("ypub") || $0.hasPrefix("zpub") } ?? false
            if !hasValidAddress && !hasValidXPub {
                importError = "Enter one valid Bitcoin address per line or a valid xpub/zpub for watched addresses."
                return
            }
        }
        if wantsMoneroImport {
            if (resolvedMoneroAddress?.isEmpty ?? true) || !AddressValidation.isValid(resolvedMoneroAddress ?? "", kind: "monero") {
                importError = localizedStoreString("Enter a valid Monero address.")
                return
            }
            if isWatchOnlyImport {
                importError = "Monero watched addresses are not supported in this build."
                return
            }
        }
        if wantsCardanoImport && !isWatchOnlyImport {
            if let resolvedCardanoAddress, !resolvedCardanoAddress.isEmpty,
                !AddressValidation.isValid(resolvedCardanoAddress, kind: "cardano")
            {
                importError = localizedStoreString("Enter a valid Cardano address.")
                return
            }
        }
        if isWatchOnlyImport {
            let watchOnlyValidations: [(Bool, [String], (String) -> Bool, String)] = [
                (
                    wantsBitcoinCashImport, bitcoinCashAddressEntries, { AddressValidation.isValid($0, kind: "bitcoinCash") },
                    "Bitcoin Cash address"
                ),
                (wantsBitcoinSVImport, bitcoinSvAddressEntries, { AddressValidation.isValid($0, kind: "bitcoinSV") }, "Bitcoin SV address"),
                (wantsLitecoinImport, litecoinAddressEntries, { AddressValidation.isValid($0, kind: "litecoin") }, "Litecoin address"),
                (wantsDogecoinImport, dogecoinAddressEntries, { self.isValidDogecoinAddressForPolicy($0) }, "Dogecoin address"),
                (wantsTronImport, tronAddressEntries, { AddressValidation.isValid($0, kind: "tron") }, "Tron address"),
                (wantsSolanaImport, solanaAddressEntries, { AddressValidation.isValid($0, kind: "solana") }, "Solana address"),
                (wantsXRPImport, xrpAddressEntries, { AddressValidation.isValid($0, kind: "xrp") }, "XRP address"),
                (wantsStellarImport, stellarAddressEntries, { AddressValidation.isValid($0, kind: "stellar") }, "Stellar address"),
                (wantsCardanoImport, cardanoAddressEntries, { AddressValidation.isValid($0, kind: "cardano") }, "Cardano address"),
                (wantsSuiImport, suiAddressEntries, { AddressValidation.isValid($0, kind: "sui") }, "Sui address"),
                (wantsAptosImport, aptosAddressEntries, { AddressValidation.isValid($0, kind: "aptos") }, "Aptos address"),
                (wantsTONImport, tonAddressEntries, { AddressValidation.isValid($0, kind: "ton") }, "TON address"),
                (
                    wantsICPImport, icpAddressEntries, { AddressValidation.isValid($0, kind: "internetComputer") },
                    "Internet Computer account identifier"
                ), (wantsNearImport, nearAddressEntries, { AddressValidation.isValid($0, kind: "near") }, "NEAR address"),
                (wantsPolkadotImport, polkadotAddressEntries, { AddressValidation.isValid($0, kind: "polkadot") }, "Polkadot address"),
            ]
            for (wantsImport, entries, validator, name) in watchOnlyValidations where wantsImport {
                if entries.isEmpty || !entries.allSatisfy(validator) {
                    importError = "Enter one valid \(name) per line for watched addresses."
                    return
                }
            }
        }
        if isWatchOnlyImport
            && (wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport
                || wantsAvalancheImport || wantsHyperliquidImport)
        {
            if ethereumAddressEntries.isEmpty || !ethereumAddressEntries.allSatisfy({ AddressValidation.isValid($0, kind: "evm") }) {
                importError = "Enter one valid EVM address per line for watched addresses."
                return
            }
        }
        if editingWalletID == nil {
            let bitcoinCashAddress: String?
            let bitcoinSvAddress: String?
            let litecoinAddress: String?
            let dogecoinAddress: String?
            let ethereumAddress: String?
            let ethereumClassicAddress: String?
            let tronAddress: String?
            let solanaAddress: String?
            let xrpAddress: String?
            let stellarAddress: String?
            let moneroAddress: String?
            let cardanoAddress: String?
            let suiAddress: String?
            let aptosAddress: String?
            let tonAddress: String?
            let icpAddress: String?
            let nearAddress: String?
            let polkadotAddress: String?
            let derivedBitcoinAddress: String?
            let createdWalletIDs = selectedChainNames.map { _ in UUID() }
            let bitcoinWalletID = zip(selectedChainNames, createdWalletIDs).first(where: { $0.0 == "Bitcoin" })?.1
            if requiresSeedPhrase {
                let p = selectedDerivationPaths
                let needsEvm =
                    wantsEthereumImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport
                    || wantsHyperliquidImport
                let chainPathCandidates: [(Bool, String, String)] = [
                    (wantsBitcoinImport, "Bitcoin", p.bitcoin), (wantsBitcoinCashImport, "Bitcoin Cash", p.bitcoinCash),
                    (wantsBitcoinSVImport, "Bitcoin SV", p.bitcoinSV), (wantsLitecoinImport, "Litecoin", p.litecoin),
                    (wantsDogecoinImport, "Dogecoin", p.dogecoin), (needsEvm, "Ethereum", p.ethereum),
                    (wantsEthereumClassicImport, "Ethereum Classic", p.ethereumClassic), (wantsTronImport, "Tron", p.tron),
                    (wantsSolanaImport, "Solana", p.solana), (wantsCardanoImport, "Cardano", p.cardano),
                    (wantsXRPImport, "XRP Ledger", p.xrp), (wantsStellarImport, "Stellar", p.stellar), (wantsSuiImport, "Sui", p.sui),
                    (wantsAptosImport, "Aptos", p.aptos), (wantsTONImport, "TON", p.ton),
                    (wantsICPImport, "Internet Computer", p.internetComputer), (wantsNearImport, "NEAR", p.near),
                    (wantsPolkadotImport, "Polkadot", p.polkadot),
                ]
                let chainPaths: [String: String] = Dictionary(
                    uniqueKeysWithValues: chainPathCandidates.compactMap { $0.0 ? ($0.1, $0.2) : nil })
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
                                seedPhrase: trimmedSeedPhrase, chain: chain, network: .mainnet,
                                derivationPath: path, overrides: overrides
                            ) {
                                perChain[chainName] = address
                            }
                        }
                        derived = perChain
                    }
                    if wantsBitcoinImport {
                        guard let bitcoinWalletID else {
                            importError = "Bitcoin wallet initialization failed."
                            return
                        }
                        _ = bitcoinWalletID
                    }
                    derivedBitcoinAddress = derived["Bitcoin"]; bitcoinCashAddress = derived["Bitcoin Cash"];
                    bitcoinSvAddress = derived["Bitcoin SV"]
                    litecoinAddress = derived["Litecoin"]; dogecoinAddress = derived["Dogecoin"]
                    ethereumAddress = derived["Ethereum"]; ethereumClassicAddress = derived["Ethereum Classic"]
                    tronAddress = derived["Tron"]; solanaAddress = derived["Solana"]; cardanoAddress = derived["Cardano"]
                    xrpAddress = derived["XRP Ledger"]; stellarAddress = derived["Stellar"]
                    suiAddress = derived["Sui"]; aptosAddress = derived["Aptos"]; tonAddress = derived["TON"]
                    icpAddress = derived["Internet Computer"]; nearAddress = derived["NEAR"]; polkadotAddress = derived["Polkadot"]
                    moneroAddress = resolvedMoneroAddress
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
                derivedBitcoinAddress = derivedPrivateKeyAddress.bitcoin
                bitcoinCashAddress =
                    derivedPrivateKeyAddress.bitcoinCash
                    ?? (AddressValidation.isValid(typedBitcoinCashAddress, kind: "bitcoinCash") ? typedBitcoinCashAddress : nil)
                bitcoinSvAddress =
                    derivedPrivateKeyAddress.bitcoinSV
                    ?? (AddressValidation.isValid(typedBitcoinSVAddress, kind: "bitcoinSV") ? typedBitcoinSVAddress : nil)
                litecoinAddress =
                    derivedPrivateKeyAddress.litecoin
                    ?? (AddressValidation.isValid(typedLitecoinAddress, kind: "litecoin") ? typedLitecoinAddress : nil)
                dogecoinAddress =
                    derivedPrivateKeyAddress.dogecoin
                    ?? (isValidDogecoinAddressForPolicy(typedDogecoinAddress) ? typedDogecoinAddress : nil)
                ethereumAddress =
                    derivedPrivateKeyAddress.evm
                    ?? (AddressValidation.isValid(typedEthereumAddress, kind: "evm") ? normalizeEVMAddress(typedEthereumAddress) : nil)
                ethereumClassicAddress = ethereumAddress
                tronAddress =
                    derivedPrivateKeyAddress.tron ?? (AddressValidation.isValid(typedTronAddress, kind: "tron") ? typedTronAddress : nil)
                solanaAddress =
                    derivedPrivateKeyAddress.solana
                    ?? (AddressValidation.isValid(typedSolanaAddress, kind: "solana") ? typedSolanaAddress : nil)
                xrpAddress =
                    derivedPrivateKeyAddress.xrp ?? (AddressValidation.isValid(typedXRPAddress, kind: "xrp") ? typedXRPAddress : nil)
                stellarAddress =
                    derivedPrivateKeyAddress.stellar
                    ?? (AddressValidation.isValid(typedStellarAddress, kind: "stellar") ? typedStellarAddress : nil)
                moneroAddress = AddressValidation.isValid(typedMoneroAddress, kind: "monero") ? typedMoneroAddress : nil
                cardanoAddress =
                    derivedPrivateKeyAddress.cardano
                    ?? (AddressValidation.isValid(typedCardanoAddress, kind: "cardano") ? typedCardanoAddress : nil)
                suiAddress =
                    derivedPrivateKeyAddress.sui
                    ?? (AddressValidation.isValid(typedSuiAddress, kind: "sui") ? typedSuiAddress.lowercased() : nil)
                aptosAddress =
                    derivedPrivateKeyAddress.aptos
                    ?? (AddressValidation.isValid(typedAptosAddress, kind: "aptos")
                        ? normalizedAddress(typedAptosAddress, for: "Aptos") : nil)
                tonAddress =
                    derivedPrivateKeyAddress.ton
                    ?? (AddressValidation.isValid(typedTonAddress, kind: "ton") ? normalizedAddress(typedTonAddress, for: "TON") : nil)
                icpAddress =
                    derivedPrivateKeyAddress.icp
                    ?? (AddressValidation.isValid(typedICPAddress, kind: "internetComputer")
                        ? normalizedAddress(typedICPAddress, for: "Internet Computer") : nil)
                nearAddress =
                    derivedPrivateKeyAddress.near
                    ?? (AddressValidation.isValid(typedNearAddress, kind: "near") ? typedNearAddress.lowercased() : nil)
                polkadotAddress =
                    derivedPrivateKeyAddress.polkadot
                    ?? (AddressValidation.isValid(typedPolkadotAddress, kind: "polkadot") ? typedPolkadotAddress : nil)
            }
            let plannedWalletIDs: [UUID]
            if isWatchOnlyImport {
                let watchOnlyEntriesByChain: [String: [String]] = [
                    "Bitcoin": bitcoinAddressEntries, "Bitcoin Cash": bitcoinCashAddressEntries, "Bitcoin SV": bitcoinSvAddressEntries,
                    "Litecoin": litecoinAddressEntries, "Dogecoin": dogecoinAddressEntries, "Tron": tronAddressEntries,
                    "Solana": solanaAddressEntries, "XRP Ledger": xrpAddressEntries, "Stellar": stellarAddressEntries,
                    "Cardano": cardanoAddressEntries, "Sui": suiAddressEntries, "Aptos": aptosAddressEntries, "TON": tonAddressEntries,
                    "Internet Computer": icpAddressEntries, "NEAR": nearAddressEntries, "Polkadot": polkadotAddressEntries,
                ]
                let evmChains: Set<String> = [
                    "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
                    "Linea", "Scroll", "Blast", "Mantle",
                ]
                let watchOnlyWalletCount: Int = {
                    if primarySelectedChainName == "Bitcoin", let x = resolvedBitcoinXPub, !x.isEmpty { return 1 }
                    if evmChains.contains(primarySelectedChainName) { return ethereumAddressEntries.count }
                    return watchOnlyEntriesByChain[primarySelectedChainName]?.count ?? 0
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
                    bitcoinAddress: resolvedBitcoinAddress ?? derivedBitcoinAddress, bitcoinXpub: resolvedBitcoinXPub,
                    bitcoinCashAddress: resolvedBitcoinCashAddress ?? bitcoinCashAddress,
                    bitcoinSvAddress: resolvedBitcoinSVAddress ?? bitcoinSvAddress,
                    litecoinAddress: resolvedLitecoinAddress ?? litecoinAddress, dogecoinAddress: dogecoinAddress,
                    ethereumAddress: ethereumAddress, ethereumClassicAddress: ethereumClassicAddress,
                    tronAddress: resolvedTronAddress ?? tronAddress, solanaAddress: resolvedSolanaAddress ?? solanaAddress,
                    xrpAddress: resolvedXRPAddress ?? xrpAddress, stellarAddress: resolvedStellarAddress ?? stellarAddress,
                    moneroAddress: resolvedMoneroAddress ?? moneroAddress, cardanoAddress: resolvedCardanoAddress ?? cardanoAddress,
                    suiAddress: resolvedSuiAddress ?? suiAddress, aptosAddress: resolvedAptosAddress ?? aptosAddress,
                    tonAddress: resolvedTONAddress ?? tonAddress, icpAddress: resolvedICPAddress ?? icpAddress,
                    nearAddress: resolvedNearAddress ?? nearAddress, polkadotAddress: resolvedPolkadotAddress ?? polkadotAddress
                ),
                watchOnlyEntries: WalletImportWatchOnlyEntries(
                    bitcoinAddresses: bitcoinAddressEntries, bitcoinXpub: resolvedBitcoinXPub,
                    bitcoinCashAddresses: bitcoinCashAddressEntries, bitcoinSvAddresses: bitcoinSvAddressEntries,
                    litecoinAddresses: litecoinAddressEntries, dogecoinAddresses: dogecoinAddressEntries,
                    ethereumAddresses: ethereumAddressEntries.map { normalizeEVMAddress($0) }, tronAddresses: tronAddressEntries,
                    solanaAddresses: solanaAddressEntries, xrpAddresses: xrpAddressEntries, stellarAddresses: stellarAddressEntries,
                    cardanoAddresses: cardanoAddressEntries, suiAddresses: suiAddressEntries.map { $0.lowercased() },
                    aptosAddresses: aptosAddressEntries.map { normalizedAddress($0, for: "Aptos") },
                    tonAddresses: tonAddressEntries.map { normalizedAddress($0, for: "TON") },
                    icpAddresses: icpAddressEntries.map { normalizedAddress($0, for: "Internet Computer") },
                    nearAddresses: nearAddressEntries.map { $0.lowercased() }, polkadotAddresses: polkadotAddressEntries
                )
            )
            let importPlan: WalletImportPlan
            do {
                importPlan = try corePlanWalletImport(request: importPlanRequest)
            } catch {
                importError = error.localizedDescription
                return
            }
            let createdWallets: [ImportedWallet] = importPlan.wallets.compactMap { plannedWallet in
                guard let walletID = UUID(uuidString: plannedWallet.walletId) else { return nil }
                return walletForPlannedImport(
                    id: walletID, plan: plannedWallet, seedDerivationPreset: selectedDerivationPreset,
                    seedDerivationPaths: selectedDerivationPaths,
                    derivationOverrides: draft.resolvedDerivationOverrides,
                    holdings: coins
                )
            }
            for instruction in importPlan.secretInstructions {
                let walletID = instruction.walletId
                let account = resolvedSeedPhraseAccount(for: walletID)
                let passwordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
                let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
                if instruction.shouldStoreSeedPhrase {
                    try? SecureSeedStore.save(trimmedSeedPhrase, for: account)
                } else {
                    try? SecureSeedStore.deleteValue(for: account)
                }
                if instruction.shouldStorePasswordVerifier, let trimmedWalletPassword {
                    try? SecureSeedPasswordStore.save(trimmedWalletPassword, for: passwordAccount)
                } else {
                    try? SecureSeedPasswordStore.deleteValue(for: passwordAccount)
                }
                if instruction.shouldStorePrivateKey {
                    SecurePrivateKeyStore.save(trimmedPrivateKey, for: privateKeyAccount)
                } else {
                    SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
                }
            }
            appendWallets(createdWallets)
            importedWalletsForRefresh = createdWallets
            for w in createdWallets {
                Task { try? await WalletServiceBridge.shared.upsertWalletDirect(w.walletSummary) }
            }
        }
        finishWalletImportFlow()
        withAnimation {
        }
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: String, to newName: String) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        let wallet = wallets[index]
        wallets[index] = ImportedWallet(
            id: wallet.id, name: newName, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress,
            tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths, derivationOverrides: wallet.derivationOverrides, selectedChain: wallet.selectedChain, holdings: wallet.holdings,
            includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
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
        seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String
    ) throws -> String {
        try WalletDerivationLayer.deriveAddress(seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath)
    }
    func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String)
        throws -> String
    { try Self.deriveSeedPhraseAddress(seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath) }
    func derivationNetwork(for chain: SeedDerivationChain, wallet: ImportedWallet? = nil) -> WalletDerivationNetwork {
        switch chain {
        case .bitcoin: return derivationNetwork(for: wallet.map(bitcoinNetworkMode(for:)) ?? bitcoinNetworkMode)
        case .dogecoin: return derivationNetwork(for: wallet.map(dogecoinNetworkMode(for:)) ?? dogecoinNetworkMode)
        default: return .mainnet
        }
    }
    func derivationNetwork(for networkMode: BitcoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode {
        case .mainnet: .mainnet;
        case .testnet: .testnet;
        case .testnet4: .testnet4;
        case .signet: .signet
        }
    }
    func derivationNetwork(for networkMode: DogecoinNetworkMode) -> WalletDerivationNetwork {
        networkMode == .testnet ? .testnet : .mainnet
    }
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
    func walletForSingleChain(
        id: UUID, name: String, chainName: String, bitcoinAddress: String?, bitcoinXpub: String?, bitcoinCashAddress: String?,
        bitcoinSvAddress: String?, litecoinAddress: String?, dogecoinAddress: String?, ethereumAddress: String?, tronAddress: String?,
        solanaAddress: String?, xrpAddress: String?, stellarAddress: String?, moneroAddress: String?, cardanoAddress: String?,
        suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?,
        polkadotAddress: String?, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths,
        derivationOverrides: CoreWalletDerivationOverrides = CoreWalletDerivationOverrides(
            passphrase: nil, mnemonicWordlist: nil, iterationCount: nil, saltPrefix: nil, hmacKey: nil,
            curve: nil, derivationAlgorithm: nil, addressAlgorithm: nil, publicKeyFormat: nil, scriptType: nil
        ),
        holdings: [Coin]
    ) -> ImportedWallet {
        ImportedWallet(
            id: id.uuidString, name: name, bitcoinNetworkMode: chainName == "Bitcoin" ? bitcoinNetworkMode : .mainnet,
            dogecoinNetworkMode: chainName == "Dogecoin" ? dogecoinNetworkMode : .mainnet,
            bitcoinAddress: chainName == "Bitcoin" ? bitcoinAddress : nil, bitcoinXpub: chainName == "Bitcoin" ? bitcoinXpub : nil,
            bitcoinCashAddress: chainName == "Bitcoin Cash" ? bitcoinCashAddress : nil,
            bitcoinSvAddress: chainName == "Bitcoin SV" ? bitcoinSvAddress : nil,
            litecoinAddress: chainName == "Litecoin" ? litecoinAddress : nil,
            dogecoinAddress: chainName == "Dogecoin" ? dogecoinAddress : nil,
            ethereumAddress: (chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum"
                || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid")
                ? ethereumAddress : nil, tronAddress: chainName == "Tron" ? tronAddress : nil,
            solanaAddress: chainName == "Solana" ? solanaAddress : nil, stellarAddress: chainName == "Stellar" ? stellarAddress : nil,
            xrpAddress: chainName == "XRP Ledger" ? xrpAddress : nil, moneroAddress: chainName == "Monero" ? moneroAddress : nil,
            cardanoAddress: chainName == "Cardano" ? cardanoAddress : nil, suiAddress: chainName == "Sui" ? suiAddress : nil,
            aptosAddress: chainName == "Aptos" ? aptosAddress : nil, tonAddress: chainName == "TON" ? tonAddress : nil,
            icpAddress: chainName == "Internet Computer" ? icpAddress : nil, nearAddress: chainName == "NEAR" ? nearAddress : nil,
            polkadotAddress: chainName == "Polkadot" ? polkadotAddress : nil, seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths, derivationOverrides: derivationOverrides,
            selectedChain: chainName, holdings: holdings.filter { $0.chainName == chainName },
            includeInPortfolioTotal: true
        )
    }
    func walletForPlannedImport(
        id: UUID, plan: PlannedWallet, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths,
        derivationOverrides: CoreWalletDerivationOverrides = CoreWalletDerivationOverrides(
            passphrase: nil, mnemonicWordlist: nil, iterationCount: nil, saltPrefix: nil, hmacKey: nil,
            curve: nil, derivationAlgorithm: nil, addressAlgorithm: nil, publicKeyFormat: nil, scriptType: nil
        ),
        holdings: [Coin]
    ) -> ImportedWallet {
        walletForSingleChain(
            id: id, name: plan.name, chainName: plan.chainName, bitcoinAddress: plan.addresses.bitcoinAddress,
            bitcoinXpub: plan.addresses.bitcoinXpub, bitcoinCashAddress: plan.addresses.bitcoinCashAddress,
            bitcoinSvAddress: plan.addresses.bitcoinSvAddress, litecoinAddress: plan.addresses.litecoinAddress,
            dogecoinAddress: plan.addresses.dogecoinAddress,
            ethereumAddress: plan.chainName == "Ethereum Classic"
                ? (plan.addresses.ethereumClassicAddress ?? plan.addresses.ethereumAddress)
                : plan.addresses.ethereumAddress, tronAddress: plan.addresses.tronAddress, solanaAddress: plan.addresses.solanaAddress,
            xrpAddress: plan.addresses.xrpAddress, stellarAddress: plan.addresses.stellarAddress,
            moneroAddress: plan.addresses.moneroAddress, cardanoAddress: plan.addresses.cardanoAddress,
            suiAddress: plan.addresses.suiAddress, aptosAddress: plan.addresses.aptosAddress, tonAddress: plan.addresses.tonAddress,
            icpAddress: plan.addresses.icpAddress, nearAddress: plan.addresses.nearAddress, polkadotAddress: plan.addresses.polkadotAddress,
            seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths,
            derivationOverrides: derivationOverrides, holdings: holdings
        )
    }
    func walletByReplacingHoldings(_ wallet: ImportedWallet, with holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub,
            bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress,
            litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress,
            nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths, derivationOverrides: wallet.derivationOverrides, selectedChain: wallet.selectedChain, holdings: holdings,
            includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
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
