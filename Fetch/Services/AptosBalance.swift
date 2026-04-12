import Foundation

struct AptosHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct AptosTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
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
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        AptosProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AptosProvider.diagnosticsChecks()
    }
}
