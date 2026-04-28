import Foundation

// MARK: - Bitcoin
typealias BitcoinNetworkMode = CoreBitcoinNetworkMode
nonisolated extension CoreBitcoinNetworkMode: RawRepresentable, CaseIterable, Codable, Identifiable {
    public init?(rawValue: String) {
        switch rawValue {
        case "mainnet": self = .mainnet
        case "testnet": self = .testnet
        case "testnet4": self = .testnet4
        case "signet": self = .signet
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .mainnet: return "mainnet"
        case .testnet: return "testnet"
        case .testnet4: return "testnet4"
        case .signet: return "signet"
        }
    }
    public static var allCases: [CoreBitcoinNetworkMode] { [.mainnet, .testnet, .testnet4, .signet] }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid CoreBitcoinNetworkMode: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
    public var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        case .testnet4: return "Testnet4"
        case .signet: return "Signet"
        }
    }
}
// MARK: - Dogecoin
typealias DogecoinNetworkMode = CoreDogecoinNetworkMode
nonisolated extension CoreDogecoinNetworkMode: RawRepresentable, CaseIterable, Codable, Identifiable {
    public init?(rawValue: String) {
        switch rawValue {
        case "mainnet": self = .mainnet
        case "testnet": self = .testnet
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .mainnet: return "mainnet"
        case .testnet: return "testnet"
        }
    }
    public static var allCases: [CoreDogecoinNetworkMode] { [.mainnet, .testnet] }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid CoreDogecoinNetworkMode: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
    public var displayName: String { self == .mainnet ? "Mainnet" : "Testnet" }
}
enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Dogecoin") }
    static func endpointCatalogByNetwork() -> [AppEndpointGroupedSettingsEntry] {
        AppEndpointDirectory.groupedSettingsEntries(for: "Dogecoin")
    }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Dogecoin") }
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
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Tron") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Tron") }
}

// MARK: - Stellar
// StellarHistoryDiagnostics moved to Rust core.
enum StellarBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Stellar") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Stellar") }
}

// MARK: - ICP
// ICPHistoryDiagnostics moved to Rust core.
enum ICPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Internet Computer") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] {
        AppEndpointDirectory.diagnosticsChecks(for: "Internet Computer")
    }
}

// MARK: - XRP
// XRPHistoryDiagnostics moved to Rust core.
enum XRPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "XRP Ledger") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] {
        endpointCatalog().map { base in AppEndpointDiagnosticsCheck(endpoint: base, probeUrl: base) }
    }
}

// MARK: - Cardano
// CardanoHistoryDiagnostics moved to Rust core.
enum CardanoBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Cardano") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Cardano") }
}

// MARK: - Polkadot
// PolkadotHistoryDiagnostics moved to Rust core.
enum PolkadotBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Polkadot") }
    static func sidecarEndpointCatalog() -> [String] { AppEndpointDirectory.endpoints(for: ["polkadot.sidecar.parity"]) }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Polkadot") }
}

// MARK: - Monero
// MoneroHistoryDiagnostics moved to Rust core.
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

// MARK: - Bitcoin Cash
enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Bitcoin Cash") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] {
        AppEndpointDirectory.diagnosticsChecks(for: "Bitcoin Cash")
    }
}

// MARK: - Bitcoin SV
enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Bitcoin SV") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Bitcoin SV") }
}

// MARK: - Litecoin
enum LitecoinBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Litecoin") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Litecoin") }
}

// MARK: - Solana
// SolanaHistoryDiagnostics moved to Rust core.
enum SolanaBalanceService {
    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.endpoints(for: ["solana.rpc.mainnet", "solana.rpc.ankr", "solana.rpc.publicnode"])
    }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Solana") }
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
// NearHistoryDiagnostics moved to Rust core.
enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "NEAR") }
    static func rpcEndpointCatalog() -> [String] {
        AppEndpointDirectory.endpoints(for: ["near.rpc.mainnet", "near.rpc.fastnear", "near.rpc.lava"])
    }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "NEAR") }
    static func parseHistoryResponse(_ data: Data, ownerAddress: String) throws -> [NearHistoryParsedSnapshot] {
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        return nearParseHistoryResponse(json: jsonString, ownerAddress: ownerAddress)
    }
}

// MARK: - Aptos
// AptosHistoryDiagnostics moved to Rust core.
enum AptosBalanceService {
    static let aptosCoinType = "0x1::aptos_coin::aptoscoin"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Aptos") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Aptos") }
}

// MARK: - Sui
// SuiHistoryDiagnostics moved to Rust core.
enum SuiBalanceService {
    static let suiCoinType = "0x2::sui::SUI"
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Sui") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "Sui") }
}

// MARK: - TON
// TONHistoryDiagnostics moved to Rust core.
enum TONBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "TON") }
    static func diagnosticsChecks() -> [AppEndpointDiagnosticsCheck] { AppEndpointDirectory.diagnosticsChecks(for: "TON") }
    static func normalizeJettonMasterAddress(_ address: String) -> String { canonicalAddressIdentifier(address) }
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
nonisolated extension CorePriceAlertCondition: RawRepresentable, CaseIterable, Codable, Identifiable {
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
