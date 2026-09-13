import Foundation
import SwiftUI
import LocalAuthentication
import os
#if canImport(Network)
    import Network
#endif
@MainActor
extension AppState {
    private func clearAllChainSendState() {
        sendPreviewStore.resetAll()
        sendingChains = []
        preparingChains = []
        clearHighRiskSendConfirmation()
    }
    private func resetSendComposerFields() {
        sendAmount = ""; sendAddress = ""; sendError = nil; sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil;
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEvmFees = false; customEvmMaxFeeGwei = ""; customEvmPriorityFeeGwei = ""
        evmManualNonceEnabled = false; evmManualNonce = ""
        lastSentTransaction = nil
        clearAllChainSendState()
    }
    func beginSend() {
        guard let firstWallet = sendEnabledWallets.first else { return }
        sendWalletID = firstWallet.id
        sendHoldingKey = availableSendCoins(for: sendWalletID).first?.holdingKey ?? ""
        resetSendComposerFields()
        syncSendAssetSelection()
        isShowingSendSheet = true
    }
    func syncSendAssetSelection() {
        let availableHoldingKeys = availableSendCoins(for: sendWalletID).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendHoldingKey) { sendHoldingKey = availableHoldingKeys.first ?? "" }
        // EIP-1559 fees and a manual nonce belong to the EVM family, which is
        // a registry fact, not to the chain named "Ethereum". Clearing them on
        // a move to Arbitrum — while the composer still offered both toggles
        // there — is half of why they were silently dropped on 22 chains.
        if selectedSendCoin?.isEVMChain != true {
            useCustomEvmFees = false; customEvmMaxFeeGwei = ""; customEvmPriorityFeeGwei = "";
            evmManualNonceEnabled = false; evmManualNonce = ""
        }
        lastSentTransaction = nil
        clearAllChainSendState()
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false
    }
    func cancelSend() { isShowingSendSheet = false; resetSendComposerFields() }
    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendWalletID).first(where: { $0.holdingKey == sendHoldingKey })
    }
    var sendAmountDecimals: UInt32? {
        guard let coin = selectedSendCoin else { return nil }
        if coin.isNativeCoin { return Chain(displayName: coin.chainName)?.nativeDecimals }
        return supportedToken(for: coin)?.token.decimals
    }
    var sendAmountIsValid: Bool {
        guard let decimals = sendAmountDecimals else { return false }
        return parseAmountInput(text: sendAmount, maxDecimals: decimals) != nil
    }
    // A provisional quote can load before the user types; it never changes the
    // amount field and is replaced by a quote for the entered amount.
    var sendPreviewAmountInput: String {
        guard sendAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let coin = selectedSendCoin, let decimals = sendAmountDecimals else { return sendAmount }
        return sendAmountShortcut(maximum: coin.amount, decimals: decimals, percentage: 10) ?? "0"
    }
    func sendShortcutAmount(percentage: UInt32) -> String? {
        guard let coin = selectedSendCoin, preparingChains.isEmpty else { return nil }
        return quotedSendAmount(
            preview: sendPreviewStore.taggedPreview(forChainNamed: coin.chainName),
            chainName: coin.chainName, isNative: coin.isNativeCoin,
            tokenDecimals: supportedToken(for: coin)?.token.decimals, percentage: percentage)
    }

    func sendPreviewDetails(for coin: Coin) -> SendPreviewDetails? {
        guard
            let c = computeSendPreviewDetails(
                preview: sendPreviewStore.taggedPreview(forChainNamed: coin.chainName),
                coinAmount: coin.amount)
        else { return nil }
        return SendPreviewDetails(
            spendableBalance: c.spendableBalance, feeRateDescription: c.feeRateDescription,
            estimatedTransactionBytes: c.estimatedTransactionBytes.map(Int.init), selectedInputCount: c.selectedInputCount.map(Int.init),
            usesChangeOutput: c.usesChangeOutput, maxSendable: c.maxSendable)
    }
    private var parsedCustomEvmFees: Result<EvmCustomFeeConfiguration, Error>? {
        // No chain test: the toggle is cleared when the selection leaves the
        // EVM family, and only the EVM preview and submit paths read this. The
        // test that was here named the chain "Ethereum", so fees typed on the
        // other 22 EVM chains were parsed, shown as applied, and dropped.
        guard useCustomEvmFees else { return nil }
        return Result {
            try parseEvmCustomFees(
                maxFeeGweiRaw: customEvmMaxFeeGwei,
                priorityFeeGweiRaw: customEvmPriorityFeeGwei)
        }
    }
    var customEvmFeeValidationError: String? {
        guard case .failure(let error)? = parsedCustomEvmFees else { return nil }
        switch error {
        case EvmCustomFeeError.InvalidMaxFee: return localizedStoreString("Enter a valid Max Fee in gwei.")
        case EvmCustomFeeError.InvalidPriorityFee: return localizedStoreString("Enter a valid Priority Fee in gwei.")
        case EvmCustomFeeError.MaxBelowPriority: return localizedStoreString("Max Fee must be greater than or equal to Priority Fee.")
        default: return error.localizedDescription
        }
    }
    func customEvmFeeConfiguration() -> EvmCustomFeeConfiguration? {
        guard case .success(let fees)? = parsedCustomEvmFees else { return nil }
        return fees
    }
    var evmNonceValidationError: String? {
        do {
            _ = try explicitEvmNonce()
            return nil
        } catch EvmNonceError.Empty {
            return localizedStoreString("Enter a nonce value for manual nonce mode.")
        } catch EvmNonceError.InvalidInteger {
            return localizedStoreString("Nonce must be a non-negative integer.")
        } catch EvmNonceError.TooLarge {
            return localizedStoreString("Nonce value is too large.")
        } catch {
            return error.localizedDescription
        }
    }
    func explicitEvmNonce() throws -> Int? {
        guard evmManualNonceEnabled else { return nil }
        return Int(try parseEvmNonce(raw: evmManualNonce))
    }
    func selectedWalletForSend() -> WalletView? { wallet(for: sendWalletID) }
    /// The pending send the composer can replace as it stands: core's rule,
    /// scoped to the wallet and chain the composer is on.
    ///
    /// The rule — an EVM chain, a send, still pending, carrying a hash — is
    /// `replaceable_sends`, derived where the records are. Swift asked it of
    /// its own projection and asked it only of the chain *named* "Ethereum",
    /// so a pending Arbitrum or Base send offered neither speed-up nor cancel.
    /// What is left here is the lookup. The chain has to match: a replacement
    /// is the pending send's nonce re-signed *on its own chain*, and the
    /// composer signs for whichever chain it is showing.
    var replaceableSendForSelectedWallet: ReplaceableSend? {
        guard let selectedSendCoin else { return nil }
        return replaceableSends.first {
            $0.walletId.caseInsensitiveCompare(sendWalletID) == .orderedSame
                && $0.chainName == selectedSendCoin.chainName
        }
    }
    func replaceableSend(forTransaction transactionID: UUID) -> ReplaceableSend? {
        replaceableSends.first {
            $0.transactionId.caseInsensitiveCompare(transactionID.uuidString) == .orderedSame
        }
    }
    func prepareReplacementContext(cancel: Bool) async {
        guard let pending = replaceableSendForSelectedWallet else {
            sendError = localizedStoreString("No pending transaction found for this wallet.")
            return
        }
        await prepareReplacementContext(pending: pending, cancel: cancel)
    }
    func openReplacementComposer(for transactionID: UUID, cancel: Bool) async -> String? {
        guard let pending = replaceableSend(forTransaction: transactionID) else {
            let message = localizedStoreString(
                "This transaction is no longer pending, so replacement and cancel are unavailable.")
            sendError = message
            return message
        }
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareReplacementContext(pending: pending, cancel: cancel)
        return sendError
    }
    func prepareReplacementContext(pending: ReplaceableSend, cancel: Bool) async {
        isPreparingReplacementContext = true; defer { isPreparingReplacementContext = false }
        do {
            let draft = try await WalletServiceBridge.shared.replacementDraft(
                transactionID: pending.transactionId, cancel: cancel)
            sendWalletID = draft.walletId
            sendHoldingKey = draft.holdingKey
            sendAddress = draft.destination
            sendAmount = draft.amount
            evmManualNonceEnabled = true
            evmManualNonce = String(draft.nonce)
            useCustomEvmFees = true
            customEvmMaxFeeGwei = draft.maxFeeGwei
            customEvmPriorityFeeGwei = draft.priorityFeeGwei
            sendError = localizedStoreString(
                cancel ? "Cancellation context loaded. Review fees and tap Send." : "Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            sendError = AppLocalization.format("Unable to prepare replacement context: %@", error.localizedDescription)
        }
    }
    func prepareSpeedUpContext() async { await prepareReplacementContext(cancel: false) }
    func prepareCancelContext() async { await prepareReplacementContext(cancel: true) }
    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    func isEVMChain(_ chainName: String) -> Bool { (Chain(displayName: chainName)?.isEVM ?? false) }
    /// The custom RPC this chain is pointed at, if it is set and valid.
    func configuredEVMRPCEndpointURL(for chainName: String) -> URL? {
        guard rpcEndpointValidationError(forChain: chainName) == nil else { return nil }
        let trimmed = rpcEndpoint(forChain: chainName)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
    /// The known-token entry for a holding, on any chain that hosts tokens.
    ///
    /// The contract normaliser is core's rather than `normalizeEVMAddress`, so
    /// a TON jetton's case-significant address is not lowercased into a
    /// non-match.
    func supportedToken(for coin: Coin) -> TokenPreferenceEntry? {
        guard let entry = cachedTokenPreferenceByDeploymentID[coin.holdingKey], entry.isEnabled else { return nil }
        return entry
    }

    /// The address is judged against the network the family is on.
    func isValidAddress(_ address: String, for chainName: String) -> Bool {
        isValidSendAddress(chainName: chainName, address: address)
    }
    func normalizedAddress(_ address: String, for chainName: String) -> String {
        normalizedSendAddress(chainName: chainName, address: address)
    }
    /// The address this send is going to, from whatever is in the field.
    ///
    /// Core owns resolution; the optional address binds the visible review.
    func resolveSendDestination(input: String, for chainName: String, expectedAddress: String? = nil) async throws -> SendDestinationResolution {
        guard let chainId = Chain(displayName: chainName)?.id else {
            throw EthereumWalletEngineError.invalidAddress
        }
        return try await WalletServiceBridge.shared.resolveSendDestination(chainId: chainId, input: input, expectedAddress: expectedAddress)
    }
    func clearHighRiskSendConfirmation() { pendingSendReview = nil; pendingHighRiskSendReasons = []; isShowingHighRiskSendConfirmation = false }
    func confirmHighRiskSendAndSubmit() async {
        isShowingHighRiskSendConfirmation = false
        guard let review = pendingSendReview else { return }
        pendingSendReview = nil
        await submitReviewedSend(review)
    }

    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        let isValid = !isEmpty && isValidAddress(trimmed, for: chainName)
        if !isEmpty, isValid { return AppLocalization.format("Valid %@ address.", chainName) }

        // The sentence a chain has of its own, looked up by id. These are
        // content, so they live in the locale files keyed by chain id; a chain
        // with none falls back to a template built from the catalog's
        // `address_prefix_hint`.
        guard let chain = Chain(displayName: chainName) else {
            return AppLocalization.format("Enter a valid %@ address.", chainName)
        }
        let key = "addressHint.\(chain.id).\(isEmpty ? "empty" : "invalid")"
        let localized = AppLocalization.string(key)
        if localized != key { return localized }

        let hint = chain.addressPrefixHint
        guard !hint.isEmpty else {
            return isEmpty
                ? localizedStoreString("Enter an address for the selected chain.")
                : AppLocalization.format("Enter a valid %@ address.", chainName)
        }
        return isEmpty
            ? AppLocalization.format("%@ addresses look like %@", chainName, hint)
            : AppLocalization.format("Enter a valid %@ address — they look like %@", chainName, hint)
    }
    func isDuplicateAddressBookAddress(_ address: String, chainName: String, excluding entryID: String? = nil) -> Bool {
        let normalized = normalizedAddress(address, for: chainName)
        guard !normalized.isEmpty else { return false }
        return addressBook.contains {
            $0.id != entryID && $0.chainName == chainName && $0.address.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }
    func canSaveAddressBookEntry(name: String, address: String, chainName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isValidAddress(address, for: chainName)
            && !isDuplicateAddressBookAddress(address, chainName: chainName)
    }
    /// Save a recipient. Core trims, normalizes the address, validates it and
    /// rejects duplicates; the UI does not pre-check beyond disabling the
    /// button via `canSaveAddressBookEntry`.
    func addAddressBookEntry(name: String, address: String, chainName: String, note: String = "") {
        enqueueAddressBookCommand(.addAddressBookEntry(
            id: UUID().uuidString, name: name, chainName: chainName,
            address: address, note: note))
    }
    func canSaveLastSentRecipientToAddressBook() -> Bool {
        guard let tx = lastSentTransaction, tx.kind == .send else { return false }
        return canSaveAddressBookEntry(name: "\(tx.symbol) Recipient", address: tx.address, chainName: tx.chainName)
    }
    func saveLastSentRecipientToAddressBook() {
        guard let tx = lastSentTransaction, tx.kind == .send else { return }
        addAddressBookEntry(name: "\(tx.symbol) Recipient", address: tx.address, chainName: tx.chainName, note: "Saved from recent send")
    }
    func renameAddressBookEntry(id: String, to newName: String) {
        enqueueAddressBookCommand(.renameAddressBookEntry(id: id, name: newName))
    }
    func removeAddressBookEntry(id: String) {
        enqueueAddressBookCommand(.removeAddressBookEntry(id: id))
    }

    /// Preserve UI intent order across actor reentrancy. Core still owns every
    /// mutation; this task chain only orders the shell's forwarding and adoption.
    private func enqueueAddressBookCommand(_ command: StateCommand) {
        let previous = addressBookCommandTask
        addressBookCommandTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.sendAddressBookCommand(command)
        }
    }

    func awaitPendingAddressBookCommands() async {
        await addressBookCommandTask?.value
    }

    /// Send an address-book command and mirror the result.
    ///
    /// A refusal arrives as an `addressBookRejected` event carrying the reason
    /// core decided on; surfacing it beats silently doing nothing.
    private func sendAddressBookCommand(_ command: StateCommand) async {
        guard let transition = try? await WalletServiceBridge.shared.applyStateCommand(command)
        else { return }
        // A read begun while the write was pending may hold the old contacts.
        // Invalidate it when the committed command returns, not when it starts.
        applyCoreState(transition.state, epoch: beginCoreStateRead())
        if let reason = transition.events.first(where: { $0.kind == "addressBookRejected" })?
            .subjectId
        {
            addressBookError = addressBookRejectionMessage(reason)
        } else {
            addressBookError = nil
        }
    }

    private func addressBookRejectionMessage(_ reason: String) -> String {
        switch reason {
        case "emptyName": return localizedStoreString("Enter a name for this contact.")
        case "invalidAddress": return localizedStoreString("That address is not valid for this chain.")
        case "duplicateAddress": return localizedStoreString("That address is already saved.")
        default: return localizedStoreString("This contact could not be saved.")
        }
    }
    /// Run a chain's synchronous self-test suite and record the outcome.
    /// One chain's self-tests: the offline suite core keeps for every chain in
    /// the catalog, plus — on an EVM chain — a probe of the endpoint it is
    /// actually pointed at.
    ///
    /// `runEthereumSelfTests` stood beside this: the same bookkeeping wired to
    /// one chain, with three extra probes. Two of them are gone. The
    /// JSON-shape check tested core's own document builder, which core tests
    /// where it is built; the portfolio fetch was the balance refresh with a
    /// different error message, and it named Ethereum in four more places. The
    /// third says something the offline suite cannot — whether the node this
    /// chain is pointed at is that chain's node — so it runs for the whole EVM
    /// family rather than for the one chain that had a button.
    func runSelfTests(for chainName: String) async {
        guard !selfTests(for: chainName).isRunning else { return }
        selfTests[chainName, default: .init()].isRunning = true
        defer { selfTests[chainName, default: .init()].isRunning = false }
        var results = ChainSelfTests.run(chainName)
        if let chain = Chain(displayName: chainName), chain.isEVM,
            let rpc = configuredEVMRPCEndpointURL(for: chainName)?.absoluteString
                ?? AppEndpointDirectory.evmRPCEndpoints(for: chainName).first
        {
            results += await selfTestsRunEvmRpc(chainId: chain.id, rpcUrl: rpc, rpcLabel: rpc)
        }
        selfTests[chainName] = .init(results: results, isRunning: true, lastRunAt: Date())

        let failedCount = results.filter { !$0.passed }.count
        let abbrev = Chain(displayName: chainName)?.gasTokenSymbol ?? chainName
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: chainName,
            message: failedCount == 0
                ? "\(abbrev) self-tests passed (\(results.count) checks)."
                : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func operationalEvents(for chainName: String) async -> [ChainOperationalEvent] {
        await WalletServiceBridge.shared.operationalEvents(chainName: chainName)
    }
    func feePriorityOption(for chainName: String) -> ChainFeePriorityOption {
        feePriorityByChain[chainName].flatMap(ChainFeePriorityOption.init(rawValue:)) ?? .normal
    }
    func setFeePriorityOption(_ option: ChainFeePriorityOption, for chainName: String) {
        setFeePriority(option.rawValue, forChain: chainName)
    }
    func runUTXORescan(chainName: String) async {
        guard let chain = Chain(displayName: chainName), !self[rescanFor: chainName].isRunning else { return }
        self[rescanFor: chainName].isRunning = true
        defer { self[rescanFor: chainName].isRunning = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan started.")
        if await performCoreRefresh(.deepRescan(chainId: chain.id)) {
            self[rescanFor: chainName].lastRunAt = Date()
            appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan completed.")
        } else {
            appendChainOperationalEvent(.warning, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan failed or completed partially. See refresh errors.")
        }
    }

    func startNetworkPathMonitorIfNeeded() {
        #if canImport(Network)
            networkPathMonitor.pathUpdateHandler = { [weak self] path in
                let reachable = path.status == .satisfied; let constrained = path.isConstrained; let expensive = path.isExpensive
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isNetworkReachable = reachable; self.isConstrainedNetwork = constrained; self.isExpensiveNetwork = expensive
                }
            }
            networkPathMonitor.start(queue: networkPathMonitorQueue)
        #endif
    }
    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, preferences.useFaceID, preferences.useAutoLock { isAppLocked = true; appLockError = nil }
        if !isActive {
            maintenanceTask?.cancel(); maintenanceTask = nil
            // Stop the Rust balance-refresh engine so it isn't firing
            // network requests while the app is in the background.
            Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
            return
        }
        startMaintenanceLoopIfNeeded()
        // Resume balance refresh with the current frequency preference.
        Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
    }
    func unlockApp() async {
        guard preferences.useFaceID else { isAppLocked = false; appLockError = nil; return }
        if await authenticateForSensitiveAction(reason: "Authenticate to unlock Spectra") { isAppLocked = false; appLockError = nil }
    }
    func startMaintenanceLoopIfNeeded() {
        guard maintenanceTask == nil else { return }
        // With no wallets there's nothing to maintain — no pending tx to
        // poll, no price work, no chain history to sync. Don't even spin
        // the loop until something's worth checking.
        // `applyWalletCollectionSideEffects` re-invokes this once a wallet
        // exists. The loop also self-exits below when wallets drop to 0.
        guard !wallets.isEmpty else { return }
        maintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Self-exit when the user deletes all wallets. Lets the
                // loop terminate naturally instead of sleeping forever
                // doing nothing — matches the no-wallet startup gate.
                if self.wallets.isEmpty {
                    self.maintenanceTask = nil
                    break
                }
                await self.runScheduledMaintenanceOnce()
                // The cadence comes back with the plan: core knows whether
                // anything is pending and what the sync profile allows.
                try? await Task.sleep(
                    nanoseconds: self.lastMaintenancePollSeconds * 1_000_000_000)
            }
        }
    }
    /// One tick. Core decides what it is, from its own clock and this device's
    /// conditions; four questions and a `Date?` on this side became one.
    func runScheduledMaintenanceOnce() async {
        await performCoreRefresh(.scheduled)
    }

    func authenticateForSensitiveAction(reason: String, allowWhenAuthenticationUnavailable: Bool = false) async -> Bool {
        guard preferences.useFaceID, preferences.requireBiometricForSendActions else { return true }
        let context = LAContext(); var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            if allowWhenAuthenticationUnavailable { return true }
            let message = "Device authentication unavailable: \(authError?.localizedDescription ?? "unknown error")"
            sendError = message; appLockError = message
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                // `resume` sits outside the optional chain on purpose: the
                // continuation must be resumed exactly once even if the store
                // is gone by the time the prompt returns, and a `guard let
                // self else { return }` here would leak it instead.
                Task { @MainActor [weak self] in
                    if success {
                        self?.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? "Authentication cancelled."
                        self?.sendError = message
                        self?.appLockError = message
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
    func authenticateForSeedPhraseReveal(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    func retryUTXOTransactionStatus(for transactionID: UUID) async -> String {
        do {
            let change = try await WalletServiceBridge.shared.recheckTransactionStatus(id: transactionID.uuidString)
            await applyPendingStatusChanges([change])
            if change.statusChanged, let status = TransactionStatus(rawValue: change.newStatus) {
                return "Status updated: \(status.localizedTitle)."
            }
            if change.newStatus == "pending" { return "No confirmation yet. Spectra will keep retrying automatically." }
            return "Transaction is confirmed."
        } catch {
            let message = String(describing: error)
            appendOperationalLog(.error, category: "Pending Transactions", message: message)
            return message
        }
    }

    func rebroadcastSignedTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.kind == .send else { return "Rebroadcast is only supported for send transactions." }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        do {
            let transactionHash = try await WalletServiceBridge.shared.rebroadcastTransaction(id: transactionID.uuidString)
            await refreshTransactionProjection()
            return "Transaction rebroadcasted: \(transactionHash). Network confirmation is pending."
        } catch {
            return error.localizedDescription
        }
    }
    func walletDerivationPath(for wallet: WalletView, chain: Chain) -> String {
        derivationResolution(for: wallet, chain: chain).normalizedPath
    }
    func derivationResolution(for wallet: WalletView, chain: Chain) -> SeedDerivationResolution {
        chain.resolve(path: wallet.seedDerivationPaths.path(for: chain))
    }
    /// The network this wallet is on for a family: its own if it has one,
    /// otherwise whatever the app is set to.
    func walletNetworkChainID(for wallet: WalletView, family: String) -> NetworkChainID {
        wallet.networkChainId ?? ""
    }

    /// The derivation chain for a network, by id.
    func seedDerivationChain(forChainID chainID: String) -> Chain? {
        Chain(id: chainID)
    }
    /// The title of the network a chain family is on — "Bitcoin",
    /// "Bitcoin Testnet4". The registry names chains, so this is a lookup
    /// rather than a family switch plus string surgery on a mode name.
    func displayChainTitle(for chainName: String) -> String {
        guard let family = Chain(displayName: chainName)?.id, !family.isEmpty else {
            return chainName
        }
        let chainID = networkChainID(forFamily: family)
        return Chain(id: chainID)?.displayName ?? chainID
    }
    /// The part after the chain — "Testnet4" — for screens that show it alone.
    func displayChainTitle(for wallet: WalletView) -> String {
        guard let family = Chain(displayName: wallet.selectedChain)?.id, !family.isEmpty else {
            return wallet.selectedChain
        }
        let chainID = walletNetworkChainID(for: wallet, family: family)
        return Chain(id: chainID)?.displayName ?? chainID
    }
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        transaction.chainName
    }
    func supportsDeepUTXODiscovery(chainName: String) -> Bool { (Chain(displayName: chainName)?.supportsDeepUTXODiscovery ?? false) }
    /// `nil` when the lookup failed, which is a different answer from an
    /// empty list. Collapsing the two let a transient failure read as "this
    /// wallet owns no addresses" — and the self-send guard, which asks exactly
    /// that question, then waved the send through.
    func knownUTXOAddresses(for wallet: WalletView, chainName: String) async -> [String]? {
        guard let chain = Chain(displayName: chainName) else { return [] }
        do {
            return try await WalletServiceBridge.shared.knownUTXOAddresses(walletID: wallet.id, chainId: chain.id)
        } catch {
            appendOperationalLog(
                .error, category: "Owned Addresses",
                message: "Known \(chainName) addresses could not be read: \(String(describing: error))",
                chainName: chainName, walletID: wallet.id)
            return nil
        }
    }

    func seedDerivationChain(for chainName: String) -> Chain? {
        CachedCoreHelpers.seedDerivationChainRaw(chainName: chainName).flatMap(Chain.init(displayName:))
    }
    func walletHasAddress(for wallet: WalletView, chainName: String) -> Bool {
        resolvedAddress(for: wallet, chainName: chainName) != nil
    }
    /// The wallet's keypool state for this chain, merged with the baseline.
    ///
    /// Core derives the baseline and refuses incomplete history reads.
    func keypoolState(for wallet: WalletView, chainName: String) async throws -> ChainKeypoolState {
        ChainKeypoolState(
            keypool: try await WalletServiceBridge.shared.keypoolState(
                walletID: wallet.id, chainName: chainName))
    }
    /// Reserve the next receive index, or return the one already reserved.
    ///
    func reservedReceiveDerivationPath(for wallet: WalletView, chainName: String, index: Int?) -> String? {
        guard let chain = seedDerivationChain(for: chainName) else { return nil }
        return walletDerivationPath(for: wallet, chain: chain)
    }
    func reservedReceiveAddressForDisplay(for wallet: WalletView, chainName: String) async -> String? {
        guard let chain = Chain(displayName: chainName) else { return nil }
        return try? await WalletServiceBridge.shared.receiveAddress(
            walletID: wallet.id, chainId: chain.id, reserve: false)
    }
    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let probeID = "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)"
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        func clearProbe() { sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false }
        guard !trimmedDestination.isEmpty else { clearProbe(); return }
        // Anything the composer cannot turn into an address — a half-typed
        // one, a name on a chain that registers none — is core refusing, and
        // there is nothing to probe until it stops.
        guard let resolved = try? await resolveSendDestination(input: trimmedDestination, for: coin.chainName) else {
            clearProbe()
            return
        }
        let destinationForProbe = resolved.address
        let ensResolutionInfo: String? =
            resolved.usedEns ? "Resolved ENS \(trimmedDestination) to \(destinationForProbe)." : nil
        let addressProbeKey = "\(coin.chainName)|\(coin.symbol)|\(destinationForProbe.lowercased())"
        if lastSendDestinationProbeKey == addressProbeKey {
            sendDestinationRiskWarning = lastSendDestinationProbeWarning
            if let ensResolutionInfo {
                sendDestinationInfoMessage = [lastSendDestinationProbeInfoMessage, ensResolutionInfo].compactMap { $0 }.joined(
                    separator: " ")
            } else {
                sendDestinationInfoMessage = lastSendDestinationProbeInfoMessage
            }
            isCheckingSendDestinationBalance = false
            return
        }
        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }
        // Native or token, which contract the token is, and what to do when it
        // is one nothing vouches for are all catalog questions — core reads its
        // own token list rather than being handed one back. An asset it cannot
        // identify is an error here, where the composer used to clear the probe
        // and show nothing at all, which reads as "checked, and fine".
        let risk = try? await WalletServiceBridge.shared.sendDestinationRisk(
            walletID: sendWalletID, holdingKey: coin.holdingKey, destination: destinationForProbe)
        guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
        guard let risk else {
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = localizedStoreString("Unable to verify this address's activity. Try again later.")
            return
        }
        let messages = chainRiskProbeMessages(
            chainName: coin.chainName, symbol: coin.symbol,
            balanceIsZero: risk.balanceIsZero, hasHistory: risk.hasHistory)
        sendDestinationRiskWarning = messages.warning
        sendDestinationInfoMessage = [messages.info, ensResolutionInfo].compactMap { $0 }.joined(separator: " ")
        lastSendDestinationProbeKey = addressProbeKey
        lastSendDestinationProbeWarning = messages.warning
        lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
    }
    /// The one sentence pair a destination verdict turns into.
    ///
    /// Four chain arms used to word this themselves and produced three
    /// different templates, two of them interpolated in Swift and so absent
    /// from the locale files — a Tron or EVM token send showed English in a
    /// Chinese app. Both templates name the asset now, which the two
    /// interpolated ones did and the localized one did not.
    func chainRiskProbeMessages(chainName: String, symbol: String, balanceIsZero: Bool, hasHistory: Bool) -> (
        warning: String?, info: String?
    ) {
        let warning: String? =
            (balanceIsZero && !hasHistory)
            ? AppLocalization.format(
                "Warning: this %@ address has zero %@ balance and no transaction history. Double-check recipient details.",
                chainName, symbol)
            : nil
        let info: String? =
            (balanceIsZero && hasHistory)
            ? AppLocalization.format(
                "Note: this %@ address has transaction history but currently zero %@ balance.", chainName, symbol)
            : nil
        return (warning, info)
    }
}
