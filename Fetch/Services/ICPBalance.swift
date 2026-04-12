import Foundation

struct ICPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum ICPBalanceService {
    static func endpointCatalog() -> [String] {
        ICPProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        ICPProvider.diagnosticsChecks()
    }
}
