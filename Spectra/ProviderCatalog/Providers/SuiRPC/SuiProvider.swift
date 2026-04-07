import Foundation

enum SuiProvider {
    static let endpointReliabilityNamespace = "sui.rpc"
    static let rpcURLs = ChainBackendRegistry.SuiRuntimeEndpoints.rpcURLs
    static let rpcBaseURLs = ChainBackendRegistry.SuiRuntimeEndpoints.rpcBaseURLs

    struct RPCEnvelope<ResultType: Decodable>: Decodable {
        let result: ResultType?
        let error: RPCError?

        struct RPCError: Decodable {
            let code: Int?
            let message: String?
        }
    }

    struct BalanceResult: Decodable {
        let totalBalance: String?

        enum CodingKeys: String, CodingKey {
            case totalBalance
        }
    }

    struct CoinBalanceResult: Decodable {
        let coinType: String?
        let totalBalance: String?

        enum CodingKeys: String, CodingKey {
            case coinType
            case totalBalance
        }
    }

    struct QueryTxBlocksResponse: Decodable {
        let data: [TransactionBlock]?
    }

    struct TransactionBlock: Decodable {
        let digest: String?
        let timestampMs: String?
        let effects: TxEffects?
        let transaction: TxData?
        let balanceChanges: [BalanceChange]?
    }

    struct TxEffects: Decodable {
        let status: TxStatus?
    }

    struct TxStatus: Decodable {
        let status: String?
    }

    struct TxData: Decodable {
        let data: TxInner?
    }

    struct TxInner: Decodable {
        let sender: String?
    }

    struct BalanceChange: Decodable {
        let owner: Owner?
        let coinType: String?
        let amount: String?
    }

    struct Owner: Decodable {
        let addressOwner: String?

        enum CodingKeys: String, CodingKey {
            case addressOwner = "AddressOwner"
        }
    }

    struct CoinPage: Decodable {
        let data: [CoinItem]?
        let hasNextPage: Bool?
        let nextCursor: String?
    }

    struct CoinItem: Decodable {
        let coinObjectID: String?
        let version: String?
        let digest: String?
        let balance: String?
    }

    struct ReferenceGasPriceResult: Decodable {
        let value: String?

        init(from decoder: Swift.Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(UInt64.self) {
                value = String(number)
                return
            }
            if let string = try? container.decode(String.self) {
                value = string
                return
            }
            value = nil
        }
    }

    struct ExecuteResult: Decodable {
        let digest: String?
        let effects: ExecuteEffects?

        struct ExecuteEffects: Decodable {
            let status: ExecuteStatus?
        }

        struct ExecuteStatus: Decodable {
            let status: String?
            let error: String?
        }
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.suiChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.suiChainName)
    }

    static func filteredRPCEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else {
            return rpcBaseURLs
        }
        return rpcBaseURLs.filter { endpoint in
            switch endpoint {
            case "https://fullnode.mainnet.sui.io:443":
                return providerIDs.contains("sui-mainnet")
            case "https://sui-rpc.publicnode.com":
                return providerIDs.contains("sui-publicnode")
            case "https://sui-mainnet-endpoint.blockvision.org":
                return providerIDs.contains("sui-blockvision")
            case "https://sui.blockpi.network/v1/rpc/public":
                return providerIDs.contains("sui-blockpi")
            case "https://rpc-mainnet.suiscan.xyz":
                return providerIDs.contains("sui-suiscan")
            default:
                return false
            }
        }
    }

    static func orderedRPCEndpoints(providerIDs: Set<String>? = nil) -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredRPCEndpoints(providerIDs: providerIDs)
        )
        return ordered.compactMap(URL.init(string:))
    }
}
