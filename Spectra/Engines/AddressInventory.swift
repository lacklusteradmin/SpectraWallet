import Foundation

private enum WalletAddressInventoryFactory {
    static func entry(
        address: String,
        derivationPath: String?,
        account: UInt32?,
        branchIndex: UInt32?,
        addressIndex: UInt32?,
        role: WalletAddressInventoryRole
    ) -> WalletAddressInventoryEntry {
        WalletAddressInventoryEntry(
            address: address,
            derivationPath: derivationPath,
            account: account,
            branchIndex: branchIndex,
            addressIndex: addressIndex,
            role: role
        )
    }

    static func singleAddressInventory(
        address: String,
        derivationPath: String?,
        account: UInt32?,
        role: WalletAddressInventoryRole = .primary
    ) -> WalletAddressInventory {
        WalletAddressInventory(
            entries: [
                entry(
                    address: address,
                    derivationPath: derivationPath,
                    account: account,
                    branchIndex: nil,
                    addressIndex: nil,
                    role: role
                )
            ],
            supportsDiscoveryScan: false,
            supportsChangeBranch: false,
            scanLimit: nil
        )
    }

    static func deriveEntry(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        derivationPath: String,
        role: WalletAddressInventoryRole
    ) throws -> WalletAddressInventoryEntry {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: coin,
            derivationPath: derivationPath
        )
        return entry(
            address: material.address,
            derivationPath: material.derivationPath,
            account: material.account,
            branchIndex: material.branch.rawValue == WalletDerivationBranch.change.rawValue ? 1 : 0,
            addressIndex: material.index,
            role: role
        )
    }

    static func scannedBranchInventory(
        seedPhrase: String,
        coin: WalletCoreSupportedCoin,
        account: UInt32,
        scanLimit: UInt32,
        externalPath: (UInt32) -> String,
        changePath: (UInt32) -> String
    ) throws -> WalletAddressInventory {
        var entries: [WalletAddressInventoryEntry] = []
        for index in 0 ..< scanLimit {
            entries.append(
                try deriveEntry(
                    seedPhrase: seedPhrase,
                    coin: coin,
                    derivationPath: externalPath(index),
                    role: index == 0 ? .primary : .external
                )
            )
            entries.append(
                try deriveEntry(
                    seedPhrase: seedPhrase,
                    coin: coin,
                    derivationPath: changePath(index),
                    role: .change
                )
            )
        }
        return WalletAddressInventory(
            entries: entries,
            supportsDiscoveryScan: true,
            supportsChangeBranch: true,
            scanLimit: scanLimit
        )
    }
}

extension DogecoinWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        account: UInt32 = 0,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        try WalletAddressInventoryFactory.scannedBranchInventory(
            seedPhrase: seedPhrase,
            coin: .dogecoin,
            account: account,
            scanLimit: scanLimit,
            externalPath: { WalletDerivationPath.dogecoin(account: account, branch: .external, index: $0) },
            changePath: { WalletDerivationPath.dogecoin(account: account, branch: .change, index: $0) }
        )
    }
}

extension LitecoinWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        account: UInt32 = 0,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        try WalletAddressInventoryFactory.scannedBranchInventory(
            seedPhrase: seedPhrase,
            coin: .litecoin,
            account: account,
            scanLimit: scanLimit,
            externalPath: { WalletDerivationPath.litecoin(account: account, branch: .external, index: $0) },
            changePath: { WalletDerivationPath.litecoin(account: account, branch: .change, index: $0) }
        )
    }
}

extension BitcoinCashWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        account: UInt32 = 0,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        try WalletAddressInventoryFactory.scannedBranchInventory(
            seedPhrase: seedPhrase,
            coin: .bitcoinCash,
            account: account,
            scanLimit: scanLimit,
            externalPath: { WalletDerivationPath.bitcoinCash(account: account, branch: .external, index: $0) },
            changePath: { WalletDerivationPath.bitcoinCash(account: account, branch: .change, index: $0) }
        )
    }
}

extension BitcoinSVWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        account: UInt32 = 0,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        try WalletAddressInventoryFactory.scannedBranchInventory(
            seedPhrase: seedPhrase,
            coin: .bitcoinSV,
            account: account,
            scanLimit: scanLimit,
            externalPath: { WalletDerivationPath.bitcoinSV(account: account, branch: .external, index: $0) },
            changePath: { WalletDerivationPath.bitcoinSV(account: account, branch: .change, index: $0) }
        )
    }
}

extension CardanoWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        account: UInt32 = 0,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        try WalletAddressInventoryFactory.scannedBranchInventory(
            seedPhrase: seedPhrase,
            coin: .cardano,
            account: account,
            scanLimit: scanLimit,
            externalPath: { "m/1852'/1815'/\(account)'/0/\($0)" },
            changePath: { "m/1852'/1815'/\(account)'/1/\($0)" }
        )
    }
}

extension EthereumWalletEngine {
    static func addressInventory(
        for seedPhrase: String,
        chain: EVMChainContext = .ethereum,
        account: UInt32 = 0,
        derivationPath: String? = nil
    ) throws -> WalletAddressInventory {
        let resolvedPath = derivationPath ?? chain.derivationPath(account: account)
        let address = try derivedAddress(
            for: seedPhrase,
            account: account,
            chain: chain,
            derivationPath: resolvedPath
        )
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: address,
            derivationPath: resolvedPath,
            account: account
        )
    }
}

extension AptosWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/637'/\(account)'/0'/0'"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, account: account),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension TronWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .tron,
            account: account
        )
        guard AddressValidation.isValidTronAddress(material.address) else {
            throw TronWalletEngineError.invalidSeedPhrase
        }
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: material.address,
            derivationPath: material.derivationPath,
            account: material.account
        )
    }
}

extension SolanaWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let standardPath = "m/44'/501'/\(account)'/0'"
        let primaryAddress = try derivedAddress(for: seedPhrase, preference: .standard, account: account)
        return WalletAddressInventory(
            entries: [
                WalletAddressInventoryFactory.entry(
                    address: primaryAddress,
                    derivationPath: standardPath,
                    account: account,
                    branchIndex: nil,
                    addressIndex: nil,
                    role: .primary
                )
            ],
            supportsDiscoveryScan: false,
            supportsChangeBranch: false,
            scanLimit: 1
        )
    }
}

extension StellarWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/148'/\(account)'"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, derivationPath: derivationPath),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension XRPWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = WalletDerivationPath.bip44(slip44CoinType: 144, account: account)
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, account: account),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension SuiWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = WalletDerivationPath.bip44(slip44CoinType: 784, account: account)
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, account: account),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension TONWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/607'/\(account)'/0/0"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, account: account),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension ICPWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/223'/\(account)'/0/0"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, derivationPath: derivationPath),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension NearWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/397'/\(account)'"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, account: account),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension PolkadotWalletEngine {
    static func addressInventory(for seedPhrase: String, account: UInt32 = 0) throws -> WalletAddressInventory {
        let derivationPath = "m/44'/354'/\(account)'"
        return WalletAddressInventoryFactory.singleAddressInventory(
            address: try derivedAddress(for: seedPhrase, derivationPath: derivationPath),
            derivationPath: derivationPath,
            account: account
        )
    }
}

extension MoneroWalletEngine {
    static func addressInventory(forPrimaryAddress primaryAddress: String) -> WalletAddressInventory {
        WalletAddressInventoryFactory.singleAddressInventory(
            address: primaryAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            derivationPath: nil,
            account: nil
        )
    }
}
