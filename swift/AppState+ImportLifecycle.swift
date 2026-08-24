import Foundation
import SwiftUI
@MainActor
extension AppState {
    func resetImportForm() {
        importDraft.configureForNewWallet()
    }
    func beginWalletImport(setupMode: SetupModeChoice = .simple) {
        importDraft.configureForNewWallet()
        importDraft.setupModeChoice = setupMode
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWatchAddressesImport() {
        importDraft.configureForWatchAddressesImport()
        // Watch mode doesn't use derivation, so the simple/advanced toggle is
        // irrelevant — always reset to simple so the state is deterministic.
        importDraft.setupModeChoice = .simple
        importError = nil
        isImportingWallet = false
        editingWalletID = nil
        isShowingWalletImporter = true
    }
    func beginWalletCreation(setupMode: SetupModeChoice = .simple) {
        importDraft.configureForCreatedWallet()
        importDraft.setupModeChoice = setupMode
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
        guard
            await authenticateForSensitiveAction(
                reason: "Authenticate to delete wallet", allowWhenAuthenticationUnavailable: true
            )
        else {
            return
        }
        let deletedWalletID = walletPendingDeletion.id
        let deletedWalletIDString = deletedWalletID
        let deletedChainName = normalizedWalletChainName(walletPendingDeletion.selectedChain)
        deleteWalletSecrets(for: deletedWalletID)
        try? await WalletServiceBridge.shared.deleteWalletRelationalData(walletId: deletedWalletIDString)
        await removeWallet(id: walletPendingDeletion.id)
        let hasRemainingWalletsOnDeletedChain = wallets.contains { normalizedWalletChainName($0.selectedChain) == deletedChainName }
        resetLargeMovementAlertBaseline()
        removeTransactions(forWalletID: walletPendingDeletion.id)
        try? await WalletServiceBridge.shared.deleteKeypoolForWallet(walletId: walletPendingDeletion.id)
        for chainName in discoveredUTXOAddressesByChain.keys { discoveredUTXOAddressesByChain[chainName]?[walletPendingDeletion.id] = nil }
        clearHistoryTracking(for: walletPendingDeletion.id)
        clearDeletedWalletDiagnostics(
            walletID: deletedWalletID, chainName: deletedChainName, hasRemainingWalletsOnChain: hasRemainingWalletsOnDeletedChain
        )
        // Core drops the wallet's owned addresses in `deleteWalletRelationalData`.
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
        if wallets.isEmpty { cancelWalletImport() }
    }
    func wallet(for walletID: String) -> ImportedWallet? { cachedWalletByIDString[walletID] }
    func knownOwnedAddresses(for walletID: String) async -> [String] {
        guard let wallet = cachedWalletByID[walletID] else { return [] }
        var candidateAddresses: [String] = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            candidateAddresses.append(candidate)
        }
        // Every address the wallet has stored, in catalog order. Seventeen
        // `appendAddress(wallet.<chain>Address)` lines stood here and they were
        // seven short of the twenty-four slots: TON, Zcash, Bitcoin Gold,
        // Decred, Kaspa, Dash and Bittensor were missing, so a stored address on
        // any of them was not counted as the wallet's own.
        for chain in Chain.all { appendAddress(wallet.address(forChainNamed: chain.displayName)) }
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
        for address in await WalletServiceBridge.shared.ownedAddresses(walletID: walletID) {
            appendAddress(address)
        }
        let request = OwnedAddressAggregationRequest(candidateAddresses: candidateAddresses)
        return coreAggregateOwnedAddresses(request: request)
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
            guard let providedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines), !providedPassword.isEmpty else {
                throw SeedPhraseRevealError.passwordRequired
            }
            guard verifySeedPhrasePassword(providedPassword, for: wallet.id) else { throw SeedPhraseRevealError.invalidPassword }
        }
        guard let seedPhrase = storedSeedPhrase(for: wallet.id), !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SeedPhraseRevealError.unavailable
        }
        return seedPhrase
    }
    func availableSendCoins(for walletID: String) -> [Coin] { cachedAvailableSendCoinsByWalletID[walletID] ?? [] }
    func availableReceiveCoins(for walletID: String) -> [Coin] { cachedAvailableReceiveCoinsByWalletID[walletID] ?? [] }
    func availableReceiveChains(for walletID: String) -> [String] { cachedAvailableReceiveChainsByWalletID[walletID] ?? [] }
    func selectedReceiveCoin(for walletID: String) -> Coin? {
        let receiveCoins = availableReceiveCoins(for: walletID)
        let plan = receiveSelection(for: walletID, coins: receiveCoins)
        guard let selectedIndex = plan.selectedReceiveHoldingIndex.map(Int.init),
            receiveCoins.indices.contains(selectedIndex)
        else { return nil }
        return receiveCoins[selectedIndex]
    }
    func resolvedReceiveChainName(for walletID: String) -> String {
        receiveSelection(for: walletID).resolvedChainName
    }
    /// Which chain and holding the receive sheet should show. `receiveChainName`
    /// is the user's current pick and stays in Swift — it is a sheet selection,
    /// not something a restart should preserve.
    private func receiveSelection(for walletID: String, coins: [Coin]? = nil) -> ReceiveSelectionPlan {
        let receiveCoins = coins ?? availableReceiveCoins(for: walletID)
        return coreReceiveSelection(
            request: ReceiveSelectionRequest(
                receiveChainName: receiveChainName,
                availableReceiveChains: availableReceiveChains(for: walletID),
                availableReceiveHoldings: receiveCoins.enumerated().map { offset, coin in
                    ReceiveSelectionHoldingInput(
                        holdingIndex: UInt64(offset), chainName: coin.chainName,
                        hasContractAddress: coin.contractAddress != nil
                    )
                }
            )
        )
    }
    var sendEnabledWallets: [ImportedWallet] { cachedSendEnabledWallets }
    var receiveEnabledWallets: [ImportedWallet] { cachedReceiveEnabledWallets }
    var canBeginSend: Bool { !sendEnabledWallets.isEmpty }
    var canBeginReceive: Bool { !receiveEnabledWallets.isEmpty }
    var alertableCoins: [Coin] { portfolio }
    var sendAddressBookEntries: [AddressBookEntry] {
        guard let selectedSendCoin else { return [] }
        return addressBook.filter { $0.chainName == selectedSendCoin.chainName }
    }
    var hasPendingEthereumSendForSelectedWallet: Bool { selectedPendingEthereumSendTransaction() != nil }
    var ethereumReplacementNonceStateMessage: String? {
        guard selectedSendCoin?.chainName == "Ethereum" else { return nil }
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            return localizedStoreString(
                "No pending Ethereum send found for this wallet. Replacement and cancel are available only for pending transactions.")
        }
        var message = AppLocalization.format("Pending %@ transaction detected", pendingTransaction.symbol)
        if let nonce = pendingTransaction.ethereumNonce {
            message += AppLocalization.format("send.replacement.pendingNonceSuffix", nonce)
        } else {
            message += "."
        }
        if let transactionHash = pendingTransaction.transactionHash {
            let shortHash = transactionHash.count > 14 ? "\(transactionHash.prefix(10))...\(transactionHash.suffix(4))" : transactionHash
            message += AppLocalization.format("send.replacement.transactionSuffix", shortHash)
        }
        message += localizedStoreString(
            " Use Speed Up to resend with higher fees or Cancel to submit a 0-value self-transfer using the same nonce.")
        return message
    }
}
