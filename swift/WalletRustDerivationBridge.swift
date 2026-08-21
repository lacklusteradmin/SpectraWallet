import Foundation

enum WalletRustDerivationBridge {
    static var isAvailable: Bool { true }

    // MARK: — Seed-phrase derive

    static func derive(
        chain: Chain,
        seedPhrase: String,
        derivationPath: String?,
        passphrase: String?,
        hmacKey: String?,
        scriptType: BitcoinScriptType? = nil,
        wantAddress: Bool,
        wantPublicKey: Bool,
        wantPrivateKey: Bool
    ) throws -> WalletRustDerivationResponseModel {
        let path = derivationPath ?? CachedCoreHelpers.chainDerivationPath(chainName: chain.displayName)
        let result = try dispatch(
            chain: chain, seedPhrase: seedPhrase, path: path,
            passphrase: passphrase?.nonEmpty, hmacKey: hmacKey?.nonEmpty,
            scriptType: scriptType ?? bitcoinScriptType(from: path),
            wa: wantAddress, wp: wantPublicKey, wk: wantPrivateKey
        )
        return WalletRustDerivationResponseModel(
            address: result.address, publicKeyHex: result.publicKeyHex, privateKeyHex: result.privateKeyHex)
    }

    // MARK: — Private-key derive

    /// Was a thirty-arm switch naming which chains derive by which algorithm,
    /// calling six per-chain exports. Core dispatches that by chain now, so the
    /// list of families lives with the registry that defines them.
    static func deriveFromPrivateKey(
        chain: Chain, privateKeyHex: String
    ) throws -> WalletRustDerivationResponseModel {
        let result = try coreDeriveFromPrivateKey(
            chainName: chain.displayName, privateKeyHex: privateKeyHex,
            wantAddress: true, wantPublicKey: false)
        return WalletRustDerivationResponseModel(
            address: result?.address, publicKeyHex: result?.publicKeyHex,
            privateKeyHex: result?.privateKeyHex)
    }

    // MARK: — Batch derive (all selected chains)

    static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for (chainName, path) in chainPaths {
            guard let chain = Chain(displayName: chainName) else { continue }
            if let address = try? derive(
                chain: chain, seedPhrase: seedPhrase, derivationPath: path,
                passphrase: nil, hmacKey: nil,
                wantAddress: true, wantPublicKey: false, wantPrivateKey: false
            ).address {
                result[chainName] = address
            }
        }
        return result
    }

    // MARK: — Script type from path

    private static func bitcoinScriptType(from path: String) -> BitcoinScriptType {
        let purpose = path.split(separator: "/")
            .first(where: { $0 != "m" && $0 != "M" })
            .map { String($0).replacingOccurrences(of: "'", with: "") }
        switch purpose {
        case "44": return .p2pkh
        case "49": return .p2shP2wpkh
        case "86": return .p2tr
        default:   return .p2wpkh
        }
    }

    // MARK: — Per-chain dispatch

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    /// One call, whatever the chain.
    ///
    /// This was a 212-line switch with an arm per chain, each calling a
    /// `derive<Chain>` export that existed only to be called from that arm.
    /// Core has dispatched by chain name since before any of them were written.
    private static func dispatch(
        chain: Chain,
        seedPhrase: String, path: String,
        passphrase: String?, hmacKey: String?,
        scriptType: BitcoinScriptType,
        wa: Bool, wp: Bool, wk: Bool
    ) throws -> DerivationResult {
        try coreDeriveForChain(
            chainName: chain.displayName, seedPhrase: seedPhrase, derivationPath: path,
            passphrase: passphrase, hmacKey: hmacKey, scriptType: scriptType,
            wantAddress: wa, wantPublicKey: wp, wantPrivateKey: wk)
    }
}

// MARK: — Shared result types


struct WalletRustDerivationResponseModel: Sendable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

// MARK: — CoreWalletDerivationOverrides helpers

extension CoreWalletDerivationOverrides {
    var isEmpty: Bool {
        passphrase == nil && mnemonicWordlist == nil && iterationCount == nil && saltPrefix == nil
            && hmacKey == nil && curve == nil && derivationAlgorithm == nil && addressAlgorithm == nil
            && publicKeyFormat == nil && scriptType == nil
    }
}

// MARK: — String helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
