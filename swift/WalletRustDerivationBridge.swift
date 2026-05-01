import Foundation
enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case requestCompilationFailed(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust derivation core does not support \(chain) yet."
        case .requestCompilationFailed(let message): return message
        }
    }
}
enum WalletRustDerivationBridge {
    nonisolated static var isAvailable: Bool { true }
    nonisolated static func makeRequestModel(
        chain: SeedDerivationChain, seedPhrase: String, derivationPath: String?, passphrase: String?,
        iterationCount: Int?, hmacKeyString: String?, requestedOutputs: WalletDerivationRequestedOutputs,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> WalletRustDerivationRequestModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let presetCurve = WalletDerivationPresetCatalog.curve(for: chain)
        let trimmedPath = derivationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDerivationPath =
            (trimmedPath?.isEmpty == false)
            ? trimmedPath
            : WalletDerivationPresetCatalog.defaultPath(for: chain)
        let compiledScriptType = try compileScriptType(from: requestCompilationPreset, derivationPath: resolvedDerivationPath)
        // The typed Swift enums used for `WalletRustDerivationRequestModel`
        // cover only the common preset algorithms. Advanced-mode overrides
        // (e.g., TonMnemonic, SubstrateBip39, Monero, SS58) live outside these
        // enums and are carried through to Rust as raw strings via
        // `advancedOverrides` below.
        return WalletRustDerivationRequestModel(
            curve: presetCurve,
            requestedOutputs: requestedOutputs,
            derivationAlgorithm: requestCompilationPreset.derivationAlgorithm,
            addressAlgorithm: requestCompilationPreset.addressAlgorithm,
            publicKeyFormat: requestCompilationPreset.publicKeyFormat, scriptType: compiledScriptType,
            seedPhrase: seedPhrase, derivationPath: resolvedDerivationPath,
            passphrase: overrides?.passphrase ?? passphrase,
            hmacKey: overrides?.hmacKey ?? hmacKeyString,
            mnemonicWordlist: overrides?.mnemonicWordlist ?? "english",
            iterationCount: overrides?.iterationCount ?? UInt32(iterationCount ?? 2048),
            advancedOverrides: overrides
        )
    }
    nonisolated static func derive(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustDerivationResponseModel {
        let overrides = requestModel.advancedOverrides
        let response = try derivationDerive(
            request: UniFfiDerivationRequest(
                chain: nil,
                curve: overrideCurveWire(overrides) ?? requestModel.curve.rustWireValue,
                requestedOutputs: requestModel.requestedOutputs.rustWireValue,
                derivationAlgorithm: overrideDerivationAlgorithmWire(overrides) ?? requestModel.derivationAlgorithm.rustWireValue,
                addressAlgorithm: overrideAddressAlgorithmWire(overrides) ?? requestModel.addressAlgorithm.rustWireValue,
                publicKeyFormat: overridePublicKeyFormatWire(overrides) ?? requestModel.publicKeyFormat.rustWireValue,
                scriptType: overrideScriptTypeWire(overrides) ?? requestModel.scriptType.rustWireValue,
                seedPhrase: requestModel.seedPhrase,
                derivationPath: requestModel.derivationPath, passphrase: requestModel.passphrase, hmacKey: requestModel.hmacKey,
                mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount,
                saltPrefix: overrides?.saltPrefix
            ))
        return WalletRustDerivationResponseModel(
            address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func deriveFromPrivateKey(
        chain: SeedDerivationChain, privateKeyHex: String
    ) throws -> WalletRustDerivationResponseModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let curve = WalletDerivationPresetCatalog.curve(for: chain)
        let scriptType = try compileScriptType(
            from: requestCompilationPreset, derivationPath: WalletDerivationPresetCatalog.defaultPath(for: chain))
        let response = try derivationDeriveFromPrivateKey(
            request: UniFfiPrivateKeyDerivationRequest(
                chain: nil, curve: curve.rustWireValue,
                addressAlgorithm: requestCompilationPreset.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestCompilationPreset.publicKeyFormat.rustWireValue,
                scriptType: scriptType.rustWireValue, privateKeyHex: privateKeyHex
            ))
        return WalletRustDerivationResponseModel(
            address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex)
    }
    nonisolated static func buildSigningMaterial(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustSigningMaterialModel
    {
        guard let derivationPath = requestModel.derivationPath else {
            throw WalletRustDerivationBridgeError.requestCompilationFailed("Signing material requires a derivation path.")
        }
        let response = try derivationBuildMaterial(
            request: UniFfiMaterialRequest(
                chain: nil, curve: requestModel.curve.rustWireValue,
                derivationAlgorithm: requestModel.derivationAlgorithm.rustWireValue,
                addressAlgorithm: requestModel.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestModel.publicKeyFormat.rustWireValue,
                scriptType: requestModel.scriptType.rustWireValue,
                seedPhrase: requestModel.seedPhrase, derivationPath: derivationPath, passphrase: requestModel.passphrase,
                hmacKey: requestModel.hmacKey, mnemonicWordlist: requestModel.mnemonicWordlist, iterationCount: requestModel.iterationCount,
                saltPrefix: nil
            ))
        return WalletRustSigningMaterialModel(
            address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath,
            account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func buildSigningMaterialFromPrivateKey(
        chain: SeedDerivationChain, privateKeyHex: String, derivationPath: String
    ) throws -> WalletRustSigningMaterialModel {
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let curve = WalletDerivationPresetCatalog.curve(for: chain)
        let scriptType = try compileScriptType(from: requestCompilationPreset, derivationPath: derivationPath)
        let response = try derivationBuildMaterialFromPrivateKey(
            request: UniFfiPrivateKeyMaterialRequest(
                chain: nil, curve: curve.rustWireValue,
                addressAlgorithm: requestCompilationPreset.addressAlgorithm.rustWireValue,
                publicKeyFormat: requestCompilationPreset.publicKeyFormat.rustWireValue,
                scriptType: scriptType.rustWireValue,
                privateKeyHex: privateKeyHex, derivationPath: derivationPath
            ))
        return WalletRustSigningMaterialModel(
            address: response.address, privateKeyHex: response.privateKeyHex, derivationPath: response.derivationPath,
            account: response.account, branch: response.branch, index: response.index)
    }
    nonisolated static func deriveAllAddresses(seedPhrase: String, chainPaths: [String: String]) throws -> [String: String] {
        try derivationDeriveAllAddresses(seedPhrase: seedPhrase, chainPaths: chainPaths)
    }
    nonisolated private static func compileScriptType(from preset: WalletDerivationRequestCompilationPreset, derivationPath: String?) throws
        -> AppCoreScriptType
    {
        do {
            return try coreCompileScriptType(preset: preset, derivationPath: derivationPath)
        } catch {
            throw WalletRustDerivationBridgeError.requestCompilationFailed(error.localizedDescription)
        }
    }
}

extension WalletDerivationCurve {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .secp256k1: return 0
        case .ed25519: return 1
        }
    }
}
extension WalletDerivationRequestedOutputs {
    nonisolated var rustWireValue: UInt32 {
        var value: UInt32 = 0
        if contains(.address) { value |= 1 << 0 }
        if contains(.publicKey) { value |= 1 << 1 }
        if contains(.privateKey) { value |= 1 << 2 }
        return value
    }
}
extension AppCoreDerivationAlgorithm {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .bip32Secp256k1: return 1
        case .slip10Ed25519: return 2
        }
    }
}
extension AppCoreAddressAlgorithm {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .bitcoin: return 1
        case .evm: return 2
        case .solana: return 3
        }
    }
}
extension AppCorePublicKeyFormat {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .compressed: return 1
        case .uncompressed: return 2
        case .xOnly: return 3
        case .raw: return 4
        }
    }
}
extension AppCoreScriptType {
    nonisolated var rustWireValue: UInt32 {
        switch self {
        case .p2pkh: return 1
        case .p2shP2wpkh: return 2
        case .p2wpkh: return 3
        case .p2tr: return 4
        case .account: return 5
        }
    }
}
struct WalletRustDerivationRequestModel: Sendable {
    let curve: WalletDerivationCurve
    let requestedOutputs: WalletDerivationRequestedOutputs
    let derivationAlgorithm: AppCoreDerivationAlgorithm
    let addressAlgorithm: AppCoreAddressAlgorithm
    let publicKeyFormat: AppCorePublicKeyFormat
    let scriptType: AppCoreScriptType
    let seedPhrase: String
    let derivationPath: String?
    let passphrase: String?
    let hmacKey: String?
    let mnemonicWordlist: String?
    let iterationCount: UInt32
    /// Power-user overrides for Advanced mode. When present, the string
    /// values override the typed-enum fields above at wire-encoding time.
    /// Algorithms outside the typed-enum set (TonMnemonic, SubstrateBip39,
    /// MoneroBip39, Bip32Ed25519Icarus, DirectSeedEd25519, etc.) are only
    /// reachable through this field.
    let advancedOverrides: CoreWalletDerivationOverrides?
    nonisolated init(
        curve: WalletDerivationCurve,
        requestedOutputs: WalletDerivationRequestedOutputs,
        derivationAlgorithm: AppCoreDerivationAlgorithm,
        addressAlgorithm: AppCoreAddressAlgorithm,
        publicKeyFormat: AppCorePublicKeyFormat, scriptType: AppCoreScriptType,
        seedPhrase: String, derivationPath: String?, passphrase: String?, hmacKey: String?,
        mnemonicWordlist: String?, iterationCount: UInt32,
        advancedOverrides: CoreWalletDerivationOverrides? = nil
    ) {
        self.curve = curve
        self.requestedOutputs = requestedOutputs
        self.derivationAlgorithm = derivationAlgorithm
        self.addressAlgorithm = addressAlgorithm
        self.publicKeyFormat = publicKeyFormat
        self.scriptType = scriptType
        self.seedPhrase = seedPhrase
        self.derivationPath = derivationPath
        self.passphrase = passphrase
        self.hmacKey = hmacKey
        self.mnemonicWordlist = mnemonicWordlist
        self.iterationCount = iterationCount
        self.advancedOverrides = advancedOverrides
    }
}

