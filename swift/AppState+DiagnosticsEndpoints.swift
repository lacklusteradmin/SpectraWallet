import Foundation
import SwiftUI

// This file now forwards diagnostics decoding/aggregation to Rust
// (`core/src/diagnostics/aggregate.rs`). The Swift layer only keeps:
//   * per-chain AppState wiring (KeyPath-driven, tied to SwiftUI reactivity)
//   * HTTP probes via Rust FFI (httpRequest / httpPostJson / diagnosticsProbeJsonrpc)
//   * async orchestration + pending-transaction mutation against
//     AppState's transaction model.
// JSON decoding and diagnostic-record construction live in core — see
// `diagnosticsHistoryEntryCount`, `diagnosticsHistorySummary`,
// `diagnosticsMakeEvm{Running,Error,Success}` and `diagnosticsParseJsonrpcProbe`
// in the generated bindings.
@MainActor
extension AppState {
    // MARK: Bitcoin-family history diagnostics

    func runUtxoHistoryDiagnostics() async {
        guard !self[historyRunFor: "Bitcoin"].isRunning else { return }
        self[historyRunFor: "Bitcoin"].isRunning = true
        defer { self[historyRunFor: "Bitcoin"].isRunning = false }
        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else { self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date(); return }
        for wallet in btcWallets { await runUtxoHistoryDiagnosticsInner(for: wallet) }
    }
    func runUtxoHistoryDiagnostics(for walletID: String) async {
        guard !self[historyRunFor: "Bitcoin"].isRunning else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == "Bitcoin" else { return }
        self[historyRunFor: "Bitcoin"].isRunning = true
        defer { self[historyRunFor: "Bitcoin"].isRunning = false }
        await runUtxoHistoryDiagnosticsInner(for: wallet)
    }
    private func runUtxoHistoryDiagnosticsInner(for wallet: ImportedWallet) async {
        let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
        do {
            let page = try await withTimeout(seconds: 20) {
                try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil)
            }
            if identifier.isEmpty {
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    UtxoHistoryDiagnostics(walletId: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: "Wallet has no BTC address or xpub configured."))
            } else {
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    UtxoHistoryDiagnostics(walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count), nextCursor: page.nextCursor, error: nil))
            }
        } catch {
            recordUTXOHistoryDiagnostics(
                chainName: "Bitcoin", walletID: wallet.id,
                UtxoHistoryDiagnostics(walletId: wallet.id, identifier: wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? "unknown", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription))
        }
        self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
    }

    // MARK: Chain-agnostic diagnostics dispatch

    /// The three diagnostics runs for one chain.
    ///
    /// Each closure is handed the `Chain` the row is keyed by, so a row never
    /// spells its own key a second time.
    struct ChainDiagnosticsDescriptor {
        let runHistory: (AppState, Chain) async -> Void
        let runHistoryForWallet: ((AppState, Chain, String) async -> Void)?
        let runEndpoints: (AppState, Chain) async -> Void
        init(
            runHistory: @escaping (AppState, Chain) async -> Void,
            runHistoryForWallet: ((AppState, Chain, String) async -> Void)? = nil,
            runEndpoints: @escaping (AppState, Chain) async -> Void
        ) {
            self.runHistory = runHistory; self.runHistoryForWallet = runHistoryForWallet; self.runEndpoints = runEndpoints
        }
    }
    static let chainDiagDescriptors: [Chain: ChainDiagnosticsDescriptor] = [
        .bitcoin: .init(
            runHistory: { store, _ in await store.runUtxoHistoryDiagnostics() },
            runHistoryForWallet: { store, _, id in await store.runUtxoHistoryDiagnostics(for: id) },
            runEndpoints: { store, _ in await store.runBitcoinEndpointReachabilityDiagnostics() }
        ),
        .dogecoin: .init(
            runHistory: { store, chain in await store.runRustHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedNetworkModeAddress(for: $0, family: "dogecoin", fallback: .dogecoin) },
                make: { UtxoHistoryDiagnostics(walletId: "", identifier: $0, sourceUsed: $1, transactionCount: Int32($2), nextCursor: nil, error: $3) },
                record: { walletID, entry in store.recordUTXOHistoryDiagnostics(
                    chainName: chain.displayName, walletID: walletID,
                    UtxoHistoryDiagnostics(
                        walletId: walletID, identifier: entry.identifier, sourceUsed: entry.sourceUsed,
                        transactionCount: entry.transactionCount, nextCursor: nil, error: entry.error)) }) },
            runEndpoints: { store, chain in await store.runCatalogEndpointReachabilityDiagnostics(for: chain.displayName) }
        ),
        .tron: .init(
            runHistory: { store, chain in await store.runRustHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .tron(entry: $1)) }) },
            runHistoryForWallet: { store, chain, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .tron(entry: $1)) }) },
            runEndpoints: { store, chain in await store.runCatalogEndpointReachabilityDiagnostics(for: chain.displayName) }
        ),
        .solana: .init(
            runHistory: { store, chain in await store.runRustHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .solana(entry: $1)) }) },
            runHistoryForWallet: { store, chain, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .solana(entry: $1)) }) },
            runEndpoints: { store, chain in await store.runCatalogEndpointReachabilityDiagnostics(for: chain.displayName) }
        ),
        .monero: .init(
            runHistory: { store, chain in await store.runRustHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .simple(entry: $1)) }) },
            runHistoryForWallet: { store, chain, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .simple(entry: $1)) }) },
            runEndpoints: { store, _ in await store.runMoneroEndpointReachabilityDiagnostics() }
        ),
        .near: .init(
            runHistory: { store, chain in await store.runRustHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .simple(entry: $1)) }) },
            runHistoryForWallet: { store, chain, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecord(chainName: chain.displayName, walletId: $0, entry: .simple(entry: $1)) }) },
            runEndpoints: { store, _ in await store.runNearEndpointReachabilityDiagnostics() }
        ),
        .ethereum: .init(
            runHistory: { store, chain in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) }) },
            runHistoryForWallet: { store, chain, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) }) },
            runEndpoints: { store, _ in await store.runEthereumEndpointReachabilityDiagnostics() }
        ),
        .bnbChain: .init(
            runHistory: { store, chain in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: chain.displayName,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: chain.displayName) }) },
            runHistoryForWallet: { store, chain, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: chain.displayName,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: chain.displayName) }) },
            runEndpoints: { store, _ in await store.runBNBEndpointReachabilityDiagnostics() }
        ),
    ]
    /// Chains whose diagnostics are the shared shape: fetch the history count
    /// for each wallet's address, and probe the endpoints the catalog lists.
    private func runSimpleChainDiagnostics(chainName: String, walletID: String? = nil) async {
        let make: (String, String, Int, String?) -> SimpleHistoryDiagnostics = {
            SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3)
        }
        let resolve: (ImportedWallet) -> String? = { [self] in resolvedAddress(for: $0, chainName: chainName) }
        let record: @MainActor (String, SimpleHistoryDiagnostics) -> Void = { [self] in
            recordSimpleHistoryDiagnostics(chainName: chainName, walletID: $0, $1)
        }
        if let walletID {
            await runRustHistoryDiagnosticsForWallet(
                walletID: walletID, chainName: chainName, resolveAddress: resolve, make: make, record: record)
        } else {
            await runRustHistoryDiagnosticsForAllWallets(
                chainName: chainName, resolveAddress: resolve, make: make, record: record)
        }
    }
    /// The EVM family's diagnostics, for chains without a descriptor of their
    /// own. Five rows said this, byte-identical but for the chain name;
    /// Ethereum and BNB Chain keep theirs because their endpoint probes parse
    /// JSON-RPC inline rather than just reaching the host.
    private func runEVMChainDiagnostics(chainName: String, walletID: String? = nil) async {
        let resolve: (ImportedWallet) -> String? = { [self] in resolvedEVMAddress(for: $0, chainName: chainName) }
        if let walletID {
            await runEVMHistoryDiagnosticsForWallet(
                walletID: walletID, chainName: chainName, resolveAddress: resolve)
        } else {
            await runEVMHistoryDiagnosticsForAllWallets(chainName: chainName, resolveAddress: resolve)
        }
    }
    /// The UTXO chains' diagnostics. Three rows said this — Litecoin, Bitcoin
    /// Cash and Bitcoin SV — identical but for the chain name. Bitcoin and
    /// Dogecoin keep theirs: Bitcoin's walks an xpub, Dogecoin's counts
    /// history entries directly.
    private func runUTXOChainDiagnostics(chainName: String, walletID: String? = nil) async {
        let resolve: (ImportedWallet) -> String? = { [self] in resolvedAddress(for: $0, chainName: chainName) }
        if let walletID {
            await runUTXOStyleHistoryDiagnosticsForWallet(
                walletID: walletID, chainName: chainName, resolveAddress: resolve)
        } else {
            await runUTXOStyleHistoryDiagnostics(chainName: chainName, resolveAddress: resolve)
        }
    }

    func runHistoryDiagnostics(for chain: Chain) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            if chain.isEVM {
                return await runEVMChainDiagnostics(chainName: chain.displayName)
            }
            if chain.supportsDeepUTXODiscovery {
                return await runUTXOChainDiagnostics(chainName: chain.displayName)
            }
            return await runSimpleChainDiagnostics(chainName: chain.displayName)
        }
        await descriptor.runHistory(self, chain)
    }
    func runHistoryDiagnostics(for chain: Chain, walletID: String) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            if chain.isEVM {
                return await runEVMChainDiagnostics(chainName: chain.displayName, walletID: walletID)
            }
            if chain.supportsDeepUTXODiscovery {
                return await runUTXOChainDiagnostics(chainName: chain.displayName, walletID: walletID)
            }
            return await runSimpleChainDiagnostics(chainName: chain.displayName, walletID: walletID)
        }
        await descriptor.runHistoryForWallet?(self, chain, walletID)
    }
    func runEndpointDiagnostics(for chain: Chain) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            return await runCatalogEndpointReachabilityDiagnostics(for: chain.displayName)
        }
        await descriptor.runEndpoints(self, chain)
    }

    // MARK: Generic history-diagnostic drivers

    /// The run flag and the "last updated" stamp are both `self[historyRunFor:
    /// chainName]`, so neither is a parameter: passing a key path built from an
    /// argument the same call already carries is the argument passed twice.
    private func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(
        chainName: String, resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void
    ) async {
        let markUpdated = { self[historyRunFor: chainName].lastUpdatedAt = Date() }
        guard !self[historyRunFor: chainName].isRunning else { return }
        self[historyRunFor: chainName].isRunning = true
        defer { self[historyRunFor: chainName].isRunning = false }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return nil }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else { markUpdated(); return }
        for (wallet, address) in walletsToRefresh { storeDiagnostics(wallet.id, await fetchDiagnostics(address)) }
        markUpdated()
    }
    private func runAddressHistoryDiagnosticsForWallet<Diagnostics>(
        walletID: String, chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void
    ) async {
        guard !self[historyRunFor: chainName].isRunning else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName,
            let address = resolveAddress(wallet)
        else { return }
        self[historyRunFor: chainName].isRunning = true
        defer { self[historyRunFor: chainName].isRunning = false }
        storeDiagnostics(wallet.id, await fetchDiagnostics(address))
        self[historyRunFor: chainName].lastUpdatedAt = Date()
    }

    // MARK: Custom reachability probes that need inline JSON-RPC parsing

    /// Run one chain's endpoint probe, holding its "checking" flag and owning
    /// the write-back.
    private func withEndpointCheck(
        for chainName: String, operation: (_ publish: @MainActor ([EndpointHealthRow]) -> Void) async -> Void
    ) async {
        guard !self[endpointHealthFor: chainName].isChecking else { return }
        self[endpointHealthFor: chainName].isChecking = true
        defer { self[endpointHealthFor: chainName].isChecking = false }
        await operation { rows in
            self[endpointHealthFor: chainName].results = rows
            self[endpointHealthFor: chainName].lastUpdatedAt = Date()
        }
    }
    func runBitcoinEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(for: "Bitcoin") { publish in
            var results: [EndpointHealthRow] = []
            for endpoint in self.effectiveBitcoinEsploraEndpoints() {
                guard let url = URL(string: endpoint) else {
                    results.append(EndpointHealthRow(label: "", endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                    continue
                }
                let probe = await self.probeHTTP(url.appending(path: "blocks/tip/height"))
                results.append(
                    EndpointHealthRow(
                        label: "", endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
                publish(results)
            }
        }
    }
    func runMoneroEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(for: "Monero") { publish in
            let trimmedBackendURL = self.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBackendURL = trimmedBackendURL.isEmpty ? MoneroBalanceService.defaultPublicBackend.baseURL : trimmedBackendURL
            guard let baseURL = URL(string: resolvedBackendURL) else {
                publish([
                    EndpointHealthRow(
                        label: "", endpoint: "monero.backend.baseURL", reachable: false, statusCode: nil, detail: "Monero backend is not configured.")
                ])
                return
            }
            let probe = await self.probeHTTP(baseURL.appendingPathComponent("v1/monero/balance"), profile: .diagnostics)
            publish([
                EndpointHealthRow(
                    label: "", endpoint: baseURL.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail)
            ])
        }
    }
    func runNearEndpointReachabilityDiagnostics() async {
        await runCatalogEndpointReachabilityDiagnostics(for: "NEAR")
    }
    func runPolkadotEndpointReachabilityDiagnostics() async {
        await runCatalogEndpointReachabilityDiagnostics(for: "Polkadot")
    }

    /// Probe every endpoint the catalog lists for a chain, each the way the
    /// catalog says: a JSON-RPC call when the record carries the `rpc` role,
    /// a GET against its probe URL otherwise.
    ///
    /// NEAR and Polkadot each had their own copy of this, and each decided
    /// which endpoints were RPC from a hand-written list of endpoint ids in
    /// `ChainTypes` — beside a catalog that already carries the role. Both
    /// lists agreed when they were written; the drift they invited is a
    /// JSON-RPC node probed with a GET, which many answer 405 and this would
    /// have reported as unreachable.
    func runCatalogEndpointReachabilityDiagnostics(for chainName: String) async {
        await withEndpointCheck(for: chainName) { publish in
            var results: [EndpointHealthRow] = []
            // The one endpoint that is not in the catalog: whatever the user
            // typed. Only Ethereum has such a setting — see "Known open items".
            if let configured = self.configuredEVMRPCEndpointURL(for: chainName),
                let method = Chain(displayName: chainName)?.rpcHealthMethod
            {
                var row = await self.probeJSONRPC(
                    endpoint: configured.absoluteString, urlString: configured.absoluteString, rpcMethod: method)
                row = EndpointHealthRow(
                    label: "Configured RPC", endpoint: row.endpoint, reachable: row.reachable,
                    statusCode: row.statusCode, detail: row.detail)
                results.append(row)
                publish(results)
            }
            for check in AppEndpointDirectory.diagnosticsChecks(for: chainName) {
                if let method = check.rpcProbeMethod {
                    results.append(
                        await self.probeJSONRPC(endpoint: check.endpoint, urlString: check.endpoint, rpcMethod: method))
                } else if let url = URL(string: check.probeUrl) {
                    let probe = await self.probeHTTP(url, profile: .diagnostics)
                    results.append(
                        EndpointHealthRow(
                            label: "", endpoint: check.endpoint, reachable: probe.reachable,
                            statusCode: probe.statusCode, detail: probe.detail))
                } else {
                    results.append(
                        EndpointHealthRow(
                            label: "", endpoint: check.endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                }
                publish(results)
            }
        }
    }
    /// Send a JSON-RPC request to `urlString` with method `rpcMethod` and an
    /// empty params array, then delegate to Rust for the reachability
    /// verdict (`diagnosticsParseJsonrpcProbe`). Swift only handles
    /// transport — parsing lives in `core::diagnostics::aggregate`.
    // Pilot call site for the Rust HTTP migration (Phase 1).
    // Transport + JSON-RPC parse both live in `core::http_ffi::diagnostics_probe_jsonrpc`.
    // Swift owns nothing here beyond URL validation and result wrapping.
    private func probeJSONRPC(endpoint: String, urlString: String, rpcMethod: String) async -> EndpointHealthRow {
        guard URL(string: urlString) != nil else {
            return EndpointHealthRow(label: "", endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")
        }
        let outcome = await diagnosticsProbeJsonrpc(url: urlString, rpcMethod: rpcMethod)
        return EndpointHealthRow(label: "", endpoint: endpoint, reachable: outcome.reachable, statusCode: outcome.statusCode, detail: outcome.detail)
    }

    // MARK: EVM history diagnostics

    private func runEVMHistoryDiagnosticsForAllWallets(
        chainName: String, resolveAddress: (ImportedWallet) -> String?
    ) async {
        guard !self[historyRunFor: chainName].isRunning else { return }
        self[historyRunFor: chainName].isRunning = true
        defer { self[historyRunFor: chainName].isRunning = false }
        let walletsToRefresh = wallets.compactMap { w -> (ImportedWallet, String)? in
            guard w.selectedChain == chainName, let a = resolveAddress(w) else { return nil }; return (w, a)
        }
        guard !walletsToRefresh.isEmpty else { self[historyRunFor: chainName].lastUpdatedAt = Date(); return }
        for (wallet, address) in walletsToRefresh {
            recordEVMHistoryDiagnostics(chainName: chainName, walletID: wallet.id, diagnosticsMakeEvmRunning(address: address))
            self[historyRunFor: chainName].lastUpdatedAt = Date()
            recordEVMHistoryDiagnostics(
            chainName: chainName, walletID: wallet.id,
            await rustEVMHistoryDiagnostics(chainName: chainName, address: address))
        }
        self[historyRunFor: chainName].lastUpdatedAt = Date()
    }
    private func runEVMHistoryDiagnosticsForWallet(
        walletID: String, chainName: String, resolveAddress: (ImportedWallet) -> String?
    ) async {
        guard !self[historyRunFor: chainName].isRunning else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName,
            let address = resolveAddress(wallet)
        else { return }
        self[historyRunFor: chainName].isRunning = true
        defer { self[historyRunFor: chainName].isRunning = false }
        recordEVMHistoryDiagnostics(chainName: chainName, walletID: wallet.id, diagnosticsMakeEvmRunning(address: address))
        self[historyRunFor: chainName].lastUpdatedAt = Date()
        recordEVMHistoryDiagnostics(
            chainName: chainName, walletID: wallet.id,
            await rustEVMHistoryDiagnostics(chainName: chainName, address: address))
        self[historyRunFor: chainName].lastUpdatedAt = Date()
    }
    /// Bridge to Rust: fused history-fetch-then-build call. Rust owns both
    /// the HTTP fetch and the diagnostics record construction so Swift never
    /// sees the intermediate JSON. Unsupported chain → error record built
    /// on the Rust side via `fetch_evm_history_diagnostics`' fallback path.
    private func rustEVMHistoryDiagnostics(chainName: String, address: String) async -> EthereumTokenTransferHistoryDiagnostics {
        let chainId = Chain(displayName: chainName)?.id ?? ""
        return (try? await WalletServiceBridge.shared.fetchEVMHistoryDiagnostics(chainId: chainId, address: address))
            ?? diagnosticsMakeEvmRunning(address: address)
    }

    // MARK: EVM endpoint reachability

    func runEthereumEndpointReachabilityDiagnostics() async {
        await runCatalogEndpointReachabilityDiagnostics(for: "Ethereum")
    }
    func runBNBEndpointReachabilityDiagnostics() async {
        await runCatalogEndpointReachabilityDiagnostics(for: "BNB Chain")
    }
    /// `setResults` and `markUpdated` were two closures called one after the
    /// other, at the one call site each caller had — a pair, so the pair is one
    /// argument, and it is the same `publish` `withEndpointCheck` hands out.
    func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); throw TimeoutError.timedOut(seconds: seconds)
            }
            guard let first = try await group.next() else { throw TimeoutError.timedOut(seconds: seconds) }
            group.cancelAll(); return first
        }
    }
    func probeHTTP(_ url: URL, profile: HttpRetryProfile = .diagnostics) async -> (reachable: Bool, statusCode: Int32?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let resp = try await httpRequest(method: "GET", url: url.absoluteString, headers: [], body: nil, profile: profile)
                let statusCode = Int32(resp.statusCode)
                return ((200..<300).contains(statusCode), statusCode, "HTTP \(statusCode)")
            }
        } catch { return (false, nil, error.localizedDescription) }
    }
    // MARK: Pending transaction refresh (AppState mutation; Swift-native)

    /// Poll one chain's pending transactions for a final status.
    ///
    /// How a chain reaches finality is a registry fact — eighteen wrappers
    /// used to state it, each naming a chain, a chain id, an address resolver
    /// and up to two flags. Adding a chain is a registry edit now.
    func refreshPendingTransactions(chainName: String) async {
        let chainID = Chain(displayName: chainName)?.id ?? ""
        guard !chainID.isEmpty else { return }
        switch (Chain(displayName: chainName)?.pendingStatusPoll ?? .none) {
        case .utxo(let tracksFinality, let requireSendKind):
            await refreshPendingUTXOChainTransactions(
                chainName: chainName, chainId: chainID,
                requireSendKind: requireSendKind, tracksFinality: tracksFinality)
        case .historyTxids:
            await refreshPendingRustHistoryChainTransactions(chainName: chainName, chainId: chainID)
        case .evmReceipt:
            await refreshPendingTransactions(chainName: chainName)
        case .none:
            break
        }
    }

    private func refreshPendingUTXOChainTransactions(
        chainName: String, chainId: String, requireSendKind: Bool = true, tracksFinality: Bool = false
    ) async {
        let tracked = transactions.filter {
            guard requireSendKind ? $0.kind == .send : true,
                $0.chainName == chainName, $0.transactionHash != nil else { return false }
            if tracksFinality { return $0.status == .pending || $0.status == .confirmed }
            return $0.status == .pending
        }
        if tracked.isEmpty {
            if tracksFinality { try? await WalletServiceBridge.shared.retainStatusTrackers(ids: []) }
            return
        }
        if tracksFinality {
            try? await WalletServiceBridge.shared.retainStatusTrackers(
                ids: tracked.map(\.id.uuidString))
        }
        var resolved: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in tracked {
            guard let hash = transaction.transactionHash, await shouldPollTransactionStatus(for: transaction) else { continue }
            do {
                let status = try await WalletServiceBridge.shared.fetchUtxoTxStatusTyped(chainId: chainId, txid: hash)
                let confirmed = status.confirmed
                let confirmations = tracksFinality ? (status.confirmations.map(Int.init) ?? transaction.confirmationCount) : nil
                await markTransactionStatusPollSuccess(
                    for: transaction, resolvedStatus: confirmed ? .confirmed : .pending,
                    confirmations: confirmations)
                resolved[transaction.id] = PendingTransactionStatusResolution(
                    status: confirmed ? .confirmed : .pending,
                    receiptBlockNumber: status.blockHeight.map(Int.init),
                    confirmations: confirmations,
                    dogecoinNetworkFeeDoge: nil)
            } catch { await markTransactionStatusPollFailure(for: transaction) }
        }
        await applyResolvedPendingStatuses(chainName: chainName, resolutions: resolved)
    }

    private func refreshPendingRustHistoryChainTransactions(chainName: String, chainId: String) async {
        // `resolvedAddress(for:chainName:)` already dispatches per chain, so the
        // twelve `resolved<Chain>Address` arguments these wrappers threaded
        // through were naming a function the callee could look up itself.
        await refreshPendingHistoryBackedTransactions(
            chainName: chainName,
            addressResolver: { [self] in resolvedAddress(for: $0, chainName: chainName) }
        ) { address in
            guard let summary = try? await WalletServiceBridge.shared.fetchHistorySummary(chainId: chainId, address: address) else {
                return ([:], true)
            }
            let map: [String: TransactionStatus] = Dictionary(
                uniqueKeysWithValues: summary.confirmedTxids.map { ($0, TransactionStatus.confirmed) })
            return (map, false)
        }
    }

    // MARK: Rust-history-fetch bridges (generic)

    /// The chain id and the two key paths used to be parameters, and all three
    /// were functions of `chainName`: `Chain(displayName:)?.id`,
    /// `\.[historyRunFor: chainName].isRunning` and `.lastUpdatedAt`. Passing
    /// them alongside the name they are built from is the name passed four
    /// times, and every descriptor row paid it twice.
    private func runRustHistoryDiagnosticsForAllWallets<D>(
        chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        record: @escaping @MainActor (String, D) -> Void
    ) async {
        guard let chainId = Chain(displayName: chainName)?.id else { return }
        await runAddressHistoryDiagnosticsForAllWallets(
            chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: record)
    }
    private func runRustHistoryDiagnosticsForWallet<D>(
        walletID: String, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        record: @escaping @MainActor (String, D) -> Void
    ) async {
        guard let chainId = Chain(displayName: chainName)?.id else { return }
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, chainName: chainName,
            resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: record)
    }
    private func runUTXOStyleHistoryDiagnostics(
        chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?
    ) async {
        guard let chainId = Chain(displayName: chainName)?.id else { return }
        await runAddressHistoryDiagnosticsForAllWallets(
            chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistorySummary(chainId: chainId, address: address).entryCount) ?? 0)
                return UtxoHistoryDiagnostics(
                    walletId: "", identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil)
            },
            storeDiagnostics: { walletID, d in
                self.recordUTXOHistoryDiagnostics(
                    chainName: chainName, walletID: walletID,
                    UtxoHistoryDiagnostics(
                        walletId: walletID, identifier: d.identifier, sourceUsed: d.sourceUsed,
                        transactionCount: d.transactionCount, nextCursor: d.nextCursor, error: d.error))
            })
    }
    private func runUTXOStyleHistoryDiagnosticsForWallet(
        walletID: String, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?
    ) async {
        guard let chainId = Chain(displayName: chainName)?.id else { return }
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistorySummary(chainId: chainId, address: address).entryCount) ?? 0)
                return UtxoHistoryDiagnostics(
                    walletId: walletID, identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil
                )
            },
            storeDiagnostics: { _, d in
                self.recordUTXOHistoryDiagnostics(chainName: chainName, walletID: walletID, d)
            })
    }
    /// Fetch Rust history JSON and construct a per-chain diagnostics record.
    /// Counting is now delegated to Rust (`diagnosticsHistoryEntryCount`);
    /// the Swift layer only threads the chain-specific `make` constructor.
    private func rustHistoryFetch<D>(chainId: String, address: String, make: (String, String, Int, String?) -> D) async -> D {
        if let count = try? await WalletServiceBridge.shared.fetchHistorySummary(chainId: chainId, address: address).entryCount {
            return make(address, "rust", Int(count), nil)
        }
        return make(address, "none", 0, "History fetch failed")
    }
}
