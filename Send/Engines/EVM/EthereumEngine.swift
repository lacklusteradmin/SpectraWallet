import Foundation
import BigInt
import WalletCore

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidSeedPhrase
    case missingRPCEndpoint
    case invalidRPCEndpoint
    case invalidResponse
    case invalidHexQuantity
    case unsupportedNetwork
    case rpcFailure(String)
    case integrationNotImplemented

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Ethereum")
        case .invalidSeedPhrase:
            return AppLocalization.string("The Ethereum seed phrase could not derive a valid account.")
        case .missingRPCEndpoint:
            return AppLocalization.string("An Ethereum RPC endpoint is required for live chain access.")
        case .invalidRPCEndpoint:
            return AppLocalization.string("The Ethereum RPC endpoint is not valid.")
        case .invalidResponse:
            return AppLocalization.string("The Ethereum RPC response was invalid.")
        case .invalidHexQuantity:
            return AppLocalization.string("The Ethereum RPC returned an invalid balance.")
        case .unsupportedNetwork:
            return AppLocalization.string("The configured EVM RPC endpoint does not match the selected chain.")
        case let .rpcFailure(message):
            return AppLocalization.string(message)
        case .integrationNotImplemented:
            return AppLocalization.string("Ethereum token integration has not been implemented yet.")
        }
    }
}

struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}

struct EthereumAccountSnapshot: Equatable {
    let address: String
    let chainID: Int
    let nativeBalanceWei: Decimal
    let blockNumber: Int?
}

struct EthereumTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let balance: Decimal
    let decimals: Int
}

struct EthereumTokenTransferSnapshot: Equatable {
    let contractAddress: String
    let tokenName: String
    let symbol: String
    let decimals: Int
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let transactionHash: String
    let blockNumber: Int
    let logIndex: Int
    let timestamp: Date?
}

struct EthereumNativeTransferSnapshot: Equatable {
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let transactionHash: String
    let blockNumber: Int
    let timestamp: Date?
}

struct EthereumTokenTransferHistoryDiagnostics: Equatable {
    let address: String
    let rpcTransferCount: Int
    let rpcError: String?
    let blockscoutTransferCount: Int
    let blockscoutError: String?
    let etherscanTransferCount: Int
    let etherscanError: String?
    let ethplorerTransferCount: Int
    let ethplorerError: String?
    let sourceUsed: String
    let transferScanCount: Int
    let decodedTransferCount: Int
    let unsupportedTransferDropCount: Int
    let decodingCompletenessRatio: Double

    init(
        address: String,
        rpcTransferCount: Int,
        rpcError: String?,
        blockscoutTransferCount: Int,
        blockscoutError: String?,
        etherscanTransferCount: Int,
        etherscanError: String?,
        ethplorerTransferCount: Int,
        ethplorerError: String?,
        sourceUsed: String,
        transferScanCount: Int = 0,
        decodedTransferCount: Int = 0,
        unsupportedTransferDropCount: Int = 0,
        decodingCompletenessRatio: Double = 0
    ) {
        self.address = address
        self.rpcTransferCount = rpcTransferCount
        self.rpcError = rpcError
        self.blockscoutTransferCount = blockscoutTransferCount
        self.blockscoutError = blockscoutError
        self.etherscanTransferCount = etherscanTransferCount
        self.etherscanError = etherscanError
        self.ethplorerTransferCount = ethplorerTransferCount
        self.ethplorerError = ethplorerError
        self.sourceUsed = sourceUsed
        self.transferScanCount = transferScanCount
        self.decodedTransferCount = decodedTransferCount
        self.unsupportedTransferDropCount = unsupportedTransferDropCount
        self.decodingCompletenessRatio = decodingCompletenessRatio
    }
}

struct EthereumTransferDecodingStats: Equatable {
    let scannedTransfers: Int
    let decodedSupportedTransfers: Int
    let droppedUnsupportedTransfers: Int

    static let zero = EthereumTransferDecodingStats(
        scannedTransfers: 0,
        decodedSupportedTransfers: 0,
        droppedUnsupportedTransfers: 0
    )
}

struct EthereumSendPreview: Equatable {
    let nonce: Int
    let gasLimit: Int
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
    let estimatedNetworkFeeETH: Double
    let spendableBalance: Double?
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double?
}

struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}

struct EthereumRPCHealthSnapshot: Equatable {
    let chainID: Int
    let latestBlockNumber: Int
}

struct EthereumSupportedToken {
    let name: String
    let symbol: String
    let contractAddress: String
    let decimals: Int
    let marketDataID: String
    let coinGeckoID: String

