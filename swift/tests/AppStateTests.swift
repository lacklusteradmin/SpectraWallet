import Foundation
#if canImport(XCTest)
import SwiftUI
import XCTest
@testable import Spectra
@MainActor
final class AppStatePlatformBridgeTests: XCTestCase {
    func testEditingWalletNamePreservesExistingHoldings() async {
        let store = AppState()
        let existingHolding = Coin(
            name: "Ethereum", symbol: "ETH", marketDataId: "1027", coinGeckoId: "ethereum", chainName: "Ethereum", tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000, mark: "E", color: .blue
        )
        let wallet = ImportedWallet(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", ethereumAddress: "0xabc123", selectedChain: "Ethereum", holdings: [existingHolding], includeInPortfolioTotal: false
        )
        store.wallets = [wallet]
        store.editingWalletID = wallet.id
        store.importDraft.configureForEditing(wallet: wallet)
        store.importDraft.walletName = "Renamed ETH"
        store.importDraft.selectedChainNamesStorage = []
        await store.importWallet()
        XCTAssertEqual(store.wallets.count, 1)
        XCTAssertEqual(store.wallets[0].name, "Renamed ETH")
        XCTAssertEqual(store.wallets[0].holdings.count, 1)
        XCTAssertEqual(store.wallets[0].holdings[0].amount, existingHolding.amount)
        XCTAssertEqual(store.wallets[0].holdings[0].priceUsd, existingHolding.priceUsd)
        XCTAssertFalse(store.wallets[0].includeInPortfolioTotal)
        XCTAssertNil(store.editingWalletID)
        XCTAssertFalse(store.isShowingWalletImporter)
        XCTAssertNil(store.importError)
    }
    func testImportingBitcoinWalletPersistsDerivedAddress() async {
        let store = AppState()
        store.importDraft.walletName = "Primary BTC"
        store.importDraft.seedPhrase = "test test test test test test test test test test test junk"
        store.importDraft.selectedChainNamesStorage = ["Bitcoin"]
        await store.importWallet()
        XCTAssertNil(store.importError)
        XCTAssertEqual(store.wallets.count, 1)
        XCTAssertEqual(store.wallets.first?.selectedChain, "Bitcoin")
        XCTAssertNotNil(store.wallets.first?.bitcoinAddress)
        XCTAssertFalse(store.wallets.first?.bitcoinAddress?.isEmpty ?? true)
    }
    func testImportingBitcoinWalletPersistsDerivedAddressOnTestnet4() async {
        let store = AppState()
        store.bitcoinNetworkMode = .testnet4
        store.importDraft.walletName = "Primary BTC Testnet4"
        store.importDraft.seedPhrase = "test test test test test test test test test test test junk"
        store.importDraft.selectedChainNamesStorage = ["Bitcoin"]
        await store.importWallet()
        XCTAssertNil(store.importError)
        XCTAssertEqual(store.wallets.count, 1)
        XCTAssertEqual(store.wallets.first?.selectedChain, "Bitcoin")
        XCTAssertNotNil(store.wallets.first?.bitcoinAddress)
        XCTAssertTrue(
            AddressValidation.isValidBitcoinAddress(store.wallets.first?.bitcoinAddress ?? "", networkMode: .testnet4)
        )
    }
    func testBitcoinDisplayNetworkNameUsesSelectedMode() {
        let store = AppState()
        store.bitcoinNetworkMode = .testnet4
        XCTAssertEqual(store.displayNetworkName(for: "Bitcoin"), "Testnet4")
        XCTAssertEqual(store.displayChainTitle(for: "Bitcoin"), "Bitcoin Testnet4")
        XCTAssertEqual(store.displayNetworkName(for: "Ethereum"), "Mainnet")
    }
    func testBitcoinWalletDisplayTitleUsesWalletSpecificNetworkMode() {
        let store = AppState()
        store.bitcoinNetworkMode = .mainnet
        let wallet = ImportedWallet(
            name: "BTC Testnet4", bitcoinNetworkMode: .testnet4, bitcoinAddress: "tb1qexample", selectedChain: "Bitcoin", holdings: []
        )
        XCTAssertEqual(store.displayNetworkName(for: wallet), "Testnet4")
        XCTAssertEqual(store.displayChainTitle(for: wallet), "Bitcoin Testnet4")
    }
    func testBitcoinTestnet4AssetsAreUnpriced() {
        let store = AppState()
        store.bitcoinNetworkMode = .testnet4
        let coin = Coin(
            name: "Bitcoin", symbol: "BTC", marketDataId: "1", coinGeckoId: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native", contractAddress: nil, amount: 1.25, priceUsd: 64000, mark: "B", color: .orange
        )
        XCTAssertEqual(store.assetIdentityKey(for: coin), "Bitcoin Testnet4|BTC")
        XCTAssertNil(store.currentPriceIfAvailable(for: coin))
        XCTAssertNil(store.currentOrFallbackPriceIfAvailable(for: coin))
        XCTAssertNil(store.currentValueIfAvailable(for: coin))
    }
    func testBitcoinTestnet4EndpointsAreAvailable() {
        XCTAssertEqual(
            AppEndpointDirectory.bitcoinEsploraBaseURLs(for: .testnet4), ["https://mempool.space/testnet4/api"]
        )
        XCTAssertEqual(
            AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(for: .testnet4), ["https://mempool.space/testnet4/api"]
        )
    }
    func testEthereumDisplayNetworkNameUsesSelectedMode() {
        let store = AppState()
        store.ethereumNetworkMode = .hoodi
        XCTAssertEqual(store.displayNetworkName(for: "Ethereum"), "Hoodi")
        XCTAssertEqual(store.displayChainTitle(for: "Ethereum"), "Ethereum Hoodi")
    }
    func testEthereumTestNetworksExposeExpectedContextsAndEndpoints() {
        XCTAssertEqual(EVMChainContext.ethereumSepolia.expectedChainID, 11_155_111)
        XCTAssertEqual(EVMChainContext.ethereumHoodi.expectedChainID, 560_048)
        XCTAssertEqual(
            EVMChainContext.ethereumSepolia.defaultRPCEndpoints, ["https://ethereum-sepolia-rpc.publicnode.com"]
        )
        XCTAssertEqual(
            EVMChainContext.ethereumHoodi.defaultRPCEndpoints, ["https://ethereum-hoodi-rpc.publicnode.com"]
        )
    }
    func testExportsPlatformSnapshotEnvelopeWithStableFoundationModels() throws {
        let store = AppState()
        let wallet = ImportedWallet(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", ethereumAddress: "0xabc123", selectedChain: "Ethereum", holdings: [
                Coin(
                    name: "Ethereum", symbol: "ETH", marketDataId: "1027", coinGeckoId: "ethereum", chainName: "Ethereum", tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000, mark: "E", color: .blue
                )
            ]
        )
        store.wallets = [wallet]
        store.addressBook = [
            AddressBookEntry(name: "Cold Wallet", chainName: "Ethereum", address: "0xdef456", note: "vault")
        ]
        store.transactions = [
            TransactionRecord(
                walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: "Ethereum", symbol: "ETH", chainName: "Ethereum", amount: 0.5, address: "0xfeedbeef", transactionHash: "0xdeadbeef"
            )
        ]
        store.livePrices = ["Ethereum|ETH": 3000]
        let snapshot = store.makePlatformSnapshotEnvelope(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.schemaVersion, PlatformSnapshotEnvelope.currentSchemaVersion)
        XCTAssertEqual(snapshot.app.walletCount, 1)
        XCTAssertEqual(snapshot.app.transactionCount, 1)
        XCTAssertEqual(snapshot.app.addressBookCount, 1)
        XCTAssertEqual(snapshot.app.wallets.first?.selectedChainID, "ethereum")
        XCTAssertEqual(snapshot.app.wallets.first?.addresses.first?.chainID, "ethereum")
        XCTAssertEqual(snapshot.app.wallets.first?.holdings.first?.valueUSD, 6000)
        XCTAssertEqual(snapshot.app.transactions.first?.chainID, "ethereum")
        XCTAssertEqual(snapshot.app.addressBook.first?.chainID, "ethereum")
        let data = try store.exportPlatformSnapshotJSON(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlatformSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.app.wallets.first?.name, "Primary ETH")
    }
}
#endif
