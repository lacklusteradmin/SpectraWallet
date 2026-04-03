import Foundation

enum XRPProvider {
    static let xrpJSONRPCEndpoints = ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs
    static let endpointReliabilityNamespace = "xrp.rpc"
    static let xrpScanAccountBases = ChainBackendRegistry.XRPRuntimeEndpoints.accountHistoryBases
    static let rippleEpochOffset: TimeInterval = 946_684_800

    enum ProviderID: String, CaseIterable {
        case xrpscan
        case xrplCluster
        case rippleS1
        case rippleS2

        var rpcEndpoint: URL {
            switch self {
            case .xrpscan, .rippleS1:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[0]
            case .xrplCluster:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[2]
            case .rippleS2:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[1]
            }
        }
    }

    struct AccountResponse: Decodable {
        let xrpBalance: String?

        enum CodingKeys: String, CodingKey {
            case xrpBalance = "xrpBalance"
        }
    }

    struct TransactionRow: Decodable {
        let hash: String?
        let transactionType: String?
        let destination: String?
        let account: String?
        let deliveredAmount: DeliveredAmount?
        let date: String?
        let validated: Bool?

        enum CodingKeys: String, CodingKey {
            case hash
            case transactionType = "TransactionType"
            case destination = "Destination"
            case account = "Account"
            case deliveredAmount = "delivered_amount"
            case date
            case validated
        }
    }

    struct TransactionEnvelope: Decodable {
        let transactions: [TransactionRow]?
        let data: [TransactionRow]?
        let rows: [TransactionRow]?
    }

    struct XRPLRPCErrorResponse: Decodable {
        let error: String?
        let error_message: String?
    }

    struct RPCEnvelope<ResultType: Decodable>: Decodable {
        let result: ResultType?
        let error: String?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case result
            case error
            case errorMessage = "error_message"
        }
    }

    struct FeeResult: Decodable {
        let drops: FeeDrops?

        struct FeeDrops: Decodable {
            let openLedgerFee: String?
            let minimumFee: String?

            enum CodingKeys: String, CodingKey {
                case openLedgerFee = "open_ledger_fee"
                case minimumFee = "minimum_fee"
            }
        }
    }

    struct AccountInfoResult: Decodable {
        let accountData: AccountData?
        let ledgerCurrentIndex: Int64?

        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
        }

        struct AccountData: Decodable {
            let sequence: Int64?

            enum CodingKeys: String, CodingKey {
                case sequence = "Sequence"
            }
        }
    }

    struct SubmitResult: Decodable {
        let engineResult: String?
        let engineResultMessage: String?
        let txJSON: SubmitTxJSON?

        enum CodingKeys: String, CodingKey {
            case engineResult = "engine_result"
            case engineResultMessage = "engine_result_message"
            case txJSON = "tx_json"
        }

        struct SubmitTxJSON: Decodable {
            let hash: String?
        }
    }

    enum DeliveredAmount: Decodable {
        case string(String)
        case object([String: String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let value = try? container.decode([String: String].self) {
                self = .object(value)
                return
            }
            throw DecodingError.typeMismatch(
                DeliveredAmount.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported delivered_amount format")
            )
        }
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.xrpChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.xrpChainName)
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
