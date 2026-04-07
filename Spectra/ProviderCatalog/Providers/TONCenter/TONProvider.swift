import Foundation

enum TONProvider {
    static let endpointReliabilityNamespace = "ton.api.v2"
    static let apiV2BaseURLs = ChainBackendRegistry.TONRuntimeEndpoints.apiV2BaseURLs
    static let apiV3BaseURLs = ChainBackendRegistry.TONRuntimeEndpoints.apiV3BaseURLs

    struct WalletInformationEnvelope: Decodable {
        let ok: Bool?
        let result: WalletInformationResult?
        let error: String?
    }

    struct WalletInformationResult: Decodable {
        let balance: String?
        let seqno: UInt32?
    }

    struct TransactionsEnvelope: Decodable {
        let ok: Bool?
        let result: [TransactionEntry]?
        let error: String?
    }

    struct JettonWalletsEnvelope: Decodable {
        let jettonWallets: [JettonWalletEntry]?

        enum CodingKeys: String, CodingKey {
            case jettonWallets = "jetton_wallets"
        }
    }

    struct JettonWalletEntry: Decodable {
        let balance: String?
        let address: String?
        let owner: AddressEnvelope?
        let jetton: AddressEnvelope?

        struct AddressEnvelope: Decodable {
            let address: String?
        }
    }

    struct TransactionEntry: Decodable {
        let utime: Int?
        let transactionID: TransactionID?
        let inMsg: Message?
        let outMsgs: [Message]?

        enum CodingKeys: String, CodingKey {
            case utime
            case transactionID = "transaction_id"
            case inMsg = "in_msg"
            case outMsgs = "out_msgs"
        }
    }

    struct TransactionID: Decodable {
        let hash: String?
    }

    struct Message: Decodable {
        let source: String?
        let destination: String?
        let value: String?
    }

    struct SendBocEnvelope: Decodable {
        let ok: Bool?
        let result: SendBocResult?
        let error: String?
    }

    struct SendBocResult: Decodable {
        let hash: String?
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.tonChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.tonChainName)
    }

    static func orderedAPIv2Endpoints() -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: apiV2BaseURLs
        )
        return ordered.compactMap(URL.init(string:))
    }
}
