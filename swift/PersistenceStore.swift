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
        // Folding in the built-ins catches tokens this build added. Core does
        // the merge and stores it, so this only adopts the answer — assigning
        // through the `didSet` would send it straight back.
        if let merged = try? await WalletServiceBridge.shared.mergeBuiltInTokenPreferences() {
            applyCoreState(merged, epoch: beginCoreStateRead())
        }
        // Price alerts arrive with the rest of the state — `loadCoreOwnedState()`
        // above already set them.
        // Owned addresses load with the rest of core's state in `open_state`.
        // Reserves receive indices, so it runs only after core's keypool is in
        // memory — reserving against an unloaded table would reissue addresses.
        await syncChainOwnedAddressManagementState()
        if let rates = await loadCodableFromSQLite([String: Double].self, key: Self.fiatRatesFromUSDDefaultsKey), !rates.isEmpty {
            fiatRatesFromUSD = rates
            fiatRatesFromUSD[FiatCurrency.usd.rawValue] = 1.0
        }
        // The eighteen settings core owns arrive with `loadCoreOwnedState()`
        // above, through `applyCoreState`. What is left here is the four this
        // platform keeps: hiding balances, Face ID, auto-lock and
        // biometric-gated sends, which no other front end has a use for.
        if let platform = await loadCodableFromSQLite(
            PlatformPreferences.self, key: Self.platformPreferencesDefaultsKey)
        {
            preferences.applyPlatform(platform)
        }
        // ── Wallet projection, from the store core owns ───────────────────────
        if let stored = try? await WalletServiceBridge.shared.storedWallets(), !stored.isEmpty {
            adoptWalletsFromCore(stored)
            rebuildWalletDerivedState()
        }
        // ── Transaction projection, from the store core owns ──────────────────
        //
        // No orphan prune here, unlike the two sites that follow a wallet
        // mutation. This load reads the wallet list and the transaction list a
        // moment apart, so a wallet recorded while it was in flight is missing
        // from the first read and present in neither — and the prune deleted
        // that wallet's transactions from the store, permanently, for having no
        // wallet. Losing a record of a real send is the worse side; an orphan
        // row shows an extra history entry until the next wallet mutation
        // prunes it. The wallet-deletion path removes a wallet's transactions
        // itself, so this was cleanup for a case that path already covers.
        if let stored = try? await WalletServiceBridge.shared.storedTransactions() {
            let records = stored.compactMap(TransactionRecord.init(snapshot:))
            if !records.isEmpty {
                adoptTransactionsFromCore(records)
                await rebuildTransactionDerivedState()
            }
        }
    }
    func persistLivePrices() {
        persistCodableToSQLite(livePrices, key: Self.livePricesDefaultsKey)
    }
    func loadPersistedLivePrices() -> [String: Double] {
        loadCodableFromUserDefaults([String: Double].self, key: Self.livePricesDefaultsKey) ?? [:]
    }
    /// Send the alert list to core, which drops what could never fire and
    /// stores the rest.
    func commitPriceAlerts() {
        let alerts = priceAlerts
        let epoch = beginCoreStateRead()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .setPriceAlerts(alerts: alerts))
            else {
                self.finishCoreStateRead(epoch)
                return
            }
            self.applyCoreState(transition.state, epoch: epoch)
        }
    }
    /// Tell core which network of a family the user picked.
    func commitNetworkChain(_ chainID: String) {
        let epoch = beginCoreStateRead()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .selectNetworkChain(chainId: chainID))
            else {
                self.finishCoreStateRead(epoch)
                return
            }
            self.applyCoreState(transition.state, epoch: epoch)
        }
    }
    /// Send the known-token list to core, which clamps it and stores it.
    func commitTokenPreferences() {
        let entries = tokenPreferences
        let epoch = beginCoreStateRead()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard
                let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                    .setTokenPreferences(entries: entries))
            else {
                self.finishCoreStateRead(epoch)
                return
            }
            self.applyCoreState(transition.state, epoch: epoch)
        }
    }
    // ── Settings ──────────────────────────────────────────────────────────────
    /// Debounced — a slider drag or a typed endpoint would otherwise be one
    /// command per frame or per keystroke.
    func commitAppSettingsSoon() {
        if pendingAppSettingsEpoch == nil { pendingAppSettingsEpoch = beginCoreStateRead() }
        appSettingsPersist.fire { [weak self] in self?.commitAppSettings() }
    }
    /// The four this platform keeps. A blob, because it is one front end's
    /// preferences and nothing else reads it.
    func persistPlatformPreferences() {
        persistCodableToSQLite(preferences.platformSnapshot, key: Self.platformPreferencesDefaultsKey)
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
