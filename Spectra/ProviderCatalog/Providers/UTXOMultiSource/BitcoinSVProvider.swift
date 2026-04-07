import Foundation

enum BitcoinSVProvider {
    enum ProviderID: String, CaseIterable {
        case whatsonchain
        case blockchair
    }

    static let whatsonchainBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainBaseURL
    static let whatsonchainChainInfoURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainChainInfoURL
    static let blockchairBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairBaseURL

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.bitcoinSVChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.bitcoinSVChainName)
    }

    struct WhatsOnChainBalanceResponse: Decodable {
        let confirmed: Int64?
        let unconfirmed: Int64?
    }

    struct WhatsOnChainHistoryEntry: Decodable {
        let txHash: String
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case height
        }
    }

    struct WhatsOnChainUnspentEntry: Decodable {
        let txHash: String
        let outputIndex: Int
        let value: UInt64

        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case outputIndex = "tx_pos"
            case value
        }
    }

    struct WhatsOnChainTransaction: Decodable {
        struct Input: Decodable {
            struct ScriptSignature: Decodable {
                let asm: String?
                let hex: String?
            }

            let txid: String?
            let vout: Int?
            let scriptSig: ScriptSignature?
            let sequence: UInt64?
            let address: String?
            let value: Double?
        }

        struct Output: Decodable {
            struct ScriptPubKey: Decodable {
                let addresses: [String]?
                let address: String?
            }

            let value: Double?
            let n: Int?
            let scriptPubKey: ScriptPubKey?
        }

        let txid: String
        let confirmations: Int?
        let blockheight: Int?
        let time: TimeInterval?
        let blocktime: TimeInterval?
        let vin: [Input]
        let vout: [Output]
    }

    struct BlockchairAddressResponse: Decodable {
        let data: [String: AddressDashboard]
    }

    struct AddressDashboard: Decodable {
        struct AddressDetails: Decodable {
            let balance: Int64?
            let transactionCount: Int?

            enum CodingKeys: String, CodingKey {
                case balance
                case transactionCount = "transaction_count"
            }
        }

        struct UTXOEntry: Decodable {
            let transactionHash: String
            let index: Int
            let value: UInt64

            enum CodingKeys: String, CodingKey {
                case transactionHash = "transaction_hash"
                case index
                case value
            }
        }

        let address: AddressDetails
        let transactions: [String]
        let utxo: [UTXOEntry]?
    }

    struct BlockchairTransactionResponse: Decodable {
        let data: [String: TransactionDashboard]
    }

    struct TransactionDashboard: Decodable {
        struct TransactionDetails: Decodable {
            let blockID: Int?
            let hash: String
            let time: String?

            enum CodingKeys: String, CodingKey {
                case blockID = "block_id"
                case hash
                case time
            }
        }

        struct Input: Decodable {
            let recipient: String?
            let value: Int64?
        }

        struct Output: Decodable {
            let recipient: String?
            let value: Int64?
        }

        let transaction: TransactionDetails
        let inputs: [Input]
        let outputs: [Output]
    }

    static func blockchairAddressDashboardURL(address: String, limit: Int, offset: Int) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(blockchairBaseURL)/dashboards/address/\(encoded)?limit=\(max(1, limit)),\(max(1, limit))&offset=\(max(0, offset)),0")
    }

    static func blockchairTransactionURL(txid: String) -> URL? {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(blockchairBaseURL)/dashboards/transaction/\(encoded)")
    }

    static func whatsOnChainURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: whatsonchainBaseURL + path) else {
            return nil
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    static func runWithFallback<T>(
        candidates: [ProviderID],
        operation: @escaping (ProviderID) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                lastError = error
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