// ── Wire-value parsers for Advanced-mode overrides ──────────────────────
// Mirror the string names in `core/derivation_presets.toml`. Returning `nil`
// means "no override for this knob; use the typed-enum value". Invalid
// strings surface as Rust-side errors from the derivation pipeline rather
// than being silently dropped.

extension CoreWalletDerivationOverrides {
    /// True when every override field is nil — i.e., the request should use
    /// chain-preset defaults. Read at import time to skip the per-chain
    /// derivation loop when no power-user overrides are set.
    var isEmpty: Bool {
        passphrase == nil && mnemonicWordlist == nil && iterationCount == nil && saltPrefix == nil
            && hmacKey == nil && curve == nil && derivationAlgorithm == nil && addressAlgorithm == nil
            && publicKeyFormat == nil && scriptType == nil
    }
}

nonisolated private func overrideCurveWire(_ o: CoreWalletDerivationOverrides?) -> UInt32? {
    guard let name = o?.curve else { return nil }
    switch name {
    case "secp256k1": return 0
    case "ed25519": return 1
    case "sr25519": return 2
    default: return nil
    }
}

nonisolated private func overrideDerivationAlgorithmWire(_ o: CoreWalletDerivationOverrides?) -> UInt32? {
    guard let name = o?.derivationAlgorithm else { return nil }
    switch name {
    case "bip32_secp256k1": return 1
    case "slip10_ed25519": return 2
    case "direct_seed_ed25519": return 3
    case "ton_mnemonic": return 4
    case "bip32_ed25519_icarus": return 5
    case "substrate_bip39": return 6
    case "monero_bip39": return 7
    default: return nil
    }
}

