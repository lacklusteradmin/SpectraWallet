import Foundation

// MARK: - Rust SQLite decode helpers (file-private)

/// Mirrors `KeypoolState` from wallet_db.rs (camelCase via serde rename_all).
private struct RustKeypoolState: Decodable {
    let nextExternalIndex: Int
    let nextChangeIndex: Int
    let reservedReceiveIndex: Int?
}

/// Mirrors `OwnedAddressRecord` from wallet_db.rs (camelCase via serde rename_all).
private struct RustOwnedAddressRecord: Decodable {
    let walletId: String
    let chainName: String
    let address: String
    let derivationPath: String?
    let branch: String?
    let branchIndex: Int?
}

extension WalletStore {
    func persistCodableToUserDefaults<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func loadCodableFromUserDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: SQLite dual-write helpers

    /// Fire-and-forget async SQLite write. Safe to call from synchronous `didSet` observers.
    func persistCodableToSQLite<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            try? await WalletServiceBridge.shared.saveState(key: key, stateJSON: json)
        }
    }

    /// Async SQLite read. Returns nil when the key is absent or the JSON cannot be decoded.
    func loadCodableFromSQLite<T: Decodable>(_ type: T.Type, key: String) async -> T? {
        guard let json = try? await WalletServiceBridge.shared.loadState(key: key),
              json != "{}",
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// After synchronous startup (which reads from UserDefaults), this method reads SQLite and
    /// overwrites in-memory state with the durable copy — so SQLite is the authoritative backend.
    func reloadPersistedStateFromSQLite() async {
        if let prices = await loadCodableFromSQLite([String: Double].self, key: Self.livePricesDefaultsKey),
           !prices.isEmpty {
            livePrices = prices
        }
        if let tokenPrefs = await loadCodableFromSQLite([TokenPreferenceEntry].self, key: Self.tokenPreferencesDefaultsKey),
           !tokenPrefs.isEmpty {
            tokenPreferences = mergeBuiltInTokenPreferences(with: tokenPrefs)
        }
        if let alertsPayload = await loadCodableFromSQLite(PersistedPriceAlertStore.self, key: Self.priceAlertsDefaultsKey),
           alertsPayload.version == PersistedPriceAlertStore.currentVersion {
            priceAlerts = alertsPayload.alerts.map(PriceAlertRule.init(snapshot:))
        }
        if let abPayload = await loadCodableFromSQLite(PersistedAddressBookStore.self, key: Self.addressBookDefaultsKey),
           abPayload.version == PersistedAddressBookStore.currentVersion {
            addressBook = abPayload.entries.map {
                AddressBookEntry(id: $0.id, name: $0.name, chainName: $0.chainName, address: $0.address, note: $0.note)
            }
        }

        // Load keypool state from Rust SQLite (authoritative after first write-through).
        // JSON shape: { chainName: { walletUUIDString: { nextExternalIndex, nextChangeIndex, reservedReceiveIndex } } }
        if let keypoolJSON = try? await WalletServiceBridge.shared.loadAllKeypoolState(),
           let keypoolData = keypoolJSON.data(using: .utf8),
           let allKeypool = try? JSONDecoder().decode(
               [String: [String: RustKeypoolState]].self, from: keypoolData
           ),
           !allKeypool.isEmpty {
            // Dogecoin maps to its own dedicated dictionary.
            if let dogeWalletMap = allKeypool["Dogecoin"] {
                var rebuilt: [UUID: DogecoinKeypoolState] = [:]
                for (uuidStr, state) in dogeWalletMap {
                    guard let uuid = UUID(uuidString: uuidStr) else { continue }
                    rebuilt[uuid] = DogecoinKeypoolState(
                        nextExternalIndex: state.nextExternalIndex,
                        nextChangeIndex: state.nextChangeIndex,
                        reservedReceiveIndex: state.reservedReceiveIndex
                    )
                }
                if !rebuilt.isEmpty { dogecoinKeypoolByWalletID = rebuilt }
            }
            // All other chains go into chainKeypoolByChain.
            var rebuiltChains: [String: [UUID: ChainKeypoolState]] = [:]
            for (chainName, walletMap) in allKeypool where chainName != "Dogecoin" {
                var rebuilt: [UUID: ChainKeypoolState] = [:]
                for (uuidStr, state) in walletMap {
                    guard let uuid = UUID(uuidString: uuidStr) else { continue }
                    rebuilt[uuid] = ChainKeypoolState(
                        nextExternalIndex: state.nextExternalIndex,
                        nextChangeIndex: state.nextChangeIndex,
                        reservedReceiveIndex: state.reservedReceiveIndex
                    )
                }
                if !rebuilt.isEmpty { rebuiltChains[chainName] = rebuilt }
            }
            if !rebuiltChains.isEmpty { chainKeypoolByChain = rebuiltChains }
        }

        // Load owned address maps from Rust SQLite.
        // JSON shape: array of { walletId, chainName, address, derivationPath?, branch?, branchIndex? }
        if let addrJSON = try? await WalletServiceBridge.shared.loadAllOwnedAddresses(),
           let addrData = addrJSON.data(using: .utf8),
           let allRecords = try? JSONDecoder().decode([RustOwnedAddressRecord].self, from: addrData),
           !allRecords.isEmpty {
            var dogeMap: [String: DogecoinOwnedAddressRecord] = [:]
            var chainMap: [String: [String: ChainOwnedAddressRecord]] = [:]
            for rec in allRecords {
                guard let walletUUID = UUID(uuidString: rec.walletId),
                      !rec.address.isEmpty else { continue }
                if rec.chainName == "Dogecoin" {
                    dogeMap[rec.address] = DogecoinOwnedAddressRecord(
                        address: rec.address,
                        walletID: walletUUID,
                        derivationPath: rec.derivationPath ?? "",
                        index: rec.branchIndex.map(Int.init) ?? 0,
                        branch: rec.branch ?? ""
                    )
                } else {
                    let chainRecord = ChainOwnedAddressRecord(
                        chainName: rec.chainName,
                        address: rec.address,
                        walletID: walletUUID,
                        derivationPath: rec.derivationPath,
                        index: rec.branchIndex.map(Int.init),
                        branch: rec.branch
                    )
                    chainMap[rec.chainName, default: [:]][rec.address] = chainRecord
                }
            }
            if !dogeMap.isEmpty { dogecoinOwnedAddressMap = dogeMap }
            if !chainMap.isEmpty { chainOwnedAddressMapByChain = chainMap }
        }
    }

    func persistLivePrices() {
        persistCodableToUserDefaults(livePrices, key: Self.livePricesDefaultsKey)
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
            storedWalletIDs().forEach { walletID in
                deleteWalletSecrets(for: walletID)
            }
            SecureStore.deleteValue(for: Self.walletsAccount)
            SecureStore.deleteValue(for: Self.walletsCoreSnapshotAccount)
            clearWalletSecretIndex()
            dogecoinOwnedAddressMap = [:]
            chainOwnedAddressMapByChain = [:]
            chainKeypoolByChain = [:]
            return
        }

        let currentWalletIDs = Set(wallets.map(\.id))
        storedWalletIDs()
            .filter { !currentWalletIDs.contains($0) }
            .forEach { walletID in
                deleteWalletSecrets(for: walletID)
            }

        dogecoinOwnedAddressMap = dogecoinOwnedAddressMap.filter { _, value in
            currentWalletIDs.contains(value.walletID)
        }
        chainOwnedAddressMapByChain = chainOwnedAddressMapByChain.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { _, value in
                currentWalletIDs.contains(value.walletID)
            }
            if !filtered.isEmpty {
                partialResult[entry.key] = filtered
            }
        }
        chainKeypoolByChain = chainKeypoolByChain.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { walletID, _ in
                currentWalletIDs.contains(walletID)
            }
            if !filtered.isEmpty {
                partialResult[entry.key] = filtered
            }
        }
        syncChainOwnedAddressManagementState()

        let snapshots = wallets
            .map(sanitizedWallet)
            .map(\.persistedSnapshot)
        let payload = PersistedWalletStore(
            version: PersistedWalletStore.currentVersion,
            wallets: snapshots
        )
        guard let data = try? Self.persistenceEncoder.encode(payload) else {
            return
        }
        SecureStore.saveData(data, for: Self.walletsAccount)
        if let coreStateData = try? WalletRustAppCoreBridge.migrateLegacyWalletStoreData(data),
           let coreSnapshotData = try? WalletRustAppCoreBridge.buildPersistedSnapshotData(
                appStateData: coreStateData,
                secretObservations: currentWalletSecretObservations(for: currentWalletIDs)
           ) {
            SecureStore.saveData(coreSnapshotData, for: Self.walletsCoreSnapshotAccount)
            if let secretIndex = try? WalletRustAppCoreBridge.walletSecretIndex(fromCoreSnapshotData: coreSnapshotData) {
                applyWalletSecretIndex(secretIndex)
            }
        } else if let coreStateData = try? WalletRustAppCoreBridge.migrateLegacyWalletStoreData(data) {
            SecureStore.saveData(coreStateData, for: Self.walletsCoreSnapshotAccount)
        }
    }

    func loadPersistedWallets() -> [ImportedWallet] {
        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount),
           let secretIndex = try? WalletRustAppCoreBridge.walletSecretIndex(fromCoreSnapshotData: coreSnapshotData) {
            applyWalletSecretIndex(secretIndex)
        } else {
            clearWalletSecretIndex()
        }

        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount),
           let exportedLegacyData = try? WalletRustAppCoreBridge.exportLegacyWalletStoreData(fromCoreStateData: coreSnapshotData),
           let wallets = decodedWalletSnapshots(from: exportedLegacyData) {
            return wallets
        }

        guard let data = SecureStore.loadData(for: Self.walletsAccount) else {
            return []
        }

        return decodedWalletSnapshots(from: data) ?? []
    }

    func storedWalletIDs() -> [UUID] {
        if let coreSnapshotData = SecureStore.loadData(for: Self.walletsCoreSnapshotAccount),
           let exportedLegacyData = try? WalletRustAppCoreBridge.exportLegacyWalletStoreData(fromCoreStateData: coreSnapshotData),
           let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: exportedLegacyData),
           payload.version == PersistedWalletStore.currentVersion {
            return payload.wallets.map { $0.id }
        }

        guard let data = SecureStore.loadData(for: Self.walletsAccount) else {
            return []
        }

        if let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
           payload.version == PersistedWalletStore.currentVersion {
            return payload.wallets.map { $0.id }
        }

        return []
    }

    func sanitizedWallet(_ wallet: ImportedWallet) -> ImportedWallet {
        let supportedHoldings = wallet.holdings.filter { coin in
            ChainBackendRegistry.supportsBalanceRefresh(for: coin.chainName)
        }.map { coin in
            Coin(
                name: coin.name,
                symbol: coin.symbol,
                marketDataID: coin.marketDataID,
                coinGeckoID: coin.coinGeckoID,
                chainName: coin.chainName,
                tokenStandard: coin.tokenStandard,
                contractAddress: coin.contractAddress,
                amount: coin.amount,
                priceUSD: coin.priceUSD,
                mark: coin.mark,
                color: coin.color
            )
        }

        return ImportedWallet(
            id: wallet.id,
            name: wallet.name,
            bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode,
            bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXPub: wallet.bitcoinXPub,
            bitcoinCashAddress: wallet.bitcoinCashAddress,
            litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress,
            tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress,
            stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress,
            moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress,
            suiAddress: wallet.suiAddress,
            nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            selectedChain: wallet.selectedChain,
            holdings: supportedHoldings
        )
    }

    func persistPriceAlerts() {
        let payload = PersistedPriceAlertStore(
            version: PersistedPriceAlertStore.currentVersion,
            alerts: priceAlerts.map(\.persistedSnapshot)
        )
        persistCodableToUserDefaults(payload, key: Self.priceAlertsDefaultsKey)
        persistCodableToSQLite(payload, key: Self.priceAlertsDefaultsKey)
    }

    func persistAddressBook() {
        let payload = PersistedAddressBookStore(
            version: PersistedAddressBookStore.currentVersion,
            entries: addressBook.map {
                PersistedAddressBookEntry(
                    id: $0.id,
                    name: $0.name,
                    chainName: $0.chainName,
                    address: $0.address,
                    note: $0.note
                )
            }
        )
        persistCodableToUserDefaults(payload, key: Self.addressBookDefaultsKey)
        persistCodableToSQLite(payload, key: Self.addressBookDefaultsKey)
    }

    func loadPersistedAddressBook() -> [AddressBookEntry] {
        guard let payload = loadCodableFromUserDefaults(
            PersistedAddressBookStore.self,
            key: Self.addressBookDefaultsKey
        ) else {
            return []
        }
        guard payload.version == PersistedAddressBookStore.currentVersion else {
            return []
        }
        return payload.entries.map {
            AddressBookEntry(
                id: $0.id,
                name: $0.name,
                chainName: $0.chainName,
                address: $0.address,
                note: $0.note
            )
        }
    }

    func persistTokenPreferences() {
        persistCodableToUserDefaults(tokenPreferences, key: Self.tokenPreferencesDefaultsKey)
        persistCodableToSQLite(tokenPreferences, key: Self.tokenPreferencesDefaultsKey)
    }

    func loadPersistedTokenPreferences() -> [TokenPreferenceEntry] {
        guard let decoded = loadCodableFromUserDefaults(
            [TokenPreferenceEntry].self,
            key: Self.tokenPreferencesDefaultsKey
        ) else {
            return ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry)
        }
        return mergeBuiltInTokenPreferences(with: decoded)
    }

    func loadPersistedPriceAlerts() -> [PriceAlertRule] {
        guard let payload = loadCodableFromUserDefaults(PersistedPriceAlertStore.self, key: Self.priceAlertsDefaultsKey),
              payload.version == PersistedPriceAlertStore.currentVersion else {
            return []
        }
        return payload.alerts.map(PriceAlertRule.init(snapshot:))
    }

    private func decodedWalletSnapshots(from data: Data) -> [ImportedWallet]? {
        guard let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
              payload.version == PersistedWalletStore.currentVersion else {
            return nil
        }

        return payload.wallets.compactMap { snapshot in
            let hasSeedPhrase = walletHasSigningMaterial(snapshot.id)
            let hasWatchOnlyAddress = [
                snapshot.bitcoinAddress,
                snapshot.bitcoinXPub,
                snapshot.litecoinAddress,
                snapshot.dogecoinAddress,
                snapshot.ethereumAddress,
                snapshot.tronAddress,
                snapshot.solanaAddress,
                snapshot.xrpAddress,
                snapshot.stellarAddress,
                snapshot.moneroAddress,
                snapshot.cardanoAddress,
                snapshot.suiAddress,
                snapshot.nearAddress,
                snapshot.polkadotAddress
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

    private func currentWalletSecretObservations(for walletIDs: Set<UUID>) -> [WalletRustSecretObservation] {
        walletIDs.map { walletID in
            let seedAccount = Self.seedPhraseAccount(for: walletID)
            let passwordAccount = Self.seedPhrasePasswordAccount(for: walletID)
            let privateKeyAccount = Self.privateKeyAccount(for: walletID)

            let hasSeedPhrase = ((try? SecureSeedStore.loadValue(for: seedAccount)) ?? "").isEmpty == false
            let hasPrivateKey = SecurePrivateKeyStore.loadValue(for: privateKeyAccount).isEmpty == false
            let hasPassword = SecureSeedPasswordStore.hasPassword(for: passwordAccount)
            let secretKind: String?
            if hasPrivateKey {
                secretKind = "privateKey"
            } else if hasSeedPhrase {
                secretKind = "seedPhrase"
            } else {
                secretKind = "watchOnly"
            }

            return WalletRustSecretObservation(
                walletID: walletID.uuidString,
                secretKind: secretKind,
                hasSeedPhrase: hasSeedPhrase,
                hasPrivateKey: hasPrivateKey,
                hasPassword: hasPassword
            )
        }
    }
}
