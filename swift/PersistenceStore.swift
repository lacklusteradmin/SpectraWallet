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
        // Core-owned domain state first: it is the authority, so anything
        // loaded after it must not contradict it.
        await loadCoreOwnedState()
        await diagnostics.loadFromSQLite()
        if let prices = await loadCodableFromSQLite([String: Double].self, key: Self.livePricesDefaultsKey), !prices.isEmpty {
            livePrices = prices
        }
        // `loadCoreOwnedState()` above already set `tokenPreferences` from core.
        // Folding in the built-ins catches tokens this build added; the didSet
        // commits the merged list straight back.
        tokenPreferences = mergeBuiltInTokenPreferences(with: tokenPreferences)
        if let alertsPayload = try? await WalletServiceBridge.shared.loadPriceAlertStore(key: Self.priceAlertsDefaultsKey),
            alertsPayload.version == 1
        {
            priceAlerts = alertsPayload.alerts.compactMap(PriceAlertRule.init(snapshot:))
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
        // Reserves receive indices, so it runs only after core's keypool is in
        // memory — reserving against an unloaded table would reissue addresses.
        await syncChainOwnedAddressManagementState()
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
        } else {
            // No SQLite settings yet — persist current (UserDefaults-loaded) values to SQLite for future launches
            persistAppSettings()
        }
        // ── Wallet projection, from the store core owns ───────────────────────
        if let stored = try? await WalletServiceBridge.shared.storedWallets(), !stored.isEmpty {
            adoptWalletsFromCore(stored)
            rebuildWalletDerivedState()
        }
        // ── Transaction projection, from the store core owns ──────────────────
        if let stored = try? await WalletServiceBridge.shared.storedTransactions() {
            let records = stored.compactMap(TransactionRecord.init(snapshot:))
            if !records.isEmpty {
                adoptTransactionsFromCore(records)
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
    func persistPriceAlerts() {
        let payload = CorePersistedPriceAlertStore(
            version: 1, alerts: priceAlerts.map(\.persistedSnapshot)
        )
        Task {
            try? await WalletServiceBridge.shared.savePriceAlertStore(
                key: Self.priceAlertsDefaultsKey, value: payload)
        }
    }
    /// Send the tracked-token list to core, which clamps it and stores it.
    func commitTokenPreferences() {
        let entries = tokenPreferences
        Task { @MainActor [weak self] in
            guard let self else { return }
            let epoch = self.beginCoreStateRead()
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .setTokenPreferences(entries: entries))
            else { return }
            self.applyCoreState(transition.state, epoch: epoch)
        }
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
            // selectedFiatCurrency is core-owned; see AppState.selectedFiatCurrency.
            selectedFiatCurrency: coreFiatCurrency.rawValue,
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
            largeMovementAlertUsdThreshold: preferences.largeMovementAlertUSDThreshold
        )
        Task { try? await WalletServiceBridge.shared.saveAppSettingsTyped(settings: settings) }
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
    // correct and complete.
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
