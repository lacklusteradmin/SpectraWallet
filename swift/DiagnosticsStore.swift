import Foundation
extension AppState {
    var bitcoinSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.bitcoinSelfTestResults }
        set { chainDiagnosticsState.bitcoinSelfTestResults = newValue }
    }
    var isRunningBitcoinSelfTests: Bool {
        get { chainDiagnosticsState.isRunningBitcoinSelfTests }
        set { chainDiagnosticsState.isRunningBitcoinSelfTests = newValue }
    }
    var bitcoinSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.bitcoinSelfTestsLastRunAt }
        set { chainDiagnosticsState.bitcoinSelfTestsLastRunAt = newValue }
    }
    var bitcoinCashSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.bitcoinCashSelfTestResults }
        set { chainDiagnosticsState.bitcoinCashSelfTestResults = newValue }
    }
    var isRunningBitcoinCashSelfTests: Bool {
        get { chainDiagnosticsState.isRunningBitcoinCashSelfTests }
        set { chainDiagnosticsState.isRunningBitcoinCashSelfTests = newValue }
    }
    var bitcoinCashSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.bitcoinCashSelfTestsLastRunAt }
        set { chainDiagnosticsState.bitcoinCashSelfTestsLastRunAt = newValue }
    }
    var bitcoinSVSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.bitcoinSVSelfTestResults }
        set { chainDiagnosticsState.bitcoinSVSelfTestResults = newValue }
    }
    var isRunningBitcoinSVSelfTests: Bool {
        get { chainDiagnosticsState.isRunningBitcoinSVSelfTests }
        set { chainDiagnosticsState.isRunningBitcoinSVSelfTests = newValue }
    }
    var bitcoinSVSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.bitcoinSVSelfTestsLastRunAt }
        set { chainDiagnosticsState.bitcoinSVSelfTestsLastRunAt = newValue }
    }
    var litecoinSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.litecoinSelfTestResults }
        set { chainDiagnosticsState.litecoinSelfTestResults = newValue }
    }
    var isRunningLitecoinSelfTests: Bool {
        get { chainDiagnosticsState.isRunningLitecoinSelfTests }
        set { chainDiagnosticsState.isRunningLitecoinSelfTests = newValue }
    }
    var litecoinSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.litecoinSelfTestsLastRunAt }
        set { chainDiagnosticsState.litecoinSelfTestsLastRunAt = newValue }
    }
    var dogecoinSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.dogecoinSelfTestResults }
        set { chainDiagnosticsState.dogecoinSelfTestResults = newValue }
    }
    var isRunningDogecoinSelfTests: Bool {
        get { chainDiagnosticsState.isRunningDogecoinSelfTests }
        set { chainDiagnosticsState.isRunningDogecoinSelfTests = newValue }
    }
    var dogecoinSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.dogecoinSelfTestsLastRunAt }
        set { chainDiagnosticsState.dogecoinSelfTestsLastRunAt = newValue }
    }
    var ethereumSelfTestResults: [ChainSelfTestResult] {
        get { chainDiagnosticsState.ethereumSelfTestResults }
        set { chainDiagnosticsState.ethereumSelfTestResults = newValue }
    }
    var isRunningEthereumSelfTests: Bool {
        get { chainDiagnosticsState.isRunningEthereumSelfTests }
        set { chainDiagnosticsState.isRunningEthereumSelfTests = newValue }
    }
    var ethereumSelfTestsLastRunAt: Date? {
        get { chainDiagnosticsState.ethereumSelfTestsLastRunAt }
        set { chainDiagnosticsState.ethereumSelfTestsLastRunAt = newValue }
    }
    var dogecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { chainDiagnosticsState.dogecoinHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.dogecoinHistoryDiagnosticsByWallet = newValue }
    }
    var dogecoinHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.dogecoinHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.dogecoinHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningDogecoinHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningDogecoinHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningDogecoinHistoryDiagnostics = newValue }
    }
    var dogecoinEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.dogecoinEndpointHealthResults }
        set { chainDiagnosticsState.dogecoinEndpointHealthResults = newValue }
    }
    var dogecoinEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.dogecoinEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.dogecoinEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingDogecoinEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingDogecoinEndpointHealth }
        set { chainDiagnosticsState.isCheckingDogecoinEndpointHealth = newValue }
    }
    var ethereumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.ethereumHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.ethereumHistoryDiagnosticsByWallet = newValue }
    }
    var ethereumHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.ethereumHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.ethereumHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningEthereumHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningEthereumHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningEthereumHistoryDiagnostics = newValue }
    }
    var ethereumEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.ethereumEndpointHealthResults }
        set { chainDiagnosticsState.ethereumEndpointHealthResults = newValue }
    }
    var ethereumEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.ethereumEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.ethereumEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingEthereumEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingEthereumEndpointHealth }
        set { chainDiagnosticsState.isCheckingEthereumEndpointHealth = newValue }
    }
    var etcHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.etcHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.etcHistoryDiagnosticsByWallet = newValue }
    }
    var etcHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.etcHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.etcHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningETCHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningETCHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningETCHistoryDiagnostics = newValue }
    }
    var etcEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.etcEndpointHealthResults }
        set { chainDiagnosticsState.etcEndpointHealthResults = newValue }
    }
    var etcEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.etcEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.etcEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingETCEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingETCEndpointHealth }
        set { chainDiagnosticsState.isCheckingETCEndpointHealth = newValue }
    }
    var arbitrumHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.arbitrumHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.arbitrumHistoryDiagnosticsByWallet = newValue }
    }
    var arbitrumHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.arbitrumHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.arbitrumHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningArbitrumHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningArbitrumHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningArbitrumHistoryDiagnostics = newValue }
    }
    var arbitrumEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.arbitrumEndpointHealthResults }
        set { chainDiagnosticsState.arbitrumEndpointHealthResults = newValue }
    }
    var arbitrumEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.arbitrumEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.arbitrumEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingArbitrumEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingArbitrumEndpointHealth }
        set { chainDiagnosticsState.isCheckingArbitrumEndpointHealth = newValue }
    }
    var optimismHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.optimismHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.optimismHistoryDiagnosticsByWallet = newValue }
    }
    var optimismHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.optimismHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.optimismHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningOptimismHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningOptimismHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningOptimismHistoryDiagnostics = newValue }
    }
    var optimismEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.optimismEndpointHealthResults }
        set { chainDiagnosticsState.optimismEndpointHealthResults = newValue }
    }
    var optimismEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.optimismEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.optimismEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingOptimismEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingOptimismEndpointHealth }
        set { chainDiagnosticsState.isCheckingOptimismEndpointHealth = newValue }
    }
    var bnbHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.bnbHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.bnbHistoryDiagnosticsByWallet = newValue }
    }
    var bnbHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bnbHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.bnbHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningBNBHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningBNBHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningBNBHistoryDiagnostics = newValue }
    }
    var bnbEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.bnbEndpointHealthResults }
        set { chainDiagnosticsState.bnbEndpointHealthResults = newValue }
    }
    var bnbEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bnbEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.bnbEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingBNBEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingBNBEndpointHealth }
        set { chainDiagnosticsState.isCheckingBNBEndpointHealth = newValue }
    }
    var avalancheHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.avalancheHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.avalancheHistoryDiagnosticsByWallet = newValue }
    }
    var avalancheHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.avalancheHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.avalancheHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningAvalancheHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningAvalancheHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningAvalancheHistoryDiagnostics = newValue }
    }
    var avalancheEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.avalancheEndpointHealthResults }
        set { chainDiagnosticsState.avalancheEndpointHealthResults = newValue }
    }
    var avalancheEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.avalancheEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.avalancheEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingAvalancheEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingAvalancheEndpointHealth }
        set { chainDiagnosticsState.isCheckingAvalancheEndpointHealth = newValue }
    }
    var hyperliquidHistoryDiagnosticsByWallet: [String: EthereumTokenTransferHistoryDiagnostics] {
        get { chainDiagnosticsState.hyperliquidHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.hyperliquidHistoryDiagnosticsByWallet = newValue }
    }
    var hyperliquidHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.hyperliquidHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.hyperliquidHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningHyperliquidHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningHyperliquidHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningHyperliquidHistoryDiagnostics = newValue }
    }
    var hyperliquidEndpointHealthResults: [EthereumEndpointHealthResult] {
        get { chainDiagnosticsState.hyperliquidEndpointHealthResults }
        set { chainDiagnosticsState.hyperliquidEndpointHealthResults = newValue }
    }
    var hyperliquidEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.hyperliquidEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.hyperliquidEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingHyperliquidEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingHyperliquidEndpointHealth }
        set { chainDiagnosticsState.isCheckingHyperliquidEndpointHealth = newValue }
    }
    var tronHistoryDiagnosticsByWallet: [String: TronHistoryDiagnostics] {
        get { chainDiagnosticsState.tronHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.tronHistoryDiagnosticsByWallet = newValue }
    }
    var tronHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.tronHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.tronHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningTronHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningTronHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningTronHistoryDiagnostics = newValue }
    }
    var tronEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.tronEndpointHealthResults }
        set { chainDiagnosticsState.tronEndpointHealthResults = newValue }
    }
    var tronEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.tronEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.tronEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingTronEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingTronEndpointHealth }
        set { chainDiagnosticsState.isCheckingTronEndpointHealth = newValue }
    }
    var solanaHistoryDiagnosticsByWallet: [String: SolanaHistoryDiagnostics] {
        get { chainDiagnosticsState.solanaHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.solanaHistoryDiagnosticsByWallet = newValue }
    }
    var solanaHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.solanaHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.solanaHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningSolanaHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningSolanaHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningSolanaHistoryDiagnostics = newValue }
    }
    var solanaEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.solanaEndpointHealthResults }
        set { chainDiagnosticsState.solanaEndpointHealthResults = newValue }
    }
    var solanaEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.solanaEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.solanaEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingSolanaEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingSolanaEndpointHealth }
        set { chainDiagnosticsState.isCheckingSolanaEndpointHealth = newValue }
    }
    var xrpHistoryDiagnosticsByWallet: [String: XrpHistoryDiagnostics] {
        get { chainDiagnosticsState.xrpHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.xrpHistoryDiagnosticsByWallet = newValue }
    }
    var xrpHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.xrpHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.xrpHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningXRPHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningXRPHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningXRPHistoryDiagnostics = newValue }
    }
    var xrpEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.xrpEndpointHealthResults }
        set { chainDiagnosticsState.xrpEndpointHealthResults = newValue }
    }
    var xrpEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.xrpEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.xrpEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingXRPEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingXRPEndpointHealth }
        set { chainDiagnosticsState.isCheckingXRPEndpointHealth = newValue }
    }
    var stellarHistoryDiagnosticsByWallet: [String: StellarHistoryDiagnostics] {
        get { chainDiagnosticsState.stellarHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.stellarHistoryDiagnosticsByWallet = newValue }
    }
    var stellarHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.stellarHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.stellarHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningStellarHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningStellarHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningStellarHistoryDiagnostics = newValue }
    }
    var stellarEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.stellarEndpointHealthResults }
        set { chainDiagnosticsState.stellarEndpointHealthResults = newValue }
    }
    var stellarEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.stellarEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.stellarEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingStellarEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingStellarEndpointHealth }
        set { chainDiagnosticsState.isCheckingStellarEndpointHealth = newValue }
    }
    var moneroHistoryDiagnosticsByWallet: [String: MoneroHistoryDiagnostics] {
        get { chainDiagnosticsState.moneroHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.moneroHistoryDiagnosticsByWallet = newValue }
    }
    var moneroHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.moneroHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.moneroHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningMoneroHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningMoneroHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningMoneroHistoryDiagnostics = newValue }
    }
    var moneroEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.moneroEndpointHealthResults }
        set { chainDiagnosticsState.moneroEndpointHealthResults = newValue }
    }
    var moneroEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.moneroEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.moneroEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingMoneroEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingMoneroEndpointHealth }
        set { chainDiagnosticsState.isCheckingMoneroEndpointHealth = newValue }
    }
    var suiHistoryDiagnosticsByWallet: [String: SuiHistoryDiagnostics] {
        get { chainDiagnosticsState.suiHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.suiHistoryDiagnosticsByWallet = newValue }
    }
    var suiHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.suiHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.suiHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningSuiHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningSuiHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningSuiHistoryDiagnostics = newValue }
    }
    var suiEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.suiEndpointHealthResults }
        set { chainDiagnosticsState.suiEndpointHealthResults = newValue }
    }
    var suiEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.suiEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.suiEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingSuiEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingSuiEndpointHealth }
        set { chainDiagnosticsState.isCheckingSuiEndpointHealth = newValue }
    }
    var aptosHistoryDiagnosticsByWallet: [String: AptosHistoryDiagnostics] {
        get { chainDiagnosticsState.aptosHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.aptosHistoryDiagnosticsByWallet = newValue }
    }
    var aptosHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.aptosHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.aptosHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningAptosHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningAptosHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningAptosHistoryDiagnostics = newValue }
    }
    var aptosEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.aptosEndpointHealthResults }
        set { chainDiagnosticsState.aptosEndpointHealthResults = newValue }
    }
    var aptosEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.aptosEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.aptosEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingAptosEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingAptosEndpointHealth }
        set { chainDiagnosticsState.isCheckingAptosEndpointHealth = newValue }
    }
    var tonHistoryDiagnosticsByWallet: [String: TonHistoryDiagnostics] {
        get { chainDiagnosticsState.tonHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.tonHistoryDiagnosticsByWallet = newValue }
    }
    var tonHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.tonHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.tonHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningTONHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningTONHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningTONHistoryDiagnostics = newValue }
    }
    var tonEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.tonEndpointHealthResults }
        set { chainDiagnosticsState.tonEndpointHealthResults = newValue }
    }
    var tonEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.tonEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.tonEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingTONEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingTONEndpointHealth }
        set { chainDiagnosticsState.isCheckingTONEndpointHealth = newValue }
    }
    var icpHistoryDiagnosticsByWallet: [String: IcpHistoryDiagnostics] {
        get { chainDiagnosticsState.icpHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.icpHistoryDiagnosticsByWallet = newValue }
    }
    var icpHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.icpHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.icpHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningICPHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningICPHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningICPHistoryDiagnostics = newValue }
    }
    var icpEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.icpEndpointHealthResults }
        set { chainDiagnosticsState.icpEndpointHealthResults = newValue }
    }
    var icpEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.icpEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.icpEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingICPEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingICPEndpointHealth }
        set { chainDiagnosticsState.isCheckingICPEndpointHealth = newValue }
    }
    var nearHistoryDiagnosticsByWallet: [String: NearHistoryDiagnostics] {
        get { chainDiagnosticsState.nearHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.nearHistoryDiagnosticsByWallet = newValue }
    }
    var nearHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.nearHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.nearHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningNearHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningNearHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningNearHistoryDiagnostics = newValue }
    }
    var nearEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.nearEndpointHealthResults }
        set { chainDiagnosticsState.nearEndpointHealthResults = newValue }
    }
    var nearEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.nearEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.nearEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingNearEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingNearEndpointHealth }
        set { chainDiagnosticsState.isCheckingNearEndpointHealth = newValue }
    }
    var polkadotHistoryDiagnosticsByWallet: [String: PolkadotHistoryDiagnostics] {
        get { chainDiagnosticsState.polkadotHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.polkadotHistoryDiagnosticsByWallet = newValue }
    }
    var polkadotHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.polkadotHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.polkadotHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningPolkadotHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningPolkadotHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningPolkadotHistoryDiagnostics = newValue }
    }
    var polkadotEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.polkadotEndpointHealthResults }
        set { chainDiagnosticsState.polkadotEndpointHealthResults = newValue }
    }
    var polkadotEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.polkadotEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.polkadotEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingPolkadotEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingPolkadotEndpointHealth }
        set { chainDiagnosticsState.isCheckingPolkadotEndpointHealth = newValue }
    }
    var cardanoHistoryDiagnosticsByWallet: [String: CardanoHistoryDiagnostics] {
        get { chainDiagnosticsState.cardanoHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.cardanoHistoryDiagnosticsByWallet = newValue }
    }
    var cardanoHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.cardanoHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.cardanoHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningCardanoHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningCardanoHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningCardanoHistoryDiagnostics = newValue }
    }
    var cardanoEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.cardanoEndpointHealthResults }
        set { chainDiagnosticsState.cardanoEndpointHealthResults = newValue }
    }
    var cardanoEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.cardanoEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.cardanoEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingCardanoEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingCardanoEndpointHealth }
        set { chainDiagnosticsState.isCheckingCardanoEndpointHealth = newValue }
    }
    var bitcoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { chainDiagnosticsState.bitcoinHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.bitcoinHistoryDiagnosticsByWallet = newValue }
    }
    var bitcoinHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningBitcoinHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningBitcoinHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningBitcoinHistoryDiagnostics = newValue }
    }
    var bitcoinEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.bitcoinEndpointHealthResults }
        set { chainDiagnosticsState.bitcoinEndpointHealthResults = newValue }
    }
    var bitcoinEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingBitcoinEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingBitcoinEndpointHealth }
        set { chainDiagnosticsState.isCheckingBitcoinEndpointHealth = newValue }
    }
    var bitcoinCashHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { chainDiagnosticsState.bitcoinCashHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.bitcoinCashHistoryDiagnosticsByWallet = newValue }
    }
    var bitcoinCashHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinCashHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinCashHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningBitcoinCashHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningBitcoinCashHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningBitcoinCashHistoryDiagnostics = newValue }
    }
    var bitcoinCashEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.bitcoinCashEndpointHealthResults }
        set { chainDiagnosticsState.bitcoinCashEndpointHealthResults = newValue }
    }
    var bitcoinCashEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinCashEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinCashEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingBitcoinCashEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingBitcoinCashEndpointHealth }
        set { chainDiagnosticsState.isCheckingBitcoinCashEndpointHealth = newValue }
    }
    var bitcoinSVHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { chainDiagnosticsState.bitcoinSVHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.bitcoinSVHistoryDiagnosticsByWallet = newValue }
    }
    var bitcoinSVHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinSVHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinSVHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningBitcoinSVHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningBitcoinSVHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningBitcoinSVHistoryDiagnostics = newValue }
    }
    var bitcoinSVEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.bitcoinSVEndpointHealthResults }
        set { chainDiagnosticsState.bitcoinSVEndpointHealthResults = newValue }
    }
    var bitcoinSVEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.bitcoinSVEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.bitcoinSVEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingBitcoinSVEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingBitcoinSVEndpointHealth }
        set { chainDiagnosticsState.isCheckingBitcoinSVEndpointHealth = newValue }
    }
    var litecoinHistoryDiagnosticsByWallet: [String: BitcoinHistoryDiagnostics] {
        get { chainDiagnosticsState.litecoinHistoryDiagnosticsByWallet }
        set { chainDiagnosticsState.litecoinHistoryDiagnosticsByWallet = newValue }
    }
    var litecoinHistoryDiagnosticsLastUpdatedAt: Date? {
        get { chainDiagnosticsState.litecoinHistoryDiagnosticsLastUpdatedAt }
        set { chainDiagnosticsState.litecoinHistoryDiagnosticsLastUpdatedAt = newValue }
    }
    var isRunningLitecoinHistoryDiagnostics: Bool {
        get { chainDiagnosticsState.isRunningLitecoinHistoryDiagnostics }
        set { chainDiagnosticsState.isRunningLitecoinHistoryDiagnostics = newValue }
    }
    var litecoinEndpointHealthResults: [BitcoinEndpointHealthResult] {
        get { chainDiagnosticsState.litecoinEndpointHealthResults }
        set { chainDiagnosticsState.litecoinEndpointHealthResults = newValue }
    }
    var litecoinEndpointHealthLastUpdatedAt: Date? {
        get { chainDiagnosticsState.litecoinEndpointHealthLastUpdatedAt }
        set { chainDiagnosticsState.litecoinEndpointHealthLastUpdatedAt = newValue }
    }
    var isCheckingLitecoinEndpointHealth: Bool {
        get { chainDiagnosticsState.isCheckingLitecoinEndpointHealth }
        set { chainDiagnosticsState.isCheckingLitecoinEndpointHealth = newValue }
    }
    var lastImportedDiagnosticsBundle: DiagnosticsBundlePayload? {
        get { chainDiagnosticsState.lastImportedDiagnosticsBundle }
        set { chainDiagnosticsState.lastImportedDiagnosticsBundle = newValue }
    }
    var chainDegradedMessages: [String: String] {
        get { diagnostics.chainDegradedMessages }
        set { diagnostics.chainDegradedMessages = newValue }
    }
    var chainDegradedMessagesByChainID: [WalletChainID: String] {
        get { diagnostics.chainDegradedMessagesByChainID }
        set { diagnostics.chainDegradedMessagesByChainID = newValue }
    }
    var lastGoodChainSyncByName: [String: Date] {
        get { diagnostics.lastGoodChainSyncByName }
        set { diagnostics.lastGoodChainSyncByName = newValue }
    }
    var lastGoodChainSyncByChainID: [WalletChainID: Date] {
        get { diagnostics.lastGoodChainSyncByChainID }
        set { diagnostics.lastGoodChainSyncByChainID = newValue }
    }
    var operationalLogs: [OperationalLogEvent] {
        get { diagnostics.operationalLogs }
        set { diagnostics.operationalLogs = newValue }
    }
    var chainDegradedBanners: [ChainDegradedBanner] { diagnostics.chainDegradedBanners }
    func markChainDegraded(_ chainName: String, detail: String) { diagnostics.markChainDegraded(chainName, detail: detail) }
}

