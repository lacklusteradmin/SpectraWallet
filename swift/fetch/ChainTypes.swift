import Foundation

// MARK: - RustBalanceDecoder (thin Swift forwarders; logic lives in Rust core/src/balance_decoder.rs)
enum RustBalanceDecoder {
    nonisolated static func uint64Field(_ field: String, from json: String) -> UInt64? { balanceDecoderU64Field(field: field, json: json) }
    nonisolated static func int64Field(_ field: String, from json: String) -> Int64? { balanceDecoderI64Field(field: field, json: json) }
    nonisolated static func f64Field(_ field: String, from json: String) -> Double? { balanceDecoderF64Field(field: field, json: json) }
    nonisolated static func stringField(_ field: String, from json: String) -> String? { balanceDecoderStringField(field: field, json: json) }
    nonisolated static func uint128StringField(_ field: String, from json: String) -> Double? { balanceDecoderU128StringFieldAsF64(field: field, json: json) }
    nonisolated static func evmNativeBalance(from json: String) -> Double? { balanceDecoderEvmNativeBalance(json: json) }
    nonisolated static func yoctoNearToDouble(from json: String) -> Double? { balanceDecoderYoctoNearToDouble(json: json) }
    nonisolated static func jsonArrayIsNonEmpty(_ json: String) -> Bool { balanceDecoderJsonArrayIsNonEmpty(json: json) }
    nonisolated static func hasField(_ field: String, in json: String) -> Bool { balanceDecoderHasField(field: field, json: json) }
    nonisolated static func firstElementStringField(_ field: String, from json: String) -> String? { balanceDecoderFirstElementStringField(field: field, json: json) }
}

// MARK: - Codable/RawRepresentable helpers for Rust-owned enums
protocol RustStringEnum: RawRepresentable, CaseIterable, Codable, Identifiable, Equatable where RawValue == String {
    nonisolated static var rawMap: [(Self, String)] { get }
}
extension RustStringEnum {
    nonisolated public init?(rawValue: String) {
        for (c, r) in Self.rawMap where r == rawValue { self = c; return }
        return nil
    }
    // Compare by case name via Mirror instead of `==`. The default `==` from
    // RawRepresentable routes through rawValue, which would re-enter this getter.
    nonisolated public var rawValue: String {
        let key = String(describing: self)
        return Self.rawMap.first(where: { String(describing: $0.0) == key })?.1 ?? ""
    }
    nonisolated public static var allCases: [Self] { Self.rawMap.map(\.0) }
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
    nonisolated public var id: String { rawValue }
    nonisolated public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid \(Self.self): \(raw)")
        }
        self = v
    }
    nonisolated public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

// MARK: - Bitcoin
typealias BitcoinNetworkMode = CoreBitcoinNetworkMode
nonisolated extension CoreBitcoinNetworkMode: RustStringEnum {
    static var rawMap: [(CoreBitcoinNetworkMode, String)] {
        [(.mainnet, "mainnet"), (.testnet, "testnet"), (.testnet4, "testnet4"), (.signet, "signet")]
    }
    public var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .testnet:  return "Testnet"
        case .testnet4: return "Testnet4"
        case .signet:   return "Signet"
        }
    }
}
// MARK: - Dogecoin
typealias DogecoinNetworkMode = CoreDogecoinNetworkMode
nonisolated extension CoreDogecoinNetworkMode: RustStringEnum {
    static var rawMap: [(CoreDogecoinNetworkMode, String)] { [(.mainnet, "mainnet"), (.testnet, "testnet")] }
    public var displayName: String { self == .mainnet ? "Mainnet" : "Testnet" }
}
struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let networkFeeDOGE: Double?
    let confirmations: Int?
}
enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Dogecoin") }
    static func endpointCatalogByNetwork() -> [(title: String, endpoints: [String])] { AppEndpointDirectory.groupedSettingsEntries(for: "Dogecoin") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Dogecoin") }
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
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Tron") }
}

// MARK: - Stellar
// StellarHistoryDiagnostics moved to Rust core.
enum StellarBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Stellar") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Stellar") }
}

// MARK: - ICP
// ICPHistoryDiagnostics moved to Rust core.
enum ICPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Internet Computer") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Internet Computer") }
}

// MARK: - XRP
// XRPHistoryDiagnostics moved to Rust core.
enum XRPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "XRP Ledger") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { endpointCatalog().map { base in (endpoint: base, probeURL: base) }}
}

// MARK: - Cardano
// CardanoHistoryDiagnostics moved to Rust core.
enum CardanoBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Cardano") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Cardano") }
}

// MARK: - Polkadot
// PolkadotHistoryDiagnostics moved to Rust core.
enum PolkadotBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Polkadot") }
    static func sidecarEndpointCatalog() -> [String] { AppEndpointDirectory.endpoints(for: ["polkadot.sidecar.parity"]) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Polkadot") }
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
        defaultPublicBackend, TrustedBackend(
            id: "edge_lws_public_2", displayName: "Edge Monero LWS (Fallback 1)", baseURL: moneroBackendURLs[1]
        ), TrustedBackend(
            id: "edge_lws_public_3", displayName: "Edge Monero LWS (Fallback 2)", baseURL: moneroBackendURLs[2]
        )
    ]
}

