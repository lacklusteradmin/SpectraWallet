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
            // The selected network is core-owned and persists, so a test that
            // switches to a testnet would otherwise leave every later test on
            // it. Selecting a family's mainnet clears the entry.
            for chainID in ["bitcoin", "ethereum", "dogecoin"] {
                _ = try await WalletServiceBridge.shared.applyStateCommand(
                    .selectNetworkChain(chainId: chainID))
            }
            _ = try await WalletServiceBridge.shared.applyTransactionCommand(.clear)
        }

        /// Every EVM mainnet resolves an address, so no wallet is dropped
        /// before the balance refresh can fetch anything.
        ///
        /// `resolvedAddress` tested `seedDerivationChain` before `isEVMChain`.
        /// Core answers the former for *every* chain in the catalog — it
        /// returns `Option` but never `None` — so the EVM branch was
        /// unreachable, and the table it fell into has no EVM entry. All 23
        /// EVM mainnets resolved to `nil`; the refresh engine drops a wallet
        /// with no address, so their balances never loaded at all.
        ///
        /// Asserted over `Chain.mainnets` rather than a list written here, so
        /// a new EVM chain is covered by adding it to the catalog.
        func testEveryEVMMainnetResolvesAWalletAddress() async {
            let store = AppState()
            store.importDraft.walletName = "EVM Coverage"
            store.importDraft.setSeedPhraseForTesting(
                "test test test test test test test test test test test junk")
            store.importDraft.selectedChainNamesStorage = ["Ethereum"]
            await store.importWallet()
            XCTAssertNil(store.importError)
            guard let wallet = store.wallets.first else { return XCTFail("no wallet") }

            let evmMainnets = Chain.mainnets.filter(\.isEVM)
            XCTAssertGreaterThan(evmMainnets.count, 20, "the catalog lost its EVM chains")
            var unresolved: [String] = []
            for chain in evmMainnets
            where store.resolvedAddress(for: wallet, chainName: chain.displayName) == nil {
                unresolved.append(chain.displayName)
            }
            XCTAssertEqual(unresolved, [], "no address, so the refresh engine drops the wallet")
        }

        /// A rename lands after a delete without bringing the wallet back.
        ///
        /// The rename write is detached, so it can arrive after the user has
        /// deleted the wallet. It used to be an upsert, so it did bring it
        /// back — and in the test suite it resurrected a wallet across the
        /// `setUp` clear, which is how this was found: an import test two
        /// files down would occasionally see two wallets instead of one.
        func testARenameThatLandsAfterADeleteDoesNotResurrectTheWallet() async throws {
            let store = AppState()
            let wallet = ImportedWallet(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Probe",
                addresses: ["Ethereum": "0xabc123"],
                selectedChain: "Ethereum", holdings: [], includeInPortfolioTotal: false
            )
            await store.recordWallet(wallet)
            store.editingWalletID = wallet.id
            store.importDraft.configureForEditing(wallet: wallet)
            store.importDraft.walletName = "Probe Renamed"
            store.importDraft.selectedChainNamesStorage = []
            await store.importWallet()

            // The delete wins the race: it is awaited, the rename is not.
            let state = try await WalletServiceBridge.shared.openState()
            for w in state.wallets {
                _ = try await WalletServiceBridge.shared.applyStateCommand(
                    .removeWallet(walletId: w.id))
            }
            try await Task.sleep(nanoseconds: 800_000_000)
            let after = try await WalletServiceBridge.shared.storedWallets()
            XCTAssertEqual(
                after.count, 0,
                "the detached rename resurrected \(after.map(\.id))")
        }

        func testEditingWalletNamePreservesExistingHoldings() async {
            let store = AppState()
            let existingHolding = Coin.makeCustom(
                name: "Ethereum", symbol: "ETH", coinGeckoId: "ethereum", chainName: "Ethereum",
                tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000
            )
            let wallet = ImportedWallet(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", addresses: ["Ethereum": "0xabc123"],
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
        /// Import derives against the *mainnet* chain whatever network is
        /// selected, and the testnet address is re-derived for display — see
        /// `PLAN.md`. So the stored address is mainnet-format and the resolved
        /// one is not.
        ///
        /// This test used to assert the stored address was valid *testnet4*,
        /// and passed — because it said so through the validator's
        /// `networkMode` argument, which nothing read. The `kind` had always
        /// been what decided, and it said `"bitcoin"`. Deleting the dead
        /// argument is what exposed it.
        func testImportingBitcoinWalletOnTestnet4StoresTheMainnetDerivedAddress() async {
            let store = AppState()
            store.selectNetworkChain("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            store.importDraft.walletName = "Primary BTC Testnet4"
            store.importDraft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
            store.importDraft.selectedChainNamesStorage = ["Bitcoin"]
            await store.importWallet()
            XCTAssertNil(store.importError)
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets.first?.selectedChain, "Bitcoin")
            let stored = store.wallets.first?.bitcoinAddress ?? ""
            XCTAssertTrue(
                AddressValidation.isValid(stored, kind: (Chain(id: "bitcoin")?.addressValidationKind ?? "")),
                "storage holds the mainnet-derived address"
            )
            // What the user is shown is derived for the selected network.
            let shown = store.wallets.first.flatMap { store.resolvedNetworkModeAddress(for: $0, family: "bitcoin", fallback: .bitcoin) } ?? ""
            XCTAssertTrue(
                AddressValidation.isValid(
                    shown, kind: Chain(id: "bitcoin-testnet-4")?.addressValidationKind ?? ""),
                "the displayed address is testnet4, got \(shown)"
            )
        }
        func testBitcoinDisplayNetworkNameUsesSelectedMode() async {
            let store = AppState()
            store.selectNetworkChain("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(store.displayNetworkName(for: "Bitcoin"), "Testnet4")
            XCTAssertEqual(store.displayChainTitle(for: "Bitcoin"), "Bitcoin Testnet4")
            XCTAssertEqual(store.displayNetworkName(for: "Ethereum"), "Mainnet")
        }
        /// A wallet carries its own network, so it can differ from the app's.
        func testBitcoinWalletDisplayTitleUsesWalletSpecificNetwork() {
            let store = AppState()
            let wallet = ImportedWallet(
                name: "BTC Testnet4", networkChainID: "bitcoin-testnet-4",
                addresses: ["Bitcoin": "tb1qexample"], selectedChain: "Bitcoin", holdings: []
            )
            XCTAssertEqual(store.displayNetworkName(for: wallet), "Testnet4")
            XCTAssertEqual(store.displayChainTitle(for: wallet), "Bitcoin Testnet4")
        }
        /// Async because the selection round-trips through core: assigning the
        /// mirror sends `SelectNetworkChain` and the unpriced set is adopted
        /// when the new state comes back. Deriving it in Swift instead would
        /// put a second copy of the rule here, which is what this whole slice
        /// removed.
        func testBitcoinTestnet4AssetsAreUnpriced() async {
            let store = AppState()
            store.selectNetworkChain("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            let coin = Coin.makeCustom(
                name: "Bitcoin", symbol: "BTC", coinGeckoId: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native",
                contractAddress: nil, amount: 1.25, priceUsd: 64000
            )
            XCTAssertEqual(store.assetIdentityKey(for: coin), "Bitcoin Testnet4|BTC")
            XCTAssertNil(store.currentPriceIfAvailable(for: coin))
            XCTAssertNil(store.currentValueIfAvailable(for: coin))
        }
        /// A holding nobody quoted is left out of the total and counted, not
        /// folded in at zero and not at an invented dollar.
        ///
        /// USDC and USDT used to be pinned to exactly $1.00 — in the price
        /// fetchers, where the constant was inserted *before* the market quote
        /// and made it unreachable, and again in the display fallback. A wallet
        /// that cannot see a depeg is most wrong exactly when it matters.
        func testUnquotedHoldingsAreExcludedFromTheTotalAndCounted() async {
            let store = AppState()
            await store.awaitPendingCoreStateWrites()
            let priced = Coin.makeCustom(
                name: "Ethereum", symbol: "ETH", coinGeckoId: "ethereum", chainName: "Ethereum",
                tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 0)
            let stablecoin = Coin.makeCustom(
                name: "USD Coin", symbol: "USDC", coinGeckoId: "usd-coin", chainName: "Ethereum",
                tokenStandard: "ERC-20", contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                amount: 100, priceUsd: 0)
            store.livePrices[store.activePriceKey(for: priced)] = 3000

            let quoted = store.quotedTotal(for: [priced, stablecoin])
            XCTAssertEqual(quoted.total, 6000, accuracy: 0.0001, "the priced holding is all the total covers")
            XCTAssertEqual(quoted.unpricedCount, 1, "the unquoted stablecoin is counted, not valued")
            XCTAssertFalse(quoted.isComplete)
            XCTAssertNil(
                store.currentPriceIfAvailable(for: stablecoin),
                "no feed answered for USDC, so there is no price to show")
        }

        /// A wallet imported while the launch load is reading core is not
        /// dropped by the adoption.
        ///
        /// The adoption was a wholesale replace with nothing ordering it
        /// against the optimistic write the command helpers make first. The
        /// read returns a snapshot taken before the import; replacing the
        /// projection with it lost the wallet — and `updateWalletsIfPresent`
        /// starts *from* the projection, so a balance refresh could not bring
        /// it back. It stayed gone until the next launch.
        func testAdoptionKeepsAWalletWrittenWhileTheReadWasInFlight() {
            struct Row: Equatable {
                let id: String
            }
            let storedSnapshot = [Row(id: "a"), Row(id: "b")]

            // Nothing wrote while the read was out: adopt core's list whole.
            XCTAssertEqual(
                mergeAdoptedProjection(stored: storedSnapshot, keepingLocal: [], identity: \.id),
                storedSnapshot)

            // An import landed mid-read. Core's snapshot predates it, so the
            // merge keeps it and adds everything core has that it lacks.
            let merged = mergeAdoptedProjection(
                stored: storedSnapshot, keepingLocal: [Row(id: "c")], identity: \.id)
            XCTAssertEqual(merged.map(\.id), ["c", "a", "b"])

            // A local entry core also has is not duplicated, and the local
            // version is the one kept — it is newer by construction.
            let overlapping = mergeAdoptedProjection(
                stored: storedSnapshot, keepingLocal: [Row(id: "a")], identity: \.id)
            XCTAssertEqual(overlapping.map(\.id), ["a", "b"])
        }

        func testBitcoinTestnet4EndpointsAreAvailable() {
            XCTAssertEqual(
                AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainID: "bitcoin-testnet-4"),
                ["https://mempool.space/testnet4/api"]
            )
            XCTAssertEqual(
                AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(forChainID: "bitcoin-testnet-4"),
                ["https://mempool.space/testnet4/api"]
            )
        }
        func testEthereumDisplayNetworkNameUsesSelectedMode() async {
            let store = AppState()
            store.selectNetworkChain("ethereum-hoodi")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(store.displayNetworkName(for: "Ethereum"), "Hoodi")
            XCTAssertEqual(store.displayChainTitle(for: "Ethereum"), "Ethereum Hoodi")
        }
        /// Every EVM chain gets the EVM address hint.
        ///
        /// Thirteen were named in the arm and the other ten mainnets — Sei,
        /// Celo, Cronos, opBNB, zkSync Era, Sonic, Berachain, Unichain, Ink and
        /// X Layer — fell to "Enter an address for the selected chain." The arm
        /// reads `Chain.isEVM` now. Asserted against the generic fallback rather
        /// than against the English text so the test does not depend on which
        /// locale it runs in.
        func testEveryEVMChainGetsAFormatSpecificAddressHint() {
            let store = AppState()
            // Kaspa has no arm of its own and never had one, so its message is
            // the fallback by construction.
            let generic = store.addressBookAddressValidationMessage(for: "", chainName: "Kaspa")
            let evmMainnets = Chain.mainnets.filter(\.isEVM)
            XCTAssertGreaterThan(evmMainnets.count, 13, "the arm used to name thirteen")
            for chain in evmMainnets {
                XCTAssertNotEqual(
                    store.addressBookAddressValidationMessage(for: "", chainName: chain.displayName),
                    generic,
                    "\(chain.displayName) still gets the generic hint")
                XCTAssertNotEqual(
                    store.addressBookAddressValidationMessage(for: "nope", chainName: chain.displayName),
                    store.addressBookAddressValidationMessage(for: "nope", chainName: "Kaspa"),
                    "\(chain.displayName) still gets the generic invalid-address hint")
            }
        }
        func testEthereumTestNetworksExposeExpectedContextsAndEndpoints() {
            let sepolia = EVMChainContext(chainName: "Ethereum Sepolia")
            let hoodi = EVMChainContext(chainName: "Ethereum Hoodi")
            XCTAssertEqual(sepolia?.expectedChainID, 11_155_111)
            XCTAssertEqual(hoodi?.expectedChainID, 560_048)
            XCTAssertEqual(sepolia?.defaultRPCEndpoints, ["https://ethereum-sepolia-rpc.publicnode.com"])
            XCTAssertEqual(hoodi?.defaultRPCEndpoints, ["https://ethereum-hoodi-rpc.publicnode.com"])
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
            // The transaction needs a wallet that exists. `loadPersistedState`
            // ends by pruning transactions whose wallet is not active, so one
            // recorded against a made-up id survives only while no load runs —
            // which is why this passed against a `walletID` of "w1" until the
            // load started doing real work.
            let wallet = ImportedWallet(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "W",
                addresses: ["Bitcoin": "bc1qexample"], selectedChain: "Bitcoin")
            await store.recordWallet(wallet)
            let tx = TransactionRecord(
                walletID: wallet.id, kind: .send, status: .pending, walletName: "W",
                assetName: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", amount: 0.1,
                address: "bc1qexample", transactionHash: "0xhash-status-test")

            store.recordTransaction(tx)
            _ = await storedStatus(for: tx.id, expecting: .pending)

            store.recordTransaction(
                tx.withRebroadcastUpdate(status: .confirmed, transactionHash: tx.transactionHash))
            let persisted = await storedStatus(for: tx.id, expecting: .confirmed)
            XCTAssertEqual(persisted, .confirmed, "status change was not persisted")

            store.removeTransactions(withIDs: [tx.id])
            _ = await storedStatus(for: tx.id, expecting: nil)
            await store.removeWallet(id: wallet.id)
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

        /// A setting survives into a fresh `AppState`, and core bounds it.
        ///
        /// Nothing covered the settings blob this replaces: it was written and
        /// read by one file on one platform, so "does a setting persist" had no
        /// assertion on either side of the boundary.
        func testSettingsGoThroughCoreAndSurviveIntoAFreshAppState() async throws {
            let store = AppState()
            store.etherscanAPIKey = "  ABC123  "
            store.bitcoinStopGap = 9_999
            store.preferences.useLargeMovementNotifications = false
            await store.awaitPendingCoreStateWrites()
            await waitUntil("core to bound the stop gap") { store.bitcoinStopGap == 200 }

            XCTAssertEqual(store.etherscanAPIKey, "ABC123", "core trims, and the mirror adopts")
            XCTAssertEqual(store.bitcoinStopGap, 200, "9999 is outside 1...200")

            let fresh = AppState()
            await waitUntil("a fresh store to load the settings") { fresh.etherscanAPIKey == "ABC123" }
            XCTAssertEqual(fresh.bitcoinStopGap, 200)
            XCTAssertFalse(fresh.preferences.useLargeMovementNotifications)

            store.etherscanAPIKey = ""
            store.bitcoinStopGap = 10
            store.preferences.useLargeMovementNotifications = true
            await store.awaitPendingCoreStateWrites()
        }

    }
#endif

@MainActor
final class DiagnosticsBundleCoverageTests: XCTestCase {
    /// Every chain the bundle reports on must be a chain the registry knows.
    ///
    /// The bundle list and the `diagnosticsJSON(for:)` switch are two lists
    /// that have to agree. Collapsing the old 23 wrapper functions onto them
    /// silently dropped Tron and Solana — they have their own JSON builders and
    /// did not match the shape the other 22 shared — and nothing failed,
    /// because a missing case just returns nil. This is the check that would
    /// have caught it.
    func testEveryBundledChainResolvesAndProducesADistinctEntry() {
        let names = AppState.diagnosticsBundleChainNames
        XCTAssertEqual(Set(names).count, names.count, "duplicate chain in the bundle list")
        for name in names {
            XCTAssertTrue(
                Chain(displayName: name).map { $0.isEVM || !$0.addressSlot.isEmpty } ?? false,
                "\(name) is not a chain the registry knows")
        }
    }

    func testEveryBundledChainHasACaseInTheSwitch() {
        let store = AppState()
        // With no wallets every chain yields an empty-but-present document, so
        // a `nil` here means the switch has no case for that chain at all.
        for name in AppState.diagnosticsBundleChainNames {
            XCTAssertNotNil(
                store.diagnosticsJSON(for: name), "no diagnosticsJSON case for \(name)")
        }
    }
}
