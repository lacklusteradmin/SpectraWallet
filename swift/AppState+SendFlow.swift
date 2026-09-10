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
        pendingSelfSendConfirmation = nil
        clearHighRiskSendConfirmation()
    }
    private func resetSendComposerFields() {
        sendAmount = ""; sendAddress = ""; sendError = nil; sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil;
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEvmFees = false; customEvmMaxFeeGwei = ""; customEvmPriorityFeeGwei = ""
        sendAdvancedMode = false; sendUTXOMaxInputCount = 0; sendEnableRBF = true; sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange; evmManualNonceEnabled = false; evmManualNonce = ""
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
        if selectedSendCoin?.chain != .litecoin { sendLitecoinChangeStrategy = .derivedChange }
        lastSentTransaction = nil
        clearAllChainSendState()
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false
    }
    func cancelSend() { isShowingSendSheet = false; resetSendComposerFields() }
    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendWalletID).first(where: { $0.holdingKey == sendHoldingKey })
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
    func selectedWalletForSend() -> ImportedWallet? { wallet(for: sendWalletID) }
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
    /// The gas asset a replacement on this pending send's chain is paid and —
    /// when it is a cancel — sent in.
    private func replacementHolding(for pending: ReplaceableSend) -> Coin? {
        availableSendCoins(for: sendWalletID).first {
            $0.chainName == pending.chainName && $0.isNativeCoin
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
        guard let wallet = wallets.first(where: { $0.id.caseInsensitiveCompare(pending.walletId) == .orderedSame })
        else {
            let message = localizedStoreString("The wallet for this pending transaction is not available.")
            sendError = message
            return message
        }
        sendWalletID = wallet.id
        // The composer is moved to the chain the pending send is on, not to
        // Ethereum, and to that chain's gas asset — the one a replacement is
        // signed in.
        guard let holding = replacementHolding(for: pending) else {
            let message = AppLocalization.format(
                "This wallet has no %@ holding on %@ to replace that transaction with.",
                Chain(id: pending.chainId)?.gasTokenSymbol ?? "", pending.chainName)
            sendError = message
            return message
        }
        sendHoldingKey = holding.holdingKey
        syncSendAssetSelection()
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareReplacementContext(pending: pending, cancel: cancel)
        return sendError
    }
    func prepareReplacementContext(pending: ReplaceableSend, cancel: Bool) async {
        // A speed-up re-signs the same transfer, and only a native one can be
        // rebuilt from a record — the token's contract is not in it. This used
        // to compose a *native* transfer of the token's amount to the token's
        // recipient, so speeding up a 100 USDC send offered to send 100 ETH.
        // Cancelling needs none of that and stays available.
        guard cancel || pending.canSpeedUp else {
            sendError = AppLocalization.format(
                "Speed Up is unavailable for a pending %@ transfer. Cancel it to free the nonce, then send again.",
                pending.symbol)
            return
        }
        guard let wallet = wallets.first(where: { $0.id.caseInsensitiveCompare(pending.walletId) == .orderedSame }),
            let ownAddress = wallet.address(forChainNamed: pending.chainName)
        else {
            sendError = localizedStoreString("Select a wallet first."); return
        }
        isPreparingReplacementContext = true; defer { isPreparingReplacementContext = false }
        do {
            let nonce = try await WalletServiceBridge.shared.fetchEVMTxNonce(
                chainId: pending.chainId, txHash: pending.transactionHash)
            sendAddress = cancel ? ownAddress : pending.toAddress
            sendAmount = cancel ? "0" : String(format: "%.8f", pending.amount)
            evmManualNonceEnabled = true; evmManualNonce = String(nonce)
            // The fee to beat is the one this chain is charging now. The pair
            // of constants below was written for Ethereum and is under the
            // base fee on some chains and far over it on others, so the live
            // estimate is loaded first and bumped; the constants are what is
            // left when no estimate loads.
            useCustomEvmFees = false
            customEvmMaxFeeGwei = ""; customEvmPriorityFeeGwei = ""
            await refreshEvmSendPreview()
            let estimate = sendPreviewStore.evmSendPreview
            let bump = coreEvmReplacementFeeBump(
                existingMaxFeeGwei: estimate.map { String($0.maxFeePerGasGwei) },
                existingPriorityFeeGwei: estimate.map { String($0.maxPriorityFeePerGasGwei) },
                defaultMaxFeeGwei: 4.0, defaultPriorityFeeGwei: 2.0
            )
            useCustomEvmFees = true
            customEvmMaxFeeGwei = bump.maxFeeGwei
            customEvmPriorityFeeGwei = bump.priorityFeeGwei
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
    func mapEvmSendError(_ error: Error) -> String {
        let message = error.localizedDescription
        switch coreEthereumSendErrorCode(message: message) {
        case .nonceTooLow:
            return localizedStoreString("Nonce too low. A newer transaction from this wallet is already known. Refresh and retry.")
        case .replacementUnderpriced:
            return localizedStoreString("Replacement transaction underpriced. Increase fees and retry.")
        case .alreadyKnown:
            return localizedStoreString("This transaction is already in the mempool.")
        case .insufficientFunds:
            return localizedStoreString("Insufficient ETH to cover value plus network fee.")
        case .maxFeeBelowBaseFee:
            return localizedStoreString("Max fee is below current base fee. Increase Max Fee and retry.")
        case .intrinsicGasLow:
            return localizedStoreString("Gas limit is too low for this transaction.")
        case .unknown:
            return message
        }
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
        guard let tokenChain = TokenHostingChain.forChainName(coin.chainName) else { return nil }
        // A chain's native asset is never one of its tokens.
        if Chain(displayName: coin.chainName)?.gasTokenSymbol == coin.symbol { return nil }
        let chainTokens = enabledKnownTokens(for: tokenChain)
        guard let contractAddress = coin.contractAddress else {
            return chainTokens.first { $0.token.symbol == coin.symbol }
        }
        let normalized = normalizedKnownTokenIdentifier(
            for: tokenChain, contractAddress: contractAddress)
        return chainTokens.first {
            $0.token.symbol == coin.symbol
                && normalizedKnownTokenIdentifier(for: tokenChain, contractAddress: $0.token.contract)
                    == normalized
        }
    }

    /// The address is judged against the network the family is on.
    func isValidAddress(_ address: String, for chainName: String) -> Bool {
        isValidSendAddress(chainName: chainName, address: address)
    }
    func normalizedAddress(_ address: String, for chainName: String) -> String {
        normalizedSendAddress(chainName: chainName, address: address)
    }
    func isENSNameCandidate(_ value: String) -> Bool {
        isEnsNameCandidate(value: value)
    }
    func resolveEVMRecipientAddress(input: String, for chainName: String) async throws -> (address: String, usedENS: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EthereumWalletEngineError.invalidAddress }
        if AddressValidation.isValid(trimmed, kind: "evm") { return (normalizeEVMAddress(trimmed), false) }
        guard chainName == "Ethereum", isENSNameCandidate(trimmed) else { throw EthereumWalletEngineError.invalidAddress }
        let cacheKey = trimmed.lowercased()
        if let cached = cachedResolvedENSAddresses[cacheKey] { return (cached, true) }
        guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmed) else {
            throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name '\(trimmed)'.")
        }
        cachedResolvedENSAddresses[cacheKey] = resolved
        return (resolved, true)
    }
    /// Warnings about an EVM recipient, localized.
    ///
    /// Core makes the two contract-code probes itself and works out which
    /// token the holding is from the token list it owns. This used to make
    /// both network calls, swallow their errors, look the token up on this
    /// side, and hand all three answers back for core to judge.
    func evmRecipientPreflightReasons(holding: Coin, destinationAddress: String) async -> [String] {
        let warnings = await WalletServiceBridge.shared.evmRecipientPreflight(
            walletID: sendWalletID, holdingKey: holding.holdingKey,
            destinationAddress: destinationAddress)
        return warnings.compactMap { w -> String? in
            switch w.code {
            case "recipient_is_contract":
                return AppLocalization.format(
                    "Recipient is a smart contract on %@. Confirm it can receive %@ safely.", w.chainName ?? "", w.symbol ?? "")
            case "recipient_code_unknown":
                return AppLocalization.format(
                    "Could not verify recipient contract state on %@. Review destination carefully.", w.chainName ?? "")
            case "token_contract_missing":
                return AppLocalization.format(
                    "Token contract %@ appears missing on %@. This may be a wrong-network token selection.",
                    w.tokenSymbol ?? "", w.chainName ?? "")
            case "token_code_unknown":
                return AppLocalization.format(
                    "Could not verify %@ contract bytecode on %@.", w.tokenSymbol ?? "", w.chainName ?? "")
            default: return nil
            }
        }
    }
    /// Why this send looks risky, localized.
    ///
    /// The address book and every address this wallet has sent to on the chain
    /// used to be assembled here and passed in — both are core's own store, so
    /// "is this a first-time destination" was only as complete as this side's
    /// copy of the history. What crosses now is what the user did: the
    /// destination, what they typed, and whether an ENS name got them there.
    func evaluateHighRiskSendReasons(
        wallet: ImportedWallet, holding: Coin, amount: Double, destinationAddress: String,
        destinationInput: String, usedENSResolution: Bool = false
    ) async -> [String] {
        let warnings = await WalletServiceBridge.shared.highRiskSendReasons(
            walletID: wallet.id, holdingKey: holding.holdingKey, amount: amount,
            destinationAddress: destinationAddress, destinationInput: destinationInput,
            usedENSResolution: usedENSResolution)
        return warnings.compactMap { w -> String? in
            switch w.code {
            case "invalid_format": return AppLocalization.format("The destination address format does not match %@.", w.chain ?? "")
            case "new_address": return localizedStoreString("This is a new destination address with no prior history in this wallet.")
            case "ens_resolved":
                return AppLocalization.format(
                    "ENS name '%@' resolved to %@. Confirm this resolved address before sending.", w.name ?? "", w.address ?? "")
            case "large_send":
                let formatted = (Double(w.percent ?? 0) / 100.0).formatted(.percent.precision(.fractionLength(0)))
                return AppLocalization.format("This send is %@ of your %@ balance.", formatted, w.symbol ?? "")
            case "non_evm_on_evm":
                return AppLocalization.format("Destination appears to be a non-EVM address while sending on %@.", w.chain ?? "")
            case "ens_off_ethereum":
                return AppLocalization.format(
                    "ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", w.chain ?? "")
            case "eth_on_utxo":
                return AppLocalization.format("Destination appears to be an Ethereum-style address while sending on %@.", w.chain ?? "")
            case "non_tron": return localizedStoreString("Destination appears to be non-Tron format while sending on Tron.")
            case "non_solana": return localizedStoreString("Destination appears to be non-Solana format while sending on Solana.")
            case "non_xrp": return localizedStoreString("Destination appears to be non-XRP format while sending on XRP Ledger.")
            case "non_monero": return localizedStoreString("Destination appears to be non-Monero format while sending on Monero.")
            case "chain_mismatch": return localizedStoreString("Wallet-chain context mismatch detected for this send.")
            default: return nil
            }
        }
    }
    func clearHighRiskSendConfirmation() { pendingHighRiskSendReasons = []; isShowingHighRiskSendConfirmation = false }
    func confirmHighRiskSendAndSubmit() async {
        bypassHighRiskSendConfirmation = true; isShowingHighRiskSendConfirmation = false; await submitSend()
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
        Task { @MainActor [weak self] in
            await self?.sendAddressBookCommand(
                .addAddressBookEntry(
                    id: UUID().uuidString, name: name, chainName: chainName,
                    address: address, note: note))
        }
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
        Task { @MainActor [weak self] in
            await self?.sendAddressBookCommand(.renameAddressBookEntry(id: id, name: newName))
        }
    }
    func removeAddressBookEntry(id: String) {
        Task { @MainActor [weak self] in
            await self?.sendAddressBookCommand(.removeAddressBookEntry(id: id))
        }
    }

    /// Send an address-book command and mirror the result.
    ///
    /// A refusal arrives as an `addressBookRejected` event carrying the reason
    /// core decided on; surfacing it beats silently doing nothing.
    private func sendAddressBookCommand(_ command: StateCommand) async {
        let epoch = beginCoreStateRead()
        guard let transition = try? await WalletServiceBridge.shared.applyStateCommand(command)
        else { return }
        applyCoreState(transition.state, epoch: epoch)
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
    private func runUTXORescan(
        chainName: String, abbrev: String, preWork: (() async -> Void)? = nil,
        refreshHistory: @Sendable () async -> Void, refreshPending: @Sendable () async -> Void
    ) async {
        guard !self[rescanFor: chainName].isRunning else { return }
        self[rescanFor: chainName].isRunning = true
        defer { self[rescanFor: chainName].isRunning = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan started.")
        await preWork?()
        async let balanceTask: () = refreshBalances()
        async let historyTask: () = refreshHistory()
        async let pendingTask: () = refreshPending()
        _ = await (balanceTask, historyTask, pendingTask)
        self[rescanFor: chainName].lastRunAt = Date()
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan completed.")
    }
    /// Deep-rescan one UTXO chain: rediscover addresses, then refetch
    /// balances, history and pending status together.
    func runUTXORescan(chainName: String) async {
        guard (Chain(displayName: chainName)?.supportsDeepUTXODiscovery ?? false) else { return }
        let abbrev = Chain(displayName: chainName)?.gasTokenSymbol ?? chainName
        await runUTXORescan(
            chainName: chainName, abbrev: abbrev,
            preWork: {
                await self.refreshUTXOAddressDiscovery(chainName: chainName)
                await self.refreshUTXOReceiveReservationState(chainName: chainName)
            },
            refreshHistory: {
                switch chainName {
                case "Bitcoin":
                    await self.refreshBitcoinTransactions(limit: HistoryPaging.endpointBatchSize)
                case let name where Chain(displayName: name)?.supportsDeepUTXODiscovery == true:
                    await self.refreshMultiAddressUTXOTransactions(chainName: name)
                default:
                    await self.refreshNormalizedTransactions(chainName: chainName)
                }
            },
            refreshPending: { await self.refreshPendingTransactions(chainName: chainName) })
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
        let plan = await maintenancePlan()
        lastMaintenancePollSeconds = plan.pollSeconds
        if appIsActive { await runActiveScheduledMaintenance(plan: plan); return }
        guard plan.runBackgroundTick else { return }
        await WalletServiceBridge.shared.recordRefresh(kind: .backgroundTick)
        await performBackgroundMaintenanceTick(
            allowHeavyBackgroundWork: plan.allowHeavyBackgroundWork)
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
                Task { @MainActor in
                    if success {
                        self.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? "Authentication cancelled."
                        self.sendError = message; self.appLockError = message
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
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        // Three facts, all of them `Chain::pending_status_poll`: which chains
        // are polled this way, whether a chain keeps counting after
        // confirmation, and whether receives are tracked too. They were a
        // five-name list, a `== "Dogecoin"` and a blanket `kind == .send`, and
        // the last one disagreed with the registry — Litecoin is
        // `require_send_kind: false` because its explorer confirms receives on
        // its own cadence, and a received Litecoin transaction could not be
        // rechecked.
        guard transaction.supportsStatusRecheck else {
            return transaction.transactionHash == nil
                ? "This transaction has no hash to recheck."
                : "Status recheck is not available for this transaction."
        }
        guard let chain = Chain(displayName: transaction.chainName),
            case .utxo(let tracksFinality, _) = chain.pendingStatusPoll
        else { return "Status recheck is not available for this transaction." }
        try? await WalletServiceBridge.shared.resetStatusTracker(
            id: transactionID.uuidString, clearFinality: tracksFinality)
        // The switch this replaces had five arms and every one of them was
        // `refreshPendingTransactions(chainName: <the same name>)`.
        await refreshPendingTransactions(chainName: transaction.chainName)
        guard let updated = transactions.first(where: { $0.id == transactionID }) else { return "Transaction status refresh completed." }
        if updated.status != transaction.status { return "Status updated: \(updated.statusText)." }
        if updated.status == .pending { return "No confirmation yet. Spectra will keep retrying automatically." }
        if updated.status == .failed { return updated.failureReason ?? "Transaction remains failed." }
        return "Transaction is confirmed."
    }
    func rebroadcastSignedTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.kind == .send else { return "Rebroadcast is only supported for send transactions." }
        guard let payload = transaction.rebroadcastPayload, let format = transaction.rebroadcastPayloadFormat else {
            return "This transaction cannot be rebroadcast because signed payload data was not saved."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        do {
            let (transactionHash, verificationStatus) = try await rebroadcastSignedTransaction(
                transaction: transaction, payload: payload, format: format
            )
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                recordTransaction(transactions[index].withRebroadcastUpdate(status: .pending, transactionHash: transactionHash))
            }
            if transaction.chainName == "Dogecoin" { await refreshPendingTransactions(chainName: "Dogecoin") }
            switch verificationStatus {
            case .verified: return "Transaction rebroadcasted and observed on the network."
            case .deferred: return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message): return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            return error.localizedDescription
        }
    }
    func rebroadcastSignedTransaction(transaction: TransactionRecord, payload: String, format: String) async throws -> (
        transactionHash: String, verificationStatus: SendBroadcastVerificationStatus
    ) {
        let existing = transaction.transactionHash ?? ""
        if format == "icp.signed_hex" || format == "icp.rust_json" || format == "monero.rust_json" { return (existing, .deferred) }
        if format == "evm.raw_hex" || format == "evm.rust_json" {
            guard let chainId = Chain(displayName: transaction.chainName)?.id else {
                throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported EVM chain for rebroadcast."])
            }
            let txid = try await WalletServiceBridge.shared.broadcastRawExtract(
                chainId: chainId, payload: payload, resultField: "txid")
            return (txid.isEmpty ? existing : txid, .deferred)
        }
        let prepared = try coreRebroadcastPreparePayload(format: format, rawPayload: payload)
        let resultValue = try await WalletServiceBridge.shared.broadcastRawExtract(
            chainId: prepared.chainId, payload: prepared.broadcastPayload, resultField: prepared.resultField)
        return (resultValue.isEmpty ? existing : resultValue, .deferred)
    }
    func walletDerivationPath(for wallet: ImportedWallet, chain: Chain) -> String {
        derivationResolution(for: wallet, chain: chain).normalizedPath
    }
    func derivationResolution(for wallet: ImportedWallet, chain: Chain) -> SeedDerivationResolution {
        chain.resolve(path: wallet.seedDerivationPaths.path(for: chain))
    }
    /// The network this wallet is on for a family: its own if it has one,
    /// otherwise whatever the app is set to.
    func walletNetworkChainID(for wallet: ImportedWallet, family: String) -> NetworkChainID {
        if let own = wallet.networkChainId,
            coreResolveChainId(input: own) == own,
            (Chain(id: family)?.networkChoices ?? []).contains(where: { $0.chainId == own })
        {
            return own
        }
        return networkChainID(forFamily: family)
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
    func displayNetworkName(for chainName: String) -> String {
        let title = displayChainTitle(for: chainName)
        guard title != chainName else { return "Mainnet" }
        return String(title.dropFirst(chainName.count)).trimmingCharacters(in: .whitespaces)
    }
    func displayChainTitle(for wallet: ImportedWallet) -> String {
        guard let family = Chain(displayName: wallet.selectedChain)?.id, !family.isEmpty else {
            return wallet.selectedChain
        }
        let chainID = walletNetworkChainID(for: wallet, family: family)
        return Chain(id: chainID)?.displayName ?? chainID
    }
    func displayNetworkName(for wallet: ImportedWallet) -> String {
        let chain = wallet.selectedChain
        let title = displayChainTitle(for: wallet)
        guard title != chain else { return "Mainnet" }
        return String(title.dropFirst(chain.count)).trimmingCharacters(in: .whitespaces)
    }
    func displayNetworkName(for transaction: TransactionRecord) -> String {
        // The families whose selected network changes the name shown. Two were
        // spelled here; `hasNetworkChoice` is the registry column.
        if Chain(displayName: transaction.chainName)?.hasNetworkChoice == true, let walletID = transaction.walletID,
            let wallet = cachedWalletByID[walletID]
        {
            return displayNetworkName(for: wallet)
        }
        return displayNetworkName(for: transaction.chainName)
    }
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        // The families whose selected network changes the name shown. Two were
        // spelled here; `hasNetworkChoice` is the registry column.
        if Chain(displayName: transaction.chainName)?.hasNetworkChoice == true, let walletID = transaction.walletID,
            let wallet = cachedWalletByID[walletID]
        {
            return displayChainTitle(for: wallet)
        }
        return displayChainTitle(for: transaction.chainName)
    }
    func supportsDeepUTXODiscovery(chainName: String) -> Bool { (Chain(displayName: chainName)?.supportsDeepUTXODiscovery ?? false) }
    /// Judged against the network the family is on, which is a chain — so the
    /// registry supplies the kind. Five hand-written cases before, two of them
    /// passing a mode the validator ignored.
    /// Judge an address against the network the chain is actually on.
    ///
    /// `wallet` picks that wallet's network where it has one of its own;
    /// without it the family's global selection is used. A Dogecoin-only twin
    /// of this existed for the wallet-scoped case, which is a distinction
    /// every one of the twenty-nine chains with a network choice has.
    ///
    /// `requireDeepUTXODiscovery` is what the address-discovery callers need
    /// and the send callers do not: discovery walks a chain's addresses, so it
    /// only applies to chains that support the walk.
    func isValidAddressForPolicy(
        _ address: String, chainName: String,
        wallet: ImportedWallet? = nil, requireDeepUTXODiscovery: Bool = false
    ) -> Bool {
        guard !requireDeepUTXODiscovery || supportsDeepUTXODiscovery(chainName: chainName),
            let family = Chain(displayName: chainName)?.id, !family.isEmpty
        else { return false }
        let selected =
            wallet.map { walletNetworkChainID(for: $0, family: family) }
            ?? networkChainID(forFamily: family)
        let kind = Chain(id: selected)?.addressValidationKind ?? ""
        return !kind.isEmpty && AddressValidation.isValid(address, kind: kind)
    }
    func knownUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        guard let chain = Chain(displayName: chainName) else { return [] }
        return (try? await WalletServiceBridge.shared.knownUTXOAddresses(
            walletID: wallet.id, chainId: chain.id)) ?? []
    }

    /// Walk the wallet's derived addresses and record the used ones.
    ///
    /// The loop was here because it needed the seed phrase, and the phrase was
    /// only readable from Swift. Core reads the seed, the derivation path, the
    /// keypool bound, the balance and the history, so the loop is core's and
    /// the phrase no longer crosses for it.
    func discoverUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        guard let chain = Chain(displayName: chainName) else { return [] }
        return (try? await WalletServiceBridge.shared.discoverUTXOAddresses(
            walletID: wallet.id, chainId: chain.id)) ?? []
    }
    func refreshUTXOAddressDiscovery(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let discovered = await withTaskGroup(of: (String, [String]).self, returning: [String: [String]].self) { group in
            for wallet in utxoWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverUTXOAddresses(for: wallet, chainName: chainName)
                    return (wallet.id, addresses)
                }
            }
            var mapping: [String: [String]] = [:]
            for await (walletID, addresses) in group { mapping[walletID] = addresses }
            return mapping
        }
        discoveredUTXOAddressesByChain[chainName] = discovered
    }
    /// Move each wallet's reservation past a receive address that has been
    /// used.
    ///
    /// Reserve, derive, check, release, re-reserve — five steps that all read
    /// or write core's tables, so they run there. Doing them from here meant a
    /// window between releasing an index and taking the next in which nothing
    /// stopped the same address being handed out twice.
    func refreshUTXOReceiveReservationState(chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        try? await WalletServiceBridge.shared.advanceUsedUTXOReservations(chainId: chain.id)
    }
    func seedDerivationChain(for chainName: String) -> Chain? {
        CachedCoreHelpers.seedDerivationChainRaw(chainName: chainName).flatMap(Chain.init(displayName:))
    }
    func walletHasAddress(for wallet: ImportedWallet, chainName: String) -> Bool {
        resolvedAddress(for: wallet, chainName: chainName) != nil
    }
    /// Record an address this wallet owns. Core holds the table — the keypool
    /// baseline is derived from it, so a second copy here could go stale and
    /// reissue an address.
    func registerOwnedAddress(
        chainName: String, address: String?, walletID: String?, derivationPath: String?, index: Int?, branch: String?
    ) {
        guard let address, let walletID, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        Task {
            try? await WalletServiceBridge.shared.registerOwnedAddress(
                walletID: walletID, chainName: chainName, address: address,
                derivationPath: derivationPath, branch: branch,
                branchIndex: index.map(Int64.init))
        }
    }
    func ownedAddresses(for walletID: String, chainName: String) async -> [String] {
        await WalletServiceBridge.shared.ownedAddresses(walletID: walletID, chainName: chainName)
    }
    /// The wallet's keypool state for this chain, merged with the baseline.
    ///
    /// Core derives the baseline and refuses incomplete history reads.
    func keypoolState(for wallet: ImportedWallet, chainName: String) async throws -> ChainKeypoolState {
        ChainKeypoolState(
            keypool: try await WalletServiceBridge.shared.keypoolState(
                walletID: wallet.id, chainName: chainName))
    }
    /// Reserve the next receive index, or return the one already reserved.
    ///
    /// Read-modify-write happens inside core: reserving from two places at once
    /// must not hand the same address to two people.
    /// `minimumIndex` is the floor the chain requires: the deep-UTXO path never
    /// hands out index 0 as a receive address.
    func reserveReceiveIndex(for wallet: ImportedWallet, chainName: String, minimumIndex: Int = 0)
        async -> Int?
    {
        let reserved = try? await WalletServiceBridge.shared.reserveReceiveIndex(
            walletID: wallet.id, chainName: chainName, minimumIndex: Int64(minimumIndex))
        return reserved.map(Int.init)
    }
    func reserveChangeIndex(for wallet: ImportedWallet, chainName: String) async -> Int? {
        let reserved = try? await WalletServiceBridge.shared.reserveChangeIndex(
            walletID: wallet.id, chainName: chainName)
        return reserved.map(Int.init)
    }
    /// The path a non-UTXO chain's receive address came from.
    ///
    /// Deep-UTXO chains no longer reach here: core records the path alongside
    /// the address it derived, so there is nothing for a caller to compute.
    func reservedReceiveDerivationPath(for wallet: ImportedWallet, chainName: String, index: Int?) -> String? {
        guard let chain = seedDerivationChain(for: chainName) else { return nil }
        return walletDerivationPath(for: wallet, chain: chain)
    }
    /// The keypool as it currently stands, recording nothing.
    ///
    /// The `reserveIfMissing: false` path of `reservedReceiveAddress` still
    /// wrote — through `keypoolState` and `registerOwnedAddress`, both of which
    /// touch observed state. This is the variant a SwiftUI `body` can call.
    func reservedReceiveAddressForDisplay(for wallet: ImportedWallet, chainName: String) async
        -> String?
    {
        guard let chain = Chain(displayName: chainName), chain.supportsDeepUTXODiscovery else {
            return resolvedAddress(for: wallet, chainName: chainName)
        }
        do {
            let address = try await WalletServiceBridge.shared.utxoReceiveAddress(
                walletID: wallet.id, chainId: chain.id, reserve: false)
            return address ?? resolvedAddress(for: wallet, chainName: chainName)
        } catch { return nil }
    }
    func reservedReceiveAddress(for wallet: ImportedWallet, chainName: String, reserveIfMissing: Bool) async -> String? {
        // Core reserves, derives and records in one call. The floor of 1 —
        // deep-UTXO chains never hand out index 0 as a receive address — is
        // its rule now rather than an argument passed from here.
        if let chain = Chain(displayName: chainName), chain.supportsDeepUTXODiscovery {
            do {
                let address = try await WalletServiceBridge.shared.utxoReceiveAddress(
                    walletID: wallet.id, chainId: chain.id, reserve: reserveIfMissing)
                return address ?? resolvedAddress(for: wallet, chainName: chainName)
            } catch { return nil }
        }
        if reserveIfMissing, await reserveReceiveIndex(for: wallet, chainName: chainName) == nil { return nil }
        guard let address = resolvedAddress(for: wallet, chainName: chainName) else { return nil }
        guard let pool = try? await keypoolState(for: wallet, chainName: chainName) else { return nil }
        let reservedIndex = pool.reservedReceiveIndex
        registerOwnedAddress(
            chainName: chainName, address: address, walletID: wallet.id,
            derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), index: reservedIndex,
            branch: "external"
        )
        return address
    }
    func activateLiveReceiveAddress(_ address: String?, for wallet: ImportedWallet, chainName: String, derivationPath: String? = nil)
        async -> String
    {
        guard let address else { return "" }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let reservedIndex = await reserveReceiveIndex(for: wallet, chainName: chainName) else { return "" }
        registerOwnedAddress(
            chainName: chainName, address: trimmed, walletID: wallet.id,
            derivationPath: derivationPath ?? reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
            index: reservedIndex, branch: "external"
        )
        return trimmed
    }
    /// Tell core which receive addresses each wallet owns.
    ///
    /// This looped over `diagnosticsChains.map(\.title)` — "Bitcoin
    /// Diagnostics" and twenty-three others — so `resolvedAddress` missed on
    /// every one and the whole thing was a no-op.
    ///
    /// Fixing the name made it real work, and real work here is not free:
    /// reserving is a write. Two things bound it. Only chains that own their
    /// address slot are visited, because the EVM family shares one address and
    /// filing it under twenty-five chain names tells the keypool nothing it
    /// does not already know from Ethereum's row. And an address core already
    /// has is skipped, so the remaining cost falls on the first load after an
    /// import rather than on every launch.
    func syncChainOwnedAddressManagementState() async {
        for wallet in wallets {
            for chain in Chain.mainnets where chain.ownsItsAddressSlot {
                let chainName = chain.displayName
                guard let address = resolvedAddress(for: wallet, chainName: chainName) else { continue }
                let known = await WalletServiceBridge.shared.ownedAddresses(
                    walletID: wallet.id, chainName: chainName)
                guard !known.contains(address) else { continue }
                let reservedIndex = await reserveReceiveIndex(for: wallet, chainName: chainName)
                registerOwnedAddress(
                    chainName: chainName, address: address, walletID: wallet.id,
                    derivationPath: reservedReceiveDerivationPath(
                        for: wallet, chainName: chainName, index: reservedIndex),
                    index: reservedIndex, branch: "external"
                )
            }
        }
    }
    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let probeID = "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)"
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        func clearProbe() { sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false }
        guard !trimmedDestination.isEmpty else { clearProbe(); return }
        var destinationForProbe = trimmedDestination
        var ensResolutionInfo: String?
        if !isValidAddress(trimmedDestination, for: coin.chainName) {
            // ENS resolves on Ethereum and nowhere else — `resolveEVMRecipientAddress`
            // refuses any other chain — so the twelve-name EVM list that stood
            // here was routing eleven chains into a call that throws and lands
            // in the same `clearProbe()` the `else` does. Say the rule instead.
            if coin.chainName == "Ethereum", isENSNameCandidate(trimmedDestination) {
                do {
                    let resolved = try await resolveEVMRecipientAddress(input: trimmedDestination, for: coin.chainName)
                    destinationForProbe = resolved.address
                    ensResolutionInfo = resolved.usedENS ? "Resolved ENS \(trimmedDestination) to \(resolved.address)." : nil
                } catch { clearProbe(); return }
            } else {
                clearProbe(); return
            }
        }
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
        guard let chain = Chain(displayName: coin.chainName), !chain.id.isEmpty else { clearProbe(); return }
        // Native when the coin is what the chain charges gas in, the catalog's
        // entry when it is a token on it. Neither means there is no balance to
        // ask about, which is what the EVM arm already did for an unvouched
        // token — the other three arms probed the *chain's* asset instead and
        // reported its balance as though it were the one being sent.
        let token: TokenDescriptor?
        if coin.symbol == chain.gasTokenSymbol {
            token = nil
        } else if let entry = supportedToken(for: coin) {
            token = TokenDescriptor(
                contract: entry.token.contract, symbol: entry.token.symbol,
                decimals: UInt8(clamping: entry.token.decimals), name: nil)
        } else {
            clearProbe()
            return
        }
        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }
        let risk = try? await WalletServiceBridge.shared.sendDestinationRisk(
            chainId: chain.id, address: destinationForProbe, token: token)
        guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
        guard let risk else {
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = localizedStoreString("Unable to verify this address's activity. Try again later.")
            return
        }
        let messages = chainRiskProbeMessages(
            chainName: chain.displayName, symbol: coin.symbol,
            balanceIsZero: risk.balanceIsZero, hasHistory: risk.hasHistory)
        sendDestinationRiskWarning = messages.warning
        sendDestinationInfoMessage = [messages.info, ensResolutionInfo].compactMap { $0 }.joined(separator: " ")
        lastSendDestinationProbeKey = addressProbeKey
        lastSendDestinationProbeWarning = messages.warning
        lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
    }
    func userFacingTronSendError(_ error: Error, symbol: String) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("timed out") {
            return localizedStoreString("Tron network request timed out. Please try again.")
        }
        if lower.contains("not connected") || lower.contains("offline") {
            return localizedStoreString("No network connection. Check your internet and retry.")
        }
        return message
    }
    func recordTronSendDiagnosticError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tronLastSendErrorDetails = trimmed
        tronLastSendErrorAt = Date()
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
