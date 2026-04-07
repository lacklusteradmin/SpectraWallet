import Foundation

enum ICPProvider {
    static let endpointReliabilityNamespace = "icp.rosetta"
    static let rosettaEndpoints = ChainBackendRegistry.ICPRuntimeEndpoints.rosettaBaseURLs
    static let networkIdentifier = NetworkIdentifier(
        blockchain: "Internet Computer",
        network: "00000000000000020101"
    )

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.icpChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.icpChainName)
    }

    static func orderedRosettaEndpoints() -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: rosettaEndpoints
        )
    }

    struct NetworkIdentifier: Codable {
        let blockchain: String
        let network: String
    }

    struct AccountIdentifier: Codable {
        let address: String
    }

    struct CurrencyAmount: Codable {
        let value: String
    }

    struct AccountBalanceRequest: Codable {
        let networkIdentifier: NetworkIdentifier
        let accountIdentifier: AccountIdentifier

        enum CodingKeys: String, CodingKey {
            case networkIdentifier = "network_identifier"
            case accountIdentifier = "account_identifier"
        }
    }

    struct AccountBalanceResponse: Codable {
        let balances: [CurrencyAmount]
    }

    struct SearchTransactionsRequest: Codable {
        let networkIdentifier: NetworkIdentifier
        let accountIdentifier: AccountIdentifier?
        let transactionIdentifier: TransactionIdentifier?
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case networkIdentifier = "network_identifier"
            case accountIdentifier = "account_identifier"
            case transactionIdentifier = "transaction_identifier"
            case limit
        }
    }

    struct SearchTransactionsResponse: Codable {
        let transactions: [SearchTransactionEntry]
    }

    struct SearchTransactionEntry: Codable {
        let blockIdentifier: BlockIdentifier
        let transaction: RosettaTransaction

        enum CodingKeys: String, CodingKey {
            case blockIdentifier = "block_identifier"
            case transaction
        }
    }

    struct BlockIdentifier: Codable {
        let index: Int64?
        let hash: String?
    }

    struct RosettaTransaction: Codable {
        let transactionIdentifier: TransactionIdentifier
        let operations: [RosettaOperation]
        let metadata: RosettaTransactionMetadata?

        enum CodingKeys: String, CodingKey {
            case transactionIdentifier = "transaction_identifier"
            case operations
            case metadata
        }
    }

    struct TransactionIdentifier: Codable {
        let hash: String?
    }

    struct RosettaOperation: Codable {
        let type: String?
        let status: String?
        let account: AccountIdentifier?
        let amount: CurrencyAmount?
    }

    struct RosettaTransactionMetadata: Codable {
        let timestamp: Int64?
    }

    struct ConstructionSubmitRequest: Codable {
        let networkIdentifier: NetworkIdentifier
        let signedTransaction: String

        enum CodingKeys: String, CodingKey {
            case networkIdentifier = "network_identifier"
            case signedTransaction = "signed_transaction"
        }
    }

    struct ConstructionMetadataOptions: Codable {
        let requestTypes: [String]

        enum CodingKeys: String, CodingKey {
            case requestTypes = "request_types"
        }
    }

    struct ConstructionMetadataRequest: Codable {
        let networkIdentifier: NetworkIdentifier
        let options: ConstructionMetadataOptions
        let publicKeys: [RosettaPublicKey]?

        enum CodingKeys: String, CodingKey {
            case networkIdentifier = "network_identifier"
            case options
            case publicKeys = "public_keys"
        }
    }

    struct ConstructionMetadataResponse: Codable {
        let suggestedFee: [CurrencyAmount]?

        enum CodingKeys: String, CodingKey {
            case suggestedFee = "suggested_fee"
        }
    }

    struct RosettaPublicKey: Codable {
        let hexBytes: String
        let curveType: String

        enum CodingKeys: String, CodingKey {
            case hexBytes = "hex_bytes"
            case curveType = "curve_type"
        }
    }

    struct ConstructionSubmitResponse: Codable {
        let transactionIdentifier: TransactionIdentifier?

        enum CodingKeys: String, CodingKey {
            case transactionIdentifier = "transaction_identifier"
        }
    }

    struct RosettaErrorResponse: Codable {
        struct Details: Codable {
            let errorMessage: String?

            enum CodingKeys: String, CodingKey {
                case errorMessage = "error_message"
            }
        }

        let message: String?
        let details: Details?
    }
}