    init(
        name: String,
        symbol: String,
        contractAddress: String,
        decimals: Int,
        marketDataID: String,
        coinGeckoID: String
    ) {
        self.name = name
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.decimals = decimals
        self.marketDataID = marketDataID
        self.coinGeckoID = coinGeckoID
    }

    init(registryEntry: ChainTokenRegistryEntry) {
        self.name = registryEntry.name
        self.symbol = registryEntry.symbol
        self.contractAddress = registryEntry.contractAddress
        self.decimals = registryEntry.decimals
        self.marketDataID = registryEntry.marketDataID
        self.coinGeckoID = registryEntry.coinGeckoID
    }
}

enum EthereumNetworkMode: String, CaseIterable, Identifiable {
    case mainnet
    case sepolia
    case hoodi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .sepolia:
            return "Sepolia"
        case .hoodi:
            return "Hoodi"
        }
    }
}

enum EVMChainContext: Equatable {
    case ethereum
    case ethereumSepolia
    case ethereumHoodi
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid

    var displayName: String {
        switch self {
        case .ethereum:
            return "Ethereum"
        case .ethereumSepolia:
            return "Ethereum Sepolia"
        case .ethereumHoodi:
            return "Ethereum Hoodi"
        case .ethereumClassic:
            return "Ethereum Classic"
        case .arbitrum:
            return "Arbitrum"
        case .optimism:
            return "Optimism"
        case .bnb:
            return "BNB Chain"
        case .avalanche:
            return "Avalanche"
        case .hyperliquid:
            return "Hyperliquid"
        }
    }

    var tokenTrackingChain: TokenTrackingChain? {
        switch self {
        case .ethereum:
            return .ethereum
        case .ethereumSepolia, .ethereumHoodi:
            return nil
        case .ethereumClassic:
            return nil
        case .arbitrum:
            return .arbitrum
        case .optimism:
            return .optimism
        case .bnb:
            return .bnb
        case .avalanche:
            return .avalanche
        case .hyperliquid:
            return .hyperliquid
        }
    }

    var expectedChainID: Int {
        switch self {
        case .ethereum:
            return 1
        case .ethereumSepolia:
            return 11_155_111
        case .ethereumHoodi:
            return 560_048
        case .ethereumClassic:
            return 61
        case .arbitrum:
            return 42161
        case .optimism:
            return 10
        case .bnb:
            return 56
        case .avalanche:
            return 43114
        case .hyperliquid:
            return 999
        }
    }

    var defaultDerivationPath: String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
            return "m/44'/60'/0'/0/0"
        case .ethereumClassic:
            return "m/44'/61'/0'/0/0"
        }
    }

    func derivationPath(account: UInt32) -> String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
            return "m/44'/60'/\(account)'/0/0"
        case .ethereumClassic:
            return "m/44'/61'/\(account)'/0/0"
        }
    }

    var defaultRPCEndpoints: [String] {
        AppEndpointDirectory.evmRPCEndpoints(for: displayName)
    }

    var isEthereumFamily: Bool {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi:
            return true
        default:
            return false
        }
    }

    var isEthereumMainnet: Bool {
        self == .ethereum
    }
}

struct EthereumTransactionReceipt: Equatable {
    let transactionHash: String
    let blockNumber: Int?
    let status: String?
    let gasUsed: Decimal?
    let effectiveGasPriceWei: Decimal?

    var isConfirmed: Bool {
        blockNumber != nil
    }

    var isFailed: Bool {
        guard let status else { return false }
        return status.lowercased() == "0x0"
    }

    var gasUsedText: String? {
        guard let gasUsed else { return nil }
        return NSDecimalNumber(decimal: gasUsed).stringValue
    }

    var effectiveGasPriceGwei: Double? {
        guard let effectiveGasPriceWei else { return nil }
        let gweiValue = effectiveGasPriceWei / Decimal(1_000_000_000)
        return NSDecimalNumber(decimal: gweiValue).doubleValue
    }

    var networkFeeETH: Double? {
        guard let gasUsed, let effectiveGasPriceWei else { return nil }
        let feeWei = gasUsed * effectiveGasPriceWei
        let feeETH = feeWei / Decimal(string: "1000000000000000000")!
        return NSDecimalNumber(decimal: feeETH).doubleValue
    }
}

