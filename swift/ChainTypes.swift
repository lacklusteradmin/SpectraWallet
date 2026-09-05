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
    private static let mintAddressBySymbol: [String: String] = {
        var result: [String: String] = [:]
        for entry in TokenPreferenceEntry.builtIn
        where entry.token.chain == TokenHostingChain.solana.rawValue && !entry.token.contract.isEmpty {
            result[entry.token.symbol.uppercased()] = entry.token.contract
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
