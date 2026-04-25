import Foundation
extension AppState {
    func loadCodableFromUserDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func persistCodableToSQLite<T: Encodable & Sendable>(_ value: T, key: String) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
            try? await WalletServiceBridge.shared.saveState(key: key, stateJSON: json)
        }
    }
    func loadCodableFromSQLite<T: Decodable>(_ type: T.Type, key: String) async -> T? {
        guard let json = try? await WalletServiceBridge.shared.loadState(key: key), json != "{}", let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
    func reloadPersistedStateFromSQLite() async {
        await diagnostics.loadFromSQLite()
        if let prices = await loadCodableFromSQLite([String: Double].self, key: Self.livePricesDefaultsKey), !prices.isEmpty {
            livePrices = prices
        }
        if let tokenPrefs = await loadCodableFromSQLite([TokenPreferenceEntry].self, key: Self.tokenPreferencesDefaultsKey),
            !tokenPrefs.isEmpty
        {
            tokenPreferences = mergeBuiltInTokenPreferences(with: tokenPrefs)
        }
        if let alertsJSON = try? await WalletServiceBridge.shared.loadState(key: Self.priceAlertsDefaultsKey), alertsJSON != "{}",
            let alertsPayload = try? decodePersistedPriceAlertStoreJson(json: alertsJSON), alertsPayload.version == 1
        {
            priceAlerts = alertsPayload.alerts.compactMap(PriceAlertRule.init(snapshot:))
        }
        if let abJSON = try? await WalletServiceBridge.shared.loadState(key: Self.addressBookDefaultsKey), abJSON != "{}",
            let abPayload = try? decodePersistedAddressBookStoreJson(json: abJSON), abPayload.version == 1
        {
            setAddressBook(abPayload.entries.compactMap(AddressBookEntry.init(snapshot:)))
        }
        if let allKeypool = try? await WalletServiceBridge.shared.loadAllKeypoolStateTyped(), !allKeypool.isEmpty {
            var rebuiltChains: [String: [String: ChainKeypoolState]] = [:]
            for (chainName, walletMap) in allKeypool {
                var rebuilt: [String: ChainKeypoolState] = [:]
                for (uuidStr, state) in walletMap {
                    rebuilt[uuidStr] = ChainKeypoolState(
                        nextExternalIndex: Int(state.nextExternalIndex), nextChangeIndex: Int(state.nextChangeIndex),
                        reservedReceiveIndex: state.reservedReceiveIndex.map { Int($0) }
                    )
                }
                if !rebuilt.isEmpty { rebuiltChains[chainName] = rebuilt }
            }
            if !rebuiltChains.isEmpty { chainKeypoolByChain = rebuiltChains }
        }
        if let allRecords = try? await WalletServiceBridge.shared.loadAllOwnedAddressesTyped(), !allRecords.isEmpty {
            var chainMap: [String: [String: ChainOwnedAddressRecord]] = [:]
            for rec in allRecords {
                guard !rec.address.isEmpty else { continue }
                let chainRecord = ChainOwnedAddressRecord(
                    chainName: rec.chainName, address: rec.address, walletID: rec.walletId, derivationPath: rec.derivationPath,
                    index: rec.branchIndex.map { Int($0) }, branch: rec.branch
                )
                chainMap[rec.chainName, default: [:]][rec.address] = chainRecord
            }
            if !chainMap.isEmpty { chainOwnedAddressMapByChain = chainMap }
        }
        if let rates = await loadCodableFromSQLite([String: Double].self, key: Self.fiatRatesFromUSDDefaultsKey), !rates.isEmpty {
            fiatRatesFromUSD = rates
            fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        }
        if let decimals = await loadCodableFromSQLite([String: Int].self, key: Self.assetDisplayDecimalsByChainDefaultsKey),
            !decimals.isEmpty
        {
            assetDisplayDecimalsByChain = decimals
        }
        if let events = await loadCodableFromSQLite([String: [ChainOperationalEvent]].self, key: Self.chainOperationalEventsDefaultsKey),
            !events.isEmpty
        {
            chainOperationalEventsByChain = events
        }
        if let feePrios = await loadCodableFromSQLite([String: String].self, key: Self.selectedFeePriorityOptionsByChainDefaultsKey),
            !feePrios.isEmpty
        {
            selectedFeePriorityOptionRawByChain = feePrios
        }
        if !wallets.isEmpty {
            let summaries: [WalletSummary] = wallets.map { $0.walletSummary }
            try? await WalletServiceBridge.shared.initWalletStateDirect(wallets: summaries)
        }
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
            preferences.hideBalances = settings.hideBalances
            preferences.useFaceID = settings.useFaceId
            preferences.useAutoLock = settings.useAutoLock
            preferences.useStrictRPCOnly = settings.useStrictRpcOnly
            preferences.requireBiometricForSendActions = settings.requireBiometricForSendActions
            preferences.usePriceAlerts = settings.usePriceAlerts
            preferences.useTransactionStatusNotifications = settings.useTransactionStatusNotifications
            preferences.useLargeMovementNotifications = settings.useLargeMovementNotifications
            preferences.automaticRefreshFrequencyMinutes = Int(settings.automaticRefreshFrequencyMinutes)
            preferences.largeMovementAlertPercentThreshold = settings.largeMovementAlertPercentThreshold
            preferences.largeMovementAlertUSDThreshold = settings.largeMovementAlertUsdThreshold
            if !settings.pinnedDashboardAssetSymbols.isEmpty { cachedPinnedDashboardAssetSymbols = settings.pinnedDashboardAssetSymbols }
        } else {
            // No SQLite settings yet — persist current (UserDefaults-loaded) values to SQLite for future launches
            persistAppSettings()
        }
        // ── Load transaction history from Rust SQLite ─────────────────────────
        if let rustRecords = try? await WalletServiceBridge.shared.fetchAllHistoryRecordsTyped(),
            !rustRecords.isEmpty
        {
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
        }
    }
    func persistLivePrices() {
        persistCodableToSQLite(livePrices, key: Self.livePricesDefaultsKey)
    }
    func loadAssetDisplayDecimalsByChain() -> [String: Int]? {
        loadCodableFromUserDefaults([String: Int].self, key: Self.assetDisplayDecimalsByChainDefaultsKey)
    }
    func loadPersistedLivePrices() -> [String: Double] {
        loadCodableFromUserDefaults([String: Double].self, key: Self.livePricesDefaultsKey) ?? [:]
    }
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
            if !filtered.isEmpty { partialResult[entry.key] = filtered }
        }
        chainKeypoolByChain = chainKeypoolByChain.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { walletID, _ in
                currentWalletIDs.contains(walletID)
            }
            if !filtered.isEmpty { partialResult[entry.key] = filtered }
        }
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
        if let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
            payload.version == PersistedWalletStore.currentVersion
        {
            return payload.wallets.map { $0.id }
        }
        return []
    }
    func sanitizedWallet(_ wallet: ImportedWallet) -> ImportedWallet {
        let supportedHoldings = wallet.holdings.filter { coin in AppEndpointDirectory.supportsBalanceRefresh(for: coin.chainName) }
        return ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress, bitcoinXpub: wallet.bitcoinXpub,
            bitcoinCashAddress: wallet.bitcoinCashAddress, bitcoinSvAddress: wallet.bitcoinSvAddress,
            litecoinAddress: wallet.litecoinAddress, dogecoinAddress: wallet.dogecoinAddress, ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress, solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress, cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress, aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress, icpAddress: wallet.icpAddress,
            nearAddress: wallet.nearAddress, polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            derivationOverrides: wallet.derivationOverrides,
            selectedChain: wallet.selectedChain, holdings: supportedHoldings,
            includeInPortfolioTotal: wallet.includeInPortfolioTotal
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
            payload.version == 1
        else { return [] }
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
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms debounce
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
            hideBalances: preferences.hideBalances,
            useFaceId: preferences.useFaceID,
            useAutoLock: preferences.useAutoLock,
            useStrictRpcOnly: preferences.useStrictRPCOnly,
            requireBiometricForSendActions: preferences.requireBiometricForSendActions,
            usePriceAlerts: preferences.usePriceAlerts,
            useTransactionStatusNotifications: preferences.useTransactionStatusNotifications,
            useLargeMovementNotifications: preferences.useLargeMovementNotifications,
            automaticRefreshFrequencyMinutes: Int32(preferences.automaticRefreshFrequencyMinutes),
            backgroundSyncProfile: backgroundSyncProfile.rawValue,
            largeMovementAlertPercentThreshold: preferences.largeMovementAlertPercentThreshold,
            largeMovementAlertUsdThreshold: preferences.largeMovementAlertUSDThreshold,
            pinnedDashboardAssetSymbols: cachedPinnedDashboardAssetSymbols
        )
        Task { try? await WalletServiceBridge.shared.saveAppSettingsTyped(settings: settings) }
    }
    func loadPersistedTokenPreferences() -> [TokenPreferenceEntry] {
        guard
            let decoded = loadCodableFromUserDefaults(
                [TokenPreferenceEntry].self, key: Self.tokenPreferencesDefaultsKey
            )
        else {
            return ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        }
        return mergeBuiltInTokenPreferences(with: decoded)
    }
    func loadPersistedPriceAlerts() -> [PriceAlertRule] {
        guard let data = UserDefaults.standard.data(forKey: Self.priceAlertsDefaultsKey),
            let json = String(data: data, encoding: .utf8),
            let payload = try? decodePersistedPriceAlertStoreJson(json: json),
            payload.version == 1
        else { return [] }
        return payload.alerts.compactMap(PriceAlertRule.init(snapshot:))
    }
    private func decodedWalletSnapshots(from data: Data) -> [ImportedWallet]? {
        guard let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
            payload.version == PersistedWalletStore.currentVersion
        else { return nil }
        return payload.wallets.compactMap { snapshot in
            let hasSeedPhrase = walletHasSigningMaterial(snapshot.id)
            let hasWatchOnlyAddress = [
                snapshot.bitcoinAddress, snapshot.bitcoinXpub, snapshot.litecoinAddress, snapshot.dogecoinAddress, snapshot.ethereumAddress,
                snapshot.tronAddress, snapshot.solanaAddress, snapshot.xrpAddress, snapshot.stellarAddress, snapshot.moneroAddress,
                snapshot.cardanoAddress, snapshot.suiAddress, snapshot.nearAddress, snapshot.polkadotAddress,
            ]
            .contains { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            guard hasSeedPhrase || hasWatchOnlyAddress else { return nil }
            let wallet = sanitizedWallet(ImportedWallet(snapshot: snapshot))
            #if DEBUG
                logBalanceTelemetry(source: "local", chainName: "PersistedWalletStore", wallet: wallet, holdings: wallet.holdings)
            #endif
            return wallet
        }
    }
}
struct PersistedCoin: Codable {
    let name: String
    let symbol: String
    let coinGeckoId: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUsd: Double
}
struct PersistedWallet: Codable {
    let id: String
    let name: String
    let bitcoinNetworkMode: BitcoinNetworkMode
    let dogecoinNetworkMode: DogecoinNetworkMode
    let bitcoinAddress: String?
    let bitcoinXpub: String?
    let bitcoinCashAddress: String?
    let bitcoinSvAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let stellarAddress: String?
    let xrpAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
    let seedDerivationPreset: SeedDerivationPreset
    let seedDerivationPaths: SeedDerivationPaths
    let derivationOverrides: CoreWalletDerivationOverrides
    let selectedChain: String
    let holdings: [PersistedCoin]
    let includeInPortfolioTotal: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bitcoinNetworkMode
        case dogecoinNetworkMode
        case bitcoinAddress
        case bitcoinXpub
        case bitcoinCashAddress
        case bitcoinSvAddress
        case litecoinAddress
        case dogecoinAddress
        case ethereumAddress
        case tronAddress
        case solanaAddress
        case stellarAddress
        case xrpAddress
        case moneroAddress
        case cardanoAddress
        case suiAddress
        case aptosAddress
        case tonAddress
        case icpAddress
        case nearAddress
        case polkadotAddress
        case seedDerivationPreset
        case seedDerivationPaths
        case derivationOverrides
        case selectedChain
        case holdings
        case includeInPortfolioTotal
    }
    init(
        id: String, name: String, bitcoinNetworkMode: BitcoinNetworkMode = .mainnet, dogecoinNetworkMode: DogecoinNetworkMode = .mainnet,
        bitcoinAddress: String?, bitcoinXpub: String?, bitcoinCashAddress: String?, bitcoinSvAddress: String?, litecoinAddress: String?,
        dogecoinAddress: String?, ethereumAddress: String?, tronAddress: String?, solanaAddress: String?, stellarAddress: String?,
        xrpAddress: String?, moneroAddress: String?, cardanoAddress: String?, suiAddress: String?, aptosAddress: String?,
        tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?,
        seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths,
        derivationOverrides: CoreWalletDerivationOverrides = CoreWalletDerivationOverrides(
            passphrase: nil, mnemonicWordlist: nil, iterationCount: nil, saltPrefix: nil, hmacKey: nil,
            curve: nil, derivationAlgorithm: nil, addressAlgorithm: nil, publicKeyFormat: nil, scriptType: nil
        ),
        selectedChain: String,
        holdings: [PersistedCoin], includeInPortfolioTotal: Bool
    ) {
        self.id = id
        self.name = name
        self.bitcoinNetworkMode = bitcoinNetworkMode
        self.dogecoinNetworkMode = dogecoinNetworkMode
        self.bitcoinAddress = bitcoinAddress
        self.bitcoinXpub = bitcoinXpub
        self.bitcoinCashAddress = bitcoinCashAddress
        self.bitcoinSvAddress = bitcoinSvAddress
        self.litecoinAddress = litecoinAddress
        self.dogecoinAddress = dogecoinAddress
        self.ethereumAddress = ethereumAddress
        self.tronAddress = tronAddress
        self.solanaAddress = solanaAddress
        self.stellarAddress = stellarAddress
        self.xrpAddress = xrpAddress
        self.moneroAddress = moneroAddress
        self.cardanoAddress = cardanoAddress
        self.suiAddress = suiAddress
        self.aptosAddress = aptosAddress
        self.tonAddress = tonAddress
        self.icpAddress = icpAddress
        self.nearAddress = nearAddress
        self.polkadotAddress = polkadotAddress
        self.seedDerivationPreset = seedDerivationPreset
        self.seedDerivationPaths = seedDerivationPaths
        self.derivationOverrides = derivationOverrides
        self.selectedChain = selectedChain
        self.holdings = holdings
        self.includeInPortfolioTotal = includeInPortfolioTotal
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bitcoinNetworkMode = try container.decodeIfPresent(BitcoinNetworkMode.self, forKey: .bitcoinNetworkMode) ?? .mainnet
        dogecoinNetworkMode = try container.decodeIfPresent(DogecoinNetworkMode.self, forKey: .dogecoinNetworkMode) ?? .mainnet
        bitcoinAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinAddress)
        bitcoinXpub = try container.decodeIfPresent(String.self, forKey: .bitcoinXpub)
        bitcoinCashAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinCashAddress)
        bitcoinSvAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinSvAddress)
        litecoinAddress = try container.decodeIfPresent(String.self, forKey: .litecoinAddress)
        dogecoinAddress = try container.decodeIfPresent(String.self, forKey: .dogecoinAddress)
        ethereumAddress = try container.decodeIfPresent(String.self, forKey: .ethereumAddress)
        tronAddress = try container.decodeIfPresent(String.self, forKey: .tronAddress)
        solanaAddress = try container.decodeIfPresent(String.self, forKey: .solanaAddress)
        stellarAddress = try container.decodeIfPresent(String.self, forKey: .stellarAddress)
        xrpAddress = try container.decodeIfPresent(String.self, forKey: .xrpAddress)
        moneroAddress = try container.decodeIfPresent(String.self, forKey: .moneroAddress)
        cardanoAddress = try container.decodeIfPresent(String.self, forKey: .cardanoAddress)
        suiAddress = try container.decodeIfPresent(String.self, forKey: .suiAddress)
        aptosAddress = try container.decodeIfPresent(String.self, forKey: .aptosAddress)
        tonAddress = try container.decodeIfPresent(String.self, forKey: .tonAddress)
        icpAddress = try container.decodeIfPresent(String.self, forKey: .icpAddress)
        nearAddress = try container.decodeIfPresent(String.self, forKey: .nearAddress)
        polkadotAddress = try container.decodeIfPresent(String.self, forKey: .polkadotAddress)
        seedDerivationPreset = try container.decode(SeedDerivationPreset.self, forKey: .seedDerivationPreset)
        seedDerivationPaths = try container.decode(SeedDerivationPaths.self, forKey: .seedDerivationPaths)
        derivationOverrides =
            try container.decodeIfPresent(CoreWalletDerivationOverrides.self, forKey: .derivationOverrides)
            ?? CoreWalletDerivationOverrides(
                passphrase: nil, mnemonicWordlist: nil, iterationCount: nil, saltPrefix: nil, hmacKey: nil,
                curve: nil, derivationAlgorithm: nil, addressAlgorithm: nil, publicKeyFormat: nil, scriptType: nil
            )
        selectedChain = try container.decode(String.self, forKey: .selectedChain)
        holdings = try container.decode([PersistedCoin].self, forKey: .holdings)
        includeInPortfolioTotal = try container.decode(Bool.self, forKey: .includeInPortfolioTotal)
    }
}
struct PersistedWalletStore: Codable {
    let version: Int
    let wallets: [PersistedWallet]
    static let currentVersion = 5
}
private enum SeedDerivationPathsCodingKeys: String, CodingKey {
    case isCustomEnabled
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case avalanche
    case hyperliquid
    case polygon
    case base
    case linea
    case scroll
    case blast
    case mantle
    case tron
    case solana
    case stellar
    case xrp
    case cardano
    case sui
    case aptos
    case ton
    case internetComputer
    case near
    case polkadot
}
private enum WalletDerivationOverridesCodingKeys: String, CodingKey {
    case passphrase
    case mnemonicWordlist
    case iterationCount
    case saltPrefix
    case hmacKey
    case curve
    case derivationAlgorithm
    case addressAlgorithm
    case publicKeyFormat
    case scriptType
}
extension CoreWalletDerivationOverrides: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WalletDerivationOverridesCodingKeys.self)
        self.init(
            passphrase: try container.decodeIfPresent(String.self, forKey: .passphrase),
            mnemonicWordlist: try container.decodeIfPresent(String.self, forKey: .mnemonicWordlist),
            iterationCount: try container.decodeIfPresent(UInt32.self, forKey: .iterationCount),
            saltPrefix: try container.decodeIfPresent(String.self, forKey: .saltPrefix),
            hmacKey: try container.decodeIfPresent(String.self, forKey: .hmacKey),
            curve: try container.decodeIfPresent(String.self, forKey: .curve),
            derivationAlgorithm: try container.decodeIfPresent(String.self, forKey: .derivationAlgorithm),
            addressAlgorithm: try container.decodeIfPresent(String.self, forKey: .addressAlgorithm),
            publicKeyFormat: try container.decodeIfPresent(String.self, forKey: .publicKeyFormat),
            scriptType: try container.decodeIfPresent(String.self, forKey: .scriptType)
        )
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WalletDerivationOverridesCodingKeys.self)
        try container.encodeIfPresent(passphrase, forKey: .passphrase)
        try container.encodeIfPresent(mnemonicWordlist, forKey: .mnemonicWordlist)
        try container.encodeIfPresent(iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(saltPrefix, forKey: .saltPrefix)
        try container.encodeIfPresent(hmacKey, forKey: .hmacKey)
        try container.encodeIfPresent(curve, forKey: .curve)
        try container.encodeIfPresent(derivationAlgorithm, forKey: .derivationAlgorithm)
        try container.encodeIfPresent(addressAlgorithm, forKey: .addressAlgorithm)
        try container.encodeIfPresent(publicKeyFormat, forKey: .publicKeyFormat)
        try container.encodeIfPresent(scriptType, forKey: .scriptType)
    }
}
extension SeedDerivationPaths: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        self = SeedDerivationPaths.defaults
        isCustomEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCustomEnabled) ?? false
        bitcoin = try container.decodeIfPresent(String.self, forKey: .bitcoin) ?? SeedDerivationChain.bitcoin.defaultPath
        bitcoinCash = try container.decodeIfPresent(String.self, forKey: .bitcoinCash) ?? SeedDerivationChain.bitcoinCash.defaultPath
        bitcoinSV = try container.decodeIfPresent(String.self, forKey: .bitcoinSV) ?? SeedDerivationChain.bitcoinSV.defaultPath
        litecoin = try container.decodeIfPresent(String.self, forKey: .litecoin) ?? SeedDerivationChain.litecoin.defaultPath
        dogecoin = try container.decodeIfPresent(String.self, forKey: .dogecoin) ?? SeedDerivationChain.dogecoin.defaultPath
        ethereum = try container.decodeIfPresent(String.self, forKey: .ethereum) ?? SeedDerivationChain.ethereum.defaultPath
        ethereumClassic =
            try container.decodeIfPresent(String.self, forKey: .ethereumClassic) ?? SeedDerivationChain.ethereumClassic.defaultPath
        arbitrum = try container.decodeIfPresent(String.self, forKey: .arbitrum) ?? SeedDerivationChain.arbitrum.defaultPath
        optimism = try container.decodeIfPresent(String.self, forKey: .optimism) ?? SeedDerivationChain.optimism.defaultPath
        avalanche = try container.decodeIfPresent(String.self, forKey: .avalanche) ?? SeedDerivationChain.avalanche.defaultPath
        hyperliquid = try container.decodeIfPresent(String.self, forKey: .hyperliquid) ?? SeedDerivationChain.hyperliquid.defaultPath
        polygon = try container.decodeIfPresent(String.self, forKey: .polygon) ?? SeedDerivationChain.polygon.defaultPath
        base = try container.decodeIfPresent(String.self, forKey: .base) ?? SeedDerivationChain.base.defaultPath
        linea = try container.decodeIfPresent(String.self, forKey: .linea) ?? SeedDerivationChain.linea.defaultPath
        scroll = try container.decodeIfPresent(String.self, forKey: .scroll) ?? SeedDerivationChain.scroll.defaultPath
        blast = try container.decodeIfPresent(String.self, forKey: .blast) ?? SeedDerivationChain.blast.defaultPath
        mantle = try container.decodeIfPresent(String.self, forKey: .mantle) ?? SeedDerivationChain.mantle.defaultPath
        tron = try container.decodeIfPresent(String.self, forKey: .tron) ?? SeedDerivationChain.tron.defaultPath
        solana = try container.decodeIfPresent(String.self, forKey: .solana) ?? SeedDerivationChain.solana.defaultPath
        stellar = try container.decodeIfPresent(String.self, forKey: .stellar) ?? SeedDerivationChain.stellar.defaultPath
        xrp = try container.decodeIfPresent(String.self, forKey: .xrp) ?? SeedDerivationChain.xrp.defaultPath
        cardano = try container.decodeIfPresent(String.self, forKey: .cardano) ?? SeedDerivationChain.cardano.defaultPath
        sui = try container.decodeIfPresent(String.self, forKey: .sui) ?? SeedDerivationChain.sui.defaultPath
        aptos = try container.decodeIfPresent(String.self, forKey: .aptos) ?? SeedDerivationChain.aptos.defaultPath
        ton = try container.decodeIfPresent(String.self, forKey: .ton) ?? SeedDerivationChain.ton.defaultPath
        internetComputer =
            try container.decodeIfPresent(String.self, forKey: .internetComputer) ?? SeedDerivationChain.internetComputer.defaultPath
        near = try container.decodeIfPresent(String.self, forKey: .near) ?? SeedDerivationChain.near.defaultPath
        polkadot = try container.decodeIfPresent(String.self, forKey: .polkadot) ?? SeedDerivationChain.polkadot.defaultPath
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        try container.encode(isCustomEnabled, forKey: .isCustomEnabled)
        try container.encode(bitcoin, forKey: .bitcoin)
        try container.encode(bitcoinCash, forKey: .bitcoinCash)
        try container.encode(bitcoinSV, forKey: .bitcoinSV)
        try container.encode(litecoin, forKey: .litecoin)
        try container.encode(dogecoin, forKey: .dogecoin)
        try container.encode(ethereum, forKey: .ethereum)
        try container.encode(ethereumClassic, forKey: .ethereumClassic)
        try container.encode(arbitrum, forKey: .arbitrum)
        try container.encode(optimism, forKey: .optimism)
        try container.encode(avalanche, forKey: .avalanche)
        try container.encode(hyperliquid, forKey: .hyperliquid)
        try container.encode(polygon, forKey: .polygon)
        try container.encode(base, forKey: .base)
        try container.encode(linea, forKey: .linea)
        try container.encode(scroll, forKey: .scroll)
        try container.encode(blast, forKey: .blast)
        try container.encode(mantle, forKey: .mantle)
        try container.encode(tron, forKey: .tron)
        try container.encode(solana, forKey: .solana)
        try container.encode(stellar, forKey: .stellar)
        try container.encode(xrp, forKey: .xrp)
        try container.encode(cardano, forKey: .cardano)
        try container.encode(sui, forKey: .sui)
        try container.encode(aptos, forKey: .aptos)
        try container.encode(ton, forKey: .ton)
        try container.encode(internetComputer, forKey: .internetComputer)
        try container.encode(near, forKey: .near)
        try container.encode(polkadot, forKey: .polkadot)
    }
}
