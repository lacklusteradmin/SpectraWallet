import Foundation
import UIKit
extension AppState {
    func restorePersistedRuntimeConfigurationAndState() {
        if let storedProvider = UserDefaults.standard.string(forKey: Self.pricingProviderDefaultsKey), let pricingProvider = PricingProvider(rawValue: storedProvider) { self.pricingProvider = pricingProvider }
        if let storedBitcoinNetworkMode = UserDefaults.standard.string(forKey: Self.bitcoinNetworkModeDefaultsKey), let bitcoinNetworkMode = BitcoinNetworkMode(rawValue: storedBitcoinNetworkMode) { self.bitcoinNetworkMode = bitcoinNetworkMode }
        if let storedDogecoinNetworkMode = UserDefaults.standard.string(forKey: Self.dogecoinNetworkModeDefaultsKey), let dogecoinNetworkMode = DogecoinNetworkMode(rawValue: storedDogecoinNetworkMode) { self.dogecoinNetworkMode = dogecoinNetworkMode }
        if let storedEthereumNetworkMode = UserDefaults.standard.string(forKey: Self.ethereumNetworkModeDefaultsKey), let ethereumNetworkMode = EthereumNetworkMode(rawValue: storedEthereumNetworkMode) { self.ethereumNetworkMode = ethereumNetworkMode }
        if let storedBitcoinFeePriority = UserDefaults.standard.string(forKey: Self.bitcoinFeePriorityDefaultsKey), let bitcoinFeePriority = BitcoinFeePriority(rawValue: storedBitcoinFeePriority) { self.bitcoinFeePriority = bitcoinFeePriority }
        if UserDefaults.standard.object(forKey: Self.bitcoinStopGapDefaultsKey) != nil { self.bitcoinStopGap = UserDefaults.standard.integer(forKey: Self.bitcoinStopGapDefaultsKey) }
        self.bitcoinEsploraEndpoints = UserDefaults.standard.string(forKey: Self.bitcoinEsploraEndpointsDefaultsKey) ?? ""
        if let storedFiatCurrency = UserDefaults.standard.string(forKey: Self.selectedFiatCurrencyDefaultsKey), let selectedFiatCurrency = FiatCurrency(rawValue: storedFiatCurrency) { self.selectedFiatCurrency = selectedFiatCurrency }
        if let storedFiatRateProvider = UserDefaults.standard.string(forKey: Self.fiatRateProviderDefaultsKey), let fiatRateProvider = FiatRateProvider(rawValue: storedFiatRateProvider) { self.fiatRateProvider = fiatRateProvider }
        if let storedFiatRates = UserDefaults.standard.dictionary(forKey: Self.fiatRatesFromUSDDefaultsKey) as? [String: Double] { fiatRatesFromUSD = storedFiatRates }
        fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        if let storedDogecoinFeePriority = UserDefaults.standard.string(forKey: Self.dogecoinFeePriorityDefaultsKey), let dogecoinFeePriority = DogecoinFeePriority(rawValue: storedDogecoinFeePriority) { self.dogecoinFeePriority = dogecoinFeePriority }
        coinGeckoAPIKey = SecureStore.loadValue(for: Self.coinGeckoAPIKeyAccount)
        ethereumRPCEndpoint = UserDefaults.standard.string(forKey: Self.ethereumRPCEndpointDefaultsKey) ?? ""
        etherscanAPIKey = UserDefaults.standard.string(forKey: Self.etherscanAPIKeyDefaultsKey) ?? ""
        moneroBackendBaseURL = UserDefaults.standard.string(forKey: MoneroBalanceService.backendBaseURLDefaultsKey) ?? ""
        moneroBackendAPIKey = UserDefaults.standard.string(forKey: MoneroBalanceService.backendAPIKeyDefaultsKey) ?? ""
        suppressWalletSideEffects = true
        setWallets(loadPersistedWallets())
        priceAlerts = loadPersistedPriceAlerts()
        setAddressBook(loadPersistedAddressBook())
        tokenPreferences = loadPersistedTokenPreferences()
        rebuildTokenPreferenceDerivedState()
        livePrices = loadPersistedLivePrices()
        chainKeypoolByChain = mergeDogecoinKeypoolIntoChainMap(loadChainKeypoolState())
        chainOwnedAddressMapByChain = mergeDogecoinOwnedAddressesIntoChainMap(loadChainOwnedAddressMap())
        chainOperationalEventsByChain = loadChainOperationalEvents()
        syncChainOwnedAddressManagementState()
        if UserDefaults.standard.object(forKey: Self.hideBalancesDefaultsKey) != nil { hideBalances = UserDefaults.standard.bool(forKey: Self.hideBalancesDefaultsKey) }
        if let storedAssetDisplayDecimalsByChain = loadAssetDisplayDecimalsByChain() { assetDisplayDecimalsByChain = storedAssetDisplayDecimalsByChain }
        if UserDefaults.standard.object(forKey: Self.useFaceIDDefaultsKey) != nil { useFaceID = UserDefaults.standard.bool(forKey: Self.useFaceIDDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.useAutoLockDefaultsKey) != nil { useAutoLock = UserDefaults.standard.bool(forKey: Self.useAutoLockDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.useStrictRPCOnlyDefaultsKey) != nil { useStrictRPCOnly = UserDefaults.standard.bool(forKey: Self.useStrictRPCOnlyDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.requireBiometricForSendActionsDefaultsKey) != nil { requireBiometricForSendActions = UserDefaults.standard.bool(forKey: Self.requireBiometricForSendActionsDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.usePriceAlertsDefaultsKey) != nil { usePriceAlerts = UserDefaults.standard.bool(forKey: Self.usePriceAlertsDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.useTransactionStatusNotificationsDefaultsKey) != nil { useTransactionStatusNotifications = UserDefaults.standard.bool(forKey: Self.useTransactionStatusNotificationsDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.useLargeMovementNotificationsDefaultsKey) != nil { useLargeMovementNotifications = UserDefaults.standard.bool(forKey: Self.useLargeMovementNotificationsDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey) != nil { automaticRefreshFrequencyMinutes = UserDefaults.standard.integer(forKey: Self.automaticRefreshFrequencyMinutesDefaultsKey) } else if let rawSyncProfile = UserDefaults.standard.string(forKey: Self.backgroundSyncProfileDefaultsKey), let profile = BackgroundSyncProfile(rawValue: rawSyncProfile) {
            backgroundSyncProfile = profile
            switch profile {
            case .conservative: automaticRefreshFrequencyMinutes = 10
            case .balanced, .aggressive: automaticRefreshFrequencyMinutes = 5
            }}
        if UserDefaults.standard.object(forKey: Self.largeMovementAlertPercentThresholdDefaultsKey) != nil { largeMovementAlertPercentThreshold = UserDefaults.standard.double(forKey: Self.largeMovementAlertPercentThresholdDefaultsKey) }
        if UserDefaults.standard.object(forKey: Self.largeMovementAlertUSDThresholdDefaultsKey) != nil { largeMovementAlertUSDThreshold = UserDefaults.standard.double(forKey: Self.largeMovementAlertUSDThresholdDefaultsKey) }
        if let storedFeePrioritySelections = UserDefaults.standard.dictionary(forKey: Self.selectedFeePriorityOptionsByChainDefaultsKey) as? [String: String] { selectedFeePriorityOptionRawByChain = storedFeePrioritySelections }
        let storedPins = (UserDefaults.standard.stringArray(forKey: Self.pinnedDashboardAssetSymbolsDefaultsKey) ?? []).map { $0.uppercased() }.filter { !$0.isEmpty }
        if !storedPins.isEmpty { cachedPinnedDashboardAssetSymbols = storedPins }
        suppressWalletSideEffects = false
        applyWalletCollectionSideEffects()
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        startNetworkPathMonitorIfNeeded()
        resetLargeMovementAlertBaseline()
    }
    func clearPersistedSecureDataOnFreshInstallIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.installMarkerDefaultsKey) { return }
        let persistedWalletIDs = storedWalletIDs()
        for walletID in persistedWalletIDs { deleteWalletSecrets(for: walletID) }
        SecureStore.deleteValue(for: Self.walletsAccount)
        SecureStore.deleteValue(for: Self.walletsCoreSnapshotAccount)
        SecureStore.deleteValue(for: Self.coinGeckoAPIKeyAccount)
        clearWalletSecretIndex()
        UserDefaults.standard.set(true, forKey: Self.installMarkerDefaultsKey)
    }
    func resetWalletData() async { await resetSelectedData(scopes: Set(ResetScope.allCases)) }
    func resetSelectedData(scopes: Set<ResetScope>) async {
        guard !scopes.isEmpty else { return }
        guard await authenticateForSensitiveAction(
            reason: "Authenticate to reset wallet data", allowWhenAuthenticationUnavailable: true
        ) else {
            return
        }
        if scopes.contains(.walletsAndSecrets) { resetWalletsAndSecretsState() }
        if scopes.contains(.historyAndCache) || scopes.contains(.walletsAndSecrets) { resetHistoryAndCacheState() }
        if scopes.contains(.alertsAndContacts) { resetAlertsAndContactsState() }
        if scopes.contains(.settingsAndEndpoints) { resetSettingsAndEndpointsState() }
        if scopes.contains(.dashboardCustomization) { resetDashboardCustomizationState() }
        if scopes.contains(.providerState) { await resetProviderState() }
        if scopes.contains(.walletsAndSecrets) || scopes.contains(.historyAndCache) { clearNetworkAndTransportCaches() }
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
        bitcoinSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        bitcoinCashSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        moneroSendPreview = nil
        isSendingBitcoin = false
        isSendingBitcoinCash = false
        isSendingLitecoin = false
        isSendingDogecoin = false
        isSendingEthereum = false
        isSendingTron = false
        isSendingSolana = false
        isSendingXRP = false
        isSendingMonero = false
        isPreparingEthereumSend = false
        isPreparingDogecoinSend = false
        isPreparingTronSend = false
        isPreparingSolanaSend = false
        isPreparingXRPSend = false
        isPreparingMoneroSend = false
        pendingEthereumSendPreviewRefresh = false
        pendingDogecoinSendPreviewRefresh = false
        pendingSelfSendConfirmation = nil
        activeEthereumSendWalletIDs = []
        lastSendDestinationProbeKey = nil
        lastSendDestinationProbeWarning = nil
        lastSendDestinationProbeInfoMessage = nil
        cachedResolvedENSAddresses = [:]
        bypassHighRiskSendConfirmation = false
        statusTrackingByTransactionID = [:]
        isShowingWalletImporter = false
        isShowingSendSheet = false
        isShowingReceiveSheet = false
        importError = nil
        isImportingWallet = false
        cancelWalletImport()
    }
    private func resetHistoryAndCacheState() {
        Task { await WalletServiceBridge.shared.clearAllHistoryRecords() }
        UserDefaults.standard.removeObject(forKey: Self.chainSyncStateDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.operationalLogsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.dogecoinKeypoolDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.dogecoinOwnedAddressMapDefaultsKey)
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
        isRunningBitcoinSelfTests = false
        isRunningBitcoinCashSelfTests = false
        isRunningBitcoinSVSelfTests = false
        isRunningLitecoinSelfTests = false
        isRunningDogecoinSelfTests = false
        isRunningDogecoinHistoryDiagnostics = false
        isCheckingDogecoinEndpointHealth = false
        isRunningEthereumSelfTests = false
        isRunningEthereumHistoryDiagnostics = false
        isCheckingEthereumEndpointHealth = false
        isRunningArbitrumHistoryDiagnostics = false
        isCheckingArbitrumEndpointHealth = false
        isRunningOptimismHistoryDiagnostics = false
        isCheckingOptimismEndpointHealth = false
        isRunningETCHistoryDiagnostics = false
        isCheckingETCEndpointHealth = false
        isRunningBNBHistoryDiagnostics = false
        isCheckingBNBEndpointHealth = false
        isRunningAvalancheHistoryDiagnostics = false
        isCheckingAvalancheEndpointHealth = false
        isRunningHyperliquidHistoryDiagnostics = false
        isCheckingHyperliquidEndpointHealth = false
        isRunningTronHistoryDiagnostics = false
        isCheckingTronEndpointHealth = false
        isRunningSolanaHistoryDiagnostics = false
        isCheckingSolanaEndpointHealth = false
        isRunningXRPHistoryDiagnostics = false
        isCheckingXRPEndpointHealth = false
        isRunningMoneroHistoryDiagnostics = false
        isCheckingMoneroEndpointHealth = false
        isRunningSuiHistoryDiagnostics = false
        isCheckingSuiEndpointHealth = false
        isRunningCardanoHistoryDiagnostics = false
        isCheckingCardanoEndpointHealth = false
        isRunningBitcoinHistoryDiagnostics = false
        isCheckingBitcoinEndpointHealth = false
        isRunningLitecoinHistoryDiagnostics = false
        isCheckingLitecoinEndpointHealth = false
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
        SecureStore.deleteValue(for: Self.coinGeckoAPIKeyAccount)
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
        UserDefaults.standard.removeObject(forKey: TokenIconPreferenceStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: TokenIconPreferenceStore.customImageRevisionDefaultsKey)
        TokenIconImageStore.removeAllImages()
        tokenPreferences = ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        livePrices = [:]
        quoteRefreshError = nil
        fiatRatesRefreshError = nil
        pricingProvider = .coinGecko
        selectedFiatCurrency = .usd
        fiatRateProvider = .openER
        assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain()
        coinGeckoAPIKey = ""
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
        hideBalances = false
        useFaceID = true
        useAutoLock = false
        useStrictRPCOnly = false
        requireBiometricForSendActions = true
        usePriceAlerts = true
        useTransactionStatusNotifications = true
        useLargeMovementNotifications = true
        automaticRefreshFrequencyMinutes = 5
        backgroundSyncProfile = .balanced
        largeMovementAlertPercentThreshold = 10
        largeMovementAlertUSDThreshold = 50
    }
    private func resetProviderState() async {
        clearNetworkAndTransportCaches()
    }
    private func clearNetworkAndTransportCaches() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        let credentialStorage = URLCredentialStorage.shared
        for (protectionSpace, credentialsByUser) in credentialStorage.allCredentials {
            for credential in credentialsByUser.values { credentialStorage.remove(credential, for: protectionSpace) }}}
}
