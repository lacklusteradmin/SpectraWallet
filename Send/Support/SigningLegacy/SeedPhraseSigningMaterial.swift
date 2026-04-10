import Foundation

enum SeedPhraseSigningMaterial {
    struct SolanaKeyMaterial {
        let address: String
        let privateKeyData: Data
        let derivationPath: String
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String
    ) throws -> WalletCoreDerivationMaterial {
        try material(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: Optional(derivationPath),
            passphrase: nil
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String?,
        passphrase: String?
    ) throws -> WalletCoreDerivationMaterial {
        let normalizedSeedPhrase = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)
        let resolvedPath = derivationPath ?? defaultPath(for: coin)
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: coin.derivationChain,
            network: .mainnet,
            seedPhrase: normalizedSeedPhrase,
            derivationPath: resolvedPath,
            passphrase: passphrase,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .privateKey]
        )
        let response = try WalletRustDerivationBridge.buildSigningMaterial(request)
        let privateKeyData = try privateKeyData(from: response.privateKeyHex)
        return WalletCoreDerivationMaterial(
            address: response.address,
            privateKeyData: privateKeyData,
            derivationPath: response.derivationPath,
            account: response.account,
            branch: response.branch == 1 ? .change : .external,
            index: response.index
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        account: UInt32
    ) throws -> WalletCoreDerivationMaterial {
        try material(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: WalletDerivationPath.bip44(
                slip44CoinType: coin.slip44CoinType,
                account: account
            ),
            passphrase: nil
        )
    }

    static func material(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        account: UInt32,
        branch: WalletDerivationBranch,
        index: UInt32
    ) throws -> WalletCoreDerivationMaterial {
        try material(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: WalletDerivationPath.bip44(
                slip44CoinType: coin.slip44CoinType,
                account: account,
                branch: branch,
                index: index
            ),
            passphrase: nil
        )
    }

    static func material(
        privateKeyHex: String,
        coin: WalletCoreSupportedCoin
    ) throws -> WalletCoreDerivationMaterial {
        let response = try WalletRustDerivationBridge.buildSigningMaterialFromPrivateKey(
            chain: coin.derivationChain,
            privateKeyHex: privateKeyHex,
            derivationPath: defaultPath(for: coin)
        )
        let privateKeyData = try privateKeyData(from: response.privateKeyHex)
        return WalletCoreDerivationMaterial(
            address: response.address,
            privateKeyData: privateKeyData,
            derivationPath: response.derivationPath,
            account: response.account,
            branch: response.branch == 1 ? .change : .external,
            index: response.index
        )
    }

    static func resolvedSolanaKeyMaterial(
        seedPhrase: String,
        ownerAddress: String?,
        preferredDerivationPath: String? = nil,
        account: UInt32 = 0
    ) throws -> SolanaKeyMaterial {
        let normalizedMnemonic = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)

        let normalizedOwner = ownerAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let accountScopedPaths = [
            "m/44'/501'/\(account)'/0'",
            "m/44'/501'/\(account)'"
        ]
        let derivationPathsToTry: [String] = {
            guard let preferredDerivationPath else { return accountScopedPaths }
            var ordered = [preferredDerivationPath]
            for path in accountScopedPaths where path != preferredDerivationPath {
                ordered.append(path)
            }
            return ordered
        }()

        var firstValid: SolanaKeyMaterial?
        for path in derivationPathsToTry {
            let result = try WalletDerivationEngine.derive(
                seedPhrase: normalizedMnemonic,
                request: WalletDerivationRequest(
                    chain: .solana,
                    network: .mainnet,
                    derivationPath: path,
                    curve: .ed25519,
                    requestedOutputs: [.address, .privateKey]
                )
            )
            guard let address = result.address,
                  let privateKeyHex = result.privateKeyHex else { continue }
            guard AddressValidation.isValidSolanaAddress(address) else { continue }
            let candidate = SolanaKeyMaterial(
                address: address,
                privateKeyData: try privateKeyData(from: privateKeyHex),
                derivationPath: path
            )
            if firstValid == nil {
                firstValid = candidate
            }
            if let normalizedOwner, address.lowercased() == normalizedOwner {
                return candidate
            }
        }

        if let firstValid, normalizedOwner == nil {
            return firstValid
        }
        if let firstValid, let normalizedOwner, firstValid.address.lowercased() == normalizedOwner {
            return firstValid
        }

        throw WalletCoreDerivationError.invalidMnemonic
    }

    private static func defaultPath(for coin: WalletCoreSupportedCoin) -> String {
        WalletDerivationPresetCatalog.defaultPath(for: coin.derivationChain)
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
}
