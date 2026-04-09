import Foundation

struct WalletDerivationNetworkPreset: Codable, Equatable, Identifiable {
    let network: WalletDerivationNetwork
    let title: String
    let detail: String
    let isDefault: Bool

    var id: String { network.rawValue }
}

struct WalletDerivationPathPreset: Codable, Equatable, Identifiable {
    let title: String
    let detail: String
    let derivationPath: String
    let isDefault: Bool

    var id: String { "\(title)|\(derivationPath)" }

    var uiPreset: SeedDerivationPathPreset {
        SeedDerivationPathPreset(title: title, detail: detail, path: derivationPath)
    }
}

struct WalletDerivationChainPreset: Codable, Equatable {
    let chain: SeedDerivationChain
    let curve: WalletDerivationCurve
    let networks: [WalletDerivationNetworkPreset]
    let derivationPaths: [WalletDerivationPathPreset]

    var defaultNetwork: WalletDerivationNetworkPreset {
        networks.first(where: \.isDefault) ?? networks[0]
    }

    var defaultPath: WalletDerivationPathPreset {
        derivationPaths.first(where: \.isDefault) ?? derivationPaths[0]
    }
}

enum WalletDerivationRequestDerivationAlgorithmPreset: String, Codable, Equatable {
    case bip32Secp256k1
    case slip10Ed25519
}

enum WalletDerivationRequestAddressAlgorithmPreset: String, Codable, Equatable {
    case bitcoin
    case evm
    case solana
}

enum WalletDerivationRequestPublicKeyFormatPreset: String, Codable, Equatable {
    case compressed
    case uncompressed
    case xOnly
    case raw
}

enum WalletDerivationRequestScriptTypePreset: String, Codable, Equatable {
    case p2pkh
    case p2shP2wpkh
    case p2wpkh
    case p2tr
    case account
}

enum WalletDerivationRequestScriptPolicyPreset: String, Codable, Equatable {
    case fixed
    case bitcoinPurpose
}

struct WalletDerivationRequestCompilationPreset: Codable, Equatable {
    let chain: SeedDerivationChain
    let derivationAlgorithm: WalletDerivationRequestDerivationAlgorithmPreset
    let addressAlgorithm: WalletDerivationRequestAddressAlgorithmPreset
    let publicKeyFormat: WalletDerivationRequestPublicKeyFormatPreset
    let scriptPolicy: WalletDerivationRequestScriptPolicyPreset
    let fixedScriptType: WalletDerivationRequestScriptTypePreset?
    let bitcoinPurposeScriptMap: [String: WalletDerivationRequestScriptTypePreset]?
}

extension WalletDerivationRequestedOutputs {
    init(jsonValues: [String]) {
        var values: WalletDerivationRequestedOutputs = []
        for value in jsonValues {
            switch value {
            case "address":
                values.insert(.address)
            case "publicKey":
                values.insert(.publicKey)
            case "privateKey":
                values.insert(.privateKey)
            default:
                break
            }
        }
        self = values
    }
}

enum WalletDerivationPresetCatalog {
    static let all: [WalletDerivationChainPreset] = load()
    static let requestCompilationAll: [WalletDerivationRequestCompilationPreset] = loadRequestCompilation()

    static func chainPreset(for chain: SeedDerivationChain) -> WalletDerivationChainPreset {
        guard let preset = all.first(where: { $0.chain == chain }) else {
            fatalError("Missing derivation preset for \(chain.rawValue)")
        }
        return preset
    }

    static func networkPresets(for chain: SeedDerivationChain) -> [WalletDerivationNetworkPreset] {
        chainPreset(for: chain).networks
    }

    static func pathPresets(for chain: SeedDerivationChain) -> [WalletDerivationPathPreset] {
        chainPreset(for: chain).derivationPaths
    }

    static func curve(for chain: SeedDerivationChain) -> WalletDerivationCurve {
        chainPreset(for: chain).curve
    }

    static func requestCompilationPreset(for chain: SeedDerivationChain) -> WalletDerivationRequestCompilationPreset {
        guard let preset = requestCompilationAll.first(where: { $0.chain == chain }) else {
            fatalError("Missing derivation request compilation preset for \(chain.rawValue)")
        }
        return preset
    }

    static func defaultNetwork(for chain: SeedDerivationChain) -> WalletDerivationNetworkPreset {
        chainPreset(for: chain).defaultNetwork
    }

    static func defaultPathPreset(for chain: SeedDerivationChain) -> WalletDerivationPathPreset {
        chainPreset(for: chain).defaultPath
    }

    static func defaultPreset(for chain: SeedDerivationChain) -> WalletDerivationPathPreset {
        defaultPathPreset(for: chain)
    }

    static func defaultPath(
        for chain: SeedDerivationChain,
        network _: WalletDerivationNetwork = .mainnet
    ) -> String {
        return chainPreset(for: chain).defaultPath.derivationPath
    }

    static func mainnetUIPresets(for chain: SeedDerivationChain) -> [SeedDerivationPathPreset] {
        pathPresets(for: chain).map(\.uiPreset)
    }

    private static func load() -> [WalletDerivationChainPreset] {
        do {
            return try WalletRustAppCoreBridge.chainPresets()
        } catch {
            fatalError("Rust derivation preset catalog failed to load: \(error.localizedDescription)")
        }
    }

    private static func loadRequestCompilation() -> [WalletDerivationRequestCompilationPreset] {
        do {
            return try WalletRustAppCoreBridge.requestCompilationPresets()
        } catch {
            fatalError("Rust derivation request compilation catalog failed to load: \(error.localizedDescription)")
        }
    }
}

extension SeedDerivationChain {
    var apiPreset: WalletDerivationChainPreset {
        WalletDerivationPresetCatalog.chainPreset(for: self)
    }

    var apiPathPresets: [WalletDerivationPathPreset] {
        WalletDerivationPresetCatalog.pathPresets(for: self)
    }

    var apiNetworkPresets: [WalletDerivationNetworkPreset] {
        WalletDerivationPresetCatalog.networkPresets(for: self)
    }
}
