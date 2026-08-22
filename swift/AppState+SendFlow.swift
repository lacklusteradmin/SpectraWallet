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
        useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false; sendUTXOMaxInputCount = 0; sendEnableRBF = true; sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange; ethereumManualNonceEnabled = false; ethereumManualNonce = ""
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
        if selectedSendCoin?.chainName != "Ethereum" {
            useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = "";
            ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        }
        if selectedSendCoin?.chainName != "Litecoin" { sendLitecoinChangeStrategy = .derivedChange }
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
    var customEthereumFeeValidationError: String? {
        let code = coreEthereumCustomFeeValidation(
            useCustomFees: useCustomEthereumFees,
            isEthereumChain: selectedSendCoin?.chainName == "Ethereum",
            maxFeeGweiRaw: customEthereumMaxFeeGwei,
            priorityFeeGweiRaw: customEthereumPriorityFeeGwei
        )
        switch code {
        case .none: return nil
        case .invalidMaxFee: return localizedStoreString("Enter a valid Max Fee in gwei.")
        case .invalidPriorityFee: return localizedStoreString("Enter a valid Priority Fee in gwei.")
        case .maxBelowPriority: return localizedStoreString("Max Fee must be greater than or equal to Priority Fee.")
        }
    }
    func customEthereumFeeConfiguration() -> EthereumCustomFeeConfiguration? {
        guard useCustomEthereumFees else { return nil }
        guard customEthereumFeeValidationError == nil else { return nil }
        guard let maxFee = Double(customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)),
            let priorityFee = Double(customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return EthereumCustomFeeConfiguration(maxFeePerGasGwei: maxFee, maxPriorityFeePerGasGwei: priorityFee)
    }
    var customEthereumNonceValidationError: String? {
        let code = coreEthereumManualNonceValidation(
            manualNonceEnabled: ethereumManualNonceEnabled, nonceRaw: ethereumManualNonce
        )
        switch code {
        case .none: return nil
        case .empty: return localizedStoreString("Enter a nonce value for manual nonce mode.")
        case .notNonNegativeInteger: return localizedStoreString("Nonce must be a non-negative integer.")
        case .tooLarge: return localizedStoreString("Nonce value is too large.")
        }
    }
    func explicitEthereumNonce() -> Int? {
        guard ethereumManualNonceEnabled else { return nil }
        guard customEthereumNonceValidationError == nil else { return nil }
        return Int(ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func selectedWalletForSend() -> ImportedWallet? { wallet(for: sendWalletID) }
    func selectedPendingEthereumSendTransaction() -> TransactionRecord? {
        guard let wallet = selectedWalletForSend() else { return nil }
        return transactions.first { record in
            record.walletID == wallet.id
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }
    func pendingEthereumSendTransaction(with transactionID: UUID) -> TransactionRecord? {
        transactions.first { record in
            record.id == transactionID
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }
    func prepareEthereumReplacementContext(cancel: Bool) async {
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
    }
    func openEthereumReplacementComposer(for transactionID: UUID, cancel: Bool) async -> String? {
        guard let pendingTransaction = pendingEthereumSendTransaction(with: transactionID) else {
            let message = localizedStoreString("This Ethereum transaction is no longer pending, so replacement/cancel is unavailable.")
            sendError = message
            return message
        }
        guard let walletID = pendingTransaction.walletID, wallets.contains(where: { $0.id == walletID }) else {
            let message = localizedStoreString("The wallet for this pending transaction is not available.")
            sendError = message
            return message
        }
        sendWalletID = walletID
        if let ethereumHolding = availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" && $0.symbol == "ETH" })
            ?? availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" })
        {
            sendHoldingKey = ethereumHolding.holdingKey
        }
        syncSendAssetSelection()
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
        return sendError
    }
    func prepareEthereumReplacementContext(pendingTransaction: TransactionRecord, cancel: Bool) async {
        guard let txHash = pendingTransaction.transactionHash else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        isPreparingEthereumReplacementContext = true; defer { isPreparingEthereumReplacementContext = false }
        do {
            let nonce = try await WalletServiceBridge.shared.fetchEVMTxNonce(chainId: Chain.ethereum.id, txHash: txHash)
            guard let walletID = pendingTransaction.walletID, let wallet = wallets.first(where: { $0.id == walletID }) else {
                sendError = localizedStoreString("Select a wallet first."); return
            }
            sendAddress = cancel ? (wallet.ethereumAddress ?? "") : pendingTransaction.address
            sendAmount = cancel ? "0" : String(format: "%.8f", pendingTransaction.amount)
            ethereumManualNonceEnabled = true; ethereumManualNonce = String(nonce); useCustomEthereumFees = true
            let bump = coreEvmReplacementFeeBump(
                existingMaxFeeGwei: customEthereumMaxFeeGwei,
                existingPriorityFeeGwei: customEthereumPriorityFeeGwei,
                defaultMaxFeeGwei: 4.0, defaultPriorityFeeGwei: 2.0
            )
            customEthereumMaxFeeGwei = bump.maxFeeGwei
            customEthereumPriorityFeeGwei = bump.priorityFeeGwei
            sendError = localizedStoreString(
                cancel ? "Cancellation context loaded. Review fees and tap Send." : "Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            sendError = localizedStoreFormat("Unable to prepare replacement context: %@", error.localizedDescription)
        }
    }
    func prepareEthereumSpeedUpContext() async { await prepareEthereumReplacementContext(cancel: false) }
    func prepareEthereumCancelContext() async { await prepareEthereumReplacementContext(cancel: true) }
    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    func mapEthereumSendError(_ error: Error) -> String {
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
    /// The registry's answer, not a 15-case switch over a tag string. The tag
    /// was produced for every EVM chain; it was this switch that dropped ten of
    /// them on the floor.
    func evmChainContext(for chainName: String) -> EVMChainContext? {
        EVMChainContext(chainName: chainName)
    }
    func isEVMChain(_ chainName: String) -> Bool { (Chain(displayName: chainName)?.isEVM ?? false) }
    func configuredEVMRPCEndpointURL(for chainName: String) -> URL? { chainName == "Ethereum" ? configuredEthereumRPCEndpointURL() : nil }
    func supportedEVMToken(for coin: Coin) -> ChainTokenRegistryEntry? {
        guard evmChainContext(for: coin.chainName) != nil else { return nil }
        // A chain's native asset is never one of its tokens. This used to be
        // six hand-written chain/symbol pairs covering a fraction of the EVM
        // chains; the registry has the full table.
        if Chain(displayName: coin.chainName)?.gasTokenSymbol == coin.symbol {
            return nil
        }
        let chainTokens = TokenTrackingChain.forChainName(coin.chainName).map { enabledEVMTrackedTokens(for: $0) } ?? []
        if let contractAddress = coin.contractAddress {
            let normalizedContract = normalizeEVMAddress(contractAddress)
            return chainTokens.first { $0.symbol == coin.symbol && $0.contractAddress == normalizedContract }
        }
        return chainTokens.first { $0.symbol == coin.symbol }
    }
    func isValidDogecoinAddressForPolicy(_ address: String, wallet: ImportedWallet? = nil) -> Bool {
        let chainID =
            wallet.map { walletNetworkChainID(for: $0, family: "dogecoin") }
            ?? networkChainID(forFamily: "dogecoin")
        return AddressValidation.isValid(address, kind: (Chain(id: chainID)?.addressValidationKind ?? ""))
    }

    /// The address is judged against the network the family is on.
    ///
    /// This used to pick a mode string from a four-chain switch and hand it to
    /// a validator that ignored it — the `kind` had always been what decided.
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
                return localizedStoreFormat(
                    "Recipient is a smart contract on %@. Confirm it can receive %@ safely.", w.chainName ?? "", w.symbol ?? "")
            case "recipient_code_unknown":
                return localizedStoreFormat(
                    "Could not verify recipient contract state on %@. Review destination carefully.", w.chainName ?? "")
            case "token_contract_missing":
                return localizedStoreFormat(
                    "Token contract %@ appears missing on %@. This may be a wrong-network token selection.",
                    w.tokenSymbol ?? "", w.chainName ?? "")
            case "token_code_unknown":
                return localizedStoreFormat(
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
            case "invalid_format": return localizedStoreFormat("The destination address format does not match %@.", w.chain ?? "")
            case "new_address": return localizedStoreString("This is a new destination address with no prior history in this wallet.")
            case "ens_resolved":
                return localizedStoreFormat(
                    "ENS name '%@' resolved to %@. Confirm this resolved address before sending.", w.name ?? "", w.address ?? "")
            case "large_send":
                let formatted = (Double(w.percent ?? 0) / 100.0).formatted(.percent.precision(.fractionLength(0)))
                return localizedStoreFormat("This send is %@ of your %@ balance.", formatted, w.symbol ?? "")
            case "non_evm_on_evm":
                return localizedStoreFormat("Destination appears to be a non-EVM address while sending on %@.", w.chain ?? "")
            case "ens_on_l2":
                return localizedStoreFormat(
                    "ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", w.chain ?? "")
            case "eth_on_utxo":
                return localizedStoreFormat("Destination appears to be an Ethereum-style address while sending on %@.", w.chain ?? "")
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
    /// What the address field says for a chain: how a valid address looks while
    /// the field is empty, and what to fix once it does not parse.
    ///
    /// One table rather than the two fourteen-arm switches this replaces, which
    /// said the same fourteen things in a different tense. Keyed by chain name
    /// because the sentences are about a chain's address format, and that is
    /// content rather than a registry fact — what the registry decides is
    /// membership, which is why the EVM family is one arm below rather than
    /// twenty-three rows here.
    ///
    /// **Ten mainnets have no entry** and fall back to the generic form:
    /// Bitcoin Cash, Bitcoin SV, Litecoin, Internet Computer, Zcash, Bitcoin
    /// Gold, Decred, Kaspa, Dash and Bittensor. Writing those needs copy in
    /// four locales, so it is a content gap recorded in `PLAN.md` rather than
    /// something to invent here — but it is one list now instead of two.
    private static let addressFormatHints: [String: (empty: String, invalid: String)] = [
        "Bitcoin": (
            "Enter a Bitcoin address valid for the selected Bitcoin network mode.",
            "Enter a valid Bitcoin address for the selected Bitcoin network mode."),
        "Dogecoin": (
            "Dogecoin addresses usually start with D, A, or 9.",
            "Enter a valid Dogecoin address beginning with D, A, or 9."),
        "Tron": (
            "Tron addresses usually start with T and are Base58 encoded.",
            "Enter a valid Tron address (starts with T)."),
        "Solana": (
            "Solana addresses are Base58 encoded and typically 32-44 characters.",
            "Enter a valid Solana address (Base58 format)."),
        "Cardano": (
            "Cardano addresses typically start with addr1 and use bech32 format.",
            "Enter a valid Cardano address (starts with addr1)."),
        "XRP Ledger": (
            "XRP Ledger addresses start with r and are Base58 encoded.",
            "Enter a valid XRP address (starts with r)."),
        "Stellar": (
            "Stellar addresses start with G and are StrKey encoded.",
            "Enter a valid Stellar address (starts with G)."),
        "Monero": (
            "Monero addresses are Base58 encoded and usually start with 4 or 8.",
            "Enter a valid Monero address (starts with 4 or 8)."),
        "TON": (
            "TON addresses are usually user-friendly strings like UQ... or raw 0:<hex> addresses.",
            "Enter a valid TON address."),
        "NEAR": (
            "NEAR addresses can be named accounts or 64-character implicit account IDs.",
            "Enter a valid NEAR account ID or implicit address."),
        "Polkadot": (
            "Polkadot addresses use SS58 encoding and usually start with 1.",
            "Enter a valid Polkadot SS58 address."),
    ]

    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        let isValid = !isEmpty && isValidAddress(trimmed, for: chainName)
        if !isEmpty, isValid { return localizedStoreFormat("Valid %@ address.", chainName) }

        if let hint = Self.addressFormatHints[chainName] {
            return localizedStoreString(isEmpty ? hint.empty : hint.invalid)
        }
        // One arm for the whole family. Thirteen names stood here and the other
        // ten EVM mainnets got the generic message; membership is the
        // registry's.
        if Chain(displayName: chainName)?.isEVM == true {
            return isEmpty
                ? localizedStoreFormat("%@ addresses use EVM format (0x + 40 hex characters).", chainName)
                : localizedStoreFormat("Enter a valid %@ address (0x + 40 hex characters).", chainName)
        }
        if chainName == "Sui" || chainName == "Aptos" {
            return isEmpty
                ? localizedStoreFormat("%@ addresses are hex and typically start with 0x.", chainName)
                : localizedStoreFormat("Enter a valid %@ address (starts with 0x).", chainName)
        }
        return isEmpty
            ? localizedStoreString("Enter an address for the selected chain.")
            : localizedStoreFormat("Enter a valid %@ address.", chainName)
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
    ///
    /// Was five wrappers, each threading three key paths into three per-chain
    /// stored properties. The suite, the abbreviation and the state are all
    /// keyed by chain now — the abbreviation from the registry, which has had
    /// it all along as `coin_symbol`.
    func runSelfTests(for chainName: String) {
        guard !selfTests(for: chainName).isRunning else { return }
        selfTests[chainName, default: .init()].isRunning = true
        let results = ChainSelfTests.run(chainName)
        selfTests[chainName] = .init(results: results, isRunning: false, lastRunAt: Date())

        let failedCount = results.filter { !$0.passed }.count
        let abbrev = Chain(displayName: chainName)?.gasTokenSymbol ?? chainName
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: chainName,
            message: failedCount == 0
                ? "\(abbrev) self-tests passed (\(results.count) checks)."
                : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func runEthereumSelfTests() async {
        guard !selfTests(for: "Ethereum").isRunning else { return }
        selfTests["Ethereum", default: .init()].isRunning = true
        defer { selfTests["Ethereum", default: .init()].isRunning = false }
        var results = ChainSelfTests.run("Ethereum")
        let rpcURL = configuredEthereumRPCEndpointURL()?.absoluteString ?? "https://ethereum.publicnode.com"
        let rpcLabel = configuredEthereumRPCEndpointURL()?.absoluteString ?? "default RPC pool"
        results.append(contentsOf: await selfTestsRunEthereumRpc(rpcUrl: rpcURL, rpcLabel: rpcLabel))
        if let firstEthereumWallet = wallets.first(where: { $0.selectedChain == "Ethereum" }),
            let ethereumAddress = resolvedEthereumAddress(for: firstEthereumWallet)
        {
            do {
                _ = try await fetchEthereumPortfolio(for: ethereumAddress)
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: true, chainLabel: "Ethereum",
                        outcome: .custom(text: "Successfully fetched ETH/ERC-20 portfolio for \(firstEthereumWallet.name).")))
            } catch {
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: false, chainLabel: "Ethereum",
                        outcome: .custom(text: "Portfolio probe failed for \(firstEthereumWallet.name): \(error.localizedDescription)")))
            }
        } else {
            results.append(
                ChainSelfTestResult(
                    name: "ETH Portfolio Probe", passed: true, chainLabel: "Ethereum",
                    outcome: .custom(text: "Skipped: no imported wallet with Ethereum enabled.")))
        }
        let diagnosticsOK = diagnosticsJSON(for: "Ethereum").map { coreDiagnosticsEvmJsonShapeOk(json: $0) } ?? false
        results.append(
            ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape", passed: diagnosticsOK, chainLabel: "Ethereum",
                outcome: .custom(
                    text: diagnosticsOK
                        ? "Diagnostics JSON contains expected top-level keys."
                        : "Diagnostics JSON missing expected keys (history/endpoints).")))
        selfTests["Ethereum"] = .init(results: results, isRunning: true, lastRunAt: Date())
        let failedCount = results.filter { !$0.passed }.count
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: "Ethereum",
            message: failedCount == 0
                ? "ETH diagnostics passed (\(results.count) checks)." : "ETH diagnostics completed with \(failedCount) failure(s).")
    }
    func operationalEvents(for chainName: String) async -> [ChainOperationalEvent] {
        await WalletServiceBridge.shared.operationalEvents(chainName: chainName)
    }
    func feePriorityOption(for chainName: String) -> ChainFeePriorityOption {
        if chainName == "Bitcoin" { return mapBitcoinFeePriorityToChainOption(bitcoinFeePriority) }
        if chainName == "Dogecoin" { return mapDogecoinFeePriorityToChainOption(dogecoinFeePriority) }
        return selectedFeePriorityOptionRawByChain[chainName].flatMap(ChainFeePriorityOption.init(rawValue:)) ?? .normal
    }
    func setFeePriorityOption(_ option: ChainFeePriorityOption, for chainName: String) {
        if chainName == "Bitcoin" { bitcoinFeePriority = mapChainOptionToBitcoinFeePriority(option); return }
        if chainName == "Dogecoin" { dogecoinFeePriority = mapChainOptionToDogecoinFeePriority(option); return }
        selectedFeePriorityOptionRawByChain[chainName] = option.rawValue
    }
    func bitcoinFeePriority(for chainName: String) -> BitcoinFeePriority {
        mapChainOptionToBitcoinFeePriority(feePriorityOption(for: chainName))
    }
    func mapBitcoinFeePriorityToChainOption(_ priority: BitcoinFeePriority) -> ChainFeePriorityOption {
        ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal
    }
    func mapChainOptionToBitcoinFeePriority(_ option: ChainFeePriorityOption) -> BitcoinFeePriority {
        BitcoinFeePriority(rawValue: option.rawValue) ?? .normal
    }
    func mapDogecoinFeePriorityToChainOption(_ priority: DogecoinFeePriority) -> ChainFeePriorityOption {
        ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal
    }
    func mapChainOptionToDogecoinFeePriority(_ option: ChainFeePriorityOption) -> DogecoinFeePriority {
        DogecoinFeePriority(rawValue: option.rawValue) ?? .normal
    }
    func persistSelectedFeePriorityOptions() {
        persistCodableToSQLite(selectedFeePriorityOptionRawByChain, key: Self.selectedFeePriorityOptionsByChainDefaultsKey)
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
    ///
    /// Five wrappers used to state this, each naming a chain, two key paths
    /// and its ticker. The ticker is on the chain descriptor, the running
    /// state is keyed, and both refreshes take a chain name — so the wrapper
    /// had nothing left to say. Bitcoin and Dogecoin keep their own history
    /// fetch: HD xpub expansion and a confirmed-fee path.
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
                case "Dogecoin":
                    await self.refreshDogecoinTransactions(limit: HistoryPaging.endpointBatchSize)
                default:
                    await self.refreshNormalizedTransactions(chainName: chainName)
                }
            },
            refreshPending: { await self.refreshPendingTransactions(chainName: chainName) })
    }

    func runDogecoinHistoryDiagnostics() async {
        guard !self[historyRunFor: "Dogecoin"].isRunning else { return }
        self[historyRunFor: "Dogecoin"].isRunning = true; defer { self[historyRunFor: "Dogecoin"].isRunning = false }
        let walletsToRefresh = wallets.compactMap { w -> (ImportedWallet, String)? in
            guard w.selectedChain == "Dogecoin", let address = resolvedDogecoinAddress(for: w) else { return nil }
            return (w, address)
        }
        guard !walletsToRefresh.isEmpty else { self[historyRunFor: "Dogecoin"].lastUpdatedAt = Date(); return }
        for (wallet, address) in walletsToRefresh {
            do {
                let count = try await withTimeout(seconds: 20) {
                    try await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: Chain.dogecoin.id, address: address)
                }
                recordUTXOHistoryDiagnostics(
                    chainName: "Dogecoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil))
            } catch {
                recordUTXOHistoryDiagnostics(
                    chainName: "Dogecoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: address, sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription))
            }
            self[historyRunFor: "Dogecoin"].lastUpdatedAt = Date()
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
        guard let chain = Chain(displayName: transaction.chainName),
            case .utxo(let tracksFinality, let requireSendKind) = chain.pendingStatusPoll,
            !requireSendKind || transaction.kind == .send
        else { return "Status recheck is not available for this transaction." }
        guard transaction.transactionHash != nil else { return "This transaction has no hash to recheck." }
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
    func rebroadcastDogecoinTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.chainName == "Dogecoin", transaction.kind == .send else {
            return "Rebroadcast is only supported for Dogecoin send transactions."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize Dogecoin rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        guard let rawTransactionHex = transaction.signedTransactionPayload,
            !rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "This transaction cannot be rebroadcast because raw signed data was not saved." }
        appendChainOperationalEvent(
            .info, chainName: "Dogecoin", message: "DOGE rebroadcast requested.", transactionHash: transaction.transactionHash)
        do {
            let txidFromJSON = try await WalletServiceBridge.shared.broadcastRawExtract(
                chainId: Chain.dogecoin.id, payload: rawTransactionHex, resultField: "txid")
            let txHash = txidFromJSON.isEmpty ? (transaction.transactionHash ?? "") : txidFromJSON
            let result = (transactionHash: txHash, verificationStatus: SendBroadcastVerificationStatus.deferred)
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                recordTransaction(transactions[index].withRebroadcastUpdate(status: .pending, transactionHash: result.transactionHash))
            }
            await refreshPendingTransactions(chainName: "Dogecoin")
            switch result.verificationStatus {
            case .verified:
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: "DOGE rebroadcast verified by provider.", transactionHash: result.transactionHash
                ); return "Transaction rebroadcasted and observed on network providers."
            case .deferred:
                appendChainOperationalEvent(
                    .warning, chainName: "Dogecoin", message: "DOGE rebroadcast accepted; verification deferred.",
                    transactionHash: result.transactionHash);
                return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message):
                appendChainOperationalEvent(
                    .warning, chainName: "Dogecoin", message: "DOGE rebroadcast verification warning: \(message)",
                    transactionHash: result.transactionHash);
                return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            appendChainOperationalEvent(
                .error, chainName: "Dogecoin", message: "DOGE rebroadcast failed: \(error.localizedDescription)",
                transactionHash: transaction.transactionHash);
            return error.localizedDescription
        }
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
    func derivationAccount(for wallet: ImportedWallet, chain: Chain) -> UInt32 {
        derivationResolution(for: wallet, chain: chain).accountIndex
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
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID,
            let wallet = cachedWalletByID[walletID]
        {
            return displayNetworkName(for: wallet)
        }
        return displayNetworkName(for: transaction.chainName)
    }
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID,
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
    func isValidUTXOAddressForPolicy(_ address: String, chainName: String) -> Bool {
        guard supportsDeepUTXODiscovery(chainName: chainName),
            let family = Chain(displayName: chainName)?.id, !family.isEmpty
        else { return false }
        let kind = Chain(id: networkChainID(forFamily: family))?.addressValidationKind ?? ""
        return !kind.isEmpty && AddressValidation.isValid(address, kind: kind)
    }
    func utxoDiscoveryDerivationPath(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let derivationChain = seedDerivationChain(for: chainName) else { return nil }
        let rawPath = walletDerivationPath(for: wallet, chain: derivationChain)
        guard let segments = coreParseDerivationPath(rawPath: rawPath), segments.count >= 5 else { return nil }
        return coreDerivationPathReplacingLastTwo(
            rawPath: rawPath, branch: UInt32(branch.rawValue), index: UInt32(max(0, index)), fallback: rawPath)
    }
    func deriveUTXOAddress(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id), supportsDeepUTXODiscovery(chainName: chainName),
            let derivationPath = utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: branch, index: index),
            let derivationChain = utxoDiscoveryDerivationChain(for: chainName),
            let address = try? deriveSeedPhraseAddress(
                seedPhrase: seedPhrase, chain: derivationChain,
                derivationPath: derivationPath
            ), isValidUTXOAddressForPolicy(address, chainName: chainName)
        else {
            return nil
        }
        return address
    }
    /// Whether this address has ever been used on chain.
    ///
    /// Three arms before, and they asked different questions. Bitcoin asked
    /// "any UTXOs, or any confirmed balance" and never looked at history;
    /// Bitcoin Cash, Bitcoin SV, Litecoin and Dogecoin asked "any balance, or
    /// any history" and never looked at the UTXO count. It is one question —
    /// see "a used Bitcoin receive address" under "Behaviour changed on
    /// purpose" — and `supports_deep_utxo_discovery` is the chain set, which
    /// brings the testnets in with their mainnets.
    func hasUTXOOnChainActivity(address: String, chainName: String) async -> Bool {
        guard let chain = Chain(displayName: chainName), chain.supportsDeepUTXODiscovery else { return false }
        if let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(
            chainId: chain.id, address: address)
        {
            if summary.utxoCount > 0 || (UInt64(summary.smallestUnit) ?? 0) > 0 { return true }
        }
        return (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(chainId: chain.id, address: address)) == true
    }
    func knownUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        var ordered: [String] = []; var seen: Set<String> = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidUTXOAddressForPolicy(trimmed, chainName: chainName), seen.insert(trimmed.lowercased()).inserted else { return }
            ordered.append(trimmed)
        }
        // The stored address for this chain, which may differ from the derived
        // one below. Five arms picked between five of the `wallet.<chain>Address`
        // shims by name; `address(forChainNamed:)` is that lookup, and it keys
        // on the registry's slot rather than on a list.
        appendAddress(wallet.address(forChainNamed: chainName))
        appendAddress(resolvedAddress(for: wallet, chainName: chainName))
        appendAddress(await reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false))
        for transaction in transactions where transaction.chainName == chainName && transaction.walletID == wallet.id {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }
        for discoveredAddress in discoveredUTXOAddressesByChain[chainName]?[wallet.id] ?? [] { appendAddress(discoveredAddress) }
        for ownedAddress in await ownedAddresses(for: wallet.id, chainName: chainName) { appendAddress(ownedAddress) }
        return ordered
    }
    func discoverUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        var ordered = await knownUTXOAddresses(for: wallet, chainName: chainName)
        var seen = Set(ordered.map { $0.lowercased() })
        guard supportsDeepUTXODiscovery(chainName: chainName), storedSeedPhrase(for: wallet.id) != nil else { return ordered }
        let state = await keypoolState(for: wallet, chainName: chainName)
        // `nextExternalIndex` already clears the highest owned external index —
        // core folds it into the baseline — so this only has to also clear the
        // reservation.
        let reserved = state.reservedReceiveIndex ?? 0
        let scanUpperBound = min(
            Self.utxoDiscoveryMaxIndex,
            max(state.nextExternalIndex, reserved + 1) + Self.utxoDiscoveryGapLimit
        )
        guard scanUpperBound >= 0 else { return ordered }
        for index in 0...scanUpperBound {
            guard let derivedAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: index) else {
                continue
            }
            let normalized = derivedAddress.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                ordered.append(derivedAddress)
            }
            if await hasUTXOOnChainActivity(address: derivedAddress, chainName: chainName) {
                registerOwnedAddress(
                    chainName: chainName, address: derivedAddress, walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: index
                    ), index: index, branch: "external"
                )
            }
        }
        return ordered
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
    func refreshUTXOReceiveReservationState(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else { return }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else { return }
        for wallet in utxoWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = await reserveReceiveIndex(for: wallet, chainName: chainName, minimumIndex: 1)
            let state = await keypoolState(for: wallet, chainName: chainName)
            guard let reservedIndex = state.reservedReceiveIndex,
                let reservedAddress = deriveUTXOAddress(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                )
            else {
                continue
            }
            registerOwnedAddress(
                chainName: chainName, address: reservedAddress, walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            guard await hasUTXOOnChainActivity(address: reservedAddress, chainName: chainName) else { continue }
            // The reserved address has been used, so move past it: release the
            // reservation and take the next index. Both halves run in core, so
            // nothing else can slip in between and reissue what we just used.
            try? await WalletServiceBridge.shared.clearReservedReceiveIndex(
                walletID: wallet.id, chainName: chainName)
            guard let nextReserved = await reserveReceiveIndex(
                for: wallet, chainName: chainName, minimumIndex: reservedIndex + 1)
            else { continue }
            if let nextAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: nextReserved) {
                registerOwnedAddress(
                    chainName: chainName, address: nextAddress, walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: nextReserved
                    ), index: nextReserved, branch: "external"
                )
            }
        }
    }
    func seedDerivationChain(for chainName: String) -> Chain? {
        CachedCoreHelpers.seedDerivationChainRaw(chainName: chainName).flatMap(Chain.init(displayName:))
    }
    func walletHasAddress(for wallet: ImportedWallet, chainName: String) -> Bool {
        resolvedAddress(for: wallet, chainName: chainName) != nil
    }
    func normalizedOwnedAddressKey(chainName: String, address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    /// Core holds the table and does the merge under its own lock — Swift only
    /// supplies the baseline, which depends on transaction and owned-address
    /// history it still computes.
    func keypoolState(for wallet: ImportedWallet, chainName: String) async -> ChainKeypoolState {
        guard let state = try? await WalletServiceBridge.shared.keypoolState(
            walletID: wallet.id, chainName: chainName)
        else { return ChainKeypoolState(keypool: KeypoolState(nextExternalIndex: 0, nextChangeIndex: 0, reservedReceiveIndex: nil)) }
        return ChainKeypoolState(keypool: state)
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
    func reservedReceiveDerivationPath(for wallet: ImportedWallet, chainName: String, index: Int?) -> String? {
        if supportsDeepUTXODiscovery(chainName: chainName) {
            guard let index else { return nil }
            return utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: .external, index: index)
        }
        guard seedDerivationChain(for: chainName) != nil else { return nil }
        return seedDerivationChain(for: chainName).map { walletDerivationPath(for: wallet, chain: $0) }
    }
    /// The keypool as it currently stands, recording nothing.
    ///
    /// The `reserveIfMissing: false` path of `reservedReceiveAddress` still
    /// wrote — through `keypoolState` and `registerOwnedAddress`, both of which
    /// touch observed state. This is the variant a SwiftUI `body` can call.
    func keypoolStateForDisplay(for wallet: ImportedWallet, chainName: String) async
        -> ChainKeypoolState
    {
        ChainKeypoolState(
            keypool: await WalletServiceBridge.shared.keypoolStateForDisplay(
                walletID: wallet.id, chainName: chainName))
    }
    func reservedReceiveAddressForDisplay(for wallet: ImportedWallet, chainName: String) async
        -> String?
    {
        if supportsDeepUTXODiscovery(chainName: chainName) {
            let state = await keypoolStateForDisplay(for: wallet, chainName: chainName)
            guard let reservedIndex = state.reservedReceiveIndex,
                let address = deriveUTXOAddress(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex)
            else { return resolvedAddress(for: wallet, chainName: chainName) }
            return address
        }
        return resolvedAddress(for: wallet, chainName: chainName)
    }
    func reservedReceiveAddress(for wallet: ImportedWallet, chainName: String, reserveIfMissing: Bool) async -> String? {
        if supportsDeepUTXODiscovery(chainName: chainName) {
            // Deep-UTXO chains never hand out index 0 as a receive address.
            let reserved: Int? =
                reserveIfMissing
                ? await reserveReceiveIndex(for: wallet, chainName: chainName, minimumIndex: 1)
                : await keypoolState(for: wallet, chainName: chainName).reservedReceiveIndex
            guard let reservedIndex = reserved,
                let address = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: reservedIndex)
            else { return resolvedAddress(for: wallet, chainName: chainName) }
            registerOwnedAddress(
                chainName: chainName, address: address, walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            return address
        }
        if reserveIfMissing { _ = await reserveReceiveIndex(for: wallet, chainName: chainName) }
        guard let address = resolvedAddress(for: wallet, chainName: chainName) else { return nil }
        let reservedIndex = await keypoolState(for: wallet, chainName: chainName).reservedReceiveIndex
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
        let reservedIndex = await reserveReceiveIndex(for: wallet, chainName: chainName)
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
        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }
        do {
            let warning: String?
            let infoMessage: String?
            switch coin.chainName {
            case "Bitcoin":
                let btcSummary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                    chainId: Chain.bitcoin.id, address: destinationForProbe)
                let btcBalance = UInt64(btcSummary.smallestUnit) ?? 0
                let m = chainRiskProbeMessages(
                    chainName: "Bitcoin", balanceLabel: "balance", balanceNonPositive: btcBalance <= 0, hasHistory: btcSummary.utxoCount > 0)
                warning = m.warning; infoMessage = m.info
            // Thirteen names stood here, and the ten EVM mainnets outside them —
            // Sei, Celo, Cronos, opBNB, zkSync Era, Sonic, Berachain, Unichain,
            // Ink and X Layer — fell to `default`, which is "no warning". The
            // probe is the same call for every EVM chain; membership is the
            // registry's.
            case let name where Chain(displayName: name)?.isEVM == true:
                guard let chainId = Chain(displayName: coin.chainName)?.id else {
                    warning = nil
                    infoMessage = nil
                    break
                }
                let normalizedAddress = try validateEVMAddress(destinationForProbe)
                let probe = try await WalletServiceBridge.shared.fetchEvmAddressProbe(
                    chainId: chainId, address: normalizedAddress
                )
                let hasHistory = probe.nonce > 0
                if coin.symbol == "ETH" || coin.symbol == "BNB" || coin.symbol == "AVAX" || coin.symbol == "ARB" || coin.symbol == "OP" {
                    let m = chainRiskProbeMessages(
                        chainName: coin.chainName, balanceLabel: "\(coin.symbol) balance",
                        balanceNonPositive: probe.balanceEth <= 0,
                        hasHistory: hasHistory)
                    warning = m.warning; infoMessage = m.info
                } else if let token = supportedEVMToken(for: coin) {
                    let tokenBalances = try await WalletServiceBridge.shared.fetchTokenBalances(
                        chainId: chainId, address: normalizedAddress,
                        tokens: [TokenDescriptor(contract: token.contractAddress, symbol: token.symbol, decimals: UInt8(token.decimals), name: nil)])
                    let tokenBalance = Decimal(string: tokenBalances.first?.balanceDisplay ?? "0") ?? .zero
                    warning =
                        (tokenBalance <= .zero && !hasHistory)
                        ? "Warning: this address has zero \(coin.symbol) balance and no transaction history on \(coin.chainName). Double-check recipient details."
                        : nil
                    infoMessage =
                        (tokenBalance <= .zero && hasHistory)
                        ? "Note: this address has transaction history but currently zero \(coin.symbol) balance on \(coin.chainName)." : nil
                } else {
                    warning = nil; infoMessage = nil
                }
            case "Tron":
                if coin.symbol == "TRX" || coin.symbol == "USDT" {
                    let tronSummary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                        chainId: Chain.tron.id, address: destinationForProbe)
                    let tronSun = UInt64(tronSummary.smallestUnit) ?? 0
                    let hasHistory =
                        (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(
                            chainId: Chain.tron.id, address: destinationForProbe)) ?? false
                    let balance: Double
                    if coin.symbol == "TRX" {
                        balance = Double(tronSun) / 1e6
                    } else {
                        let usdtResults = try await WalletServiceBridge.shared.fetchTokenBalances(
                            chainId: Chain.tron.id, address: destinationForProbe,
                            tokens: [TokenDescriptor(contract: TronBalanceService.usdtTronContract, symbol: "USDT", decimals: 6, name: nil)])
                        balance = usdtResults.first.flatMap { Double($0.balanceDisplay) } ?? 0
                    }
                    let label = "\(coin.symbol) balance"
                    warning =
                        (balance <= 0 && !hasHistory)
                        ? "Warning: this Tron address has zero \(coin.symbol) balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage =
                        (balance <= 0 && hasHistory) ? "Note: this Tron address has transaction history but currently zero \(label)." : nil
                } else {
                    warning = nil; infoMessage = nil
                }
            case "NEAR":
                let nearBalance: Double
                if let nearSummary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                    chainId: Chain.near.id, address: destinationForProbe)
                {
                    nearBalance = Double(nearSummary.amountDisplay) ?? 0
                } else {
                    nearBalance = 0
                }
                let nearHasHistory =
                    (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(
                        chainId: Chain.near.id, address: destinationForProbe)) ?? false
                let m = chainRiskProbeMessages(
                    chainName: "NEAR", balanceLabel: "NEAR balance", balanceNonPositive: nearBalance <= 0, hasHistory: nearHasHistory)
                warning = m.warning; infoMessage = m.info
            // No chain list on the way out either. The seven names that used to
            // gate this arm — Litecoin, Dogecoin, Solana, XRP Ledger, Monero,
            // Sui, Aptos — were a copy of the seven `core_simple_chain_risk_probe_config`
            // matches, and it already answers `nil` for a chain it has no probe
            // for. Two answers to one question, and the copy could only ever be
            // the staler of the two.
            default:
                if let cfg = coreSimpleChainRiskProbeConfig(chainName: coin.chainName, symbol: coin.symbol),
                    let chainId = Chain(displayName: coin.chainName)?.id
                {
                    (warning, infoMessage) = await fetchChainRiskWarning(
                        chainId: chainId, address: destinationForProbe,
                        chainName: cfg.displayChainName, balanceLabel: cfg.balanceLabel)
                } else {
                    warning = nil
                    infoMessage = nil
                }
            }
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = warning
            sendDestinationInfoMessage = [infoMessage, ensResolutionInfo]
                .compactMap { $0 }.joined(separator: " ")
            lastSendDestinationProbeKey = addressProbeKey
            lastSendDestinationProbeWarning = warning
            lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
        } catch {
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
        }
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
    private func fetchChainRiskWarning(
        chainId: String, address: String, chainName: String, balanceLabel: String
    ) async -> (warning: String?, info: String?) {
        guard let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: chainId, address: address) else {
            return (nil, nil)
        }
        let balance = Double(summary.amountDisplay) ?? 0
        let hasHistory = (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(chainId: chainId, address: address)) ?? false
        let m = chainRiskProbeMessages(
            chainName: chainName, balanceLabel: balanceLabel, balanceNonPositive: balance <= 0, hasHistory: hasHistory)
        return (m.warning, m.info)
    }
    /// Validate that the wallet has sufficient balance for amount + fee.
    /// Returns nil on success, or a user-facing error message on failure.
    func validateSendBalance(
        amount: Double, networkFee: Double, holdingBalance: Double,
        isNativeAsset: Bool, symbol: String,
        nativeSymbol: String?, nativeBalance: Double?,
        feeDecimals: Int, chainLabel: String?
    ) -> String? {
        if isNativeAsset {
            let total = amount + networkFee
            if total > holdingBalance {
                let totalText = String(format: "%.\(feeDecimals)f", total)
                return localizedStoreFormat(
                    "Insufficient %@ for amount plus network fee (needs ~%@ %@).",
                    symbol, totalText, symbol
                )
            }
        } else {
            if amount > holdingBalance {
                return localizedStoreFormat("Insufficient %@ balance for this transfer.", symbol)
            }
            if let nativeSym = nativeSymbol, let nativeBal = nativeBalance, networkFee > nativeBal {
                let feeText = String(format: "%.\(feeDecimals)f", networkFee)
                if let chain = chainLabel {
                    return localizedStoreFormat(
                        "Insufficient %@ to cover %@ network fee (~%@ %@).",
                        nativeSym, chain, feeText, nativeSym
                    )
                }
                return localizedStoreFormat(
                    "Insufficient %@ to cover the network fee (~%@ %@).",
                    nativeSym, feeText, nativeSym
                )
            }
        }
        return nil
    }
    func chainRiskProbeMessages(chainName: String, balanceLabel: String, balanceNonPositive: Bool, hasHistory: Bool) -> (
        warning: String?, info: String?
    ) {
        let warning: String? =
            (balanceNonPositive && !hasHistory)
            ? localizedStoreFormat(
                "Warning: this %@ address has zero balance and no transaction history. Double-check recipient details.", chainName)
            : nil
        let info: String? =
            (balanceNonPositive && hasHistory)
            ? localizedStoreFormat("Note: this %@ address has transaction history but currently zero %@.", chainName, balanceLabel)
            : nil
        return (warning, info)
    }
}
