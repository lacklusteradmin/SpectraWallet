import Foundation
import UIKit
extension AppState {
    func restorePersistedRuntimeConfigurationAndState() {
        // The eighteen settings core owns are not seeded here. They arrive with
        // `open_state`, through `applyCoreState`.
        //
        // What stood here was a `UserDefaults` read per setting — the provider,
        // the fee priorities, the endpoints, the notification toggles and the
        // thresholds — and *nothing has written those keys* since settings
        // moved into SQLite. Harmless while the values only fed a blob this
        // side also owned; not harmless once core owns them, because each read
        // lands in a `didSet` that commits, so every launch would have sent
        // core a stale seed before core's own state arrived.
        if let storedFiatRates = UserDefaults.standard.dictionary(forKey: Self.fiatRatesFromUSDDefaultsKey) as? [String: Double] {
            fiatRatesFromUSD = storedFiatRates
        }
        fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        suppressWalletSideEffects = true
        // Price alerts + address book are loaded async via
        // `reloadPersistedStateFromSQLite()` from the typed Rust SQLite store.
        // Built-in tokens only. The user's tracked list is core state and
        // arrives in `reloadPersistedStateFromSQLite()`; reading a second copy
        // from UserDefaults here would race it and usually win.
        tokenPreferences = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        rebuildTokenPreferenceDerivedState()
        livePrices = loadPersistedLivePrices()
        // Keypool, owned addresses and operational events all load from core in
        // `reloadPersistedStateFromSQLite()`. They used to be seeded here from
        // UserDefaults first, but nothing has written those keys since the move
        // to SQLite — the seed could only ever supply stale indices.
        // `syncChainOwnedAddressManagementState` runs there too: it reserves
        // receive indices, so it must not run before core has loaded the
        // keypool or it would reserve against an empty table.
        if let storedAssetDisplayDecimalsByChain = loadAssetDisplayDecimalsByChain() {
            assetDisplayDecimalsByChain = storedAssetDisplayDecimalsByChain
        }
        // Pinned dashboard assets are a core setting now; they arrive with
        // the rest of `CoreAppState`. The UserDefaults key they used to be
        // seeded from has had no writer since that move.
        suppressWalletSideEffects = false
        applyWalletCollectionSideEffects()
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        startNetworkPathMonitorIfNeeded()
        resetLargeMovementAlertBaseline()
        // Restore Tor preferences. Booleans default to false in UserDefaults, so
        // we only overwrite if a key was explicitly stored. `torEnabled` defaults
        // to true on first install — the guard prevents silently forcing it off.
        if UserDefaults.standard.object(forKey: Self.torEnabledDefaultsKey) != nil {
            torEnabled = UserDefaults.standard.bool(forKey: Self.torEnabledDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.torUseCustomProxyDefaultsKey) != nil {
            torUseCustomProxy = UserDefaults.standard.bool(forKey: Self.torUseCustomProxyDefaultsKey)
        }
        if let addr = UserDefaults.standard.string(forKey: Self.torCustomProxyAddressDefaultsKey), !addr.isEmpty {
            torCustomProxyAddress = addr
        }
        if UserDefaults.standard.object(forKey: Self.torKillSwitchDefaultsKey) != nil {
            torKillSwitch = UserDefaults.standard.bool(forKey: Self.torKillSwitchDefaultsKey)
        }
        startTorIfEnabled()
    }
    func clearPersistedSecureDataOnFreshInstallIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.installMarkerDefaultsKey) { return }
        let persistedWalletIDs = wallets.map(\.id)
        for walletID in persistedWalletIDs { deleteWalletSecrets(for: walletID) }
        SecureStore.deleteValue(for: Self.walletsAccount)
        SecureStore.deleteValue(for: Self.walletsCoreSnapshotAccount)
        clearWalletSecretIndex()
        UserDefaults.standard.set(true, forKey: Self.installMarkerDefaultsKey)
    }
    func resetWalletData() async { await resetSelectedData(scopes: Set(ResetScope.allCases)) }
    func resetSelectedData(scopes: Set<ResetScope>) async {
        guard !scopes.isEmpty else { return }
        guard
            await authenticateForSensitiveAction(
                reason: "Authenticate to reset wallet data", allowWhenAuthenticationUnavailable: true
            )
        else {
            return
        }
        let plan = coreResetDispatch(scopes: scopes.map(\.rawValue))
        if plan.resetWalletsAndSecrets { resetWalletsAndSecretsState() }
        if plan.resetHistoryAndCache { await resetHistoryAndCacheState() }
        if plan.resetAlertsAndContacts { resetAlertsAndContactsState() }
        if plan.resetSettingsAndEndpoints { resetSettingsAndEndpointsState() }
        if plan.resetDashboardCustomization { resetDashboardCustomizationState() }
        if plan.resetProviderState { await resetProviderState() }
        if plan.clearNetworkAndTransportCaches { clearNetworkAndTransportCaches() }
        UserDefaults.standard.set(true, forKey: Self.installMarkerDefaultsKey)
    }
    private func resetWalletsAndSecretsState() {
        let existingWalletIDs = wallets.map(\.id)
        existingWalletIDs.forEach { deleteWalletSecrets(for: $0) }
        SecureStore.deleteValue(for: Self.walletsAccount)
        SecureStore.deleteValue(for: Self.walletsCoreSnapshotAccount)
        UserDefaults.standard.removeObject(forKey: Self.walletsAccount)
        clearWalletSecretIndex()
        clearAllWalletsDetached()
        discoveredUTXOAddressesByChain = [:]
        receiveWalletID = ""
        receiveChainName = ""
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
        useCustomEthereumFees = false
        customEthereumMaxFeeGwei = ""
        customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false
        sendUTXOMaxInputCount = 0
        sendEnableRBF = true
        sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange
        ethereumManualNonceEnabled = false
        ethereumManualNonce = ""
        isPreparingEthereumReplacementContext = false
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
        cachedResolvedENSAddresses = [:]
        bypassHighRiskSendConfirmation = false
        // Keeping none of them is the clear; core's second name for it is gone.
        Task { try? await WalletServiceBridge.shared.retainStatusTrackers(ids: []) }
        isShowingWalletImporter = false
        isShowingAddWalletEntry = false
        isShowingSendSheet = false
        isShowingReceiveSheet = false
        importError = nil
        isImportingWallet = false
        cancelWalletImport()
    }
    private func resetHistoryAndCacheState() async {
        Task { try? await WalletServiceBridge.shared.clearAllHistoryRecords() }
        UserDefaults.standard.removeObject(forKey: Self.chainSyncStateDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.operationalLogsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.chainKeypoolDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.chainOwnedAddressMapDefaultsKey)
        clearAllTransactions()
        resetAllHistoryPagination()
        // `diagnosticsClearAll` empties the whole Rust-owned registry, so the
        // per-chain history clears this used to spell out — twenty-two chains
        // times four lines, described in a comment as belt-and-suspenders over
        // exactly this call — said nothing it does not. Nor did the two lines
        // that followed it for Tron and Solana: those tables read and write
        // through the same registry, so the call had already emptied them.
        diagnosticsClearAll()
        chainDiagnosticsState.historyRunByChain = [:]
        chainDiagnosticsState.endpointHealthByChain = [:]
        diagnostics.chainDegradedMessages = [:]
        diagnostics.lastGoodChainSyncByName = [:]
        Task { try? await WalletServiceBridge.shared.clearOperationalEvents(chainName: nil) }
        selfTests = [:]
        diagnostics.clearOperationalLogs()
        // A thirty-two entry key-path list stood here setting `isRunning` and
        // `isChecking` to false on sixteen named chains — two lines *after*
        // `historyRunByChain` and `endpointHealthByChain` were emptied. Both
        // subscripts insert a default row on write, so the loop did not clear
        // anything: it put sixteen default rows back into maps the reset had
        // just emptied. Deleting it resets more, not less, and for every chain
        // rather than the sixteen someone last remembered.
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
        lastObservedPortfolioTotalUSD = nil
        // Ten lines naming the five UTXO chains, which is the map itself.
        utxoRescanStateByChain = [:]
        await rebuildNormalizedHistoryIndex()
    }
    private func resetAlertsAndContactsState() {
        // Core-owned: assigning sends `SetPriceAlerts`, which clears the store.
        priceAlerts = []
        // Core-owned: clear by command so the store and the mirror agree.
        let contactIDs = addressBook.map(\.id)
        Task { @MainActor [weak self] in
            for id in contactIDs { self?.removeAddressBookEntry(id: id) }
        }
    }
    private func resetDashboardCustomizationState() { resetPinnedDashboardAssets() }
    private func resetSettingsAndEndpointsState() {
        // The settings core owns are reset by assigning the properties below,
        // which commit. The `UserDefaults` keys that used to be cleared here —
        // one per setting, twenty-two of them — have had no writer since
        // settings moved into SQLite, so removing them removed nothing.
        UserDefaults.standard.removeObject(forKey: Self.tokenPreferencesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.fiatRatesFromUSDDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.livePricesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.assetDisplayDecimalsByChainDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.torEnabledDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.torUseCustomProxyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.torCustomProxyAddressDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.torKillSwitchDefaultsKey)
        tokenPreferences = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        livePrices = [:]
        quoteRefreshError = nil
        fiatRatesRefreshError = nil
        pricingProvider = .coinGecko
        // Core-owned: reset by command so the store and the mirror agree.
        Task { @MainActor [weak self] in await self?.setFiatCurrency(.usd) }
        fiatRateProvider = .openER
        assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain()
        ethereumRPCEndpoint = ""
        etherscanAPIKey = ""
        moneroBackendBaseURL = ""
        moneroBackendAPIKey = ""
        for family in ["bitcoin", "ethereum", "dogecoin"] { selectNetworkChain(family) }
        bitcoinEsploraEndpoints = ""
        bitcoinStopGap = 10
        clearFeePriorities()
        preferences.resetToDefaults()
        persistPlatformPreferences()
        backgroundSyncProfile = .balanced
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
