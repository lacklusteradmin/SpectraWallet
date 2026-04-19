import Foundation

enum WalletDerivationBranch: Int {
    case external = 0
    case change = 1
}

enum WalletDerivationPath {
    static func dogecoin(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String {
        "m/44'/3'/\(account)'/\(branch.rawValue)/\(index)"
    }
}

typealias WalletDerivationChainPreset = AppCoreChainPreset
typealias WalletDerivationPathPreset = AppCorePathPreset
typealias WalletDerivationNetworkPreset = AppCoreNetworkPreset
typealias WalletDerivationRequestCompilationPreset = AppCoreRequestCompilationPreset

extension AppCorePathPreset {
    nonisolated var uiPreset: SeedDerivationPathPreset {
        SeedDerivationPathPreset(title: title, detail: detail, path: derivationPath)
    }
}

extension WalletDerivationRequestedOutputs {
    init(jsonValues: [String]) {
        var values: WalletDerivationRequestedOutputs = []
        for value in jsonValues {
            switch value {
            case "address": values.insert(.address)
            case "publicKey": values.insert(.publicKey)
            case "privateKey": values.insert(.privateKey)
            default: break
            }
        }
        self = values
    }
}

enum WalletDerivationPresetCatalog {
    nonisolated static let all: [WalletDerivationChainPreset] = load()
    nonisolated static let requestCompilationAll: [WalletDerivationRequestCompilationPreset] = loadRequestCompilation()

    nonisolated static func chainPreset(for chain: SeedDerivationChain) -> WalletDerivationChainPreset {
        guard let preset = all.first(where: { $0.chain == chain.rawValue }) else {
            fatalError("Missing derivation preset for \(chain.rawValue)")
        }
        return preset
    }

    nonisolated static func networkPresets(for chain: SeedDerivationChain) -> [WalletDerivationNetworkPreset] {
        chainPreset(for: chain).networks
    }

    nonisolated static func pathPresets(for chain: SeedDerivationChain) -> [WalletDerivationPathPreset] {
        chainPreset(for: chain).derivationPaths
    }

    nonisolated static func curve(for chain: SeedDerivationChain) -> WalletDerivationCurve {
        let raw = chainPreset(for: chain).curve
        guard let curve = WalletDerivationCurve(rawValue: raw) else {
            fatalError("Unknown curve \(raw) for \(chain.rawValue)")
        }
        return curve
    }

    nonisolated static func requestCompilationPreset(for chain: SeedDerivationChain) -> WalletDerivationRequestCompilationPreset {
        guard let preset = requestCompilationAll.first(where: { $0.chain == chain.rawValue }) else {
            fatalError("Missing derivation request compilation preset for \(chain.rawValue)")
        }
        return preset
    }

    nonisolated static func defaultPreset(for chain: SeedDerivationChain) -> WalletDerivationPathPreset {
        let paths = chainPreset(for: chain).derivationPaths
        return paths.first(where: \.isDefault) ?? paths[0]
    }

    nonisolated static func defaultPath(for chain: SeedDerivationChain, network _: WalletDerivationNetwork = .mainnet) -> String {
        defaultPreset(for: chain).derivationPath
    }

    nonisolated static func mainnetUIPresets(for chain: SeedDerivationChain) -> [SeedDerivationPathPreset] {
        pathPresets(for: chain).map(\.uiPreset)
    }

    private static func load() -> [WalletDerivationChainPreset] {
        do {
            return try appCoreChainPresets()
        } catch {
            fatalError("Rust derivation preset catalog failed to load: \(error.localizedDescription)")
        }
    }

    private static func loadRequestCompilation() -> [WalletDerivationRequestCompilationPreset] {
        do {
            return try appCoreRequestCompilationPresets()
        } catch {
            fatalError("Rust derivation request compilation catalog failed to load: \(error.localizedDescription)")
        }
    }
}
