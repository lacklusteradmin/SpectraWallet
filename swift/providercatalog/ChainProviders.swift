import Foundation

enum SolanaProvider {
    static let endpointReliabilityNamespace = "solana.rpc"
    static let balanceRPCBaseURLs = ChainBackendRegistry.SolanaRuntimeEndpoints.balanceRPCBaseURLs
    static let sendRPCBaseURLs = ChainBackendRegistry.SolanaRuntimeEndpoints.sendRPCBaseURLs
    static func balanceEndpointCatalog() -> [String] { balanceRPCBaseURLs }
    static func sendEndpointCatalog() -> [String] { sendRPCBaseURLs }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.solanaChainName) }
    static func orderedSendRPCBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        let candidates = filteredSendRPCBaseURLs(providerIDs: providerIDs)
        return ChainEndpointReliability.orderedEndpoints(namespace: endpointReliabilityNamespace, candidates: candidates)
    }
    static func filteredSendRPCBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else { return sendRPCBaseURLs }
        return sendRPCBaseURLs.filter { endpoint in
            switch endpoint {
            case "https://api.mainnet-beta.solana.com": return providerIDs.contains("solana-mainnet-beta")
            case "https://rpc.ankr.com/solana": return providerIDs.contains("solana-ankr")
            default: return false
            }}}
}

enum PolkadotProvider {
    static let endpointReliabilityNamespace = "polkadot.sidecar"
    static let sidecarBaseURLs = ChainBackendRegistry.PolkadotRuntimeEndpoints.sidecarBaseURLs
    static let rpcBaseURLs = ChainBackendRegistry.PolkadotRuntimeEndpoints.rpcBaseURLs
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.polkadotChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.polkadotChainName) }
    static func orderedSidecarEndpoints() -> [String] { ChainEndpointReliability.orderedEndpoints(namespace: endpointReliabilityNamespace, candidates: sidecarBaseURLs) }
    struct SidecarBalanceInfo: Decodable {
        let free: String?
        let nonce: Int? }
    struct TransactionMaterial: Decodable {
        struct At: Decodable {
            let hash: String
            let height: String
        }
        let at: At
        let genesisHash: String
        let specVersion: String
        let txVersion: String
    }
    struct FeeEstimateEnvelope: Decodable {
        let estimatedFee: String?
        let partialFee: String?
        let inclusionFee: FeeComponent?
        struct FeeComponent: Decodable {
            let baseFee: String?
            let lenFee: String?
            let adjustedWeightFee: String? }}
    struct BroadcastEnvelope: Decodable {
        let hash: String?
        let txHash: String? }
}

enum AptosProvider {
    static let endpoints = ChainBackendRegistry.AptosRuntimeEndpoints.rpcURLs
    struct CoinStoreResource: Decodable {
        let data: CoinStoreData?
        struct CoinStoreData: Decodable {
            let coin: CoinValue? }
        struct CoinValue: Decodable {
            let value: String? }}
    struct AccountResource: Decodable {
        let type: String?
        let data: CoinStoreResource.CoinStoreData? }
    struct TransactionItem: Decodable {
        let type: String?
        let hash: String?
        let success: Bool?
        let sender: String?
        let timestamp: String?
        let payload: Payload?
        struct Payload: Decodable {
            let function: String?
            let arguments: [String]? }}
    struct ViewFunctionRequest: Encodable {
        let function: String
        let typeArguments: [String]
        let arguments: [String]
        enum CodingKeys: String, CodingKey {
            case function
            case typeArguments = "type_arguments"
            case arguments
        }}
    struct SubmitResponse: Decodable {
        let hash: String? }
    struct TransactionLookupResponse: Decodable {
        let hash: String?
        let success: Bool?
        let vmStatus: String?
        enum CodingKeys: String, CodingKey {
            case hash
            case success
            case vmStatus = "vm_status"
        }}
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.aptosChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.aptosChainName) }
}

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
        id: defaultBackendID, displayName: "Edge Monero LWS (Default)", baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[0]
    )
    static let trustedBackends: [TrustedBackend] = [
        defaultPublicBackend, TrustedBackend(
            id: "edge_lws_public_2", displayName: "Edge Monero LWS (Fallback 1)", baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[1]
        ), TrustedBackend(
            id: "edge_lws_public_3", displayName: "Edge Monero LWS (Fallback 2)", baseURL: ChainBackendRegistry.MoneroRuntimeEndpoints.trustedBackendBaseURLs[2]
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
        let status: String? }
    struct PreviewRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }
    struct PreviewResponse: Decodable {
        let estimatedFeeXMR: Double
        let priority: String? }
    struct SendRequest: Encodable {
        let fromAddress: String
        let toAddress: String
        let amountXMR: Double
    }
    struct SendResponse: Decodable {
        let txid: String
        let feeXMR: Double? }
}

