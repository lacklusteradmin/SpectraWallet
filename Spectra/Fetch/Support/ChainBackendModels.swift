import Foundation

enum ChainIntegrationState: String {
    case live = "Live"
    case planned = "Planned"
}

protocol ChainWalletBackend {
    var chainName: String { get }
    var supportedSymbols: [String] { get }
    var integrationState: ChainIntegrationState { get }
    var supportsSeedImport: Bool { get }
    var supportsBalanceRefresh: Bool { get }
    var supportsReceiveAddress: Bool { get }
    var supportsSend: Bool { get }
}

struct BitcoinChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin"
    let supportedSymbols = ["BTC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BitcoinCashChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin Cash"
    let supportedSymbols = ["BCH"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BitcoinSVChainBackend: ChainWalletBackend {
    let chainName = "Bitcoin SV"
    let supportedSymbols = ["BSV"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct LitecoinChainBackend: ChainWalletBackend {
    let chainName = "Litecoin"
    let supportedSymbols = ["LTC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct EthereumChainBackend: ChainWalletBackend {
    let chainName = "Ethereum"
    let supportedSymbols = ["ETH", "USDT", "USDC", "DAI"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct ArbitrumChainBackend: ChainWalletBackend {
    let chainName = "Arbitrum"
    let supportedSymbols = ["ETH", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct OptimismChainBackend: ChainWalletBackend {
    let chainName = "Optimism"
    let supportedSymbols = ["ETH", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct EthereumClassicChainBackend: ChainWalletBackend {
    let chainName = "Ethereum Classic"
    let supportedSymbols = ["ETC"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct DogecoinChainBackend: ChainWalletBackend {
    let chainName = "Dogecoin"
    let supportedSymbols = ["DOGE"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct BNBChainBackend: ChainWalletBackend {
    let chainName = "BNB Chain"
    let supportedSymbols = ["BNB"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct AvalancheChainBackend: ChainWalletBackend {
    let chainName = "Avalanche"
    let supportedSymbols = ["AVAX"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct HyperliquidChainBackend: ChainWalletBackend {
    let chainName = "Hyperliquid"
    let supportedSymbols = ["HYPE", "Tracked ERC-20s"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct TronChainBackend: ChainWalletBackend {
    let chainName = "Tron"
    let supportedSymbols = ["TRX", "USDT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct SolanaChainBackend: ChainWalletBackend {
    let chainName = "Solana"
    let supportedSymbols = ["SOL"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct XRPChainBackend: ChainWalletBackend {
    let chainName = "XRP Ledger"
    let supportedSymbols = ["XRP"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct MoneroChainBackend: ChainWalletBackend {
    let chainName = "Monero"
    let supportedSymbols = ["XMR"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct CardanoChainBackend: ChainWalletBackend {
    let chainName = "Cardano"
    let supportedSymbols = ["ADA"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct SuiChainBackend: ChainWalletBackend {
    let chainName = "Sui"
    let supportedSymbols = ["SUI"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct AptosChainBackend: ChainWalletBackend {
    let chainName = "Aptos"
    let supportedSymbols = ["APT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct TONChainBackend: ChainWalletBackend {
    let chainName = "TON"
    let supportedSymbols = ["TON", "Tracked Jettons"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct ICPChainBackend: ChainWalletBackend {
    let chainName = "Internet Computer"
    let supportedSymbols = ["ICP"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct NearChainBackend: ChainWalletBackend {
    let chainName = "NEAR"
    let supportedSymbols = ["NEAR"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct PolkadotChainBackend: ChainWalletBackend {
    let chainName = "Polkadot"
    let supportedSymbols = ["DOT"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct StellarChainBackend: ChainWalletBackend {
    let chainName = "Stellar"
    let supportedSymbols = ["XLM"]
    let integrationState: ChainIntegrationState = .live
    let supportsSeedImport = true
    let supportsBalanceRefresh = true
    let supportsReceiveAddress = true
    let supportsSend = true
}

struct PlannedChainBackend: ChainWalletBackend {
    let chainName: String
    let supportedSymbols: [String]
    let integrationState: ChainIntegrationState = .planned
    let supportsSeedImport = true
    let supportsBalanceRefresh = false
    let supportsReceiveAddress = false
    let supportsSend = false
}

enum AppChainID: String, CaseIterable, Identifiable {
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    case tron
    case solana
    case cardano
    case xrp
    case stellar
    case monero
    case sui
    case aptos
    case ton
    case icp
    case near
    case polkadot

    var id: String { rawValue }
}

struct AppChainDescriptor: Identifiable {
    let id: AppChainID
    let chainName: String
    let shortLabel: String
    let nativeSymbol: String
    let searchKeywords: [String]
    let supportsDiagnostics: Bool
    let supportsEndpointCatalog: Bool
    let isEVM: Bool

    var title: String {
        String(
            format: AppLocalization.string("%@ Diagnostics"),
            locale: AppLocalization.locale,
            chainName
        )
    }

    init(
        id: AppChainID,
        chainName: String,
        title: String,
        shortLabel: String,
        nativeSymbol: String,
        searchKeywords: [String],
        supportsDiagnostics: Bool,
        supportsEndpointCatalog: Bool,
        isEVM: Bool
    ) {
        self.id = id
        self.chainName = chainName
        self.shortLabel = shortLabel
        self.nativeSymbol = nativeSymbol
        self.searchKeywords = searchKeywords
        self.supportsDiagnostics = supportsDiagnostics
        self.supportsEndpointCatalog = supportsEndpointCatalog
        self.isEVM = isEVM
    }
}

struct ChainBroadcastProviderOption: Identifiable, Hashable {
    let id: String
    let title: String
}
