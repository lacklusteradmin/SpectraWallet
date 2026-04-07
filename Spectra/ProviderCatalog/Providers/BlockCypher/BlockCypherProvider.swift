import Foundation

enum BlockCypherProvider {
    enum Network {
        case dogecoinMainnet
        case dogecoinTestnet
        case litecoinMainnet

        var baseURL: String {
            switch self {
            case .dogecoinMainnet:
                return ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL
            case .dogecoinTestnet:
                return ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherTestnetBaseURL
            case .litecoinMainnet:
                return ChainBackendRegistry.LitecoinRuntimeEndpoints.blockcypherBaseURL
            }
        }
    }

    static func url(path: String, network: Network) -> URL? {
        URL(string: network.baseURL + path)
    }

    struct AddressRefsResponse: Decodable {
        struct TransactionReference: Decodable {
            let txHash: String
            let txOutputIndex: Int?
            let value: UInt64?

            enum CodingKeys: String, CodingKey {
                case txHash = "tx_hash"
                case txOutputIndex = "tx_output_n"
                case value
            }
        }

        let txrefs: [TransactionReference]?
        let unconfirmedTxrefs: [TransactionReference]?

        enum CodingKeys: String, CodingKey {
            case txrefs
            case unconfirmedTxrefs = "unconfirmed_txrefs"
        }
    }

    struct AddressBalanceResponse: Decodable {
        let finalBalance: Int64?
        let balance: Int64?

        enum CodingKeys: String, CodingKey {
            case finalBalance = "final_balance"
            case balance
        }
    }

    struct AddressStatsResponse: Decodable {
        let finalBalance: Int64?
        let balance: Int64?
        let finalNTx: Int?
        let nTx: Int?

        enum CodingKeys: String, CodingKey {
            case finalBalance = "final_balance"
            case balance
            case finalNTx = "final_n_tx"
            case nTx = "n_tx"
        }
    }

    struct NetworkFeesResponse: Decodable {
        let height: Int?
        let highFeePerKB: Double?
        let mediumFeePerKB: Double?
        let lowFeePerKB: Double?

        enum CodingKeys: String, CodingKey {
            case height
            case highFeePerKB = "high_fee_per_kb"
            case mediumFeePerKB = "medium_fee_per_kb"
            case lowFeePerKB = "low_fee_per_kb"
        }
    }

    struct TransactionHashResponse: Decodable {
        let hash: String?
    }

    struct TransactionStatusResponse: Decodable {
        let confirmations: Int?
        let blockHeight: Int?

        enum CodingKeys: String, CodingKey {
            case confirmations
            case blockHeight = "block_height"
        }
    }

    struct TransactionDetailResponse: Decodable {
        struct Input: Decodable {
            let addresses: [String]?
            let outputValue: Int64?
            let value: Int64?

            enum CodingKeys: String, CodingKey {
                case addresses
                case outputValue = "output_value"
                case value
            }
        }

        struct Output: Decodable {
            let addresses: [String]?
            let value: Int64?
        }

        let hash: String?
        let received: String?
        let blockHeight: Int?
        let confirmations: Int?
        let inputs: [Input]?
        let outputs: [Output]?

        enum CodingKeys: String, CodingKey {
            case hash
            case received
            case blockHeight = "block_height"
            case confirmations
            case inputs
            case outputs
        }
    }

    struct AddressTransactionsResponse: Decodable {
        let txs: [TransactionDetailResponse]?
    }

    struct BroadcastResponse: Decodable {
        struct Transaction: Decodable {
            let hash: String?
        }

        let tx: Transaction?
    }
}
