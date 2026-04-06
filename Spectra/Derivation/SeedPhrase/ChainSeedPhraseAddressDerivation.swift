import Foundation
import WalletCore

enum SeedPhraseAddressDerivation {
    static func materialAddress(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String,
        normalizer: (String) -> String = { $0 }
    ) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: SeedPhraseSafety.normalizedPhrase(from: seedPhrase),
            coin: coin,
            derivationPath: derivationPath
        )
        return normalizer(material.address)
    }

    static func materialAddress(
        privateKeyHex: String,
        coin: WalletCoreSupportedCoin,
        normalizer: (String) -> String = { $0 }
    ) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(privateKeyHex: privateKeyHex, coin: coin)
        return normalizer(material.address)
    }

    static func bitcoinAddress(seedPhrase: String, derivationPath: String) throws -> String {
        try materialAddress(seedPhrase: seedPhrase, coin: .bitcoin, derivationPath: derivationPath)
    }

    static func bitcoinAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .bitcoin)
    }

    static func bitcoinCashAddress(seedPhrase: String, derivationPath: String) throws -> String {
        try materialAddress(seedPhrase: seedPhrase, coin: .bitcoinCash, derivationPath: derivationPath)
    }

    static func bitcoinCashAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .bitcoinCash)
    }

    static func bitcoinSVAddress(seedPhrase: String, derivationPath: String) throws -> String {
        try materialAddress(seedPhrase: seedPhrase, coin: .bitcoinSV, derivationPath: derivationPath)
    }

    static func bitcoinSVAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .bitcoinSV)
    }

    static func litecoinAddress(seedPhrase: String, derivationPath: String) throws -> String {
        try materialAddress(seedPhrase: seedPhrase, coin: .litecoin, derivationPath: derivationPath)
    }

    static func litecoinAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .litecoin)
    }

    static func dogecoinAddress(
        seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        isChange: Bool,
        index: Int,
        account: Int
    ) throws -> String {
        let accountIndex = UInt32(max(account, 0))
        let derivationPath = WalletDerivationPath.dogecoin(
            account: accountIndex,
            branch: isChange ? .change : .external,
            index: UInt32(max(index, 0))
        )
        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: SeedPhraseSafety.normalizedPhrase(from: seedPhrase),
            coin: .dogecoin,
            derivationPath: derivationPath,
            passphrase: nil
        )
        let address = try UTXOAddressCodec.legacyP2PKHAddress(
            privateKeyData: material.privateKeyData,
            version: DogecoinWalletEngine.p2pkhVersion(for: networkMode)
        )
        guard AddressValidation.isValidDogecoinAddress(address, networkMode: networkMode) else {
            throw WalletCoreDerivationError.invalidMnemonic
        }
        return address
    }

    static func dogecoinAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .dogecoin)
    }

    static func evmAddress(
        seedPhrase: String,
        account: UInt32,
        chain: EVMChainContext,
        derivationPath: String?
    ) throws -> String {
        let normalizedSeedPhrase = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)
        let wordCount = SeedPhraseSafety.normalizedWords(from: normalizedSeedPhrase).count
        guard wordCount > 0,
              SeedPhraseSafety.validationError(for: normalizedSeedPhrase, expectedWordCount: wordCount) == nil else {
            throw WalletCoreDerivationError.invalidMnemonic
        }

        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: normalizedSeedPhrase,
            coin: .ethereum,
            derivationPath: derivationPath ?? chain.derivationPath(account: account),
            passphrase: nil
        )
        return material.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func evmAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(privateKeyHex: privateKeyHex, coin: .ethereum)
        return material.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func tronAddress(seedPhrase: String, derivationPath: String) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: .tron,
            derivationPath: derivationPath,
            passphrase: nil
        )
        guard AddressValidation.isValidTronAddress(material.address) else {
            throw WalletCoreDerivationError.invalidMnemonic
        }
        return material.address
    }

    static func tronAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(privateKeyHex: privateKeyHex, coin: .tron)
        guard AddressValidation.isValidTronAddress(material.address) else {
            throw WalletCoreDerivationError.invalidPrivateKey
        }
        return material.address
    }

    static func solanaAddress(
        seedPhrase: String,
        preference: SolanaWalletEngine.DerivationPreference,
        account: UInt32
    ) throws -> String {
        let normalizedMnemonic = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)

        let preferredPath: String
        switch preference {
        case .standard:
            preferredPath = "m/44'/501'/\(account)'/0'"
        case .legacy:
            preferredPath = "m/44'/501'/\(account)'"
        }
        let candidatePaths = [
            preferredPath,
            "m/44'/501'/\(account)'/0'",
            "m/44'/501'/\(account)'"
        ]

        for path in candidatePaths {
            let result = try WalletDerivationEngine.derive(
                seedPhrase: normalizedMnemonic,
                request: WalletDerivationRequest(
                    chain: .solana,
                    network: .mainnet,
                    derivationPath: path,
                    curve: .ed25519,
                    requestedOutputs: [.address]
                )
            )
            guard let address = result.address else { continue }
            if AddressValidation.isValidSolanaAddress(address) {
                return address
            }
        }

        throw WalletCoreDerivationError.invalidMnemonic
    }

    static func solanaAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .solana)
    }

    static func xrpAddress(seedPhrase: String, account: UInt32 = 0) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .xrp,
            derivationPath: WalletDerivationPath.bip44(slip44CoinType: 144, account: account)
        )
    }

    static func xrpAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .xrp)
    }

    static func stellarAddress(seedPhrase: String, derivationPath: String = "m/44'/148'/0'") throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .stellar,
            derivationPath: derivationPath,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    static func stellarAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .stellar,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    static func cardanoAddress(seedPhrase: String, derivationPath: String) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .cardano,
            derivationPath: derivationPath
        )
    }

    static func cardanoAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .cardano)
    }

    static func suiAddress(seedPhrase: String, account: UInt32 = 0) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .sui,
            derivationPath: WalletDerivationPath.bip44(slip44CoinType: 784, account: account)
        )
    }

    static func suiAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .sui,
            normalizer: { $0.lowercased() }
        )
    }

    static func aptosAddress(seedPhrase: String, account: UInt32 = 0) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .aptos,
            derivationPath: "m/44'/637'/\(account)'/0'/0'",
            normalizer: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
            }
        )
    }

    static func aptosAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .aptos,
            normalizer: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
            }
        )
    }

    static func tonAddress(seedPhrase: String, account: UInt32 = 0) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .ton,
            derivationPath: "m/44'/607'/\(account)'/0/0",
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    static func tonAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .ton,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    static func icpAddress(seedPhrase: String, derivationPath: String = "m/44'/223'/0'/0/0") throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .internetComputer,
            derivationPath: derivationPath,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
    }

    static func icpAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .internetComputer,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
    }

    static func nearAddress(seedPhrase: String, account: UInt32 = 0) throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .near,
            derivationPath: "m/44'/397'/\(account)'",
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
    }

    static func nearAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(
            privateKeyHex: privateKeyHex,
            coin: .near,
            normalizer: { $0.lowercased() }
        )
    }

    static func polkadotAddress(seedPhrase: String, derivationPath: String = "m/44'/354'/0'") throws -> String {
        try materialAddress(
            seedPhrase: seedPhrase,
            coin: .polkadot,
            derivationPath: derivationPath,
            normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    static func polkadotAddress(forPrivateKey privateKeyHex: String) throws -> String {
        try materialAddress(privateKeyHex: privateKeyHex, coin: .polkadot)
    }

    static func address(
        for seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String,
        normalizer: (String) -> String = { $0 },
        validator: (String) -> Bool
    ) throws -> String {
        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: derivationPath,
            passphrase: nil
        )
        let normalized = normalizer(material.address)
        guard validator(normalized) else {
            throw WalletCoreDerivationError.invalidMnemonic
        }
        return normalized
    }

    static func address(
        forPrivateKey privateKeyHex: String,
        coin: WalletCoreSupportedCoin,
        normalizer: (String) -> String = { $0 },
        validator: (String) -> Bool
    ) throws -> String {
        let rawKey = try privateKeyData(from: privateKeyHex)
        guard let key = PrivateKey(data: rawKey) else {
            throw WalletCoreDerivationError.invalidPrivateKey
        }
        let address = coinType(for: coin).deriveAddress(privateKey: key)
        let normalized = normalizer(address)
        guard validator(normalized) else {
            throw WalletCoreDerivationError.invalidPrivateKey
        }
        return normalized
    }

    private static func privateKeyData(from rawValue: String) throws -> Data {
        let normalized = PrivateKeyHex.normalized(from: rawValue)
        guard normalized.count == 64 else {
            throw WalletCoreDerivationError.invalidPrivateKey
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index ..< nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw WalletCoreDerivationError.invalidPrivateKey
            }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }

    private static func coinType(for coin: WalletCoreSupportedCoin) -> CoinType {
        switch coin {
        case .bitcoin:
            return .bitcoin
        case .bitcoinCash:
            return .bitcoinCash
        case .bitcoinSV:
            return .bitcoin
        case .litecoin:
            return .litecoin
        case .dogecoin:
            return .dogecoin
        case .ethereum:
            return .ethereum
        case .tron:
            return .tron
        case .solana:
            return .solana
        case .stellar:
            return .stellar
        case .xrp:
            return .xrp
        case .cardano:
            return .cardano
        case .sui:
            return .sui
        case .aptos:
            return .aptos
        case .ton:
            return .ton
        case .internetComputer:
            return .internetComputer
        case .near:
            return .near
        case .polkadot:
            return .polkadot
        }
    }
}
