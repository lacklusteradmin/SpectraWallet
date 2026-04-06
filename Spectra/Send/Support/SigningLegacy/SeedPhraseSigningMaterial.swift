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
        let response = try WalletDerivationEngine.derive(
            seedPhrase: normalizedSeedPhrase,
            request: WalletDerivationRequest(
                chain: coin.derivationChain,
                network: .mainnet,
                derivationPath: resolvedPath,
                curve: WalletDerivationEngine.curve(for: coin.derivationChain),
                passphrase: passphrase,
                requestedOutputs: [.address, .privateKey]
            )
        )
        guard let address = response.address,
              let privateKeyHex = response.privateKeyHex else {
            throw WalletCoreDerivationError.invalidMnemonic
        }
        let privateKeyData = try privateKeyData(from: privateKeyHex)
        let segments = DerivationPathParser.parse(resolvedPath) ?? []
        let branchValue = segments.count >= 2 ? segments[segments.count - 2].value : 0
        let indexValue = segments.last?.value ?? 0
        return WalletCoreDerivationMaterial(
            address: address,
            privateKeyData: privateKeyData,
            derivationPath: resolvedPath,
            account: segments.count >= 3 ? segments[2].value : 0,
            branch: branchValue == 1 ? .change : .external,
            index: indexValue
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
        let normalizedHex = PrivateKeyHex.normalized(from: privateKeyHex)
        let privateKeyData = try privateKeyData(from: normalizedHex)
        let address = try SeedPhraseAddressDerivation.address(
            forPrivateKey: normalizedHex,
            coin: coin,
            validator: { _ in true }
        )
        return WalletCoreDerivationMaterial(
            address: address,
            privateKeyData: privateKeyData,
            derivationPath: defaultPath(for: coin),
            account: 0,
            branch: .external,
            index: 0
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