typealias EthereumJSONRPCRequest<Params: Encodable> = EthereumRPCProvider.JSONRPCRequest<Params>
typealias EthereumJSONRPCResponse = EthereumRPCProvider.JSONRPCResponse
typealias EthereumJSONRPCDecodedResponse<Result: Decodable> = EthereumRPCProvider.JSONRPCDecodedResponse<Result>
typealias EthereumTransactionReceiptJSONRPCResponse = EthereumRPCProvider.TransactionReceiptJSONRPCResponse
typealias EthereumTransactionReceiptPayload = EthereumRPCProvider.TransactionReceiptPayload
typealias EthereumTransactionPayload = EthereumRPCProvider.TransactionPayload
typealias EthereumTransactionByHashPayload = EthereumRPCProvider.TransactionByHashPayload
typealias EthereumBlockPayload = EthereumRPCProvider.BlockPayload
typealias EthereumTransactionReceiptWithLogsPayload = EthereumRPCProvider.TransactionReceiptWithLogsPayload
typealias EthereumLogPayload = EthereumRPCProvider.LogPayload

struct HyperliquidExplorerResolvedTransaction {
    let transactionHash: String
    let blockNumber: Int
    let fromAddress: String
    let toAddress: String
    let value: Decimal
    let timestamp: Date?
    let logs: [EthereumLogPayload]
}

typealias EthereumJSONRPCError = EthereumRPCProvider.JSONRPCError
typealias ENSIdeasResolveResponse = EVMExplorerProvider.ENSIdeasResolveResponse
typealias EthereumCallRequest = EthereumRPCProvider.CallRequest
typealias EthereumEstimateGasRequest = EthereumRPCProvider.EstimateGasRequest
typealias EthereumBlockByNumberParameters = EthereumRPCProvider.BlockByNumberParameters
typealias EtherscanTokenTransferResponse = EVMExplorerProvider.EtherscanTokenTransferResponse
typealias EtherscanTokenTransferItem = EVMExplorerProvider.EtherscanTokenTransferItem
typealias EtherscanNormalTransactionResponse = EVMExplorerProvider.EtherscanNormalTransactionResponse
typealias EtherscanNormalTransactionItem = EVMExplorerProvider.EtherscanNormalTransactionItem
typealias BlockscoutTokenTransfersResponse = EVMExplorerProvider.BlockscoutTokenTransfersResponse
typealias BlockscoutNormalTransactionsResponse = EVMExplorerProvider.BlockscoutNormalTransactionsResponse
typealias BlockscoutNormalTransactionItem = EVMExplorerProvider.BlockscoutNormalTransactionItem
typealias BlockscoutTokenTransferItem = EVMExplorerProvider.BlockscoutTokenTransferItem
typealias BlockscoutAddress = EVMExplorerProvider.BlockscoutAddress
typealias BlockscoutBlock = EVMExplorerProvider.BlockscoutBlock
typealias BlockscoutToken = EVMExplorerProvider.BlockscoutToken
typealias BlockscoutAmount = EVMExplorerProvider.BlockscoutAmount
typealias EthplorerErrorResponse = EVMExplorerProvider.EthplorerErrorResponse
typealias EthplorerErrorBody = EVMExplorerProvider.EthplorerErrorBody
typealias EthplorerAddressHistoryResponse = EVMExplorerProvider.EthplorerAddressHistoryResponse
typealias EthplorerOperation = EVMExplorerProvider.EthplorerOperation
typealias EthplorerTokenInfo = EVMExplorerProvider.EthplorerTokenInfo

struct EthereumSendParameters {
    let nonce: Int
    let gasLimit: Int
    let maxFeePerGasWei: Decimal
    let maxPriorityFeePerGasWei: Decimal
}

struct EthereumFeeHistoryParameters: Encodable {
    let blockCountHex: String
    let blockTag: String
    let rewardPercentiles: [Int]

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(blockCountHex)
        try container.encode(blockTag)
        try container.encode(rewardPercentiles)
    }
}

struct EthereumFeeHistoryResult: Decodable {
    let baseFeePerGas: [String]
    let reward: [[String]]?
}

struct EthereumCallParameters: Encodable {
    let call: EthereumCallRequest
    let blockTag: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(call)
        try container.encode(blockTag)
    }
}

struct EthereumSimulationRequest: Encodable {
    let from: String
    let to: String
    let value: String
    let data: String?
}

struct EthereumSimulationParameters: Encodable {
    let call: EthereumSimulationRequest
    let blockTag: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(call)
        try container.encode(blockTag)
    }
}


enum EthereumWalletEngine {
    static let iso8601Formatter = ISO8601DateFormatter()
    static let supportedTokens: [EthereumSupportedToken] = supportedTokens(for: .ethereum)
}
