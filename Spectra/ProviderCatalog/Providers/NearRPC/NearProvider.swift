import Foundation

enum NearProvider {
    static let endpointReliabilityNamespace = "near.rpc"
    static let rpcEndpoints = ChainBackendRegistry.NearRuntimeEndpoints.rpcBaseURLs
    static let historyEndpoints = ChainBackendRegistry.NearRuntimeEndpoints.historyBaseURLs

    struct RPCEnvelope<ResultType: Decodable>: Decodable {
        let result: ResultType?
        let error: RPCError?
    }

    struct RPCError: Decodable {
        let code: Int?
        let message: String?
        let name: String?
        let cause: RPCCause?
    }

    struct RPCCause: Decodable {
        let name: String?
        let info: String?
    }

    struct ViewAccountResult: Decodable {
        let amount: String?
    }

    struct CallFunctionResult: Decodable {
        let result: [UInt8]?
    }

    struct AccessKeyResult: Decodable {
        let nonce: UInt64
        let blockHash: String

        enum CodingKeys: String, CodingKey {
            case nonce
            case blockHash = "block_hash"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let nonce = try? container.decode(UInt64.self, forKey: .nonce) {
                self.nonce = nonce
            } else if let nonceText = try? container.decode(String.self, forKey: .nonce),
                      let nonce = UInt64(nonceText) {
                self.nonce = nonce
            } else {
                throw DecodingError.typeMismatch(
                    UInt64.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing NEAR nonce")
                )
            }
            blockHash = try container.decode(String.self, forKey: .blockHash)
        }
    }

    struct GasPriceResult: Decodable {
        let gasPrice: String

        enum CodingKeys: String, CodingKey {
            case gasPrice = "gas_price"
        }
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.nearChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.nearChainName)
    }

    static func orderedRPCEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredRPCEndpoints(providerIDs: providerIDs)
        )
    }

    static func filteredRPCEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else { return rpcEndpoints }
        return rpcEndpoints.filter { endpoint in
            switch endpoint {
            case "https://rpc.mainnet.near.org":
                return providerIDs.contains("near-mainnet-rpc")
            case "https://free.rpc.fastnear.com":
                return providerIDs.contains("fastnear-rpc")
            case "https://near.lava.build":
                return providerIDs.contains("lava-near-rpc")
            default:
                return false
            }
        }
    }
}
