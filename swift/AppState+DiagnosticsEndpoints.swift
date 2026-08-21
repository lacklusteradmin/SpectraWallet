import Foundation
import SwiftUI

// This file now forwards diagnostics decoding/aggregation to Rust
// (`core/src/diagnostics/aggregate.rs`). The Swift layer only keeps:
//   * per-chain AppState wiring (KeyPath-driven, tied to SwiftUI reactivity)
//   * HTTP probes via Rust FFI (httpRequest / httpPostJson / diagnosticsProbeJsonrpc)
//   * async orchestration + pending-transaction mutation against
//     AppState's transaction model.
// All pure JSON decoding and diagnostic-record construction has been
// lifted — see `diagnosticsHistoryEntryCount`, `diagnosticsHistorySummary`,
// `diagnosticsMakeEvm{Running,Error,Success}`, and
// `diagnosticsParseJsonrpcProbe` in the generated UniFFI bindings.
@MainActor
extension AppState {
    // MARK: Bitcoin-family history diagnostics

    func runBitcoinHistoryDiagnostics() async {
        guard !self[historyRunFor: "Bitcoin"].isRunning else { return }
        self[historyRunFor: "Bitcoin"].isRunning = true
        defer { self[historyRunFor: "Bitcoin"].isRunning = false }
        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else { self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date(); return }
        for wallet in btcWallets { await runBitcoinHistoryDiagnosticsInner(for: wallet) }
    }
    func runBitcoinHistoryDiagnostics(for walletID: String) async {
        guard !self[historyRunFor: "Bitcoin"].isRunning else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == "Bitcoin" else { return }
        self[historyRunFor: "Bitcoin"].isRunning = true
        defer { self[historyRunFor: "Bitcoin"].isRunning = false }
        await runBitcoinHistoryDiagnosticsInner(for: wallet)
    }
    private func runBitcoinHistoryDiagnosticsInner(for wallet: ImportedWallet) async {
        let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
        do {
            let page = try await withTimeout(seconds: 20) {
                try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil)
            }
            if identifier.isEmpty {
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: "Wallet has no BTC address or xpub configured."))
            } else {
                recordUTXOHistoryDiagnostics(
                    chainName: "Bitcoin", walletID: wallet.id,
                    BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count), nextCursor: page.nextCursor, error: nil))
            }
        } catch {
            recordUTXOHistoryDiagnostics(
                chainName: "Bitcoin", walletID: wallet.id,
                BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? "unknown", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription))
        }
        self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
    }

    // MARK: Chain-agnostic diagnostics dispatch

    struct ChainDiagnosticsDescriptor {
        let runHistory: (AppState) async -> Void
        let runHistoryForWallet: ((AppState, String) async -> Void)?
        let runEndpoints: (AppState) async -> Void
        init(
            runHistory: @escaping (AppState) async -> Void,
            runHistoryForWallet: ((AppState, String) async -> Void)? = nil,
            runEndpoints: @escaping (AppState) async -> Void
        ) {
            self.runHistory = runHistory; self.runHistoryForWallet = runHistoryForWallet; self.runEndpoints = runEndpoints
        }
    }
    static let chainDiagDescriptors: [Chain: ChainDiagnosticsDescriptor] = [
        .bitcoin: .init(
            runHistory: { await $0.runBitcoinHistoryDiagnostics() },
            runHistoryForWallet: { await $0.runBitcoinHistoryDiagnostics(for: $1) },
            runEndpoints: { await $0.runBitcoinEndpointReachabilityDiagnostics() }
        ),
        .dogecoin: .init(
            runHistory: { await $0.runDogecoinHistoryDiagnostics() },
            runEndpoints: { await $0.runDogecoinEndpointReachabilityDiagnostics() }
        ),
        .tron: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: Chain.tron.id, isRunningKP: \.[historyRunFor: "Tron"].isRunning, chainName: "Tron",
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                record: { diagnosticsRecordTron(walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Tron"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: Chain.tron.id, isRunningKP: \.[historyRunFor: "Tron"].isRunning, chainName: "Tron",
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                record: { diagnosticsRecordTron(walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Tron"].lastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.self[endpointHealthFor: "Tron"].isChecking, checks: AppEndpointDirectory.diagnosticsChecks(for: "Tron"),
                resultsKP: \.self[endpointHealthFor: "Tron"].results, tsKP: \.self[endpointHealthFor: "Tron"].lastUpdatedAt) }
        ),
        .solana: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: Chain.solana.id, isRunningKP: \.[historyRunFor: "Solana"].isRunning, chainName: "Solana",
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                record: { diagnosticsRecordSolana(walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Solana"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: Chain.solana.id, isRunningKP: \.[historyRunFor: "Solana"].isRunning, chainName: "Solana",
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                record: { diagnosticsRecordSolana(walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Solana"].lastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.self[endpointHealthFor: "Solana"].isChecking, checks: AppEndpointDirectory.diagnosticsChecks(for: "Solana"),
                resultsKP: \.self[endpointHealthFor: "Solana"].results, tsKP: \.self[endpointHealthFor: "Solana"].lastUpdatedAt) }
        ),
        .monero: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: Chain.monero.id, isRunningKP: \.[historyRunFor: "Monero"].isRunning, chainName: "Monero",
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecordSimple(chainName: "Monero", walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Monero"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: Chain.monero.id, isRunningKP: \.[historyRunFor: "Monero"].isRunning, chainName: "Monero",
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecordSimple(chainName: "Monero", walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "Monero"].lastUpdatedAt) },
            runEndpoints: { await $0.runMoneroEndpointReachabilityDiagnostics() }
        ),
        .near: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: Chain.near.id, isRunningKP: \.[historyRunFor: "NEAR"].isRunning, chainName: "NEAR",
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecordSimple(chainName: "NEAR", walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "NEAR"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: Chain.near.id, isRunningKP: \.[historyRunFor: "NEAR"].isRunning, chainName: "NEAR",
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                record: { diagnosticsRecordSimple(chainName: "NEAR", walletId: $0, entry: $1) }, tsKP: \.[historyRunFor: "NEAR"].lastUpdatedAt) },
            runEndpoints: { await $0.runNearEndpointReachabilityDiagnostics() }
        ),
        .ethereum: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Ethereum", runningPath: \.[historyRunFor: "Ethereum"].isRunning,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) },
                tsPath: \.[historyRunFor: "Ethereum"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: "Ethereum", runningPath: \.[historyRunFor: "Ethereum"].isRunning,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) },
                tsPath: \.[historyRunFor: "Ethereum"].lastUpdatedAt) },
            runEndpoints: { await $0.runEthereumEndpointReachabilityDiagnostics() }
        ),
        .bnbChain: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "BNB Chain", runningPath: \.[historyRunFor: "BNB Chain"].isRunning,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "BNB Chain") },
                tsPath: \.[historyRunFor: "BNB Chain"].lastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: "BNB Chain", runningPath: \.[historyRunFor: "BNB Chain"].isRunning,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "BNB Chain") },
                tsPath: \.[historyRunFor: "BNB Chain"].lastUpdatedAt) },
            runEndpoints: { await $0.runBNBEndpointReachabilityDiagnostics() }
        ),
    ]
    /// Chains whose diagnostics are the shared shape: fetch the history count
    /// for each wallet's address, and probe the endpoints the catalog lists.
    ///
    /// Eight rows of the descriptor table said this, byte-identical but for
    /// the chain name. A chain lands here unless it has a descriptor of its
    /// own, so adding one costs nothing.
    private func runSimpleChainDiagnostics(chainName: String, walletID: String? = nil) async {
        let chainID = Chain(displayName: chainName)?.id ?? ""
        guard !chainID.isEmpty else { return }
        let make: (String, String, Int, String?) -> SimpleHistoryDiagnostics = {
            SimpleHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3)
        }
        if let walletID {
            await runRustHistoryDiagnosticsForWallet(
                walletID: walletID, chainId: chainID,
                isRunningKP: \.[historyRunFor: chainName].isRunning, chainName: chainName,
                resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
                make: make, record: { [self] in recordSimpleHistoryDiagnostics(chainName: chainName, walletID: $0, $1) },
                tsKP: \.[historyRunFor: chainName].lastUpdatedAt)
        } else {
            await runRustHistoryDiagnosticsForAllWallets(
                chainId: chainID, isRunningKP: \.[historyRunFor: chainName].isRunning,
                chainName: chainName,
                resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
                make: make, record: { [self] in recordSimpleHistoryDiagnostics(chainName: chainName, walletID: $0, $1) },
                tsKP: \.[historyRunFor: chainName].lastUpdatedAt)
        }
    }
    /// The EVM family's diagnostics, for chains without a descriptor of their
    /// own. Five rows said this, byte-identical but for the chain name;
    /// Ethereum and BNB Chain keep theirs because their endpoint probes parse
    /// JSON-RPC inline rather than just reaching the host.
    private func runEVMChainDiagnostics(chainName: String, walletID: String? = nil) async {
        if let walletID {
            await runEVMHistoryDiagnosticsForWallet(
                walletID: walletID, chainName: chainName,
                runningPath: \.[historyRunFor: chainName].isRunning,
                resolveAddress: { [self] in resolvedEVMAddress(for: $0, chainName: chainName) },
                tsPath: \.[historyRunFor: chainName].lastUpdatedAt)
        } else {
            await runEVMHistoryDiagnosticsForAllWallets(
                chainName: chainName, runningPath: \.[historyRunFor: chainName].isRunning,
                resolveAddress: { [self] in resolvedEVMAddress(for: $0, chainName: chainName) },
                tsPath: \.[historyRunFor: chainName].lastUpdatedAt)
        }
    }
    /// The UTXO chains' diagnostics. Three rows said this — Litecoin, Bitcoin
    /// Cash and Bitcoin SV — identical but for the chain name. Bitcoin and
    /// Dogecoin keep theirs: Bitcoin's walks an xpub, Dogecoin's counts
    /// history entries directly.
    private func runUTXOChainDiagnostics(chainName: String, walletID: String? = nil) async {
        let chainID = Chain(displayName: chainName)?.id ?? ""
        guard !chainID.isEmpty else { return }
        if let walletID {
            await runUTXOStyleHistoryDiagnosticsForWallet(
                walletID: walletID, chainId: chainID,
                isRunningKP: \.[historyRunFor: chainName].isRunning, chainName: chainName,
                resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
                tsKP: \.[historyRunFor: chainName].lastUpdatedAt)
        } else {
            await runUTXOStyleHistoryDiagnostics(
                chainId: chainID, isRunningKP: \.[historyRunFor: chainName].isRunning,
                chainName: chainName,
                resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
                tsKP: \.[historyRunFor: chainName].lastUpdatedAt)
        }
    }
    private func runEVMChainEndpointDiagnostics(chainName: String) async {
        guard let context = EVMChainContext(chainName: chainName) else { return }
        await runPureEVMEndpointDiagnostics(
            isCheckingKP: \.self[endpointHealthFor: chainName].isChecking, chainName: chainName,
            context: context,
            resultsKP: \.self[endpointHealthFor: chainName].results,
            tsKP: \.self[endpointHealthFor: chainName].lastUpdatedAt)
    }
    private func runSimpleChainEndpointDiagnostics(chainName: String) async {
        await runSimpleEndpointDiagnostics(
            isCheckingKP: \.self[endpointHealthFor: chainName].isChecking,
            checks: AppEndpointDirectory.diagnosticsChecks(for: chainName),
            resultsKP: \.self[endpointHealthFor: chainName].results,
            tsKP: \.self[endpointHealthFor: chainName].lastUpdatedAt)
    }

    func runHistoryDiagnostics(for chain: Chain) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            if (Chain(displayName: chain.displayName)?.isEVM ?? false) {
                return await runEVMChainDiagnostics(chainName: chain.displayName)
            }
            if (Chain(displayName: chain.displayName)?.supportsDeepUTXODiscovery ?? false) {
                return await runUTXOChainDiagnostics(chainName: chain.displayName)
            }
            return await runSimpleChainDiagnostics(chainName: chain.displayName)
        }
        await descriptor.runHistory(self)
    }
    func runHistoryDiagnostics(for chain: Chain, walletID: String) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            if (Chain(displayName: chain.displayName)?.isEVM ?? false) {
                return await runEVMChainDiagnostics(chainName: chain.displayName, walletID: walletID)
            }
            if (Chain(displayName: chain.displayName)?.supportsDeepUTXODiscovery ?? false) {
                return await runUTXOChainDiagnostics(chainName: chain.displayName, walletID: walletID)
            }
            return await runSimpleChainDiagnostics(chainName: chain.displayName, walletID: walletID)
        }
        await descriptor.runHistoryForWallet?(self, walletID)
    }
    func runEndpointDiagnostics(for chain: Chain) async {
        guard let descriptor = Self.chainDiagDescriptors[chain] else {
            return (Chain(displayName: chain.displayName)?.isEVM ?? false)
                ? await runEVMChainEndpointDiagnostics(chainName: chain.displayName)
                : await runSimpleChainEndpointDiagnostics(chainName: chain.displayName)
        }
        await descriptor.runEndpoints(self)
    }

    // MARK: Generic history-diagnostic drivers

    private func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(
        isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void, markUpdated: () -> Void
    ) async {
        guard !self[keyPath: isRunningKP] else { return }
        self[keyPath: isRunningKP] = true; defer { self[keyPath: isRunningKP] = false }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return nil }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else { markUpdated(); return }
        for (wallet, address) in walletsToRefresh { storeDiagnostics(wallet.id, await fetchDiagnostics(address)) }
        markUpdated()
    }
    private func runAddressHistoryDiagnosticsForWallet<Diagnostics>(
        walletID: String, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void, markUpdated: () -> Void
    ) async {
        guard !self[keyPath: isRunningKP] else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName,
            let address = resolveAddress(wallet)
        else { return }
        self[keyPath: isRunningKP] = true; defer { self[keyPath: isRunningKP] = false }
        storeDiagnostics(wallet.id, await fetchDiagnostics(address)); markUpdated()
    }

    // MARK: Custom reachability probes that need inline JSON-RPC parsing

    private func withEndpointCheck(
        _ isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, operation: () async -> Void
    ) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await operation()
    }
    func runBitcoinEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.self[endpointHealthFor: "Bitcoin"].isChecking) {
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
                self[endpointHealthFor: "Bitcoin"].results = results
                self[endpointHealthFor: "Bitcoin"].lastUpdatedAt = Date()
            }
        }
    }
    func runMoneroEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.self[endpointHealthFor: "Monero"].isChecking) {
            let trimmedBackendURL = self.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBackendURL = trimmedBackendURL.isEmpty ? MoneroBalanceService.defaultPublicBackend.baseURL : trimmedBackendURL
            guard let baseURL = URL(string: resolvedBackendURL) else {
                self[endpointHealthFor: "Monero"].results = [
                    EndpointHealthRow(
                        label: "", endpoint: "monero.backend.baseURL", reachable: false, statusCode: nil, detail: "Monero backend is not configured.")
                ]
                self[endpointHealthFor: "Monero"].lastUpdatedAt = Date(); return
            }
            let probe = await self.probeHTTP(baseURL.appendingPathComponent("v1/monero/balance"), profile: .diagnostics)
            self[endpointHealthFor: "Monero"].results = [
                EndpointHealthRow(
                    label: "", endpoint: baseURL.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail)
            ]
            self[endpointHealthFor: "Monero"].lastUpdatedAt = Date()
        }
    }
    func runNearEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.self[endpointHealthFor: "NEAR"].isChecking) {
            var results: [EndpointHealthRow] = []
            let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())
            for check in AppEndpointDirectory.diagnosticsChecks(for: "NEAR") {
                let endpoint = check.endpoint
                let probeURL = check.probeUrl
                if rpcEndpoints.contains(endpoint) {
                    results.append(await self.probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "status"))
                } else if let url = URL(string: probeURL) {
                    let probe = await self.probeHTTP(url, profile: .diagnostics)
                    results.append(
                        EndpointHealthRow(
                            label: "", endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
                } else {
                    results.append(EndpointHealthRow(label: "", endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                }
            }
            self[endpointHealthFor: "NEAR"].results = results; self[endpointHealthFor: "NEAR"].lastUpdatedAt = Date()
        }
    }
    func runPolkadotEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.self[endpointHealthFor: "Polkadot"].isChecking) {
            var results: [EndpointHealthRow] = []
            for check in AppEndpointDirectory.diagnosticsChecks(for: "Polkadot") {
                let endpoint = check.endpoint
                let probeURL = check.probeUrl
                if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                    guard URL(string: probeURL) != nil else {
                        results.append(
                            EndpointHealthRow(label: "", endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                        continue
                    }
                    do {
                        let resp = try await httpRequest(method: "GET", url: probeURL, headers: [], body: nil, profile: .diagnostics)
                        let statusCode = Int32(resp.statusCode)
                        let reachable = (200...299).contains(statusCode)
                        results.append(
                            EndpointHealthRow(
                                label: "", endpoint: endpoint, reachable: reachable, statusCode: statusCode,
                                detail: reachable ? "OK" : "HTTP \(statusCode)"))
                    } catch {
                        results.append(
                            EndpointHealthRow(
                                label: "", endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
                    }
                    continue
                }
                results.append(await self.probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "chain_getHeader"))
            }
            self[endpointHealthFor: "Polkadot"].results = results; self[endpointHealthFor: "Polkadot"].lastUpdatedAt = Date()
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
        chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>, resolveAddress: (ImportedWallet) -> String?,
        tsPath: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: runningPath] else { return }
        self[keyPath: runningPath] = true; defer { self[keyPath: runningPath] = false }
        let walletsToRefresh = wallets.compactMap { w -> (ImportedWallet, String)? in
            guard w.selectedChain == chainName, let a = resolveAddress(w) else { return nil }; return (w, a)
        }
        guard !walletsToRefresh.isEmpty else { self[keyPath: tsPath] = Date(); return }
        for (wallet, address) in walletsToRefresh {
            recordEVMHistoryDiagnostics(chainName: chainName, walletID: wallet.id, diagnosticsMakeEvmRunning(address: address))
            self[keyPath: tsPath] = Date()
            recordEVMHistoryDiagnostics(
            chainName: chainName, walletID: wallet.id,
            await rustEVMHistoryDiagnostics(chainName: chainName, address: address))
        }
        self[keyPath: tsPath] = Date()
    }
    private func runEVMHistoryDiagnosticsForWallet(
        walletID: String, chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>,
        resolveAddress: (ImportedWallet) -> String?,
        tsPath: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: runningPath] else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName,
            let address = resolveAddress(wallet)
        else { return }
        self[keyPath: runningPath] = true; defer { self[keyPath: runningPath] = false }
        recordEVMHistoryDiagnostics(chainName: chainName, walletID: wallet.id, diagnosticsMakeEvmRunning(address: address))
        self[keyPath: tsPath] = Date()
        recordEVMHistoryDiagnostics(
            chainName: chainName, walletID: wallet.id,
            await rustEVMHistoryDiagnostics(chainName: chainName, address: address))
        self[keyPath: tsPath] = Date()
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

    private static let ethereumExplorerProbeChecks: [(label: String, urlString: String)] = [
        ("Etherscan API", "https://api.etherscan.io/api?module=stats&action=ethprice"),
        ("Ethplorer API", "https://api.ethplorer.io/getAddressInfo/0x0000000000000000000000000000000000000000?apiKey=freekey"),
    ]
    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !self[endpointHealthFor: "Ethereum"].isChecking else { return }
        self[endpointHealthFor: "Ethereum"].isChecking = true; defer { self[endpointHealthFor: "Ethereum"].isChecking = false }
        var checks = evmEndpointChecks(chainName: "Ethereum", context: evmChainContext(for: "Ethereum") ?? .ethereum)
        checks.append(
            contentsOf: Self.ethereumExplorerProbeChecks.compactMap { entry in
                URL(string: entry.urlString).map { (entry.label, $0, false) }
            })
        await runLabeledEVMEndpointDiagnostics(
            checks: checks, setResults: { self[endpointHealthFor: "Ethereum"].results = $0 },
            markUpdated: { self[endpointHealthFor: "Ethereum"].lastUpdatedAt = Date() })
    }
    private static let bnbExplorerProbeChecks: [(label: String, urlString: String)] = [
        ("BscScan API", "https://api.bscscan.com/api?module=stats&action=bnbprice")
    ]
    func runBNBEndpointReachabilityDiagnostics() async {
        guard !self[endpointHealthFor: "BNB Chain"].isChecking else { return }
        self[endpointHealthFor: "BNB Chain"].isChecking = true; defer { self[endpointHealthFor: "BNB Chain"].isChecking = false }
        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(
            contentsOf: Self.bnbExplorerProbeChecks.compactMap { entry in
                URL(string: entry.urlString).map { (entry.label, $0, false) }
            })
        await runLabeledEVMEndpointDiagnostics(
            checks: checks, setResults: { self[endpointHealthFor: "BNB Chain"].results = $0 },
            markUpdated: { self[endpointHealthFor: "BNB Chain"].lastUpdatedAt = Date() })
    }
    func evmEndpointChecks(chainName: String, context: EVMChainContext) -> [(label: String, endpoint: URL, isRPC: Bool)] {
        var checks: [(label: String, endpoint: URL, isRPC: Bool)] = []
        if let configured = configuredEVMRPCEndpointURL(for: chainName) { checks.append(("Configured RPC", configured, true)) }
        for rpc in context.defaultRPCEndpoints {
            guard let url = URL(string: rpc), !checks.contains(where: { $0.endpoint == url }) else { continue }
            checks.append(("Fallback RPC", url, true))
        }
        return checks
    }
    func runSimpleEndpointReachabilityDiagnostics(
        checks: [AppEndpointDiagnosticsCheck], profile: HttpRetryProfile, setResults: ([EndpointHealthRow]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [EndpointHealthRow] = []
        for check in checks {
            guard let url = URL(string: check.probeUrl) else {
                results.append(
                    EndpointHealthRow(label: "", endpoint: check.endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(
                EndpointHealthRow(
                    label: "", endpoint: check.endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    func runLabeledEVMEndpointDiagnostics(
        checks: [(label: String, endpoint: URL, isRPC: Bool)], setResults: ([EndpointHealthRow]) -> Void, markUpdated: () -> Void
    ) async {
        var results: [EndpointHealthRow] = []
        for check in checks {
            let probe = check.isRPC ? await probeEthereumRPC(check.endpoint) : await probeHTTP(check.endpoint)
            results.append(
                EndpointHealthRow(
                    label: check.label, endpoint: check.endpoint.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode,
                    detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    private func runSimpleEndpointDiagnostics(
        isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, checks: [AppEndpointDiagnosticsCheck],
        resultsKP: ReferenceWritableKeyPath<AppState, [EndpointHealthRow]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await runSimpleEndpointReachabilityDiagnostics(
            checks: checks, profile: .diagnostics, setResults: { self[keyPath: resultsKP] = $0 },
            markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runPureEVMEndpointDiagnostics(
        isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, context: EVMChainContext,
        resultsKP: ReferenceWritableKeyPath<AppState, [EndpointHealthRow]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await runLabeledEVMEndpointDiagnostics(
            checks: evmEndpointChecks(chainName: chainName, context: context), setResults: { self[keyPath: resultsKP] = $0 },
            markUpdated: { self[keyPath: tsKP] = Date() })
    }

    // MARK: HTTP probes + timeout helper

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
    func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int32?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let payload = #"{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}"#
                let resp = try await httpPostJson(url: url.absoluteString, bodyJson: payload, headers: [:])
                let statusCode = Int32(resp.status)
                if (200..<300).contains(statusCode) {
                    let trimmed = resp.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode)")
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
        let now = Date()
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
        await applyResolvedPendingTransactionStatuses(
            resolved, staleFailureIDs: await stalePendingFailureIDs(from: tracked))
    }

    private func refreshPendingRustHistoryChainTransactions(chainName: String, chainId: String) async {
        // `resolvedAddress(for:chainName:)` already dispatches per chain, so the
        // twelve `resolved<Chain>Address` arguments these wrappers threaded
        // through were naming a function the callee could look up itself.
        await refreshPendingHistoryBackedTransactions(
            chainName: chainName,
            addressResolver: { [self] in resolvedAddress(for: $0, chainName: chainName) }
        ) { address in
            guard let confirmed = try? await WalletServiceBridge.shared.fetchHistoryConfirmedTxids(chainId: chainId, address: address) else {
                return ([:], true)
            }
            let map: [String: TransactionStatus] = Dictionary(uniqueKeysWithValues: confirmed.map { ($0, TransactionStatus.confirmed) })
            return (map, false)
        }
    }

    // MARK: Rust-history-fetch bridges (generic)

    private func runRustHistoryDiagnosticsForAllWallets<D>(
        chainId: String, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        record: @escaping @MainActor (String, D) -> Void, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: record, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runRustHistoryDiagnosticsForWallet<D>(
        walletID: String, chainId: String, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        record: @escaping @MainActor (String, D) -> Void, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: record, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnostics(
        chainId: String, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address)) ?? 0)
                return BitcoinHistoryDiagnostics(
                    walletId: "", identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil)
            },
            storeDiagnostics: { walletID, d in
                self.recordUTXOHistoryDiagnostics(
                    chainName: chainName, walletID: walletID,
                    BitcoinHistoryDiagnostics(
                        walletId: walletID, identifier: d.identifier, sourceUsed: d.sourceUsed,
                        transactionCount: d.transactionCount, nextCursor: d.nextCursor, error: d.error))
            }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnosticsForWallet(
        walletID: String, chainId: String, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address)) ?? 0)
                return BitcoinHistoryDiagnostics(
                    walletId: walletID, identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil
                )
            },
            storeDiagnostics: { _, d in
                self.recordUTXOHistoryDiagnostics(chainName: chainName, walletID: walletID, d)
            }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    /// Fetch Rust history JSON and construct a per-chain diagnostics record.
    /// Counting is now delegated to Rust (`diagnosticsHistoryEntryCount`);
    /// the Swift layer only threads the chain-specific `make` constructor.
    private func rustHistoryFetch<D>(chainId: String, address: String, make: (String, String, Int, String?) -> D) async -> D {
        if let count = try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address) {
            return make(address, "rust", Int(count), nil)
        }
        return make(address, "none", 0, "History fetch failed")
    }
}
