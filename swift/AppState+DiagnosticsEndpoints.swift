import Foundation
import SwiftUI

// Swift holds progress and rendered diagnostics; core owns probes and status updates.
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
        await runCatalogEndpointReachabilityDiagnostics(for: chain.displayName)
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
    func runBitcoinEndpointReachabilityDiagnostics() async { await runCatalogEndpointReachabilityDiagnostics(for: "Bitcoin") }
    func runMoneroEndpointReachabilityDiagnostics() async { await runCatalogEndpointReachabilityDiagnostics(for: "Monero") }
    func runCatalogEndpointReachabilityDiagnostics(for chainName: String) async {
        guard let chain = Chain(displayName: chainName) else { return }
        await withEndpointCheck(for: chainName) { publish in
            do {
                let rows = try await WalletServiceBridge.shared.probeChainEndpoints(chainID: chain.id)
                publish(rows.map { EndpointHealthRow(label: $0.checked ? "" : "Not checked", endpoint: $0.endpoint, reachable: $0.reachable, statusCode: nil, detail: $0.detail) })
            } catch {
                publish([EndpointHealthRow(label: "", endpoint: chainName, reachable: false, statusCode: nil, detail: error.localizedDescription)])
            }
        }
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

/// UI deadline for the history diagnostic action; transport timeouts remain core's.
private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(seconds)); throw AppState.TimeoutError.timedOut(seconds: seconds) }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw AppState.TimeoutError.timedOut(seconds: seconds) }
        return first
    }
}
