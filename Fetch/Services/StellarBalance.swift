import Foundation

struct StellarHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum StellarBalanceService {
    static func endpointCatalog() -> [String] {
        StellarProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        StellarProvider.diagnosticsChecks()
    }
}
