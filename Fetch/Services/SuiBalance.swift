import Foundation

struct SuiHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct SuiTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
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
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        SuiProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        SuiProvider.diagnosticsChecks()
    }
}
