import Foundation

enum WalletRustDerivationBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case requestCompilationFailed(String)

    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain):
            return "The Rust derivation core does not support \(chain) yet."
        case .rustCoreReturnedNullResponse:
            return "The Rust derivation core returned an empty response."
        case .rustCoreFailed(let message):
            return message
        case .requestCompilationFailed(let message):
            return message
        }
    }
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

struct WalletRustFFIRequestedOutputs: OptionSet {
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

struct WalletRustDerivationRequestModel {
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

struct WalletRustPrivateKeyRequestModel {
    let chain: WalletRustFFIChain
    let network: WalletRustFFINetwork
    let curve: WalletRustFFICurve
    let addressAlgorithm: WalletRustFFIAddressAlgorithm
    let publicKeyFormat: WalletRustFFIPublicKeyFormat
    let scriptType: WalletRustFFIScriptType
    let privateKeyHex: String
}

struct WalletRustFFIBuffer {
    var ptr: UnsafeMutablePointer<UInt8>?
    var len: Int

    static let empty = WalletRustFFIBuffer(ptr: nil, len: 0)
}

struct WalletRustFFIRequest {
    var chain: UInt32
    var network: UInt32
    var curve: UInt32
    var requestedOutputs: UInt32
    var derivationAlgorithm: UInt32
    var addressAlgorithm: UInt32
    var publicKeyFormat: UInt32
    var scriptType: UInt32
    var seedPhraseUTF8: WalletRustFFIBuffer
    var derivationPathUTF8: WalletRustFFIBuffer
    var passphraseUTF8: WalletRustFFIBuffer
    var hmacKeyUTF8: WalletRustFFIBuffer
    var mnemonicWordlistUTF8: WalletRustFFIBuffer
    var iterationCount: UInt32
}

struct WalletRustFFIPrivateKeyRequest {
    var chain: UInt32
    var network: UInt32
    var curve: UInt32
    var addressAlgorithm: UInt32
    var publicKeyFormat: UInt32
    var scriptType: UInt32
    var privateKeyHexUTF8: WalletRustFFIBuffer
}

struct WalletRustFFIResponse {
    var statusCode: Int32
    var addressUTF8: WalletRustFFIBuffer
    var publicKeyHexUTF8: WalletRustFFIBuffer
    var privateKeyHexUTF8: WalletRustFFIBuffer
    var errorMessageUTF8: WalletRustFFIBuffer
}

struct WalletRustDerivationResponseModel {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

extension WalletRustFFIChain {
    init?(chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin:
            self = .bitcoin
        case .ethereum:
            self = .ethereum
        case .solana:
            self = .solana
        case .bitcoinCash:
            self = .bitcoinCash
        case .bitcoinSV:
            self = .bitcoinSV
        case .litecoin:
            self = .litecoin
        case .dogecoin:
            self = .dogecoin
        case .ethereumClassic:
            self = .ethereumClassic
        case .arbitrum:
            self = .arbitrum
        case .optimism:
            self = .optimism
        case .avalanche:
            self = .avalanche
        case .hyperliquid:
            self = .hyperliquid
        case .tron:
            self = .tron
        case .stellar:
            self = .stellar
        case .xrp:
            self = .xrp
        case .cardano:
            self = .cardano
        case .sui:
            self = .sui
        case .aptos:
            self = .aptos
        case .ton:
            self = .ton
        case .internetComputer:
            self = .internetComputer
        case .near:
            self = .near
        case .polkadot:
            self = .polkadot
        }
    }
}

extension WalletRustFFINetwork {
    init(network: WalletDerivationNetwork) {
        switch network {
        case .mainnet:
            self = .mainnet
        case .testnet:
            self = .testnet
        case .testnet4:
            self = .testnet4
        case .signet:
            self = .signet
        }
    }
}

extension WalletRustFFICurve {
    init(curve: WalletDerivationCurve) {
        switch curve {
        case .secp256k1:
            self = .secp256k1
        case .ed25519:
            self = .ed25519
        }
    }
}

extension WalletRustFFIRequestedOutputs {
    init(outputs: WalletDerivationRequestedOutputs) {
        var value: WalletRustFFIRequestedOutputs = []
        if outputs.contains(.address) {
            value.insert(.address)
        }
        if outputs.contains(.publicKey) {
            value.insert(.publicKey)
        }
        if outputs.contains(.privateKey) {
            value.insert(.privateKey)
        }
        self = value
    }
}

private extension Array where Element == UInt8 {
    mutating func zeroize() {
        guard !isEmpty else { return }
        withUnsafeMutableBytes { mutableBytes in
            mutableBytes.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}

extension WalletRustDerivationRequestModel {
    func withFFIRequest<T>(_ body: (inout WalletRustFFIRequest) throws -> T) rethrows -> T {
        var seedPhraseStorage = Array(seedPhrase.utf8)
        var derivationPathStorage = Array((derivationPath ?? "").utf8)
        var passphraseStorage = Array((passphrase ?? "").utf8)
        var hmacKeyStorage = Array((hmacKey ?? "").utf8)
        var mnemonicWordlistStorage = Array((mnemonicWordlist ?? "").utf8)

        defer {
            seedPhraseStorage.zeroize()
            derivationPathStorage.zeroize()
            passphraseStorage.zeroize()
            hmacKeyStorage.zeroize()
            mnemonicWordlistStorage.zeroize()
        }

        var request = WalletRustFFIRequest(
            chain: chain.rawValue,
            network: network.rawValue,
            curve: curve.rawValue,
            requestedOutputs: requestedOutputs.rawValue,
            derivationAlgorithm: derivationAlgorithm.rawValue,
            addressAlgorithm: addressAlgorithm.rawValue,
            publicKeyFormat: publicKeyFormat.rawValue,
            scriptType: scriptType.rawValue,
            seedPhraseUTF8: seedPhraseStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            },
            derivationPathUTF8: derivationPathStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            },
            passphraseUTF8: passphraseStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            },
            hmacKeyUTF8: hmacKeyStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            },
            mnemonicWordlistUTF8: mnemonicWordlistStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            },
            iterationCount: iterationCount
        )

