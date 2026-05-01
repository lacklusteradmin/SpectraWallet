import Foundation

// MARK: ─ (merged from WalletDerivationLayer.swift)

nonisolated struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
}
enum WalletDerivationCurve: String, Codable {
    case secp256k1
    case ed25519
}
enum WalletDerivationError: LocalizedError {
    case emptyRequestedOutputs
    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs: return "At least one derivation output must be requested."
        }
    }
}
enum WalletDerivationLayer {
    static func derive(
        seedPhrase: String, chain: SeedDerivationChain,
        derivationPath: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> WalletRustDerivationResponseModel {
        guard !requestedOutputs.isEmpty else { throw WalletDerivationError.emptyRequestedOutputs }
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, seedPhrase: seedPhrase, derivationPath: derivationPath,
            passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: requestedOutputs,
            overrides: overrides
        )
        return try WalletRustDerivationBridge.derive(request)
    }
    static func deriveAddress(
        seedPhrase: String, chain: SeedDerivationChain, derivationPath: String,
        overrides: CoreWalletDerivationOverrides? = nil
    ) throws -> String
    {
        let result = try derive(
            seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath,
            requestedOutputs: .address, overrides: overrides)
        guard let address = result.address else { throw WalletDerivationError.emptyRequestedOutputs }
        return address
    }
    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        CachedCoreHelpers.evmSeedDerivationChainName(chainName: chainName).flatMap(SeedDerivationChain.init(rawValue:))
    }
}

// MARK: ─ (merged from Presets.swift)

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
typealias WalletDerivationRequestCompilationPreset = AppCoreRequestCompilationPreset

extension AppCorePathPreset {
    nonisolated var uiPreset: SeedDerivationPathPreset {
        SeedDerivationPathPreset(title: title, detail: detail, path: derivationPath)
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

    nonisolated static func defaultPath(for chain: SeedDerivationChain) -> String {
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
