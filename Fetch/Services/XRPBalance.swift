import Foundation

struct XRPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum XRPBalanceService {
    static func endpointCatalog() -> [String] {
        XRPProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        endpointCatalog().map { base in
            (endpoint: base, probeURL: base)
        }
    }
}
