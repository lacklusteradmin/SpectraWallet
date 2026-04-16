import Foundation
enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case requestCompilationFailed(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust derivation core does not support \(chain) yet."
        case .rustCoreReturnedNullResponse: return "The Rust derivation core returned an empty response."
        case .rustCoreFailed(let message): return message
        case .requestCompilationFailed(let message): return message
        }}
}
private struct WalletRustDerivationRequestPayload: Encodable, Sendable {
    let chain: UInt32
    let network: UInt32
    let curve: UInt32
    let requestedOutputs: UInt32
    let derivationAlgorithm: UInt32
    let addressAlgorithm: UInt32
    let publicKeyFormat: UInt32
    let scriptType: UInt32
    let seedPhrase: String
    let derivationPath: String?
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
}
private struct WalletRustPrivateKeyRequestPayload: Encodable, Sendable {
    let chain: UInt32
    let network: UInt32
    let curve: UInt32
    let addressAlgorithm: UInt32
    let publicKeyFormat: UInt32
    let scriptType: UInt32
    let privateKeyHex: String
}
private struct WalletRustMaterialRequestPayload: Encodable, Sendable {
    let chain: UInt32
    let network: UInt32
    let curve: UInt32
    let derivationAlgorithm: UInt32
    let addressAlgorithm: UInt32
    let publicKeyFormat: UInt32
    let scriptType: UInt32
    let seedPhrase: String
    let derivationPath: String
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
}
private struct WalletRustPrivateKeyMaterialRequestPayload: Encodable, Sendable {
    let chain: UInt32
    let network: UInt32
    let curve: UInt32
    let addressAlgorithm: UInt32
    let publicKeyFormat: UInt32
    let scriptType: UInt32
    let privateKeyHex: String
    let derivationPath: String
}
private struct WalletRustDerivationResponsePayload: Decodable, Sendable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
private struct WalletRustMaterialResponsePayload: Decodable, Sendable {
    let address: String
    let privateKeyHex: String
    let derivationPath: String
    let account: UInt32
    let branch: UInt32
    let index: UInt32
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
        let request = WalletRustDerivationRequestPayload(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, requestedOutputs: requestModel.requestedOutputs.rawValue, derivationAlgorithm: requestModel.derivationAlgorithm.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, seedPhrase: requestModel.seedPhrase, derivationPath: requestModel.derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount
        )
        return try decodeResponse(json: try derivationDeriveJson(requestJson: encodeJSONString(request)))
    }
    nonisolated static func deriveFromPrivateKey(chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String) throws -> WalletRustDerivationResponseModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let requestModel = WalletRustPrivateKeyRequestModel(
            chain: ffiChain, network: WalletRustFFINetwork(network: network), curve: WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain)), addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm), publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat), scriptType: try compileScriptType(
                from: requestCompilationPreset, derivationPath: WalletDerivationPresetCatalog.defaultPath(for: chain)
            ), privateKeyHex: privateKeyHex
        )
        let payload = WalletRustPrivateKeyRequestPayload(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, privateKeyHex: requestModel.privateKeyHex
        )
        return try decodeResponse(json: try derivationDeriveFromPrivateKeyJson(requestJson: encodeJSONString(payload)))
    }
    nonisolated static func buildSigningMaterial(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustSigningMaterialModel {
        guard let derivationPath = requestModel.derivationPath else { throw WalletRustDerivationBridgeError.requestCompilationFailed("Signing material requires a derivation path.") }
        let payload = WalletRustMaterialRequestPayload(
            chain: requestModel.chain.rawValue, network: requestModel.network.rawValue, curve: requestModel.curve.rawValue, derivationAlgorithm: requestModel.derivationAlgorithm.rawValue, addressAlgorithm: requestModel.addressAlgorithm.rawValue, publicKeyFormat: requestModel.publicKeyFormat.rawValue, scriptType: requestModel.scriptType.rawValue, seedPhrase: requestModel.seedPhrase, derivationPath: derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount
        )
        return try decodeMaterialResponse(
            json: try derivationBuildMaterialJson(requestJson: encodeJSONString(payload))
        )
    }
    nonisolated static func buildSigningMaterialFromPrivateKey(chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet, privateKeyHex: String, derivationPath: String) throws -> WalletRustSigningMaterialModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else { throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue) }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let payload = WalletRustPrivateKeyMaterialRequestPayload(
            chain: ffiChain.rawValue, network: WalletRustFFINetwork(network: network).rawValue, curve: WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain)).rawValue, addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm).rawValue, publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat).rawValue, scriptType: try compileScriptType(from: requestCompilationPreset, derivationPath: derivationPath).rawValue, privateKeyHex: privateKeyHex, derivationPath: derivationPath
        )
        return try decodeMaterialResponse(
            json: try derivationBuildMaterialFromPrivateKeyJson(requestJson: encodeJSONString(payload))
        )
    }
    nonisolated static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        let pathsJSON = try encodeJSONString(chainPaths)
        let resultJSON = try derivationDeriveAllAddressesJson(seedPhrase: seedPhrase, chainPathsJson: pathsJSON)
        guard let data = resultJSON.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WalletRustDerivationBridgeError.rustCoreReturnedNullResponse }
        return raw.compactMapValues { $0 as? String }
    }
    nonisolated private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { throw WalletRustDerivationBridgeError.requestCompilationFailed("Rust derivation request was not valid UTF-8 JSON.") }
        return json
    }
    nonisolated private static func decodeResponse(json: String) throws -> WalletRustDerivationResponseModel {
        guard let data = json.data(using: .utf8) else { throw WalletRustDerivationBridgeError.rustCoreFailed("Rust derivation response was not valid UTF-8.") }
        let payload: WalletRustDerivationResponsePayload
        do {
            payload = try JSONDecoder().decode(WalletRustDerivationResponsePayload.self, from: data)
        } catch {
            throw WalletRustDerivationBridgeError.rustCoreFailed(error.localizedDescription)
        }
        return WalletRustDerivationResponseModel(
            address: payload.address, publicKeyHex: payload.publicKeyHex, privateKeyHex: payload.privateKeyHex
        )
    }
    nonisolated private static func decodeMaterialResponse(json: String) throws -> WalletRustSigningMaterialModel {
        guard let data = json.data(using: .utf8) else { throw WalletRustDerivationBridgeError.rustCoreFailed("Rust derivation material response was not valid UTF-8.") }
        let payload: WalletRustMaterialResponsePayload
        do {
            payload = try JSONDecoder().decode(WalletRustMaterialResponsePayload.self, from: data)
        } catch {
            throw WalletRustDerivationBridgeError.rustCoreFailed(error.localizedDescription)
        }
        return WalletRustSigningMaterialModel(
            address: payload.address, privateKeyHex: payload.privateKeyHex, derivationPath: payload.derivationPath, account: payload.account, branch: payload.branch, index: payload.index
        )
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
        case .bitcoinPurpose: guard let purpose = derivationPath.flatMap({ DerivationPathParser.segmentValue(at: 0, in: $0) }) else {
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
