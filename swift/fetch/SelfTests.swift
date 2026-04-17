import Foundation

private enum SelfTestsRustBridge {
    static func run(chainKey: String) -> [ChainSelfTestResult] {
        selfTestsRunChain(chainKey: chainKey)
    }

    static func runAll() -> [String: [ChainSelfTestResult]] {
        selfTestsRunAll()
    }
}

enum DogecoinChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Dogecoin") }
}

enum EthereumChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Ethereum") }
}

@MainActor enum BitcoinSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin") } }
@MainActor enum BitcoinCashSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin Cash") } }
@MainActor enum LitecoinSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Litecoin") } }
@MainActor enum BitcoinSVSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Bitcoin SV") } }
@MainActor enum CardanoSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Cardano") } }
@MainActor enum SolanaChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Solana") } }
@MainActor enum StellarSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Stellar") } }
@MainActor enum XRPChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "XRP") } }
@MainActor enum TronChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Tron") } }
@MainActor enum SuiChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Sui") } }
@MainActor enum AptosChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Aptos") } }
@MainActor enum TONChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "TON") } }
@MainActor enum ICPChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Internet Computer") } }
@MainActor enum NearChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "NEAR") } }
@MainActor enum PolkadotChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Polkadot") } }
@MainActor enum MoneroChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Monero") } }
@MainActor enum BNBChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "BNB Chain") } }
@MainActor enum AvalancheChainSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Avalanche") } }
@MainActor enum EthereumClassicSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Ethereum Classic") } }
@MainActor enum HyperliquidSelfTestSuite { static func runAll() -> [ChainSelfTestResult] { SelfTestsRustBridge.run(chainKey: "Hyperliquid") } }

@MainActor
enum AllChainsSelfTestSuite {
    static func runAll() -> [String: [ChainSelfTestResult]] { SelfTestsRustBridge.runAll() }
}
