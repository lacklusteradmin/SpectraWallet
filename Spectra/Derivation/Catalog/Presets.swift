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

    func makeJSONRequest(
        seedPhrase: String,
        network: WalletDerivationNetwork,
        derivationPath: String?,
        requestedOutputs: WalletDerivationRequestedOutputs = .all,
        passphrase: String? = nil,
        iterationCount: Int? = nil,
        hmacKeyString: String? = nil
    ) throws -> Data {
        try JSONEncoder().encode(
            WalletDerivationJSONPresetRequest(
                chain: chain.rawValue,
                network: network.rawValue,
                seedPhrase: seedPhrase,
                derivationPath: derivationPath,
                curve: curve.rawValue,
                passphrase: passphrase,
                iterationCount: iterationCount,
                hmacKeyString: hmacKeyString,
                requestedOutputs: requestedOutputs.jsonValues
            )
        )
    }

    var defaultNetwork: WalletDerivationNetworkPreset {
        networks.first(where: \.isDefault) ?? networks[0]
    }

    var defaultPath: WalletDerivationPathPreset {
        derivationPaths.first(where: \.isDefault) ?? derivationPaths[0]
    }
}

private struct WalletDerivationJSONPresetRequest: Codable {
    let chain: String
    let network: String
    let seedPhrase: String
    let derivationPath: String?
    let curve: String
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: [String]
}