nonisolated private func overrideAddressAlgorithmWire(_ o: CoreWalletDerivationOverrides?) -> UInt32? {
    guard let name = o?.addressAlgorithm else { return nil }
    switch name {
    case "bitcoin": return 1
    case "evm": return 2
    case "solana": return 3
    case "near_hex": return 4
    case "ton_raw_account_id": return 5
    case "cardano_shelley_enterprise": return 6
    case "ss58": return 7
    case "monero_main": return 8
    case "ton_v4r2": return 9
    case "litecoin": return 10
    case "dogecoin": return 11
    case "bitcoin_cash_legacy": return 12
    case "bitcoin_sv_legacy": return 13
    case "tron_base58_check": return 14
    case "xrp_base58_check": return 15
    case "stellar_strkey": return 16
    case "sui_keccak": return 17
    case "aptos_keccak": return 18
    case "icp_principal": return 19
    default: return nil
    }
}

nonisolated private func overridePublicKeyFormatWire(_ o: CoreWalletDerivationOverrides?) -> UInt32? {
    guard let name = o?.publicKeyFormat else { return nil }
    switch name {
    case "compressed": return 1
    case "uncompressed": return 2
    case "x_only": return 3
    case "raw": return 4
    default: return nil
    }
}

nonisolated private func overrideScriptTypeWire(_ o: CoreWalletDerivationOverrides?) -> UInt32? {
    guard let name = o?.scriptType else { return nil }
    switch name {
    case "p2pkh": return 1
    case "p2sh_p2wpkh": return 2
    case "p2wpkh": return 3
    case "p2tr": return 4
    case "account": return 5
    default: return nil
    }
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
