import Foundation
extension AppState {
    func loadCodableFromUserDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func persistCodableToSQLite<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
        Task {
            try? await WalletServiceBridge.shared.saveState(key: key, stateJSON: json)
        }}
    func loadCodableFromSQLite<T: Decodable>(_ type: T.Type, key: String) async -> T? {
        guard let json = try? await WalletServiceBridge.shared.loadState(key: key), json != "{}", let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func reloadPersistedStateFromSQLite() async {
        if let prices = await loadCodableFromSQLite([String: Double].self, key: Self.livePricesDefaultsKey), !prices.isEmpty { livePrices = prices }
        if let tokenPrefs = await loadCodableFromSQLite([TokenPreferenceEntry].self, key: Self.tokenPreferencesDefaultsKey), !tokenPrefs.isEmpty { tokenPreferences = mergeBuiltInTokenPreferences(with: tokenPrefs) }
        if let alertsJSON = try? await WalletServiceBridge.shared.loadState(key: Self.priceAlertsDefaultsKey), alertsJSON != "{}", let alertsPayload = try? decodePersistedPriceAlertStoreJson(json: alertsJSON), alertsPayload.version == 1 {
            priceAlerts = alertsPayload.alerts.compactMap(PriceAlertRule.init(snapshot:))
        }
        if let abJSON = try? await WalletServiceBridge.shared.loadState(key: Self.addressBookDefaultsKey), abJSON != "{}", let abPayload = try? decodePersistedAddressBookStoreJson(json: abJSON), abPayload.version == 1 {
            setAddressBook(abPayload.entries.compactMap(AddressBookEntry.init(snapshot:)))
        }
        if let allKeypool = try? await WalletServiceBridge.shared.loadAllKeypoolStateTyped(), !allKeypool.isEmpty {
            var rebuiltChains: [String: [String: ChainKeypoolState]] = [:]
            for (chainName, walletMap) in allKeypool {
                var rebuilt: [String: ChainKeypoolState] = [:]
                for (uuidStr, state) in walletMap {
                    rebuilt[uuidStr] = ChainKeypoolState(
                        nextExternalIndex: Int(state.nextExternalIndex), nextChangeIndex: Int(state.nextChangeIndex), reservedReceiveIndex: state.reservedReceiveIndex.map { Int($0) }
                    )
                }
                if !rebuilt.isEmpty { rebuiltChains[chainName] = rebuilt }}
            if !rebuiltChains.isEmpty { chainKeypoolByChain = rebuiltChains }}
        if let allRecords = try? await WalletServiceBridge.shared.loadAllOwnedAddressesTyped(), !allRecords.isEmpty {
            var chainMap: [String: [String: ChainOwnedAddressRecord]] = [:]
            for rec in allRecords {
                guard !rec.address.isEmpty else { continue }
                let chainRecord = ChainOwnedAddressRecord(
                    chainName: rec.chainName, address: rec.address, walletID: rec.walletId, derivationPath: rec.derivationPath, index: rec.branchIndex.map { Int($0) }, branch: rec.branch
                )
                chainMap[rec.chainName, default: [:]][rec.address] = chainRecord
            }
            if !chainMap.isEmpty { chainOwnedAddressMapByChain = chainMap }}
        if let rates = await loadCodableFromSQLite([String: Double].self, key: Self.fiatRatesFromUSDDefaultsKey), !rates.isEmpty {
            fiatRatesFromUSD = rates
            fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        }
        if let decimals = await loadCodableFromSQLite([String: Int].self, key: Self.assetDisplayDecimalsByChainDefaultsKey), !decimals.isEmpty { assetDisplayDecimalsByChain = decimals }
        if let events = await loadCodableFromSQLite([String: [ChainOperationalEvent]].self, key: Self.chainOperationalEventsDefaultsKey), !events.isEmpty { chainOperationalEventsByChain = events }
        if let feePrios = await loadCodableFromSQLite([String: String].self, key: Self.selectedFeePriorityOptionsByChainDefaultsKey), !feePrios.isEmpty { selectedFeePriorityOptionRawByChain = feePrios }
        if !wallets.isEmpty {
            let summaries: [WalletSummary] = wallets.map { $0.walletSummary }
            try? await WalletServiceBridge.shared.initWalletStateDirect(wallets: summaries) }
        // ── Load app settings from Rust SQLite ────────────────────────────────
        if let settings = try? await WalletServiceBridge.shared.loadAppSettingsTyped() {
            if let v = PricingProvider(rawValue: settings.pricingProvider) { pricingProvider = v }
            if let v = FiatCurrency(rawValue: settings.selectedFiatCurrency) { selectedFiatCurrency = v }
            if let v = FiatRateProvider(rawValue: settings.fiatRateProvider) { fiatRateProvider = v }
            if let v = EthereumNetworkMode(rawValue: settings.ethereumNetworkMode) { ethereumNetworkMode = v }
            if let v = BitcoinNetworkMode(rawValue: settings.bitcoinNetworkMode) { bitcoinNetworkMode = v }
            if let v = DogecoinNetworkMode(rawValue: settings.dogecoinNetworkMode) { dogecoinNetworkMode = v }
            if let v = BitcoinFeePriority(rawValue: settings.bitcoinFeePriority) { bitcoinFeePriority = v }
            if let v = DogecoinFeePriority(rawValue: settings.dogecoinFeePriority) { dogecoinFeePriority = v }
            if let v = BackgroundSyncProfile(rawValue: settings.backgroundSyncProfile) { backgroundSyncProfile = v }
            ethereumRPCEndpoint = settings.ethereumRpcEndpoint
            etherscanAPIKey = settings.etherscanApiKey
            moneroBackendBaseURL = settings.moneroBackendBaseUrl
            moneroBackendAPIKey = settings.moneroBackendApiKey
            bitcoinEsploraEndpoints = settings.bitcoinEsploraEndpoints
            bitcoinStopGap = Int(settings.bitcoinStopGap)
            hideBalances = settings.hideBalances
            useFaceID = settings.useFaceId
            useAutoLock = settings.useAutoLock
            useStrictRPCOnly = settings.useStrictRpcOnly
            requireBiometricForSendActions = settings.requireBiometricForSendActions
            usePriceAlerts = settings.usePriceAlerts
            useTransactionStatusNotifications = settings.useTransactionStatusNotifications
            useLargeMovementNotifications = settings.useLargeMovementNotifications
            automaticRefreshFrequencyMinutes = Int(settings.automaticRefreshFrequencyMinutes)
            largeMovementAlertPercentThreshold = settings.largeMovementAlertPercentThreshold
            largeMovementAlertUSDThreshold = settings.largeMovementAlertUsdThreshold
            if !settings.pinnedDashboardAssetSymbols.isEmpty { cachedPinnedDashboardAssetSymbols = settings.pinnedDashboardAssetSymbols }
        } else {
            // No SQLite settings yet — persist current (UserDefaults-loaded) values to SQLite for future launches
            persistAppSettings()
        }
        // ── Load transaction history from Rust SQLite ─────────────────────────
        if let rustRecords = try? await WalletServiceBridge.shared.fetchAllHistoryRecordsTyped(),
           !rustRecords.isEmpty {
            let rustTransactions = rustRecords.compactMap { rec -> TransactionRecord? in
                guard let payloadData = Data(base64Encoded: rec.payload),
                      let payloadJSON = String(data: payloadData, encoding: .utf8),
                      let persisted = try? decodePersistedTransactionRecordJson(json: payloadJSON)
                else { return nil }
                return TransactionRecord(snapshot: persisted)
            }
            if !rustTransactions.isEmpty {
                withSuspendedTransactionSideEffects { transactions = rustTransactions }
                pruneTransactionsForActiveWallets()
                rebuildTransactionDerivedState()
            }
        }}
    func persistLivePrices() {
        persistCodableToSQLite(livePrices, key: Self.livePricesDefaultsKey)
    }
    func loadAssetDisplayDecimalsByChain() -> [String: Int]? { loadCodableFromUserDefaults([String: Int].self, key: Self.assetDisplayDecimalsByChainDefaultsKey) }
    func loadPersistedLivePrices() -> [String: Double] { loadCodableFromUserDefaults([String: Double].self, key: Self.livePricesDefaultsKey) ?? [:] }
    func persistWallets() {
        guard !wallets.isEmpty else {
            storedWalletIDs().forEach { walletID in deleteWalletSecrets(for: walletID) }
            SecureStore.deleteValue(for: Self.walletsAccount)
            SecureStore.deleteValue(for: Self.walletsCoreSnapshotAccount)
            clearWalletSecretIndex()
            chainOwnedAddressMapByChain = [:]
            chainKeypoolByChain = [:]
            return
        }
        let currentWalletIDs = Set(wallets.map(\.id))
        storedWalletIDs().filter { !currentWalletIDs.contains($0) }
            .forEach { walletID in deleteWalletSecrets(for: walletID) }
        chainOwnedAddressMapByChain = chainOwnedAddressMapByChain.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { _, value in
                currentWalletIDs.contains(value.walletID)
            }
            if !filtered.isEmpty { partialResult[entry.key] = filtered }}
        chainKeypoolByChain = chainKeypoolByChain.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { walletID, _ in
                currentWalletIDs.contains(walletID)
            }
            if !filtered.isEmpty { partialResult[entry.key] = filtered }}
        syncChainOwnedAddressManagementState()
        let snapshots = wallets.map(sanitizedWallet).map(\.persistedSnapshot)
        let payload = PersistedWalletStore(version: PersistedWalletStore.currentVersion, wallets: snapshots)
        guard let data = try? Self.persistenceEncoder.encode(payload) else { return }
        SecureStore.saveData(data, for: Self.walletsAccount)
    }
    func loadPersistedWallets() -> [ImportedWallet] {
        clearWalletSecretIndex()
        guard let data = SecureStore.loadData(for: Self.walletsAccount) else { return [] }
        return decodedWalletSnapshots(from: data) ?? []
    }
    func storedWalletIDs() -> [String] {
        guard let data = SecureStore.loadData(for: Self.walletsAccount) else { return [] }
        if let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data), payload.version == PersistedWalletStore.currentVersion {
            return payload.wallets.map { $0.id }}
        return []
    }
    func sanitizedWallet(_ wallet: ImportedWallet) -> ImportedWallet {
        let supportedHoldings = wallet.holdings.filter { coin in AppEndpointDirectory.supportsBalanceRefresh(for: coin.chainName) }
        return ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode, dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress, xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset, seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain, holdings: supportedHoldings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
    }
    func persistPriceAlerts() {
        let payload = CorePersistedPriceAlertStore(
            version: 1, alerts: priceAlerts.map(\.persistedSnapshot)
        )
        guard let json = try? encodePersistedPriceAlertStoreJson(value: payload) else { return }
        Task { try? await WalletServiceBridge.shared.saveState(key: Self.priceAlertsDefaultsKey, stateJSON: json) }
    }
    func persistAddressBook() {
        let payload = CorePersistedAddressBookStore(
            version: 1, entries: addressBook.map(\.persistedSnapshot)
        )
        guard let json = try? encodePersistedAddressBookStoreJson(value: payload) else { return }
        Task { try? await WalletServiceBridge.shared.saveState(key: Self.addressBookDefaultsKey, stateJSON: json) }
    }
    func loadPersistedAddressBook() -> [AddressBookEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.addressBookDefaultsKey),
              let json = String(data: data, encoding: .utf8),
              let payload = try? decodePersistedAddressBookStoreJson(json: json),
              payload.version == 1 else { return [] }
        return payload.entries.compactMap(AddressBookEntry.init(snapshot:))
    }
    func persistTokenPreferences() {
        persistCodableToSQLite(tokenPreferences, key: Self.tokenPreferencesDefaultsKey)
    }
    // ── App settings persistence (Rust SQLite) ─────────────────────────────────
    /// Debounced — coalesces rapid-fire settings changes (e.g. slider drags,
    /// multiple toggles in quick succession) into a single SQLite write.
    func persistAppSettings() {
        appSettingsPersistTask?.cancel()
        appSettingsPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard !Task.isCancelled, let self else { return }
            self.persistAppSettingsNow()
        }
    }
    private func persistAppSettingsNow() {
        let settings = PersistedAppSettings(
            pricingProvider: pricingProvider.rawValue,
            selectedFiatCurrency: selectedFiatCurrency.rawValue,
            fiatRateProvider: fiatRateProvider.rawValue,
            ethereumRpcEndpoint: ethereumRPCEndpoint,
            ethereumNetworkMode: ethereumNetworkMode.rawValue,
            etherscanApiKey: etherscanAPIKey,
            moneroBackendBaseUrl: moneroBackendBaseURL,
            moneroBackendApiKey: moneroBackendAPIKey,
            bitcoinNetworkMode: bitcoinNetworkMode.rawValue,
            dogecoinNetworkMode: dogecoinNetworkMode.rawValue,
            bitcoinEsploraEndpoints: bitcoinEsploraEndpoints,
            bitcoinStopGap: Int32(bitcoinStopGap),
            bitcoinFeePriority: bitcoinFeePriority.rawValue,
            dogecoinFeePriority: dogecoinFeePriority.rawValue,
            hideBalances: hideBalances,
            useFaceId: useFaceID,
            useAutoLock: useAutoLock,
            useStrictRpcOnly: useStrictRPCOnly,
            requireBiometricForSendActions: requireBiometricForSendActions,
            usePriceAlerts: usePriceAlerts,
            useTransactionStatusNotifications: useTransactionStatusNotifications,
            useLargeMovementNotifications: useLargeMovementNotifications,
            automaticRefreshFrequencyMinutes: Int32(automaticRefreshFrequencyMinutes),
            backgroundSyncProfile: backgroundSyncProfile.rawValue,
            largeMovementAlertPercentThreshold: largeMovementAlertPercentThreshold,
            largeMovementAlertUsdThreshold: largeMovementAlertUSDThreshold,
            pinnedDashboardAssetSymbols: cachedPinnedDashboardAssetSymbols
        )
        WalletServiceBridge.shared.saveAppSettingsTyped(settings: settings)
    }
    func loadPersistedTokenPreferences() -> [TokenPreferenceEntry] {
        guard let decoded = loadCodableFromUserDefaults(
            [TokenPreferenceEntry].self, key: Self.tokenPreferencesDefaultsKey
        ) else {
            return ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        }
        return mergeBuiltInTokenPreferences(with: decoded)
    }
    func loadPersistedPriceAlerts() -> [PriceAlertRule] {
        guard let data = UserDefaults.standard.data(forKey: Self.priceAlertsDefaultsKey),
              let json = String(data: data, encoding: .utf8),
              let payload = try? decodePersistedPriceAlertStoreJson(json: json),
              payload.version == 1 else { return [] }
        return payload.alerts.compactMap(PriceAlertRule.init(snapshot:))
    }
    private func decodedWalletSnapshots(from data: Data) -> [ImportedWallet]? {
        guard let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data), payload.version == PersistedWalletStore.currentVersion else { return nil }
        return payload.wallets.compactMap { snapshot in
            let hasSeedPhrase = walletHasSigningMaterial(snapshot.id)
            let hasWatchOnlyAddress = [
                snapshot.bitcoinAddress, snapshot.bitcoinXpub, snapshot.litecoinAddress, snapshot.dogecoinAddress, snapshot.ethereumAddress, snapshot.tronAddress, snapshot.solanaAddress, snapshot.xrpAddress, snapshot.stellarAddress, snapshot.moneroAddress, snapshot.cardanoAddress, snapshot.suiAddress, snapshot.nearAddress, snapshot.polkadotAddress
            ]
            .contains { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            guard hasSeedPhrase || hasWatchOnlyAddress else { return nil }
            let wallet = sanitizedWallet(ImportedWallet(snapshot: snapshot))
#if DEBUG
            logBalanceTelemetry(source: "local", chainName: "PersistedWalletStore", wallet: wallet, holdings: wallet.holdings)
#endif
            return wallet
        }}
}
