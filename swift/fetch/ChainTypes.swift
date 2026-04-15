import Foundation

// MARK: - RustBalanceDecoder (thin Swift forwarders; logic lives in Rust core/src/balance_decoder.rs)
enum RustBalanceDecoder {
    static func uint64Field(_ field: String, from json: String) -> UInt64? { balanceDecoderU64Field(field: field, json: json) }
    static func int64Field(_ field: String, from json: String) -> Int64? { balanceDecoderI64Field(field: field, json: json) }
    static func uint128StringField(_ field: String, from json: String) -> Double? { balanceDecoderU128StringFieldAsF64(field: field, json: json) }
    static func evmNativeBalance(from json: String) -> Double? { balanceDecoderEvmNativeBalance(json: json) }
    static func yoctoNearToDouble(from json: String) -> Double? { balanceDecoderYoctoNearToDouble(json: json) }
}

// MARK: - Codable/RawRepresentable helpers for Rust-owned enums
protocol RustStringEnum: RawRepresentable, CaseIterable, Codable, Identifiable, Equatable where RawValue == String {
    static var rawMap: [(Self, String)] { get }
}
extension RustStringEnum {
    public init?(rawValue: String) {
        for (c, r) in Self.rawMap where r == rawValue { self = c; return }
        return nil
    }
    // Compare by case name via Mirror instead of `==`. The default `==` from
    // RawRepresentable routes through rawValue, which would re-enter this getter.
    public var rawValue: String {
        let key = String(describing: self)
        return Self.rawMap.first(where: { String(describing: $0.0) == key })?.1 ?? ""
    }
    public static var allCases: [Self] { Self.rawMap.map(\.0) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid \(Self.self): \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

// MARK: - Bitcoin
typealias BitcoinNetworkMode = CoreBitcoinNetworkMode
extension CoreBitcoinNetworkMode: RustStringEnum {
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
struct BitcoinHistorySnapshot: Equatable {
    let txid: String
    let amountBTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}
struct BitcoinHistoryPage {
    let snapshots: [BitcoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

// MARK: - Dogecoin
typealias DogecoinNetworkMode = CoreDogecoinNetworkMode
extension CoreDogecoinNetworkMode: RustStringEnum {
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
    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int?
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.dogecoinChainName) }
    static func endpointCatalogByNetwork() -> [(title: String, endpoints: [String])] { AppEndpointDirectory.groupedSettingsEntries(for: ChainBackendRegistry.dogecoinChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.dogecoinChainName) }
}

// MARK: - EVM
struct EthereumCustomFeeConfiguration: Equatable {
    let maxFeePerGasGwei: Double
    let maxPriorityFeePerGasGwei: Double
}
struct EthereumTransactionReceipt: Equatable {
    let transactionHash: String
    let blockNumber: Int?
    let status: String?
    let gasUsed: Decimal?
    let effectiveGasPriceWei: Decimal?
    var isConfirmed: Bool { blockNumber != nil }
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
struct EthereumSupportedToken {
    let name: String
    let symbol: String
    let contractAddress: String
    let decimals: Int
    let marketDataId: String
    let coinGeckoId: String
    init(name: String, symbol: String, contractAddress: String, decimals: Int, marketDataId: String, coinGeckoId: String) {
        self.name = name
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.decimals = decimals
        self.marketDataId = marketDataId
        self.coinGeckoId = coinGeckoId
    }
    init(registryEntry: ChainTokenRegistryEntry) {
        self.name = registryEntry.name
        self.symbol = registryEntry.symbol
        self.contractAddress = registryEntry.contractAddress
        self.decimals = registryEntry.decimals
        self.marketDataId = registryEntry.marketDataId
        self.coinGeckoId = registryEntry.coinGeckoId
    }
}
// EthereumTokenTransferHistoryDiagnostics moved to Rust core; see DiagnosticsTypesCompat.swift.

// MARK: - Tron
struct TronTokenBalanceSnapshot: Equatable {
    let symbol: String
    let contractAddress: String?
    let balance: Double
}
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
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.tronChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.tronChainName) }
}

// MARK: - Stellar
// StellarHistoryDiagnostics moved to Rust core.
enum StellarBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.stellarChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.stellarChainName) }
}

// MARK: - ICP
// ICPHistoryDiagnostics moved to Rust core.
enum ICPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.icpChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.icpChainName) }
}

// MARK: - XRP
// XRPHistoryDiagnostics moved to Rust core.
enum XRPBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.xrpChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { endpointCatalog().map { base in (endpoint: base, probeURL: base) }}
}

// MARK: - Cardano
// CardanoHistoryDiagnostics moved to Rust core.
enum CardanoBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.cardanoChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.cardanoChainName) }
}

// MARK: - Polkadot
// PolkadotHistoryDiagnostics moved to Rust core.
enum PolkadotBalanceService {
    static func endpointCatalog() -> [String] { PolkadotProvider.endpointCatalog() }
    static func sidecarEndpointCatalog() -> [String] { PolkadotProvider.sidecarBaseURLs }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { PolkadotProvider.diagnosticsChecks() }
}

