import Foundation
import Combine

final class WalletChainDiagnosticsState: ObservableObject {
    @Published var dogecoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningDogecoinSelfTests: Bool = false
    @Published var dogecoinSelfTestsLastRunAt: Date?
    @Published var bitcoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinSelfTests: Bool = false
    @Published var bitcoinSelfTestsLastRunAt: Date?
    @Published var bitcoinCashSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinCashSelfTests: Bool = false
    @Published var bitcoinCashSelfTestsLastRunAt: Date?
    @Published var bitcoinSVSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningBitcoinSVSelfTests: Bool = false
    @Published var bitcoinSVSelfTestsLastRunAt: Date?
    @Published var litecoinSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningLitecoinSelfTests: Bool = false
    @Published var litecoinSelfTestsLastRunAt: Date?
    @Published var dogecoinHistoryDiagnosticsByWallet: [UUID: BitcoinHistoryDiagnostics] = [:]
    @Published var dogecoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningDogecoinHistoryDiagnostics: Bool = false
    @Published var dogecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var dogecoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingDogecoinEndpointHealth: Bool = false
    @Published var ethereumSelfTestResults: [ChainSelfTestResult] = []
    @Published var isRunningEthereumSelfTests: Bool = false
    @Published var ethereumSelfTestsLastRunAt: Date?
    @Published var ethereumHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var ethereumHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningEthereumHistoryDiagnostics: Bool = false
    @Published var ethereumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var ethereumEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingEthereumEndpointHealth: Bool = false
    @Published var etcHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var etcHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningETCHistoryDiagnostics: Bool = false
    @Published var etcEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var etcEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingETCEndpointHealth: Bool = false
    @Published var arbitrumHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var arbitrumHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningArbitrumHistoryDiagnostics: Bool = false
    @Published var arbitrumEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var arbitrumEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingArbitrumEndpointHealth: Bool = false
    @Published var optimismHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var optimismHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningOptimismHistoryDiagnostics: Bool = false
    @Published var optimismEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var optimismEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingOptimismEndpointHealth: Bool = false
    @Published var bnbHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var bnbHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBNBHistoryDiagnostics: Bool = false
    @Published var bnbEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var bnbEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBNBEndpointHealth: Bool = false
    @Published var avalancheHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var avalancheHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningAvalancheHistoryDiagnostics: Bool = false
    @Published var avalancheEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var avalancheEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingAvalancheEndpointHealth: Bool = false
    @Published var hyperliquidHistoryDiagnosticsByWallet: [UUID: EthereumTokenTransferHistoryDiagnostics] = [:]
    @Published var hyperliquidHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningHyperliquidHistoryDiagnostics: Bool = false
    @Published var hyperliquidEndpointHealthResults: [EthereumEndpointHealthResult] = []
    @Published var hyperliquidEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingHyperliquidEndpointHealth: Bool = false
    @Published var tronHistoryDiagnosticsByWallet: [UUID: TronHistoryDiagnostics] = [:]
    @Published var tronHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningTronHistoryDiagnostics: Bool = false
    @Published var tronEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var tronEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingTronEndpointHealth: Bool = false
    @Published var solanaHistoryDiagnosticsByWallet: [UUID: SolanaHistoryDiagnostics] = [:]
    @Published var solanaHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningSolanaHistoryDiagnostics: Bool = false
    @Published var solanaEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var solanaEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingSolanaEndpointHealth: Bool = false
    @Published var xrpHistoryDiagnosticsByWallet: [UUID: XRPHistoryDiagnostics] = [:]
    @Published var xrpHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningXRPHistoryDiagnostics: Bool = false
    @Published var xrpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var xrpEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingXRPEndpointHealth: Bool = false
    @Published var stellarHistoryDiagnosticsByWallet: [UUID: StellarHistoryDiagnostics] = [:]
    @Published var stellarHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningStellarHistoryDiagnostics: Bool = false
    @Published var stellarEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var stellarEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingStellarEndpointHealth: Bool = false
    @Published var moneroHistoryDiagnosticsByWallet: [UUID: MoneroHistoryDiagnostics] = [:]
    @Published var moneroHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningMoneroHistoryDiagnostics: Bool = false
    @Published var moneroEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var moneroEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingMoneroEndpointHealth: Bool = false
    @Published var suiHistoryDiagnosticsByWallet: [UUID: SuiHistoryDiagnostics] = [:]
    @Published var suiHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningSuiHistoryDiagnostics: Bool = false
    @Published var suiEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var suiEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingSuiEndpointHealth: Bool = false
    @Published var aptosHistoryDiagnosticsByWallet: [UUID: AptosHistoryDiagnostics] = [:]
    @Published var aptosHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningAptosHistoryDiagnostics: Bool = false
    @Published var aptosEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var aptosEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingAptosEndpointHealth: Bool = false
    @Published var tonHistoryDiagnosticsByWallet: [UUID: TONHistoryDiagnostics] = [:]
    @Published var tonHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningTONHistoryDiagnostics: Bool = false
    @Published var tonEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var tonEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingTONEndpointHealth: Bool = false
    @Published var icpHistoryDiagnosticsByWallet: [UUID: ICPHistoryDiagnostics] = [:]
    @Published var icpHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningICPHistoryDiagnostics: Bool = false
    @Published var icpEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var icpEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingICPEndpointHealth: Bool = false
    @Published var nearHistoryDiagnosticsByWallet: [UUID: NearHistoryDiagnostics] = [:]
    @Published var nearHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningNearHistoryDiagnostics: Bool = false
    @Published var nearEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var nearEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingNearEndpointHealth: Bool = false
    @Published var polkadotHistoryDiagnosticsByWallet: [UUID: PolkadotHistoryDiagnostics] = [:]
    @Published var polkadotHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningPolkadotHistoryDiagnostics: Bool = false
    @Published var polkadotEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var polkadotEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingPolkadotEndpointHealth: Bool = false
    @Published var cardanoHistoryDiagnosticsByWallet: [UUID: CardanoHistoryDiagnostics] = [:]
    @Published var cardanoHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningCardanoHistoryDiagnostics: Bool = false
    @Published var cardanoEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var cardanoEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingCardanoEndpointHealth: Bool = false
    @Published var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload?
    @Published var bitcoinHistoryDiagnosticsByWallet: [UUID: BitcoinHistoryDiagnostics] = [:]
    @Published var bitcoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinHistoryDiagnostics: Bool = false
    @Published var bitcoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinEndpointHealth: Bool = false
    @Published var bitcoinCashHistoryDiagnosticsByWallet: [UUID: BitcoinHistoryDiagnostics] = [:]
    @Published var bitcoinCashHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinCashHistoryDiagnostics: Bool = false
    @Published var bitcoinCashEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinCashEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinCashEndpointHealth: Bool = false
    @Published var bitcoinSVHistoryDiagnosticsByWallet: [UUID: BitcoinHistoryDiagnostics] = [:]
    @Published var bitcoinSVHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningBitcoinSVHistoryDiagnostics: Bool = false
    @Published var bitcoinSVEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var bitcoinSVEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingBitcoinSVEndpointHealth: Bool = false
    @Published var litecoinHistoryDiagnosticsByWallet: [UUID: BitcoinHistoryDiagnostics] = [:]
    @Published var litecoinHistoryDiagnosticsLastUpdatedAt: Date?
    @Published var isRunningLitecoinHistoryDiagnostics: Bool = false
    @Published var litecoinEndpointHealthResults: [BitcoinEndpointHealthResult] = []
    @Published var litecoinEndpointHealthLastUpdatedAt: Date?
    @Published var isCheckingLitecoinEndpointHealth: Bool = false
}
