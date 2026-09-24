import Foundation
import SwiftUI
@MainActor
extension AppState {
    func beginSend() {
        guard let firstWallet = sendEnabledWallets.first else { return }
        sendFlow.walletId = firstWallet.id
        sendFlow.holdingKey = availableSendCoins(for: sendFlow.walletId).first?.holdingKey ?? ""
        sendFlow.resetComposer()
        syncSendAssetSelection()
        sendFlow.isPresented = true
    }
    func syncSendAssetSelection() {
        sendFlow.destinationProbeRequestId = UUID()
        let availableHoldingKeys = availableSendCoins(for: sendFlow.walletId).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendFlow.holdingKey) { sendFlow.holdingKey = availableHoldingKeys.first ?? "" }
        // Keep EIP-1559 fees and manual nonce when switching within the EVM
        // family; clear them when leaving it.
        if selectedSendCoin?.isEVMChain != true {
            sendFlow.useCustomEvmFees = false; sendFlow.customEvmMaxFeeGwei = ""; sendFlow.customEvmPriorityFeeGwei = "";
            sendFlow.evmManualNonceEnabled = false; sendFlow.evmManualNonce = ""
        }
        sendFlow.invalidateSession()
        sendFlow.clearPreview()
        sendFlow.destinationRiskWarning = nil; sendFlow.destinationInfoMessage = nil; sendFlow.isCheckingDestination = false
    }
    func cancelSend() { sendFlow.isPresented = false; sendFlow.resetComposer() }
    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendFlow.walletId).first(where: { $0.holdingKey == sendFlow.holdingKey })
    }
    var sendAmountDecimals: UInt32? {
        guard let coin = selectedSendCoin else { return nil }
        return assetPrecision?.byDeploymentId[coin.holdingKey]
    }
    var sendAmountIsValid: Bool {
        guard let decimals = sendAmountDecimals else { return false }
        return isValidAmountInput(text: sendFlow.amount, maxDecimals: decimals)
    }
    // A provisional quote can load before the user types; it never changes the
    // amount field and is replaced by a quote for the entered amount.
    var sendPreviewAmountInput: String {
        guard sendFlow.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let coin = selectedSendCoin, let decimals = sendAmountDecimals else { return sendFlow.amount }
        return sendAmountShortcut(maximum: coin.amount, decimals: decimals, percentage: 10) ?? "0"
    }
    /// The quote core made for the selected holding, if it is current.
    var sendQuote: OwnedSendPreview? {
        guard let coin = selectedSendCoin else { return nil }
        return sendFlow.previewStore.quote(walletId: sendFlow.walletId, coin: coin)
    }
    /// The quote for the amount on screen. A quote for another amount — the
    /// provisional one, or one still in flight — says nothing about this one.
    var sendQuoteForEnteredAmount: OwnedSendPreview? {
        guard let quote = sendQuote,
              quote.amount == sendFlow.amount.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return quote
    }
    func sendShortcutAmount(percentage: UInt32) -> String? {
        guard !sendFlow.isPreparingPreview else { return nil }
        return sendQuote?.shortcuts[percentage]
    }
    func sendPreviewDetails(for coin: Coin) -> SendPreviewDetails? {
        sendFlow.previewStore.quote(walletId: sendFlow.walletId, coin: coin)?.details
    }
    private var parsedCustomEvmFees: Result<EvmCustomFeeConfiguration, Error>? {
        // The toggle is cleared outside the EVM family; only EVM preview and
        // submit paths read these fees.
        guard sendFlow.useCustomEvmFees else { return nil }
        return Result {
            try parseEvmCustomFees(
                maxFeeGweiRaw: sendFlow.customEvmMaxFeeGwei,
                priorityFeeGweiRaw: sendFlow.customEvmPriorityFeeGwei)
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
        guard sendFlow.evmManualNonceEnabled else { return nil }
        return Int(try parseEvmNonce(raw: sendFlow.evmManualNonce))
    }
    func selectedWalletForSend() -> WalletView? { wallet(for: sendFlow.walletId) }
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
            $0.walletId.caseInsensitiveCompare(sendFlow.walletId) == .orderedSame
                && $0.chainId == selectedSendCoin.chainId
        }
    }
    func replaceableSend(forTransaction transactionId: String) -> ReplaceableSend? {
        replaceableSends.first {
            $0.transactionId.caseInsensitiveCompare(transactionId) == .orderedSame
        }
    }
    func prepareReplacementContext(cancel: Bool) async {
        guard let pending = replaceableSendForSelectedWallet else {
            sendFlow.error = localizedStoreString("No pending transaction found for this wallet.")
            return
        }
        await prepareReplacementContext(pending: pending, cancel: cancel)
    }
    func openReplacementComposer(for transactionId: String, cancel: Bool) async -> String? {
        guard let pending = replaceableSend(forTransaction: transactionId) else {
            let message = localizedStoreString(
                "This transaction is no longer pending, so replacement and cancel are unavailable.")
            sendFlow.error = message
            return message
        }
        selectedMainTab = .home
        await Task.yield()
        sendFlow.isPresented = true
        await prepareReplacementContext(pending: pending, cancel: cancel)
        return sendFlow.error
    }
    func prepareReplacementContext(pending: ReplaceableSend, cancel: Bool) async {
        sendFlow.invalidateSession()
        let session = sendFlow.session.id
        sendFlow.isPreparingReplacement = true
        defer { if sendFlow.session.id == session { sendFlow.isPreparingReplacement = false } }
        do {
            let draft = try await self.bridge.replacementDraft(
                transactionId: pending.transactionId, cancel: cancel)
            guard sendFlow.session.isCurrent(session) else { return }
            sendFlow.walletId = draft.walletId
            sendFlow.holdingKey = draft.holdingKey
            sendFlow.address = draft.destination
            sendFlow.amount = draft.amount
            sendFlow.evmManualNonceEnabled = true
            sendFlow.evmManualNonce = String(draft.nonce)
            sendFlow.useCustomEvmFees = true
            sendFlow.customEvmMaxFeeGwei = draft.maxFeeGwei
            sendFlow.customEvmPriorityFeeGwei = draft.priorityFeeGwei
            sendFlow.error = localizedStoreString(
                cancel ? "Cancellation context loaded. Review fees and tap Send." : "Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            guard sendFlow.session.isCurrent(session) else { return }
            sendFlow.error = AppLocalization.format("Unable to prepare replacement context: %@", error.localizedDescription)
        }
    }
    func prepareSpeedUpContext() async { await prepareReplacementContext(cancel: false) }
    func prepareCancelContext() async { await prepareReplacementContext(cancel: true) }
    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    func isValidAddress(_ address: String, on chain: Chain) -> Bool {
        isValidSendAddress(chainId: chain.id, address: address)
    }
    func normalizedAddress(_ address: String, on chain: Chain) -> String {
        normalizedSendAddress(chainId: chain.id, address: address)
    }
    /// The address this send is going to, from whatever is in the field.
    ///
    /// Core owns resolution; the optional address binds the visible review.
    func resolveSendDestination(input: String, on chain: Chain, expectedAddress: String? = nil) async throws -> SendDestinationResolution {
        try await self.bridge.resolveSendDestination(chainId: chain.id, input: input, expectedAddress: expectedAddress)
    }
    func clearHighRiskSendConfirmation() { sendFlow.isShowingHighRiskConfirmation = false }
    func confirmSigning(password: String?) async {
        sendFlow.isShowingHighRiskConfirmation = false
        await signPreparedSend(password: password)
    }

    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let requestId = UUID()
        sendFlow.destinationProbeRequestId = requestId
        let walletId = sendFlow.walletId
        let holdingKey = coin.holdingKey
        let input = sendFlow.address
        func isCurrent() -> Bool {
            !Task.isCancelled && sendFlow.destinationProbeRequestId == requestId
                && sendFlow.walletId == walletId && sendFlow.holdingKey == holdingKey && sendFlow.address == input
        }
        sendFlow.destinationRiskWarning = nil
        sendFlow.destinationInfoMessage = nil
        sendFlow.isCheckingDestination = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        defer { if sendFlow.destinationProbeRequestId == requestId { sendFlow.isCheckingDestination = false } }
        guard sendFlow.isCheckingDestination else { return }
        do {
            // Core resolves the typed input and identifies the stored deployment.
            // No ticker-based cache or cross-protocol address normalization lives here.
            let risk = try await self.bridge.sendDestinationRisk(
                walletId: walletId, holdingKey: holdingKey, destination: input)
            guard isCurrent() else { return }
            let messages = chainRiskProbeMessages(chainName: coin.chainName, symbol: coin.symbol,
                activity: risk.activity)
            sendFlow.destinationRiskWarning = messages.warning
            sendFlow.destinationInfoMessage = messages.info
        } catch {
            guard isCurrent() else { return }
            sendFlow.destinationInfoMessage = localizedStoreString("Unable to verify this address's activity. Try again later.")
        }
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