        return try body(&request)
    }
}

extension WalletRustPrivateKeyRequestModel {
    func withFFIRequest<T>(_ body: (inout WalletRustFFIPrivateKeyRequest) throws -> T) rethrows -> T {
        var privateKeyStorage = Array(privateKeyHex.utf8)
        defer {
            privateKeyStorage.zeroize()
        }

        var request = WalletRustFFIPrivateKeyRequest(
            chain: chain.rawValue,
            network: network.rawValue,
            curve: curve.rawValue,
            addressAlgorithm: addressAlgorithm.rawValue,
            publicKeyFormat: publicKeyFormat.rawValue,
            scriptType: scriptType.rawValue,
            privateKeyHexUTF8: privateKeyStorage.withUnsafeMutableBytes { bytes in
                WalletRustFFIBuffer(
                    ptr: bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    len: bytes.count
                )
            }
        )

        return try body(&request)
    }
}

@_silgen_name("spectra_derivation_derive")
private func spectra_derivation_derive(
    _ request: UnsafePointer<WalletRustFFIRequest>?
) -> UnsafeMutablePointer<WalletRustFFIResponse>?

@_silgen_name("spectra_derivation_derive_from_private_key")
private func spectra_derivation_derive_from_private_key(
    _ request: UnsafePointer<WalletRustFFIPrivateKeyRequest>?
) -> UnsafeMutablePointer<WalletRustFFIResponse>?

@_silgen_name("spectra_derivation_response_free")
private func spectra_derivation_response_free(
    _ response: UnsafeMutablePointer<WalletRustFFIResponse>?
)

enum WalletRustDerivationBridge {
    static var isAvailable: Bool {
        true
    }

