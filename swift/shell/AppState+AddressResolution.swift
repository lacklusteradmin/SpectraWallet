import Foundation

@MainActor
extension AppState {
    func solanaDerivationPreference(for wallet: ImportedWallet) -> SolanaDerivationPreference {
        derivationResolution(for: wallet, chain: .solana).flavor == .legacy ? .legacy : .standard
    }

    func resolvedEthereumAddress(for wallet: ImportedWallet) -> String? { resolvedEVMAddress(for: wallet, chainName: "Ethereum") }

    func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        guard isEVMChain(chainName), evmChainContext(for: chainName) != nil else { return nil }
        if let seedPhrase = storedSeedPhrase(for: wallet.id),
           let derivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: chainName),
           let derived = try? WalletDerivationLayer.deriveAddress(seedPhrase: seedPhrase, chain: derivationChain, network: .mainnet, derivationPath: walletDerivationPath(for: wallet, chain: derivationChain)) {
            return derived
        }
        if let addr = wallet.ethereumAddress, !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AddressValidation.normalized(addr, kind: "evm")
        }
        return nil
    }

    func resolvedBitcoinAddress(for wallet: ImportedWallet) -> String? {
        let networkMode = bitcoinNetworkMode(for: wallet)
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoin, network: derivationNetwork(for: networkMode),
            derivationPath: walletDerivationPath(for: wallet, chain: .bitcoin),
            storedAddress: wallet.bitcoinAddress,
            validationKind: "bitcoin", validationNetworkMode: networkMode.rawValue
        )
    }

    func resolvedDogecoinAddress(for wallet: ImportedWallet) -> String? {
        let networkMode = dogecoinNetworkMode(for: wallet)
        let derivationPath = WalletDerivationPath.dogecoin(
            account: derivationAccount(for: wallet, chain: .dogecoin), branch: .external, index: 0
        )
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: .dogecoin, network: derivationNetwork(for: networkMode),
            derivationPath: derivationPath, storedAddress: wallet.dogecoinAddress,
            validationKind: "dogecoin", validationNetworkMode: networkMode.rawValue
        )
    }

    func resolvedTronAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron,
            storedAddress: wallet.tronAddress, validationKind: "tron"
        )
    }

    func resolvedSolanaAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana),
            storedAddress: wallet.solanaAddress, validationKind: "solana"
        )
    }

    func resolvedSuiAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .sui, derivationPath: walletDerivationPath(for: wallet, chain: .sui),
            storedAddress: wallet.suiAddress, validationKind: "sui", normalizeStored: true
        )
    }

    func resolvedAptosAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .aptos, derivationPath: walletDerivationPath(for: wallet, chain: .aptos),
            storedAddress: wallet.aptosAddress, validationKind: "aptos", normalizeStored: true
        )
    }

    func resolvedTONAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .ton, derivationPath: walletDerivationPath(for: wallet, chain: .ton),
            storedAddress: wallet.tonAddress, validationKind: "ton", normalizeStored: true
        )
    }

    func resolvedICPAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .internetComputer, derivationPath: wallet.seedDerivationPaths.internetComputer,
            storedAddress: wallet.icpAddress, validationKind: "internetComputer", normalizeStored: true
        )
    }

    func resolvedNearAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near),
            storedAddress: wallet.nearAddress, validationKind: "near",
            derivedPostProcess: .lowercase, normalizeStored: true
        )
    }

    func resolvedPolkadotAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .polkadot, derivationPath: wallet.seedDerivationPaths.polkadot,
            storedAddress: wallet.polkadotAddress, validationKind: "polkadot",
            derivedPostProcess: .trim
        )
    }

    func resolvedStellarAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .stellar, derivationPath: wallet.seedDerivationPaths.stellar,
            storedAddress: wallet.stellarAddress, validationKind: "stellar",
            derivedPostProcess: .trim
        )
    }

    func resolvedCardanoAddress(for wallet: ImportedWallet) -> String? {
        if let addr = wallet.cardanoAddress, AddressValidation.isValid(addr, kind: "cardano") {
            return addr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let seedPhrase = storedSeedPhrase(for: wallet.id),
           let derived = try? WalletDerivationLayer.deriveAddress(seedPhrase: seedPhrase, chain: .cardano, network: .mainnet, derivationPath: walletDerivationPath(for: wallet, chain: .cardano)),
           AddressValidation.isValid(derived, kind: "cardano") {
            return derived
        }
        return nil
    }

    func resolvedXRPAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .xrp, derivationPath: walletDerivationPath(for: wallet, chain: .xrp),
            storedAddress: wallet.xrpAddress, validationKind: "xrp"
        )
    }

    func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        guard let addr = wallet.moneroAddress, AddressValidation.isValid(addr, kind: "monero") else { return nil }
        return addr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedLitecoinAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .litecoin, derivationPath: walletDerivationPath(for: wallet, chain: .litecoin),
            storedAddress: wallet.litecoinAddress, validationKind: "litecoin"
        )
    }

    func resolvedBitcoinCashAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoinCash, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoinCash),
            storedAddress: wallet.bitcoinCashAddress, validationKind: "bitcoinCash"
        )
    }

    func resolvedBitcoinSVAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoinSV, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoinSV),
            storedAddress: wallet.bitcoinSvAddress, validationKind: "bitcoinSV"
        )
    }

    func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        switch chainName {
        case "Bitcoin": return resolvedBitcoinAddress(for: wallet)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV": return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin": return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin": return resolvedDogecoinAddress(for: wallet)
        case "Tron": return resolvedTronAddress(for: wallet)
        case "Solana": return resolvedSolanaAddress(for: wallet)
        case "Stellar": return resolvedStellarAddress(for: wallet)
        case "XRP Ledger": return resolvedXRPAddress(for: wallet)
        case "Monero": return resolvedMoneroAddress(for: wallet)
        case "Cardano": return resolvedCardanoAddress(for: wallet)
        case "Sui": return resolvedSuiAddress(for: wallet)
        case "Aptos": return resolvedAptosAddress(for: wallet)
        case "TON": return resolvedTONAddress(for: wallet)
        case "Internet Computer": return resolvedICPAddress(for: wallet)
        case "NEAR": return resolvedNearAddress(for: wallet)
        case "Polkadot": return resolvedPolkadotAddress(for: wallet)
        default:
            if isEVMChain(chainName) { return resolvedEVMAddress(for: wallet, chainName: chainName) }
            return nil
        }
    }

    func walletWithResolvedDogecoinAddress(_ wallet: ImportedWallet) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: resolvedDogecoinAddress(for: wallet) ?? wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress,
            aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress,
            icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress, seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths, selectedChain: wallet.selectedChain,
            holdings: wallet.holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
    }

    private func resolveDerivedOrStoredAddress(
        for wallet: ImportedWallet,
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork = .mainnet,
        derivationPath: String,
        storedAddress: String?,
        validationKind: String,
        validationNetworkMode: String? = nil,
        derivedPostProcess: DerivedAddressPostProcess = .none,
        normalizeStored: Bool = false
    ) -> String? {
        let derived: String? = {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { return nil }
            return try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath
            )
        }()
        return corePlanResolveDerivedOrStoredAddress(
            derived: derived, stored: storedAddress, validationKind: validationKind,
            validationNetworkMode: validationNetworkMode, derivedPostProcess: derivedPostProcess,
            normalizeStored: normalizeStored
        )
    }
}
enum AddressValidation {
    nonisolated static func isValid(_ address: String, kind: String, networkMode: String? = nil) -> Bool {
        coreValidateAddress(request: AddressValidationRequest(kind: kind, value: address, networkMode: networkMode)).isValid
    }
    nonisolated static func normalized(_ address: String, kind: String, networkMode: String? = nil) -> String? {
        coreValidateAddress(request: AddressValidationRequest(kind: kind, value: address, networkMode: networkMode)).normalizedValue
    }
    nonisolated static func isValidAptosTokenType(_ value: String) -> Bool {
        coreValidateStringIdentifier(request: StringValidationRequest(kind: "aptosTokenType", value: value)).isValid
    }
}
