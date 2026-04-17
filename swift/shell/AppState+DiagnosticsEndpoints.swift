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
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }
        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else { bitcoinHistoryDiagnosticsLastUpdatedAt = Date(); return }
        for wallet in btcWallets { await runBitcoinHistoryDiagnosticsInner(for: wallet) }
    }
    func runBitcoinHistoryDiagnostics(for walletID: String) async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == "Bitcoin" else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }
        await runBitcoinHistoryDiagnosticsInner(for: wallet)
    }
    private func runBitcoinHistoryDiagnosticsInner(for wallet: ImportedWallet) async {
        let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? wallet.name
        do {
            let page = try await withTimeout(seconds: 20) { try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil) }
            if identifier.isEmpty {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: "Wallet has no BTC address or xpub configured.")
            } else {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count), nextCursor: page.nextCursor, error: nil)
            }
        } catch {
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(walletId: wallet.id, identifier: wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? "unknown", sourceUsed: "none", transactionCount: 0, nextCursor: nil, error: error.localizedDescription)
        }
        bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    // MARK: Per-chain runners (one-liners; wire AppState KeyPaths + async refresh)

    func runLitecoinHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin", resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet, tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) }
    func runLitecoinHistoryDiagnostics(for walletID: String) async { await runUTXOStyleHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin", resolveAddress: { self.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet, tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) }
    func runLitecoinEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingLitecoinEndpointHealth, checks: LitecoinBalanceService.diagnosticsChecks(), resultsKP: \.litecoinEndpointHealthResults, tsKP: \.litecoinEndpointHealthLastUpdatedAt) }
    func runBitcoinCashHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.bitcoinCash, isRunningKP: \.isRunningBitcoinCashHistoryDiagnostics, chainName: "Bitcoin Cash", resolveAddress: { self.resolvedBitcoinCashAddress(for: $0) }, diagsKP: \.bitcoinCashHistoryDiagnosticsByWallet, tsKP: \.bitcoinCashHistoryDiagnosticsLastUpdatedAt) }
    func runBitcoinCashEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingBitcoinCashEndpointHealth, checks: BitcoinCashBalanceService.diagnosticsChecks(), resultsKP: \.bitcoinCashEndpointHealthResults, tsKP: \.bitcoinCashEndpointHealthLastUpdatedAt) }
    func runBitcoinSVHistoryDiagnostics() async { await runUTXOStyleHistoryDiagnostics(chainId: SpectraChainID.bitcoinSv, isRunningKP: \.isRunningBitcoinSVHistoryDiagnostics, chainName: "Bitcoin SV", resolveAddress: { self.resolvedBitcoinSVAddress(for: $0) }, diagsKP: \.bitcoinSVHistoryDiagnosticsByWallet, tsKP: \.bitcoinSVHistoryDiagnosticsLastUpdatedAt) }
    func runBitcoinSVEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingBitcoinSVEndpointHealth, checks: BitcoinSVBalanceService.diagnosticsChecks(), resultsKP: \.bitcoinSVEndpointHealthResults, tsKP: \.bitcoinSVEndpointHealthLastUpdatedAt) }
    func runTronHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron", resolveAddress: { self.resolvedTronAddress(for: $0) }, make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) }, diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) }
    func runTronHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron", resolveAddress: { self.resolvedTronAddress(for: $0) }, make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) }, diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) }
    func runTronEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingTronEndpointHealth, checks: TronBalanceService.diagnosticsChecks(), resultsKP: \.tronEndpointHealthResults, tsKP: \.tronEndpointHealthLastUpdatedAt) }
    func runSolanaHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana", resolveAddress: { self.resolvedSolanaAddress(for: $0) }, make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) }, diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) }
    func runSolanaHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana", resolveAddress: { self.resolvedSolanaAddress(for: $0) }, make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) }, diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) }
    func runSolanaEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingSolanaEndpointHealth, checks: SolanaBalanceService.diagnosticsChecks(), resultsKP: \.solanaEndpointHealthResults, tsKP: \.solanaEndpointHealthLastUpdatedAt) }
    func runCardanoHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano", resolveAddress: { self.resolvedCardanoAddress(for: $0) }, make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) }
    func runCardanoHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano", resolveAddress: { self.resolvedCardanoAddress(for: $0) }, make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) }
    func runCardanoEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingCardanoEndpointHealth, checks: CardanoBalanceService.diagnosticsChecks(), resultsKP: \.cardanoEndpointHealthResults, tsKP: \.cardanoEndpointHealthLastUpdatedAt) }
    func runXRPHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger", resolveAddress: { self.resolvedXRPAddress(for: $0) }, make: { XRPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) }
    func runXRPHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger", resolveAddress: { self.resolvedXRPAddress(for: $0) }, make: { XRPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) }
    func runXRPEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingXRPEndpointHealth, checks: XRPBalanceService.diagnosticsChecks(), resultsKP: \.xrpEndpointHealthResults, tsKP: \.xrpEndpointHealthLastUpdatedAt) }
    func runStellarHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar", resolveAddress: { self.resolvedStellarAddress(for: $0) }, make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) }
    func runStellarHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar", resolveAddress: { self.resolvedStellarAddress(for: $0) }, make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) }
    func runStellarEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingStellarEndpointHealth, checks: StellarBalanceService.diagnosticsChecks(), resultsKP: \.stellarEndpointHealthResults, tsKP: \.stellarEndpointHealthLastUpdatedAt) }
    func runMoneroHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero", resolveAddress: { self.resolvedMoneroAddress(for: $0) }, make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) }
    func runMoneroHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero", resolveAddress: { self.resolvedMoneroAddress(for: $0) }, make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) }
    func runSuiHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui", resolveAddress: { self.resolvedSuiAddress(for: $0) }, make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) }
    func runSuiHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui", resolveAddress: { self.resolvedSuiAddress(for: $0) }, make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) }
    func runAptosHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos", resolveAddress: { self.resolvedAptosAddress(for: $0) }, make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) }
    func runAptosHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos", resolveAddress: { self.resolvedAptosAddress(for: $0) }, make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) }
    func runTONHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON", resolveAddress: { self.resolvedTONAddress(for: $0) }, make: { TONHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) }
    func runTONHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON", resolveAddress: { self.resolvedTONAddress(for: $0) }, make: { TONHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) }
    func runICPHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer", resolveAddress: { self.resolvedICPAddress(for: $0) }, make: { ICPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) }
    func runICPHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer", resolveAddress: { self.resolvedICPAddress(for: $0) }, make: { ICPHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) }
    func runNearHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR", resolveAddress: { self.resolvedNearAddress(for: $0) }, make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) }
    func runNearHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR", resolveAddress: { self.resolvedNearAddress(for: $0) }, make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) }
    func runPolkadotHistoryDiagnostics() async { await runRustHistoryDiagnosticsForAllWallets(chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot", resolveAddress: { self.resolvedPolkadotAddress(for: $0) }, make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) }
    func runPolkadotHistoryDiagnostics(for walletID: String) async { await runRustHistoryDiagnosticsForWallet(walletID: walletID, chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot", resolveAddress: { self.resolvedPolkadotAddress(for: $0) }, make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) }, diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) }
    func runSuiEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingSuiEndpointHealth, checks: SuiBalanceService.diagnosticsChecks(), resultsKP: \.suiEndpointHealthResults, tsKP: \.suiEndpointHealthLastUpdatedAt) }
    func runAptosEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingAptosEndpointHealth, checks: AptosBalanceService.diagnosticsChecks(), resultsKP: \.aptosEndpointHealthResults, tsKP: \.aptosEndpointHealthLastUpdatedAt) }
    func runTONEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingTONEndpointHealth, checks: TONBalanceService.diagnosticsChecks(), resultsKP: \.tonEndpointHealthResults, tsKP: \.tonEndpointHealthLastUpdatedAt) }
    func runICPEndpointReachabilityDiagnostics() async { await runSimpleEndpointDiagnostics(isCheckingKP: \.isCheckingICPEndpointHealth, checks: ICPBalanceService.diagnosticsChecks(), resultsKP: \.icpEndpointHealthResults, tsKP: \.icpEndpointHealthLastUpdatedAt) }

    // MARK: Generic history-diagnostic drivers

    func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(isRunning: () -> Bool, setRunning: (Bool) -> Void, chainName: String, resolveAddress: (ImportedWallet) -> String?, fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void, markUpdated: () -> Void) async {
        guard !isRunning() else { return }
        setRunning(true); defer { setRunning(false) }
        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return nil }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else { markUpdated(); return }
        for (wallet, address) in walletsToRefresh { storeDiagnostics(wallet.id, await fetchDiagnostics(address)) }
        markUpdated()
    }
    func runAddressHistoryDiagnosticsForWallet<Diagnostics>(walletID: String, isRunning: () -> Bool, setRunning: (Bool) -> Void, chainName: String, resolveAddress: (ImportedWallet) -> String?, fetchDiagnostics: (String) async -> Diagnostics, storeDiagnostics: (String, Diagnostics) -> Void, markUpdated: () -> Void) async {
        guard !isRunning() else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return }
        setRunning(true); defer { setRunning(false) }
        storeDiagnostics(wallet.id, await fetchDiagnostics(address)); markUpdated()
    }

    // MARK: Custom reachability probes that need inline JSON-RPC parsing

    func runBitcoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinEndpointHealth else { return }
        isCheckingBitcoinEndpointHealth = true; defer { isCheckingBitcoinEndpointHealth = false }
        var results: [BitcoinEndpointHealthResult] = []
        for endpoint in effectiveBitcoinEsploraEndpoints() {
            guard let url = URL(string: endpoint) else { results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")); continue }
            let probe = await probeHTTP(url.appending(path: "blocks/tip/height"))
            results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
            bitcoinEndpointHealthResults = results
            bitcoinEndpointHealthLastUpdatedAt = Date()
        }
    }
    func runMoneroEndpointReachabilityDiagnostics() async {
        guard !isCheckingMoneroEndpointHealth else { return }
        isCheckingMoneroEndpointHealth = true; defer { isCheckingMoneroEndpointHealth = false }
        let trimmedBackendURL = moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBackendURL = trimmedBackendURL.isEmpty ? MoneroBalanceService.defaultPublicBackend.baseURL : trimmedBackendURL
        guard let baseURL = URL(string: resolvedBackendURL) else {
            moneroEndpointHealthResults = [BitcoinEndpointHealthResult(endpoint: "monero.backend.baseURL", reachable: false, statusCode: nil, detail: "Monero backend is not configured.")]
            moneroEndpointHealthLastUpdatedAt = Date(); return
        }
        let probe = await probeHTTP(baseURL.appendingPathComponent("v1/monero/balance"), profile: .diagnostics)
        moneroEndpointHealthResults = [BitcoinEndpointHealthResult(endpoint: baseURL.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail)]
        moneroEndpointHealthLastUpdatedAt = Date()
    }
    func runNearEndpointReachabilityDiagnostics() async {
        guard !isCheckingNearEndpointHealth else { return }
        isCheckingNearEndpointHealth = true; defer { isCheckingNearEndpointHealth = false }
        var results: [BitcoinEndpointHealthResult] = []
        let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())
        for (endpoint, probeURL) in NearBalanceService.diagnosticsChecks() {
            if rpcEndpoints.contains(endpoint) {
                results.append(await probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "status"))
            } else if let url = URL(string: probeURL) {
                let probe = await probeHTTP(url, profile: .diagnostics)
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
            } else {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
            }
        }
        nearEndpointHealthResults = results; nearEndpointHealthLastUpdatedAt = Date()
    }
    func runPolkadotEndpointReachabilityDiagnostics() async {
        guard !isCheckingPolkadotEndpointHealth else { return }
        isCheckingPolkadotEndpointHealth = true; defer { isCheckingPolkadotEndpointHealth = false }
        var results: [BitcoinEndpointHealthResult] = []
        for (endpoint, probeURL) in PolkadotBalanceService.diagnosticsChecks() {
            if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                guard URL(string: probeURL) != nil else { results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")); continue }
                do {
                    let resp = try await httpRequest(method: "GET", url: probeURL, headers: [], body: nil, profile: .diagnostics)
                    let statusCode = Int(resp.statusCode)
                    let reachable = (200 ... 299).contains(statusCode)
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: statusCode, detail: reachable ? "OK" : "HTTP \(statusCode)"))
                } catch { results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription)) }
                continue
            }
            results.append(await probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "chain_getHeader"))
        }
        polkadotEndpointHealthResults = results; polkadotEndpointHealthLastUpdatedAt = Date()
    }
    /// Send a JSON-RPC request to `urlString` with method `rpcMethod` and an
    /// empty params array, then delegate to Rust for the reachability
    /// verdict (`diagnosticsParseJsonrpcProbe`). Swift only handles
    /// transport — parsing lives in `core::diagnostics::aggregate`.
    // Pilot call site for the Rust HTTP migration (Phase 1).
    // Transport + JSON-RPC parse both live in `core::http_ffi::diagnostics_probe_jsonrpc`.
    // Swift owns nothing here beyond URL validation and result wrapping.
    private func probeJSONRPC(endpoint: String, urlString: String, rpcMethod: String) async -> BitcoinEndpointHealthResult {
        guard URL(string: urlString) != nil else {
            return BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL")
        }
        let outcome = await diagnosticsProbeJsonrpc(url: urlString, rpcMethod: rpcMethod)
        let status = outcome.statusCode.map { Int($0) }
        return BitcoinEndpointHealthResult(endpoint: endpoint, reachable: outcome.reachable, statusCode: status, detail: outcome.detail)
    }

    // MARK: EVM history diagnostics

    func runEthereumHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics, resolveAddress: { self.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet, tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt) }
    func runEthereumHistoryDiagnostics(for walletID: String) async { await runEVMHistoryDiagnosticsForWallet(walletID: walletID, chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics, resolveAddress: { self.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet, tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt) }
    func runETCHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Ethereum Classic", runningPath: \.isRunningETCHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Ethereum Classic") }, diagsPath: \.etcHistoryDiagnosticsByWallet, tsPath: \.etcHistoryDiagnosticsLastUpdatedAt) }
    func runBNBHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "BNB Chain") }, diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt) }
    func runBNBHistoryDiagnostics(for walletID: String) async { await runEVMHistoryDiagnosticsForWallet(walletID: walletID, chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "BNB Chain") }, diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt) }
    func runArbitrumHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Arbitrum", runningPath: \.isRunningArbitrumHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Arbitrum") }, diagsPath: \.arbitrumHistoryDiagnosticsByWallet, tsPath: \.arbitrumHistoryDiagnosticsLastUpdatedAt) }
    func runOptimismHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Optimism", runningPath: \.isRunningOptimismHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Optimism") }, diagsPath: \.optimismHistoryDiagnosticsByWallet, tsPath: \.optimismHistoryDiagnosticsLastUpdatedAt) }
    func runAvalancheHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Avalanche", runningPath: \.isRunningAvalancheHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Avalanche") }, diagsPath: \.avalancheHistoryDiagnosticsByWallet, tsPath: \.avalancheHistoryDiagnosticsLastUpdatedAt) }
    func runHyperliquidHistoryDiagnostics() async { await runEVMHistoryDiagnosticsForAllWallets(chainName: "Hyperliquid", runningPath: \.isRunningHyperliquidHistoryDiagnostics, resolveAddress: { self.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") }, diagsPath: \.hyperliquidHistoryDiagnosticsByWallet, tsPath: \.hyperliquidHistoryDiagnosticsLastUpdatedAt) }

    private func runEVMHistoryDiagnosticsForAllWallets(chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>, resolveAddress: (ImportedWallet) -> String?, diagsPath: ReferenceWritableKeyPath<AppState, [String: EthereumTokenTransferHistoryDiagnostics]>, tsPath: ReferenceWritableKeyPath<AppState, Date?>) async {
        guard !self[keyPath: runningPath] else { return }
        self[keyPath: runningPath] = true; defer { self[keyPath: runningPath] = false }
        let walletsToRefresh = wallets.compactMap { w -> (ImportedWallet, String)? in
            guard w.selectedChain == chainName, let a = resolveAddress(w) else { return nil }; return (w, a)
        }
        guard !walletsToRefresh.isEmpty else { self[keyPath: tsPath] = Date(); return }
        for (wallet, address) in walletsToRefresh {
            self[keyPath: diagsPath][wallet.id] = diagnosticsMakeEvmRunning(address: address)
            self[keyPath: tsPath] = Date()
            self[keyPath: diagsPath][wallet.id] = await rustEVMHistoryDiagnostics(chainName: chainName, address: address)
        }
        self[keyPath: tsPath] = Date()
    }
    private func runEVMHistoryDiagnosticsForWallet(walletID: String, chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>, resolveAddress: (ImportedWallet) -> String?, diagsPath: ReferenceWritableKeyPath<AppState, [String: EthereumTokenTransferHistoryDiagnostics]>, tsPath: ReferenceWritableKeyPath<AppState, Date?>) async {
        guard !self[keyPath: runningPath] else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName, let address = resolveAddress(wallet) else { return }
        self[keyPath: runningPath] = true; defer { self[keyPath: runningPath] = false }
        self[keyPath: diagsPath][wallet.id] = diagnosticsMakeEvmRunning(address: address)
        self[keyPath: tsPath] = Date()
        self[keyPath: diagsPath][wallet.id] = await rustEVMHistoryDiagnostics(chainName: chainName, address: address)
        self[keyPath: tsPath] = Date()
    }
    /// Bridge to Rust: fetch EVM history JSON then construct the diagnostics
    /// record in Rust (`diagnosticsMakeEvmSuccess` / `diagnosticsMakeEvmError`).
    private func rustEVMHistoryDiagnostics(chainName: String, address: String) async -> EthereumTokenTransferHistoryDiagnostics {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            return diagnosticsMakeEvmError(address: address, errorDescription: WalletServiceBridgeError.unsupportedChain(chainName).localizedDescription)
        }
        do {
            let historyJSON = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(chainId: chainId, address: address, tokens: [], page: 1, pageSize: 50)
            return diagnosticsMakeEvmSuccess(address: address, historyJson: historyJSON)
        } catch {
            return diagnosticsMakeEvmError(address: address, errorDescription: error.localizedDescription)
        }
    }

    // MARK: EVM endpoint reachability

    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !isCheckingEthereumEndpointHealth else { return }
        isCheckingEthereumEndpointHealth = true; defer { isCheckingEthereumEndpointHealth = false }
        var checks = evmEndpointChecks(chainName: "Ethereum", context: evmChainContext(for: "Ethereum") ?? .ethereum)
        checks.append(contentsOf: [
            ("Etherscan API", URL(string: "https://api.etherscan.io/api?module=stats&action=ethprice")!),
            ("Ethplorer API", URL(string: "https://api.ethplorer.io/getAddressInfo/0x0000000000000000000000000000000000000000?apiKey=freekey")!)
        ].map { ($0.0, $0.1, false) })
        await runLabeledEVMEndpointDiagnostics(checks: checks, setResults: { self.ethereumEndpointHealthResults = $0 }, markUpdated: { self.ethereumEndpointHealthLastUpdatedAt = Date() })
    }
    func runETCEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingETCEndpointHealth, chainName: "Ethereum Classic", context: .ethereumClassic, resultsKP: \.etcEndpointHealthResults, tsKP: \.etcEndpointHealthLastUpdatedAt) }
    func runArbitrumEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingArbitrumEndpointHealth, chainName: "Arbitrum", context: .arbitrum, resultsKP: \.arbitrumEndpointHealthResults, tsKP: \.arbitrumEndpointHealthLastUpdatedAt) }
    func runOptimismEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingOptimismEndpointHealth, chainName: "Optimism", context: .optimism, resultsKP: \.optimismEndpointHealthResults, tsKP: \.optimismEndpointHealthLastUpdatedAt) }
    func runAvalancheEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingAvalancheEndpointHealth, chainName: "Avalanche", context: .avalanche, resultsKP: \.avalancheEndpointHealthResults, tsKP: \.avalancheEndpointHealthLastUpdatedAt) }
    func runHyperliquidEndpointReachabilityDiagnostics() async { await runPureEVMEndpointDiagnostics(isCheckingKP: \.isCheckingHyperliquidEndpointHealth, chainName: "Hyperliquid", context: .hyperliquid, resultsKP: \.hyperliquidEndpointHealthResults, tsKP: \.hyperliquidEndpointHealthLastUpdatedAt) }
    func runBNBEndpointReachabilityDiagnostics() async {
        guard !isCheckingBNBEndpointHealth else { return }
        isCheckingBNBEndpointHealth = true; defer { isCheckingBNBEndpointHealth = false }
        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(contentsOf: [
            ("BscScan API", URL(string: "https://api.bscscan.com/api?module=stats&action=bnbprice")!)
        ].map { ($0.0, $0.1, false) })
        await runLabeledEVMEndpointDiagnostics(checks: checks, setResults: { self.bnbEndpointHealthResults = $0 }, markUpdated: { self.bnbEndpointHealthLastUpdatedAt = Date() })
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
    func runSimpleEndpointReachabilityDiagnostics(checks: [(endpoint: String, probeURL: String)], profile: HttpRetryProfile, setResults: ([BitcoinEndpointHealthResult]) -> Void, markUpdated: () -> Void) async {
        var results: [BitcoinEndpointHealthResult] = []
        for check in checks {
            guard let url = URL(string: check.probeURL) else {
                results.append(BitcoinEndpointHealthResult(endpoint: check.endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(BitcoinEndpointHealthResult(endpoint: check.endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    func runLabeledEVMEndpointDiagnostics(checks: [(label: String, endpoint: URL, isRPC: Bool)], setResults: ([EthereumEndpointHealthResult]) -> Void, markUpdated: () -> Void) async {
        var results: [EthereumEndpointHealthResult] = []
        for check in checks {
            let probe = check.isRPC ? await probeEthereumRPC(check.endpoint) : await probeHTTP(check.endpoint)
            results.append(EthereumEndpointHealthResult(label: check.label, endpoint: check.endpoint.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    private func runSimpleEndpointDiagnostics(isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, checks: [(endpoint: String, probeURL: String)], resultsKP: ReferenceWritableKeyPath<AppState, [BitcoinEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await runSimpleEndpointReachabilityDiagnostics(checks: checks, profile: .diagnostics, setResults: { self[keyPath: resultsKP] = $0 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runPureEVMEndpointDiagnostics(isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, context: EVMChainContext, resultsKP: ReferenceWritableKeyPath<AppState, [EthereumEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await runLabeledEVMEndpointDiagnostics(checks: evmEndpointChecks(chainName: chainName, context: context), setResults: { self[keyPath: resultsKP] = $0 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }

    // MARK: HTTP probes + timeout helper

    func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); throw TimeoutError.timedOut(seconds: seconds) }
            guard let first = try await group.next() else { throw TimeoutError.timedOut(seconds: seconds) }
            group.cancelAll(); return first
        }
    }
    func probeHTTP(_ url: URL, profile: HttpRetryProfile = .diagnostics) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let resp = try await httpRequest(method: "GET", url: url.absoluteString, headers: [], body: nil, profile: profile)
                let statusCode = Int(resp.statusCode)
                return ((200 ..< 300).contains(statusCode), statusCode, "HTTP \(statusCode)")
            }
        } catch { return (false, nil, error.localizedDescription) }
    }
    func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let payload = #"{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}"#
                let resp = try await httpPostJson(url: url.absoluteString, bodyJson: payload, headers: [:])
                let statusCode = Int(resp.status)
                if (200 ..< 300).contains(statusCode) {
                    let trimmed = resp.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode)")
            }
        } catch { return (false, nil, error.localizedDescription) }
    }

    // MARK: Pending transaction refresh (AppState mutation; Swift-native)

    func refreshPendingBitcoinTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin", chainId: SpectraChainID.bitcoin) }
    func refreshPendingBitcoinCashTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash) }
    func refreshPendingBitcoinSVTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv) }
    func refreshPendingLitecoinTransactions() async { await refreshPendingUTXOChainTransactions(chainName: "Litecoin", chainId: SpectraChainID.litecoin, requireSendKind: false) }
    private func refreshPendingUTXOChainTransactions(chainName: String, chainId: UInt32, requireSendKind: Bool = true) async {
        let now = Date()
        let pending = transactions.filter { (requireSendKind ? $0.kind == .send : true) && $0.chainName == chainName && $0.status == .pending && $0.transactionHash != nil }
        guard !pending.isEmpty else { return }
        var resolved: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pending {
            guard let hash = transaction.transactionHash, shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(chainId: chainId, txid: hash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: confirmed ? .confirmed : .pending, now: now)
                resolved[transaction.id] = PendingTransactionStatusResolution(status: confirmed ? .confirmed : .pending, receiptBlockNumber: obj["block_height"] as? Int, confirmations: nil, dogecoinNetworkFeeDoge: nil)
            } catch { markTransactionStatusPollFailure(for: transaction, now: now) }
        }
        applyResolvedPendingTransactionStatuses(resolved, staleFailureIDs: stalePendingFailureIDs(from: pending, now: now), now: now)
    }

    func refreshPendingDogecoinTransactions() async {
        let now = Date()
        let tracked = transactions.filter { transaction in
            transaction.kind == .send && transaction.chainName == "Dogecoin"
                && (transaction.status == .pending || transaction.status == .confirmed)
                && transaction.transactionHash != nil
        }
        guard !tracked.isEmpty else { statusTrackingByTransactionID = [:]; return }
        let trackedIDs = Set(tracked.map(\.id))
        statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedIDs.contains($0.key) }
        var resolved: [UUID: DogecoinTransactionStatus] = [:]
        for transaction in tracked {
            guard let hash = transaction.transactionHash, shouldPollDogecoinStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(chainId: SpectraChainID.dogecoin, txid: hash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let status = DogecoinTransactionStatus(confirmed: obj["confirmed"] as? Bool ?? false, blockHeight: obj["block_height"] as? Int, networkFeeDOGE: nil, confirmations: obj["confirmations"] as? Int)
                resolved[transaction.id] = status
                markDogecoinStatusPollSuccess(for: transaction, status: status, now: now)
            } catch { markDogecoinStatusPollFailure(for: transaction, now: now); continue }
        }
        let staleFailureCandidates = tracked.filter { transaction in
            guard transaction.status == .pending else { return false }
            guard now.timeIntervalSince(transaction.createdAt) >= Self.pendingFailureTimeoutSeconds else { return false }
            return (statusTrackingByTransactionID[transaction.id]?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures
        }
        let staleFailureIDs = Set(staleFailureCandidates.map { $0.id })
        guard !resolved.isEmpty || !staleFailureIDs.isEmpty else { return }
        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        setTransactions(transactions.map { transaction in
            if let status = resolved[transaction.id] {
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                let resolvedConfirmations = status.confirmations ?? transaction.dogecoinConfirmations
                if (resolvedConfirmations ?? 0) >= Self.standardFinalityConfirmations {
                    var tracker = statusTrackingByTransactionID[transaction.id] ?? DogecoinStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = true
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    statusTrackingByTransactionID[transaction.id] = tracker
                }
                return TransactionRecord(id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: resolvedStatus, walletName: transaction.walletName, assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount, address: transaction.address, transactionHash: transaction.transactionHash, receiptBlockNumber: status.blockHeight, receiptGasUsed: transaction.receiptGasUsed, receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: transaction.receiptNetworkFeeEth, feePriorityRaw: transaction.feePriorityRaw, feeRateDescription: transaction.feeRateDescription, confirmationCount: resolvedConfirmations, dogecoinConfirmedNetworkFeeDoge: status.networkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: resolvedConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput, dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex, failureReason: nil, transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt)
            }
            guard staleFailureIDs.contains(transaction.id) else { return transaction }
            return TransactionRecord(id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: .failed, walletName: transaction.walletName, assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount, address: transaction.address, transactionHash: transaction.transactionHash, receiptBlockNumber: transaction.receiptBlockNumber, receiptGasUsed: transaction.receiptGasUsed, receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: transaction.receiptNetworkFeeEth, feePriorityRaw: transaction.feePriorityRaw, feeRateDescription: transaction.feeRateDescription, confirmationCount: transaction.confirmationCount, dogecoinConfirmedNetworkFeeDoge: transaction.dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: transaction.dogecoinConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb, usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput, dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex, failureReason: transaction.failureReason ?? localizedStoreString("Dogecoin transaction appears stuck and could not be confirmed after extended retries."), transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt)
        })
        for (transactionID, status) in resolved {
            guard let oldTransaction = oldByID[transactionID], let newTransaction = transactions.first(where: { $0.id == transactionID }) else { continue }
            if oldTransaction.status != .confirmed, status.confirmed {
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: localizedStoreString("DOGE transaction confirmed."), transactionHash: newTransaction.transactionHash)
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }
            if oldTransaction.dogecoinConfirmations != newTransaction.dogecoinConfirmations, newTransaction.status == .confirmed, let c = newTransaction.dogecoinConfirmations, c >= Self.standardFinalityConfirmations, oldTransaction.dogecoinConfirmations ?? 0 < Self.standardFinalityConfirmations {
                appendChainOperationalEvent(.info, chainName: "Dogecoin", message: localizedStoreFormat("DOGE transaction reached finality (%d confirmations).", c), transactionHash: newTransaction.transactionHash)
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }
        }
        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID], oldTransaction.status != .failed else { continue }
            appendChainOperationalEvent(.error, chainName: "Dogecoin", message: localizedStoreString("DOGE transaction marked failed after extended retries."), transactionHash: oldTransaction.transactionHash)
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }
    }

    func refreshPendingTronTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Tron", chainId: SpectraChainID.tron, addressResolver: resolvedTronAddress) }
    func refreshPendingSolanaTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Solana", chainId: SpectraChainID.solana, addressResolver: resolvedSolanaAddress) }
    func refreshPendingCardanoTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Cardano", chainId: SpectraChainID.cardano, addressResolver: resolvedCardanoAddress) }
    func refreshPendingXRPTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "XRP Ledger", chainId: SpectraChainID.xrp, addressResolver: resolvedXRPAddress) }
    func refreshPendingStellarTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Stellar", chainId: SpectraChainID.stellar, addressResolver: resolvedStellarAddress) }
    func refreshPendingMoneroTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Monero", chainId: SpectraChainID.monero, addressResolver: resolvedMoneroAddress) }
    func refreshPendingSuiTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Sui", chainId: SpectraChainID.sui, addressResolver: resolvedSuiAddress) }
    func refreshPendingAptosTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Aptos", chainId: SpectraChainID.aptos, addressResolver: resolvedAptosAddress) }
    func refreshPendingTONTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "TON", chainId: SpectraChainID.ton, addressResolver: resolvedTONAddress) }
    func refreshPendingICPTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Internet Computer", chainId: SpectraChainID.icp, addressResolver: resolvedICPAddress) }
    func refreshPendingNearTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "NEAR", chainId: SpectraChainID.near, addressResolver: resolvedNearAddress) }
    func refreshPendingPolkadotTransactions() async { await refreshPendingRustHistoryChainTransactions(chainName: "Polkadot", chainId: SpectraChainID.polkadot, addressResolver: resolvedPolkadotAddress) }

    private func refreshPendingRustHistoryChainTransactions(chainName: String, chainId: UInt32, addressResolver: (ImportedWallet) -> String?) async {
        await refreshPendingHistoryBackedTransactions(chainName: chainName, addressResolver: addressResolver) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address) else { return ([:], true) }
            // Rust-side decoder returns confirmed txids; project to Swift's `[String: TransactionStatus]` shape.
            let confirmed = diagnosticsHistoryConfirmedTxids(json: json)
            let map: [String: TransactionStatus] = Dictionary(uniqueKeysWithValues: confirmed.map { ($0, TransactionStatus.confirmed) })
            return (map, false)
        }
    }

    // MARK: Rust-history-fetch bridges (generic)

    private func runRustHistoryDiagnosticsForAllWallets<D>(chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D, diagsKP: ReferenceWritableKeyPath<AppState, [String: D]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        await runAddressHistoryDiagnosticsForAllWallets(isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) }, storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runRustHistoryDiagnosticsForWallet<D>(walletID: String, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D, diagsKP: ReferenceWritableKeyPath<AppState, [String: D]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        await runAddressHistoryDiagnosticsForWallet(walletID: walletID, isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) }, storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnostics(chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, diagsKP: ReferenceWritableKeyPath<AppState, [String: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        await runAddressHistoryDiagnosticsForAllWallets(isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { address in
            let count = Int((try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)).map { diagnosticsHistoryEntryCount(json: $0) } ?? 0)
            return BitcoinHistoryDiagnostics(walletId: "", identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil)
        }, storeDiagnostics: { walletID, d in self[keyPath: diagsKP][walletID] = BitcoinHistoryDiagnostics(walletId: walletID, identifier: d.identifier, sourceUsed: d.sourceUsed, transactionCount: d.transactionCount, nextCursor: d.nextCursor, error: d.error) }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnosticsForWallet(walletID: String, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, resolveAddress: @escaping (ImportedWallet) -> String?, diagsKP: ReferenceWritableKeyPath<AppState, [String: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>) async {
        await runAddressHistoryDiagnosticsForWallet(walletID: walletID, isRunning: { self[keyPath: isRunningKP] }, setRunning: { self[keyPath: isRunningKP] = $0 }, chainName: chainName, resolveAddress: resolveAddress, fetchDiagnostics: { address in
            let count = Int((try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address)).map { diagnosticsHistoryEntryCount(json: $0) } ?? 0)
            return BitcoinHistoryDiagnostics(walletId: walletID, identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil)
        }, storeDiagnostics: { _, d in self[keyPath: diagsKP][walletID] = d }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    /// Fetch Rust history JSON and construct a per-chain diagnostics record.
    /// Counting is now delegated to Rust (`diagnosticsHistoryEntryCount`);
    /// the Swift layer only threads the chain-specific `make` constructor.
    private func rustHistoryFetch<D>(chainId: UInt32, address: String, make: (String, String, Int, String?) -> D) async -> D {
        if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(chainId: chainId, address: address) {
            return make(address, "rust", Int(diagnosticsHistoryEntryCount(json: json)), nil)
        }
        return make(address, "none", 0, "History fetch failed")
    }
}