    static func makeRequestModel(
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork,
        seedPhrase: String,
        derivationPath: String?,
        passphrase: String?,
        iterationCount: Int?,
        hmacKeyString: String?,
        requestedOutputs: WalletDerivationRequestedOutputs
    ) throws -> WalletRustDerivationRequestModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)
        let effectiveCurve = WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain))
        let trimmedPath = derivationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDerivationPath = (trimmedPath?.isEmpty == false)
            ? trimmedPath
            : WalletDerivationPresetCatalog.defaultPath(for: chain, network: network)
        let compiledScriptType = try compileScriptType(
            from: requestCompilationPreset,
            derivationPath: resolvedDerivationPath
        )

        return WalletRustDerivationRequestModel(
            chain: ffiChain,
            network: WalletRustFFINetwork(network: network),
            curve: effectiveCurve,
            requestedOutputs: WalletRustFFIRequestedOutputs(outputs: requestedOutputs),
            derivationAlgorithm: ffiDerivationAlgorithm(from: requestCompilationPreset.derivationAlgorithm),
            addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm),
            publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat),
            scriptType: compiledScriptType,
            seedPhrase: seedPhrase,
            derivationPath: resolvedDerivationPath,
            passphrase: passphrase,
            hmacKey: hmacKeyString,
            mnemonicWordlist: "english",
            iterationCount: UInt32(iterationCount ?? 2048)
        )
    }

    static func derive(_ requestModel: WalletRustDerivationRequestModel) throws -> WalletRustDerivationResponseModel {
        return try requestModel.withFFIRequest { request in
            try withRustResponse(
                request: &request,
                invoke: spectra_derivation_derive,
                fallbackErrorMessage: "Rust derivation failed."
            )
        }
    }

    static func deriveFromPrivateKey(
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork = .mainnet,
        privateKeyHex: String
    ) throws -> WalletRustDerivationResponseModel {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustDerivationBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }
        let requestCompilationPreset = WalletDerivationPresetCatalog.requestCompilationPreset(for: chain)

        let requestModel = WalletRustPrivateKeyRequestModel(
            chain: ffiChain,
            network: WalletRustFFINetwork(network: network),
            curve: WalletRustFFICurve(curve: WalletDerivationPresetCatalog.curve(for: chain)),
            addressAlgorithm: ffiAddressAlgorithm(from: requestCompilationPreset.addressAlgorithm),
            publicKeyFormat: ffiPublicKeyFormat(from: requestCompilationPreset.publicKeyFormat),
            scriptType: try compileScriptType(
                from: requestCompilationPreset,
                derivationPath: WalletDerivationPresetCatalog.defaultPath(for: chain)
            ),
            privateKeyHex: privateKeyHex
        )

        return try requestModel.withFFIRequest { request in
            try withRustResponse(
                request: &request,
                invoke: spectra_derivation_derive_from_private_key,
                fallbackErrorMessage: "Rust private-key derivation failed."
            )
        }
    }

    private static func withRustResponse<Request>(
        request: inout Request,
        invoke: (UnsafePointer<Request>?) -> UnsafeMutablePointer<WalletRustFFIResponse>?,
        fallbackErrorMessage: String
    ) throws -> WalletRustDerivationResponseModel {
        guard let responsePointer = withUnsafePointer(to: request, { invoke($0) }) else {
            throw WalletRustDerivationBridgeError.rustCoreReturnedNullResponse
        }
        defer {
            spectra_derivation_response_free(responsePointer)
        }

        let response = responsePointer.pointee
        if response.statusCode != 0 {
            let errorMessage = string(from: response.errorMessageUTF8) ?? fallbackErrorMessage
            throw WalletRustDerivationBridgeError.rustCoreFailed(errorMessage)
        }

        return WalletRustDerivationResponseModel(
            address: string(from: response.addressUTF8),
            publicKeyHex: string(from: response.publicKeyHexUTF8),
            privateKeyHex: string(from: response.privateKeyHexUTF8)
        )
    }

    private static func string(from buffer: WalletRustFFIBuffer) -> String? {
        guard let ptr = buffer.ptr, buffer.len > 0 else { return nil }
        let bytes = UnsafeBufferPointer(start: UnsafePointer(ptr), count: buffer.len)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ffiDerivationAlgorithm(
        from preset: WalletDerivationRequestDerivationAlgorithmPreset
    ) -> WalletRustFFIDerivationAlgorithm {
        switch preset {
        case .bip32Secp256k1:
            return .bip32Secp256k1
        case .slip10Ed25519:
            return .slip10Ed25519
        }
    }

    private static func ffiAddressAlgorithm(
        from preset: WalletDerivationRequestAddressAlgorithmPreset
    ) -> WalletRustFFIAddressAlgorithm {
        switch preset {
        case .bitcoin:
            return .bitcoin
        case .evm:
            return .evm
        case .solana:
            return .solana
        }
    }

    private static func ffiPublicKeyFormat(
        from preset: WalletDerivationRequestPublicKeyFormatPreset
    ) -> WalletRustFFIPublicKeyFormat {
        switch preset {
        case .compressed:
            return .compressed
        case .uncompressed:
            return .uncompressed
        case .xOnly:
            return .xOnly
        case .raw:
            return .raw
        }
    }

    private static func compileScriptType(
        from preset: WalletDerivationRequestCompilationPreset,
        derivationPath: String?
    ) throws -> WalletRustFFIScriptType {
        switch preset.scriptPolicy {
        case .bitcoinPurpose:
            guard let purpose = derivationPath
                .flatMap({ DerivationPathParser.segmentValue(at: 0, in: $0) }) else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed(
                    "Unable to compile Bitcoin script type from derivation path."
                )
            }
            guard let mappedScript = preset.bitcoinPurposeScriptMap?[String(purpose)] else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed(
                    "Unsupported Bitcoin derivation purpose \(purpose)."
                )
            }
            return ffiScriptType(from: mappedScript)
        case .fixed:
            guard let fixedScriptType = preset.fixedScriptType else {
                throw WalletRustDerivationBridgeError.requestCompilationFailed(
                    "Fixed script policy requires fixedScriptType."
                )
            }
            return ffiScriptType(from: fixedScriptType)
        }
    }

    private static func ffiScriptType(
        from preset: WalletDerivationRequestScriptTypePreset
    ) -> WalletRustFFIScriptType {
        switch preset {
        case .p2pkh:
            return .p2pkh
        case .p2shP2wpkh:
            return .p2shP2wpkh
        case .p2wpkh:
            return .p2wpkh
        case .p2tr:
            return .p2tr
        case .account:
            return .account
        }
    }
}
