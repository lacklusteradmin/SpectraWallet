import Foundation

struct PolkadotHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum PolkadotBalanceService {
    static func endpointCatalog() -> [String] {
        PolkadotProvider.endpointCatalog()
    }

    static func sidecarEndpointCatalog() -> [String] {
        PolkadotProvider.sidecarBaseURLs
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        PolkadotProvider.diagnosticsChecks()
    }
}
