import Foundation
nonisolated struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
}
enum WalletDerivationCurve: String, Codable {
    case secp256k1
    case ed25519
}
enum WalletDerivationError: LocalizedError {
    case emptyRequestedOutputs
    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs: return "At least one derivation output must be requested."
        }
    }
}
enum WalletDerivationLayer {
    static func derive(
        seedPhrase: String, chain: SeedDerivationChain,
        derivationPath: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> WalletRustDerivationResponseModel {
        guard !requestedOutputs.isEmpty else { throw WalletDerivationError.emptyRequestedOutputs }
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, seedPhrase: seedPhrase, derivationPath: derivationPath,
            passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: requestedOutputs,
            overrides: overrides
        )
        return try WalletRustDerivationBridge.derive(request)
    }
    static func deriveAddress(
        seedPhrase: String, chain: SeedDerivationChain, derivationPath: String,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> String
    {
        let result = try derive(
            seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath,
            requestedOutputs: .address, overrides: overrides)
        guard let address = result.address else { throw WalletDerivationError.emptyRequestedOutputs }
        return address
    }
    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        CachedCoreHelpers.evmSeedDerivationChainName(chainName: chainName).flatMap(SeedDerivationChain.init(rawValue:))
    }
}