extension WalletDerivationRequestedOutputs {
    var jsonValues: [String] {
        var values: [String] = []
        if contains(.address) { values.append("address") }
        if contains(.publicKey) { values.append("publicKey") }
        if contains(.privateKey) { values.append("privateKey") }
        return values
    }

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
        guard let data = presetJSON.data(using: .utf8),
              let presets = try? decoder.decode([WalletDerivationChainPreset].self, from: data) else {
            fatalError("Invalid derivation preset JSON catalog")
        }
        return presets
    }

    private static let presetJSON = #"""
    [
      {
        "chain": "Bitcoin",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Bitcoin main network", "isDefault": true },
          { "network": "testnet", "title": "Testnet", "detail": "Bitcoin test network", "isDefault": false },
          { "network": "testnet4", "title": "Testnet4", "detail": "Bitcoin testnet4 network", "isDefault": false },
          { "network": "signet", "title": "Signet", "detail": "Bitcoin signet network", "isDefault": false }
        ],
        "derivationPaths": [
          { "title": "Taproot", "detail": "m/86'/0'/0'/0/0", "derivationPath": "m/86'/0'/0'/0/0", "isDefault": false },
          { "title": "Native SegWit", "detail": "m/84'/0'/0'/0/0", "derivationPath": "m/84'/0'/0'/0/0", "isDefault": true },
          { "title": "Nested SegWit", "detail": "m/49'/0'/0'/0/0", "derivationPath": "m/49'/0'/0'/0/0", "isDefault": false },
          { "title": "Legacy", "detail": "m/44'/0'/0'/0/0", "derivationPath": "m/44'/0'/0'/0/0", "isDefault": false },
          { "title": "Electrum Legacy", "detail": "m/0'/0", "derivationPath": "m/0'/0", "isDefault": false },
          { "title": "BIP32 Legacy", "detail": "m/0'/0/0", "derivationPath": "m/0'/0/0", "isDefault": false }
        ]
      },
      {
        "chain": "Bitcoin Cash",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Bitcoin Cash main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/145'/0'/0/0", "derivationPath": "m/44'/145'/0'/0/0", "isDefault": true },
          { "title": "Legacy", "detail": "m/44'/0'/0'/0/0", "derivationPath": "m/44'/0'/0'/0/0", "isDefault": false },
          { "title": "Electrum Legacy", "detail": "m/0", "derivationPath": "m/0", "isDefault": false }
        ]
      },
      {
        "chain": "Bitcoin SV",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Bitcoin SV main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/236'/0'/0/0", "derivationPath": "m/44'/236'/0'/0/0", "isDefault": true },
          { "title": "Electrum Legacy", "detail": "m/0", "derivationPath": "m/0", "isDefault": false }
        ]
      },
      {
        "chain": "Litecoin",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Litecoin main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Legacy", "detail": "m/44'/2'/0'/0/0", "derivationPath": "m/44'/2'/0'/0/0", "isDefault": true },
          { "title": "SegWit", "detail": "m/49'/2'/0'/0/0", "derivationPath": "m/49'/2'/0'/0/0", "isDefault": false },
          { "title": "Native SegWit", "detail": "m/84'/2'/0'/0/0", "derivationPath": "m/84'/2'/0'/0/0", "isDefault": false }
        ]
      },
      {
        "chain": "Dogecoin",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Dogecoin main network", "isDefault": true },
          { "network": "testnet", "title": "Testnet", "detail": "Dogecoin test network", "isDefault": false }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/3'/0'/0/0", "derivationPath": "m/44'/3'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Ethereum",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Ethereum main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Ethereum Classic",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Ethereum Classic main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/61'/0'/0/0", "derivationPath": "m/44'/61'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Arbitrum",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Arbitrum main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Optimism",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Optimism main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Avalanche",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Avalanche main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Hyperliquid",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Hyperliquid main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Tron",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Tron main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/195'/0'/0/0", "derivationPath": "m/44'/195'/0'/0/0", "isDefault": true },
          { "title": "Simple BIP44", "detail": "m/44'/195'/0'", "derivationPath": "m/44'/195'/0'", "isDefault": false },
          { "title": "Legacy", "detail": "m/44'/60'/0'/0/0", "derivationPath": "m/44'/60'/0'/0/0", "isDefault": false }
        ]
      },
      {
        "chain": "Solana",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Solana main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/501'/0'/0'", "derivationPath": "m/44'/501'/0'/0'", "isDefault": true },
          { "title": "Legacy", "detail": "m/44'/501'/0'", "derivationPath": "m/44'/501'/0'", "isDefault": false }
        ]
      },
      {
        "chain": "Stellar",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Stellar main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/148'/0'", "derivationPath": "m/44'/148'/0'", "isDefault": true }
        ]
      },
      {
        "chain": "XRP Ledger",
        "curve": "secp256k1",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "XRP Ledger main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/144'/0'/0/0", "derivationPath": "m/44'/144'/0'/0/0", "isDefault": true },
          { "title": "Simple BIP44", "detail": "m/44'/144'/0'", "derivationPath": "m/44'/144'/0'", "isDefault": false }
        ]
      },
      {
        "chain": "Cardano",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Cardano main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Shelley", "detail": "m/1852'/1815'/0'/0/0", "derivationPath": "m/1852'/1815'/0'/0/0", "isDefault": true },
          { "title": "Byron", "detail": "m/44'/1815'/0'/0/0", "derivationPath": "m/44'/1815'/0'/0/0", "isDefault": false }
        ]
      },
      {
        "chain": "Sui",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Sui main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/784'/0'/0'/0'", "derivationPath": "m/44'/784'/0'/0'/0'", "isDefault": true }
        ]
      },
      {
        "chain": "Aptos",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Aptos main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/637'/0'/0'/0'", "derivationPath": "m/44'/637'/0'/0'/0'", "isDefault": true }
        ]
      },
      {
        "chain": "TON",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "TON main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/607'/0'/0/0", "derivationPath": "m/44'/607'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "Internet Computer",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Internet Computer main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/223'/0'/0/0", "derivationPath": "m/44'/223'/0'/0/0", "isDefault": true }
        ]
      },
      {
        "chain": "NEAR",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "NEAR main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/397'/0'", "derivationPath": "m/44'/397'/0'", "isDefault": true }
        ]
      },
      {
        "chain": "Polkadot",
        "curve": "ed25519",
        "networks": [
          { "network": "mainnet", "title": "Mainnet", "detail": "Polkadot main network", "isDefault": true }
        ],
        "derivationPaths": [
          { "title": "Standard", "detail": "m/44'/354'/0'", "derivationPath": "m/44'/354'/0'", "isDefault": true }
        ]
      }
    ]
    """#
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
