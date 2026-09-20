import Foundation
import SwiftUI
@MainActor
extension AppState {
    private func clearAllChainSendState() {
        sendPreviewRequestId = UUID()
        sendPreviewStore.resetAll()
        sendingChains = []
        preparingChains = []
        clearHighRiskSendConfirmation()
    }
    private func resetSendComposerFields() {
        sendDestinationProbeRequestId = UUID()
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
        sendWalletId = firstWallet.id
        sendHoldingKey = availableSendCoins(for: sendWalletId).first?.holdingKey ?? ""
        resetSendComposerFields()
        syncSendAssetSelection()
        isShowingSendSheet = true
    }
    func syncSendAssetSelection() {
        sendDestinationProbeRequestId = UUID()
        let availableHoldingKeys = availableSendCoins(for: sendWalletId).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendHoldingKey) { sendHoldingKey = availableHoldingKeys.first ?? "" }
        // Keep EIP-1559 fees and manual nonce when switching within the EVM
        // family; clear them when leaving it.
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
        availableSendCoins(for: sendWalletId).first(where: { $0.holdingKey == sendHoldingKey })
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
    /// Whether a preview for this chain is being fetched. `preparingChains`
    /// holds preview slots, so the question goes through the same key.
    func isPreparingSendPreview(forChainNamed chainName: String) -> Bool {
        SendPreviewStore.slot(forChainNamed: chainName).map(preparingChains.contains) ?? false
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
        // The toggle is cleared outside the EVM family; only EVM preview and
        // submit paths read these fees.
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
    func selectedWalletForSend() -> WalletView? { wallet(for: sendWalletId) }
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
            $0.walletId.caseInsensitiveCompare(sendWalletId) == .orderedSame
                && $0.chainName == selectedSendCoin.chainName
        }
    }
    func replaceableSend(forTransaction transactionId: String) -> ReplaceableSend? {
        replaceableSends.first {
            $0.transactionId.caseInsensitiveCompare(transactionId) == .orderedSame
        }
    }
    func prepareReplacementContext(cancel: Bool) async {
        guard let pending = replaceableSendForSelectedWallet else {
            sendError = localizedStoreString("No pending transaction found for this wallet.")
            return
        }
        await prepareReplacementContext(pending: pending, cancel: cancel)
    }
    func openReplacementComposer(for transactionId: String, cancel: Bool) async -> String? {
        guard let pending = replaceableSend(forTransaction: transactionId) else {
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
            let draft = try await self.bridge.replacementDraft(
                transactionId: pending.transactionId, cancel: cancel)
            sendWalletId = draft.walletId
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
    /// The known-token entry for a holding, on any chain that hosts tokens.
    ///
    /// The contract normaliser is core's rather than a lowercasing of the
    /// address, so a TON jetton's case-significant address is not lowercased
    /// into a non-match.
    func supportedToken(for coin: Coin) -> TokenPreferenceEntry? {
        guard let entry = cachedTokenPreferenceByDeploymentId[coin.holdingKey], entry.isEnabled else { return nil }
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
        return try await self.bridge.resolveSendDestination(chainId: chainId, input: input, expectedAddress: expectedAddress)
    }
    func clearHighRiskSendConfirmation() { pendingSendReview = nil; pendingHighRiskSendReasons = []; isShowingHighRiskSendConfirmation = false }
    func confirmHighRiskSendAndSubmit(password: String?) async {
        isShowingHighRiskSendConfirmation = false
        guard let review = pendingSendReview else { return }
        pendingSendReview = nil
        await submitReviewedSend(review, password: password)
    }

    /// `nil` when the lookup failed, which is a different answer from an
    /// empty list. Collapsing the two let a transient failure read as "this
    /// wallet owns no addresses" — and the self-send guard, which asks exactly
    /// that question, then waved the send through.
    func knownUTXOAddresses(for wallet: WalletView, chainName: String) async -> [String]? {
        guard let chain = Chain(displayName: chainName) else { return [] }
        do {
            return try await self.bridge.knownUTXOAddresses(walletId: wallet.id, chainId: chain.id)
        } catch {
            appendOperationalLog(
                .error, category: "Owned Addresses",
                message: "Known \(chainName) addresses could not be read: \(String(describing: error))",
                chainName: chainName, walletId: wallet.id)
            return nil
        }
    }

    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let requestId = UUID()
        sendDestinationProbeRequestId = requestId
        let walletId = sendWalletId
        let holdingKey = coin.holdingKey
        let input = sendAddress
        func isCurrent() -> Bool {
            !Task.isCancelled && sendDestinationProbeRequestId == requestId
                && sendWalletId == walletId && sendHoldingKey == holdingKey && sendAddress == input
        }
        sendDestinationRiskWarning = nil
        sendDestinationInfoMessage = nil
        isCheckingSendDestinationBalance = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        defer { if sendDestinationProbeRequestId == requestId { isCheckingSendDestinationBalance = false } }
        guard isCheckingSendDestinationBalance else { return }
        do {
            // Core resolves the typed input and identifies the stored deployment.
            // No ticker-based cache or cross-protocol address normalization lives here.
            let risk = try await self.bridge.sendDestinationRisk(
                walletId: walletId, holdingKey: holdingKey, destination: input)
            guard isCurrent() else { return }
            let messages = chainRiskProbeMessages(chainName: coin.chainName, symbol: coin.symbol,
                balanceIsZero: risk.balanceIsZero, hasHistory: risk.hasHistory)
            sendDestinationRiskWarning = messages.warning
            sendDestinationInfoMessage = messages.info
        } catch {
            guard isCurrent() else { return }
            sendDestinationInfoMessage = localizedStoreString("Unable to verify this address's activity. Try again later.")
        }
    }
    /// Localized title and message for a destination verdict.
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
    func availableSendCoins(for walletId: String) -> [Coin] { cachedAvailableSendCoinsByWalletId[walletId] ?? [] }
    var sendEnabledWallets: [WalletView] { cachedSendEnabledWallets }
    var canBeginSend: Bool { !sendEnabledWallets.isEmpty }
    var replacementNonceStateMessage: String? {
        guard let selectedSendCoin, selectedSendCoin.isEVMChain else { return nil }
        guard let pending = replaceableSendForSelectedWallet else {
            return AppLocalization.format(
                "No pending %@ send found for this wallet. Replacement and cancel are available only for pending transactions.",
                selectedSendCoin.chainName)
        }
        var message = AppLocalization.format("Pending %@ transaction detected", pending.symbol)
        if let nonce = pending.recordedNonce {
            message += AppLocalization.format("send.replacement.pendingNonceSuffix", nonce)
        } else {
            message += "."
        }
        let hash = pending.transactionHash
        let shortHash = hash.count > 14 ? "\(hash.prefix(10))...\(hash.suffix(4))" : hash
        message += AppLocalization.format("send.replacement.transactionSuffix", shortHash)
        message += localizedStoreString(
            pending.canSpeedUp
                ? " Use Speed Up to resend with higher fees or Cancel to submit a 0-value self-transfer using the same nonce."
                : " Use Cancel to submit a 0-value self-transfer using the same nonce. A token transfer cannot be rebuilt from its record, so it cannot be sped up.")
        return message
    }
}
