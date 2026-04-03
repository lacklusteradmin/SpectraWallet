import Foundation

enum BitcoinCashProvider {
    enum ProviderID: String, CaseIterable {
        case blockchair
        case actorforth
    }

    static let blockchairBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairBaseURL
    static let actorforthBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.actorforthBaseURL

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.bitcoinCashChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.bitcoinCashChainName)
    }

    struct BlockchairAddressResponse: Decodable {
        struct Context: Decodable {
            let code: Int?
        }

        let data: [String: AddressDashboard]
        let context: Context?
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

    struct ActorForthEnvelope<Payload: Decodable>: Decodable {
        let status: String?
        let message: String?
        let data: Payload?
    }

    struct ActorForthAddressDetails: Decodable {
        let balanceSat: Int64?
        let txApperances: Int?
        let transactions: [String]?

        enum CodingKeys: String, CodingKey {
            case balanceSat
            case txApperances
            case transactions
        }
    }

    struct ActorForthUTXOPayload: Decodable {
        struct Entry: Decodable {
            let txid: String?
            let vout: Int?
            let satoshis: UInt64?
        }

        let utxos: [Entry]?
    }

    struct ActorForthTransactionPayload: Decodable {
        struct Input: Decodable {
            let legacyAddress: String?
            let cashAddress: String?
            let valueSat: Int64?

            enum CodingKeys: String, CodingKey {
                case legacyAddress
                case cashAddress
                case valueSat
            }
        }

        struct Output: Decodable {
            let legacyAddress: String?
            let cashAddress: String?
            let value: String?
            let valueSat: Int64?

            enum CodingKeys: String, CodingKey {
                case legacyAddress
                case cashAddress
                case value
                case valueSat
            }
        }

        let txid: String?
        let confirmations: Int?
        let blockheight: Int?
        let time: TimeInterval?
        let vin: [Input]?
        let vout: [Output]?
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

    static func actorForthAddressDetailsURL(address: String) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(actorforthBaseURL)/address/details/\(encoded)")
    }

    static func actorForthUTXOsURL(address: String) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(actorforthBaseURL)/address/utxo/\(encoded)")
    }

    static func actorForthTransactionURL(txid: String) -> URL? {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(actorforthBaseURL)/transaction/details/\(encoded)")
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