enum TONProvider {
    static let endpointReliabilityNamespace = "ton.api.v2"
    static let apiV2BaseURLs = ChainBackendRegistry.TONRuntimeEndpoints.apiV2BaseURLs
    static let apiV3BaseURLs = ChainBackendRegistry.TONRuntimeEndpoints.apiV3BaseURLs
    struct WalletInformationEnvelope: Decodable {
        let ok: Bool?
        let result: WalletInformationResult?
        let error: String? }
    struct WalletInformationResult: Decodable {
        let balance: String?
        let seqno: UInt32? }
    struct TransactionsEnvelope: Decodable {
        let ok: Bool?
        let result: [TransactionEntry]?
        let error: String? }
    struct JettonWalletsEnvelope: Decodable {
        let jettonWallets: [JettonWalletEntry]?
        enum CodingKeys: String, CodingKey {
            case jettonWallets = "jetton_wallets"
        }}
    struct JettonWalletEntry: Decodable {
        let balance: String?
        let address: String?
        let owner: AddressEnvelope?
        let jetton: AddressEnvelope?
        struct AddressEnvelope: Decodable {
            let address: String? }}
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
        }}
    struct TransactionID: Decodable {
        let hash: String? }
    struct Message: Decodable {
        let source: String?
        let destination: String?
        let value: String? }
    struct SendBocEnvelope: Decodable {
        let ok: Bool?
        let result: SendBocResult?
        let error: String? }
    struct SendBocResult: Decodable {
        let hash: String? }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.tonChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.tonChainName) }
    static func orderedAPIv2Endpoints() -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace, candidates: apiV2BaseURLs
        )
        return ordered.compactMap(URL.init(string:))
    }
}

