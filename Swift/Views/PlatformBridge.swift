import Foundation
private extension String {
    var platformTrimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
private extension ImportedWallet {
    func makeAddressSnapshots() -> [PlatformWalletAddressSnapshot] {
        let candidates: [(String, String?)] = [
            ("Bitcoin", bitcoinAddress), ("Bitcoin Cash", bitcoinCashAddress), ("Bitcoin SV", bitcoinSvAddress), ("Litecoin", litecoinAddress), ("Dogecoin", dogecoinAddress), ("Ethereum", ethereumAddress), ("Tron", tronAddress), ("Solana", solanaAddress), ("Stellar", stellarAddress), ("XRP Ledger", xrpAddress), ("Monero", moneroAddress), ("Cardano", cardanoAddress), ("Sui", suiAddress), ("Aptos", aptosAddress), ("TON", tonAddress), ("Internet Computer", icpAddress), ("NEAR", nearAddress), ("Polkadot", polkadotAddress)
        ]
        return candidates.compactMap { chainName, address in
            guard let resolvedAddress = address?.platformTrimmedOrNil, let chainID = WalletChainID(chainName) else { return nil }
            return PlatformWalletAddressSnapshot(
                id: "\(id):\(chainID.rawValue)", chainID: chainID.rawValue, chainName: chainID.displayName, address: resolvedAddress
            )
        }}
}
extension Coin: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformAssetSnapshot {
        let chainID = WalletChainID(chainName) ?? WalletChainID(rawValue: chainName)
        return PlatformAssetSnapshot(
            id: holdingKey, name: name, symbol: symbol, chainID: chainID.rawValue, chainName: chainID.displayName, tokenStandard: tokenStandard, contractAddress: contractAddress?.platformTrimmedOrNil, marketDataId: marketDataId, coinGeckoId: coinGeckoId, amount: amount, priceUsd: priceUsd, valueUSD: valueUSD
        )
    }
}
extension ImportedWallet: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformWalletSnapshot {
        let chainID = WalletChainID(selectedChain) ?? WalletChainID(rawValue: selectedChain)
        return PlatformWalletSnapshot(
            id: id, name: name, selectedChainID: chainID.rawValue, selectedChainName: chainID.displayName, includeInPortfolioTotal: includeInPortfolioTotal, totalBalanceUSD: totalBalance, addresses: makeAddressSnapshots(), holdings: holdings.map { $0.makePlatformSnapshot() }
        )
    }
}
extension TransactionRecord: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformTransactionSnapshot {
        let chainID = WalletChainID(chainName) ?? WalletChainID(rawValue: chainName)
        return PlatformTransactionSnapshot(
            id: id, walletID: walletID, kind: kind.rawValue, status: status.rawValue, walletName: walletName, assetName: assetName, symbol: symbol, chainID: chainID.rawValue, chainName: chainID.displayName, amount: amount, address: address, transactionHash: transactionHash?.platformTrimmedOrNil, failureReason: failureReason?.platformTrimmedOrNil, transactionHistorySource: transactionHistorySource?.platformTrimmedOrNil, createdAt: createdAt
        )
    }
}
extension AddressBookEntry: PlatformSnapshotConvertible {
    func makePlatformSnapshot() -> PlatformAddressBookEntrySnapshot {
        let chainID = WalletChainID(chainName) ?? WalletChainID(rawValue: chainName)
        return PlatformAddressBookEntrySnapshot(
            id: id, name: name, chainID: chainID.rawValue, chainName: chainID.displayName, address: address, note: note
        )
    }
}
@MainActor
extension AppState {
    func makePlatformSnapshotEnvelope(generatedAt: Date = Date()) -> PlatformSnapshotEnvelope {
        PlatformSnapshotEnvelope(
            generatedAt: generatedAt, app: PlatformAppSnapshot(
                pricingProvider: pricingProvider.rawValue, fiatCurrency: selectedFiatCurrency.rawValue, walletCount: wallets.count, transactionCount: transactions.count, addressBookCount: addressBook.count, wallets: wallets.map { $0.makePlatformSnapshot() }, portfolio: cachedPortfolio.map { $0.makePlatformSnapshot() }, transactions: transactions.map { $0.makePlatformSnapshot() }, addressBook: addressBook.map { $0.makePlatformSnapshot() }, livePrices: livePrices
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
