import Foundation
extension AppState {
    func resetSelectedData(scopes: Set<ResetScope>) async {
        guard !scopes.isEmpty else { return }
        guard
            await authenticateForSensitiveAction(.resetData,
                reason: AppLocalization.string("Authenticate to reset wallet data")
            )
        else {
            return
        }
        await awaitPendingSettingCommands()
        await walletMutationTask?.value
        await awaitPendingAddressBookCommands()
        let outcome: ResetOutcome
        do {
            outcome = try await self.bridge.resetData(scopes: Array(scopes))
        } catch {
            appendOperationalLog(.error, category: "Reset", message: String(describing: error))
            return
        }
        let epoch = beginCoreStateRead()
        applyCoreState(outcome.state, epoch: epoch)
        await refreshTransactionProjection()
        let plan = outcome.plan
        if plan.resetWalletsAndSecrets { await resetWalletsAndSecretsState() }
        if plan.resetHistoryAndCache { await resetHistoryAndCacheState() }
        if plan.resetSettingsAndEndpoints { await resetSettingsAndEndpointsState() }
        if plan.resetProviderState { await resetProviderState() }
        if plan.clearNetworkAndTransportCaches { clearNetworkAndTransportCaches() }
    }
    private func resetWalletsAndSecretsState() async {
        receiveWalletId = ""
        receiveHoldingKey = ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
        walletPendingDeletion = nil
        editingWalletId = nil
        sendWalletId = ""
        sendHoldingKey = ""
        sendAmount = ""
        sendAddress = ""
        sendError = nil
        sendDestinationRiskWarning = nil
        sendDestinationInfoMessage = nil
        pendingHighRiskSendReasons = []
        isShowingHighRiskSendConfirmation = false
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEvmFees = false
        customEvmMaxFeeGwei = ""
        customEvmPriorityFeeGwei = ""
        evmManualNonceEnabled = false
        evmManualNonce = ""
        isPreparingReplacementContext = false
        lastSentTransaction = nil
        sendPreviewStore.resetAll()
        sendingChains = []
        preparingChains = []
        sendPreviewRequestId = UUID()
        sendDestinationProbeRequestId = UUID()
        pendingSendReview = nil
        // Core prunes status trackers against committed history on the next
        // maintenance sweep, including when there is no remaining work.
        isShowingWalletImporter = false
        isShowingAddWalletEntry = false
        isShowingSendSheet = false
        isShowingReceiveSheet = false
        importError = nil
        isImportingWallet = false
        cancelWalletImport()
    }
    private func resetHistoryAndCacheState() async {
        chainDiagnosticsState.historyRunByChain = [:]
        chainDiagnosticsState.endpointHealthByChain = [:]
        selfTests = [:]
        // Nothing clears `isRunning`/`isChecking` per chain below this point:
        // the `historyRunByChain` and `endpointHealthByChain` subscripts insert
        // a default row on write, so touching them after the maps are emptied
        // puts rows back rather than clearing any.
        isLoadingMoreOnChainHistory = false
        lastImportedDiagnosticsBundle = nil
        lastPendingTransactionRefreshAt = nil
        isRefreshingLivePrices = false
        // Ten lines naming the five UTXO chains, which is the map itself.
        utxoRescanStateByChain = [:]
        await refreshTransactionProjection()
    }
    private func resetSettingsAndEndpointsState() async {
        // The five this platform keeps for itself: hiding balances, appearance,
        // Face ID, auto-lock and biometric-gated sends. No other front end has
        // a use for them, so core has no default to be the copy of. Each
        // writes itself back to `UserDefaults` as it changes.
        preferences.resetToDefaults()
    }
    private func resetProviderState() async {
        clearNetworkAndTransportCaches()
    }
    private func clearNetworkAndTransportCaches() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        let credentialStorage = URLCredentialStorage.shared
        for (protectionSpace, credentialsByUser) in credentialStorage.allCredentials {
            for credential in credentialsByUser.values { credentialStorage.remove(credential, for: protectionSpace) }
        }
    }
}