enum ChainSelfTests {
    static func run(_ chainKey: String) -> [ChainSelfTestResult] {
        selfTestsRunChain(chainKey: chainKey)
    }
    static func runAll() -> [String: [ChainSelfTestResult]] {
        selfTestsRunAll()
    }
}
extension ChainSelfTestOutcome {
    var displayMessage: String {
        switch self {
        case .validAddressAccepted: return AppLocalization.string("Valid address accepted.")
        case .validAddressRejected: return AppLocalization.string("Valid address was rejected.")
        case .invalidAddressRejected: return AppLocalization.string("Invalid address rejected.")
        case .invalidAddressUnexpectedlyAccepted: return AppLocalization.string("Invalid address was unexpectedly accepted.")
        case .derivationFailed: return AppLocalization.string("Seed derivation failed.")
        case .derivedAddressValid: return AppLocalization.string("Derived address is valid.")
        case .derivedAddressInvalid: return AppLocalization.string("Derived address is invalid.")
        case .normalizationSuccess: return AppLocalization.string("Address normalization succeeded.")
        case .normalizationFailure: return AppLocalization.string("Address normalization failed.")
        case .checksumMutationRejected: return AppLocalization.string("Checksum mutation rejected.")
        case .checksumMutationAccepted: return AppLocalization.string("Checksum mutation was unexpectedly accepted.")
        case .custom(let text): return text
        }
    }
}
extension ChainSelfTestResult {
    var displayMessage: String { outcome.displayMessage }
}