enum EsploraProvider {
    enum ProviderID: String, CaseIterable {
        case blockstream
        case mempool
        case mempoolEmzy
        case maestro
    }
    struct AddressResponse: Decodable {
        let chainStats: AddressStats
        let mempoolStats: AddressStats
        enum CodingKeys: String, CodingKey {
            case chainStats = "chain_stats"
            case mempoolStats = "mempool_stats"
        }}
    struct AddressStats: Decodable {
        let fundedTXOSum: Int64
        let spentTXOSum: Int64
        let txCount: Int
        enum CodingKeys: String, CodingKey {
            case fundedTXOSum = "funded_txo_sum"
            case spentTXOSum = "spent_txo_sum"
            case txCount = "tx_count"
        }}
    struct TransactionStatus: Decodable {
        let confirmed: Bool
        let blockHeight: Int?
        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
        }}
    struct AddressTransaction: Decodable {
        struct VIN: Decodable {
            struct Prevout: Decodable {
                let scriptpubkeyAddress: String?
                let value: Int64
                enum CodingKeys: String, CodingKey {
                    case scriptpubkeyAddress = "scriptpubkey_address"
                    case value
                }}
            let prevout: Prevout? }
        struct VOUT: Decodable {
            let scriptpubkeyAddress: String?
            let value: Int64
            enum CodingKeys: String, CodingKey {
                case scriptpubkeyAddress = "scriptpubkey_address"
                case value
            }}
        struct Status: Decodable {
            let confirmed: Bool
            let blockHeight: Int?
            let blockTime: TimeInterval?
            enum CodingKeys: String, CodingKey {
                case confirmed
                case blockHeight = "block_height"
                case blockTime = "block_time"
            }}
        let txid: String
        let vin: [VIN]
        let vout: [VOUT]
        let status: Status
    }
    static func defaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] { ChainBackendRegistry.BitcoinRuntimeEndpoints.esploraBaseURLs(for: networkMode) }
    static func runtimeBaseURLs(for networkMode: BitcoinNetworkMode, custom: [String] = []) -> [String] {
        let trimmed = custom.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !trimmed.isEmpty { return trimmed }
        return defaultBaseURLs(for: networkMode)
    }
    static func filteredBaseURLs(for networkMode: BitcoinNetworkMode, custom: [String] = [], providerIDs: Set<String>? = nil) -> [String] {
        let allEndpoints = runtimeBaseURLs(for: networkMode, custom: custom)
        guard let providerIDs, !providerIDs.isEmpty else { return allEndpoints }
        let normalized = Set(providerIDs.map { $0.lowercased() })
        let allowEsplora = normalized.contains("esplora")
        let allowMaestro = normalized.contains("maestro-esplora")
        let filtered = allEndpoints.filter { endpoint in
            let isMaestro = endpoint.contains("gomaestro-api.org")
            return isMaestro ? allowMaestro : allowEsplora
        }
        return filtered.isEmpty ? allEndpoints : filtered
    }
    static func url(baseURL: String, path: String) -> URL? { URL(string: baseURL + path) }
    static func runWithFallback<T>(
        baseURLs: [String], operation: @escaping (String) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await operation(baseURL)
            } catch {
                if firstError == nil { firstError = error }
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }}
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }
}

enum BitcoinCashProvider {
    enum ProviderID: String, CaseIterable {
        case blockchair
        case actorforth
    }
    static let blockchairBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairBaseURL
    static let actorforthBaseURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.actorforthBaseURL
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.bitcoinCashChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.bitcoinCashChainName) }
    struct BlockchairAddressResponse: Decodable {
        struct Context: Decodable {
            let code: Int? }
        let data: [String: AddressDashboard]
        let context: Context? }
    struct AddressDashboard: Decodable {
        struct AddressDetails: Decodable {
            let balance: Int64?
            let transactionCount: Int?
            enum CodingKeys: String, CodingKey {
                case balance
                case transactionCount = "transaction_count"
            }}
        struct UTXOEntry: Decodable {
            let transactionHash: String
            let index: Int
            let value: UInt64
            enum CodingKeys: String, CodingKey {
                case transactionHash = "transaction_hash"
                case index
                case value
            }}
        let address: AddressDetails
        let transactions: [String]
        let utxo: [UTXOEntry]? }
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
            }}
        struct Input: Decodable {
            let recipient: String?
            let value: Int64? }
        struct Output: Decodable {
            let recipient: String?
            let value: Int64? }
        let transaction: TransactionDetails
        let inputs: [Input]
        let outputs: [Output]
    }
    struct ActorForthEnvelope<Payload: Decodable>: Decodable {
        let status: String?
        let message: String?
        let data: Payload? }
    struct ActorForthAddressDetails: Decodable {
        let balanceSat: Int64?
        let txApperances: Int?
        let transactions: [String]?
        enum CodingKeys: String, CodingKey {
            case balanceSat
            case txApperances
            case transactions
        }}
    struct ActorForthUTXOPayload: Decodable {
        struct Entry: Decodable {
            let txid: String?
            let vout: Int?
            let satoshis: UInt64? }
        let utxos: [Entry]? }
    struct ActorForthTransactionPayload: Decodable {
        struct Input: Decodable {
            let legacyAddress: String?
            let cashAddress: String?
            let valueSat: Int64?
            enum CodingKeys: String, CodingKey {
                case legacyAddress
                case cashAddress
                case valueSat
            }}
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
            }}
        let txid: String?
        let confirmations: Int?
        let blockheight: Int?
        let time: TimeInterval?
        let vin: [Input]?
        let vout: [Output]? }
    static func blockchairAddressDashboardURL(address: String, limit: Int, offset: Int) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(blockchairBaseURL)/dashboards/address/\(encoded)?limit=\(max(1, limit)),\(max(1, limit))&offset=\(max(0, offset)),0")
    }
    static func blockchairTransactionURL(txid: String) -> URL? {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(blockchairBaseURL)/dashboards/transaction/\(encoded)")
    }
    static func actorForthAddressDetailsURL(address: String) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(actorforthBaseURL)/address/details/\(encoded)")
    }
    static func actorForthUTXOsURL(address: String) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(actorforthBaseURL)/address/utxo/\(encoded)")
    }
    static func actorForthTransactionURL(txid: String) -> URL? {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(actorforthBaseURL)/transaction/details/\(encoded)")
    }
    static func runWithFallback<T>(
        candidates: [ProviderID], operation: @escaping (ProviderID) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                if firstError == nil { firstError = error }
                lastError = error
                try? await Task.sleep(nanoseconds: 150_000_000)
            }}
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }
}

