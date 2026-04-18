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
    nonisolated private static func ffiDerivationAlgorithm(from raw: String) -> WalletRustFFIDerivationAlgorithm {
        switch raw {
        case "bip32Secp256k1": return .bip32Secp256k1
        case "slip10Ed25519": return .slip10Ed25519
        default: fatalError("Unknown derivation algorithm: \(raw)")
        }}
    nonisolated private static func ffiAddressAlgorithm(from raw: String) -> WalletRustFFIAddressAlgorithm {
        switch raw {
        case "bitcoin": return .bitcoin
        case "evm": return .evm
        case "solana": return .solana
        default: fatalError("Unknown address algorithm: \(raw)")
        }}
    nonisolated private static func ffiPublicKeyFormat(from raw: String) -> WalletRustFFIPublicKeyFormat {
        switch raw {
        case "compressed": return .compressed
        case "uncompressed": return .uncompressed
        case "xOnly": return .xOnly
        case "raw": return .raw
        default: fatalError("Unknown public key format: \(raw)")
        }}
    nonisolated private static func compileScriptType(from preset: WalletDerivationRequestCompilationPreset, derivationPath: String?) throws -> WalletRustFFIScriptType {
        switch preset.scriptPolicy {
        case "bitcoinPurpose":
            guard let purpose = derivationPath.flatMap({ coreDerivationPathSegmentValue(path: $0, index: 0) }) else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed("Unable to compile Bitcoin script type from derivation path.")
            }
            guard let mappedScript = preset.bitcoinPurposeScriptMap?[String(purpose)] else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed(
                    "Unsupported Bitcoin derivation purpose \(purpose)."
                )
            }
            return ffiScriptType(from: mappedScript)
        case "fixed":
            guard let fixedScriptType = preset.fixedScriptType else { throw WalletRustDerivationBridgeError.requestCompilationFailed("Fixed script policy requires fixedScriptType.") }
            return ffiScriptType(from: fixedScriptType)
        default:
            throw WalletRustDerivationBridgeError.requestCompilationFailed("Unknown script policy: \(preset.scriptPolicy)")
        }}
    nonisolated private static func ffiScriptType(from raw: String) -> WalletRustFFIScriptType {
        switch raw {
        case "p2pkh": return .p2pkh
        case "p2shP2wpkh": return .p2shP2wpkh
        case "p2wpkh": return .p2wpkh
        case "p2tr": return .p2tr
        case "account": return .account
        default: fatalError("Unknown script type: \(raw)")
        }}
}
enum WalletRustFFIChain: UInt32 {
    case bitcoin = 0
    case ethereum = 1
    case solana = 2
    case bitcoinCash = 3
    case bitcoinSV = 4
    case litecoin = 5
    case dogecoin = 6
    case ethereumClassic = 7
    case arbitrum = 8
    case optimism = 9
    case avalanche = 10
    case hyperliquid = 11
    case tron = 12
    case stellar = 13
    case xrp = 14
    case cardano = 15
    case sui = 16
    case aptos = 17
    case ton = 18
    case internetComputer = 19
    case near = 20
    case polkadot = 21
}
enum WalletRustFFINetwork: UInt32 {
    case mainnet = 0
    case testnet = 1
    case testnet4 = 2
    case signet = 3
}
enum WalletRustFFICurve: UInt32 {
    case secp256k1 = 0
    case ed25519 = 1
}
nonisolated struct WalletRustFFIRequestedOutputs: OptionSet, Sendable {
    let rawValue: UInt32
    static let address = WalletRustFFIRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletRustFFIRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletRustFFIRequestedOutputs(rawValue: 1 << 2)
}
enum WalletRustFFIDerivationAlgorithm: UInt32 {
    case auto = 0
    case bip32Secp256k1 = 1
    case slip10Ed25519 = 2
}
enum WalletRustFFIAddressAlgorithm: UInt32 {
    case auto = 0
    case bitcoin = 1
    case evm = 2
    case solana = 3
}
enum WalletRustFFIPublicKeyFormat: UInt32 {
    case auto = 0
    case compressed = 1
    case uncompressed = 2
    case xOnly = 3
    case raw = 4
}
enum WalletRustFFIScriptType: UInt32 {
    case auto = 0
    case p2pkh = 1
    case p2shP2wpkh = 2
    case p2wpkh = 3
    case p2tr = 4
    case account = 5
}
struct WalletRustDerivationRequestModel: Sendable {
    let chain: WalletRustFFIChain
    let network: WalletRustFFINetwork
    let curve: WalletRustFFICurve
    let requestedOutputs: WalletRustFFIRequestedOutputs
    let derivationAlgorithm: WalletRustFFIDerivationAlgorithm
    let addressAlgorithm: WalletRustFFIAddressAlgorithm
    let publicKeyFormat: WalletRustFFIPublicKeyFormat
    let scriptType: WalletRustFFIScriptType
    let seedPhrase: String
    let derivationPath: String?
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
}
struct WalletRustPrivateKeyRequestModel: Sendable {
    let chain: WalletRustFFIChain
    let network: WalletRustFFINetwork
    let curve: WalletRustFFICurve
    let addressAlgorithm: WalletRustFFIAddressAlgorithm
    let publicKeyFormat: WalletRustFFIPublicKeyFormat
    let scriptType: WalletRustFFIScriptType
    let privateKeyHex: String
}
struct WalletRustSigningMaterialModel: Sendable {
    let address: String
    let privateKeyHex: String
    let derivationPath: String
    let account: UInt32
    let branch: UInt32
    let index: UInt32
}
struct WalletRustDerivationResponseModel: Sendable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
extension WalletRustFFIChain {
    nonisolated init?(chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin: self = .bitcoin
        case .ethereum: self = .ethereum
        case .solana: self = .solana
        case .bitcoinCash: self = .bitcoinCash
        case .bitcoinSV: self = .bitcoinSV
        case .litecoin: self = .litecoin
        case .dogecoin: self = .dogecoin
        case .ethereumClassic: self = .ethereumClassic
        case .arbitrum: self = .arbitrum
        case .optimism: self = .optimism
        case .avalanche: self = .avalanche
        case .hyperliquid: self = .hyperliquid
        case .tron: self = .tron
        case .stellar: self = .stellar
        case .xrp: self = .xrp
        case .cardano: self = .cardano
        case .sui: self = .sui
        case .aptos: self = .aptos
        case .ton: self = .ton
        case .internetComputer: self = .internetComputer
        case .near: self = .near
        case .polkadot: self = .polkadot
        }}
}
extension WalletRustFFINetwork {
    nonisolated init(network: WalletDerivationNetwork) {
        switch network {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        case .testnet4: self = .testnet4
        case .signet: self = .signet
        }}
}
extension WalletRustFFICurve {
    nonisolated init(curve: WalletDerivationCurve) {
        switch curve {
        case .secp256k1: self = .secp256k1
        case .ed25519: self = .ed25519
        }}
}
extension WalletRustFFIRequestedOutputs {
    nonisolated init(outputs: WalletDerivationRequestedOutputs) {
        var value: WalletRustFFIRequestedOutputs = []
        if outputs.contains(.address) { value.insert(.address) }
        if outputs.contains(.publicKey) { value.insert(.publicKey) }
        if outputs.contains(.privateKey) { value.insert(.privateKey) }
        self = value
    }
}
