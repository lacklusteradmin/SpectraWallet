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
        network: WalletDerivationNetwork = .mainnet
    ) -> String {
        let preset = chainPreset(for: chain)
        if preset.networks.contains(where: { $0.network == network }) {
            return preset.defaultPath.derivationPath
        }
        return preset.defaultPath.derivationPath
    }

    static func mainnetUIPresets(for chain: SeedDerivationChain) -> [SeedDerivationPathPreset] {
        pathPresets(for: chain).map(\.uiPreset)
    }

    private static func load() -> [WalletDerivationChainPreset] {
        let decoder = JSONDecoder()
        let resourceURL = Bundle.main.url(
            forResource: "DerivationPresets",
            withExtension: "json"
        ) ?? Bundle.main.url(
            forResource: "DerivationPresets",
            withExtension: "json",
            subdirectory: "Derivation/Catalog"
        ) ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("DerivationPresets.json")
        guard let data = try? Data(contentsOf: resourceURL),
              let presets = try? decoder.decode([WalletDerivationChainPreset].self, from: data) else {
            fatalError("Invalid derivation preset JSON catalog")
        }
        return presets
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
