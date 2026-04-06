import Foundation

extension WalletStore {
    func persistCodableToUserDefaults<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func loadCodableFromUserDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func persistLivePrices() {
        persistCodableToUserDefaults(livePrices, key: Self.livePricesDefaultsKey)
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
    }

    func loadPersistedWallets() -> [ImportedWallet] {
        guard let data = SecureStore.loadData(for: Self.walletsAccount) else {
            return []
        }

        if let payload = try? Self.persistenceDecoder.decode(PersistedWalletStore.self, from: data),
           payload.version == PersistedWalletStore.currentVersion {
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

        return []
    }

    func storedWalletIDs() -> [UUID] {
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
}
