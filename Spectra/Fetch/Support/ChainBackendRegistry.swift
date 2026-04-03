import Foundation

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
        static let blockchainInfoMultiAddressBaseURL = AppEndpointDirectory.endpoint("bitcoin.blockchain_info.multiaddr")
        static let blockchairXPubDashboardBaseURL = AppEndpointDirectory.endpoint("bitcoin.blockchair.xpub")

        static func esploraBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
            AppEndpointDirectory.bitcoinEsploraBaseURLs(for: networkMode)
        }

        static func walletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
            AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(for: networkMode)
        }
    }

    enum BitcoinCashRuntimeEndpoints {
        static let blockchairBaseURL = AppEndpointDirectory.endpoint("bitcoincash.blockchair.api")
        static let blockchairPushURL = AppEndpointDirectory.endpoint("bitcoincash.blockchair.push")
        static let blockchairTransactionURLPrefix = AppEndpointDirectory.endpoint("bitcoincash.blockchair.txprefix")
        static let actorforthBaseURL = AppEndpointDirectory.endpoint("bitcoincash.actorforth.api")
        static let actorforthTransactionURLPrefix = AppEndpointDirectory.endpoint("bitcoincash.actorforth.txprefix")
        static let actorforthBroadcastURLPrefix = AppEndpointDirectory.endpoint("bitcoincash.actorforth.broadcast")
    }

    enum BitcoinSVRuntimeEndpoints {
        static let whatsonchainBaseURL = AppEndpointDirectory.endpoint("bitcoinsv.whatsonchain.api")
        static let whatsonchainChainInfoURL = AppEndpointDirectory.endpoint("bitcoinsv.whatsonchain.chaininfo")
        static let whatsonchainBroadcastURL = AppEndpointDirectory.endpoint("bitcoinsv.whatsonchain.broadcast")
        static let whatsonchainTransactionURLPrefix = AppEndpointDirectory.endpoint("bitcoinsv.whatsonchain.txprefix")
        static let blockchairBaseURL = AppEndpointDirectory.endpoint("bitcoinsv.blockchair.api")
        static let blockchairPushURL = AppEndpointDirectory.endpoint("bitcoinsv.blockchair.push")
        static let blockchairTransactionURLPrefix = AppEndpointDirectory.endpoint("bitcoinsv.blockchair.txprefix")
    }

    enum LitecoinRuntimeEndpoints {
        static let litecoinspaceBaseURL = AppEndpointDirectory.endpoint("litecoin.litecoinspace.api")
        static let blockcypherBaseURL = AppEndpointDirectory.endpoint("litecoin.blockcypher.api")
        static let sochainBaseURL = AppEndpointDirectory.endpoint("litecoin.sochain.api")
    }

    enum DogecoinRuntimeEndpoints {
        static let blockcypherBaseURL = AppEndpointDirectory.endpoint("dogecoin.mainnet.blockcypher")
        static let blockcypherTestnetBaseURL = AppEndpointDirectory.endpoint("dogecoin.testnet.blockcypher")
    }

    enum TronRuntimeEndpoints {
        static let tronScanAddressInfoBases = AppEndpointDirectory.endpoints(for: ["tron.tronscan.account"])
        static let tronGridAccountsBases = AppEndpointDirectory.endpoints(for: [
            "tron.trongrid.accounts.io",
            "tron.trongrid.accounts.pro",
            "tron.trongrid.accounts.network"
        ])
        static let tronGridBroadcastBaseURLs = AppEndpointDirectory.endpoints(for: [
            "tron.trongrid.rpc.io",
            "tron.trongrid.rpc.pro",
            "tron.trongrid.rpc.network"
        ])
        static let tronScanProbeURL = AppEndpointDirectory.diagnosticsChecks(for: tronChainName).first(where: { $0.endpoint.contains("tronscan") })?.probeURL ?? ""
        static let tronGridProbeURL = AppEndpointDirectory.diagnosticsChecks(for: tronChainName).first(where: { $0.endpoint.contains("trongrid") })?.probeURL ?? ""
        static let tronGridBaseURL = AppEndpointDirectory.endpoint("tron.trongrid.rpc.io")
    }

    enum SolanaRuntimeEndpoints {
        static let balanceRPCBaseURLs = AppEndpointDirectory.endpoints(for: [
            "solana.rpc.mainnet",
            "solana.rpc.ankr",
            "solana.rpc.publicnode"
        ])
        static let sendRPCBaseURLs = Array(balanceRPCBaseURLs.prefix(2))
    }

    enum XRPRuntimeEndpoints {
        static let accountHistoryBases = AppEndpointDirectory.endpoints(for: [
            "xrp.history.xrpscan_api",
            "xrp.history.xrpscan"
        ])
        static let rpcBaseURLs = AppEndpointDirectory.endpoints(for: [
            "xrp.rpc.s1",
            "xrp.rpc.s2",
            "xrp.rpc.cluster"
        ])

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }
    }

    enum CardanoRuntimeEndpoints {
        static let koiosBaseURLs = AppEndpointDirectory.endpoints(for: [
            "cardano.koios.primary",
            "cardano.koios.xray",
            "cardano.koios.happystaking"
        ])

        static var primaryBaseURL: URL {
            URL(string: koiosBaseURLs[0])!
        }
    }

    enum AptosRuntimeEndpoints {
        static let rpcBaseURLs = AppEndpointDirectory.endpoints(for: [
            "aptos.rpc.aptoslabs",
            "aptos.rpc.blastapi",
            "aptos.rpc.mainnet"
        ])

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }

        static var primaryRPCURL: URL {
            rpcURLs[0]
        }
    }

    enum TONRuntimeEndpoints {
        static let apiV2BaseURLs = AppEndpointDirectory.endpoints(for: ["ton.api.v2"])
        static let apiV3BaseURLs = AppEndpointDirectory.endpoints(for: ["ton.api.v3"])

        static var primaryAPIv2URL: URL {
            URL(string: apiV2BaseURLs[0])!
        }
    }

    enum SuiRuntimeEndpoints {
        static let rpcBaseURLs = AppEndpointDirectory.endpoints(for: [
            "sui.rpc.mainnet",
            "sui.rpc.publicnode",
            "sui.rpc.blockvision",
            "sui.rpc.blockpi",
            "sui.rpc.suiscan"
        ])

        static var rpcURLs: [URL] {
            rpcBaseURLs.compactMap(URL.init(string:))
        }

        static var primaryRPCURL: URL {
            rpcURLs[0]
        }
    }

    enum NearRuntimeEndpoints {
        static let rpcBaseURLs = AppEndpointDirectory.endpoints(for: [
            "near.rpc.mainnet",
            "near.rpc.fastnear",
            "near.rpc.lava"
        ])
        static let historyBaseURLs = AppEndpointDirectory.endpoints(for: ["near.history.nearblocks"])
    }

    enum PolkadotRuntimeEndpoints {
        static let sidecarBaseURLs = AppEndpointDirectory.endpoints(for: ["polkadot.sidecar.parity"])
        static let rpcBaseURLs = AppEndpointDirectory.endpoints(for: [
            "polkadot.rpc.onfinality",
            "polkadot.rpc.dotters",
            "polkadot.rpc.ibp"
        ])
    }

    enum StellarRuntimeEndpoints {
        static let horizonBaseURLs = AppEndpointDirectory.endpoints(for: [
            "stellar.horizon.primary",
            "stellar.horizon.lobstr"
        ])
    }

    enum MoneroRuntimeEndpoints {
        static let trustedBackendBaseURLs = AppEndpointDirectory.endpoints(for: [
            "monero.backend.1",
            "monero.backend.2",
            "monero.backend.3"
        ])
    }

    enum ICPRuntimeEndpoints {
        static let rosettaBaseURLs = AppEndpointDirectory.endpoints(for: ["icp.rosetta"])
    }

    enum ExplorerRegistry {
        static func transactionURL(for chainName: String, transactionHash: String) -> URL? {
            guard let baseURL = AppEndpointDirectory.transactionExplorerBaseURL(for: chainName) else { return nil }
            if chainName == aptosChainName {
                return URL(string: "\(baseURL)\(transactionHash)?network=mainnet")
            }
            return URL(string: baseURL + transactionHash)
        }

        static func transactionLabel(for chainName: String) -> String? {
            AppEndpointDirectory.transactionExplorerLabel(for: chainName)
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
            let rawURL: String? = switch chainName {
            case ethereumChainName:
                AppEndpointDirectory.endpoint("ethereum.explorer.etherscan").replacingOccurrences(of: "/api", with: "/v2/api")
            case bnbChainName:
                AppEndpointDirectory.endpoint("bnb.explorer.bscscan")
            case avalancheChainName:
                "https://api.snowtrace.io/api"
            case hyperliquidChainName:
                AppEndpointDirectory.endpoint("hyperliquid.explorer.api")
            default:
                nil
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
                let baseURL = AppEndpointDirectory.endpoint("ethereum.explorer.blockscout")
                return URL(
                    string: "\(baseURL)/api/v2/addresses/\(normalizedAddress)/token-transfers?type=ERC-20&items_count=\(pageSize)&page=\(page)"
                )
            case ethereumClassicChainName:
                let baseURL = AppEndpointDirectory.endpoint("ethereumclassic.explorer.blockscout")
                return URL(
                    string: "\(baseURL)/api/v2/addresses/\(normalizedAddress)/token-transfers?type=ERC-20&items_count=\(pageSize)&page=\(page)"
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
                let baseURL = AppEndpointDirectory.endpoint("ethereum.explorer.blockscout")
                return URL(
                    string: "\(baseURL)/api/v2/addresses/\(normalizedAddress)/transactions?items_count=\(max(10, min(pageSize, 500)))&page=\(max(1, page))"
                )
            case ethereumClassicChainName:
                guard action == "txlist" else { return nil }
                let baseURL = AppEndpointDirectory.endpoint("ethereumclassic.explorer.blockscout")
                return URL(
                    string: "\(baseURL)/api/v2/addresses/\(normalizedAddress)/transactions?items_count=\(max(10, min(pageSize, 500)))&page=\(max(1, page))"
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
            let baseURL = AppEndpointDirectory.endpoint("ethereum.explorer.ethplorer")
            return URL(
                string: "\(baseURL)/getAddressHistory/\(normalizedAddress)?apiKey=freekey&type=transfer&limit=\(requestedLimit)"
            )
        }

        static func addressExplorerURL(for chainName: String, normalizedAddress: String) -> URL? {
            guard chainName == hyperliquidChainName else { return nil }
            return URL(string: "\(AppEndpointDirectory.endpoint("hyperliquid.explorer.web"))/address/\(normalizedAddress)")
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
            AppEndpointDirectory.explorerSupplementalEndpoints(for: chainName)
        }
    }

    static let bitcoinChainName = "Bitcoin"
    static let bitcoinCashChainName = "Bitcoin Cash"
    static let bitcoinSVChainName = "Bitcoin SV"
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
