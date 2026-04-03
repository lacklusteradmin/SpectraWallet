import Foundation

enum EthereumRPCProvider {
    struct JSONRPCRequest<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: Params
    }

    struct JSONRPCResponse: Decodable {
        let result: String?
        let error: JSONRPCError?
    }

    struct JSONRPCDecodedResponse<Result: Decodable>: Decodable {
        let result: Result?
        let error: JSONRPCError?
    }

    struct TransactionReceiptJSONRPCResponse: Decodable {
        let result: TransactionReceiptPayload?
        let error: JSONRPCError?
    }

    struct TransactionReceiptPayload: Decodable {
        let transactionHash: String
        let blockNumber: String?
        let status: String?
        let gasUsed: String?
        let effectiveGasPrice: String?
    }

    struct TransactionPayload: Decodable {
        let nonce: String?
    }

    struct TransactionByHashPayload: Decodable {
        let hash: String?
        let blockNumber: String?
        let from: String
        let to: String?
        let value: String
    }

    struct BlockPayload: Decodable {
        let timestamp: String
    }

    struct TransactionReceiptWithLogsPayload: Decodable {
        let transactionHash: String
        let blockNumber: String?
        let status: String?
        let logs: [LogPayload]
    }

    struct LogPayload: Decodable {
        let address: String
        let topics: [String]
        let data: String
        let logIndex: String?
    }

    struct JSONRPCError: Decodable {
        let code: Int
        let message: String
    }

    struct CallRequest: Encodable {
        let to: String
        let data: String
    }

    struct EstimateGasRequest: Encodable {
        let from: String
        let to: String
        let value: String
        let data: String?
    }

    struct BlockByNumberParameters: Encodable {
        let blockNumber: String
        let includeTransactions: Bool

        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(blockNumber)
            try container.encode(includeTransactions)
        }
    }

    static func makeRequest<Params: Encodable>(
        method: String,
        params: Params,
        requestID: Int,
        endpoint: URL
    ) throws -> URLRequest {
        let payload = JSONRPCRequest(id: requestID, method: method, params: params)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}
