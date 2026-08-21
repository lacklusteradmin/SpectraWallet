import Foundation

// MARK: ─ (merged from WalletDerivationLayer.swift)

struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
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
        seedPhrase: String, chain: Chain,
        derivationPath: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> WalletRustDerivationResponseModel {
        guard !requestedOutputs.isEmpty else { throw WalletDerivationError.emptyRequestedOutputs }
        return try WalletRustDerivationBridge.derive(
            chain: chain, seedPhrase: seedPhrase, derivationPath: derivationPath,
            passphrase: overrides?.passphrase, hmacKey: overrides?.hmacKey,
            wantAddress: requestedOutputs.contains(.address),
            wantPublicKey: requestedOutputs.contains(.publicKey),
            wantPrivateKey: requestedOutputs.contains(.privateKey)
        )
    }
    static func deriveAddress(
        seedPhrase: String, chain: Chain, derivationPath: String,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> String
    {
        let result = try derive(
            seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath,
            requestedOutputs: .address, overrides: overrides)
        guard let address = result.address else { throw WalletDerivationError.emptyRequestedOutputs }
        return address
    }
    @MainActor static func evmSeedDerivationChain(for chainName: String) -> Chain? {
        CachedCoreHelpers.evmSeedDerivationChainName(chainName: chainName).flatMap(Chain.init(displayName:))
    }
}

// MARK: ─ (merged from Presets.swift)

enum WalletDerivationBranch: Int {
    case external = 0
    case change = 1
}

enum WalletDerivationPath {
    static func dogecoin(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String {
        "m/44'/3'/\(account)'/\(branch.rawValue)/\(index)"
    }
}

