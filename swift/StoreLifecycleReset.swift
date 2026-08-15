import Foundation
import UIKit
extension AppState {
    func restorePersistedRuntimeConfigurationAndState() {
        if let storedProvider = UserDefaults.standard.string(forKey: Self.pricingProviderDefaultsKey),
            let pricingProvider = PricingProvider(rawValue: storedProvider)
        {
            self.pricingProvider = pricingProvider
        }
        if let storedBitcoinNetworkMode = UserDefaults.standard.string(forKey: Self.bitcoinNetworkModeDefaultsKey),
            let bitcoinNetworkMode = BitcoinNetworkMode(rawValue: storedBitcoinNetworkMode)
        {
            self.bitcoinNetworkMode = bitcoinNetworkMode
        }
        if let storedDogecoinNetworkMode = UserDefaults.standard.string(forKey: Self.dogecoinNetworkModeDefaultsKey),
            let dogecoinNetworkMode = DogecoinNetworkMode(rawValue: storedDogecoinNetworkMode)
        {
            self.dogecoinNetworkMode = dogecoinNetworkMode
        }
        if let storedEthereumNetworkMode = UserDefaults.standard.string(forKey: Self.ethereumNetworkModeDefaultsKey),
            let ethereumNetworkMode = EthereumNetworkMode(rawValue: storedEthereumNetworkMode)
        {
            self.ethereumNetworkMode = ethereumNetworkMode
        }
        if let storedBitcoinFeePriority = UserDefaults.standard.string(forKey: Self.bitcoinFeePriorityDefaultsKey),
            let bitcoinFeePriority = BitcoinFeePriority(rawValue: storedBitcoinFeePriority)
        {
            self.bitcoinFeePriority = bitcoinFeePriority
        }
        if UserDefaults.standard.object(forKey: Self.bitcoinStopGapDefaultsKey) != nil {
            self.bitcoinStopGap = UserDefaults.standard.integer(forKey: Self.bitcoinStopGapDefaultsKey)
        }
        self.bitcoinEsploraEndpoints = UserDefaults.standard.string(forKey: Self.bitcoinEsploraEndpointsDefaultsKey) ?? ""
        if let storedFiatRateProvider = UserDefaults.standard.string(forKey: Self.fiatRateProviderDefaultsKey),
            let fiatRateProvider = FiatRateProvider(rawValue: storedFiatRateProvider)
        {
            self.fiatRateProvider = fiatRateProvider
        }
        if let storedFiatRates = UserDefaults.standard.dictionary(forKey: Self.fiatRatesFromUSDDefaultsKey) as? [String: Double] {
            fiatRatesFromUSD = storedFiatRates
        }
        fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        if let storedDogecoinFeePriority = UserDefaults.standard.string(forKey: Self.dogecoinFeePriorityDefaultsKey),
            let dogecoinFeePriority = DogecoinFeePriority(rawValue: storedDogecoinFeePriority)
        {
            self.dogecoinFeePriority = dogecoinFeePriority
        }
        ethereumRPCEndpoint = UserDefaults.standard.string(forKey: Self.ethereumRPCEndpointDefaultsKey) ?? ""
        etherscanAPIKey = UserDefaults.standard.string(forKey: Self.etherscanAPIKeyDefaultsKey) ?? ""
        moneroBackendBaseURL = UserDefaults.standard.string(forKey: MoneroBalanceService.backendBaseURLDefaultsKey) ?? ""
        moneroBackendAPIKey = UserDefaults.standard.string(forKey: MoneroBalanceService.backendAPIKeyDefaultsKey) ?? ""
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
        restoreBoolPreference(Self.hideBalancesDefaultsKey, \.hideBalances)
        restoreBoolPreference(Self.useFaceIDDefaultsKey, \.useFaceID)
        restoreBoolPreference(Self.useAutoLockDefaultsKey, \.useAutoLock)
        restoreBoolPreference(Self.useStrictRPCOnlyDefaultsKey, \.useStrictRPCOnly)
        restoreBoolPreference(Self.requireBiometricForSendActionsDefaultsKey, \.requireBiometricForSendActions)
        restoreBoolPreference(Self.usePriceAlertsDefaultsKey, \.usePriceAlerts)
        restoreBoolPreference(Self.useTransactionStatusNotificationsDefaultsKey, \.useTransactionStatusNotifications)
        restoreBoolPreference(Self.useLargeMovementNotificationsDefaultsKey, \.useLargeMovementNotifications)
        if UserDefaults.standard.object(forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey) != nil {
            preferences.automaticRefreshFrequencyMinutes = UserDefaults.standard.integer(
                forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey)
        } else if let rawSyncProfile = UserDefaults.standard.string(forKey: Self.backgroundSyncProfileDefaultsKey),
            let profile = BackgroundSyncProfile(rawValue: rawSyncProfile)
        {
            backgroundSyncProfile = profile
            switch profile {
            case .conservative: preferences.automaticRefreshFrequencyMinutes = 10
            case .balanced, .aggressive: preferences.automaticRefreshFrequencyMinutes = 5
            }
        }
        if UserDefaults.standard.object(forKey: Self.largeMovementAlertPercentThresholdDefaultsKey) != nil {
            preferences.largeMovementAlertPercentThreshold = UserDefaults.standard.double(
                forKey: Self.largeMovementAlertPercentThresholdDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.largeMovementAlertUSDThresholdDefaultsKey) != nil {
            preferences.largeMovementAlertUSDThreshold = UserDefaults.standard.double(
                forKey: Self.largeMovementAlertUSDThresholdDefaultsKey)
        }
        if let storedFeePrioritySelections = UserDefaults.standard.dictionary(forKey: Self.selectedFeePriorityOptionsByChainDefaultsKey)
            as? [String: String]
        {
            selectedFeePriorityOptionRawByChain = storedFeePrioritySelections
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
    private func restoreBoolPreference(_ key: String, _ path: ReferenceWritableKeyPath<AppUserPreferences, Bool>) {
        guard UserDefaults.standard.object(forKey: key) != nil else { return }
        preferences[keyPath: path] = UserDefaults.standard.bool(forKey: key)
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
        if plan.resetHistoryAndCache { resetHistoryAndCacheState() }
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
        Task { try? await WalletServiceBridge.shared.clearStatusTrackers() }
        isShowingWalletImporter = false
        isShowingAddWalletEntry = false
        isShowingSendSheet = false
        isShowingReceiveSheet = false
        importError = nil
        isImportingWallet = false
        cancelWalletImport()
    }
    private func resetHistoryAndCacheState() {
        Task { try? await WalletServiceBridge.shared.clearAllHistoryRecords() }
        UserDefaults.standard.removeObject(forKey: Self.chainSyncStateDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.operationalLogsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.chainKeypoolDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.chainOwnedAddressMapDefaultsKey)
        clearAllTransactions()
        resetAllHistoryPagination()
        dogecoinHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Dogecoin"].lastUpdatedAt = nil
        self[endpointHealthFor: "Dogecoin"].results = []
        self[endpointHealthFor: "Dogecoin"].lastUpdatedAt = nil
        ethereumHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Ethereum"].lastUpdatedAt = nil
        self[endpointHealthFor: "Ethereum"].results = []
        self[endpointHealthFor: "Ethereum"].lastUpdatedAt = nil
        arbitrumHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Arbitrum"].lastUpdatedAt = nil
        self[endpointHealthFor: "Arbitrum"].results = []
        self[endpointHealthFor: "Arbitrum"].lastUpdatedAt = nil
        optimismHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Optimism"].lastUpdatedAt = nil
        self[endpointHealthFor: "Optimism"].results = []
        self[endpointHealthFor: "Optimism"].lastUpdatedAt = nil
        etcHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Ethereum Classic"].lastUpdatedAt = nil
        self[endpointHealthFor: "Ethereum Classic"].results = []
        self[endpointHealthFor: "Ethereum Classic"].lastUpdatedAt = nil
        bnbHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "BNB Chain"].lastUpdatedAt = nil
        self[endpointHealthFor: "BNB Chain"].results = []
        self[endpointHealthFor: "BNB Chain"].lastUpdatedAt = nil
        avalancheHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Avalanche"].lastUpdatedAt = nil
        self[endpointHealthFor: "Avalanche"].results = []
        self[endpointHealthFor: "Avalanche"].lastUpdatedAt = nil
        hyperliquidHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Hyperliquid"].lastUpdatedAt = nil
        self[endpointHealthFor: "Hyperliquid"].results = []
        self[endpointHealthFor: "Hyperliquid"].lastUpdatedAt = nil
        tronHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Tron"].lastUpdatedAt = nil
        self[endpointHealthFor: "Tron"].results = []
        self[endpointHealthFor: "Tron"].lastUpdatedAt = nil
        solanaHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Solana"].lastUpdatedAt = nil
        self[endpointHealthFor: "Solana"].results = []
        self[endpointHealthFor: "Solana"].lastUpdatedAt = nil
        self[simpleHistoryFor: "XRP Ledger"] = [:]
        self[historyRunFor: "XRP Ledger"].lastUpdatedAt = nil
        self[endpointHealthFor: "XRP Ledger"].results = []
        self[endpointHealthFor: "XRP Ledger"].lastUpdatedAt = nil
        self[simpleHistoryFor: "Monero"] = [:]
        self[historyRunFor: "Monero"].lastUpdatedAt = nil
        self[endpointHealthFor: "Monero"].results = []
        self[endpointHealthFor: "Monero"].lastUpdatedAt = nil
        self[simpleHistoryFor: "Sui"] = [:]
        self[historyRunFor: "Sui"].lastUpdatedAt = nil
        self[endpointHealthFor: "Sui"].results = []
        self[endpointHealthFor: "Sui"].lastUpdatedAt = nil
        self[simpleHistoryFor: "NEAR"] = [:]
        self[historyRunFor: "NEAR"].lastUpdatedAt = nil
        self[endpointHealthFor: "NEAR"].results = []
        self[endpointHealthFor: "NEAR"].lastUpdatedAt = nil
        self[simpleHistoryFor: "Polkadot"] = [:]
        self[historyRunFor: "Polkadot"].lastUpdatedAt = nil
        self[endpointHealthFor: "Polkadot"].results = []
        self[endpointHealthFor: "Polkadot"].lastUpdatedAt = nil
        self[simpleHistoryFor: "Cardano"] = [:]
        self[historyRunFor: "Cardano"].lastUpdatedAt = nil
        self[endpointHealthFor: "Cardano"].results = []
        self[endpointHealthFor: "Cardano"].lastUpdatedAt = nil
        bitcoinCashHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Bitcoin Cash"].lastUpdatedAt = nil
        self[endpointHealthFor: "Bitcoin Cash"].results = []
        self[endpointHealthFor: "Bitcoin Cash"].lastUpdatedAt = nil
        bitcoinSVHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Bitcoin SV"].lastUpdatedAt = nil
        self[endpointHealthFor: "Bitcoin SV"].results = []
        self[endpointHealthFor: "Bitcoin SV"].lastUpdatedAt = nil
        bitcoinHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Bitcoin"].lastUpdatedAt = nil
        self[endpointHealthFor: "Bitcoin"].results = []
        self[endpointHealthFor: "Bitcoin"].lastUpdatedAt = nil
        litecoinHistoryDiagnosticsByWallet = [:]
        self[historyRunFor: "Litecoin"].lastUpdatedAt = nil
        // Belt-and-suspenders: drop the entire Rust-owned diagnostics registry.
        diagnosticsClearAll()
        self[endpointHealthFor: "Litecoin"].results = []
        self[endpointHealthFor: "Litecoin"].lastUpdatedAt = nil
        diagnostics.chainDegradedMessages = [:]
        diagnostics.lastGoodChainSyncByName = [:]
        Task { try? await WalletServiceBridge.shared.clearOperationalEvents(chainName: nil) }
        selfTests = [:]
        diagnostics.clearOperationalLogs()
        for kp: ReferenceWritableKeyPath<AppState, Bool> in [
            \.[historyRunFor: "Dogecoin"].isRunning, \.self[endpointHealthFor: "Dogecoin"].isChecking,
            \.[historyRunFor: "Ethereum"].isRunning, \.self[endpointHealthFor: "Ethereum"].isChecking,
            \.[historyRunFor: "Arbitrum"].isRunning, \.self[endpointHealthFor: "Arbitrum"].isChecking,
            \.[historyRunFor: "Optimism"].isRunning, \.self[endpointHealthFor: "Optimism"].isChecking,
            \.[historyRunFor: "Ethereum Classic"].isRunning, \.self[endpointHealthFor: "Ethereum Classic"].isChecking,
            \.[historyRunFor: "BNB Chain"].isRunning, \.self[endpointHealthFor: "BNB Chain"].isChecking,
            \.[historyRunFor: "Avalanche"].isRunning, \.self[endpointHealthFor: "Avalanche"].isChecking,
            \.[historyRunFor: "Hyperliquid"].isRunning, \.self[endpointHealthFor: "Hyperliquid"].isChecking,
            \.[historyRunFor: "Tron"].isRunning, \.self[endpointHealthFor: "Tron"].isChecking,
            \.[historyRunFor: "Solana"].isRunning, \.self[endpointHealthFor: "Solana"].isChecking,
            \.[historyRunFor: "XRP Ledger"].isRunning, \.self[endpointHealthFor: "XRP Ledger"].isChecking,
            \.[historyRunFor: "Monero"].isRunning, \.self[endpointHealthFor: "Monero"].isChecking,
            \.[historyRunFor: "Sui"].isRunning, \.self[endpointHealthFor: "Sui"].isChecking,
            \.[historyRunFor: "Cardano"].isRunning, \.self[endpointHealthFor: "Cardano"].isChecking,
            \.[historyRunFor: "Bitcoin"].isRunning, \.self[endpointHealthFor: "Bitcoin"].isChecking,
            \.[historyRunFor: "Litecoin"].isRunning, \.self[endpointHealthFor: "Litecoin"].isChecking,
        ] { self[keyPath: kp] = false }
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
        isRunningBitcoinRescan = false
        bitcoinRescanLastRunAt = nil
        isRunningBitcoinCashRescan = false
        bitcoinCashRescanLastRunAt = nil
        isRunningBitcoinSVRescan = false
        bitcoinSVRescanLastRunAt = nil
        isRunningLitecoinRescan = false
        litecoinRescanLastRunAt = nil
        isRunningDogecoinRescan = false
        dogecoinRescanLastRunAt = nil
        rebuildNormalizedHistoryIndex()
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
        UserDefaults.standard.removeObject(forKey: Self.tokenPreferencesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.pricingProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.fiatRateProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.fiatRatesFromUSDDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.livePricesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.ethereumRPCEndpointDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.etherscanAPIKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.ethereumNetworkModeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MoneroBalanceService.backendBaseURLDefaultsKey)
        UserDefaults.standard.removeObject(forKey: MoneroBalanceService.backendAPIKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.bitcoinNetworkModeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.bitcoinEsploraEndpointsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.bitcoinStopGapDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.bitcoinFeePriorityDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.dogecoinFeePriorityDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedFeePriorityOptionsByChainDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.hideBalancesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.assetDisplayDecimalsByChainDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.useFaceIDDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.useAutoLockDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.useStrictRPCOnlyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.requireBiometricForSendActionsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.usePriceAlertsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.useTransactionStatusNotificationsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.useLargeMovementNotificationsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.backgroundSyncProfileDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.largeMovementAlertPercentThresholdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.largeMovementAlertUSDThresholdDefaultsKey)
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
        ethereumNetworkMode = .mainnet
        moneroBackendBaseURL = ""
        moneroBackendAPIKey = ""
        bitcoinNetworkMode = .mainnet
        bitcoinEsploraEndpoints = ""
        bitcoinStopGap = 10
        bitcoinFeePriority = .normal
        dogecoinFeePriority = .normal
        selectedFeePriorityOptionRawByChain = [:]
        preferences.resetToDefaults()
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
