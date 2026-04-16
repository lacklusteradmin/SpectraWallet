import Foundation
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
struct WalletRustFFIRequestedOutputs: OptionSet, Sendable {
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