// MARK: - Bitcoin Cash
enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Bitcoin Cash") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Bitcoin Cash") }
}

// MARK: - Bitcoin SV
enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Bitcoin SV") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Bitcoin SV") }
}

// MARK: - Litecoin
enum LitecoinBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Litecoin") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Litecoin") }
}

// MARK: - Solana
// SolanaHistoryDiagnostics moved to Rust core.
enum SolanaBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.endpoints(for: ["solana.rpc.mainnet", "solana.rpc.ankr", "solana.rpc.publicnode"]) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Solana") }
    struct KnownTokenMetadata {
        let symbol: String
        let name: String
        let decimals: Int
        let marketDataId: String
        let coinGeckoId: String
    }
    static let usdtMintAddress = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
    static let usdcMintAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    static let pyusdMintAddress = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
    static let usdgMintAddress = "2u1tszSeqZ3qBWF3uNGPFc8TzMk2tdiwknnRMWGWjGWH"
    static let usd1MintAddress = "USD1ttGY1N17NEEHLmELoaybftRBUSErhqYiQzvEmuB"
    static let linkMintAddress = "LinkhB3afbBKb2EQQu7s7umdZceV3wcvAUJhQAfQ23L"
    static let wlfiMintAddress = "WLFinEv6ypjkczcS83FZqFpgFZYwQXutRbxGe7oC16g"
    static let jupMintAddress = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
    static let bonkMintAddress = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    static let knownTokenMetadataByMint: [String: KnownTokenMetadata] = [
        usdtMintAddress: KnownTokenMetadata(
            symbol: "USDT", name: "Tether USD", decimals: 6, marketDataId: "825", coinGeckoId: "tether"
        ), usdcMintAddress: KnownTokenMetadata(
            symbol: "USDC", name: "USD Coin", decimals: 6, marketDataId: "3408", coinGeckoId: "usd-coin"
        ), pyusdMintAddress: KnownTokenMetadata(
            symbol: "PYUSD", name: "PayPal USD", decimals: 6, marketDataId: "27772", coinGeckoId: "paypal-usd"
        ), usdgMintAddress: KnownTokenMetadata(
            symbol: "USDG", name: "Global Dollar", decimals: 6, marketDataId: "0", coinGeckoId: "global-dollar"
        ), usd1MintAddress: KnownTokenMetadata(symbol: "USD1", name: "USD1", decimals: 6, marketDataId: "0", coinGeckoId: ""), linkMintAddress: KnownTokenMetadata(
            symbol: "LINK", name: "Chainlink", decimals: 8, marketDataId: "1975", coinGeckoId: "chainlink"
        ), wlfiMintAddress: KnownTokenMetadata(
            symbol: "WLFI", name: "World Liberty Financial", decimals: 6, marketDataId: "0", coinGeckoId: ""
        ), jupMintAddress: KnownTokenMetadata(
            symbol: "JUP", name: "Jupiter", decimals: 6, marketDataId: "29210", coinGeckoId: "jupiter-exchange-solana"
        ), bonkMintAddress: KnownTokenMetadata(symbol: "BONK", name: "Bonk", decimals: 5, marketDataId: "23095", coinGeckoId: "bonk")
    ]
    static func mintAddress(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "USDT": return usdtMintAddress
        case "USDC": return usdcMintAddress
        case "PYUSD": return pyusdMintAddress
        case "USDG": return usdgMintAddress
        case "USD1": return usd1MintAddress
        case "LINK": return linkMintAddress
        case "WLFI": return wlfiMintAddress
        case "JUP": return jupMintAddress
        case "BONK": return bonkMintAddress
        default: return nil
        }}
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
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "NEAR") }
    static func rpcEndpointCatalog() -> [String] { AppEndpointDirectory.endpoints(for: ["near.rpc.mainnet", "near.rpc.fastnear", "near.rpc.lava"]) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "NEAR") }
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
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Aptos") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Aptos") }
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
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "Sui") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "Sui") }
}

// MARK: - TON
// TONHistoryDiagnostics moved to Rust core.
enum TONBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: "TON") }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: "TON") }
    static func normalizeJettonMasterAddress(_ address: String) -> String { canonicalAddressIdentifier(address) }
    private static func canonicalAddressIdentifier(_ address: String?) -> String { address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

// MARK: - Transactions & price alerts (Rust-owned enums)

typealias TransactionKind = CoreTransactionKind
nonisolated extension CoreTransactionKind: RustStringEnum {
    static var rawMap: [(CoreTransactionKind, String)] { [(.send, "send"), (.receive, "receive")] }
}

typealias TransactionStatus = CoreTransactionStatus
nonisolated extension CoreTransactionStatus: RustStringEnum {
    static var rawMap: [(CoreTransactionStatus, String)] {
        [(.pending, "pending"), (.confirmed, "confirmed"), (.failed, "failed")]
    }
}

typealias PriceAlertCondition = CorePriceAlertCondition
nonisolated extension CorePriceAlertCondition: RustStringEnum {
    static var rawMap: [(CorePriceAlertCondition, String)] { [(.above, "Above"), (.below, "Below")] }
}
