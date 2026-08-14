import Foundation

/// The per-chain facts an EVM send needs, sourced from the registry.
///
/// This was an enum with a case per chain and five switches over it —
/// `displayName`, `tokenTrackingChain`, `expectedChainID`, the derivation path
/// and `isEthereumFamily`. It covered 15 of the 23 EVM mainnets, so
/// `isEVMChain` answered *false* for Sei, Celo, Cronos, opBNB, zkSync Era,
/// Sonic, Berachain, Unichain, Ink and X Layer, and every EVM path skipped
/// them without saying so.
///
/// It is a struct now, built from `coreEvmChainContext`. Adding an EVM chain is
/// a registry edit and nothing here changes. The named statics are kept so the
/// existing `EVMChainContext.arbitrum` call sites read the same.
struct EVMChainContext: Equatable {
    let displayName: String
    /// EIP-155 chain id, checked against what the RPC reports before signing.
    let expectedChainID: Int
    /// BIP-44 coin type: 60 for the Ethereum family, 61 for Ethereum Classic.
    let coinType: UInt32
    let isEthereumFamily: Bool
    let isEthereumMainnet: Bool

    /// `nil` when the chain is not an EVM chain the registry knows.
    init?(chainName: String) {
        guard let info = coreEvmChainContext(chainName: chainName) else { return nil }
        displayName = info.displayName
        expectedChainID = Int(info.chainId)
        coinType = info.coinType
        isEthereumFamily = info.isEthereumFamily
        isEthereumMainnet = info.isEthereumMainnet
    }

    /// A chain the app names directly. Falls back to a context with chain id 0
    /// rather than trapping: a mismatched id fails the pre-signing check
    /// loudly, where a `fatalError` here would take the app down at launch.
    /// Resolving a derivation path used to `fatalError` on exactly this kind of
    /// miss, and it crashed every testnet.
    private static func known(_ chainName: String) -> EVMChainContext {
        EVMChainContext(chainName: chainName)
            ?? EVMChainContext(
                displayName: chainName, expectedChainID: 0, coinType: 60,
                isEthereumFamily: false, isEthereumMainnet: false)
    }

    private init(
        displayName: String, expectedChainID: Int, coinType: UInt32, isEthereumFamily: Bool,
        isEthereumMainnet: Bool
    ) {
        self.displayName = displayName
        self.expectedChainID = expectedChainID
        self.coinType = coinType
        self.isEthereumFamily = isEthereumFamily
        self.isEthereumMainnet = isEthereumMainnet
    }

    static var ethereum: EVMChainContext { known("Ethereum") }
    static var ethereumSepolia: EVMChainContext { known("Ethereum Sepolia") }
    static var ethereumHoodi: EVMChainContext { known("Ethereum Hoodi") }
    static var ethereumClassic: EVMChainContext { known("Ethereum Classic") }
    static var arbitrum: EVMChainContext { known("Arbitrum") }
    static var optimism: EVMChainContext { known("Optimism") }
    static var bnb: EVMChainContext { known("BNB Chain") }
    static var avalanche: EVMChainContext { known("Avalanche") }
    static var hyperliquid: EVMChainContext { known("Hyperliquid") }
    static var polygon: EVMChainContext { known("Polygon") }
    static var base: EVMChainContext { known("Base") }
    static var linea: EVMChainContext { known("Linea") }
    static var scroll: EVMChainContext { known("Scroll") }
    static var blast: EVMChainContext { known("Blast") }
    static var mantle: EVMChainContext { known("Mantle") }

    var tokenTrackingChain: TokenTrackingChain? { TokenTrackingChain.forChainName(displayName) }
    var defaultDerivationPath: String { derivationPath(account: 0) }
    func derivationPath(account: UInt32) -> String { "m/44\'/\(coinType)\'/\(account)\'/0/0" }
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
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
