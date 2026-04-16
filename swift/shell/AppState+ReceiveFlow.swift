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
                "refresh_pending_transactions", startedAt: startedAt, metadata: "chains=\(trackedChains.count) include_history=\(includeHistoryRefreshes)"
            )
        }
        lastPendingTransactionRefreshAt = Date()
        let trackedTransactionIDs = Set(transactions.compactMap { t -> UUID? in
            guard t.kind == .send, t.transactionHash != nil, t.status == .pending || t.status == .confirmed else { return nil }
            return t.id
        })
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedTransactionIDs.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            let allPendingChains = ["Bitcoin", "Bitcoin Cash", "Litecoin", "Ethereum", "Arbitrum", "Optimism", "Ethereum Classic", "BNB Chain", "Avalanche", "Hyperliquid", "Dogecoin", "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot"]
            for chainName in allPendingChains {
                guard let chainID = WalletChainID(chainName), trackedChains.contains(chainID) else { continue }
                group.addTask { await self.refreshPendingTransactionsForChain(chainName) }
            }
            await group.waitForAll()
        }
        let refreshLastSent: () -> Void = {
            if let lastSentTransaction = self.lastSentTransaction, let refreshed = self.transactions.first(where: { $0.id == lastSentTransaction.id }) {
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
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else { return "Select a wallet and chain" }
        let chainAddress: String?
        switch (receiveCoin.symbol, receiveCoin.chainName) {
        case ("BTC", _): chainAddress = wallet.bitcoinAddress
        case ("BCH", "Bitcoin Cash"): chainAddress = resolvedBitcoinCashAddress(for: wallet)
        case ("BSV", "Bitcoin SV"): chainAddress = resolvedBitcoinSVAddress(for: wallet)
        case ("LTC", "Litecoin"): chainAddress = resolvedLitecoinAddress(for: wallet)
        case ("DOGE", "Dogecoin"): chainAddress = nil
        default:
            if isEVMChain(receiveCoin.chainName) { chainAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) }
            else {
                let simpleResolvers: [String: (ImportedWallet) -> String?] = [
                    "Tron": resolvedTronAddress(for:), "Solana": resolvedSolanaAddress(for:), "Cardano": resolvedCardanoAddress(for:), "XRP Ledger": resolvedXRPAddress(for:), "Stellar": resolvedStellarAddress(for:), "Monero": resolvedMoneroAddress(for:), "Sui": resolvedSuiAddress(for:), "Aptos": resolvedAptosAddress(for:), "TON": resolvedTONAddress(for:), "Internet Computer": resolvedICPAddress(for:), "NEAR": resolvedNearAddress(for:), "Polkadot": resolvedPolkadotAddress(for:),
                ]
                chainAddress = simpleResolvers[receiveCoin.chainName]?(wallet)
            }
        }
        let hasWatchAddress = wallet.dogecoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return receiveAddressMessage(input: ReceiveAddressMessageInput(
            chainName: receiveCoin.chainName, symbol: receiveCoin.symbol, isEvmChain: isEVMChain(receiveCoin.chainName), resolvedAddress: receiveResolvedAddress, chainAddress: chainAddress, hasSeed: storedSeedPhrase(for: wallet.id) != nil, hasWatchAddress: hasWatchAddress, isResolving: isResolvingReceiveAddress
        ))
    }
    private func refreshPendingTransactionsForChain(_ chainName: String) async {
        switch chainName {
        case "Bitcoin":           await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash":      await refreshPendingBitcoinCashTransactions()
        case "Litecoin":          await refreshPendingLitecoinTransactions()
        case "Ethereum":          await refreshPendingEthereumTransactions()
        case "Arbitrum":          await refreshPendingArbitrumTransactions()
        case "Optimism":          await refreshPendingOptimismTransactions()
        case "Ethereum Classic":  await refreshPendingETCTransactions()
        case "BNB Chain":         await refreshPendingBNBTransactions()
        case "Avalanche":         await refreshPendingAvalancheTransactions()
        case "Hyperliquid":       await refreshPendingHyperliquidTransactions()
        case "Dogecoin":          await refreshPendingDogecoinTransactions()
        case "Tron":              await refreshPendingTronTransactions()
        case "Solana":            await refreshPendingSolanaTransactions()
        case "Cardano":           await refreshPendingCardanoTransactions()
        case "XRP Ledger":        await refreshPendingXRPTransactions()
        case "Stellar":           await refreshPendingStellarTransactions()
        case "Monero":            await refreshPendingMoneroTransactions()
        case "Sui":               await refreshPendingSuiTransactions()
        case "Aptos":             await refreshPendingAptosTransactions()
        case "TON":               await refreshPendingTONTransactions()
        case "Internet Computer": await refreshPendingICPTransactions()
        case "NEAR":              await refreshPendingNearTransactions()
        case "Polkadot":          await refreshPendingPolkadotTransactions()
        default: break
        }}
    func refreshReceiveAddress() async {
        guard let wallet = wallet(for: receiveWalletID), let receiveCoin = selectedReceiveCoin(for: receiveWalletID) else {
            receiveResolvedAddress = ""; return
        }
        if isEVMChain(receiveCoin.chainName) {
            guard let evmAddress = resolvedEVMAddress(for: wallet, chainName: receiveCoin.chainName) else { receiveResolvedAddress = ""; return }
            guard !isResolvingReceiveAddress else { return }
            isResolvingReceiveAddress = true
            defer { isResolvingReceiveAddress = false }
            receiveResolvedAddress = (try? activateLiveReceiveAddress(receiveEVMAddress(for: evmAddress), for: wallet, chainName: receiveCoin.chainName)) ?? ""
            return
        }
        let liveResolvers: [(String, (ImportedWallet) -> String?)] = [
            ("Tron",              { self.resolvedTronAddress(for: $0) }), ("Solana",            { self.resolvedSolanaAddress(for: $0) }), ("Cardano",           { self.resolvedCardanoAddress(for: $0) }), ("XRP Ledger",        { self.resolvedXRPAddress(for: $0) }), ("Stellar",           { self.resolvedStellarAddress(for: $0) }), ("Monero",            { self.resolvedMoneroAddress(for: $0) }), ("Sui",               { self.resolvedSuiAddress(for: $0) }), ("Aptos",             { self.resolvedAptosAddress(for: $0) }), ("TON",               { self.resolvedTONAddress(for: $0) }), ("Internet Computer", { self.resolvedICPAddress(for: $0) }), ("NEAR",              { self.resolvedNearAddress(for: $0) }), ("Polkadot",          { self.resolvedPolkadotAddress(for: $0) }), ]
        for (chainName, resolver) in liveResolvers where receiveCoin.chainName == chainName {
            receiveResolvedAddress = activateLiveReceiveAddress(resolver(wallet), for: wallet, chainName: chainName)
            return
        }
        if receiveCoin.symbol == "DOGE", receiveCoin.chainName == "Dogecoin" {
            receiveResolvedAddress = dogecoinReservedReceiveAddress(for: wallet, reserveIfMissing: true) ?? ""
            return
        }
        guard receiveCoin.symbol == "BTC" else {
            if (receiveCoin.symbol == "BCH" && receiveCoin.chainName == "Bitcoin Cash")
                || (receiveCoin.symbol == "BSV" && receiveCoin.chainName == "Bitcoin SV")
                || (receiveCoin.symbol == "LTC" && receiveCoin.chainName == "Litecoin") {
                receiveResolvedAddress = reservedReceiveAddress(for: wallet, chainName: receiveCoin.chainName, reserveIfMissing: true) ?? ""
                return
            }
            receiveResolvedAddress = ""
            return
        }
        if let bitcoinAddress = wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !bitcoinAddress.isEmpty, storedSeedPhrase(for: wallet.id) == nil {
            receiveResolvedAddress = activateLiveReceiveAddress(bitcoinAddress, for: wallet, chainName: receiveCoin.chainName)
            return
        }
        guard !isResolvingReceiveAddress else { return }
        isResolvingReceiveAddress = true
        defer { isResolvingReceiveAddress = false }
        do {
            let xpub: String
            if let stored = wallet.bitcoinXpub?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty { xpub = stored } else if let seedPhrase = storedSeedPhrase(for: wallet.id) {
                xpub = try await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                    mnemonicPhrase: seedPhrase, passphrase: "", accountPath: "m/84'/0'/0'")
            } else {
                receiveResolvedAddress = ""
                return
            }
            let json = try await WalletServiceBridge.shared.fetchBitcoinNextUnusedAddressJSON(xpub: xpub)
            let address: String?
            if json.trimmingCharacters(in: .whitespacesAndNewlines) == "null" { address = nil } else if let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { address = obj["address"] as? String } else { address = nil }
            receiveResolvedAddress = activateLiveReceiveAddress(
                address ?? wallet.bitcoinAddress ?? "", for: wallet, chainName: receiveCoin.chainName
            )
        } catch {
            receiveResolvedAddress = ""
        }}
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
        let trimmedSeedPhrase = importDraft.seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }.joined(separator: " ")
        let trimmedPrivateKey = PrivateKeyHex.normalized(from: importDraft.privateKeyInput)
        let trimmedWalletPassword = importDraft.normalizedWalletPassword
        let draft = importDraft
        func tr(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func entries(_ s: String) -> [String] { draft.watchOnlyEntries(from: s) }
        let bitcoinAddressEntries = entries(draft.bitcoinAddressInput); let trimmedBitcoinAddress = tr(draft.bitcoinAddressInput); let trimmedBitcoinXPub = tr(draft.bitcoinXpubInput)
        let bitcoinCashAddressEntries = entries(draft.bitcoinCashAddressInput); let typedBitcoinCashAddress = tr(draft.bitcoinCashAddressInput)
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
        let wantsBitcoinImport = draft.wantsBitcoin, wantsBitcoinCashImport = draft.wantsBitcoinCash, wantsBitcoinSVImport = draft.wantsBitcoinSV, wantsLitecoinImport = draft.wantsLitecoin, wantsDogecoinImport = draft.wantsDogecoin
        let wantsEthereumImport = draft.wantsEthereum, wantsEthereumClassicImport = draft.wantsEthereumClassic, wantsArbitrumImport = draft.wantsArbitrum, wantsOptimismImport = draft.wantsOptimism
        let wantsBNBImport = draft.wantsBNBChain, wantsAvalancheImport = draft.wantsAvalanche, wantsHyperliquidImport = draft.wantsHyperliquid
        let wantsTronImport = draft.wantsTron, wantsSolanaImport = draft.wantsSolana, wantsCardanoImport = draft.wantsCardano, wantsXRPImport = draft.wantsXRP, wantsStellarImport = draft.wantsStellar
        let wantsMoneroImport = draft.wantsMonero, wantsSuiImport = draft.wantsSui, wantsAptosImport = draft.wantsAptos, wantsTONImport = draft.wantsTON, wantsICPImport = draft.wantsICP, wantsNearImport = draft.wantsNear, wantsPolkadotImport = draft.wantsPolkadot
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
        let requiresSeedPhrase = (wantsBitcoinImport || wantsBitcoinCashImport || wantsBitcoinSVImport || wantsLitecoinImport || wantsDogecoinImport || wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport || wantsTronImport || wantsSolanaImport || wantsCardanoImport || wantsXRPImport || wantsStellarImport || wantsMoneroImport || wantsSuiImport || wantsAptosImport || wantsTONImport || wantsICPImport || wantsNearImport || wantsPolkadotImport) && !isWatchOnlyImport && !isPrivateKeyImport
        // Per-chain "resolved" optional: keep the typed value only when the chain
        // is selected for import AND the value is non-empty.
        func res(_ wants: Bool, _ v: String) -> String? { (wants && !v.isEmpty) ? v : nil }
        let resolvedBitcoinAddress = res(wantsBitcoinImport, trimmedBitcoinAddress), resolvedBitcoinXPub = res(wantsBitcoinImport, trimmedBitcoinXPub)
        let resolvedBitcoinCashAddress = res(wantsBitcoinCashImport, typedBitcoinCashAddress), resolvedBitcoinSVAddress = res(wantsBitcoinSVImport, typedBitcoinSVAddress)
        let resolvedLitecoinAddress = res(wantsLitecoinImport, typedLitecoinAddress)
        let resolvedTronAddress = res(wantsTronImport, typedTronAddress), resolvedSolanaAddress = res(wantsSolanaImport, typedSolanaAddress)
        let resolvedXRPAddress = res(wantsXRPImport, typedXRPAddress), resolvedStellarAddress = res(wantsStellarImport, typedStellarAddress)
        let resolvedMoneroAddress = res(wantsMoneroImport, typedMoneroAddress), resolvedCardanoAddress = res(wantsCardanoImport, typedCardanoAddress)
        let resolvedSuiAddress = res(wantsSuiImport, typedSuiAddress), resolvedAptosAddress = res(wantsAptosImport, typedAptosAddress)
        let resolvedTONAddress = res(wantsTONImport, typedTonAddress), resolvedICPAddress = res(wantsICPImport, typedICPAddress)
        let resolvedNearAddress = res(wantsNearImport, typedNearAddress), resolvedPolkadotAddress = res(wantsPolkadotImport, typedPolkadotAddress)
        if isPrivateKeyImport {
            guard PrivateKeyHex.isLikely(trimmedPrivateKey) else {
                importError = "Enter a valid 32-byte hex key."
                return
            }
            guard selectedChainNames.allSatisfy({ chainSupportsPrivateKeyImport(chainName: $0) }) else {
                importError = "Private key import currently supports every chain in this build except Monero."
                return
            }
            let derivedAddress = derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName)
            guard derivedAddress.bitcoin != nil || derivedAddress.bitcoinCash != nil || derivedAddress.bitcoinSV != nil || derivedAddress.litecoin != nil || derivedAddress.dogecoin != nil || derivedAddress.evm != nil || derivedAddress.tron != nil || derivedAddress.solana != nil || derivedAddress.xrp != nil || derivedAddress.stellar != nil || derivedAddress.cardano != nil || derivedAddress.sui != nil || derivedAddress.aptos != nil || derivedAddress.ton != nil || derivedAddress.icp != nil || derivedAddress.near != nil || derivedAddress.polkadot != nil else {
                importError = "Unable to derive an address from this key."
                return
            }}
        if isWatchOnlyImport && wantsBitcoinImport {
            let hasValidAddress = !bitcoinAddressEntries.isEmpty
                && bitcoinAddressEntries.allSatisfy { AddressValidation.isValidBitcoinAddress($0, networkMode: self.bitcoinNetworkMode) }
            let hasValidXPub = resolvedBitcoinXPub.map { $0.hasPrefix("xpub") || $0.hasPrefix("ypub") || $0.hasPrefix("zpub") } ?? false
            if !hasValidAddress && !hasValidXPub {
                importError = "Enter one valid Bitcoin address per line or a valid xpub/zpub for watched addresses."
                return
            }}
        if wantsMoneroImport {
            if (resolvedMoneroAddress?.isEmpty ?? true) || !AddressValidation.isValidMoneroAddress(resolvedMoneroAddress ?? "") {
                importError = localizedStoreString("Enter a valid Monero address.")
                return
            }
            if isWatchOnlyImport {
                importError = "Monero watched addresses are not supported in this build."
                return
            }}
        if wantsCardanoImport && !isWatchOnlyImport {
            if let resolvedCardanoAddress, !resolvedCardanoAddress.isEmpty, !AddressValidation.isValidCardanoAddress(resolvedCardanoAddress) {
                importError = localizedStoreString("Enter a valid Cardano address.")
                return
            }}
        if isWatchOnlyImport {
            let watchOnlyValidations: [(Bool, [String], (String) -> Bool, String)] = [
                (wantsBitcoinCashImport, bitcoinCashAddressEntries, AddressValidation.isValidBitcoinCashAddress,    "Bitcoin Cash address"), (wantsBitcoinSVImport,   bitcoinSvAddressEntries,   AddressValidation.isValidBitcoinSVAddress,      "Bitcoin SV address"), (wantsLitecoinImport,    litecoinAddressEntries,    AddressValidation.isValidLitecoinAddress,        "Litecoin address"), (wantsDogecoinImport,    dogecoinAddressEntries,    { self.isValidDogecoinAddressForPolicy($0) },    "Dogecoin address"), (wantsTronImport,        tronAddressEntries,        AddressValidation.isValidTronAddress,            "Tron address"), (wantsSolanaImport,      solanaAddressEntries,      AddressValidation.isValidSolanaAddress,          "Solana address"), (wantsXRPImport,         xrpAddressEntries,         AddressValidation.isValidXRPAddress,             "XRP address"), (wantsStellarImport,     stellarAddressEntries,     AddressValidation.isValidStellarAddress,         "Stellar address"), (wantsCardanoImport,     cardanoAddressEntries,     AddressValidation.isValidCardanoAddress,         "Cardano address"), (wantsSuiImport,         suiAddressEntries,         AddressValidation.isValidSuiAddress,             "Sui address"), (wantsAptosImport,       aptosAddressEntries,       AddressValidation.isValidAptosAddress,           "Aptos address"), (wantsTONImport,         tonAddressEntries,         AddressValidation.isValidTONAddress,             "TON address"), (wantsICPImport,         icpAddressEntries,         AddressValidation.isValidICPAddress,             "Internet Computer account identifier"), (wantsNearImport,        nearAddressEntries,        AddressValidation.isValidNearAddress,            "NEAR address"), (wantsPolkadotImport,    polkadotAddressEntries,    AddressValidation.isValidPolkadotAddress,        "Polkadot address"), ]
            for (wantsImport, entries, validator, name) in watchOnlyValidations where wantsImport {
                if entries.isEmpty || !entries.allSatisfy(validator) {
                    importError = "Enter one valid \(name) per line for watched addresses."
                    return
                }}}
        if isWatchOnlyImport && (wantsEthereumImport || wantsEthereumClassicImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport) {
            if ethereumAddressEntries.isEmpty || !ethereumAddressEntries.allSatisfy(AddressValidation.isValidEthereumAddress) {
                importError = "Enter one valid EVM address per line for watched addresses."
                return
            }}
        if editingWalletID == nil {
            let bitcoinCashAddress: String?, bitcoinSvAddress: String?, litecoinAddress: String?, dogecoinAddress: String?
            let ethereumAddress: String?, ethereumClassicAddress: String?
            let tronAddress: String?, solanaAddress: String?, xrpAddress: String?, stellarAddress: String?
            let moneroAddress: String?, cardanoAddress: String?
            let suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?
            let derivedBitcoinAddress: String?
            let createdWalletIDs = selectedChainNames.map { _ in UUID() }
            let bitcoinWalletID = zip(selectedChainNames, createdWalletIDs).first(where: { $0.0 == "Bitcoin" })? .1
            if requiresSeedPhrase {
                let p = selectedDerivationPaths
                let needsEvm = wantsEthereumImport || wantsArbitrumImport || wantsOptimismImport || wantsBNBImport || wantsAvalancheImport || wantsHyperliquidImport
                let chainPathCandidates: [(Bool, String, String)] = [
                    (wantsBitcoinImport, "Bitcoin", p.bitcoin), (wantsBitcoinCashImport, "Bitcoin Cash", p.bitcoinCash), (wantsBitcoinSVImport, "Bitcoin SV", p.bitcoinSV), (wantsLitecoinImport, "Litecoin", p.litecoin), (wantsDogecoinImport, "Dogecoin", p.dogecoin), (needsEvm, "Ethereum", p.ethereum), (wantsEthereumClassicImport, "Ethereum Classic", p.ethereumClassic), (wantsTronImport, "Tron", p.tron), (wantsSolanaImport, "Solana", p.solana), (wantsCardanoImport, "Cardano", p.cardano), (wantsXRPImport, "XRP Ledger", p.xrp), (wantsStellarImport, "Stellar", p.stellar), (wantsSuiImport, "Sui", p.sui), (wantsAptosImport, "Aptos", p.aptos), (wantsTONImport, "TON", p.ton), (wantsICPImport, "Internet Computer", p.internetComputer), (wantsNearImport, "NEAR", p.near), (wantsPolkadotImport, "Polkadot", p.polkadot),
                ]
                let chainPaths: [String: String] = Dictionary(uniqueKeysWithValues: chainPathCandidates.compactMap { $0.0 ? ($0.1, $0.2) : nil })
                do {
                    let derived = try WalletRustDerivationBridge.deriveAllAddresses(
                        seedPhrase: trimmedSeedPhrase, chainPaths: chainPaths
                    )
                    if wantsBitcoinImport {
                        guard let bitcoinWalletID else {
                            importError = "Bitcoin wallet initialization failed."
                            return
                        }
                        _ = bitcoinWalletID
                    }
                    derivedBitcoinAddress = derived["Bitcoin"]; bitcoinCashAddress = derived["Bitcoin Cash"]; bitcoinSvAddress = derived["Bitcoin SV"]
                    litecoinAddress = derived["Litecoin"]; dogecoinAddress = derived["Dogecoin"]
                    ethereumAddress = derived["Ethereum"]; ethereumClassicAddress = derived["Ethereum Classic"]
                    tronAddress = derived["Tron"]; solanaAddress = derived["Solana"]; cardanoAddress = derived["Cardano"]
                    xrpAddress = derived["XRP Ledger"]; stellarAddress = derived["Stellar"]
                    suiAddress = derived["Sui"]; aptosAddress = derived["Aptos"]; tonAddress = derived["TON"]
                    icpAddress = derived["Internet Computer"]; nearAddress = derived["NEAR"]; polkadotAddress = derived["Polkadot"]
                    moneroAddress = resolvedMoneroAddress
                } catch {
                    let resolvedMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    if resolvedMessage.isEmpty || resolvedMessage == "(null)" { importError = "Wallet initialization failed. Check the seed phrase." } else { importError = resolvedMessage }
                    return
                }
            } else {
                let derivedPrivateKeyAddress = isPrivateKeyImport ? derivePrivateKeyImportAddress(privateKeyHex: trimmedPrivateKey, chainName: primarySelectedChainName) : PrivateKeyImportAddressResolution(bitcoin: nil, bitcoinCash: nil, bitcoinSV: nil, litecoin: nil, dogecoin: nil, evm: nil, tron: nil, solana: nil, xrp: nil, stellar: nil, cardano: nil, sui: nil, aptos: nil, ton: nil, icp: nil, near: nil, polkadot: nil)
                derivedBitcoinAddress = derivedPrivateKeyAddress.bitcoin
                bitcoinCashAddress = derivedPrivateKeyAddress.bitcoinCash ?? (AddressValidation.isValidBitcoinCashAddress(typedBitcoinCashAddress) ? typedBitcoinCashAddress : nil)
                bitcoinSvAddress = derivedPrivateKeyAddress.bitcoinSV ?? (AddressValidation.isValidBitcoinSVAddress(typedBitcoinSVAddress) ? typedBitcoinSVAddress : nil)
                litecoinAddress = derivedPrivateKeyAddress.litecoin ?? (AddressValidation.isValidLitecoinAddress(typedLitecoinAddress) ? typedLitecoinAddress : nil)
                dogecoinAddress = derivedPrivateKeyAddress.dogecoin ?? (isValidDogecoinAddressForPolicy(typedDogecoinAddress) ? typedDogecoinAddress : nil)
                ethereumAddress = derivedPrivateKeyAddress.evm ?? (AddressValidation.isValidEthereumAddress(typedEthereumAddress) ? normalizeEVMAddress(typedEthereumAddress) : nil)
                ethereumClassicAddress = ethereumAddress
                tronAddress = derivedPrivateKeyAddress.tron ?? (AddressValidation.isValidTronAddress(typedTronAddress) ? typedTronAddress : nil)
                solanaAddress = derivedPrivateKeyAddress.solana ?? (AddressValidation.isValidSolanaAddress(typedSolanaAddress) ? typedSolanaAddress : nil)
                xrpAddress = derivedPrivateKeyAddress.xrp ?? (AddressValidation.isValidXRPAddress(typedXRPAddress) ? typedXRPAddress : nil)
                stellarAddress = derivedPrivateKeyAddress.stellar ?? (AddressValidation.isValidStellarAddress(typedStellarAddress) ? typedStellarAddress : nil)
                moneroAddress = AddressValidation.isValidMoneroAddress(typedMoneroAddress) ? typedMoneroAddress : nil
                cardanoAddress = derivedPrivateKeyAddress.cardano ?? (AddressValidation.isValidCardanoAddress(typedCardanoAddress) ? typedCardanoAddress : nil)
                suiAddress = derivedPrivateKeyAddress.sui ?? (AddressValidation.isValidSuiAddress(typedSuiAddress) ? typedSuiAddress.lowercased() : nil)
                aptosAddress = derivedPrivateKeyAddress.aptos ?? (AddressValidation.isValidAptosAddress(typedAptosAddress) ? normalizedAddress(typedAptosAddress, for: "Aptos") : nil)
                tonAddress = derivedPrivateKeyAddress.ton ?? (AddressValidation.isValidTONAddress(typedTonAddress) ? normalizedAddress(typedTonAddress, for: "TON") : nil)
                icpAddress = derivedPrivateKeyAddress.icp ?? (AddressValidation.isValidICPAddress(typedICPAddress) ? normalizedAddress(typedICPAddress, for: "Internet Computer") : nil)
                nearAddress = derivedPrivateKeyAddress.near ?? (AddressValidation.isValidNearAddress(typedNearAddress) ? typedNearAddress.lowercased() : nil)
                polkadotAddress = derivedPrivateKeyAddress.polkadot ?? (AddressValidation.isValidPolkadotAddress(typedPolkadotAddress) ? typedPolkadotAddress : nil)
            }
            let plannedWalletIDs: [UUID]
            if isWatchOnlyImport {
                let watchOnlyEntriesByChain: [String: [String]] = [
                    "Bitcoin": bitcoinAddressEntries, "Bitcoin Cash": bitcoinCashAddressEntries, "Bitcoin SV": bitcoinSvAddressEntries, "Litecoin": litecoinAddressEntries, "Dogecoin": dogecoinAddressEntries, "Tron": tronAddressEntries, "Solana": solanaAddressEntries, "XRP Ledger": xrpAddressEntries, "Stellar": stellarAddressEntries, "Cardano": cardanoAddressEntries, "Sui": suiAddressEntries, "Aptos": aptosAddressEntries, "TON": tonAddressEntries, "Internet Computer": icpAddressEntries, "NEAR": nearAddressEntries, "Polkadot": polkadotAddressEntries,
                ]
                let evmChains: Set<String> = ["Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid"]
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
                plannedWalletIDs = selectedChainNames.map { _ in UUID() }}
            let importPlanRequest = WalletRustImportPlanRequest(
                walletName: trimmedWalletName, defaultWalletNameStartIndex: defaultWalletNameStartIndex, primarySelectedChainName: primarySelectedChainName, selectedChainNames: selectedChainNames, plannedWalletIDs: plannedWalletIDs.map(\.uuidString), isWatchOnlyImport: isWatchOnlyImport, isPrivateKeyImport: isPrivateKeyImport, hasWalletPassword: trimmedWalletPassword != nil, resolvedAddresses: WalletRustImportAddresses(
                    bitcoinAddress: resolvedBitcoinAddress ?? derivedBitcoinAddress, bitcoinXpub: resolvedBitcoinXPub, bitcoinCashAddress: resolvedBitcoinCashAddress ?? bitcoinCashAddress, bitcoinSvAddress: resolvedBitcoinSVAddress ?? bitcoinSvAddress, litecoinAddress: resolvedLitecoinAddress ?? litecoinAddress, dogecoinAddress: dogecoinAddress, ethereumAddress: ethereumAddress, ethereumClassicAddress: ethereumClassicAddress, tronAddress: resolvedTronAddress ?? tronAddress, solanaAddress: resolvedSolanaAddress ?? solanaAddress, xrpAddress: resolvedXRPAddress ?? xrpAddress, stellarAddress: resolvedStellarAddress ?? stellarAddress, moneroAddress: resolvedMoneroAddress ?? moneroAddress, cardanoAddress: resolvedCardanoAddress ?? cardanoAddress, suiAddress: resolvedSuiAddress ?? suiAddress, aptosAddress: resolvedAptosAddress ?? aptosAddress, tonAddress: resolvedTONAddress ?? tonAddress, icpAddress: resolvedICPAddress ?? icpAddress, nearAddress: resolvedNearAddress ?? nearAddress, polkadotAddress: resolvedPolkadotAddress ?? polkadotAddress
                ), watchOnlyEntries: WalletRustWatchOnlyEntries(
                    bitcoinAddresses: bitcoinAddressEntries, bitcoinXpub: resolvedBitcoinXPub, bitcoinCashAddresses: bitcoinCashAddressEntries, bitcoinSvAddresses: bitcoinSvAddressEntries, litecoinAddresses: litecoinAddressEntries, dogecoinAddresses: dogecoinAddressEntries, ethereumAddresses: ethereumAddressEntries.map { normalizeEVMAddress($0) }, tronAddresses: tronAddressEntries, solanaAddresses: solanaAddressEntries, xrpAddresses: xrpAddressEntries, stellarAddresses: stellarAddressEntries, cardanoAddresses: cardanoAddressEntries, suiAddresses: suiAddressEntries.map { $0.lowercased() }, aptosAddresses: aptosAddressEntries.map { normalizedAddress($0, for: "Aptos") }, tonAddresses: tonAddressEntries.map { normalizedAddress($0, for: "TON") }, icpAddresses: icpAddressEntries.map { normalizedAddress($0, for: "Internet Computer") }, nearAddresses: nearAddressEntries.map { $0.lowercased() }, polkadotAddresses: polkadotAddressEntries
                )
            )
            let importPlan: WalletRustImportPlan
            do {
                importPlan = try WalletRustAppCoreBridge.planWalletImport(importPlanRequest)
            } catch {
                importError = error.localizedDescription
                return
            }
            let createdWallets: [ImportedWallet] = importPlan.wallets.compactMap { plannedWallet in
                guard let walletID = UUID(uuidString: plannedWallet.walletID) else { return nil }
                return walletForPlannedImport(
                    id: walletID, plan: plannedWallet, seedDerivationPreset: selectedDerivationPreset, seedDerivationPaths: selectedDerivationPaths, holdings: coins
                )
            }
            for instruction in importPlan.secretInstructions {
                let walletID = instruction.walletID
                let account = resolvedSeedPhraseAccount(for: walletID)
                let passwordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
                let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
                if instruction.shouldStoreSeedPhrase { try? SecureSeedStore.save(trimmedSeedPhrase, for: account) } else { try? SecureSeedStore.deleteValue(for: account) }
                if instruction.shouldStorePasswordVerifier, let trimmedWalletPassword { try? SecureSeedPasswordStore.save(trimmedWalletPassword, for: passwordAccount) } else { try? SecureSeedPasswordStore.deleteValue(for: passwordAccount) }
                if instruction.shouldStorePrivateKey { SecurePrivateKeyStore.save(trimmedPrivateKey, for: privateKeyAccount) } else { SecurePrivateKeyStore.deleteValue(for: privateKeyAccount) }}
            appendWallets(createdWallets)
            importedWalletsForRefresh = createdWallets
            for w in createdWallets {
                let holdingsArr: [[String: Any]] = w.holdings.map { coin in
                    var h: [String: Any] = [
                        "name": coin.name, "symbol": coin.symbol, "marketDataId": coin.marketDataId, "coinGeckoId": coin.coinGeckoId, "chainName": coin.chainName, "tokenStandard": coin.tokenStandard, "amount": coin.amount, "priceUsd": coin.priceUsd
                    ]
                    if let contract = coin.contractAddress { h["contractAddress"] = contract }
                    return h
                }
                let summary: [String: Any] = [
                    "id": w.id, "name": w.name, "isWatchOnly": false, "selectedChain": w.selectedChain, "includeInPortfolioTotal": w.includeInPortfolioTotal, "bitcoinNetworkMode": w.bitcoinNetworkMode.rawValue, "dogecoinNetworkMode": w.dogecoinNetworkMode.rawValue, "derivationPreset": w.seedDerivationPreset ?? "standard", "derivationPaths": w.seedDerivationPaths ?? [:], "holdings": holdingsArr, "addresses": []
                ]
                if let data = try? JSONSerialization.data(withJSONObject: summary), let json = String(data: data, encoding: .utf8) {
                    Task { try? await WalletServiceBridge.shared.upsertWalletJSON(json) }}}}
        finishWalletImportFlow()
        withAnimation {
        }
        scheduleImportedWalletRefresh(importedWalletsForRefresh)
    }
    func renameWallet(id: String, to newName: String) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        let wallet = wallets[index]
        wallets[index] = ImportedWallet(
            id: wallet.id, name: newName, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: wallet.holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
        finishWalletImportFlow()
    }
    func finishWalletImportFlow() {
        importError = nil
        importDraft.clearSensitiveInputs()
        resetImportForm()
        editingWalletID = nil
        isShowingWalletImporter = false
    }
    struct PrivateKeyImportAddressResolution {
        var bitcoin: String? = nil; var bitcoinCash: String? = nil; var bitcoinSV: String? = nil
        var litecoin: String? = nil; var dogecoin: String? = nil; var evm: String? = nil
        var tron: String? = nil; var solana: String? = nil; var xrp: String? = nil
        var stellar: String? = nil; var cardano: String? = nil; var sui: String? = nil
        var aptos: String? = nil; var ton: String? = nil; var icp: String? = nil
        var near: String? = nil; var polkadot: String? = nil
        static func only(bitcoin: String? = nil, bitcoinCash: String? = nil, bitcoinSV: String? = nil, litecoin: String? = nil, dogecoin: String? = nil, evm: String? = nil, tron: String? = nil, solana: String? = nil, xrp: String? = nil, stellar: String? = nil, cardano: String? = nil, sui: String? = nil, aptos: String? = nil, ton: String? = nil, icp: String? = nil, near: String? = nil, polkadot: String? = nil) -> Self {
            Self(bitcoin: bitcoin, bitcoinCash: bitcoinCash, bitcoinSV: bitcoinSV, litecoin: litecoin, dogecoin: dogecoin, evm: evm, tron: tron, solana: solana, xrp: xrp, stellar: stellar, cardano: cardano, sui: sui, aptos: aptos, ton: ton, icp: icp, near: near, polkadot: polkadot)
        }
    }
    func derivePrivateKeyImportAddress(privateKeyHex: String, chainName: String?) -> PrivateKeyImportAddressResolution {
        guard let chainName else { return .only() }
        typealias D = SeedPhraseAddressDerivation
        let p = privateKeyHex
        switch chainName {
        case "Bitcoin": return .only(bitcoin: try? D.bitcoinAddress(forPrivateKey: p))
        case "Bitcoin Cash": return .only(bitcoinCash: try? D.bitcoinCashAddress(forPrivateKey: p))
        case "Bitcoin SV": return .only(bitcoinSV: try? D.bitcoinSvAddress(forPrivateKey: p))
        case "Litecoin": return .only(litecoin: try? D.litecoinAddress(forPrivateKey: p))
        case "Dogecoin": return .only(dogecoin: try? D.dogecoinAddress(forPrivateKey: p))
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return .only(evm: try? D.evmAddress(forPrivateKey: p))
        case "Tron": return .only(tron: try? D.tronAddress(forPrivateKey: p))
        case "Solana": return .only(solana: try? D.solanaAddress(forPrivateKey: p))
        case "XRP Ledger": return .only(xrp: try? D.xrpAddress(forPrivateKey: p))
        case "Stellar": return .only(stellar: try? D.stellarAddress(forPrivateKey: p))
        case "Cardano": return .only(cardano: try? D.cardanoAddress(forPrivateKey: p))
        case "Sui": return .only(sui: try? D.suiAddress(forPrivateKey: p))
        case "Aptos": return .only(aptos: try? D.aptosAddress(forPrivateKey: p))
        case "TON": return .only(ton: try? D.tonAddress(forPrivateKey: p))
        case "Internet Computer": return .only(icp: try? D.icpAddress(forPrivateKey: p))
        case "NEAR": return .only(near: try? D.nearAddress(forPrivateKey: p))
        case "Polkadot": return .only(polkadot: try? D.polkadotAddress(forPrivateKey: p))
        default: return .only()
        }
    }
    static func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String) throws -> String {
        let result = try WalletDerivationLayer.derive(
            seedPhrase: seedPhrase, request: WalletDerivationRequest(
                chain: chain, network: network, derivationPath: derivationPath, curve: WalletDerivationEngine.curve(for: chain), requestedOutputs: [.address]
            )
        )
        guard let address = result.address else { throw WalletDerivationEngineError.emptyRequestedOutputs }
        return address
    }
    func deriveSeedPhraseAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String) throws -> String { try Self.deriveSeedPhraseAddress(seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath) }
    func derivationNetwork(for chain: SeedDerivationChain, wallet: ImportedWallet? = nil) -> WalletDerivationNetwork {
        switch chain {
        case .bitcoin: return derivationNetwork(for: wallet.map(bitcoinNetworkMode(for:)) ?? bitcoinNetworkMode)
        case .dogecoin: return derivationNetwork(for: wallet.map(dogecoinNetworkMode(for:)) ?? dogecoinNetworkMode)
        default: return .mainnet
        }
    }
    func derivationNetwork(for networkMode: BitcoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode { case .mainnet: .mainnet; case .testnet: .testnet; case .testnet4: .testnet4; case .signet: .signet }
    }
    func derivationNetwork(for networkMode: DogecoinNetworkMode) -> WalletDerivationNetwork {
        networkMode == .testnet ? .testnet : .mainnet
    }
    func utxoDiscoveryDerivationChain(for chainName: String) -> SeedDerivationChain? { ["Bitcoin": SeedDerivationChain.bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSV, "Litecoin": .litecoin, "Dogecoin": .dogecoin][chainName] }
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
    func walletForSingleChain(id: UUID, name: String, chainName: String, bitcoinAddress: String?, bitcoinXpub: String?, bitcoinCashAddress: String?, bitcoinSvAddress: String?, litecoinAddress: String?, dogecoinAddress: String?, ethereumAddress: String?, tronAddress: String?, solanaAddress: String?, xrpAddress: String?, stellarAddress: String?, moneroAddress: String?, cardanoAddress: String?, suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths, holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: id.uuidString, name: name, bitcoinNetworkMode: chainName == "Bitcoin" ? bitcoinNetworkMode : .mainnet, dogecoinNetworkMode: chainName == "Dogecoin" ? dogecoinNetworkMode : .mainnet, bitcoinAddress: chainName == "Bitcoin" ? bitcoinAddress : nil, bitcoinXpub: chainName == "Bitcoin" ? bitcoinXpub : nil, bitcoinCashAddress: chainName == "Bitcoin Cash" ? bitcoinCashAddress : nil, bitcoinSvAddress: chainName == "Bitcoin SV" ? bitcoinSvAddress : nil, litecoinAddress: chainName == "Litecoin" ? litecoinAddress : nil, dogecoinAddress: chainName == "Dogecoin" ? dogecoinAddress : nil, ethereumAddress: (chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid") ? ethereumAddress : nil, tronAddress: chainName == "Tron" ? tronAddress : nil, solanaAddress: chainName == "Solana" ? solanaAddress : nil, stellarAddress: chainName == "Stellar" ? stellarAddress : nil, xrpAddress: chainName == "XRP Ledger" ? xrpAddress : nil, moneroAddress: chainName == "Monero" ? moneroAddress : nil, cardanoAddress: chainName == "Cardano" ? cardanoAddress : nil, suiAddress: chainName == "Sui" ? suiAddress : nil, aptosAddress: chainName == "Aptos" ? aptosAddress : nil, tonAddress: chainName == "TON" ? tonAddress : nil, icpAddress: chainName == "Internet Computer" ? icpAddress : nil, nearAddress: chainName == "NEAR" ? nearAddress : nil, polkadotAddress: chainName == "Polkadot" ? polkadotAddress : nil, seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths, selectedChain: chainName, holdings: holdings.filter { $0.chainName == chainName }, includeInPortfolioTotal: true
        )
    }
    func walletForPlannedImport(id: UUID, plan: WalletRustPlannedWallet, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths, holdings: [Coin]) -> ImportedWallet {
        walletForSingleChain(
            id: id, name: plan.name, chainName: plan.chainName, bitcoinAddress: plan.addresses.bitcoinAddress, bitcoinXpub: plan.addresses.bitcoinXpub, bitcoinCashAddress: plan.addresses.bitcoinCashAddress, bitcoinSvAddress: plan.addresses.bitcoinSvAddress, litecoinAddress: plan.addresses.litecoinAddress, dogecoinAddress: plan.addresses.dogecoinAddress, ethereumAddress: plan.chainName == "Ethereum Classic"
                ? (plan.addresses.ethereumClassicAddress ?? plan.addresses.ethereumAddress)
                : plan.addresses.ethereumAddress, tronAddress: plan.addresses.tronAddress, solanaAddress: plan.addresses.solanaAddress, xrpAddress: plan.addresses.xrpAddress, stellarAddress: plan.addresses.stellarAddress, moneroAddress: plan.addresses.moneroAddress, cardanoAddress: plan.addresses.cardanoAddress, suiAddress: plan.addresses.suiAddress, aptosAddress: plan.addresses.aptosAddress, tonAddress: plan.addresses.tonAddress, icpAddress: plan.addresses.icpAddress, nearAddress: plan.addresses.nearAddress, polkadotAddress: plan.addresses.polkadotAddress, seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths, holdings: holdings
        )
    }
    func walletByReplacingHoldings(_ wallet: ImportedWallet, with holdings: [Coin]) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
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
        return order.compactMap { grouped[$0] }}
    var hasLivePriceRefreshWork: Bool { !priceRequestCoins.isEmpty }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home && hasLivePriceRefreshWork }
    var hasPendingTransactionMaintenanceWork: Bool {
        transactions.contains { transaction in
            guard transaction.kind == .send, transaction.transactionHash != nil else { return false }
            if transaction.status == .pending { return true }
            return transaction.status == .confirmed
        }}
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
    var pendingTransactionMaintenanceChainIDs: Set<WalletChainID> { Set(pendingTransactionMaintenanceChains.compactMap(WalletChainID.init)) }
    var refreshableChainNames: Set<String> { cachedRefreshableChainNames }
    var refreshableChainIDs: Set<WalletChainID> { Set(refreshableChainNames.compactMap(WalletChainID.init)) }
    var backgroundBalanceRefreshFrequencyMinutes: Int { max(automaticRefreshFrequencyMinutes * 3, 15) }
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
    func persistAssetDisplayDecimalsByChain() { persistCodableToSQLite(assetDisplayDecimalsByChain, key: Self.assetDisplayDecimalsByChainDefaultsKey) }
}