// MARK: - Monero
// MoneroHistoryDiagnostics moved to Rust core.
enum MoneroBalanceService {
    typealias TrustedBackend = MoneroProvider.TrustedBackend
    static let backendBaseURLDefaultsKey = MoneroProvider.backendBaseURLDefaultsKey
    static let backendAPIKeyDefaultsKey = MoneroProvider.backendAPIKeyDefaultsKey
    static let defaultBackendID = MoneroProvider.defaultBackendID
    static let defaultPublicBackend = MoneroProvider.defaultPublicBackend
    static let trustedBackends = MoneroProvider.trustedBackends
}

// MARK: - Bitcoin Cash
enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] { BitcoinCashProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinCashProvider.diagnosticsChecks() }
}

// MARK: - Bitcoin SV
enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] { BitcoinSVProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { BitcoinSVProvider.diagnosticsChecks() }
}

// MARK: - Litecoin
enum LitecoinBalanceService {
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.litecoinChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.litecoinChainName) }
}

// MARK: - Solana
// SolanaHistoryDiagnostics moved to Rust core.
struct SolanaSPLTokenBalanceSnapshot: Equatable {
    let mintAddress: String
    let sourceTokenAccountAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataId: String
    let coinGeckoId: String
}
struct SolanaPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SolanaSPLTokenBalanceSnapshot]
}
enum SolanaBalanceService {
    static func endpointCatalog() -> [String] { SolanaProvider.balanceEndpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { SolanaProvider.diagnosticsChecks() }
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
    static func isValidAddress(_ address: String) -> Bool { AddressValidation.isValidSolanaAddress(address) }
}

// MARK: - NEAR
struct NearHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}
// NearHistoryDiagnostics moved to Rust core.
struct NearTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataId: String
    let coinGeckoId: String
}
enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.nearChainName) }
    static func rpcEndpointCatalog() -> [String] { ChainBackendRegistry.NearRuntimeEndpoints.rpcBaseURLs }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.nearChainName) }
    static func parseHistoryResponse(_ data: Data, ownerAddress: String) throws -> [NearHistorySnapshot] {
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        return nearParseHistoryResponse(json: jsonString, ownerAddress: ownerAddress).map { parsed in
            NearHistorySnapshot(
                transactionHash: parsed.transactionHash,
                kind: TransactionKind(rawValue: parsed.kind) ?? .send,
                amount: parsed.amountNear,
                counterpartyAddress: parsed.counterpartyAddress,
                createdAt: parsed.createdAtUnixSeconds > 0 ? Date(timeIntervalSince1970: parsed.createdAtUnixSeconds) : Date(),
                status: .confirmed
            )
        }
    }
}

// MARK: - Aptos
// AptosHistoryDiagnostics moved to Rust core.
struct AptosTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataId: String
    let coinGeckoId: String
}
struct AptosPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [AptosTokenBalanceSnapshot]
}
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
    static func endpointCatalog() -> [String] { AptosProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AptosProvider.diagnosticsChecks() }
}

// MARK: - Sui
// SuiHistoryDiagnostics moved to Rust core.
struct SuiTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataId: String
    let coinGeckoId: String
}
struct SuiPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SuiTokenBalanceSnapshot]
}
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
    static func endpointCatalog() -> [String] { AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.suiChainName) }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.suiChainName) }
}

// MARK: - TON
// TONHistoryDiagnostics moved to Rust core.
struct TONJettonBalanceSnapshot: Equatable {
    let masterAddress: String
    let walletAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataId: String
    let coinGeckoId: String
}
struct TONPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [TONJettonBalanceSnapshot]
}
enum TONBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataId: String
        let coinGeckoId: String
    }
    static func endpointCatalog() -> [String] { TONProvider.endpointCatalog() }
    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] { TONProvider.diagnosticsChecks() }
    static func normalizeJettonMasterAddress(_ address: String) -> String { canonicalAddressIdentifier(address) }
    private static func canonicalAddressIdentifier(_ address: String?) -> String { address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

// MARK: - Transactions & price alerts (Rust-owned enums)

typealias TransactionKind = CoreTransactionKind
extension CoreTransactionKind: RustStringEnum {
    static var rawMap: [(CoreTransactionKind, String)] { [(.send, "send"), (.receive, "receive")] }
}

typealias TransactionStatus = CoreTransactionStatus
extension CoreTransactionStatus: RustStringEnum {
    static var rawMap: [(CoreTransactionStatus, String)] {
        [(.pending, "pending"), (.confirmed, "confirmed"), (.failed, "failed")]
    }
}

typealias PriceAlertCondition = CorePriceAlertCondition
extension CorePriceAlertCondition: RustStringEnum {
    static var rawMap: [(CorePriceAlertCondition, String)] { [(.above, "Above"), (.below, "Below")] }
}
