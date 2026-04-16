import Foundation
import SwiftUI
@MainActor
extension AppState {
func resetImportForm() {
    importDraft.configureForNewWallet()
}
    func beginWalletImport() {
        importDraft.configureForNewWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWatchAddressesImport() {
        importDraft.configureForWatchAddressesImport()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWalletCreation() {
        importDraft.configureForCreatedWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func cancelWalletImport() {
        importDraft.configureForNewWallet()
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = false
    }
    func beginEditingWallet(_ wallet: ImportedWallet) {
        editingWalletID = wallet.id
        importError = nil
        isImportingWallet = false
        importDraft.configureForEditing(wallet: wallet)
        isShowingWalletImporter = true
    }
    func confirmDeleteWallet(_ wallet: ImportedWallet) { walletPendingDeletion = wallet }
    func deletePendingWallet() async {
        guard let walletPendingDeletion else { return }
        guard await authenticateForSensitiveAction(
            reason: "Authenticate to delete wallet", allowWhenAuthenticationUnavailable: true
        ) else {
            return
        }
        let deletedWalletID = walletPendingDeletion.id
        let deletedWalletIDString = deletedWalletID
        let deletedChainName = normalizedWalletChainName(walletPendingDeletion.selectedChain)
        deleteWalletSecrets(for: deletedWalletID)
        await WalletServiceBridge.shared.deleteWalletRelationalData(walletId: deletedWalletIDString)
        removeWallet(id: walletPendingDeletion.id)
        let hasRemainingWalletsOnDeletedChain = wallets.contains { normalizedWalletChainName($0.selectedChain) == deletedChainName }
        resetLargeMovementAlertBaseline()
        removeTransactions(forWalletID: walletPendingDeletion.id)
        dogecoinKeypoolByWalletID[walletPendingDeletion.id] = nil
        discoveredDogecoinAddressesByWallet[walletPendingDeletion.id] = nil
        for chainName in discoveredUTXOAddressesByChain.keys { discoveredUTXOAddressesByChain[chainName]?[walletPendingDeletion.id] = nil }
        clearHistoryTracking(for: walletPendingDeletion.id)
        clearDeletedWalletDiagnostics(
            walletID: deletedWalletID, chainName: deletedChainName, hasRemainingWalletsOnChain: hasRemainingWalletsOnDeletedChain
        )
        dogecoinOwnedAddressMap = dogecoinOwnedAddressMap.filter { _, value in
            value.walletID != walletPendingDeletion.id
        }
        if receiveWalletID == deletedWalletIDString {
            receiveWalletID = ""
            receiveChainName = ""
            receiveHoldingKey = ""
            receiveResolvedAddress = ""
            isResolvingReceiveAddress = false
        }
        if sendWalletID == deletedWalletIDString { cancelSend() }
        if editingWalletID == deletedWalletID {
            editingWalletID = nil
            isShowingWalletImporter = false
        }
        selectedMainTab = .home
        self.walletPendingDeletion = nil
        if wallets.isEmpty { cancelWalletImport() }}
    func wallet(for walletID: String) -> ImportedWallet? { cachedWalletByIDString[walletID] }
    func knownOwnedAddresses(for walletID: String) -> [String] {
        guard let wallet = cachedWalletByID[walletID] else { return [] }
        var candidateAddresses: [String] = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            candidateAddresses.append(candidate)
        }
        appendAddress(wallet.bitcoinAddress)
        appendAddress(wallet.bitcoinCashAddress)
        appendAddress(wallet.bitcoinSvAddress)
        appendAddress(wallet.litecoinAddress)
        appendAddress(wallet.dogecoinAddress)
        appendAddress(wallet.ethereumAddress)
        appendAddress(wallet.tronAddress)
        appendAddress(wallet.solanaAddress)
        appendAddress(wallet.stellarAddress)
        appendAddress(wallet.xrpAddress)
        appendAddress(wallet.moneroAddress)
        appendAddress(wallet.cardanoAddress)
        appendAddress(wallet.suiAddress)
        appendAddress(wallet.aptosAddress)
        appendAddress(wallet.icpAddress)
        appendAddress(wallet.nearAddress)
        appendAddress(wallet.polkadotAddress)
        appendAddress(resolvedBitcoinCashAddress(for: wallet))
        appendAddress(resolvedBitcoinSVAddress(for: wallet))
        appendAddress(resolvedLitecoinAddress(for: wallet))
        appendAddress(resolvedDogecoinAddress(for: wallet))
        appendAddress(resolvedEthereumAddress(for: wallet))
        appendAddress(resolvedTronAddress(for: wallet))
        appendAddress(resolvedSolanaAddress(for: wallet))
        appendAddress(resolvedXRPAddress(for: wallet))
        appendAddress(resolvedStellarAddress(for: wallet))
        appendAddress(resolvedMoneroAddress(for: wallet))
        appendAddress(resolvedCardanoAddress(for: wallet))
        appendAddress(resolvedSuiAddress(for: wallet))
        appendAddress(resolvedAptosAddress(for: wallet))
        appendAddress(resolvedTONAddress(for: wallet))
        appendAddress(resolvedICPAddress(for: wallet))
        appendAddress(resolvedNearAddress(for: wallet))
        appendAddress(resolvedPolkadotAddress(for: wallet))
        for transaction in transactions where transaction.walletID == walletID {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }
        for addresses in chainOwnedAddressMapByChain.values {
            for value in addresses.values where value.walletID == walletID { appendAddress(value.address) }}
        let request = WalletRustOwnedAddressAggregationRequest(candidateAddresses: candidateAddresses)
        return WalletRustAppCoreBridge.aggregateOwnedAddresses(request)
    }
    func canRevealSeedPhrase(for walletID: String) -> Bool { storedSeedPhrase(for: walletID) != nil }
    func verifySeedPhrasePassword(_ password: String, for walletID: String) -> Bool {
        let account = resolvedSeedPhrasePasswordAccount(for: walletID)
        return SecureSeedPasswordStore.verify(password, for: account)
    }
    func isWatchOnlyWallet(_ wallet: ImportedWallet) -> Bool { !walletHasSigningMaterial(wallet.id) }
    func isPrivateKeyWallet(_ wallet: ImportedWallet) -> Bool { isPrivateKeyBackedWallet(wallet.id) }
    func revealSeedPhrase(for wallet: ImportedWallet, password: String? = nil) async throws -> String {
        let authenticated = await authenticateForSeedPhraseReveal(reason: "Authenticate to view seed phrase for \(wallet.name)")
        guard authenticated else { throw SeedPhraseRevealError.authenticationRequired }
        if walletRequiresSeedPhrasePassword(wallet.id) {
            guard let providedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines), !providedPassword.isEmpty else { throw SeedPhraseRevealError.passwordRequired }
            guard verifySeedPhrasePassword(providedPassword, for: wallet.id) else { throw SeedPhraseRevealError.invalidPassword }}
        guard let seedPhrase = storedSeedPhrase(for: wallet.id), !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SeedPhraseRevealError.unavailable }
        return seedPhrase
    }
    func availableSendCoins(for walletID: String) -> [Coin] { cachedAvailableSendCoinsByWalletID[walletID] ?? [] }
    func availableReceiveCoins(for walletID: String) -> [Coin] { cachedAvailableReceiveCoinsByWalletID[walletID] ?? [] }
    func availableReceiveChains(for walletID: String) -> [String] { cachedAvailableReceiveChainsByWalletID[walletID] ?? [] }
    func selectedReceiveCoin(for walletID: String) -> Coin? {
        let receiveCoins = availableReceiveCoins(for: walletID)
        if let plan = rustReceiveSelectionPlan(for: walletID, coins: receiveCoins) {
            guard let selectedIndex = plan.selectedReceiveHoldingIndex.map(Int.init), receiveCoins.indices.contains(selectedIndex) else { return nil }
            return receiveCoins[selectedIndex]
        }
        let resolvedChainName = resolvedReceiveChainName(for: walletID)
        guard !resolvedChainName.isEmpty else { return nil }
        var firstMatchingCoin: Coin?
        for coin in receiveCoins where coin.chainName == resolvedChainName {
            if firstMatchingCoin == nil { firstMatchingCoin = coin }
            if coin.contractAddress == nil { return coin }}
        return firstMatchingCoin
    }
    func resolvedReceiveChainName(for walletID: String) -> String {
        let availableChains = availableReceiveChains(for: walletID)
        if let plan = rustReceiveSelectionPlan(
            for: walletID, coins: availableReceiveCoins(for: walletID), chains: availableChains
        ) {
            return plan.resolvedChainName
        }
        if availableChains.contains(receiveChainName) { return receiveChainName }
        return availableChains.first ?? ""
    }
    private func rustReceiveSelectionPlan(for walletID: String, coins: [Coin]? = nil, chains: [String]? = nil) -> WalletRustReceiveSelectionPlan? {
        let receiveCoins = coins ?? availableReceiveCoins(for: walletID)
        let availableChains = chains ?? availableReceiveChains(for: walletID)
        let request = WalletRustReceiveSelectionRequest(
            receiveChainName: receiveChainName, availableReceiveChains: availableChains, availableReceiveHoldings: receiveCoins.enumerated().map { offset, coin in
                WalletRustReceiveSelectionHoldingInput(
                    holdingIndex: offset, chainName: coin.chainName, hasContractAddress: coin.contractAddress != nil
                )
            }
        )
        return WalletRustAppCoreBridge.planReceiveSelection(request)
    }
    var sendEnabledWallets: [ImportedWallet] { cachedSendEnabledWallets }
    var receiveEnabledWallets: [ImportedWallet] { cachedReceiveEnabledWallets }
    var canBeginSend: Bool { !sendEnabledWallets.isEmpty }
    var canBeginReceive: Bool { !receiveEnabledWallets.isEmpty }
    var alertableCoins: [Coin] { portfolio }
    var sendAddressBookEntries: [AddressBookEntry] {
        guard let selectedSendCoin else { return [] }
        return addressBook.filter { $0.chainName == selectedSendCoin.chainName }}
    var hasPendingEthereumSendForSelectedWallet: Bool { selectedPendingEthereumSendTransaction() != nil }
    var ethereumReplacementNonceStateMessage: String? {
        guard selectedSendCoin?.chainName == "Ethereum" else { return nil }
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else { return localizedStoreString("No pending Ethereum send found for this wallet. Replacement and cancel are available only for pending transactions.") }
        var message = localizedStoreFormat("Pending %@ transaction detected", pendingTransaction.symbol)
        if let nonce = pendingTransaction.ethereumNonce { message += localizedStoreFormat("send.replacement.pendingNonceSuffix", nonce) } else { message += "." }
        if let transactionHash = pendingTransaction.transactionHash {
            let shortHash = transactionHash.count > 14 ? "\(transactionHash.prefix(10))...\(transactionHash.suffix(4))" : transactionHash
            message += localizedStoreFormat("send.replacement.transactionSuffix", shortHash)
        }
        message += localizedStoreString(" Use Speed Up to resend with higher fees or Cancel to submit a 0-value self-transfer using the same nonce.")
        return message
    }
}
