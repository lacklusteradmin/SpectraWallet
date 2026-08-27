import Foundation

/// A network a chain family can be on, as a registry chain id.
typealias NetworkChainID = String

extension AppState {
    /// The networks this chain family offers, mainnet first. Core answers, so
    /// no front end enumerates them.
    nonisolated func networkChoices(forChainID chainID: String) -> [NetworkChoice] {
        (Chain(id: chainID)?.networkChoices ?? [])
    }
}

nonisolated extension NetworkChoice: Identifiable {
    public var id: String { chainId }
}

// MARK: - EVM
struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}
// EthereumTokenTransferHistoryDiagnostics moved to Rust core; see DiagnosticsTypesCompat.swift.

// MARK: - Tron
// TronHistoryDiagnostics moved to Rust core.
enum TronBalanceService {
    static let usdtTronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    static let usddTronContract = "TXDk8mbtRbXeYuMNS83CfKPaYYT8XWv9Hz"
    static let usd1TronContract = "TPFqcBAaaUMCSVRCqPaQ9QnzKhmuoLR6Rc"
    static let bttTronContract = "TAFjULxiVgT4qWk6UZwjqwZXTSaGaqnVp4"
    struct TrackedTRC20Token: Equatable {
        let symbol: String
        let contractAddress: String
        let decimals: Int
    }
}

// MARK: - Stellar
// SimpleHistoryDiagnostics moved to Rust core.

// MARK: - ICP
// SimpleHistoryDiagnostics moved to Rust core.

// MARK: - XRP
// SimpleHistoryDiagnostics moved to Rust core.

// MARK: - Cardano
// SimpleHistoryDiagnostics moved to Rust core.

// MARK: - Polkadot
// SimpleHistoryDiagnostics moved to Rust core.
enum PolkadotBalanceService {
}

// MARK: - Monero
// SimpleHistoryDiagnostics moved to Rust core.
enum MoneroBalanceService {
    struct TrustedBackend: Identifiable, Hashable {
        let id: String
        let displayName: String
        let baseURL: String
    }
    static let backendBaseURLDefaultsKey = "monero.backend.baseURL"
    static let backendAPIKeyDefaultsKey = "monero.backend.apiKey"
    static let defaultBackendID = "edge_lws_public"
    static let defaultPublicBackend = TrustedBackend(
        id: defaultBackendID, displayName: "Edge Monero LWS (Default)", baseURL: moneroBackendURLs[0]
    )
    private static let moneroBackendURLs = AppEndpointDirectory.endpoints(for: ["monero.backend.1", "monero.backend.2", "monero.backend.3"])
    static let trustedBackends: [TrustedBackend] = [
        defaultPublicBackend,
        TrustedBackend(
            id: "edge_lws_public_2", displayName: "Edge Monero LWS (Fallback 1)", baseURL: moneroBackendURLs[1]
        ),
        TrustedBackend(
            id: "edge_lws_public_3", displayName: "Edge Monero LWS (Fallback 2)", baseURL: moneroBackendURLs[2]
        ),
    ]
}




// MARK: - Solana
// SolanaHistoryDiagnostics moved to Rust core.
enum SolanaBalanceService {
    struct KnownTokenMetadata {
        let symbol: String
        let name: String
        let decimals: Int
        let coinGeckoId: String
    }
    /// All registry-known SPL tokens, derived from `tokens.toml` via the
    /// Rust-built registry. Single source of truth for mint → metadata lookup
    /// when no user-configured token preferences exist.
    static let knownTokenMetadataByMint: [String: KnownTokenMetadata] = {
        var result: [String: KnownTokenMetadata] = [:]
        for entry in ChainTokenRegistryEntry.builtIn where entry.chain == .solana && !entry.contractAddress.isEmpty {
            result[entry.contractAddress] = KnownTokenMetadata(
                symbol: entry.symbol, name: entry.name, decimals: entry.decimals, coinGeckoId: entry.coinGeckoId
            )
        }
        return result
    }()
    private static let mintAddressBySymbol: [String: String] = {
        var result: [String: String] = [:]
        for entry in ChainTokenRegistryEntry.builtIn where entry.chain == .solana && !entry.contractAddress.isEmpty {
            result[entry.symbol.uppercased()] = entry.contractAddress
        }
        return result
    }()
    static func mintAddress(for symbol: String) -> String? { mintAddressBySymbol[symbol.uppercased()] }
    static func isValidAddress(_ address: String) -> Bool { AddressValidation.isValid(address, kind: "solana") }
}

// MARK: - NEAR
// SimpleHistoryDiagnostics moved to Rust core.
enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
}

// MARK: - Aptos
// SimpleHistoryDiagnostics moved to Rust core.
enum AptosBalanceService {
    static let aptosCoinType = "0x1::aptos_coin::aptoscoin"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
}

// MARK: - Sui
// SimpleHistoryDiagnostics moved to Rust core.
enum SuiBalanceService {
    static let suiCoinType = "0x2::sui::SUI"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
}

// MARK: - TON
// SimpleHistoryDiagnostics moved to Rust core.
enum TONBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
    private static func canonicalAddressIdentifier(_ address: String?) -> String {
        address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Transactions & price alerts (Rust-owned enums)

typealias TransactionKind = CoreTransactionKind
nonisolated extension CoreTransactionKind: RawRepresentable, CaseIterable, Codable, Identifiable {
    public init?(rawValue: String) {
        switch rawValue {
        case "send": self = .send
        case "receive": self = .receive
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .send: return "send"
        case .receive: return "receive"
        }
    }
    public static var allCases: [CoreTransactionKind] { [.send, .receive] }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid CoreTransactionKind: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

typealias TransactionStatus = CoreTransactionStatus
nonisolated extension CoreTransactionStatus: RawRepresentable, CaseIterable, Codable, Identifiable {
    public init?(rawValue: String) {
        switch rawValue {
        case "pending": self = .pending
        case "confirmed": self = .confirmed
        case "failed": self = .failed
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .pending: return "pending"
        case .confirmed: return "confirmed"
        case .failed: return "failed"
        }
    }
    public static var allCases: [CoreTransactionStatus] { [.pending, .confirmed, .failed] }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid CoreTransactionStatus: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

typealias PriceAlertCondition = CorePriceAlertCondition
extension CorePriceAlertCondition: RawRepresentable, CaseIterable, Codable, Identifiable {
    public init?(rawValue: String) {
        switch rawValue {
        case "Above": self = .above
        case "Below": self = .below
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .above: return "Above"
        case .below: return "Below"
        }
    }
    public static var allCases: [CorePriceAlertCondition] { [.above, .below] }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid CorePriceAlertCondition: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

// MARK: - Network selection
