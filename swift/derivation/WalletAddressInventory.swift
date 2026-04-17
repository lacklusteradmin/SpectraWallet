import Foundation
private enum WalletAddressInventoryFactory {
    static func entry(address: String, derivationPath: String?, account: UInt32?, branchIndex: UInt32?, addressIndex: UInt32?, role: WalletAddressInventoryRole) -> WalletAddressInventoryEntry {
        WalletAddressInventoryEntry(
            address: address, derivationPath: derivationPath, account: account, branchIndex: branchIndex, addressIndex: addressIndex, role: role
        )
    }
    static func singleAddressInventory(address: String, derivationPath: String?, account: UInt32?, role: WalletAddressInventoryRole = .primary) -> WalletAddressInventory {
        WalletAddressInventory(
            entries: [
                entry(
                    address: address, derivationPath: derivationPath, account: account, branchIndex: nil, addressIndex: nil, role: role
                )
            ], supportsDiscoveryScan: false, supportsChangeBranch: false, scanLimit: nil
        )
    }
    static func deriveEntry(seedPhrase: String, chain: SeedDerivationChain, derivationPath: String, role: WalletAddressInventoryRole) throws -> WalletAddressInventoryEntry {
        let values = try WalletDerivationLayer.derive(
            seedPhrase: seedPhrase, chain: chain, network: .mainnet, derivationPath: derivationPath, requestedOutputs: .address
        )
        let segments = DerivationPathParser.parse(derivationPath)
        let account = segments.flatMap { $0.count >= 3 ? $0[2].value : nil }
        let branchIndex = segments.flatMap { $0.count >= 2 ? $0[$0.count - 2].value : nil }
        let index = segments?.last?.value
        return entry(
            address: values.address ?? "", derivationPath: derivationPath, account: account, branchIndex: branchIndex, addressIndex: index, role: role
        )
    }
    static func scannedBranchInventory(
        seedPhrase: String, chain: SeedDerivationChain, account: UInt32, scanLimit: UInt32, externalPath: (UInt32) -> String, changePath: (UInt32) -> String
    ) throws -> WalletAddressInventory {
        var entries: [WalletAddressInventoryEntry] = []
        for index in 0 ..< scanLimit {
            entries.append(
                try deriveEntry(
                    seedPhrase: seedPhrase, chain: chain, derivationPath: externalPath(index), role: index == 0 ? .primary : .external
                )
            )
            entries.append(
                try deriveEntry(
                    seedPhrase: seedPhrase, chain: chain, derivationPath: changePath(index), role: .change
                )
            )
        }
        return WalletAddressInventory(
            entries: entries, supportsDiscoveryScan: true, supportsChangeBranch: true, scanLimit: scanLimit
        )
    }
}
