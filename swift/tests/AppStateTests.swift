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
                _ = try await bridge.ready().recheckTransactionStatus(transactionId: id)
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
            store.walletImport.draft.selectedChainIdsStorage = ["ethereum"]
            await store.importWallet()
            XCTAssertNil(store.walletImport.error)
            guard let wallet = store.wallets.first else { return XCTFail("no wallet") }

            let resolved = Chain.mainnets.filter { wallet.address(on: $0) != nil }
            XCTAssertEqual(
                Set(resolved), Set(Chain.mainnets.filter(\.isEVM)),
                "an Ethereum wallet answers for the EVM family — Ethereum Classic included, "
                    + "which has its own slot and one key — and for nothing else")
        }

        func testARenameThatLandsAfterADeleteDoesNotResurrectTheWallet() async throws {
            let store = makeState()
            let wallet = WalletView(
                id: UUID(), name: "Probe", chainId: "ethereum",
                addresses: ["ethereum": "0xabc123"])
            try await store.seedWalletForTesting(wallet)
            let removed = await store.removeWallet(id: wallet.id)
            XCTAssertTrue(removed)
            await store.renameWallet(id: wallet.id, to: "Late rename")
            let after = try await bridge.ready().portfolioSnapshot().wallets
            XCTAssertTrue(after.isEmpty)
            XCTAssertTrue(store.wallets.isEmpty)
        }

        func testEditingWalletNamePreservesExistingHoldings() async throws {
            let store = makeState()
            let existingHolding = Coin.fixture(
                name: "Ethereum", symbol: "ETH", coingeckoId: "ethereum", chainId: "ethereum", amount: "2")
            let wallet = WalletView(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Primary ETH", chainId: "ethereum",
                addresses: ["ethereum": "0xabc123"], holdings: [existingHolding], includeInPortfolioTotal: false
            )
            try await store.seedWalletForTesting(wallet)
            store.beginEditingWallet(wallet)
            store.walletImport.draft.walletName = "Renamed ETH"
            store.walletImport.draft.selectedChainIdsStorage = []
            await store.importWallet()
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets[0].name, "Renamed ETH")
            XCTAssertEqual(store.wallets[0].holdings.count, 1)
            XCTAssertEqual(store.wallets[0].holdings[0].amount, existingHolding.amount)
            XCTAssertFalse(store.wallets[0].includeInPortfolioTotal)
            XCTAssertNil(store.walletImport.editingWalletId)
            XCTAssertFalse(store.walletImport.isPresented)
            XCTAssertNil(store.walletImport.error)
        }
        func testImportingBitcoinWalletPersistsDerivedAddress() async {
            let store = makeState()
            store.walletImport.draft.walletName = "Primary BTC"
            store.walletImport.draft.setSeedPhraseForTesting("test test test test test test test test test test test junk")
            store.walletImport.draft.selectedChainIdsStorage = ["bitcoin"]
            await store.importWallet()
            XCTAssertNil(store.walletImport.error)
            XCTAssertEqual(store.wallets.count, 1)
            XCTAssertEqual(store.wallets.first?.chainId, "bitcoin")
            XCTAssertFalse(store.wallets.first?.address(on: .bitcoin)?.isEmpty ?? true)
        }
        func testBitcoinDisplayNetworkNameUsesSelectedMode() async {
            let store = makeState()
            store.selectChainForFamily("bitcoin-testnet-4")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(store.selectedNetworkTitle(forFamily: .bitcoin), "Bitcoin Testnet4")
        }
        /// A wallet carries its own network, so it can differ from the app's.
        func testBitcoinWalletDisplayTitleUsesWalletSpecificNetwork() {
            let wallet = WalletView(
                name: "BTC Testnet4", chainId: "bitcoin-testnet-4",
                addresses: ["bitcoin-testnet-4": "tb1qexample"]
            )
            XCTAssertEqual(wallet.networkTitle, "Bitcoin Testnet4")
        }
        func testHistoricalNetworkTitleIgnoresCurrentNetworkSelection() async {
            let store = makeState()
            let transaction = TransactionRecord(id: UUID().uuidString, kind: .send, status: .confirmed,
                walletName: "Historical", assetDisplayName: "Ethereum", symbol: "ETH",
                chainId: "ethereum-sepolia", amount: "1", address: "0x1111111111111111111111111111111111111111")
            store.selectChainForFamily("ethereum-hoodi")
            await store.awaitPendingCoreStateWrites()
            XCTAssertEqual(transaction.chainName, "Ethereum Sepolia")
        }

        func testStakingAndReceiveRefusalAcrossAsyncBinding() async throws {
            do {
                _ = try await bridge.ready().fetchStakingValidators(chainId: "bitcoin")
                XCTFail("Unsupported staking must refuse before network access")
            } catch { }
            do {
                _ = try await bridge.ready().receiveAddress(walletId: "missing", chainId: "ethereum", reserve: true)
                XCTFail("A missing wallet must not produce an address or a message-as-address")
            } catch { }
        }

        func testUnvaluedFiguresAreUnavailableAndPartialTotalsAreLabelled() async {
            let store = makeState()
            await store.awaitPendingCoreStateWrites()
            let before = store.selectedFiatCurrency
            await store.setFiatCurrency(.eur)
            XCTAssertNil(store.amounts.formattedFiatIfAvailable(nil))
            XCTAssertEqual(store.amounts.formattedFiat(nil), "—")
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
            XCTAssertEqual(store.selectedNetworkTitle(forFamily: .ethereum), "Ethereum Hoodi")
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
            let generic = store.addressBookAddressValidationMessage(for: "", chain: .kaspa)
            let evmMainnets = Chain.mainnets.filter(\.isEVM)
            XCTAssertGreaterThan(evmMainnets.count, 13, "the arm used to name thirteen")
            for chain in evmMainnets {
                XCTAssertNotEqual(
                    store.addressBookAddressValidationMessage(for: "", chain: chain),
                    generic,
                    "\(chain.displayName) still gets the generic hint")
                XCTAssertNotEqual(
                    store.addressBookAddressValidationMessage(for: "nope", chain: chain),
                    store.addressBookAddressValidationMessage(for: "nope", chain: .kaspa),
                    "\(chain.displayName) still gets the generic invalid-address hint")
            }
        }
        func testEveryCatalogCapabilityHasALocalizedLabel() async throws {
            let capabilities = Set(try await service.endpointDirectory().flatMap(\.record.capabilities))
            XCTAssertFalse(capabilities.isEmpty)
            for capability in capabilities {
                let key = "endpointCapability.\(capability)"
                XCTAssertNotEqual(AppLocalization.string(key), key, capability)
            }
        }
        /// What the app reads about Ethereum's test networks: that the
        /// registry knows them as EVM testnets of Ethereum, and the RPC
        /// endpoints the catalog gives each. Their EIP-155 ids were asserted
        /// here through `EVMChainContext`, which the app no longer has; core's
        /// `evm_chains_carry_their_eip155_ids` checks them where they live.
        func testEthereumTestNetworksExposeExpectedContextsAndEndpoints() {
            for id in ["ethereum-sepolia", "ethereum-hoodi"] {
                let chain = Chain(id: id)
                XCTAssertEqual(chain?.isEVM, true, id)
                XCTAssertEqual(chain?.isTestnet, true, id)
                XCTAssertEqual(chain?.mainnetCounterpart, .ethereum, id)
            }
            XCTAssertEqual(AppEndpointDirectory.groupedSettingsEntries(for: "ethereum-sepolia").flatMap(\.endpoints),
                ["https://ethereum-sepolia-rpc.publicnode.com"])
            XCTAssertEqual(AppEndpointDirectory.groupedSettingsEntries(for: "ethereum-hoodi").flatMap(\.endpoints),
                ["https://ethereum-hoodi-rpc.publicnode.com"])
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
            for chain in [Chain.kaspa, .dash, .zcash, .ton, .icp, .bitcoinGold, .bittensor] {
                try await store.clearWalletsForTesting()

                var wallet = WalletView(name: "Watch \(chain.id)", chainId: chain.id)
                wallet.setAddress("address-for-\(chain.id)", on: chain)
                try await store.seedWalletForTesting(wallet)

                // Read it back the way a fresh launch does.
                let reloaded = try await bridge.ready().portfolioSnapshot().wallets
                XCTAssertEqual(reloaded.count, 1, "\(chain.id) wallet was dropped on load")
                XCTAssertEqual(
                    reloaded.first?.address(on: chain), "address-for-\(chain.id)",
                    "\(chain.id) address did not round-trip")
                XCTAssertEqual(reloaded.first?.chainId, chain.id)
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

            let state = try await bridge.ready().appState()
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
            await store.awaitPendingStateCommands()
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
                    chain: .ethereum)
            }
            await store.awaitPendingStateCommands()
            XCTAssertEqual(store.addressBook.count, 3)
            let stale = try await bridge.ready().appState()

            for entry in store.addressBook { store.removeAddressBookEntry(id: entry.id) }
            await store.awaitPendingStateCommands()
            store.applyCoreState(stale)
            XCTAssertTrue(store.addressBook.isEmpty, "an earlier read must not resurrect removed contacts")
            let persisted = try await bridge.ready().appState()
            XCTAssertTrue(persisted.addressBook.isEmpty)
        }

        func testAddingAContactGoesThroughCoreAndPersists() async throws {
            let store = makeState()
            try await bridge.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)

            store.addAddressBookEntry(
                name: "  Cold Wallet  ", address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                chain: .bitcoin, note: " vault ")
            await store.awaitPendingStateCommands()

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
        /// A refusal reaches the contact form. Which addresses core refuses —
        /// invalid, duplicate in any case — is tested in `address_book.rs`.
        func testAContactRefusalReachesTheForm() async throws {
            let store = makeState()
            try await bridge.openState()
            await store.loadCoreOwnedState()
            await clearAddressBook(store)
            store.addAddressBookEntry(
                name: "Typo", address: "definitely-not-an-address", chain: .bitcoin)
            await store.awaitPendingStateCommands()
            XCTAssertTrue(store.addressBook.isEmpty)
            XCTAssertNotNil(store.addressBookError)
        }

        /// A pending send that later confirms must still read as confirmed
        /// after reopening the database in an independent service.
        func testTransactionStatusChangeIsPersisted() async throws {
            let store = makeState()
            // The transaction needs a wallet that exists: core prunes
            // transactions whose wallet is gone when state loads, so one
            // recorded against a made-up id survives only until the next load.
            let wallet = WalletView(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "W", chainId: "bitcoin",
                addresses: ["bitcoin": "bc1qexample"])
            try await store.seedWalletForTesting(wallet)
            let tx = TransactionRecord(
                id: UUID().uuidString,
                walletId: wallet.id, kind: .send, status: .pending, walletName: "W",
                assetDisplayName: "Bitcoin", symbol: "BTC", chainId: "bitcoin", amount: "0.1",
                address: "bc1qexample", transactionHash: "0xhash-status-test")

            try await store.seedTransactionForTesting(tx)
            let pending = try await bridge.ready().transaction(id: tx.id)
            XCTAssertEqual(pending?.status, .pending)

            try await store.seedTransactionForTesting(
                tx.withRebroadcastUpdate(status: .confirmed, transactionHash: tx.transactionHash))
            let reopened = try WalletService(endpoints: [])
            _ = try await reopened.openState(databasePath: directory.appendingPathComponent("state.sqlite").path)
            let persisted = try await reopened.transaction(id: tx.id)?.status
            XCTAssertEqual(persisted, .confirmed, "status change was not persisted")

            _ = try await bridge.ready().applyTransactionCommand(command: .remove(ids: [tx.id]))
            let deleted = try await bridge.ready().transaction(id: tx.id)
            XCTAssertNil(deleted)
            await store.removeWallet(id: wallet.id)
        }

        func testTorDoesNotActivateOrStopForAnUncommittedToggle() async throws {
            _ = try await bridge.ready().applyStateCommand(command: .setAppSetting(update: .torEnabled(value: false)))
            _ = try await service.configureNetworkRuntime(cacheDir: directory.path)
            let store = makeState()
            store.updateSetting(.torUseCustomProxy(value: true))
            store.updateSetting(.torCustomProxyAddress(value: "socks5://127.0.0.1:19050"))
            await store.awaitPendingStateCommands()
            XCTAssertEqual(torStatus(), .stopped)
            store.updateSetting(.torEnabled(value: true))
            XCTAssertTrue(store.appSettings.torEnabled)
            XCTAssertFalse(store.committedAppSettings.torEnabled)
            XCTAssertEqual(torStatus(), .stopped)
            await store.awaitPendingStateCommands()
            XCTAssertTrue(store.committedAppSettings.torEnabled)
            XCTAssertEqual(torStatus(), .ready)
            store.updateSetting(.torEnabled(value: false))
            XCTAssertEqual(torStatus(), .ready)
            await store.awaitPendingStateCommands()
            XCTAssertEqual(torStatus(), .stopped)
            store.updateSetting(.torUseCustomProxy(value: false))
            store.updateSetting(.torCustomProxyAddress(value: "socks5://127.0.0.1:9050"))
            await store.awaitPendingStateCommands()
        }

        func testSettingsRuntimeUsesCommittedValuesWhileEditsAreQueued() async throws {
            let store = makeState()
            let state = try await bridge.ready().appState()
            store.applyCoreState(state)
            let initial = store.committedAppSettings.bitcoinStopGap
            let next: UInt32 = initial == 30 ? 40 : 30
            store.updateSetting(.bitcoinStopGap(value: next))
            XCTAssertEqual(store.appSettings.bitcoinStopGap, next)
            XCTAssertEqual(store.committedAppSettings.bitcoinStopGap, initial)
            store.updateSetting(.bitcoinStopGap(value: initial))
            XCTAssertEqual(store.committedAppSettings.bitcoinStopGap, initial)
            await store.awaitPendingStateCommands()
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
            await store.awaitPendingStateCommands()

            let fresh = makeState()
            await fresh.loadCoreOwnedState()
            XCTAssertEqual(fresh.appSettings.customEndpoints.last?.endpoint, "https://wallet.example")
            XCTAssertEqual(fresh.appSettings.bitcoinStopGap, 200)
            XCTAssertFalse(fresh.appSettings.useLargeMovementNotifications)

            store.updateSetting(.bitcoinStopGap(value: 10))
            store.updateSetting(.useLargeMovementNotifications(value: true))
            await store.awaitPendingStateCommands()
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
            store.applyCoreState(transition.state)
            store.applyPortfolioSnapshot(stale)
            XCTAssertEqual(store.selectedFiatCurrency, .eur)
            XCTAssertNil(store.portfolioValuation)
            XCTAssertEqual(store.portfolioSnapshotRevision, 0)
        }

        func testCoreVersionWinsRegardlessOfRequestCompletionOrder() async throws {
            let old = try await bridge.ready().appState()
            let changed = try await bridge.ready().applyStateCommand(command: .setFiatCurrency(currency: .eur))
            // A failed operation after the successful write must not discard its result.
            do {
                _ = try await bridge.ready().recheckTransactionStatus(transactionId: "missing")
                XCTFail("missing transaction must fail")
            } catch {}
            let store = makeState()
            XCTAssertTrue(store.applyCoreState(changed.state))
            XCTAssertFalse(store.applyCoreState(old))
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
        _ = try await bridge.ready().applyTransactionCommand(command: .upsert(records: [record]))
        await refreshTransactionProjection()
    }
    func seedWalletForTesting(_ wallet: WalletView) async throws {
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        await rebuildWalletDerivedStateFromCore()
    }
    func clearWalletsForTesting() async throws {
        let stored = try await bridge.ready().portfolioSnapshot().wallets
        for wallet in stored { _ = try await bridge.ready().applyStateCommand(command: .removeWallet(walletId: wallet.id)) }
        await rebuildWalletDerivedStateFromCore()
    }
}

private extension TransactionRecord {
    func withRebroadcastUpdate(status: TransactionStatus, transactionHash: String?, failureReason: TransactionFailure? = nil) -> TransactionRecord {
        var updated = self
        updated.status = status
        updated.transactionHash = transactionHash
        updated.failureReason = failureReason
        return updated
    }
}
