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
    }

    enum TONRuntimeEndpoints {
        static let apiV2BaseURLs = AppEndpointDirectory.endpoints(for: ["ton.api.v2"])
        static let apiV3BaseURLs = AppEndpointDirectory.endpoints(for: ["ton.api.v3"])
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

    private static func loadChainBackends() -> [ChainBackendRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.chainBackends()
        } catch {
            preconditionFailure("Rust chain backend catalog failed to load: \(error.localizedDescription)")
        }
    }

    private static func loadLiveChainNames() -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.liveChainNames()
        } catch {
            preconditionFailure("Rust live-chain catalog failed to load: \(error.localizedDescription)")
        }
    }

    private static func loadAppChains() -> [AppChainDescriptor] {
        do {
            return try WalletRustEndpointCatalogBridge.appChainDescriptors()
        } catch {
            preconditionFailure("Rust app-chain catalog failed to load: \(error.localizedDescription)")
        }
    }
}
