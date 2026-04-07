import Foundation

enum EVMExplorerProvider {
    struct ENSIdeasResolveResponse: Decodable {
        let address: String?
    }

    struct EtherscanTokenTransferResponse: Decodable {
        let status: String?
        let message: String?
        let result: [EtherscanTokenTransferItem]
        let resultText: String?

        enum CodingKeys: String, CodingKey {
            case status
            case message
            case result
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            if let items = try? container.decode([EtherscanTokenTransferItem].self, forKey: .result) {
                result = items
                resultText = nil
            } else if let text = try? container.decode(String.self, forKey: .result) {
                result = []
                resultText = text
            } else {
                result = []
                resultText = nil
            }
        }
    }

    struct EtherscanTokenTransferItem: Decodable {
        let blockNumber: String
        let timeStamp: String
        let hash: String
        let from: String
        let to: String
        let contractAddress: String
        let tokenName: String
        let tokenSymbol: String
        let tokenDecimal: String
        let value: String
    }

    struct EtherscanNormalTransactionResponse: Decodable {
        let status: String?
        let message: String?
        let result: [EtherscanNormalTransactionItem]
        let resultText: String?

        enum CodingKeys: String, CodingKey {
            case status
            case message
            case result
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            if let items = try? container.decode([EtherscanNormalTransactionItem].self, forKey: .result) {
                result = items
                resultText = nil
            } else if let text = try? container.decode(String.self, forKey: .result) {
                result = []
                resultText = text
            } else {
                result = []
                resultText = nil
            }
        }
    }

    struct EtherscanNormalTransactionItem: Decodable {
        let blockNumber: String
        let timeStamp: String
        let hash: String
        let from: String
        let to: String
        let value: String
        let isError: String?
        let txreceipt_status: String?
    }

    struct BlockscoutTokenTransfersResponse: Decodable {
        let items: [BlockscoutTokenTransferItem]
    }

    struct BlockscoutNormalTransactionsResponse: Decodable {
        let items: [BlockscoutNormalTransactionItem]
    }

    struct BlockscoutNormalTransactionItem: Decodable {
        let hash: String?
        let timestamp: String?
        let from: BlockscoutAddress?
        let to: BlockscoutAddress?
        let value: String?
        let result: String?
        let block: BlockscoutBlock?
    }

    struct BlockscoutTokenTransferItem: Decodable {
        let transaction_hash: String?
        let block_number: Int?
        let timestamp: String?
        let from: BlockscoutAddress?
        let to: BlockscoutAddress?
        let token: BlockscoutToken?
        let total: BlockscoutAmount?
    }

    struct BlockscoutAddress: Decodable {
        let hash: String?
    }

    struct BlockscoutBlock: Decodable {
        let height: Int?
    }

    struct BlockscoutToken: Decodable {
        let address: String?
        let symbol: String?
        let name: String?
        let decimals: String?
    }

    struct BlockscoutAmount: Decodable {
        let value: String?
    }

    struct EthplorerErrorResponse: Decodable {
        let error: EthplorerErrorBody?
    }

    struct EthplorerErrorBody: Decodable {
        let code: Int?
        let message: String?
    }

    struct EthplorerAddressHistoryResponse: Decodable {
        let operations: [EthplorerOperation]?
    }

    struct EthplorerOperation: Decodable {
        let timestamp: TimeInterval?
        let transactionHash: String?
        let from: String?
        let to: String?
        let value: String?
        let blockNumber: Int?
        let tokenInfo: EthplorerTokenInfo?
    }

    struct EthplorerTokenInfo: Decodable {
        let address: String?
        let symbol: String?
        let name: String?
        let decimals: String?
    }

    static func etherscanAPIURL(for chain: EVMChainContext) -> URL? {
        if chain.isEthereumFamily {
            return URL(string: "https://api.etherscan.io/v2/api")
        }
        return ChainBackendRegistry.EVMExplorerRegistry.etherscanStyleAPIURL(for: chain.displayName)
    }

    static func blockscoutTokenTransfersURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        page: Int,
        pageSize: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.blockscoutTokenTransfersURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            page: page,
            pageSize: pageSize
        )
    }

    static func blockscoutAccountAPIURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        action: String,
        page: Int,
        pageSize: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.blockscoutAccountAPIURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            action: action,
            page: page,
            pageSize: pageSize
        )
    }

    static func ethplorerHistoryURL(
        for chain: EVMChainContext,
        normalizedAddress: String,
        requestedLimit: Int
    ) -> URL? {
        ChainBackendRegistry.EVMExplorerRegistry.ethplorerHistoryURL(
            for: chain.displayName,
            normalizedAddress: normalizedAddress,
            requestedLimit: requestedLimit
        )
    }
}
