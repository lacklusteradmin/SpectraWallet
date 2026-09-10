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

    /// Bitcoin's history diagnostics: run the refresh and show what it says.
    ///
    /// This used to fetch a page per wallet through a second copy of the
    /// refresh's own source selection — HD xpub, stored address, stored xpub —
    /// read the result for a diagnostics row and throw the page away. The
    /// refresh reports which source answered, how many records and what
    /// failed, so this runs it and writes the rows. The page it fetched is
    /// merged rather than discarded, which is what the button on this screen
    /// says it is for.
    func runBitcoinXpubHistoryDiagnostics() async {
        guard !self[historyRunFor: "Bitcoin"].isRunning else { return }
        self[historyRunFor: "Bitcoin"].isRunning = true
        defer { self[historyRunFor: "Bitcoin"].isRunning = false }
        guard wallets.contains(where: { $0.selectedChain == "Bitcoin" }) else {
            self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
            return
        }
        // Bounded like every other probe on this screen. Without it a refresh
        // that never answers leaves `isRunning` set and the button dead for
        // the rest of the session; the rows the refresh already wrote stand.
        try? await withTimeout(seconds: 20) { await self.refreshBitcoinTransactions() }
        self[historyRunFor: "Bitcoin"].lastUpdatedAt = Date()
    }

    // MARK: Chain-agnostic diagnostics dispatch

    /// Run one chain's history diagnostics.
    ///
    /// A table of eight rows stood here, keyed by `Chain`, each naming its own
    /// history driver and its own address resolver. Six had become the generic
    /// path written out: `resolvedAddress(for:chainName:)` resolves every
    /// chain — the EVM family included, which shares one address — so the
    /// resolver column was one expression spelled eight ways, and which fetch
    /// to make is `chain.isEVM`. Bitcoin is the row that still differs: its
    /// diagnostics read an xpub's history page rather than one address's
    /// summary.
    func runHistoryDiagnostics(for chain: Chain) async {
        guard chain != .bitcoin else { return await runBitcoinXpubHistoryDiagnostics() }
        let chainName = chain.displayName
        // An EVM row shows "running" while its indexer call is in flight; the
        // other chains make one summary request and record its result.
        let placeholder: ((String, String) -> HistoryDiagnostics)? =
            chain.isEVM ? { diagnosticsMakeEvmRunning(walletId: $0, address: $1) } : nil
        await runAddressHistoryDiagnosticsForAllWallets(
            chainName: chainName,
            resolveAddress: { [self] in resolvedAddress(for: $0, chainName: chainName) },
            placeholder: placeholder,
            fetchDiagnostics: { [self] walletID, address in
                if chain.isEVM {
                    return await rustEVMHistoryDiagnostics(
                        chainName: chainName, walletID: walletID, address: address)
                }
                return await rustHistoryFetch(chainId: chain.id, walletID: walletID, address: address)
            })
    }
    /// Bitcoin probes its Esplora endpoints and Monero its configured backend;
    /// every other chain's endpoints are the ones the catalog lists, probed the
    /// way the catalog says. Six of the eight rows that used to say this named
    /// the catalog run, two of them through a wrapper that passed the chain's
    /// own name back to it.
    func runEndpointDiagnostics(for chain: Chain) async {
        switch chain {
        case .bitcoin: await runBitcoinEndpointReachabilityDiagnostics()
        case .monero: await runMoneroEndpointReachabilityDiagnostics()
        default: await runCatalogEndpointReachabilityDiagnostics(for: chain.displayName)
        }
    }

    // MARK: Generic history-diagnostic drivers

    /// The run flag and the "last updated" stamp are both `self[historyRunFor:
    /// chainName]`, so neither is a parameter: passing a key path built from an
    /// argument the same call already carries is the argument passed twice.
    private func runAddressHistoryDiagnosticsForAllWallets(
        chainName: String, resolveAddress: (ImportedWallet) -> String?,
        placeholder: ((String, String) -> HistoryDiagnostics)? = nil,
        fetchDiagnostics: (String, String) async -> HistoryDiagnostics
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
        for (wallet, address) in walletsToRefresh {
            if let placeholder {
                recordHistoryDiagnostics(chainName: chainName, placeholder(wallet.id, address))
                markUpdated()
            }
            recordHistoryDiagnostics(chainName: chainName, await fetchDiagnostics(wallet.id, address))
        }
        markUpdated()
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

    /// Bridge to Rust: fused history-fetch-then-build call. Rust owns both
    /// the HTTP fetch and the diagnostics record construction so Swift never
    /// sees the intermediate JSON. Unsupported chain → error record built
    /// on the Rust side via `fetch_evm_history_diagnostics`' fallback path.
    private func rustEVMHistoryDiagnostics(
        chainName: String, walletID: String, address: String
    ) async -> HistoryDiagnostics {
        let chainId = Chain(displayName: chainName)?.id ?? ""
        return (try? await WalletServiceBridge.shared.fetchEVMHistoryDiagnostics(
            chainId: chainId, walletID: walletID, address: address))
            ?? diagnosticsMakeEvmRunning(walletId: walletID, address: address)
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
    // MARK: Pending transaction refresh

    /// Poll one chain's pending transactions for a final status.
    ///
    /// Three loops used to live here, one per poll shape — a UTXO status
    /// endpoint, an address history naming confirmed txids, an EVM receipt.
    /// Each selected the records to poll from this projection of core's store,
    /// asked core whether each was due, fetched, told core the outcome,
    /// collected the resolutions and handed them back to be applied: five
    /// crossings per transaction, for a store core owns. What comes back is
    /// what changed, and this writes the event and the notification — the two
    /// things that are genuinely this platform's.
    func refreshPendingTransactions(chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        let changes = (try? await WalletServiceBridge.shared.pollPendingTransactions(
            chainId: chain.id)) ?? []
        guard !changes.isEmpty else { return }
        await applyPendingStatusChanges(changes)
    }

    // MARK: Rust-history-fetch bridge

    /// One history-summary call, as a diagnostics row.
    ///
    /// Took a `make` closure so each chain could build its own record shape.
    /// There is one shape, so there is nothing to pass.
    private func rustHistoryFetch(
        chainId: String, walletID: String, address: String
    ) async -> HistoryDiagnostics {
        let count = try? await WalletServiceBridge.shared.fetchHistorySummary(
            chainId: chainId, address: address
        ).entryCount
        return HistoryDiagnostics(
            walletId: walletID, identifier: address,
            sourceUsed: count == nil ? "none" : "rust",
            transactionCount: Int32(count ?? 0), scannedCount: nil, nextCursor: nil,
            error: count == nil ? "History fetch failed" : nil, perSource: [])
    }
}
