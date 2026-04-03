import Foundation

enum WalletDerivationLayer {
    static func resolvedBitcoinAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? BitcoinWalletEngine.derivedAddress(
                for: wallet.id,
                seedPhrase: seedPhrase,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoin)
           ),
           AddressValidation.isValidBitcoinAddress(derivedAddress, networkMode: store.bitcoinNetworkMode(for: wallet)) {
            return derivedAddress
        }
        if let bitcoinAddress = wallet.bitcoinAddress,
           AddressValidation.isValidBitcoinAddress(bitcoinAddress, networkMode: store.bitcoinNetworkMode(for: wallet)) {
            return bitcoinAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedEthereumAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        resolvedEVMAddress(for: wallet, chainName: "Ethereum", using: store)
    }

    static func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String, using store: WalletStore) -> String? {
        guard store.isEVMChain(chainName) else { return nil }
        guard let chain = store.evmChainContext(for: chainName) else { return nil }
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivationChain = evmSeedDerivationChain(for: chainName),
           let derivedAddress = try? EthereumWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: derivationChain),
                chain: chain,
                derivationPath: store.walletDerivationPath(for: wallet, chain: derivationChain)
           ) {
            return derivedAddress
        }
        if let ethereumAddress = wallet.ethereumAddress,
           !ethereumAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EthereumWalletEngine.normalizeAddress(ethereumAddress)
        }
        return nil
    }

    static func resolvedTronAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? WalletStore.deriveTronAddress(seedPhrase: seedPhrase, wallet: wallet),
           AddressValidation.isValidTronAddress(derivedAddress) {
            return derivedAddress
        }

        if let tronAddress = wallet.tronAddress,
           AddressValidation.isValidTronAddress(tronAddress) {
            return tronAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedSolanaAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? SolanaWalletEngine.derivedAddress(
                for: seedPhrase,
                preference: store.solanaDerivationPreference(for: wallet),
                account: store.derivationAccount(for: wallet, chain: .solana)
           ),
           AddressValidation.isValidSolanaAddress(derivedAddress) {
            return derivedAddress
        }

        if let solanaAddress = wallet.solanaAddress,
           AddressValidation.isValidSolanaAddress(solanaAddress) {
            return solanaAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedSuiAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? SuiWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: .sui)
           ),
           AddressValidation.isValidSuiAddress(derivedAddress) {
            return derivedAddress
        }

        if let suiAddress = wallet.suiAddress,
           AddressValidation.isValidSuiAddress(suiAddress) {
            return suiAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return nil
    }

    static func resolvedAptosAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? AptosWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: .aptos)
           ),
           AddressValidation.isValidAptosAddress(derivedAddress) {
            return derivedAddress
        }

        if let aptosAddress = wallet.aptosAddress,
           AddressValidation.isValidAptosAddress(aptosAddress) {
            let trimmed = aptosAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
        }
        return nil
    }

    static func resolvedTONAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? TONWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: .ton)
           ),
           AddressValidation.isValidTONAddress(derivedAddress) {
            return derivedAddress
        }

        if let tonAddress = wallet.tonAddress,
           AddressValidation.isValidTONAddress(tonAddress) {
            return tonAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedICPAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? ICPWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: wallet.seedDerivationPaths.internetComputer
           ),
           AddressValidation.isValidICPAddress(derivedAddress) {
            return derivedAddress
        }

        if let icpAddress = wallet.icpAddress,
           AddressValidation.isValidICPAddress(icpAddress) {
            return icpAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return nil
    }

    static func resolvedNearAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? NearWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: .near)
           ),
           AddressValidation.isValidNearAddress(derivedAddress) {
            return derivedAddress.lowercased()
        }

        if let nearAddress = wallet.nearAddress,
           AddressValidation.isValidNearAddress(nearAddress) {
            return nearAddress
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        return nil
    }

    static func resolvedPolkadotAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? PolkadotWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: wallet.seedDerivationPaths.polkadot
           ),
           AddressValidation.isValidPolkadotAddress(derivedAddress) {
            return derivedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let polkadotAddress = wallet.polkadotAddress,
           AddressValidation.isValidPolkadotAddress(polkadotAddress) {
            return polkadotAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedStellarAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? StellarWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: wallet.seedDerivationPaths.stellar
           ),
           AddressValidation.isValidStellarAddress(derivedAddress) {
            return derivedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let stellarAddress = wallet.stellarAddress,
           AddressValidation.isValidStellarAddress(stellarAddress) {
            return stellarAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedCardanoAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let cardanoAddress = wallet.cardanoAddress,
           AddressValidation.isValidCardanoAddress(cardanoAddress) {
            return cardanoAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? CardanoWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .cardano)
           ),
           AddressValidation.isValidCardanoAddress(derivedAddress) {
            return derivedAddress
        }
        return nil
    }

    static func resolvedXRPAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? XRPWalletEngine.derivedAddress(
                for: seedPhrase,
                account: store.derivationAccount(for: wallet, chain: .xrp)
           ),
           AddressValidation.isValidXRPAddress(derivedAddress) {
            return derivedAddress
        }

        if let xrpAddress = wallet.xrpAddress,
           AddressValidation.isValidXRPAddress(xrpAddress) {
            return xrpAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        if let moneroAddress = wallet.moneroAddress,
           AddressValidation.isValidMoneroAddress(moneroAddress) {
            return moneroAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedDogecoinAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        let networkMode = store.dogecoinNetworkMode(for: wallet)
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? DogecoinWalletEngine.derivedAddress(
                for: seedPhrase,
                networkMode: networkMode,
                account: Int(store.derivationAccount(for: wallet, chain: .dogecoin))
           ),
           store.isValidDogecoinAddressForPolicy(derivedAddress, networkMode: networkMode) {
            return derivedAddress
        }
        if let dogecoinAddress = wallet.dogecoinAddress,
           store.isValidDogecoinAddressForPolicy(dogecoinAddress, networkMode: networkMode) {
            return dogecoinAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedLitecoinAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? LitecoinWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .litecoin)
           ),
           AddressValidation.isValidLitecoinAddress(derivedAddress) {
            return derivedAddress
        }
        if let litecoinAddress = wallet.litecoinAddress,
           AddressValidation.isValidLitecoinAddress(litecoinAddress) {
            return litecoinAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedBitcoinCashAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? BitcoinCashWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinCash)
           ),
           AddressValidation.isValidBitcoinCashAddress(derivedAddress) {
            return derivedAddress
        }
        if let bitcoinCashAddress = wallet.bitcoinCashAddress,
           AddressValidation.isValidBitcoinCashAddress(bitcoinCashAddress) {
            return bitcoinCashAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func resolvedBitcoinSVAddress(for wallet: ImportedWallet, using store: WalletStore) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id),
           let derivedAddress = try? BitcoinSVWalletEngine.derivedAddress(
                for: seedPhrase,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinSV)
           ),
           AddressValidation.isValidBitcoinSVAddress(derivedAddress) {
            return derivedAddress
        }
        if let bitcoinSVAddress = wallet.bitcoinSVAddress,
           AddressValidation.isValidBitcoinSVAddress(bitcoinSVAddress) {
            return bitcoinSVAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        switch chainName {
        case "Ethereum":
            return .ethereum
        case "Ethereum Classic":
            return .ethereumClassic
        case "Arbitrum":
            return .arbitrum
        case "BNB Chain":
            return .ethereum
        case "Avalanche":
            return .avalanche
        case "Hyperliquid":
            return .hyperliquid
        default:
            return nil
        }
    }
}
