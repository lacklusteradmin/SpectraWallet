import Foundation
#if canImport(XCTest)
    import SwiftUI
    import XCTest
    @testable import Spectra
    @MainActor
    final class AppStatePlatformBridgeTests: XCTestCase {
        /// `AppState()` loads whatever is in the shared keychain-backed wallet
        /// store, which persists across runs on the simulator. Start every test
        /// from an empty store so results don't depend on what ran before.
        override func setUp() async throws {
            try await super.setUp()
            // Core-owned state is shared across every `AppState`, so reset it
            // here too. Without this a test inherits whatever the previous one
            // left, and the order tests happen to run in becomes load-bearing.
            //
            // Everything is awaited through the bridge rather than through
            // `AppState`'s fire-and-forget helpers: an un-awaited cleanup lands
            // in the middle of the test it was meant to precede.
            let state = try await WalletServiceBridge.shared.openState()
            _ = try await WalletServiceBridge.shared.applyStateCommand(
                .setFiatCurrency(fiatCurrencyCode: "USD"))
            for entry in state.addressBook {
                _ = try await WalletServiceBridge.shared.applyStateCommand(
                    .removeAddressBookEntry(id: entry.id))
            }
            for wallet in state.wallets {
                _ = try await WalletServiceBridge.shared.applyStateCommand(
                    .removeWallet(walletId: wallet.id))
            }
            _ = try await WalletServiceBridge.shared.applyTransactionCommand(.clear)
        }

        func testEditingWalletNamePreservesExistingHoldings() async {
            let store = AppState()
            let existingHolding = Coin.makeCustom(
                name: "Ethereum", symbol: "ETH", coinGeckoId: "ethereum", chainName: "Ethereum",
                tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000
            )
            let wallet = ImportedWallet(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", ethereumAddress: "0xabc123",
                selectedChain: "Ethereum", holdings: [existingHolding], includeInPortfolioTotal: false
            )
            await store.recordWallet(wallet)
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
            store.importDraft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
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
            store.importDraft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
            store.importDraft.selectedChainNamesStorage = ["Bitcoin"]
            await store.importWallet()
            XCTAssertNil(store.importError)
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets.first?.selectedChain, "Bitcoin")
            XCTAssertNotNil(store.wallets.first?.bitcoinAddress)
            XCTAssertTrue(
                AddressValidation.isValid(
                    store.wallets.first?.bitcoinAddress ?? "", kind: "bitcoin", networkMode: BitcoinNetworkMode.testnet4.rawValue)
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
            let coin = Coin.makeCustom(
                name: "Bitcoin", symbol: "BTC", coinGeckoId: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native",
                contractAddress: nil, amount: 1.25, priceUsd: 64000
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
        /// A watch-only wallet on a chain outside the old hand-written
        /// 14-chain list was dropped from the store on load. Storage is now a
        /// map, so "has any address" is a property of the wallet, not of a
        /// list someone has to remember to extend.
        func testWatchOnlyWalletOnAnyChainSurvivesPersistence() async throws {
            // One `AppState`, as the app has. Several instances sharing one
            // core is not a situation the product creates, and testing it
            // measures the harness rather than the behaviour.
            let store = AppState()
            for chainName in ["Kaspa", "Dash", "Zcash", "TON", "Internet Computer", "Bitcoin Gold", "Bittensor"] {
                await store.clearAllWallets()

                var wallet = ImportedWallet(name: "Watch \(chainName)", selectedChain: chainName)
                wallet.setAddress("address-for-\(chainName)", forChainNamed: chainName)
                await store.recordWallet(wallet)

                // Read it back the way a fresh launch does.
                let reloaded = try await WalletServiceBridge.shared.storedWallets()
                XCTAssertEqual(reloaded.count, 1, "\(chainName) wallet was dropped on load")
                XCTAssertEqual(
                    reloaded.first?.address(forChainNamed: chainName), "address-for-\(chainName)",
                    "\(chainName) address did not round-trip")
                XCTAssertEqual(reloaded.first?.selectedChain, chainName)
            }
            await store.clearAllWallets()
        }

        // ── Core-owned settings (PLAN.md Stage 0) ─────────────────────────
        //
        // The display currency is domain state: core owns it, core persists it,
        // and every front end reads the same value. Swift keeps a mirror it
        // never writes directly.

        /// Assigning to the mirror sends a command; the value that comes back
        /// is core's, normalized by core.
        func testSettingCurrencyGoesThroughCoreAndIsNormalized() async throws {
            let store = AppState()
            await store.setFiatCurrency(.eur)

            // Core is the authority; the mirror follows it.
            let state = try await WalletServiceBridge.shared.appState()
            XCTAssertEqual(state.settings.fiatCurrencyCode, "EUR")
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
        }

        /// A fresh `AppState` picks up what core has stored — the same path
        /// that makes a change made in the CLI visible in the app.
        func testCurrencySurvivesIntoAFreshAppState() async throws {
            let writer = AppState()
            await writer.setFiatCurrency(.jpy)

            let reader = AppState()
            await reader.loadCoreOwnedState()
            XCTAssertEqual(reader.selectedFiatCurrency, .jpy)
        }

        // ── Address book (PLAN.md Stage 1) ────────────────────────────────
        //
        // The list, and the rules about what may go in it, belong to core.
        // Swift sends commands and renders what comes back.

        /// Wait for fire-and-forget work to land, rather than guessing a sleep
        /// duration. A fixed sleep passes on an idle machine and fails on a
        /// loaded one, which is how a suite becomes untrustworthy.
        private func waitUntil(
            _ description: String, timeout: Duration = .seconds(5),
            _ condition: @MainActor () -> Bool
        ) async {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if condition() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            XCTFail("timed out waiting for \(description)")
        }

        private func clearAddressBook(_ store: AppState) async {
            for id in store.addressBook.map(\.id) {
                store.removeAddressBookEntry(id: id)
            }
            await waitUntil("address book to empty") { store.addressBook.isEmpty }
        }

        func testAddingAContactGoesThroughCoreAndPersists() async throws {
            let store = AppState()
            try await WalletServiceBridge.shared.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)

            store.addAddressBookEntry(
                name: "  Cold Wallet  ", address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                chainName: "Bitcoin", note: " vault ")
            await waitUntil("the contact to be saved") { store.addressBook.count == 1 }

            XCTAssertEqual(store.addressBook.count, 1)
            XCTAssertEqual(store.addressBook.first?.name, "Cold Wallet", "core trims")
            XCTAssertEqual(store.addressBook.first?.note, "vault")
            XCTAssertNil(store.addressBookError)

            // A fresh AppState sees it — same path that makes a CLI change visible.
            let reader = AppState()
            await reader.loadCoreOwnedState()
            XCTAssertEqual(reader.addressBook.count, 1)

            await clearAddressBook(store)
        }

        /// Core refuses, and says why. The UI must not silently do nothing.
        func testCoreRejectsInvalidAndDuplicateContacts() async throws {
            let store = AppState()
            try await WalletServiceBridge.shared.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)

            store.addAddressBookEntry(
                name: "Typo", address: "definitely-not-an-address", chainName: "Bitcoin")
            await waitUntil("the refusal to surface") { store.addressBookError != nil }
            XCTAssertTrue(store.addressBook.isEmpty)
            XCTAssertNotNil(store.addressBookError)

            store.addAddressBookEntry(
                name: "Cold", address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                chainName: "Bitcoin")
            await waitUntil("the valid contact to save") { store.addressBook.count == 1 }
            XCTAssertNil(store.addressBookError, "a valid entry clears the message")

            store.addAddressBookEntry(
                name: "Same again", address: "BC1QCR8TE4KR609GCAWUTMRZA0J4XV80JY8Z306FYU",
                chainName: "Bitcoin")
            await waitUntil("the duplicate to be refused") { store.addressBookError != nil }
            XCTAssertEqual(store.addressBook.count, 1, "case does not get around the duplicate check")
            XCTAssertNotNil(store.addressBookError)

            await clearAddressBook(store)
        }

        /// A pending send that later confirms must still read as confirmed
        /// after a relaunch. Persistence is asynchronous and debounced, so this
        /// polls rather than sleeping for a guessed interval.
        func testTransactionStatusChangeIsPersisted() async throws {
            let store = AppState()
            let tx = TransactionRecord(
                walletID: "w1", kind: .send, status: .pending, walletName: "W", assetName: "Bitcoin",
                symbol: "BTC", chainName: "Bitcoin", amount: 0.1, address: "bc1qexample",
                transactionHash: "0xhash-status-test")

            store.recordTransaction(tx)
            _ = await storedStatus(for: tx.id, expecting: .pending)

            store.recordTransaction(
                tx.withRebroadcastUpdate(status: .confirmed, transactionHash: tx.transactionHash))
            let persisted = await storedStatus(for: tx.id, expecting: .confirmed)
            XCTAssertEqual(persisted, .confirmed, "status change was not persisted")

            store.removeTransactions(withIDs: [tx.id])
            _ = await storedStatus(for: tx.id, expecting: nil)
        }

        /// Poll the history store until `id` reads as `expecting`, or give up.
        /// Returns whatever it last saw so the caller can assert on it.
        private func storedStatus(
            for id: UUID, expecting: TransactionStatus?, timeout: Duration = .seconds(5)
        ) async -> TransactionStatus? {
            let deadline = ContinuousClock.now + timeout
            var seen: TransactionStatus?
            while ContinuousClock.now < deadline {
                let stored = (try? await WalletServiceBridge.shared.fetchAllHistoryRecordsTyped()) ?? []
                seen = stored.compactMap { TransactionRecord(snapshot: $0.payload) }
                    .first { $0.id == id }?.status
                if seen == expecting { return seen }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return seen
        }

        func testExportsPlatformSnapshotEnvelopeWithStableFoundationModels() async throws {
            let store = AppState()
            let wallet = ImportedWallet(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", ethereumAddress: "0xabc123",
                selectedChain: "Ethereum",
                holdings: [
                    Coin.makeCustom(
                        name: "Ethereum", symbol: "ETH", coinGeckoId: "ethereum", chainName: "Ethereum",
                        tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000
                    )
                ]
            )
            await store.recordWallet(wallet)
            // Core-owned. Sent through the bridge and awaited: this test is
            // about the snapshot, not about the fire-and-forget UI entry point.
            _ = try await WalletServiceBridge.shared.applyStateCommand(
                .addAddressBookEntry(
                    id: UUID().uuidString, name: "Cold Wallet", chainName: "Ethereum",
                    address: "0x9858EfFD232B4033E47d90003D41EC34EcaEda94", note: "vault"))
            await store.loadCoreOwnedState()
            store.recordTransaction(
                TransactionRecord(
                    walletID: wallet.id, kind: .send, status: .pending, walletName: wallet.name, assetName: "Ethereum", symbol: "ETH",
                    chainName: "Ethereum", amount: 0.5, address: "0xfeedbeef", transactionHash: "0xdeadbeef"
                ))
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
