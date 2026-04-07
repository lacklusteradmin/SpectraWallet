import Foundation

enum AptosProvider {
    static let endpoints = ChainBackendRegistry.AptosRuntimeEndpoints.rpcURLs

    struct CoinStoreResource: Decodable {
        let data: CoinStoreData?

        struct CoinStoreData: Decodable {
            let coin: CoinValue?
        }

        struct CoinValue: Decodable {
            let value: String?
        }
    }

    struct AccountResource: Decodable {
        let type: String?
        let data: CoinStoreResource.CoinStoreData?
    }

    struct TransactionItem: Decodable {
        let type: String?
        let hash: String?
        let success: Bool?
        let sender: String?
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let function: String?
            let arguments: [String]?
        }
    }

    struct ViewFunctionRequest: Encodable {
        let function: String
        let typeArguments: [String]
        let arguments: [String]

        enum CodingKeys: String, CodingKey {
            case function
            case typeArguments = "type_arguments"
            case arguments
        }
    }

    struct SubmitResponse: Decodable {
        let hash: String?
    }

    struct TransactionLookupResponse: Decodable {
        let hash: String?
        let success: Bool?
        let vmStatus: String?

        enum CodingKeys: String, CodingKey {
            case hash
            case success
            case vmStatus = "vm_status"
        }
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.aptosChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.aptosChainName)
    }
}
