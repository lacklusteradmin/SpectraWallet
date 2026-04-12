import Foundation
import WalletCore

struct TONHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct TONJettonBalanceSnapshot: Equatable {
    let masterAddress: String
    let walletAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
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
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        TONProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        TONProvider.diagnosticsChecks()
    }

    static func normalizeJettonMasterAddress(_ address: String) -> String {
        canonicalAddressIdentifier(address)
    }

    private static func canonicalAddressIdentifier(_ address: String?) -> String {
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        if let anyAddress = AnyAddress(string: trimmed, coin: .ton) {
            return anyAddress.description
        }
        return trimmed
    }
}
