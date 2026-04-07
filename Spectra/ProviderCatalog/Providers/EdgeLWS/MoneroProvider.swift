import Foundation

enum MoneroProvider {
    struct TrustedBackend: Identifiable, Hashable {
        let id: String
        let displayName: String
        let baseURL: String
    }

    static let backendBaseURLDefaultsKey = "monero.backend.baseURL"
    static let backendAPIKeyDefaultsKey = "monero.backend.apiKey"
    static let defaultBackendID = "edge_lws_public"
    static let defaultPublicBackend = TrustedBackend(
        id: defaultBackendID,
        displayName: "Edge Monero LWS (Default)",
        baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[0]
    )
    static let trustedBackends: [TrustedBackend] = [
        defaultPublicBackend,
        TrustedBackend(
            id: "edge_lws_public_2",
            displayName: "Edge Monero LWS (Fallback 1)",
            baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[1]
        ),
        TrustedBackend(
            id: "edge_lws_public_3",
            displayName: "Edge Monero LWS (Fallback 2)",
            baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[2]
        )
    ]

    struct BalanceResponse: Decodable {
        let balanceXMR: Double
    }

    struct HistoryResponse: Decodable {
        let transactions: [HistoryItem]
    }

    struct HistoryItem: Decodable {
        let txid: String
        let direction: String
        let amountXMR: Double
        let counterpartyAddress: String?
        let timestamp: TimeInterval
        let status: String?
    }

    struct PreviewRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }

    struct PreviewResponse: Decodable {
        let estimatedFeeXMR: Double
        let priority: String?
    }

    struct SendRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }

    struct SendResponse: Decodable {
        let txid: String
        let feeXMR: Double?
    }
}
