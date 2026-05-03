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
        if let storedFiatCurrency = UserDefaults.standard.string(forKey: Self.selectedFiatCurrencyDefaultsKey),
            let selectedFiatCurrency = FiatCurrency(rawValue: storedFiatCurrency)
        {
            self.selectedFiatCurrency = selectedFiatCurrency
        }
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
        setWallets(loadPersistedWallets())
        // Price alerts + address book are loaded async via
        // `reloadPersistedStateFromSQLite()` from the typed Rust SQLite store.
        tokenPreferences = loadPersistedTokenPreferences()
        rebuildTokenPreferenceDerivedState()
        livePrices = loadPersistedLivePrices()
        chainKeypoolByChain = loadChainKeypoolState()
        chainOwnedAddressMapByChain = loadChainOwnedAddressMap()
        chainOperationalEventsByChain = loadChainOperationalEvents()
        syncChainOwnedAddressManagementState()
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
        let storedPins = (UserDefaults.standard.stringArray(forKey: Self.pinnedDashboardAssetSymbolsDefaultsKey) ?? []).map {
            $0.uppercased()
        }.filter { !$0.isEmpty }
        if !storedPins.isEmpty { cachedPinnedDashboardAssetSymbols = storedPins }
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
        let persistedWalletIDs = storedWalletIDs()
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
        let plan = corePlanResetDispatch(scopes: scopes.map(\.rawValue))
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
        setWallets([])
        chainKeypoolByChain = [:]
        chainOwnedAddressMapByChain = [:]
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
        sendPreviewStore.bitcoinSendPreview = nil
        sendPreviewStore.litecoinSendPreview = nil
        sendPreviewStore.ethereumSendPreview = nil
        sendPreviewStore.bitcoinCashSendPreview = nil
        sendPreviewStore.dogecoinSendPreview = nil
        sendPreviewStore.tronSendPreview = nil
        sendPreviewStore.solanaSendPreview = nil
        sendPreviewStore.xrpSendPreview = nil
        sendPreviewStore.moneroSendPreview = nil
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
        statusTrackingByTransactionID = [:]
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
        setTransactions([])
        resetAllHistoryPagination()
        bitcoinSelfTestResults = []
        bitcoinSelfTestsLastRunAt = nil
        bitcoinCashSelfTestResults = []
        bitcoinCashSelfTestsLastRunAt = nil
        bitcoinSVSelfTestResults = []
        bitcoinSVSelfTestsLastRunAt = nil
        litecoinSelfTestResults = []
        litecoinSelfTestsLastRunAt = nil
        dogecoinSelfTestResults = []
        dogecoinSelfTestsLastRunAt = nil
        dogecoinHistoryDiagnosticsByWallet = [:]
        dogecoinHistoryDiagnosticsLastUpdatedAt = nil
        dogecoinEndpointHealthResults = []
        dogecoinEndpointHealthLastUpdatedAt = nil
        ethereumSelfTestResults = []
        ethereumSelfTestsLastRunAt = nil
        ethereumHistoryDiagnosticsByWallet = [:]
        ethereumHistoryDiagnosticsLastUpdatedAt = nil
        ethereumEndpointHealthResults = []
        ethereumEndpointHealthLastUpdatedAt = nil
        arbitrumHistoryDiagnosticsByWallet = [:]
        arbitrumHistoryDiagnosticsLastUpdatedAt = nil
        arbitrumEndpointHealthResults = []
        arbitrumEndpointHealthLastUpdatedAt = nil
        optimismHistoryDiagnosticsByWallet = [:]
        optimismHistoryDiagnosticsLastUpdatedAt = nil
        optimismEndpointHealthResults = []
        optimismEndpointHealthLastUpdatedAt = nil
        etcHistoryDiagnosticsByWallet = [:]
        etcHistoryDiagnosticsLastUpdatedAt = nil
        etcEndpointHealthResults = []
        etcEndpointHealthLastUpdatedAt = nil
        bnbHistoryDiagnosticsByWallet = [:]
        bnbHistoryDiagnosticsLastUpdatedAt = nil
        bnbEndpointHealthResults = []
        bnbEndpointHealthLastUpdatedAt = nil
        avalancheHistoryDiagnosticsByWallet = [:]
        avalancheHistoryDiagnosticsLastUpdatedAt = nil
        avalancheEndpointHealthResults = []
        avalancheEndpointHealthLastUpdatedAt = nil
        hyperliquidHistoryDiagnosticsByWallet = [:]
        hyperliquidHistoryDiagnosticsLastUpdatedAt = nil
        hyperliquidEndpointHealthResults = []
        hyperliquidEndpointHealthLastUpdatedAt = nil
        tronHistoryDiagnosticsByWallet = [:]
        tronHistoryDiagnosticsLastUpdatedAt = nil
        tronEndpointHealthResults = []
        tronEndpointHealthLastUpdatedAt = nil
        solanaHistoryDiagnosticsByWallet = [:]
        solanaHistoryDiagnosticsLastUpdatedAt = nil
        solanaEndpointHealthResults = []
        solanaEndpointHealthLastUpdatedAt = nil
        xrpHistoryDiagnosticsByWallet = [:]
        xrpHistoryDiagnosticsLastUpdatedAt = nil
        xrpEndpointHealthResults = []
        xrpEndpointHealthLastUpdatedAt = nil
        moneroHistoryDiagnosticsByWallet = [:]
        moneroHistoryDiagnosticsLastUpdatedAt = nil
        moneroEndpointHealthResults = []
        moneroEndpointHealthLastUpdatedAt = nil
        suiHistoryDiagnosticsByWallet = [:]
        suiHistoryDiagnosticsLastUpdatedAt = nil
        suiEndpointHealthResults = []
        suiEndpointHealthLastUpdatedAt = nil
        nearHistoryDiagnosticsByWallet = [:]
        nearHistoryDiagnosticsLastUpdatedAt = nil
        nearEndpointHealthResults = []
        nearEndpointHealthLastUpdatedAt = nil
        polkadotHistoryDiagnosticsByWallet = [:]
        polkadotHistoryDiagnosticsLastUpdatedAt = nil
        polkadotEndpointHealthResults = []
        polkadotEndpointHealthLastUpdatedAt = nil
        cardanoHistoryDiagnosticsByWallet = [:]
        cardanoHistoryDiagnosticsLastUpdatedAt = nil
        cardanoEndpointHealthResults = []
        cardanoEndpointHealthLastUpdatedAt = nil
        bitcoinCashHistoryDiagnosticsByWallet = [:]
        bitcoinCashHistoryDiagnosticsLastUpdatedAt = nil
        bitcoinCashEndpointHealthResults = []
        bitcoinCashEndpointHealthLastUpdatedAt = nil
        bitcoinSVHistoryDiagnosticsByWallet = [:]
        bitcoinSVHistoryDiagnosticsLastUpdatedAt = nil
        bitcoinSVEndpointHealthResults = []
        bitcoinSVEndpointHealthLastUpdatedAt = nil
        bitcoinHistoryDiagnosticsByWallet = [:]
        bitcoinHistoryDiagnosticsLastUpdatedAt = nil
        bitcoinEndpointHealthResults = []
        bitcoinEndpointHealthLastUpdatedAt = nil
        litecoinHistoryDiagnosticsByWallet = [:]
        litecoinHistoryDiagnosticsLastUpdatedAt = nil
        // Belt-and-suspenders: drop the entire Rust-owned diagnostics registry.
        diagnosticsClearAll()
        litecoinEndpointHealthResults = []
        litecoinEndpointHealthLastUpdatedAt = nil
        diagnostics.chainDegradedMessages = [:]
        diagnostics.lastGoodChainSyncByName = [:]
        chainOperationalEventsByChain = [:]
        diagnostics.clearOperationalLogs()
        for kp: ReferenceWritableKeyPath<AppState, Bool> in [
            \.isRunningBitcoinSelfTests, \.isRunningBitcoinCashSelfTests, \.isRunningBitcoinSVSelfTests,
            \.isRunningLitecoinSelfTests, \.isRunningDogecoinSelfTests,
            \.isRunningDogecoinHistoryDiagnostics, \.isCheckingDogecoinEndpointHealth,
            \.isRunningEthereumSelfTests, \.isRunningEthereumHistoryDiagnostics, \.isCheckingEthereumEndpointHealth,
            \.isRunningArbitrumHistoryDiagnostics, \.isCheckingArbitrumEndpointHealth,
            \.isRunningOptimismHistoryDiagnostics, \.isCheckingOptimismEndpointHealth,
            \.isRunningETCHistoryDiagnostics, \.isCheckingETCEndpointHealth,
            \.isRunningBNBHistoryDiagnostics, \.isCheckingBNBEndpointHealth,
            \.isRunningAvalancheHistoryDiagnostics, \.isCheckingAvalancheEndpointHealth,
            \.isRunningHyperliquidHistoryDiagnostics, \.isCheckingHyperliquidEndpointHealth,
            \.isRunningTronHistoryDiagnostics, \.isCheckingTronEndpointHealth,
            \.isRunningSolanaHistoryDiagnostics, \.isCheckingSolanaEndpointHealth,
            \.isRunningXRPHistoryDiagnostics, \.isCheckingXRPEndpointHealth,
            \.isRunningMoneroHistoryDiagnostics, \.isCheckingMoneroEndpointHealth,
            \.isRunningSuiHistoryDiagnostics, \.isCheckingSuiEndpointHealth,
            \.isRunningCardanoHistoryDiagnostics, \.isCheckingCardanoEndpointHealth,
            \.isRunningBitcoinHistoryDiagnostics, \.isCheckingBitcoinEndpointHealth,
            \.isRunningLitecoinHistoryDiagnostics, \.isCheckingLitecoinEndpointHealth,
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
        persistTransactionsFullSync()
        rebuildNormalizedHistoryIndex()
    }
    private func resetAlertsAndContactsState() {
        UserDefaults.standard.removeObject(forKey: Self.priceAlertsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.addressBookDefaultsKey)
        priceAlerts = []
        setAddressBook([])
    }
    private func resetDashboardCustomizationState() { resetPinnedDashboardAssets() }
    private func resetSettingsAndEndpointsState() {
        UserDefaults.standard.removeObject(forKey: Self.tokenPreferencesDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.pricingProviderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedFiatCurrencyDefaultsKey)
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
        selectedFiatCurrency = .usd
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
