import Foundation

enum ChainBackendRegistry {
    static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        do {
            return try WalletRustEndpointCatalogBridge.broadcastProviderOptions(for: chainName)
        } catch {
            preconditionFailure("Rust broadcast provider lookup failed for \(chainName): \(error.localizedDescription)")
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
    static let liveChainNames = loadLiveChainNames()

    static let allBackends: [ChainBackendRecord] = loadChainBackends()

    static let appChains: [AppChainDescriptor] = loadAppChains()

    static func backend(for chainName: String) -> ChainBackendRecord? {
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

    private static func loadChainBackends() -> [ChainBackendRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.chainBackends()
        } catch {
            return fallbackChainBackends
        }
    }

    private static func loadLiveChainNames() -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.liveChainNames()
        } catch {
            return fallbackLiveChainNames
        }
    }

    private static func loadAppChains() -> [AppChainDescriptor] {
        do {
            return try WalletRustEndpointCatalogBridge.appChainDescriptors()
        } catch {
            return fallbackAppChains
        }
    }

    private static let fallbackChainBackends: [ChainBackendRecord] = [
        ChainBackendRecord(chainName: bitcoinChainName, supportedSymbols: ["BTC"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: bitcoinCashChainName, supportedSymbols: ["BCH"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: bitcoinSVChainName, supportedSymbols: ["BSV"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: litecoinChainName, supportedSymbols: ["LTC"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: dogecoinChainName, supportedSymbols: ["DOGE"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: ethereumChainName, supportedSymbols: ["ETH", "USDT", "USDC", "DAI"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: ethereumClassicChainName, supportedSymbols: ["ETC"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: arbitrumChainName, supportedSymbols: ["ETH", "USDT", "USDC", "DAI"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: optimismChainName, supportedSymbols: ["ETH", "USDT", "USDC", "DAI"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: bnbChainName, supportedSymbols: ["BNB"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: avalancheChainName, supportedSymbols: ["AVAX"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: hyperliquidChainName, supportedSymbols: ["HYPE"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: tronChainName, supportedSymbols: ["TRX", "USDT"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: solanaChainName, supportedSymbols: ["SOL"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: xrpChainName, supportedSymbols: ["XRP"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: moneroChainName, supportedSymbols: ["XMR"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: cardanoChainName, supportedSymbols: ["ADA"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: suiChainName, supportedSymbols: ["SUI"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: aptosChainName, supportedSymbols: ["APT"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: tonChainName, supportedSymbols: ["TON"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: icpChainName, supportedSymbols: ["ICP"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: nearChainName, supportedSymbols: ["NEAR"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: polkadotChainName, supportedSymbols: ["DOT"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true),
        ChainBackendRecord(chainName: stellarChainName, supportedSymbols: ["XLM"], integrationState: .live, supportsSeedImport: true, supportsBalanceRefresh: true, supportsReceiveAddress: true, supportsSend: true)
    ]

    private static let fallbackLiveChainNames: [String] = fallbackChainBackends.map(\.chainName)

    private static let fallbackAppChains: [AppChainDescriptor] = [
        AppChainDescriptor(id: .bitcoin, chainName: bitcoinChainName, shortLabel: "BTC", nativeSymbol: "BTC", searchKeywords: ["bitcoin", "btc"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .bitcoinCash, chainName: bitcoinCashChainName, shortLabel: "BCH", nativeSymbol: "BCH", searchKeywords: ["bitcoin cash", "bch"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .bitcoinSV, chainName: bitcoinSVChainName, shortLabel: "BSV", nativeSymbol: "BSV", searchKeywords: ["bitcoin sv", "bsv"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .litecoin, chainName: litecoinChainName, shortLabel: "LTC", nativeSymbol: "LTC", searchKeywords: ["litecoin", "ltc"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .dogecoin, chainName: dogecoinChainName, shortLabel: "DOGE", nativeSymbol: "DOGE", searchKeywords: ["dogecoin", "doge"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .ethereum, chainName: ethereumChainName, shortLabel: "ETH", nativeSymbol: "ETH", searchKeywords: ["ethereum", "eth"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .ethereumClassic, chainName: ethereumClassicChainName, shortLabel: "ETC", nativeSymbol: "ETC", searchKeywords: ["ethereum classic", "etc"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .arbitrum, chainName: arbitrumChainName, shortLabel: "ARB", nativeSymbol: "ETH", searchKeywords: ["arbitrum", "arb"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .optimism, chainName: optimismChainName, shortLabel: "OP", nativeSymbol: "ETH", searchKeywords: ["optimism", "op"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .bnb, chainName: bnbChainName, shortLabel: "BNB", nativeSymbol: "BNB", searchKeywords: ["bnb", "bsc", "binance"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .avalanche, chainName: avalancheChainName, shortLabel: "AVAX", nativeSymbol: "AVAX", searchKeywords: ["avalanche", "avax"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .hyperliquid, chainName: hyperliquidChainName, shortLabel: "HYPE", nativeSymbol: "HYPE", searchKeywords: ["hyperliquid", "hyperevm", "hype"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: true),
        AppChainDescriptor(id: .tron, chainName: tronChainName, shortLabel: "TRX", nativeSymbol: "TRX", searchKeywords: ["tron", "trx"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .solana, chainName: solanaChainName, shortLabel: "SOL", nativeSymbol: "SOL", searchKeywords: ["solana", "sol"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .cardano, chainName: cardanoChainName, shortLabel: "ADA", nativeSymbol: "ADA", searchKeywords: ["cardano", "ada"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .xrp, chainName: xrpChainName, shortLabel: "XRP", nativeSymbol: "XRP", searchKeywords: ["xrp", "ripple", "xrp ledger"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .stellar, chainName: stellarChainName, shortLabel: "XLM", nativeSymbol: "XLM", searchKeywords: ["stellar", "xlm"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .monero, chainName: moneroChainName, shortLabel: "XMR", nativeSymbol: "XMR", searchKeywords: ["monero", "xmr"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .sui, chainName: suiChainName, shortLabel: "SUI", nativeSymbol: "SUI", searchKeywords: ["sui"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .aptos, chainName: aptosChainName, shortLabel: "APT", nativeSymbol: "APT", searchKeywords: ["aptos", "apt"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .ton, chainName: tonChainName, shortLabel: "TON", nativeSymbol: "TON", searchKeywords: ["ton", "the open network"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .icp, chainName: icpChainName, shortLabel: "ICP", nativeSymbol: "ICP", searchKeywords: ["internet computer", "icp"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .near, chainName: nearChainName, shortLabel: "NEAR", nativeSymbol: "NEAR", searchKeywords: ["near"], supportsDiagnostics: false, supportsEndpointCatalog: true, isEVM: false),
        AppChainDescriptor(id: .polkadot, chainName: polkadotChainName, shortLabel: "DOT", nativeSymbol: "DOT", searchKeywords: ["polkadot", "dot"], supportsDiagnostics: true, supportsEndpointCatalog: true, isEVM: false)
    ]
}
