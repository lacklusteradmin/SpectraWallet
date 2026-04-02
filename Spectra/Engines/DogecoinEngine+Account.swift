import Foundation
import WalletCore

extension DogecoinWalletEngine {
    static func resolveChangeAddress(
        seedPhrase: String,
        keyMaterial: SigningKeyMaterial,
        changeIndex: Int?,
        derivationAccount: UInt32
    ) throws -> (address: String, derivationPath: String) {
        guard let changeIndex else {
            return (keyMaterial.changeAddress, keyMaterial.changeDerivationPath)
        }

        let address = try derivedAddress(
            for: seedPhrase,
            isChange: true,
            index: changeIndex,
            account: Int(derivationAccount)
        )
        return (
            address,
            WalletDerivationPath.dogecoin(
                account: derivationAccount,
                branch: .change,
                index: UInt32(changeIndex)
            )
        )
    }

    static func deriveSigningKeyMaterial(
        seedPhrase: String,
        expectedAddress: String?,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        try deriveSigningKeyMaterialWithWalletCore(
            seedPhrase: seedPhrase,
            expectedAddress: expectedAddress,
            derivationAccount: derivationAccount
        )
    }

    static func deriveSigningKeyMaterialWithWalletCore(
        seedPhrase: String,
        expectedAddress: String?,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let normalizedExpectedAddress: String?
        if let expectedAddress {
            normalizedExpectedAddress = normalizeAddressForCurrentNetwork(
                expectedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            normalizedExpectedAddress = nil
        }
        let mnemonicWords = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        for index in 0 ..< derivationScanLimit {
            let signingMaterial = try WalletCoreDerivation.deriveMaterial(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .external,
                index: UInt32(index)
            )
            guard let signingAddress = normalizeAddressForCurrentNetwork(signingMaterial.address) else {
                continue
            }
            if let normalizedExpectedAddress, normalizedExpectedAddress != signingAddress {
                continue
            }

            let changeMaterial = try WalletCoreDerivation.deriveMaterial(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .change,
                index: UInt32(index)
            )
            guard let changeAddress = normalizeAddressForCurrentNetwork(changeMaterial.address) else {
                continue
            }
            return SigningKeyMaterial(
                address: signingAddress,
                privateKeyData: signingMaterial.privateKeyData,
                signingDerivationPath: signingMaterial.derivationPath,
                changeAddress: changeAddress,
                changeDerivationPath: changeMaterial.derivationPath
            )
        }
        throw DogecoinWalletEngineError.walletAddressNotDerivedFromSeed
    }

    static func walletCoreDerivedAddress(
        seedPhrase: String,
        isChange: Bool,
        index: Int,
        account: Int
    ) throws -> String {
        guard index >= 0 else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let mnemonicWords = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeedPhrase,
            coin: .dogecoin,
            account: UInt32(max(0, account)),
            branch: isChange ? .change : .external,
            index: UInt32(index)
        )
        guard !material.address.isEmpty else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        guard let normalizedAddress = normalizeAddressForCurrentNetwork(material.address) else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        return normalizedAddress
    }
}
