import Foundation

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
    case polygon
    case base
    case linea
    case scroll
    case blast
    case mantle
    var displayName: String {
        switch self {
        case .ethereum: return "Ethereum"
        case .ethereumSepolia: return "Ethereum Sepolia"
        case .ethereumHoodi: return "Ethereum Hoodi"
        case .ethereumClassic: return "Ethereum Classic"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .bnb: return "BNB Chain"
        case .avalanche: return "Avalanche"
        case .hyperliquid: return "Hyperliquid"
        case .polygon: return "Polygon"
        case .base: return "Base"
        case .linea: return "Linea"
        case .scroll: return "Scroll"
        case .blast: return "Blast"
        case .mantle: return "Mantle"
        }
    }
    var tokenTrackingChain: TokenTrackingChain? {
        switch self {
        case .ethereum: return .ethereum
        case .ethereumSepolia, .ethereumHoodi, .ethereumClassic: return nil
        case .arbitrum: return .arbitrum
        case .optimism: return .optimism
        case .bnb: return .bnb
        case .avalanche: return .avalanche
        case .hyperliquid: return .hyperliquid
        case .polygon: return .polygon
        case .base: return .base
        case .linea: return .linea
        case .scroll: return .scroll
        case .blast: return .blast
        case .mantle: return .mantle
        }
    }
    var expectedChainID: Int {
        switch self {
        case .ethereum: return 1
        case .ethereumSepolia: return 11_155_111
        case .ethereumHoodi: return 560_048
        case .ethereumClassic: return 61
        case .arbitrum: return 42161
        case .optimism: return 10
        case .bnb: return 56
        case .avalanche: return 43114
        case .hyperliquid: return 999
        case .polygon: return 137
        case .base: return 8453
        case .linea: return 59144
        case .scroll: return 534352
        case .blast: return 81457
        case .mantle: return 5000
        }
    }
    var defaultDerivationPath: String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid, .polygon, .base,
            .linea, .scroll, .blast, .mantle:
            return "m/44'/60'/0'/0/0"
        case .ethereumClassic: return "m/44'/61'/0'/0/0"
        }
    }
    func derivationPath(account: UInt32) -> String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid, .polygon, .base,
            .linea, .scroll, .blast, .mantle:
            return "m/44'/60'/\(account)'/0/0"
        case .ethereumClassic: return "m/44'/61'/\(account)'/0/0"
        }
    }
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
    var isEthereumFamily: Bool {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi: return true
        default: return false
        }
    }
    var isEthereumMainnet: Bool { self == .ethereum }
}

// Send preview types are now UniFFI-generated from Rust (core/src/wallet_core.rs).
// Swift owns only the send *result* types (not yet lifted) + chain-specific enums used by the UI.

struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}

enum EthereumNetworkMode: String, CaseIterable, Identifiable {
    case mainnet
    case sepolia
    case hoodi
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .sepolia: return "Sepolia"
        case .hoodi: return "Hoodi"
        }
    }
}
enum BitcoinFeePriority: String, CaseIterable, Identifiable {
    case economy
    case normal
    case priority
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .economy: return "Economy"
        case .normal: return "Normal"
        case .priority: return "Priority"
        }
    }
}
enum DogecoinFeePriority: String, CaseIterable, Equatable, Codable {
    case economy
    case normal
    case priority
}
enum LitecoinChangeStrategy: String, CaseIterable, Identifiable {
    case derivedChange
    case reuseSourceAddress
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .derivedChange: return "Derived change address"
        case .reuseSourceAddress: return "Reuse source address"
        }
    }
}
enum SolanaDerivationPreference {
    case standard
    case legacy
}

// MARK: - EVM address utilities (moved from Send/Engines/EVM/)

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid EVM address."
        case .invalidResponse: return "Unexpected response from EVM provider."
        case .rpcFailure(let detail): return detail
        }
    }
}
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard AddressValidation.isValid(normalized, kind: "evm") else { throw EthereumWalletEngineError.invalidAddress }
    return normalized
}
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}

@MainActor
@Observable
final class SendPreviewStore {
    var ethereumSendPreview: EthereumSendPreview?
    var bitcoinSendPreview: BitcoinSendPreview?
    var bitcoinCashSendPreview: BitcoinSendPreview?
    var bitcoinSVSendPreview: BitcoinSendPreview?
    var litecoinSendPreview: BitcoinSendPreview?
    var dogecoinSendPreview: DogecoinSendPreview?
    var tronSendPreview: TronSendPreview?
    var solanaSendPreview: SolanaSendPreview?
    var xrpSendPreview: XrpSendPreview?
    var stellarSendPreview: StellarSendPreview?
    var moneroSendPreview: MoneroSendPreview?
    var cardanoSendPreview: CardanoSendPreview?
    var suiSendPreview: SuiSendPreview?
    var aptosSendPreview: AptosSendPreview?
    var tonSendPreview: TonSendPreview?
    var icpSendPreview: IcpSendPreview?
    var nearSendPreview: NearSendPreview?
    var polkadotSendPreview: PolkadotSendPreview?

    /// The preview to hand Rust for `chainName`, tagged with its shape.
    ///
    /// Rust used to receive all eighteen previews and select one by matching on
    /// the chain name — a match that carried its own EVM chain list and had
    /// gone stale. Tagging at the source means only the relevant preview
    /// crosses the FFI, and EVM membership is asked of the registry.
    func taggedPreview(forChainNamed chainName: String) -> SendPreview? {
        switch chainName {
        case "Bitcoin": return bitcoinSendPreview.map { .utxo(preview: $0) }
        case "Bitcoin Cash": return bitcoinCashSendPreview.map { .utxo(preview: $0) }
        case "Bitcoin SV": return bitcoinSVSendPreview.map { .utxo(preview: $0) }
        case "Litecoin": return litecoinSendPreview.map { .utxo(preview: $0) }
        case "Dogecoin": return dogecoinSendPreview.map { .dogecoin(preview: $0) }
        case "Tron": return tronSendPreview.map { .tron(preview: $0) }
        case "Solana": return solanaSendPreview.map { .solana(preview: $0) }
        case "XRP Ledger": return xrpSendPreview.map { .xrp(preview: $0) }
        case "Stellar": return stellarSendPreview.map { .stellar(preview: $0) }
        case "Monero": return moneroSendPreview.map { .monero(preview: $0) }
        case "Cardano": return cardanoSendPreview.map { .cardano(preview: $0) }
        case "Sui": return suiSendPreview.map { .sui(preview: $0) }
        case "Aptos": return aptosSendPreview.map { .aptos(preview: $0) }
        case "TON": return tonSendPreview.map { .ton(preview: $0) }
        case "Internet Computer": return icpSendPreview.map { .icp(preview: $0) }
        case "NEAR": return nearSendPreview.map { .near(preview: $0) }
        case "Polkadot": return polkadotSendPreview.map { .polkadot(preview: $0) }
        default:
            // Every EVM chain shares one preview. Asking the registry rather
            // than listing them is what fixes Base, Polygon, Linea, Scroll,
            // Blast, Mantle and the newer rollups, which the old name match
            // never reached.
            guard coreIsEvmChain(chainName: chainName) else { return nil }
            return ethereumSendPreview.map { .ethereum(preview: $0) }
        }
    }

    func resetAll() {
        ethereumSendPreview = nil
        bitcoinSendPreview = nil
        bitcoinCashSendPreview = nil
        bitcoinSVSendPreview = nil
        litecoinSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        stellarSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        aptosSendPreview = nil
        tonSendPreview = nil
        icpSendPreview = nil
        nearSendPreview = nil
        polkadotSendPreview = nil
    }
}
