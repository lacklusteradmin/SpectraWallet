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
    /// Core-assigned identifier. A string, not a `UUID`: the id is opaque to
    /// the platform and core is free to mint it however it likes.
    let id: String
    let name: String
    let chainID: String
    let chainName: String
    let address: String
    let note: String
}
private extension String {
    var platformTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
private extension ImportedWallet {
    func makeAddressSnapshots() -> [PlatformWalletAddressSnapshot] {
        let candidates: [(String, String?)] = [
            ("Bitcoin", bitcoinAddress), ("Bitcoin Cash", bitcoinCashAddress), ("Bitcoin SV", bitcoinSvAddress),
            ("Litecoin", litecoinAddress), ("Dogecoin", dogecoinAddress), ("Ethereum", ethereumAddress), ("Tron", tronAddress),
            ("Solana", solanaAddress), ("Stellar", stellarAddress), ("XRP Ledger", xrpAddress), ("Monero", moneroAddress),
            ("Cardano", cardanoAddress), ("Sui", suiAddress), ("Aptos", aptosAddress), ("TON", tonAddress),
            ("Internet Computer", icpAddress), ("NEAR", nearAddress), ("Polkadot", polkadotAddress),
        ]
        return candidates.compactMap { chainName, address in
            guard let resolvedAddress = address?.platformTrimmedOrNil, let chainID = WalletChainID(chainName) else { return nil }
            return PlatformWalletAddressSnapshot(
                id: "\(id):\(chainID.rawValue)", chainID: chainID.rawValue, chainName: chainID.displayName, address: resolvedAddress
            )
        }
    }
}
extension Coin: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformAssetSnapshot {
        let chainID = WalletChainID.resolved(chainName)
        return PlatformAssetSnapshot(
            id: holdingKey, name: name, symbol: symbol, chainID: chainID.rawValue, chainName: chainID.displayName,
            tokenStandard: tokenStandard, contractAddress: contractAddress?.platformTrimmedOrNil,
            coinGeckoId: coinGeckoId, amount: amount, priceUsd: priceUsd, valueUSD: valueUSD
        )
    }
}
extension ImportedWallet: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformWalletSnapshot {
        let chainID = WalletChainID.resolved(selectedChain)
        return PlatformWalletSnapshot(
            id: id, name: name, selectedChainID: chainID.rawValue, selectedChainName: chainID.displayName,
            includeInPortfolioTotal: includeInPortfolioTotal, totalBalanceUSD: totalBalance, addresses: makeAddressSnapshots(),
            holdings: holdings.map { $0.makePlatformSnapshot() }
        )
    }
}
extension TransactionRecord: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformTransactionSnapshot {
        let chainID = WalletChainID.resolved(chainName)
        return PlatformTransactionSnapshot(
            id: id, walletID: walletID, kind: kind.rawValue, status: status.rawValue, walletName: walletName, assetName: assetName,
            symbol: symbol, chainID: chainID.rawValue, chainName: chainID.displayName, amount: amount, address: address,
            transactionHash: transactionHash?.platformTrimmedOrNil, failureReason: failureReason?.platformTrimmedOrNil,
            transactionHistorySource: transactionHistorySource?.platformTrimmedOrNil, createdAt: createdAt
        )
    }
}
extension AddressBookEntry: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformAddressBookEntrySnapshot {
        let chainID = WalletChainID.resolved(chainName)
        return PlatformAddressBookEntrySnapshot(
            id: id, name: name, chainID: chainID.rawValue, chainName: chainID.displayName, address: address, note: note
        )
    }
}
@MainActor
extension AppState {
    func makePlatformSnapshotEnvelope(generatedAt: Date = Date()) -> PlatformSnapshotEnvelope {
        PlatformSnapshotEnvelope(
            generatedAt: generatedAt,
            app: PlatformAppSnapshot(
                pricingProvider: pricingProvider.rawValue, fiatCurrency: selectedFiatCurrency.rawValue, walletCount: wallets.count,
                transactionCount: transactions.count, addressBookCount: addressBook.count,
                wallets: wallets.map { $0.makePlatformSnapshot() }, portfolio: cachedPortfolio.map { $0.makePlatformSnapshot() },
                transactions: transactions.map { $0.makePlatformSnapshot() }, addressBook: addressBook.map { $0.makePlatformSnapshot() },
                livePrices: livePrices
            )
        )
    }
    func exportPlatformSnapshotJSON(generatedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(makePlatformSnapshotEnvelope(generatedAt: generatedAt))
    }
}
