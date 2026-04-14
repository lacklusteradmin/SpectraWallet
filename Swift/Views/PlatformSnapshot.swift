import Foundation
protocol PlatformSnapshotConvertible {
    associatedtype PlatformSnapshot: Codable
    func makePlatformSnapshot() -> PlatformSnapshot
}
struct PlatformSnapshotEnvelope: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let generatedAt: Date
    let app: PlatformAppSnapshot
    init(generatedAt: Date = Date(), app: PlatformAppSnapshot) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.app = app
    }
}
struct PlatformAppSnapshot: Codable {
    let pricingProvider: String
    let fiatCurrency: String
    let walletCount: Int
    let transactionCount: Int
    let addressBookCount: Int
    let wallets: [PlatformWalletSnapshot]
    let portfolio: [PlatformAssetSnapshot]
    let transactions: [PlatformTransactionSnapshot]
    let addressBook: [PlatformAddressBookEntrySnapshot]
    let livePrices: [String: Double]
}
struct PlatformWalletSnapshot: Codable, Identifiable {
    let id: String
    let name: String
    let selectedChainID: String
    let selectedChainName: String
    let includeInPortfolioTotal: Bool
    let totalBalanceUSD: Double
    let addresses: [PlatformWalletAddressSnapshot]
    let holdings: [PlatformAssetSnapshot]
}
struct PlatformWalletAddressSnapshot: Codable, Identifiable {
    let id: String
    let chainID: String
    let chainName: String
    let address: String
}
struct PlatformAssetSnapshot: Codable, Identifiable {
    let id: String
    let name: String
    let symbol: String
    let chainID: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let marketDataId: String
    let coinGeckoId: String
    let amount: Double
    let priceUsd: Double
    let valueUSD: Double
}
struct PlatformTransactionSnapshot: Codable, Identifiable {
    let id: UUID
    let walletID: String?
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainID: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAt: Date
}
struct PlatformAddressBookEntrySnapshot: Codable, Identifiable {
    let id: UUID
    let name: String
    let chainID: String
    let chainName: String
    let address: String
    let note: String
}
