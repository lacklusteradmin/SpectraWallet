import Foundation
enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case requestCompilationFailed(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust derivation core does not support \(chain) yet."
        case .requestCompilationFailed(let message): return message
        }}
}
enum WalletRustDerivationBridge {
    nonisolated static var isAvailable: Bool { true }
    nonisolated static func makeRequestModel(chain: SeedDerivationChain, network: WalletDerivationNetwork, seedPhrase: String, derivationPath: String?, passphrase: String?, iterationCount: Int?, hmacKeyString: String?, requestedOutputs: WalletDerivationRequestedOutputs) throws -> WalletRustDerivationRequestModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let effectiveCurve = WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain))
        let trimmedPath = derivationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDerivationPath = (trimmedPath?.isEmpty == false)
            ? trimmedPath
            : WalletDerivationPresetCatalog.defaultPath(for: chain, network: network)
        let compiledScriptType = try compileScriptType(from: requestCompilationPreset, derivationPath: resolvedDerivationPath)
        return WalletRustDerivationRequestModel(
            chain: ffiChain, network: WalletRustFFINetwork(network: network), curve: effectiveCurve, requestedOutputs: WalletRustFFIRequestedOutputs(outputs: requestedOutputs), derivationAlgorithm: ffiDerivationAlgorithm(from: requestCompilationPreset.derivationAlgorithm), addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm), publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat), scriptType: compiledScriptType, seedPhrase: seedPhrase, derivationPath: resolvedDerivationPath, passphrase: passphrase, hmacKey: hmacKeyString, mnemonicWordlist: "english", iterationCount: UInt32(iterationCount ?? 2048)
        )
    }
    nonisolated static func derive(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustDerivationResponseModel {
        let response = try derivationDerive(request: UniFFIDerivationRequest(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, requestedOutputs: requestModel.requestedOutputs.rawValue, derivationAlgorithm: requestModel.derivationAlgorithm.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, seedPhrase: requestModel.seedPhrase, derivationPath: requestModel.derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount, saltPrefix: nil
        ))
        return WalletRustDerivationResponseModel(address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func deriveFromPrivateKey(chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String) throws -> WalletRustDerivationResponseModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let requestModel = WalletRustPrivateKeyRequestModel(
            chain: ffiChain, network: WalletRustFFINetwork(network: network), curve: WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain)), addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm), publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat), scriptType: try compileScriptType(
                from: requestCompilationPreset, derivationPath: WalletDerivationPresetCatalog.defaultPath(for: chain)
            ), privateKeyHex: privateKeyHex
        )
        let response = try derivationDeriveFromPrivateKey(request: UniFFIPrivateKeyDerivationRequest(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, privateKeyHex: requestModel.privateKeyHex
        ))
        return WalletRustDerivationResponseModel(address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func buildSigningMaterial(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustSigningMaterialModel {
        guard let derivationPath = requestModel.derivationPath else { throw WalletRustDerivationBridgeError.requestCompilationFailed("Signing material requires a derivation path.") }
        let response = try derivationBuildMaterial(request: UniFFIMaterialRequest(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, derivationAlgorithm: requestModel.derivationAlgorithm.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, seedPhrase: requestModel.seedPhrase, derivationPath: derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount, saltPrefix: nil
        ))
        return WalletRustSigningMaterialModel(address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath, account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func buildSigningMaterialFromPrivateKey(chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String, derivationPath: String) throws -> WalletRustSigningMaterialModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let response = try derivationBuildMaterialFromPrivateKey(request: UniFFIPrivateKeyMaterialRequest(
            chain: ffiChain.rawValue, network: WalletRustFFINetwork(network: network).rawValue, curve: WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain)).rawValue, addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm).rawValue, publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat).rawValue, scriptType: try compileScriptType(from: requestCompilationPreset, derivationPath: derivationPath).rawValue, privateKeyHex: privateKeyHex, derivationPath: derivationPath
        ))
        return WalletRustSigningMaterialModel(address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath, account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        try derivationDeriveAllAddresses(seedPhrase: seedPhrase, chainPaths: chainPaths)
    }
    nonisolated private static func ffiDerivationAlgorithm(from preset: WalletDerivationRequestDerivationAlgorithmPreset) -> WalletRustFFIDerivationAlgorithm {
        switch preset {
        case .bip32Secp256k1: return .bip32Secp256k1
        case .slip10Ed25519: return .slip10Ed25519
        }}
    nonisolated private static func ffiAddressAlgorithm(from preset: WalletDerivationRequestAddressAlgorithmPreset) -> WalletRustFFIAddressAlgorithm {
        switch preset {
        case .bitcoin: return .bitcoin
        case .evm: return .evm
        case .solana: return .solana
        }}
    nonisolated private static func ffiPublicKeyFormat(from preset: WalletDerivationRequestPublicKeyFormatPreset) -> WalletRustFFIPublicKeyFormat {
        switch preset {
        case .compressed: return .compressed
        case .uncompressed: return .uncompressed
        case .xOnly: return .xOnly
        case .raw: return .raw
        }}
    nonisolated private static func compileScriptType(from preset: WalletDerivationRequestCompilationPreset, derivationPath: String?) throws -> WalletRustFFIScriptType {
        switch preset.scriptPolicy {
        case .bitcoinPurpose: guard let purpose = derivationPath.flatMap({ coreDerivationPathSegmentValue(path: $0, index: 0) }) else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed("Unable to compile Bitcoin script type from derivation path.")
            }
            guard let mappedScript = preset.bitcoinPurposeScriptMap?[String(purpose)] else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed(
                    "Unsupported Bitcoin derivation purpose \(purpose)."
                )
            }
            return ffiScriptType(from: mappedScript)
        case .fixed: guard let fixedScriptType = preset.fixedScriptType else { throw WalletRustDerivationBridgeError.requestCompilationFailed("Fixed script policy requires fixedScriptType.") }
            return ffiScriptType(from: fixedScriptType)
        }}
    nonisolated private static func ffiScriptType(from preset: WalletDerivationRequestScriptTypePreset) -> WalletRustFFIScriptType {
        switch preset {
        case .p2pkh: return .p2pkh
        case .p2shP2wpkh: return .p2shP2wpkh
        case .p2wpkh: return .p2wpkh
        case .p2tr: return .p2tr
        case .account: return .account
        }}
}