enum BitcoinSVProvider {
    enum ProviderID: String, CaseIterable {
        case whatsonchain
        case blockchair
    }
    static let whatsonchainBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainBaseURL
    static let whatsonchainChainInfoURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainChainInfoURL
    static let blockchairBaseURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairBaseURL
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.bitcoinSVChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.bitcoinSVChainName) }
    struct WhatsOnChainBalanceResponse: Decodable {
        let confirmed: Int64?
        let unconfirmed: Int64? }
    struct WhatsOnChainHistoryEntry: Decodable {
        let txHash: String
        let height: Int?
        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case height
        }}
    struct WhatsOnChainUnspentEntry: Decodable {
        let txHash: String
        let outputIndex: Int
        let value: UInt64
        enum CodingKeys: String, CodingKey {
            case txHash = "tx_hash"
            case outputIndex = "tx_pos"
            case value
        }}
    struct WhatsOnChainTransaction: Decodable {
        struct Input: Decodable {
            struct ScriptSignature: Decodable {
                let asm: String?
                let hex: String? }
            let txid: String?
            let vout: Int?
            let scriptSig: ScriptSignature?
            let sequence: UInt64?
            let address: String?
            let value: Double? }
        struct Output: Decodable {
            struct ScriptPubKey: Decodable {
                let addresses: [String]?
                let address: String? }
            let value: Double?
            let n: Int?
            let scriptPubKey: ScriptPubKey? }
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
            }}
        struct UTXOEntry: Decodable {
            let transactionHash: String
            let index: Int
            let value: UInt64
            enum CodingKeys: String, CodingKey {
                case transactionHash = "transaction_hash"
                case index
                case value
            }}
        let address: AddressDetails
        let transactions: [String]
        let utxo: [UTXOEntry]? }
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
            }}
        struct Input: Decodable {
            let recipient: String?
            let value: Int64? }
        struct Output: Decodable {
            let recipient: String?
            let value: Int64? }
        let transaction: TransactionDetails
        let inputs: [Input]
        let outputs: [Output]
    }
    static func blockchairAddressDashboardURL(address: String, limit: Int, offset: Int) -> URL? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(blockchairBaseURL)/dashboards/address/\(encoded)?limit=\(max(1, limit)),\(max(1, limit))&offset=\(max(0, offset)),0")
    }
    static func blockchairTransactionURL(txid: String) -> URL? {
        guard let encoded = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(blockchairBaseURL)/dashboards/transaction/\(encoded)")
    }
    static func whatsOnChainURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: whatsonchainBaseURL + path) else { return nil }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url
    }
    static func runWithFallback<T>(
        candidates: [ProviderID], operation: @escaping (ProviderID) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                if firstError == nil { firstError = error }
                lastError = error
                try? await Task.sleep(nanoseconds: 150_000_000)
            }}
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
