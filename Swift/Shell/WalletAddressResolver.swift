import Foundation
enum WalletAddressResolver {
    static func resolvedBitcoinAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .bitcoin, network: bitcoinNetwork(for: store.bitcoinNetworkMode(for: wallet)), derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoin)
           ), AddressValidation.isValidBitcoinAddress(derivedAddress, networkMode: store.bitcoinNetworkMode(for: wallet)) {
            return derivedAddress
        }
        if let bitcoinAddress = wallet.bitcoinAddress, AddressValidation.isValidBitcoinAddress(bitcoinAddress, networkMode: store.bitcoinNetworkMode(for: wallet)) { return bitcoinAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedEthereumAddress(for wallet: ImportedWallet, using store: AppState) -> String? { resolvedEVMAddress(for: wallet, chainName: "Ethereum", using: store) }
    static func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String, using store: AppState) -> String? {
        guard store.isEVMChain(chainName) else { return nil }
        guard store.evmChainContext(for: chainName) != nil else { return nil }
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: chainName), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: derivationChain, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: derivationChain)
           ) {
            return derivedAddress
        }
        if let ethereumAddress = wallet.ethereumAddress, !ethereumAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return AddressValidation.normalizedEthereumAddress(ethereumAddress) }
        return nil
    }
    static func resolvedTronAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .tron, network: .mainnet, derivationPath: wallet.seedDerivationPaths.tron
           ), AddressValidation.isValidTronAddress(derivedAddress) {
            return derivedAddress
        }
        if let tronAddress = wallet.tronAddress, AddressValidation.isValidTronAddress(tronAddress) { return tronAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedSolanaAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .solana, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .solana)
           ), AddressValidation.isValidSolanaAddress(derivedAddress) {
            return derivedAddress
        }
        if let solanaAddress = wallet.solanaAddress, AddressValidation.isValidSolanaAddress(solanaAddress) { return solanaAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedSuiAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .sui, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .sui)
           ), AddressValidation.isValidSuiAddress(derivedAddress) {
            return derivedAddress
        }
        if let suiAddress = wallet.suiAddress, let normalizedAddress = AddressValidation.normalizedSuiAddress(suiAddress) { return normalizedAddress }
        return nil
    }
    static func resolvedAptosAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .aptos, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .aptos)
           ), AddressValidation.isValidAptosAddress(derivedAddress) {
            return derivedAddress
        }
        if let aptosAddress = wallet.aptosAddress, let normalizedAddress = AddressValidation.normalizedAptosAddress(aptosAddress) { return normalizedAddress }
        return nil
    }
    static func resolvedTONAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .ton, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .ton)
           ), AddressValidation.isValidTONAddress(derivedAddress) {
            return derivedAddress
        }
        if let tonAddress = wallet.tonAddress, let normalizedAddress = AddressValidation.normalizedTONAddress(tonAddress) { return normalizedAddress }
        return nil
    }
    static func resolvedICPAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .internetComputer, network: .mainnet, derivationPath: wallet.seedDerivationPaths.internetComputer
           ), AddressValidation.isValidICPAddress(derivedAddress) {
            return derivedAddress
        }
        if let icpAddress = wallet.icpAddress, let normalizedAddress = AddressValidation.normalizedICPAddress(icpAddress) { return normalizedAddress }
        return nil
    }
    static func resolvedNearAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .near, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .near)
           ), AddressValidation.isValidNearAddress(derivedAddress) {
            return derivedAddress.lowercased()
        }
        if let nearAddress = wallet.nearAddress, let normalizedAddress = AddressValidation.normalizedNearAddress(nearAddress) { return normalizedAddress }
        return nil
    }
    static func resolvedPolkadotAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .polkadot, network: .mainnet, derivationPath: wallet.seedDerivationPaths.polkadot
           ), AddressValidation.isValidPolkadotAddress(derivedAddress) {
            return derivedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let polkadotAddress = wallet.polkadotAddress, AddressValidation.isValidPolkadotAddress(polkadotAddress) { return polkadotAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedStellarAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .stellar, network: .mainnet, derivationPath: wallet.seedDerivationPaths.stellar
           ), AddressValidation.isValidStellarAddress(derivedAddress) {
            return derivedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let stellarAddress = wallet.stellarAddress, AddressValidation.isValidStellarAddress(stellarAddress) { return stellarAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedCardanoAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let cardanoAddress = wallet.cardanoAddress, AddressValidation.isValidCardanoAddress(cardanoAddress) { return cardanoAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .cardano, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .cardano)
           ), AddressValidation.isValidCardanoAddress(derivedAddress) {
            return derivedAddress
        }
        return nil
    }
    static func resolvedXRPAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .xrp, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .xrp)
           ), AddressValidation.isValidXRPAddress(derivedAddress) {
            return derivedAddress
        }
        if let xrpAddress = wallet.xrpAddress, AddressValidation.isValidXRPAddress(xrpAddress) { return xrpAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedAddress(for wallet: ImportedWallet, chainName: String, using store: AppState) -> String? {
        switch chainName {
        case "Bitcoin": return resolvedBitcoinAddress(for: wallet, using: store)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet, using: store)
        case "Bitcoin SV": return resolvedBitcoinSVAddress(for: wallet, using: store)
        case "Litecoin": return resolvedLitecoinAddress(for: wallet, using: store)
        case "Dogecoin": return resolvedDogecoinAddress(for: wallet, using: store)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return resolvedEVMAddress(for: wallet, chainName: chainName, using: store)
        case "Tron": return resolvedTronAddress(for: wallet, using: store)
        case "Solana": return resolvedSolanaAddress(for: wallet, using: store)
        case "Stellar": return resolvedStellarAddress(for: wallet, using: store)
        case "XRP Ledger": return resolvedXRPAddress(for: wallet, using: store)
        case "Monero": return resolvedMoneroAddress(for: wallet)
        case "Cardano": return resolvedCardanoAddress(for: wallet, using: store)
        case "Sui": return resolvedSuiAddress(for: wallet, using: store)
        case "Aptos": return resolvedAptosAddress(for: wallet, using: store)
        case "TON": return resolvedTONAddress(for: wallet, using: store)
        case "Internet Computer": return resolvedICPAddress(for: wallet, using: store)
        case "NEAR": return resolvedNearAddress(for: wallet, using: store)
        case "Polkadot": return resolvedPolkadotAddress(for: wallet, using: store)
        default: return nil
        }}
    static func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        if let moneroAddress = wallet.moneroAddress, AddressValidation.isValidMoneroAddress(moneroAddress) { return moneroAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedDogecoinAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        let networkMode = store.dogecoinNetworkMode(for: wallet)
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .dogecoin, network: dogecoinNetwork(for: networkMode), derivationPath: WalletDerivationPath.dogecoin(
                    account: store.derivationAccount(for: wallet, chain: .dogecoin), branch: .external, index: 0
                )
           ), store.isValidDogecoinAddressForPolicy(derivedAddress, networkMode: networkMode) {
            return derivedAddress
        }
        if let dogecoinAddress = wallet.dogecoinAddress, store.isValidDogecoinAddressForPolicy(dogecoinAddress, networkMode: networkMode) { return dogecoinAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedLitecoinAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .litecoin, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .litecoin)
           ), AddressValidation.isValidLitecoinAddress(derivedAddress) {
            return derivedAddress
        }
        if let litecoinAddress = wallet.litecoinAddress, AddressValidation.isValidLitecoinAddress(litecoinAddress) { return litecoinAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedBitcoinCashAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .bitcoinCash, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinCash)
           ), AddressValidation.isValidBitcoinCashAddress(derivedAddress) {
            return derivedAddress
        }
        if let bitcoinCashAddress = wallet.bitcoinCashAddress, AddressValidation.isValidBitcoinCashAddress(bitcoinCashAddress) { return bitcoinCashAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    static func resolvedBitcoinSVAddress(for wallet: ImportedWallet, using store: AppState) -> String? {
        if let seedPhrase = store.storedSeedPhrase(for: wallet.id), let derivedAddress = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .bitcoinSV, network: .mainnet, derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinSV)
           ), AddressValidation.isValidBitcoinSVAddress(derivedAddress) {
            return derivedAddress
        }
        if let bitcoinSvAddress = wallet.bitcoinSvAddress, AddressValidation.isValidBitcoinSVAddress(bitcoinSvAddress) { return bitcoinSvAddress.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }
    private static func bitcoinNetwork(for networkMode: BitcoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .testnet4: return .testnet4
        case .signet: return .signet
        }}
    private static func dogecoinNetwork(for networkMode: DogecoinNetworkMode) -> WalletDerivationNetwork {
        switch networkMode {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        }}
}
