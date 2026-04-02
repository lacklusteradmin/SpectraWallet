import Foundation

enum ChainIntegrationState: String {
    case live = "Live"
    case planned = "Planned"
}

protocol ChainWalletBackend {
    var chainName: String { get }
    var supportedSymbols: [String] { get }
    var integrationState: ChainIntegrationState { get }
    var supportsSeedImport: Bool { get }
    var supportsBalanceRefresh: Bool { get }
    var supportsReceiveAddress: Bool { get }
    var supportsSend: Bool { get }
}

struct BitcoinChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin"
    let supportedSymbols = ["BTC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BitcoinCashChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin Cash"
    let supportedSymbols = ["BCH"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BitcoinSVChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin SV"
    let supportedSymbols = ["BSV"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct LitecoinChainBackend: ChainWalletBackend {
    let chainName = "Litecoin"
    let supportedSymbols = ["LTC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct EthereumChainBackend: ChainWalletBackend {
    let chainName = "Ethereum"
    let supportedSymbols = ["ETH", "USDT", "USDC", "DAI"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct ArbitrumChainBackend: ChainWalletBackend {
    let chainName = "Arbitrum"
    let supportedSymbols = ["ETH", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct OptimismChainBackend: ChainWalletBackend {
    let chainName = "Optimism"
    let supportedSymbols = ["ETH", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct EthereumClassicChainBackend: ChainWalletBackend {
    let chainName = "Ethereum Classic"
    let supportedSymbols = ["ETC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct DogecoinChainBackend: ChainWalletBackend {
    let chainName = "Dogecoin"
    let supportedSymbols = ["DOGE"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BNBChainBackend: ChainWalletBackend {
    let chainName = "BNB Chain"
    let supportedSymbols = ["BNB"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct AvalancheChainBackend: ChainWalletBackend {
    let chainName = "Avalanche"
    let supportedSymbols = ["AVAX"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct HyperliquidChainBackend: ChainWalletBackend {
    let chainName = "Hyperliquid"
    let supportedSymbols = ["HYPE", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct TronChainBackend: ChainWalletBackend {
    let chainName = "Tron"
    let supportedSymbols = ["TRX", "USDT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct SolanaChainBackend: ChainWalletBackend {
    let chainName = "Solana"
    let supportedSymbols = ["SOL"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct XRPChainBackend: ChainWalletBackend {
    let chainName = "XRP Ledger"
    let supportedSymbols = ["XRP"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct MoneroChainBackend: ChainWalletBackend {
    let chainName = "Monero"
    let supportedSymbols = ["XMR"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct CardanoChainBackend: ChainWalletBackend {
    let chainName = "Cardano"
    let supportedSymbols = ["ADA"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct SuiChainBackend: ChainWalletBackend {
    let chainName = "Sui"
    let supportedSymbols = ["SUI"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct AptosChainBackend: ChainWalletBackend {
    let chainName = "Aptos"
    let supportedSymbols = ["APT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct TONChainBackend: ChainWalletBackend {
    let chainName = "TON"
    let supportedSymbols = ["TON", "Tracked Jettons"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct ICPChainBackend: ChainWalletBackend {
    let chainName = "Internet Computer"
    let supportedSymbols = ["ICP"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct NearChainBackend: ChainWalletBackend {
    let chainName = "NEAR"
    let supportedSymbols = ["NEAR"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct PolkadotChainBackend: ChainWalletBackend {
    let chainName = "Polkadot"
    let supportedSymbols = ["DOT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct StellarChainBackend: ChainWalletBackend {
    let chainName = "Stellar"
    let supportedSymbols = ["XLM"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct PlannedChainBackend: ChainWalletBackend {
    let chainName: String
    let supportedSymbols: [String]
    let integrationState: ChainIntegrationState = .planned
    let supportsSeedImport = true
    let supportsBalanceRefresh = false
    let supportsReceiveAddress = false
    let supportsSend = false
}

enum AppChainID: String, CaseIterable, Identifiable {
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    case tron
    case solana
    case cardano
    case xrp
    case stellar
    case monero
    case sui
    case aptos
    case ton
    case icp
    case near
    case polkadot

    var id: String { rawValue }
}

struct AppChainDescriptor: Identifiable {
    let id: AppChainID
    let chainName: String
    let shortLabel: String
    let nativeSymbol: String
    let searchKeywords: [String]
    let supportsDiagnostics: Bool
    let supportsEndpointCatalog: Bool
    let isEVM: Bool

    var title: String {
        String(
            format: AppLocalization.string("%@ Diagnostics"),
            locale: AppLocalization.locale,
            chainName
        )
    }

    init(
        id: AppChainID,
        chainName: String,
        title: String,
        shortLabel: String,
        nativeSymbol: String,
        searchKeywords: [String],
        supportsDiagnostics: Bool,
        supportsEndpointCatalog: Bool,
        isEVM: Bool
    ) {
        self.id = id
        self.chainName = chainName
        self.shortLabel = shortLabel
        self.nativeSymbol = nativeSymbol
        self.searchKeywords = searchKeywords
        self.supportsDiagnostics = supportsDiagnostics
        self.supportsEndpointCatalog = supportsEndpointCatalog
        self.isEVM = isEVM
    }
}

struct ChainBroadcastProviderOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum ChainBackendRegistry {
    static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        switch chainName {
        case "Bitcoin":
            return [
                ChainBroadcastProviderOption(id: "esplora", title: "Esplora"),
                ChainBroadcastProviderOption(id: "maestro-esplora", title: "Maestro Esplora")
            ]
        case "Bitcoin Cash":
            return [
                ChainBroadcastProviderOption(id: "blockchair", title: "Blockchair"),
                ChainBroadcastProviderOption(id: "actorforth", title: "ActorForth REST")
            ]
        case "Bitcoin SV":
            return [
                ChainBroadcastProviderOption(id: "whatsonchain", title: "WhatsOnChain"),
                ChainBroadcastProviderOption(id: "blockchair", title: "Blockchair")
            ]
        case "Litecoin":
            return [
                ChainBroadcastProviderOption(id: "litecoinspace", title: "LitecoinSpace"),
                ChainBroadcastProviderOption(id: "blockcypher", title: "BlockCypher")
            ]
        case "Dogecoin":
            return [
                ChainBroadcastProviderOption(id: "blockchair", title: "Blockchair"),
                ChainBroadcastProviderOption(id: "blockcypher", title: "BlockCypher")
            ]
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return [
                ChainBroadcastProviderOption(id: "rpc", title: "RPC Broadcast")
            ]
        case "Tron":
            return [
                ChainBroadcastProviderOption(id: "trongrid-io", title: "TronGrid"),
                ChainBroadcastProviderOption(id: "trongrid-pro", title: "TronGrid Pro"),
                ChainBroadcastProviderOption(id: "trongrid-network", title: "TronGrid Network")
            ]
        case "Solana":
            return [
                ChainBroadcastProviderOption(id: "solana-mainnet-beta", title: "Solana Mainnet RPC"),
                ChainBroadcastProviderOption(id: "solana-ankr", title: "Ankr Solana RPC")
            ]
        case "Cardano":
            return [
                ChainBroadcastProviderOption(id: "koios", title: "Koios"),
                ChainBroadcastProviderOption(id: "xray-koios", title: "Xray Koios"),
                ChainBroadcastProviderOption(id: "happystaking-koios", title: "HappyStake Koios")
            ]
        case "XRP Ledger":
            return [
                ChainBroadcastProviderOption(id: "ripple-s1", title: "Ripple RPC S1"),
                ChainBroadcastProviderOption(id: "ripple-s2", title: "Ripple RPC S2"),
                ChainBroadcastProviderOption(id: "xrplcluster", title: "XRPL Cluster")
            ]
        case "Stellar":
            return [
                ChainBroadcastProviderOption(id: "stellar-horizon", title: "Stellar Horizon"),
                ChainBroadcastProviderOption(id: "lobstr-horizon", title: "LOBSTR Horizon")
            ]
        case "Monero":
            return [
                ChainBroadcastProviderOption(id: "edge-lws-1", title: "Edge Monero LWS 1"),
                ChainBroadcastProviderOption(id: "edge-lws-2", title: "Edge Monero LWS 2"),
                ChainBroadcastProviderOption(id: "edge-lws-3", title: "Edge Monero LWS 3")
            ]
        case "Sui":
            return [
                ChainBroadcastProviderOption(id: "sui-mainnet", title: "Sui Mainnet"),
                ChainBroadcastProviderOption(id: "sui-publicnode", title: "PublicNode Sui"),
                ChainBroadcastProviderOption(id: "sui-blockvision", title: "BlockVision Sui"),
                ChainBroadcastProviderOption(id: "sui-blockpi", title: "BlockPI Sui"),
                ChainBroadcastProviderOption(id: "sui-suiscan", title: "SuiScan RPC")
            ]
        case "Aptos":
            return [
                ChainBroadcastProviderOption(id: "aptoslabs-api", title: "Aptos Labs API"),
                ChainBroadcastProviderOption(id: "blastapi-aptos", title: "BlastAPI Aptos"),
                ChainBroadcastProviderOption(id: "aptoslabs-mainnet", title: "Aptos Mainnet")
            ]
        case "TON":
            return [
                ChainBroadcastProviderOption(id: "ton-api-v2", title: "TON API v2")
            ]
        case "Internet Computer":
            return [
                ChainBroadcastProviderOption(id: "rosetta", title: "Rosetta")
            ]
        case "NEAR":
            return [
                ChainBroadcastProviderOption(id: "near-mainnet-rpc", title: "NEAR Mainnet RPC"),
                ChainBroadcastProviderOption(id: "fastnear-rpc", title: "FastNEAR RPC"),
                ChainBroadcastProviderOption(id: "lava-near-rpc", title: "Lava NEAR RPC")
            ]
        case "Polkadot":
            return [
                ChainBroadcastProviderOption(id: "sidecar", title: "Sidecar")
            ]
        default:
            return []
        }
    }

    enum BitcoinRuntimeEndpoints {
        static let blockchainInfoMultiAddressBaseURL = "https://blockchain.info/multiaddr"
        static let blockchairXPubDashboardBaseURL = "https://api.blockchair.com/bitcoin/dashboards/xpub/"

        static func esploraBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
            switch networkMode {
            case .mainnet:
                return [
                    "https://blockstream.info/api",
                    "https://mempool.space/api",
                    "https://mempool.emzy.de/api",
                    "https://xbt-mainnet.gomaestro-api.org/v0/esplora"
                ]
            case .testnet:
                return [
                    "https://blockstream.info/testnet/api",
                    "https://mempool.space/testnet/api"
                ]
            case .testnet4:
                return [
                    "https://mempool.space/testnet4/api"
                ]
            case .signet:
                return [
                    "https://blockstream.info/signet/api",
                    "https://mempool.space/signet/api"
                ]
            }
        }

        static func walletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
            switch networkMode {
            case .mainnet:
                return [
                    "https://blockstream.info/api",
                    "https://mempool.space/api",
                    "https://xbt-mainnet.gomaestro-api.org/v0/esplora"
                ]
            case .testnet:
                return [
                    "https://blockstream.info/testnet/api",
                    "https://mempool.space/testnet/api"
                ]
            case .testnet4:
                return [
                    "https://mempool.space/testnet4/api"
                ]
            case .signet:
                return [
                    "https://mempool.space/signet/api"
                ]
            }
        }
    }

    enum BitcoinCashRuntimeEndpoints {
        static let blockchairBaseURL = "https://api.blockchair.com/bitcoin-cash"
        static let blockchairPushURL = "https://api.blockchair.com/bitcoin-cash/push/transaction"
        static let blockchairTransactionURLPrefix = "https://api.blockchair.com/bitcoin-cash/dashboards/transaction/"
        static let actorforthBaseURL = "https://rest.bch.actorforth.org/v2"
        static let actorforthTransactionURLPrefix = "https://rest.bch.actorforth.org/v2/transaction/details/"
        static let actorforthBroadcastURLPrefix = "https://rest.bch.actorforth.org/v2/rawtransactions/sendRawTransaction/"
    }

    enum BitcoinSVRuntimeEndpoints {
        static let whatsonchainBaseURL = "https://api.whatsonchain.com/v1/bsv/main"
        static let whatsonchainChainInfoURL = "https://api.whatsonchain.com/v1/bsv/main/chain/info"
        static let whatsonchainBroadcastURL = "https://api.whatsonchain.com/v1/bsv/main/tx/raw"
        static let whatsonchainTransactionURLPrefix = "https://api.whatsonchain.com/v1/bsv/main/tx/hash/"
        static let blockchairBaseURL = "https://api.blockchair.com/bitcoin-sv"
        static let blockchairPushURL = "https://api.blockchair.com/bitcoin-sv/push/transaction"
        static let blockchairTransactionURLPrefix = "https://api.blockchair.com/bitcoin-sv/dashboards/transaction/"
    }

    enum LitecoinRuntimeEndpoints {
        static let litecoinspaceBaseURL = "https://litecoinspace.org/api"
        static let blockcypherBaseURL = "https://api.blockcypher.com/v1/ltc/main"
        static let sochainBaseURL = "https://sochain.com/api/v2"
    }

    enum DogecoinRuntimeEndpoints {
        static let blockchairBaseURL = "https://api.blockchair.com/dogecoin"
        static let blockcypherBaseURL = "https://api.blockcypher.com/v1/doge/main"
        static let dogechainBaseURL = "https://dogechain.info/api/v1"
        static let sochainBaseURL = "https://sochain.com/api/v2"
        static let testnetElectrsBaseURL = "https://doge-electrs-testnet-demo.qed.me"
    }

    enum TronRuntimeEndpoints {
        static let tronScanAddressInfoBases = [
            "https://apilist.tronscanapi.com/api/accountv2"
        ]
        static let tronGridAccountsBases = [
            "https://api.trongrid.io/v1/accounts",
            "https://api.trongrid.pro/v1/accounts",
            "https://api.trongrid.network/v1/accounts"
        ]
        static let tronGridBroadcastBaseURLs = [
            "https://api.trongrid.io",
            "https://api.trongrid.pro",
            "https://api.trongrid.network"
        ]
        static let tronScanProbeURL = "https://apilist.tronscanapi.com/api/system/status"
        static let tronGridProbeURL = "https://api.trongrid.io/wallet/getnowblock"
        static let tronGridBaseURL = "https://api.trongrid.io"
    }

    enum SolanaRuntimeEndpoints {
        static let balanceRPCBaseURLs = [
            "https://api.mainnet-beta.solana.com",
            "https://rpc.ankr.com/solana",
            "https://solana-rpc.publicnode.com"
        ]
        static let sendRPCBaseURLs = Array(balanceRPCBaseURLs.prefix(2))
    }

    enum XRPRuntimeEndpoints {
        static let accountHistoryBases = [
            "https://api.xrpscan.com/api/v1/account",
            "https://xrpscan.com/api/v1/account"
        ]
        static let rpcBaseURLs = [
            "https://s1.ripple.com:51234/",
            "https://s2.ripple.com:51234/",
            "https://xrplcluster.com/"
        ]

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }
    }

    enum CardanoRuntimeEndpoints {
        static let koiosBaseURLs = [
            "https://api.koios.rest/api/v1",
            "https://graph.xray.app/output/services/koios/mainnet/api/v1",
            "https://koios.happystaking.io:8453/api/v1"
        ]

        static var primaryBaseURL: URL {
            URL(string: koiosBaseURLs[0])!
        }
    }

    enum AptosRuntimeEndpoints {
        static let rpcBaseURLs = [
            "https://api.mainnet.aptoslabs.com/v1",
            "https://aptos-mainnet.public.blastapi.io/v1",
            "https://mainnet.aptoslabs.com/v1"
        ]

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }

        static var primaryRPCURL: URL {
            rpcURLs[0]
        }
    }

    enum TONRuntimeEndpoints {
        static let apiV2BaseURLs = ["https://toncenter.com/api/v2"]
        static let apiV3BaseURLs = ["https://toncenter.com/api/v3"]

        static var primaryAPIv2URL: URL {
            URL(string: apiV2BaseURLs[0])!
        }
    }

    enum SuiRuntimeEndpoints {
        static let rpcBaseURLs = [
            "https://fullnode.mainnet.sui.io:443",
            "https://sui-rpc.publicnode.com",
            "https://sui-mainnet-endpoint.blockvision.org",
            "https://sui.blockpi.network/v1/rpc/public",
            "https://rpc-mainnet.suiscan.xyz"
        ]

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }

        static var primaryRPCURL: URL {
            rpcURLs[0]
        }
    }

    enum NearRuntimeEndpoints {
        static let rpcBaseURLs = [
            "https://rpc.mainnet.near.org",
            "https://free.rpc.fastnear.com",
            "https://near.lava.build"
        ]
        static let historyBaseURLs = [
            "https://api.nearblocks.io/v1"
        ]
    }

    enum PolkadotRuntimeEndpoints {
        static let sidecarBaseURLs = [
            "https://polkadot-public-sidecar.parity-chains.parity.io"
        ]
        static let rpcBaseURLs = [
            "https://polkadot.api.onfinality.io/public",
            "https://polkadot.dotters.network",
            "https://rpc.ibp.network/polkadot"
        ]
    }

    enum StellarRuntimeEndpoints {
        static let horizonBaseURLs = [
            "https://horizon.stellar.org",
            "https://horizon.stellar.lobstr.co"
        ]
    }

    enum MoneroRuntimeEndpoints {
        static let trustedBackendBaseURLs = [
            "https://monerolws1.edge.app",
            "https://monerolws2.edge.app",
            "https://monerolws3.edge.app"
        ]
    }

    enum ICPRuntimeEndpoints {
        static let rosettaBaseURLs = [
            "https://rosetta-api.internetcomputer.org"
        ]
    }

    enum ExplorerRegistry {
        private static let transactionBases: [String: String] = [
            bitcoinChainName: "https://mempool.space/tx/",
            bitcoinCashChainName: "https://blockchair.com/bitcoin-cash/transaction/",
            "Bitcoin SV": "https://whatsonchain.com/tx/",
            litecoinChainName: "https://litecoinspace.org/tx/",
            dogecoinChainName: "https://dogechain.info/tx/",
            ethereumChainName: "https://etherscan.io/tx/",
            ethereumClassicChainName: "https://blockscout.com/etc/mainnet/tx/",
            arbitrumChainName: "https://arbiscan.io/tx/",
            optimismChainName: "https://optimistic.etherscan.io/tx/",
            bnbChainName: "https://bscscan.com/tx/",
            avalancheChainName: "https://snowtrace.io/tx/",
            hyperliquidChainName: "https://app.hyperliquid.xyz/explorer/tx/",
            icpChainName: "https://dashboard.internetcomputer.org/transaction/",
            stellarChainName: "https://stellar.expert/explorer/public/tx/",
            tonChainName: "https://tonviewer.com/",
            tronChainName: "https://tronscan.org/#/transaction/",
            nearChainName: "https://nearblocks.io/txns/",
            polkadotChainName: "https://polkadot.subscan.io/extrinsic/"
        ]

        private static let transactionLabels: [String: String] = [
            bitcoinChainName: "Open In Mempool",
            bitcoinCashChainName: "Open In Blockchair",
            "Bitcoin SV": "Open In WhatsOnChain",
            litecoinChainName: "Open In LitecoinSpace",
            dogecoinChainName: "Open In Dogechain",
            ethereumChainName: "Open In Etherscan",
            ethereumClassicChainName: "Open In Blockscout",
            arbitrumChainName: "Open In Arbiscan",
            optimismChainName: "Open In Optimism Etherscan",
            bnbChainName: "Open In BscScan",
            avalancheChainName: "Open In Snowtrace",
            hyperliquidChainName: "Open In Hyperliquid Explorer",
            icpChainName: "Open In ICP Dashboard",
            stellarChainName: "Open In Stellar Expert",
            aptosChainName: "Open In Aptos Explorer",
            tonChainName: "Open In Tonviewer",
            tronChainName: "Open In TronScan",
            nearChainName: "Open In NearBlocks",
            polkadotChainName: "Open In Subscan"
        ]

        static func transactionURL(for chainName: String, transactionHash: String) -> URL? {
            switch chainName {
            case aptosChainName:
                return URL(string: "https://explorer.aptoslabs.com/txn/\(transactionHash)?network=mainnet")
            default:
                guard let baseURL = transactionBases[chainName] else { return nil }
                return URL(string: baseURL + transactionHash)
            }
        }

        static func transactionLabel(for chainName: String) -> String? {
            transactionLabels[chainName]
        }
    }

    enum MarketDataRegistry {
        static let coinGeckoSimplePriceURL = "https://api.coingecko.com/api/v3/simple/price"
        static let binanceTickerPriceURL = "https://api.binance.com/api/v3/ticker/price"
        static let coinbaseExchangeRatesURL = "https://api.coinbase.com/v2/exchange-rates?currency=USD"
        static let coinPaprikaTickersURL = "https://api.coinpaprika.com/v1/tickers"
        static let coinLoreTickersURL = "https://api.coinlore.net/api/tickers/?start=0&limit=1000"
        static let openERLatestUSDURL = "https://open.er-api.com/v6/latest/USD"
        static let frankfurterLatestURL = "https://api.frankfurter.app/latest"
        static let exchangeRateHostLiveURL = "https://api.exchangerate.host/live"
        static let fawazAhmedUSDRatesURL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json"
    }

    enum EVMExplorerRegistry {
        static func etherscanStyleAPIURL(for chainName: String) -> URL? {
            let rawURL: String?
            switch chainName {
            case ethereumChainName:
                rawURL = "https://api.etherscan.io/v2/api"
            case bnbChainName:
                rawURL = "https://api.bscscan.com/api"
            case avalancheChainName:
                rawURL = "https://api.snowtrace.io/api"
            case hyperliquidChainName:
                rawURL = "https://api.hyperevmscan.io/api"
            default:
                rawURL = nil
            }
            return rawURL.flatMap(URL.init(string:))
        }

        static func blockscoutTokenTransfersURL(
            for chainName: String,
            normalizedAddress: String,
            page: Int,
            pageSize: Int
        ) -> URL? {
            switch chainName {
            case ethereumChainName:
                return URL(
                    string: "https://eth.blockscout.com/api/v2/addresses/\(normalizedAddress)/token-transfers?type=ERC-20&items_count=\(pageSize)&page=\(page)"
                )
            case ethereumClassicChainName:
                return URL(
                    string: "https://blockscout.com/etc/mainnet/api/v2/addresses/\(normalizedAddress)/token-transfers?type=ERC-20&items_count=\(pageSize)&page=\(page)"
                )
            default:
                return nil
            }
        }

        static func blockscoutAccountAPIURL(
            for chainName: String,
            normalizedAddress: String,
            action: String,
            page: Int,
            pageSize: Int
        ) -> URL? {
            switch chainName {
            case ethereumChainName:
                guard action == "txlist" else { return nil }
                return URL(
                    string: "https://eth.blockscout.com/api/v2/addresses/\(normalizedAddress)/transactions?items_count=\(max(10, min(pageSize, 500)))&page=\(max(1, page))"
                )
            case ethereumClassicChainName:
                guard action == "txlist" else { return nil }
                return URL(
                    string: "https://blockscout.com/etc/mainnet/api/v2/addresses/\(normalizedAddress)/transactions?items_count=\(max(10, min(pageSize, 500)))&page=\(max(1, page))"
                )
            default:
                return nil
            }
        }

        static func ethplorerHistoryURL(
            for chainName: String,
            normalizedAddress: String,
            requestedLimit: Int
        ) -> URL? {
            guard chainName == ethereumChainName else { return nil }
            return URL(
                string: "https://api.ethplorer.io/getAddressHistory/\(normalizedAddress)?apiKey=freekey&type=transfer&limit=\(requestedLimit)"
            )
        }

        static func addressExplorerURL(for chainName: String, normalizedAddress: String) -> URL? {
            guard chainName == hyperliquidChainName else { return nil }
            return URL(string: "https://hyperevmscan.io/address/\(normalizedAddress)")
        }

        static func diagnosticProbeEntries(for chainName: String) -> [(String, URL)] {
            switch chainName {
            case ethereumChainName:
                return [
                    ("Etherscan API", URL(string: "https://api.etherscan.io/api?module=stats&action=ethprice")!),
                    ("Ethplorer API", URL(string: "https://api.ethplorer.io/getAddressInfo/0x0000000000000000000000000000000000000000?apiKey=freekey")!)
                ]
            case bnbChainName:
                return [
                    ("BscScan API", URL(string: "https://api.bscscan.com/api?module=stats&action=bnbprice")!)
                ]
            default:
                return []
            }
        }

        static func supplementalEndpointCatalogEntries(for chainName: String) -> [String] {
            switch chainName {
            case ethereumChainName:
                return [
                    "https://api.etherscan.io/api",
                    "https://api.ethplorer.io"
                ]
            case bnbChainName:
                return [
                    "https://api.bscscan.com/api"
                ]
            default:
                return []
            }
        }
    }

    static let bitcoinChainName = "Bitcoin"
    static let bitcoinCashChainName = "Bitcoin Cash"
    static let litecoinChainName = "Litecoin"
    static let ethereumChainName = "Ethereum"
    static let arbitrumChainName = "Arbitrum"
    static let optimismChainName = "Optimism"
    static let ethereumClassicChainName = "Ethereum Classic"
    static let dogecoinChainName = "Dogecoin"
    static let bnbChainName = "BNB Chain"
    static let avalancheChainName = "Avalanche"
    static let hyperliquidChainName = "Hyperliquid"
    static let tronChainName = "Tron"
    static let solanaChainName = "Solana"
    static let xrpChainName = "XRP Ledger"
    static let moneroChainName = "Monero"
    static let cardanoChainName = "Cardano"
    static let suiChainName = "Sui"
    static let aptosChainName = "Aptos"
    static let tonChainName = "TON"
    static let icpChainName = "Internet Computer"
    static let nearChainName = "NEAR"
    static let polkadotChainName = "Polkadot"
    static let stellarChainName = "Stellar"
    static let liveChainNames = [
        bitcoinChainName,
        bitcoinCashChainName,
        litecoinChainName,
        ethereumChainName,
        arbitrumChainName,
        optimismChainName,
        ethereumClassicChainName,
        dogecoinChainName,
        bnbChainName,
        avalancheChainName,
        hyperliquidChainName,
        tronChainName,
        solanaChainName,
        xrpChainName,
        moneroChainName,
        cardanoChainName,
        suiChainName,
        aptosChainName,
        tonChainName,
        icpChainName,
        nearChainName,
        polkadotChainName,
        stellarChainName
    ]

    static let allBackends: [any ChainWalletBackend] = [
        BitcoinChainBackend(),
        BitcoinCashChainBackend(),
        BitcoinSVChainBackend(),
        LitecoinChainBackend(),
        EthereumChainBackend(),
        ArbitrumChainBackend(),
        OptimismChainBackend(),
        EthereumClassicChainBackend(),
        DogecoinChainBackend(),
        BNBChainBackend(),
        AvalancheChainBackend(),
        HyperliquidChainBackend(),
        TronChainBackend(),
        SolanaChainBackend(),
        XRPChainBackend(),
        MoneroChainBackend(),
        CardanoChainBackend(),
        SuiChainBackend(),
        AptosChainBackend(),
        TONChainBackend(),
        ICPChainBackend(),
        NearChainBackend(),
        PolkadotChainBackend(),
        StellarChainBackend(),
        PlannedChainBackend(chainName: "Polygon", supportedSymbols: ["MATIC"])
    ]

    static let appChains: [AppChainDescriptor] = [
        AppChainDescriptor(id: .bitcoin, chainName: bitcoinChainName, title: "Bitcoin Diagnostics", shortLabel: "BTC", nativeSymbol: "BTC", searchKeywords: ["Bitcoin", "BTC"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .bitcoinCash, chainName: bitcoinCashChainName, title: "Bitcoin Cash Diagnostics", shortLabel: "BCH", nativeSymbol: "BCH", searchKeywords: ["Bitcoin Cash", "BCH"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .bitcoinSV, chainName: "Bitcoin SV", title: "Bitcoin SV Diagnostics", shortLabel: "BSV", nativeSymbol: "BSV", searchKeywords: ["Bitcoin SV", "BSV"], supportsDiagnostics: true, supportsEndpointCatalog: false, isEVM: false),
        AppChainDescriptor(id: .litecoin, chainName: litecoinChainName, title: "Litecoin Diagnostics", shortLabel: "LTC", nativeSymbol: "LTC", searchKeywords: ["Litecoin", "LTC"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .dogecoin, chainName: dogecoinChainName, title: "Dogecoin Diagnostics", shortLabel: "DOGE", nativeSymbol: "DOGE", searchKeywords: ["Dogecoin", "DOGE"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .ethereum, chainName: ethereumChainName, title: "Ethereum Diagnostics", shortLabel: "ETH", nativeSymbol: "ETH", searchKeywords: ["Ethereum", "ETH"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .ethereumClassic, chainName: ethereumClassicChainName, title: "Ethereum Classic Diagnostics", shortLabel: "ETC", nativeSymbol: "ETC", searchKeywords: ["Ethereum Classic", "ETC"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .arbitrum, chainName: arbitrumChainName, title: "Arbitrum Diagnostics", shortLabel: "ARB", nativeSymbol: "ETH", searchKeywords: ["Arbitrum", "ARB"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .optimism, chainName: optimismChainName, title: "Optimism Diagnostics", shortLabel: "OP", nativeSymbol: "ETH", searchKeywords: ["Optimism", "OP"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .bnb, chainName: bnbChainName, title: "BNB Chain Diagnostics", shortLabel: "BNB", nativeSymbol: "BNB", searchKeywords: ["BNB Chain", "BNB"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .avalanche, chainName: avalancheChainName, title: "Avalanche Diagnostics", shortLabel: "AVAX", nativeSymbol: "AVAX", searchKeywords: ["Avalanche", "AVAX"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .hyperliquid, chainName: hyperliquidChainName, title: "Hyperliquid Diagnostics", shortLabel: "HYPE", nativeSymbol: "HYPE", searchKeywords: ["Hyperliquid", "HYPE"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .tron, chainName: tronChainName, title: "Tron Diagnostics", shortLabel: "TRX", nativeSymbol: "TRX", searchKeywords: ["Tron", "TRX"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .solana, chainName: solanaChainName, title: "Solana Diagnostics", shortLabel: "SOL", nativeSymbol: "SOL", searchKeywords: ["Solana", "SOL"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .cardano, chainName: cardanoChainName, title: "Cardano Diagnostics", shortLabel: "ADA", nativeSymbol: "ADA", searchKeywords: ["Cardano", "ADA"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .xrp, chainName: xrpChainName, title: "XRP Diagnostics", shortLabel: "XRP", nativeSymbol: "XRP", searchKeywords: ["XRP", "XRP Ledger"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .stellar, chainName: stellarChainName, title: "Stellar Diagnostics", shortLabel: "XLM", nativeSymbol: "XLM", searchKeywords: ["Stellar", "XLM"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .monero, chainName: moneroChainName, title: "Monero Diagnostics", shortLabel: "XMR", nativeSymbol: "XMR", searchKeywords: ["Monero", "XMR"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .sui, chainName: suiChainName, title: "Sui Diagnostics", shortLabel: "SUI", nativeSymbol: "SUI", searchKeywords: ["Sui", "SUI"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .aptos, chainName: aptosChainName, title: "Aptos Diagnostics", shortLabel: "APT", nativeSymbol: "APT", searchKeywords: ["Aptos", "APT"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .ton, chainName: tonChainName, title: "TON Diagnostics", shortLabel: "TON", nativeSymbol: "TON", searchKeywords: ["TON"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .icp, chainName: icpChainName, title: "Internet Computer Diagnostics", shortLabel: "ICP", nativeSymbol: "ICP", searchKeywords: ["Internet Computer", "ICP"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .near, chainName: nearChainName, title: "NEAR Diagnostics", shortLabel: "NEAR", nativeSymbol: "NEAR", searchKeywords: ["NEAR"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .polkadot, chainName: polkadotChainName, title: "Polkadot Diagnostics", shortLabel: "DOT", nativeSymbol: "DOT", searchKeywords: ["Polkadot", "DOT"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false)
    ]

    static func backend(for chainName: String) -> (any ChainWalletBackend)? {
        allBackends.first { $0.chainName == chainName }
    }

    static func supportsBalanceRefresh(for chainName: String) -> Bool {
        backend(for: chainName)?.supportsBalanceRefresh ?? false
    }

    static func supportsReceiveAddress(for chainName: String) -> Bool {
        backend(for: chainName)?.supportsReceiveAddress ?? false
    }

    static func supportsSend(for chainName: String) -> Bool {
        backend(for: chainName)?.supportsSend ?? false
    }

    static func appChain(for chainName: String) -> AppChainDescriptor? {
        appChains.first { $0.chainName == chainName }
    }

    static func appChain(for id: AppChainID) -> AppChainDescriptor {
        appChains.first(where: { $0.id == id })!
    }

    static var diagnosticsChains: [AppChainDescriptor] {
        appChains.filter(\.supportsDiagnostics)
    }

    static var endpointCatalogChains: [AppChainDescriptor] {
        appChains.filter(\.supportsEndpointCatalog)
    }

    static var futureIntegrationHeadline: String {
        "Bitcoin, Bitcoin Cash, and Litecoin are live today. Ethereum is live for seed-derived ETH send/receive plus ETH, USDT, USDC, and DAI balance tracking. Arbitrum is live for seed-derived ETH receive/send plus tracked ERC-20 balances and history on Arbitrum One. Optimism is live for seed-derived ETH receive/send plus tracked ERC-20 balances and history on Optimism mainnet. Ethereum Classic is live for seed-derived ETC send/receive and balance refresh. BNB Chain is live for seed-derived BNB send/receive and balance refresh. Avalanche is live for seed-derived AVAX send/receive and balance refresh. Hyperliquid is live for seed-derived HYPE receive/send plus tracked ERC-20 balances and history on HyperEVM. Dogecoin is live with seed-derived address import, balance refresh, receive, and in-app send. Tron is live for seed or watched-address import, TRX + USDT balance refresh, receive, history, and in-app send. Solana is live for seed or watched-address import, SOL balance refresh, receive, history, and in-app send. XRP Ledger is live for seed or watched-address import plus XRP balance and history refresh. Monero is live in remote-backend mode for balance, history, receive, and send. Cardano is live for seed-derived ADA balance/history, receive, and in-app send. Sui is live for seed or watched-address import plus SUI balance/history/send. Aptos is live for seed or watched-address APT receive, balance refresh, history, diagnostics, and in-app send. TON is live for seed or watched-address TON receive, balance refresh, history, diagnostics, and in-app send. Internet Computer is live for seed or watched-address ICP receive, balance refresh, history, diagnostics, and in-app send. NEAR is live for seed-derived receive, history, balance refresh, and in-app send. Polkadot is live for seed or watched-address DOT receive, balance refresh, history, diagnostics, and in-app send. Stellar is live for seed or watched-address XLM receive, balance refresh, history, diagnostics, and in-app send."
    }
}
