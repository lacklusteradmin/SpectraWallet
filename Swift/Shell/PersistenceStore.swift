import Foundation
private struct RustHistoryRecord: Decodable {
    let id: String
    let walletId: String?
    let chainName: String
    let txHash: String?
    let createdAt: Double
    let payload: String  // base64
}
private struct RustKeypoolState: Decodable {
    let nextExternalIndex: Int
    let nextChangeIndex: Int
    let reservedReceiveIndex: Int?
}
private struct RustOwnedAddressRecord: Decodable {
    let walletId: String
    let chainName: String
    let address: String
    let derivationPath: String?
    let branch: String?
    let branchIndex: Int?
}
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
        if let keypoolJSON = try? await WalletServiceBridge.shared.loadAllKeypoolState(), let keypoolData = keypoolJSON.data(using: .utf8), let allKeypool = try? JSONDecoder().decode(
               [String: [String: RustKeypoolState]].self, from: keypoolData
           ), !allKeypool.isEmpty {
            if let dogeWalletMap = allKeypool["Dogecoin"] {
                var rebuilt: [String: DogecoinKeypoolState] = [:]
                for (uuidStr, state) in dogeWalletMap {
                    rebuilt[uuidStr] = DogecoinKeypoolState(
                        nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex, reservedReceiveIndex: state.reservedReceiveIndex
                    )
                }
                if !rebuilt.isEmpty { dogecoinKeypoolByWalletID = rebuilt }}
            var rebuiltChains: [String: [String: ChainKeypoolState]] = [:]
            for (chainName, walletMap) in allKeypool where chainName != "Dogecoin" {
                var rebuilt: [String: ChainKeypoolState] = [:]
                for (uuidStr, state) in walletMap {
                    rebuilt[uuidStr] = ChainKeypoolState(
                        nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex, reservedReceiveIndex: state.reservedReceiveIndex
                    )
                }
                if !rebuilt.isEmpty { rebuiltChains[chainName] = rebuilt }}
            if !rebuiltChains.isEmpty { chainKeypoolByChain = rebuiltChains }}
        if let addrJSON = try? await WalletServiceBridge.shared.loadAllOwnedAddresses(), let addrData = addrJSON.data(using: .utf8), let allRecords = try? JSONDecoder().decode([RustOwnedAddressRecord].self, from: addrData), !allRecords.isEmpty {
            var dogeMap: [String: DogecoinOwnedAddressRecord] = [:]
            var chainMap: [String: [String: ChainOwnedAddressRecord]] = [:]
            for rec in allRecords {
                guard !rec.address.isEmpty else { continue }
                if rec.chainName == "Dogecoin" {
                    dogeMap[rec.address] = DogecoinOwnedAddressRecord(
                        address: rec.address, walletID: rec.walletId, derivationPath: rec.derivationPath ?? "", index: rec.branchIndex.map { Int($0) } ?? 0, branch: rec.branch ?? ""
                    )
                } else {
                    let chainRecord = ChainOwnedAddressRecord(
                        chainName: rec.chainName, address: rec.address, walletID: rec.walletId, derivationPath: rec.derivationPath, index: rec.branchIndex.map { Int($0) }, branch: rec.branch
                    )
                    chainMap[rec.chainName, default: [:]][rec.address] = chainRecord
                }}
            if !dogeMap.isEmpty { dogecoinOwnedAddressMap = dogeMap }
            if !chainMap.isEmpty { chainOwnedAddressMapByChain = chainMap }}
        if let rates = await loadCodableFromSQLite([String: Double].self, key: Self.fiatRatesFromUSDDefaultsKey), !rates.isEmpty {
            fiatRatesFromUSD = rates
            fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        }
        if let decimals = await loadCodableFromSQLite([String: Int].self, key: Self.assetDisplayDecimalsByChainDefaultsKey), !decimals.isEmpty { assetDisplayDecimalsByChain = decimals }
        if let events = await loadCodableFromSQLite([String: [ChainOperationalEvent]].self, key: Self.chainOperationalEventsDefaultsKey), !events.isEmpty { chainOperationalEventsByChain = events }
        if let feePrios = await loadCodableFromSQLite([String: String].self, key: Self.selectedFeePriorityOptionsByChainDefaultsKey), !feePrios.isEmpty { selectedFeePriorityOptionRawByChain = feePrios }
        if !wallets.isEmpty {
            let summaries: [[String: Any]] = wallets.map { w in
                var d: [String: Any] = [
                    "id": w.id, "name": w.name, "isWatchOnly": false, "selectedChain": w.selectedChain, "includeInPortfolioTotal": w.includeInPortfolioTotal, "bitcoinNetworkMode": w.bitcoinNetworkMode.rawValue, "dogecoinNetworkMode": w.dogecoinNetworkMode.rawValue, "derivationPreset": w.seedDerivationPreset ?? "standard", "derivationPaths": w.seedDerivationPaths ?? [:], "holdings": w.holdings.map { coin -> [String: Any] in
                        var h: [String: Any] = [
                            "name": coin.name, "symbol": coin.symbol, "marketDataId": coin.marketDataId, "coinGeckoId": coin.coinGeckoId, "chainName": coin.chainName, "tokenStandard": coin.tokenStandard, "amount": coin.amount, "priceUsd": coin.priceUsd
                        ]
                        if let contract = coin.contractAddress { h["contractAddress"] = contract }
                        return h
                    }, "addresses": []
                ]
                if let xpub = w.bitcoinXpub { d["bitcoinXpub"] = xpub }
                return d
            }
            if let data = try? JSONSerialization.data(withJSONObject: summaries), let json = String(data: data, encoding: .utf8) { try? await WalletServiceBridge.shared.initWalletState(walletsJson: json) }}
        // ── Load app settings from Rust SQLite ────────────────────────────────
        if let settingsJSON = try? await WalletServiceBridge.shared.loadAppSettings(),
           settingsJSON != "{}",
           let settingsData = settingsJSON.data(using: .utf8),
           let settings = try? JSONDecoder().decode(PersistedAppSettings.self, from: settingsData) {
            if let v = PricingProvider(rawValue: settings.pricingProvider) { pricingProvider = v }
            if let v = FiatCurrency(rawValue: settings.selectedFiatCurrency) { selectedFiatCurrency = v }
            if let v = FiatRateProvider(rawValue: settings.fiatRateProvider) { fiatRateProvider = v }
            if let v = EthereumNetworkMode(rawValue: settings.ethereumNetworkMode) { ethereumNetworkMode = v }
            if let v = BitcoinNetworkMode(rawValue: settings.bitcoinNetworkMode) { bitcoinNetworkMode = v }
            if let v = DogecoinNetworkMode(rawValue: settings.dogecoinNetworkMode) { dogecoinNetworkMode = v }
            if let v = BitcoinFeePriority(rawValue: settings.bitcoinFeePriority) { bitcoinFeePriority = v }
            if let v = DogecoinFeePriority(rawValue: settings.dogecoinFeePriority) { dogecoinFeePriority = v }
            if let v = BackgroundSyncProfile(rawValue: settings.backgroundSyncProfile) { backgroundSyncProfile = v }
            ethereumRPCEndpoint = settings.ethereumRPCEndpoint
            etherscanAPIKey = settings.etherscanAPIKey
            moneroBackendBaseURL = settings.moneroBackendBaseURL
            moneroBackendAPIKey = settings.moneroBackendAPIKey
            bitcoinEsploraEndpoints = settings.bitcoinEsploraEndpoints
            bitcoinStopGap = settings.bitcoinStopGap
            hideBalances = settings.hideBalances
            useFaceID = settings.useFaceID
            useAutoLock = settings.useAutoLock
            useStrictRPCOnly = settings.useStrictRPCOnly
            requireBiometricForSendActions = settings.requireBiometricForSendActions
            usePriceAlerts = settings.usePriceAlerts
            useTransactionStatusNotifications = settings.useTransactionStatusNotifications
            useLargeMovementNotifications = settings.useLargeMovementNotifications
            automaticRefreshFrequencyMinutes = settings.automaticRefreshFrequencyMinutes
            largeMovementAlertPercentThreshold = settings.largeMovementAlertPercentThreshold
            largeMovementAlertUSDThreshold = settings.largeMovementAlertUSDThreshold
            if !settings.pinnedDashboardAssetSymbols.isEmpty { cachedPinnedDashboardAssetSymbols = settings.pinnedDashboardAssetSymbols }
        } else {
            // No SQLite settings yet — persist current (UserDefaults-loaded) values to SQLite for future launches
            persistAppSettings()
        }
        // ── Load transaction history from Rust SQLite ─────────────────────────
        if let historyJSON = try? await WalletServiceBridge.shared.fetchAllHistoryRecords(),
           historyJSON != "[]",
           let historyData = historyJSON.data(using: .utf8),
           let rustRecords = try? JSONDecoder().decode([RustHistoryRecord].self, from: historyData),
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
            dogecoinOwnedAddressMap = [:]
            chainOwnedAddressMapByChain = [:]
            chainKeypoolByChain = [:]
            return
        }
        let currentWalletIDs = Set(wallets.map(\.id))
        storedWalletIDs().filter { !currentWalletIDs.contains($0) }
            .forEach { walletID in deleteWalletSecrets(for: walletID) }
        dogecoinOwnedAddressMap = dogecoinOwnedAddressMap.filter { _, value in
            currentWalletIDs.contains(value.walletID)
        }
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
        if let coreStateData = try? WalletRustAppCoreBridge.migrateLegacyWalletStoreData(data), let coreSnapshotData = try? WalletRustAppCoreBridge.buildPersistedSnapshotData(
                appStateData: coreStateData, secretObservations: currentWalletSecretObservations(for: currentWalletIDs)
           ) {
            SecureStore.saveData(coreSnapshotData, for: Self.walletsCoreSnapshotAccount)
            if let secretIndex = try? WalletRustAppCoreBridge.walletSecretIndex(fromCoreSnapshotData: coreSnapshotData) { applyWalletSecretIndex(secretIndex) }
        } else if let coreStateData = try? WalletRustAppCoreBridge.migrateLegacyWalletStoreData(data) { SecureStore.saveData(coreStateData, for: Self.walletsCoreSnapshotAccount) }}
    func loadPersistedWallets() -> [ImportedWallet] {
        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount), let secretIndex = try? WalletRustAppCoreBridge.walletSecretIndex(fromCoreSnapshotData: coreSnapshotData) { applyWalletSecretIndex(secretIndex) } else { clearWalletSecretIndex() }
        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount), let exportedLegacyData = try? WalletRustAppCoreBridge.exportLegacyWalletStoreData(fromCoreStateData: coreSnapshotData), let wallets = decodedWalletSnapshots(from: exportedLegacyData) { return wallets }
        guard let data = SecureStore.loadData(for: Self.walletsAccount) else { return [] }
        return decodedWalletSnapshots(from: data) ?? []
    }
    func storedWalletIDs() -> [String] {
        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount), let exportedLegacyData = try? WalletRustAppCoreBridge.exportLegacyWalletStoreData(fromCoreStateData: coreSnapshotData), let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: exportedLegacyData), payload.version == PersistedWalletStore.currentVersion {
            return payload.wallets.map { $0.id }}
        guard let data = SecureStore.loadData(for: Self.walletsAccount) else { return [] }
        if let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data), payload.version == PersistedWalletStore.currentVersion {
            return payload.wallets.map { $0.id }}
        return []
    }
    func sanitizedWallet(_ wallet: ImportedWallet) -> ImportedWallet {
        let supportedHoldings = wallet.holdings.filter { coin in ChainBackendRegistry.supportsBalanceRefresh(for: coin.chainName) }
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
    private struct PersistedAppSettings: Codable {
        var pricingProvider: String
        var selectedFiatCurrency: String
        var fiatRateProvider: String
        var ethereumRPCEndpoint: String
        var ethereumNetworkMode: String
        var etherscanAPIKey: String
        var moneroBackendBaseURL: String
        var moneroBackendAPIKey: String
        var bitcoinNetworkMode: String
        var dogecoinNetworkMode: String
        var bitcoinEsploraEndpoints: String
        var bitcoinStopGap: Int
        var bitcoinFeePriority: String
        var dogecoinFeePriority: String
        var hideBalances: Bool
        var useFaceID: Bool
        var useAutoLock: Bool
        var useStrictRPCOnly: Bool
        var requireBiometricForSendActions: Bool
        var usePriceAlerts: Bool
        var useTransactionStatusNotifications: Bool
        var useLargeMovementNotifications: Bool
        var automaticRefreshFrequencyMinutes: Int
        var backgroundSyncProfile: String
        var largeMovementAlertPercentThreshold: Double
        var largeMovementAlertUSDThreshold: Double
        var pinnedDashboardAssetSymbols: [String]
    }
    func persistAppSettings() {
        let settings = PersistedAppSettings(
            pricingProvider: pricingProvider.rawValue,
            selectedFiatCurrency: selectedFiatCurrency.rawValue,
            fiatRateProvider: fiatRateProvider.rawValue,
            ethereumRPCEndpoint: ethereumRPCEndpoint,
            ethereumNetworkMode: ethereumNetworkMode.rawValue,
            etherscanAPIKey: etherscanAPIKey,
            moneroBackendBaseURL: moneroBackendBaseURL,
            moneroBackendAPIKey: moneroBackendAPIKey,
            bitcoinNetworkMode: bitcoinNetworkMode.rawValue,
            dogecoinNetworkMode: dogecoinNetworkMode.rawValue,
            bitcoinEsploraEndpoints: bitcoinEsploraEndpoints,
            bitcoinStopGap: bitcoinStopGap,
            bitcoinFeePriority: bitcoinFeePriority.rawValue,
            dogecoinFeePriority: dogecoinFeePriority.rawValue,
            hideBalances: hideBalances,
            useFaceID: useFaceID,
            useAutoLock: useAutoLock,
            useStrictRPCOnly: useStrictRPCOnly,
            requireBiometricForSendActions: requireBiometricForSendActions,
            usePriceAlerts: usePriceAlerts,
            useTransactionStatusNotifications: useTransactionStatusNotifications,
            useLargeMovementNotifications: useLargeMovementNotifications,
            automaticRefreshFrequencyMinutes: automaticRefreshFrequencyMinutes,
            backgroundSyncProfile: backgroundSyncProfile.rawValue,
            largeMovementAlertPercentThreshold: largeMovementAlertPercentThreshold,
            largeMovementAlertUSDThreshold: largeMovementAlertUSDThreshold,
            pinnedDashboardAssetSymbols: cachedPinnedDashboardAssetSymbols
        )
        guard let data = try? JSONEncoder().encode(settings), let json = String(data: data, encoding: .utf8) else { return }
        Task { await WalletServiceBridge.shared.saveAppSettings(json: json) }
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
    private func currentWalletSecretObservations(for walletIDs: Set<String>) -> [WalletRustSecretObservation] {
        walletIDs.map { walletID in
            let seedAccount = Self.seedPhraseAccount(for: walletID)
            let passwordAccount = Self.seedPhrasePasswordAccount(for: walletID)
            let privateKeyAccount = Self.privateKeyAccount(for: walletID)
            let hasSeedPhrase = ((try? SecureSeedStore.loadValue(for: seedAccount)) ?? "").isEmpty == false
            let hasPrivateKey = SecurePrivateKeyStore.loadValue(for: privateKeyAccount).isEmpty == false
            let hasPassword = SecureSeedPasswordStore.hasPassword(for: passwordAccount)
            let secretKind: String?
            if hasPrivateKey { secretKind = "privateKey" } else if hasSeedPhrase { secretKind = "seedPhrase" } else { secretKind = "watchOnly" }
            return WalletRustSecretObservation(
                walletID: walletID, secretKind: secretKind, hasSeedPhrase: hasSeedPhrase, hasPrivateKey: hasPrivateKey, hasPassword: hasPassword
            )
        }}
}
