import Foundation
#if canImport(XCTest)
    import SwiftUI
    import XCTest
    @testable import Spectra
    @MainActor
    final class AppStatePlatformBridgeTests: IsolatedAppStateTestCase {
        func testUnpinningAllAssetsPersistsAcrossAsyncBridge() async throws {
            let service = try WalletService(endpoints: [])
            let path = directory
                .appendingPathComponent("pins-\(UUID().uuidString).sqlite").path
            let initial = try await service.openState(databasePath: path)
            XCTAssertEqual(initial.settings.pinnedDashboardTokenIds.count, 4)
            for tokenId in initial.settings.pinnedDashboardTokenIds {
                _ = try await service.applyStateCommand(
                    command: .setDashboardAssetPinned(tokenId: tokenId, isPinned: false))
            }
            let reopened = try WalletService(endpoints: [])
            let saved = try await reopened.openState(databasePath: path)
            XCTAssertTrue(saved.settings.pinnedDashboardTokenIds.isEmpty)
            let options = try await reopened.dashboardPinOptions()
            XCTAssertTrue(options.allSatisfy { !$0.isPinned })
            let reset = try await reopened.applyStateCommand(command: .resetPinnedDashboardAssets)
            XCTAssertEqual(reset.state.settings.pinnedDashboardTokenIds, initial.settings.pinnedDashboardTokenIds)
        }

        /// The pending sweep is reached through the app's one refresh entry
        /// point; this holds its async export to a runtime across the binding.
        func testOwnedPendingMaintenanceCrossesTheAsyncBridge() async throws {
            let service = try WalletService(endpoints: [])
            let path = directory
                .appendingPathComponent("pending-\(UUID().uuidString).sqlite").path
            _ = try await service.openState(databasePath: path)
            let result = try await service.refreshPendingTransactions()
            XCTAssertTrue(result.chains.isEmpty)
            XCTAssertTrue(result.changes.isEmpty)
            XCTAssertTrue(result.failures.isEmpty)
        }

        func testManualStatusRecheckRefusesMissingTransactionAcrossAsyncBridge() async throws {
            let id = UUID().uuidString
            do {
                _ = try await bridge.recheckTransactionStatus(id: id)
                XCTFail("a missing transaction must not produce a successful status")
            } catch {
                XCTAssertTrue(String(describing: error).contains("Transaction not found"))
            }
            let store = makeState()
            let message = await store.retryUTXOTransactionStatus(for: id)
            XCTAssertTrue(message.contains("Transaction not found"))
        }

        /// A wallet answers for the chains it was imported for and for no
        /// others.
        ///
        /// The resolver used to derive on demand, so it answered for every
        /// chain in the catalog from any wallet's seed — including chains the
        /// user never imported, which is not an address that wallet has. It
        /// reads what core stored now: the EVM family shares one slot, so an
        /// Ethereum wallet still answers for all 23 EVM mainnets, and a
        /// Solana wallet is not asked to produce a Bitcoin address.
        func testAWalletAnswersForItsOwnChainsAndNoOthers() async {
            let store = makeState()
            store.walletImport.draft.walletName = "Catalog Coverage"
            store.walletImport.draft.setSeedPhraseForTesting(
                "test test test test test test test test test test test junk")
            store.walletImport.draft.selectedChainNamesStorage = ["Ethereum"]
            await store.importWallet()
            XCTAssertNil(store.walletImport.error)
            guard let wallet = store.wallets.first else { return XCTFail("no wallet") }

            let resolved = Chain.mainnets.filter {
                store.resolvedAddress(for: wallet, chainName: $0.displayName) != nil
            }
            XCTAssertEqual(
                Set(resolved), Set(Chain.mainnets.filter(\.isEVM)),
                "an Ethereum wallet answers for the EVM family — Ethereum Classic included, "
                    + "which has its own slot and one key — and for nothing else")
        }

        func testARenameThatLandsAfterADeleteDoesNotResurrectTheWallet() async throws {
            let store = makeState()
            let wallet = WalletView(
                id: UUID(), name: "Probe",
                addresses: ["Ethereum": "0xabc123"], familyName: "Ethereum")
            try await store.seedWalletForTesting(wallet)
            let removed = await store.removeWallet(id: wallet.id)
            XCTAssertTrue(removed)
            await store.renameWallet(id: wallet.id, to: "Late rename")
            let after = try await bridge.portfolioSnapshot().wallets
            XCTAssertTrue(after.isEmpty)
            XCTAssertTrue(store.wallets.isEmpty)
        }

        func testEditingWalletNamePreservesExistingHoldings() async throws {
            let store = makeState()
            let existingHolding = Coin.makeCustom(
                name: "Ethereum", symbol: "ETH", coingeckoId: "ethereum", chainName: "Ethereum",
                tokenStandard: "Native", contractAddress: nil, amount: 2, priceUsd: 3000
            )
            let wallet = WalletView(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", addresses: ["Ethereum": "0xabc123"],
                familyName: "Ethereum", holdings: [existingHolding], includeInPortfolioTotal: false
            )
            try await store.seedWalletForTesting(wallet)
            store.beginEditingWallet(wallet)
            store.walletImport.draft.walletName = "Renamed ETH"
            store.walletImport.draft.selectedChainNamesStorage = []
            await store.importWallet()
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets[0].name, "Renamed ETH")
            XCTAssertEqual(store.wallets[0].holdings.count, 1)
            XCTAssertEqual(store.wallets[0].holdings[0].amount, existingHolding.amount)
            XCTAssertEqual(store.wallets[0].holdings[0].priceUsd, existingHolding.priceUsd)
            XCTAssertFalse(store.wallets[0].includeInPortfolioTotal)
            XCTAssertNil(store.walletImport.editingWalletId)
            XCTAssertFalse(store.walletImport.isPresented)
            XCTAssertNil(store.walletImport.error)
        }
        func testImportingBitcoinWalletPersistsDerivedAddress() async {
            let store = makeState()
            store.walletImport.draft.walletName = "Primary BTC"
            store.walletImport.draft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
            store.walletImport.draft.selectedChainNamesStorage = ["Bitcoin"]
            await store.importWallet()
            XCTAssertNil(store.walletImport.error)
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets.first?.familyName, "Bitcoin")
            XCTAssertNotNil(store.wallets.first?.address(forChainNamed: "Bitcoin"))
            XCTAssertFalse(store.wallets.first?.address(forChainNamed: "Bitcoin")?.isEmpty ?? true)
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
            let store = makeState()
            store.selectChainForFamily("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            store.walletImport.draft.walletName = "Primary BTC Testnet4"
            store.walletImport.draft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
            store.walletImport.draft.selectedChainNamesStorage = ["Bitcoin"]
            await store.importWallet()
            XCTAssertNil(store.walletImport.error)
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets.first?.familyName, "Bitcoin")
            let stored = store.wallets.first?.address(forChainNamed: "Bitcoin") ?? ""
            XCTAssertTrue(
                AddressValidation.isValid(stored, kind: (Chain(id: "bitcoin")?.addressValidationKind ?? "")),
                "storage holds the mainnet-derived address"
            )
            // What the user is shown is the address core stored for the network
            // the wallet is on. It used to be re-derived from the seed on every
            // read, so a sealed wallet showed the mainnet address on testnet.
            let shown = store.wallets.first.flatMap { store.resolvedAddress(for: $0, chainName: "Bitcoin") } ?? ""
            XCTAssertTrue(
                AddressValidation.isValid(
                    shown, kind: Chain(id: "bitcoin-testnet-4")?.addressValidationKind ?? ""),
                "the displayed address is testnet4, got \(shown)"
            )
            XCTAssertNotEqual(shown, stored, "the two networks are different keys")
            let wallet = store.wallets[0]
            XCTAssertEqual(wallet.seedDerivationPaths.path(for: .bitcoin), "m/84'/0'/0'/0/0")
            XCTAssertEqual(wallet.seedDerivationPaths.path(for: .bitcoinTestnet4), "m/84'/1'/0'/0/0")
            XCTAssertEqual(wallet.holdings.first?.symbol, "tBTC")
        }
        func testBitcoinDisplayNetworkNameUsesSelectedMode() async {
            let store = makeState()
            store.selectChainForFamily("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(store.selectedNetworkTitle(forFamilyName: "Bitcoin"), "Bitcoin Testnet4")
        }
        /// A wallet carries its own network, so it can differ from the app's.
        func testBitcoinWalletDisplayTitleUsesWalletSpecificNetwork() {
            let wallet = WalletView(
                name: "BTC Testnet4", selectedChainId: "bitcoin-testnet-4",
                addresses: ["Bitcoin": "tb1qexample"], familyName: "Bitcoin", holdings: []
            )
            XCTAssertEqual(wallet.networkTitle, "Bitcoin Testnet4")
        }
        func testHistoricalNetworkTitleIgnoresCurrentNetworkSelection() async {
            let store = makeState()
            let transaction = TransactionRecord(id: UUID().uuidString, kind: .send, status: .confirmed,
                walletName: "Historical", assetDisplayName: "Ethereum", symbol: "ETH",
                chainName: "Ethereum Sepolia", amount: 1, address: "0x1111111111111111111111111111111111111111")
            store.selectChainForFamily("ethereum-hoodi")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(transaction.chainName, "Ethereum Sepolia")
        }

        func testOwnedMovementAndStakingRefusalAcrossAsyncBinding() async throws {
            let movement = try await bridge.evaluatePortfolioMovement(appIsActive: false)
            XCTAssertNil(movement)
            do {
                _ = try await bridge.fetchStakingValidators(chainId: "bitcoin")
                XCTFail("Unsupported staking must refuse before network access")
            } catch { }
            do {
                _ = try await bridge.receiveAddress(walletId: "missing", chainId: "ethereum", reserve: true)
                XCTFail("A missing wallet must not produce an address or a message-as-address")
            } catch { }
        }

        /// Async because the selection round-trips through core: assigning the
        /// mirror sends `SelectChainForFamily` and the unpriced set is adopted
        /// when the new state comes back. Deriving it in Swift instead would
        /// put a second copy of the rule here, which is what this whole slice
        /// removed.
        func testBitcoinTestnet4AssetsAreUnpriced() async {
            let store = makeState()
            store.selectChainForFamily("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            let coin = Coin.makeCustom(
                name: "Bitcoin", symbol: "BTC", coingeckoId: "", chainName: "Bitcoin Testnet4", tokenStandard: "Native",
                contractAddress: nil, amount: 1.25, priceUsd: 64000
            )
            XCTAssertEqual(coin.holdingKey, "bitcoin-testnet-4:native")
            store.livePrices[coin.holdingKey] = 64000
            XCTAssertNil(store.amounts.currentPriceIfAvailable(for: coin))
            XCTAssertNil(store.amounts.currentValueIfAvailable(for: coin))
            let mainnet = Coin.makeCustom(
                name: "Bitcoin", symbol: "BTC", coingeckoId: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native",
                contractAddress: nil, amount: 1, priceUsd: 0)
            store.livePrices[mainnet.holdingKey] = 64000
            XCTAssertEqual(store.amounts.currentPriceIfAvailable(for: mainnet), 64000)
        }
        func testMissingFiatRateIsUnavailableAndPartialTotalsAreLabelled() async {
            let store = makeState()
            await store.awaitPendingCoreStateWrites()
            let before = store.selectedFiatCurrency
            await store.setFiatCurrency(.eur)
            store.fiatRatesFromUSD = [:]
            XCTAssertNil(store.amounts.formattedFiatAmountIfAvailable(fromUSD: 500))
            XCTAssertEqual(store.amounts.formattedFiatAmount(fromUSD: 500), "—")
            XCTAssertEqual(store.amounts.formattedQuotedTotal(nil), "—")
            let incomplete = QuotedTotal(total: 6000, unpricedCount: 1, fiatTotal: 5400)
            XCTAssertTrue(store.amounts.formattedQuotedTotal(incomplete).contains(AppLocalization.format("%lld without a price", 1)))
            await store.setFiatCurrency(before)
        }

        func testBitcoinTestnet4EndpointsAreAvailable() {
            XCTAssertEqual(
                AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainId: "bitcoin-testnet-4"),
                ["https://mempool.space/testnet4/api"]
            )
        }
        func testEthereumDisplayNetworkNameUsesSelectedMode() async {
            let store = makeState()
            store.selectChainForFamily("ethereum-hoodi")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(store.selectedNetworkTitle(forFamilyName: "Ethereum"), "Ethereum Hoodi")
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
            let store = makeState()
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
        func testEndpointTokenCapabilitiesHaveLocalizedLabels() throws {
            let endpoint = "https://eth.blockscout.com"
            let summary = try XCTUnwrap(AppEndpointDirectory.tagSummary(for: endpoint))
            XCTAssertTrue(summary.hasPrefix("blockscout"))
            for capability in ["history", "token-history"] {
                let key = "endpointCapability.\(capability)"
                let label = AppLocalization.string(key)
                XCTAssertNotEqual(label, key)
                XCTAssertTrue(summary.contains(label), capability)
            }
            for capability in ["token-discovery", "token-balance"] {
                let key = "endpointCapability.\(capability)"
                let label = AppLocalization.string(key)
                XCTAssertNotEqual(label, key)
                XCTAssertFalse(summary.contains(label), capability)
            }
            let node = try XCTUnwrap(AppEndpointDirectory.tagSummary(for: "https://ethereum-rpc.publicnode.com"))
            XCTAssertTrue(node.contains(AppLocalization.string("endpointCapability.token-balance")))
            XCTAssertFalse(node.contains(AppLocalization.string("endpointCapability.token-history")))
        }
        /// What the app reads about Ethereum's test networks: that the
        /// registry knows them as EVM testnets of Ethereum, and the RPC
        /// endpoints the catalog gives each. Their EIP-155 ids were asserted
        /// here through `EVMChainContext`, which the app no longer has; core's
        /// `evm_chains_carry_their_eip155_ids` checks them where they live.
        func testEthereumTestNetworksExposeExpectedContextsAndEndpoints() {
            for name in ["Ethereum Sepolia", "Ethereum Hoodi"] {
                let chain = Chain(displayName: name)
                XCTAssertEqual(chain?.isEVM, true, name)
                XCTAssertEqual(chain?.isTestnet, true, name)
                XCTAssertEqual(chain?.mainnetCounterpart, .ethereum, name)
            }
            XCTAssertEqual(AppEndpointDirectory.evmRPCEndpoints(for: "ethereum-sepolia"), ["https://ethereum-sepolia-rpc.publicnode.com"])
            XCTAssertEqual(AppEndpointDirectory.evmRPCEndpoints(for: "ethereum-hoodi"), ["https://ethereum-hoodi-rpc.publicnode.com"])
            let groups = AppEndpointDirectory.groupedSettingsEntries(for: "ethereum")
            XCTAssertTrue(groups.contains { $0.chainId == "ethereum-sepolia" && $0.title == "Ethereum Sepolia" })
            XCTAssertEqual(AppEndpointDirectory.groupedSettingsEntries(for: "ethereum-sepolia").map(\.chainId), ["ethereum-sepolia"])
        }
        /// A watch-only wallet on a chain outside the old hand-written
        /// 14-chain list was dropped from the store on load. Storage is now a
        /// map, so "has any address" is a property of the wallet, not of a
        /// list someone has to remember to extend.
        func testWatchOnlyWalletOnAnyChainSurvivesPersistence() async throws {
            // One `AppState`, as the app has. Several instances sharing one
            // core is not a situation the product creates, and testing it
            // measures the harness rather than the behaviour.
            let store = makeState()
            for chainName in ["Kaspa", "Dash", "Zcash", "TON", "Internet Computer", "Bitcoin Gold", "Bittensor"] {
                try await store.clearWalletsForTesting()

                var wallet = WalletView(name: "Watch \(chainName)", familyName: chainName)
                wallet.setAddress("address-for-\(chainName)", forChainNamed: chainName)
                try await store.seedWalletForTesting(wallet)

                // Read it back the way a fresh launch does.
                let reloaded = try await bridge.portfolioSnapshot().wallets
                XCTAssertEqual(reloaded.count, 1, "\(chainName) wallet was dropped on load")
                XCTAssertEqual(
                    reloaded.first?.address(forChainNamed: chainName), "address-for-\(chainName)",
                    "\(chainName) address did not round-trip")
                XCTAssertEqual(reloaded.first?.familyName, chainName)
            }
            try await store.clearWalletsForTesting()
        }

        // ── Core-owned settings (PLAN.md Stage 0) ─────────────────────────
        //
        // The display currency is domain state: core owns it, core persists it,
        // and every front end reads the same value. Swift keeps a mirror it
        // never writes directly.

        /// Choosing a currency sends a command; what the app shows is what
        /// core stored.
        func testSettingCurrencyGoesThroughCoreAndIsNormalized() async throws {
            let store = makeState()
            await store.setFiatCurrency(.eur)

            let state = try await bridge.appState()
            XCTAssertEqual(state.settings.fiatCurrency, .eur)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
        }

        /// A fresh `AppState` picks up what core has stored — the same path
        /// that makes a change made in the CLI visible in the app.
        func testCurrencySurvivesIntoAFreshAppState() async throws {
            let writer = makeState()
            await writer.setFiatCurrency(.jpy)

            let reader = makeState()
            await reader.loadCoreOwnedState()
            XCTAssertEqual(reader.selectedFiatCurrency, .jpy)
        }

        // ── Address book (PLAN.md Stage 1) ────────────────────────────────
        //
        // The list, and the rules about what may go in it, belong to core.
        // Swift sends commands and renders what comes back.

        private func clearAddressBook(_ store: AppState) async {
            for id in store.addressBook.map(\.id) {
                store.removeAddressBookEntry(id: id)
            }
            await store.awaitPendingAddressBookCommands()
            XCTAssertTrue(store.addressBook.isEmpty)
        }

        func testQueuedContactWritesCannotBeUndoneByAnOlderRead() async throws {
            let store = makeState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)
            for index in 1...3 {
                store.addAddressBookEntry(
                    name: "Contact \(index)",
                    address: "0x" + String(repeating: String(index), count: 40),
                    chainName: "Ethereum")
            }
            await store.awaitPendingAddressBookCommands()
            XCTAssertEqual(store.addressBook.count, 3)
            let stale = try await bridge.appState()

            for entry in store.addressBook { store.removeAddressBookEntry(id: entry.id) }
            await store.awaitPendingAddressBookCommands()
            store.applyCoreState(stale)
            XCTAssertTrue(store.addressBook.isEmpty, "an earlier read must not resurrect removed contacts")
            let persisted = try await bridge.appState()
            XCTAssertTrue(persisted.addressBook.isEmpty)
        }

        func testAddingAContactGoesThroughCoreAndPersists() async throws {
            let store = makeState()
            try await bridge.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)

            store.addAddressBookEntry(
                name: "  Cold Wallet  ", address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                chainName: "Bitcoin", note: " vault ")
            await store.awaitPendingAddressBookCommands()

            XCTAssertEqual(store.addressBook.count, 1)
            XCTAssertEqual(store.addressBook.first?.name, "Cold Wallet", "core trims")
            XCTAssertEqual(store.addressBook.first?.note, "vault")
            XCTAssertNil(store.addressBookError)

            // A fresh AppState sees it — same path that makes a CLI change visible.
            let reader = makeState()
            await reader.loadCoreOwnedState()
            XCTAssertEqual(reader.addressBook.count, 1)

            await clearAddressBook(store)
        }

        /// Core refuses, and says why. The UI must not silently do nothing.
        func testCoreRejectsInvalidAndDuplicateContacts() async throws {
            let store = makeState()
            try await bridge.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)

            store.addAddressBookEntry(
                name: "Typo", address: "definitely-not-an-address", chainName: "Bitcoin")
            await store.awaitPendingAddressBookCommands()
            XCTAssertTrue(store.addressBook.isEmpty)
            XCTAssertNotNil(store.addressBookError)

            store.addAddressBookEntry(
                name: "Cold", address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                chainName: "Bitcoin")
            await store.awaitPendingAddressBookCommands()
            XCTAssertNil(store.addressBookError, "a valid entry clears the message")

            store.addAddressBookEntry(
                name: "Same again", address: "BC1QCR8TE4KR609GCAWUTMRZA0J4XV80JY8Z306FYU",
                chainName: "Bitcoin")
            await store.awaitPendingAddressBookCommands()
            XCTAssertEqual(store.addressBook.count, 1, "case does not get around the duplicate check")
            XCTAssertNotNil(store.addressBookError)

            await clearAddressBook(store)
        }

        /// A pending send that later confirms must still read as confirmed
        /// after reopening the database in an independent service.
        func testTransactionStatusChangeIsPersisted() async throws {
            let store = makeState()
            // The transaction needs a wallet that exists: core prunes
            // transactions whose wallet is gone when state loads, so one
            // recorded against a made-up id survives only until the next load.
            let wallet = WalletView(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "W",
                addresses: ["Bitcoin": "bc1qexample"], familyName: "Bitcoin")
            try await store.seedWalletForTesting(wallet)
            let tx = TransactionRecord(
                id: UUID().uuidString,
                walletId: wallet.id, kind: .send, status: .pending, walletName: "W",
                assetDisplayName: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", amount: 0.1,
                address: "bc1qexample", transactionHash: "0xhash-status-test")

            try await store.seedTransactionForTesting(tx)
            let pending = try await bridge.transaction(id: tx.id)
            XCTAssertEqual(pending?.status, .pending)

            try await store.seedTransactionForTesting(
                tx.withRebroadcastUpdate(status: .confirmed, transactionHash: tx.transactionHash))
            let reopened = try WalletService(endpoints: [])
            _ = try await reopened.openState(databasePath: directory.appendingPathComponent("state.sqlite").path)
            let persisted = try await reopened.transaction(id: tx.id)?.status
            XCTAssertEqual(persisted, .confirmed, "status change was not persisted")

            _ = try await bridge.applyTransactionCommand(.remove(ids: [tx.id]))
            let deleted = try await bridge.transaction(id: tx.id)
            XCTAssertNil(deleted)
            await store.removeWallet(id: wallet.id)
        }

        func testTorDoesNotActivateOrStopForAnUncommittedToggle() async throws {
            _ = try await bridge.applyStateCommand(.setAppSetting(update: .torEnabled(value: false)))
            _ = try await service.configureNetworkRuntime(cacheDir: directory.path)
            let store = makeState()
            store.updateSetting(.torUseCustomProxy(value: true))
            store.updateSetting(.torCustomProxyAddress(value: "socks5://127.0.0.1:19050"))
            await store.awaitPendingSettingCommands()
            XCTAssertEqual(torStatus(), .stopped)
            store.updateSetting(.torEnabled(value: true))
            XCTAssertTrue(store.appSettings.torEnabled)
            XCTAssertFalse(store.committedAppSettings.torEnabled)
            XCTAssertEqual(torStatus(), .stopped)
            await store.awaitPendingSettingCommands()
            XCTAssertTrue(store.committedAppSettings.torEnabled)
            XCTAssertEqual(torStatus(), .ready)
            store.updateSetting(.torEnabled(value: false))
            XCTAssertEqual(torStatus(), .ready)
            await store.awaitPendingSettingCommands()
            XCTAssertEqual(torStatus(), .stopped)
            store.updateSetting(.torUseCustomProxy(value: false))
            store.updateSetting(.torCustomProxyAddress(value: "socks5://127.0.0.1:9050"))
            await store.awaitPendingSettingCommands()
        }

        func testSettingsRuntimeUsesCommittedValuesWhileEditsAreQueued() async throws {
            let store = makeState()
            let state = try await bridge.appState()
            store.applyCoreState(state, refreshPortfolio: false)
            let initial = store.committedAppSettings.bitcoinStopGap
            let next: UInt32 = initial == 30 ? 40 : 30
            store.updateSetting(.bitcoinStopGap(value: next))
            XCTAssertEqual(store.appSettings.bitcoinStopGap, next)
            XCTAssertEqual(store.committedAppSettings.bitcoinStopGap, initial)
            store.updateSetting(.bitcoinStopGap(value: initial))
            XCTAssertEqual(store.committedAppSettings.bitcoinStopGap, initial)
            await store.awaitPendingSettingCommands()
            XCTAssertEqual(store.appSettings.bitcoinStopGap, initial)
            XCTAssertEqual(store.committedAppSettings.bitcoinStopGap, initial)
        }

        /// A setting survives into a fresh `AppState`, and core bounds it —
        /// on screen at once, by core's own rule, not after the round trip.
        func testSettingsGoThroughCoreAndSurviveIntoAFreshAppState() async throws {
            let store = makeState()
            store.updateSetting(.addCustomEndpoint(capabilities: ["fee", "broadcast", "verification"], chainId: "monero", api: "monero-daemon-rpc", endpoint: "  https://wallet.example  "))
            store.updateSetting(.bitcoinStopGap(value: 9_999))
            store.updateSetting(.useLargeMovementNotifications(value: false))
            XCTAssertEqual(store.appSettings.customEndpoints.last?.endpoint, "https://wallet.example", "core's rule trims before the command lands")
            XCTAssertEqual(store.appSettings.bitcoinStopGap, 200, "9999 is outside 1...200")
            await store.awaitPendingSettingCommands()

            let fresh = makeState()
            await fresh.loadCoreOwnedState()
            XCTAssertEqual(fresh.appSettings.customEndpoints.last?.endpoint, "https://wallet.example")
            XCTAssertEqual(fresh.appSettings.bitcoinStopGap, 200)
            XCTAssertFalse(fresh.appSettings.useLargeMovementNotifications)

            store.updateSetting(.bitcoinStopGap(value: 10))
            store.updateSetting(.useLargeMovementNotifications(value: true))
            await store.awaitPendingSettingCommands()
        }

        func testImportCompletionPreservesAPartialSuccessNotice() async {
            let store = makeState()
            store.beginWatchAddressesImport()
            await store.walletImport.submit { "Some addresses were refused" }
            // SwiftUI can write the dismissed binding again after completion.
            store.walletImport.isPresented = false
            XCTAssertEqual(store.walletImport.error, "Some addresses were refused")
            XCTAssertFalse(store.walletImport.isPresented)
            XCTAssertTrue(store.appNoticeItems.contains { $0.message == "Some addresses were refused" })
        }

        func testPortfolioSnapshotRejectsADelayedOlderResult() async throws {
            let service = try WalletService(endpoints: [])
            let old = try await service.portfolioSnapshot()
            _ = try await service.applyStateCommand(command: .setFiatCurrency(currency: .eur))
            let new = try await service.portfolioSnapshot()
            let store = makeState()


            store.applyPortfolioSnapshot(new)
            store.applyPortfolioSnapshot(old)
            XCTAssertEqual(store.portfolioSnapshotRevision, new.revision)
            XCTAssertEqual(store.portfolioValuation?.currency, .eur)
            XCTAssertNil(store.portfolioValuation?.portfolio.fiatTotal)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
        }

        func testSnapshotCannotPartiallyOverwriteANewerStateCommand() async throws {
            let service = try WalletService(endpoints: [])
            let stale = try await service.portfolioSnapshot()
            let store = makeState()

            let transition = try await service.applyStateCommand(command: .setFiatCurrency(currency: .eur))
            store.applyCoreState(transition.state, refreshPortfolio: false)
            store.applyPortfolioSnapshot(stale)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
            XCTAssertNil(store.portfolioValuation)
            XCTAssertEqual(store.portfolioSnapshotRevision, 0)
        }

        func testCoreVersionWinsRegardlessOfRequestCompletionOrder() async throws {
            let old = try await bridge.appState()
            let changed = try await bridge.applyStateCommand(.setFiatCurrency(currency: .eur))
            // A failed operation after the successful write must not discard its result.
            do {
                _ = try await bridge.recheckTransactionStatus(id: "missing")
                XCTFail("missing transaction must fail")
            } catch {}
            let store = makeState()
            XCTAssertTrue(store.applyCoreState(changed.state, refreshPortfolio: false))
            XCTAssertFalse(store.applyCoreState(old, refreshPortfolio: false))
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
            XCTAssertEqual(store.appliedCoreStateRevision, changed.state.revision)
        }

        func testFiatCatalogSuppliesStableIdentityAndDisplayMetadata() {
            XCTAssertEqual(FiatCurrency.allCases.count, 12)
            XCTAssertEqual(Set(FiatCurrency.allCases.map(\.code)).count, 12)
            XCTAssertEqual(FiatCurrency.jpy.displayRules.decimals, 0)
            XCTAssertEqual(FiatCurrency.usd.displayRules.minimumVisible, 0.01)
        }

        func testPasswordVerdictsCrossTheBindingWithoutEnglishMessages() {
            XCTAssertEqual(validateWalletPassword(password: "短密碼", confirmation: "短密碼"), .tooShort)
            XCTAssertEqual(validateWalletPassword(password: "abcd", confirmation: "abce"), .confirmationMismatch)
            XCTAssertNil(validateWalletPassword(password: "密碼測試", confirmation: "密碼測試"))
        }

        func testDerivationInputPreservesSecretWhitespace() throws {
            let draft = WalletImportDraft()
            draft.overridePassphrase = " secret "
            draft.overrideHmacKey = " key "
            let parsed = draft.resolvedDerivationOverrides
            XCTAssertEqual(parsed.passphrase, " secret ")
            XCTAssertEqual(parsed.hmacKey, " key ")
        }

    }
#endif

@MainActor
private extension AppState {
    func seedTransactionForTesting(_ record: TransactionRecord) async throws {
        _ = try await bridge.applyTransactionCommand(.upsert(records: [record]))
        await refreshTransactionProjection()
    }
    func seedWalletForTesting(_ wallet: WalletView) async throws {
        _ = try await bridge.applyStateCommand(.upsertWallet(wallet: wallet.walletState(isWatchOnly: isWatchOnlyWallet(wallet))))
        await rebuildWalletDerivedStateFromCore()
    }
    func clearWalletsForTesting() async throws {
        let stored = try await bridge.portfolioSnapshot().wallets
        for wallet in stored { _ = try await bridge.applyStateCommand(.removeWallet(walletId: wallet.id)) }
        await rebuildWalletDerivedStateFromCore()
    }
}

private extension TransactionRecord {
    func withRebroadcastUpdate(status: TransactionStatus, transactionHash: String?, failureReason: String? = nil) -> TransactionRecord {
        var updated = self
        updated.status = status
        updated.transactionHash = transactionHash
        updated.failureReason = failureReason
        return updated
    }
}
