import Foundation

enum StellarProvider {
    static let horizonEndpoints = ChainBackendRegistry.StellarRuntimeEndpoints.horizonBaseURLs

    struct AccountResponse: Decodable {
        struct BalanceEntry: Decodable {
            let balance: String?
            let assetType: String?

            enum CodingKeys: String, CodingKey {
                case balance
                case assetType = "asset_type"
            }
        }

        let sequence: String?
        let balances: [BalanceEntry]
    }

    struct FeeStatsResponse: Decodable {
        struct FeeCharged: Decodable {
            let p50: String?
        }

        let lastLedgerBaseFee: String?
        let feeCharged: FeeCharged?

        enum CodingKeys: String, CodingKey {
            case lastLedgerBaseFee = "last_ledger_base_fee"
            case feeCharged = "fee_charged"
        }
    }

    struct SubmitTransactionResponse: Decodable {
        let hash: String?
    }

    struct PaymentsEnvelope: Decodable {
        struct Embedded: Decodable {
            let records: [PaymentRecord]
        }

        let embedded: Embedded

        enum CodingKeys: String, CodingKey {
            case embedded = "_embedded"
        }
    }

    struct PaymentsEnvelopeVariant: Decodable {
        let records: [PaymentRecord]?
        let data: [PaymentRecord]?
    }

    struct PaymentRecord: Decodable {
        let id: String?
        let type: String?
        let assetType: String?
        let from: String?
        let to: String?
        let account: String?
        let amount: String?
        let createdAt: String?
        let transactionHash: String?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case assetType = "asset_type"
            case from
            case to
            case account
            case amount
            case createdAt = "created_at"
            case transactionHash = "transaction_hash"
        }
    }

    struct TransactionLookupResponse: Decodable {
        let successful: Bool?
        let hash: String?
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.stellarChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.stellarChainName)
    }
}
