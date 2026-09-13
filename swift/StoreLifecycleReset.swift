import Foundation
import UIKit
extension AppState {
    func restorePersistedRuntimeConfigurationAndState() {
        // The eighteen settings core owns are not seeded here. They arrive with
        // `open_state`, through `applyCoreState`.
        suppressWalletSideEffects = true
        // Price alerts + address book are loaded async via
        // `reloadPersistedStateFromSQLite()` from the typed Rust SQLite store.
        // The known-token list is core state and arrives with `open_state`,
        // which seeds the catalog itself — a second copy assembled here would
        // race that and usually win.
        rebuildTokenPreferenceDerivedState()
        livePrices = [:]
        // Keypool, owned addresses and operational events all load from core in
        // `reloadPersistedStateFromSQLite()`. They used to be seeded here from
        // UserDefaults first, but nothing has written those keys since the move
        // to SQLite — the seed could only ever supply stale indices.
        // Pinned dashboard assets are a core setting now; they arrive with
        // the rest of `CoreAppState`. The UserDefaults key they used to be
        // seeded from has had no writer since that move.
        suppressWalletSideEffects = false
        applyWalletCollectionSideEffects()
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        startNetworkPathMonitorIfNeeded()
        // Tor preferences arrive with core settings through adoptAppSettings.
        startTorIfEnabled()
    }
    func clearPersistedSecureDataOnFreshInstallIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.installMarkerDefaultsKey) { return }
        UserDefaults.standard.set(true, forKey: Self.installMarkerDefaultsKey)
    }
    func resetSelectedData(scopes: Set<ResetScope>) async {
        guard !scopes.isEmpty else { return }
        guard
            await authenticateForSensitiveAction(
                reason: "Authenticate to reset wallet data", allowWhenAuthenticationUnavailable: true
            )
        else {
            return
        }
        appSettingsPersist.cancel()
        await walletMutationTask?.value
        await awaitPendingAddressBookCommands()
        let outcome: ResetOutcome
        do {
            outcome = try await WalletServiceBridge.shared.resetData(scopes: scopes.map(\.rawValue))
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
        UserDefaults.standard.set(true, forKey: Self.installMarkerDefaultsKey)
    }
    private func resetWalletsAndSecretsState() async {
        clearWalletSecretIndex()
        discoveredUTXOAddressesByChain = [:]
        receiveWalletID = ""
        receiveHoldingKey = ""
        receiveResolvedAddress = ""
        isResolvingReceiveAddress = false
        walletPendingDeletion = nil
        editingWalletID = nil
        sendWalletID = ""
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
        sendAdvancedMode = false
        sendUTXOMaxInputCount = 0
        sendEnableRBF = true
        sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange
        evmManualNonceEnabled = false
        evmManualNonce = ""
        isPreparingReplacementContext = false
        lastSentTransaction = nil
        sendPreviewStore.resetAll()
        sendingChains = []
        preparingChains = []
        pendingSendPreviewRefreshChains = []
        pendingSelfSendConfirmation = nil
        activeEthereumSendWalletIDs = []
        lastSendDestinationProbeKey = nil
        lastSendDestinationProbeWarning = nil
        lastSendDestinationProbeInfoMessage = nil
        bypassHighRiskSendConfirmation = false
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
        tronLastSendErrorDetails = nil
        tronLastSendErrorAt = nil
        lastImportedDiagnosticsBundle = nil
        lastPendingTransactionRefreshAt = nil
        isRefreshingLivePrices = false
        isRefreshingChainBalances = false
        allowsBalanceNetworkRefresh = false
        isRefreshingPendingTransactions = false
        lastLivePriceRefreshAt = nil
        lastChainBalanceRefreshAt = nil
        lastHistoryRefreshAtByChain = [:]
        // Ten lines naming the five UTXO chains, which is the map itself.
        utxoRescanStateByChain = [:]
        do {
            try await rebuildNormalizedHistoryIndex()
            historyReadError = nil
        } catch {
            historyReadError = localizedStoreString("Unable to read transaction history. Existing records have been kept.")
        }
    }
    private func resetSettingsAndEndpointsState() async {
        // The five this platform keeps for itself: hiding balances, appearance,
        // Face ID, auto-lock and biometric-gated sends. No other front end has
        // a use for them, so core has no default to be the copy of.
        preferences.resetToDefaults()
        persistPlatformPreferences()
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
