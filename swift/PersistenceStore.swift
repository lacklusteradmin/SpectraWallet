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
        if let alertsPayload = try? await WalletServiceBridge.shared.loadPriceAlertStore(key: Self.priceAlertsDefaultsKey),
            alertsPayload.version == 1
        {
            priceAlerts = alertsPayload.alerts.compactMap(PriceAlertRule.init(snapshot:))
        }
        if let abPayload = try? await WalletServiceBridge.shared.loadAddressBookStore(key: Self.addressBookDefaultsKey),
            abPayload.version == 1
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
            let rustTransactions = rustRecords.compactMap { rec in
                TransactionRecord(snapshot: rec.payload)
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
        var sanitized = wallet
        sanitized.holdings = wallet.holdings.filter { coin in
            AppEndpointDirectory.supportsBalanceRefresh(for: coin.chainName)
        }
        return sanitized
    }
    func persistPriceAlerts() {
        let payload = CorePersistedPriceAlertStore(
            version: 1, alerts: priceAlerts.map(\.persistedSnapshot)
        )
        Task {
            try? await WalletServiceBridge.shared.savePriceAlertStore(
                key: Self.priceAlertsDefaultsKey, value: payload)
        }
    }
    func persistAddressBook() {
        let payload = CorePersistedAddressBookStore(
            version: 1, entries: addressBook.map(\.persistedSnapshot)
        )
        Task {
            try? await WalletServiceBridge.shared.saveAddressBookStore(
                key: Self.addressBookDefaultsKey, value: payload)
        }
    }
    func persistTokenPreferences() {
        persistCodableToSQLite(tokenPreferences, key: Self.tokenPreferencesDefaultsKey)
    }
    // ── App settings persistence (Rust SQLite) ─────────────────────────────────
    /// Debounced — coalesces rapid-fire settings changes (e.g. slider drags,
    /// multiple toggles in quick succession) into a single SQLite write.
    func persistAppSettings() {
        appSettingsPersist.fire { [weak self] in self?.persistAppSettingsNow() }
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
    private func decodedWalletSnapshots(from data: Data) -> [ImportedWallet]? {
        guard let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
            payload.version == PersistedWalletStore.currentVersion
        else { return nil }
        return payload.wallets.compactMap { snapshot in
            let hasSeedPhrase = walletHasSigningMaterial(snapshot.id)
            // Any stored address counts. This used to be a hand-written list of
            // 14 chains, which meant a watch-only wallet on one of the other
            // ten — Kaspa, Dash, Zcash, TON, ICP, Aptos, Bitcoin Cash,
            // Bitcoin SV, Bitcoin Gold, Decred, Bittensor — failed the check
            // and was dropped from the store on load.
            let hasWatchOnlyAddress =
                snapshot.addresses.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                || (snapshot.bitcoinXpub ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
/// On-disk mirror of `ImportedWallet`.
///
/// `addresses` is the same slot-keyed map the Rust record uses, so `Codable`
/// is synthesized apart from the tolerances below. What used to be here was 26
/// per-chain fields repeated four times over — declarations, an initializer's
/// parameters, its assignments, and a hand-written decoder — roughly 180 lines
/// that had to grow with every chain added.
struct PersistedWallet: Codable {
    let id: String
    let name: String
    let bitcoinNetworkMode: BitcoinNetworkMode
    let dogecoinNetworkMode: DogecoinNetworkMode
    /// `Chain::address_slot()` → address.
    let addresses: [String: String]
    let bitcoinXpub: String?
    let seedDerivationPreset: SeedDerivationPreset
    let seedDerivationPaths: SeedDerivationPaths
    let derivationOverrides: CoreWalletDerivationOverrides
    let selectedChain: String
    let holdings: [PersistedCoin]
    let includeInPortfolioTotal: Bool

    init(
        id: String, name: String,
        bitcoinNetworkMode: BitcoinNetworkMode = .mainnet,
        dogecoinNetworkMode: DogecoinNetworkMode = .mainnet,
        addresses: [String: String],
        bitcoinXpub: String? = nil,
        seedDerivationPreset: SeedDerivationPreset,
        seedDerivationPaths: SeedDerivationPaths,
        derivationOverrides: CoreWalletDerivationOverrides = .empty,
        selectedChain: String,
        holdings: [PersistedCoin],
        includeInPortfolioTotal: Bool
    ) {
        self.id = id
        self.name = name
        self.bitcoinNetworkMode = bitcoinNetworkMode
        self.dogecoinNetworkMode = dogecoinNetworkMode
        self.addresses = addresses
        self.bitcoinXpub = bitcoinXpub
        self.seedDerivationPreset = seedDerivationPreset
        self.seedDerivationPaths = seedDerivationPaths
        self.derivationOverrides = derivationOverrides
        self.selectedChain = selectedChain
        self.holdings = holdings
        self.includeInPortfolioTotal = includeInPortfolioTotal
    }

    // Explicit decoder only for the fields that tolerate absence; everything
    // else is required and should fail loudly.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bitcoinNetworkMode = try container.decodeIfPresent(BitcoinNetworkMode.self, forKey: .bitcoinNetworkMode) ?? .mainnet
        dogecoinNetworkMode = try container.decodeIfPresent(DogecoinNetworkMode.self, forKey: .dogecoinNetworkMode) ?? .mainnet
        addresses = try container.decodeIfPresent([String: String].self, forKey: .addresses) ?? [:]
        bitcoinXpub = try container.decodeIfPresent(String.self, forKey: .bitcoinXpub)
        seedDerivationPreset = try container.decode(SeedDerivationPreset.self, forKey: .seedDerivationPreset)
        seedDerivationPaths = try container.decode(SeedDerivationPaths.self, forKey: .seedDerivationPaths)
        derivationOverrides =
            try container.decodeIfPresent(CoreWalletDerivationOverrides.self, forKey: .derivationOverrides) ?? .empty
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
    // `byChain` is a plain [String: String], so the synthesized Codable is
    // correct and complete. What used to be here was a 44-entry table of
    // (coding key, key path, chain) that had to be extended for every new
    // chain, plus a `SeedDerivationPathsCodingKeys` enum to match.
    private enum CodingKeys: String, CodingKey {
        case isCustomEnabled
        case byChain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Start from catalog defaults so a payload written before a chain
        // existed still yields a usable path for it.
        var byChain = SeedDerivationPaths.defaults.byChain
        for (key, path) in try container.decodeIfPresent([String: String].self, forKey: .byChain) ?? [:] {
            byChain[key] = path
        }
        self.init(
            isCustomEnabled: try container.decodeIfPresent(Bool.self, forKey: .isCustomEnabled) ?? false,
            byChain: byChain
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isCustomEnabled, forKey: .isCustomEnabled)
        try container.encode(byChain, forKey: .byChain)
    }
}
