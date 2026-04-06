import Foundation

struct DiagnosticsEnvironmentMetadata: Codable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let pricingProvider: String
    let selectedFiatCurrency: String
    let walletCount: Int
    let transactionCount: Int
}

struct DiagnosticsBundlePayload: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let environment: DiagnosticsEnvironmentMetadata
    let chainDegradedMessages: [String: String]
    let bitcoinDiagnosticsJSON: String
    let bitcoinSVDiagnosticsJSON: String?
    let litecoinDiagnosticsJSON: String?
    let ethereumDiagnosticsJSON: String
    let arbitrumDiagnosticsJSON: String?
    let optimismDiagnosticsJSON: String?
    let bnbDiagnosticsJSON: String?
    let avalancheDiagnosticsJSON: String?
    let hyperliquidDiagnosticsJSON: String?
    let tronDiagnosticsJSON: String?
    let solanaDiagnosticsJSON: String?
    let stellarDiagnosticsJSON: String?
}

struct EthereumEndpointHealthResult: Identifiable {
    let id = UUID()
    let label: String
    let endpoint: String
    let reachable: Bool
    let statusCode: Int?
    let detail: String
}

struct BitcoinHistoryDiagnostics: Identifiable {
    let id = UUID()
    let walletID: UUID
    let identifier: String
    let sourceUsed: String
    let transactionCount: Int
    let nextCursor: String?
    let error: String?
}

struct BitcoinEndpointHealthResult: Identifiable {
    let id = UUID()
    let endpoint: String
    let reachable: Bool
    let statusCode: Int?
    let detail: String
}
