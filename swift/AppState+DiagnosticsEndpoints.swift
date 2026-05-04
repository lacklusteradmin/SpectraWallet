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
            let page = try await withTimeout(seconds: 20) {
                try await self.fetchBitcoinHistoryPage(for: wallet, limit: HistoryPaging.endpointBatchSize, cursor: nil)
            }
            if identifier.isEmpty {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: "missing address/xpub", sourceUsed: "none", transactionCount: 0, nextCursor: nil,
                    error: "Wallet has no BTC address or xpub configured.")
            } else {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: identifier, sourceUsed: page.sourceUsed, transactionCount: Int32(page.snapshots.count),
                    nextCursor: page.nextCursor, error: nil)
            }
        } catch {
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletId: wallet.id, identifier: wallet.bitcoinAddress ?? wallet.bitcoinXpub ?? "unknown", sourceUsed: "none",
                transactionCount: 0, nextCursor: nil, error: error.localizedDescription)
        }
        bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    // MARK: Chain-agnostic diagnostics dispatch

    private struct ChainDiagnosticsDescriptor {
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
    private static let chainDiagDescriptors: [StandardDiagnosticsChain: ChainDiagnosticsDescriptor] = [
        .bitcoin: .init(
            runHistory: { await $0.runBitcoinHistoryDiagnostics() },
            runHistoryForWallet: { await $0.runBitcoinHistoryDiagnostics(for: $1) },
            runEndpoints: { await $0.runBitcoinEndpointReachabilityDiagnostics() }
        ),
        .dogecoin: .init(
            runHistory: { await $0.runDogecoinHistoryDiagnostics() },
            runEndpoints: { await $0.runDogecoinEndpointReachabilityDiagnostics() }
        ),
        .litecoin: .init(
            runHistory: { store in await store.runUTXOStyleHistoryDiagnostics(
                chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin",
                resolveAddress: { store.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet,
                tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runUTXOStyleHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.litecoin, isRunningKP: \.isRunningLitecoinHistoryDiagnostics, chainName: "Litecoin",
                resolveAddress: { store.resolvedLitecoinAddress(for: $0) }, diagsKP: \.litecoinHistoryDiagnosticsByWallet,
                tsKP: \.litecoinHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingLitecoinEndpointHealth, checks: LitecoinBalanceService.diagnosticsChecks(),
                resultsKP: \.litecoinEndpointHealthResults, tsKP: \.litecoinEndpointHealthLastUpdatedAt) }
        ),
        .bitcoinCash: .init(
            runHistory: { store in await store.runUTXOStyleHistoryDiagnostics(
                chainId: SpectraChainID.bitcoinCash, isRunningKP: \.isRunningBitcoinCashHistoryDiagnostics, chainName: "Bitcoin Cash",
                resolveAddress: { store.resolvedBitcoinCashAddress(for: $0) }, diagsKP: \.bitcoinCashHistoryDiagnosticsByWallet,
                tsKP: \.bitcoinCashHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingBitcoinCashEndpointHealth, checks: BitcoinCashBalanceService.diagnosticsChecks(),
                resultsKP: \.bitcoinCashEndpointHealthResults, tsKP: \.bitcoinCashEndpointHealthLastUpdatedAt) }
        ),
        .bitcoinSV: .init(
            runHistory: { store in await store.runUTXOStyleHistoryDiagnostics(
                chainId: SpectraChainID.bitcoinSv, isRunningKP: \.isRunningBitcoinSVHistoryDiagnostics, chainName: "Bitcoin SV",
                resolveAddress: { store.resolvedBitcoinSVAddress(for: $0) }, diagsKP: \.bitcoinSVHistoryDiagnosticsByWallet,
                tsKP: \.bitcoinSVHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingBitcoinSVEndpointHealth, checks: BitcoinSVBalanceService.diagnosticsChecks(),
                resultsKP: \.bitcoinSVEndpointHealthResults, tsKP: \.bitcoinSVEndpointHealthLastUpdatedAt) }
        ),
        .tron: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron",
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.tron, isRunningKP: \.isRunningTronHistoryDiagnostics, chainName: "Tron",
                resolveAddress: { store.resolvedTronAddress(for: $0) },
                make: { TronHistoryDiagnostics(address: $0, tronScanTxCount: Int32($2), tronScanTrc20Count: 0, sourceUsed: $1, error: $3) },
                diagsKP: \.tronHistoryDiagnosticsByWallet, tsKP: \.tronHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingTronEndpointHealth, checks: TronBalanceService.diagnosticsChecks(),
                resultsKP: \.tronEndpointHealthResults, tsKP: \.tronEndpointHealthLastUpdatedAt) }
        ),
        .solana: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana",
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.solana, isRunningKP: \.isRunningSolanaHistoryDiagnostics, chainName: "Solana",
                resolveAddress: { store.resolvedSolanaAddress(for: $0) },
                make: { SolanaHistoryDiagnostics(address: $0, rpcCount: Int32($2), sourceUsed: $1, error: $3) },
                diagsKP: \.solanaHistoryDiagnosticsByWallet, tsKP: \.solanaHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingSolanaEndpointHealth, checks: SolanaBalanceService.diagnosticsChecks(),
                resultsKP: \.solanaEndpointHealthResults, tsKP: \.solanaEndpointHealthLastUpdatedAt) }
        ),
        .cardano: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano",
                resolveAddress: { store.resolvedCardanoAddress(for: $0) },
                make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.cardano, isRunningKP: \.isRunningCardanoHistoryDiagnostics, chainName: "Cardano",
                resolveAddress: { store.resolvedCardanoAddress(for: $0) },
                make: { CardanoHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.cardanoHistoryDiagnosticsByWallet, tsKP: \.cardanoHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingCardanoEndpointHealth, checks: CardanoBalanceService.diagnosticsChecks(),
                resultsKP: \.cardanoEndpointHealthResults, tsKP: \.cardanoEndpointHealthLastUpdatedAt) }
        ),
        .xrp: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger",
                resolveAddress: { store.resolvedXRPAddress(for: $0) },
                make: { XrpHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.xrp, isRunningKP: \.isRunningXRPHistoryDiagnostics, chainName: "XRP Ledger",
                resolveAddress: { store.resolvedXRPAddress(for: $0) },
                make: { XrpHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.xrpHistoryDiagnosticsByWallet, tsKP: \.xrpHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingXRPEndpointHealth, checks: XRPBalanceService.diagnosticsChecks(),
                resultsKP: \.xrpEndpointHealthResults, tsKP: \.xrpEndpointHealthLastUpdatedAt) }
        ),
        .stellar: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar",
                resolveAddress: { store.resolvedStellarAddress(for: $0) },
                make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.stellar, isRunningKP: \.isRunningStellarHistoryDiagnostics, chainName: "Stellar",
                resolveAddress: { store.resolvedStellarAddress(for: $0) },
                make: { StellarHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.stellarHistoryDiagnosticsByWallet, tsKP: \.stellarHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingStellarEndpointHealth, checks: StellarBalanceService.diagnosticsChecks(),
                resultsKP: \.stellarEndpointHealthResults, tsKP: \.stellarEndpointHealthLastUpdatedAt) }
        ),
        .monero: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero",
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.monero, isRunningKP: \.isRunningMoneroHistoryDiagnostics, chainName: "Monero",
                resolveAddress: { store.resolvedMoneroAddress(for: $0) },
                make: { MoneroHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.moneroHistoryDiagnosticsByWallet, tsKP: \.moneroHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runMoneroEndpointReachabilityDiagnostics() }
        ),
        .sui: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui",
                resolveAddress: { store.resolvedSuiAddress(for: $0) },
                make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.sui, isRunningKP: \.isRunningSuiHistoryDiagnostics, chainName: "Sui",
                resolveAddress: { store.resolvedSuiAddress(for: $0) },
                make: { SuiHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.suiHistoryDiagnosticsByWallet, tsKP: \.suiHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingSuiEndpointHealth, checks: SuiBalanceService.diagnosticsChecks(),
                resultsKP: \.suiEndpointHealthResults, tsKP: \.suiEndpointHealthLastUpdatedAt) }
        ),
        .aptos: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos",
                resolveAddress: { store.resolvedAptosAddress(for: $0) },
                make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.aptos, isRunningKP: \.isRunningAptosHistoryDiagnostics, chainName: "Aptos",
                resolveAddress: { store.resolvedAptosAddress(for: $0) },
                make: { AptosHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.aptosHistoryDiagnosticsByWallet, tsKP: \.aptosHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingAptosEndpointHealth, checks: AptosBalanceService.diagnosticsChecks(),
                resultsKP: \.aptosEndpointHealthResults, tsKP: \.aptosEndpointHealthLastUpdatedAt) }
        ),
        .ton: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON",
                resolveAddress: { store.resolvedTONAddress(for: $0) },
                make: { TonHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.ton, isRunningKP: \.isRunningTONHistoryDiagnostics, chainName: "TON",
                resolveAddress: { store.resolvedTONAddress(for: $0) },
                make: { TonHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.tonHistoryDiagnosticsByWallet, tsKP: \.tonHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingTONEndpointHealth, checks: TONBalanceService.diagnosticsChecks(),
                resultsKP: \.tonEndpointHealthResults, tsKP: \.tonEndpointHealthLastUpdatedAt) }
        ),
        .icp: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer",
                resolveAddress: { store.resolvedICPAddress(for: $0) },
                make: { IcpHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.icp, isRunningKP: \.isRunningICPHistoryDiagnostics, chainName: "Internet Computer",
                resolveAddress: { store.resolvedICPAddress(for: $0) },
                make: { IcpHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.icpHistoryDiagnosticsByWallet, tsKP: \.icpHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runSimpleEndpointDiagnostics(
                isCheckingKP: \.isCheckingICPEndpointHealth, checks: ICPBalanceService.diagnosticsChecks(),
                resultsKP: \.icpEndpointHealthResults, tsKP: \.icpEndpointHealthLastUpdatedAt) }
        ),
        .near: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR",
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.near, isRunningKP: \.isRunningNearHistoryDiagnostics, chainName: "NEAR",
                resolveAddress: { store.resolvedNearAddress(for: $0) },
                make: { NearHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.nearHistoryDiagnosticsByWallet, tsKP: \.nearHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runNearEndpointReachabilityDiagnostics() }
        ),
        .polkadot: .init(
            runHistory: { store in await store.runRustHistoryDiagnosticsForAllWallets(
                chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot",
                resolveAddress: { store.resolvedPolkadotAddress(for: $0) },
                make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runRustHistoryDiagnosticsForWallet(
                walletID: id, chainId: SpectraChainID.polkadot, isRunningKP: \.isRunningPolkadotHistoryDiagnostics, chainName: "Polkadot",
                resolveAddress: { store.resolvedPolkadotAddress(for: $0) },
                make: { PolkadotHistoryDiagnostics(address: $0, sourceUsed: $1, transactionCount: Int32($2), error: $3) },
                diagsKP: \.polkadotHistoryDiagnosticsByWallet, tsKP: \.polkadotHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPolkadotEndpointReachabilityDiagnostics() }
        ),
        .ethereum: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet,
                tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: "Ethereum", runningPath: \.isRunningEthereumHistoryDiagnostics,
                resolveAddress: { store.resolvedEthereumAddress(for: $0) }, diagsPath: \.ethereumHistoryDiagnosticsByWallet,
                tsPath: \.ethereumHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runEthereumEndpointReachabilityDiagnostics() }
        ),
        .ethereumClassic: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Ethereum Classic", runningPath: \.isRunningETCHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "Ethereum Classic") },
                diagsPath: \.etcHistoryDiagnosticsByWallet, tsPath: \.etcHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPureEVMEndpointDiagnostics(
                isCheckingKP: \.isCheckingETCEndpointHealth, chainName: "Ethereum Classic", context: .ethereumClassic,
                resultsKP: \.etcEndpointHealthResults, tsKP: \.etcEndpointHealthLastUpdatedAt) }
        ),
        .arbitrum: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Arbitrum", runningPath: \.isRunningArbitrumHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "Arbitrum") },
                diagsPath: \.arbitrumHistoryDiagnosticsByWallet, tsPath: \.arbitrumHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPureEVMEndpointDiagnostics(
                isCheckingKP: \.isCheckingArbitrumEndpointHealth, chainName: "Arbitrum", context: .arbitrum,
                resultsKP: \.arbitrumEndpointHealthResults, tsKP: \.arbitrumEndpointHealthLastUpdatedAt) }
        ),
        .optimism: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Optimism", runningPath: \.isRunningOptimismHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "Optimism") },
                diagsPath: \.optimismHistoryDiagnosticsByWallet, tsPath: \.optimismHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPureEVMEndpointDiagnostics(
                isCheckingKP: \.isCheckingOptimismEndpointHealth, chainName: "Optimism", context: .optimism,
                resultsKP: \.optimismEndpointHealthResults, tsKP: \.optimismEndpointHealthLastUpdatedAt) }
        ),
        .bnb: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "BNB Chain") },
                diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt) },
            runHistoryForWallet: { store, id in await store.runEVMHistoryDiagnosticsForWallet(
                walletID: id, chainName: "BNB Chain", runningPath: \.isRunningBNBHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "BNB Chain") },
                diagsPath: \.bnbHistoryDiagnosticsByWallet, tsPath: \.bnbHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runBNBEndpointReachabilityDiagnostics() }
        ),
        .avalanche: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Avalanche", runningPath: \.isRunningAvalancheHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "Avalanche") },
                diagsPath: \.avalancheHistoryDiagnosticsByWallet, tsPath: \.avalancheHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPureEVMEndpointDiagnostics(
                isCheckingKP: \.isCheckingAvalancheEndpointHealth, chainName: "Avalanche", context: .avalanche,
                resultsKP: \.avalancheEndpointHealthResults, tsKP: \.avalancheEndpointHealthLastUpdatedAt) }
        ),
        .hyperliquid: .init(
            runHistory: { store in await store.runEVMHistoryDiagnosticsForAllWallets(
                chainName: "Hyperliquid", runningPath: \.isRunningHyperliquidHistoryDiagnostics,
                resolveAddress: { store.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") },
                diagsPath: \.hyperliquidHistoryDiagnosticsByWallet, tsPath: \.hyperliquidHistoryDiagnosticsLastUpdatedAt) },
            runEndpoints: { await $0.runPureEVMEndpointDiagnostics(
                isCheckingKP: \.isCheckingHyperliquidEndpointHealth, chainName: "Hyperliquid", context: .hyperliquid,
                resultsKP: \.hyperliquidEndpointHealthResults, tsKP: \.hyperliquidEndpointHealthLastUpdatedAt) }
        ),
    ]
    func runHistoryDiagnostics(for chain: StandardDiagnosticsChain) async {
        await Self.chainDiagDescriptors[chain]?.runHistory(self)
    }
    func runHistoryDiagnostics(for chain: StandardDiagnosticsChain, walletID: String) async {
        await Self.chainDiagDescriptors[chain]?.runHistoryForWallet?(self, walletID)
    }
    func runEndpointDiagnostics(for chain: StandardDiagnosticsChain) async {
        await Self.chainDiagDescriptors[chain]?.runEndpoints(self)
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
        await withEndpointCheck(\.isCheckingBitcoinEndpointHealth) {
            var results: [BitcoinEndpointHealthResult] = []
            for endpoint in self.effectiveBitcoinEsploraEndpoints() {
                guard let url = URL(string: endpoint) else {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                    continue
                }
                let probe = await self.probeHTTP(url.appending(path: "blocks/tip/height"))
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
                self.bitcoinEndpointHealthResults = results
                self.bitcoinEndpointHealthLastUpdatedAt = Date()
            }
        }
    }
    func runMoneroEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.isCheckingMoneroEndpointHealth) {
            let trimmedBackendURL = self.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBackendURL = trimmedBackendURL.isEmpty ? MoneroBalanceService.defaultPublicBackend.baseURL : trimmedBackendURL
            guard let baseURL = URL(string: resolvedBackendURL) else {
                self.moneroEndpointHealthResults = [
                    BitcoinEndpointHealthResult(
                        endpoint: "monero.backend.baseURL", reachable: false, statusCode: nil, detail: "Monero backend is not configured.")
                ]
                self.moneroEndpointHealthLastUpdatedAt = Date(); return
            }
            let probe = await self.probeHTTP(baseURL.appendingPathComponent("v1/monero/balance"), profile: .diagnostics)
            self.moneroEndpointHealthResults = [
                BitcoinEndpointHealthResult(
                    endpoint: baseURL.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail)
            ]
            self.moneroEndpointHealthLastUpdatedAt = Date()
        }
    }
    func runNearEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.isCheckingNearEndpointHealth) {
            var results: [BitcoinEndpointHealthResult] = []
            let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())
            for check in NearBalanceService.diagnosticsChecks() {
                let endpoint = check.endpoint
                let probeURL = check.probeUrl
                if rpcEndpoints.contains(endpoint) {
                    results.append(await self.probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "status"))
                } else if let url = URL(string: probeURL) {
                    let probe = await self.probeHTTP(url, profile: .diagnostics)
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
                } else {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                }
            }
            self.nearEndpointHealthResults = results; self.nearEndpointHealthLastUpdatedAt = Date()
        }
    }
    func runPolkadotEndpointReachabilityDiagnostics() async {
        await withEndpointCheck(\.isCheckingPolkadotEndpointHealth) {
            var results: [BitcoinEndpointHealthResult] = []
            for check in PolkadotBalanceService.diagnosticsChecks() {
                let endpoint = check.endpoint
                let probeURL = check.probeUrl
                if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                    guard URL(string: probeURL) != nil else {
                        results.append(
                            BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                        continue
                    }
                    do {
                        let resp = try await httpRequest(method: "GET", url: probeURL, headers: [], body: nil, profile: .diagnostics)
                        let statusCode = Int(resp.statusCode)
                        let reachable = (200...299).contains(statusCode)
                        results.append(
                            BitcoinEndpointHealthResult(
                                endpoint: endpoint, reachable: reachable, statusCode: statusCode,
                                detail: reachable ? "OK" : "HTTP \(statusCode)"))
                    } catch {
                        results.append(
                            BitcoinEndpointHealthResult(
                                endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
                    }
                    continue
                }
                results.append(await self.probeJSONRPC(endpoint: endpoint, urlString: endpoint, rpcMethod: "chain_getHeader"))
            }
            self.polkadotEndpointHealthResults = results; self.polkadotEndpointHealthLastUpdatedAt = Date()
        }
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

    private func runEVMHistoryDiagnosticsForAllWallets(
        chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>, resolveAddress: (ImportedWallet) -> String?,
        diagsPath: ReferenceWritableKeyPath<AppState, [String: EthereumTokenTransferHistoryDiagnostics]>,
        tsPath: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
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
    private func runEVMHistoryDiagnosticsForWallet(
        walletID: String, chainName: String, runningPath: ReferenceWritableKeyPath<AppState, Bool>,
        resolveAddress: (ImportedWallet) -> String?,
        diagsPath: ReferenceWritableKeyPath<AppState, [String: EthereumTokenTransferHistoryDiagnostics]>,
        tsPath: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: runningPath] else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }), wallet.selectedChain == chainName,
            let address = resolveAddress(wallet)
        else { return }
        self[keyPath: runningPath] = true; defer { self[keyPath: runningPath] = false }
        self[keyPath: diagsPath][wallet.id] = diagnosticsMakeEvmRunning(address: address)
        self[keyPath: tsPath] = Date()
        self[keyPath: diagsPath][wallet.id] = await rustEVMHistoryDiagnostics(chainName: chainName, address: address)
        self[keyPath: tsPath] = Date()
    }
    /// Bridge to Rust: fused history-fetch-then-build call. Rust owns both
    /// the HTTP fetch and the diagnostics record construction so Swift never
    /// sees the intermediate JSON. Unsupported chain → error record built
    /// on the Rust side via `fetch_evm_history_diagnostics`' fallback path.
    private func rustEVMHistoryDiagnostics(chainName: String, address: String) async -> EthereumTokenTransferHistoryDiagnostics {
        let chainId = SpectraChainID.id(for: chainName) ?? 0
        return (try? await WalletServiceBridge.shared.fetchEVMHistoryDiagnostics(chainId: chainId, address: address))
            ?? diagnosticsMakeEvmRunning(address: address)
    }

    // MARK: EVM endpoint reachability

    private static let ethereumExplorerProbeChecks: [(label: String, urlString: String)] = [
        ("Etherscan API", "https://api.etherscan.io/api?module=stats&action=ethprice"),
        ("Ethplorer API", "https://api.ethplorer.io/getAddressInfo/0x0000000000000000000000000000000000000000?apiKey=freekey"),
    ]
    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !isCheckingEthereumEndpointHealth else { return }
        isCheckingEthereumEndpointHealth = true; defer { isCheckingEthereumEndpointHealth = false }
        var checks = evmEndpointChecks(chainName: "Ethereum", context: evmChainContext(for: "Ethereum") ?? .ethereum)
        checks.append(
            contentsOf: Self.ethereumExplorerProbeChecks.compactMap { entry in
                URL(string: entry.urlString).map { (entry.label, $0, false) }
            })
        await runLabeledEVMEndpointDiagnostics(
            checks: checks, setResults: { self.ethereumEndpointHealthResults = $0 },
            markUpdated: { self.ethereumEndpointHealthLastUpdatedAt = Date() })
    }
    private static let bnbExplorerProbeChecks: [(label: String, urlString: String)] = [
        ("BscScan API", "https://api.bscscan.com/api?module=stats&action=bnbprice")
    ]
    func runBNBEndpointReachabilityDiagnostics() async {
        guard !isCheckingBNBEndpointHealth else { return }
        isCheckingBNBEndpointHealth = true; defer { isCheckingBNBEndpointHealth = false }
        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(
            contentsOf: Self.bnbExplorerProbeChecks.compactMap { entry in
                URL(string: entry.urlString).map { (entry.label, $0, false) }
            })
        await runLabeledEVMEndpointDiagnostics(
            checks: checks, setResults: { self.bnbEndpointHealthResults = $0 },
            markUpdated: { self.bnbEndpointHealthLastUpdatedAt = Date() })
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
        checks: [AppEndpointDiagnosticsCheck], profile: HttpRetryProfile, setResults: ([BitcoinEndpointHealthResult]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [BitcoinEndpointHealthResult] = []
        for check in checks {
            guard let url = URL(string: check.probeUrl) else {
                results.append(
                    BitcoinEndpointHealthResult(endpoint: check.endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: check.endpoint, reachable: probe.reachable, statusCode: probe.statusCode, detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    func runLabeledEVMEndpointDiagnostics(
        checks: [(label: String, endpoint: URL, isRPC: Bool)], setResults: ([EthereumEndpointHealthResult]) -> Void, markUpdated: () -> Void
    ) async {
        var results: [EthereumEndpointHealthResult] = []
        for check in checks {
            let probe = check.isRPC ? await probeEthereumRPC(check.endpoint) : await probeHTTP(check.endpoint)
            results.append(
                EthereumEndpointHealthResult(
                    label: check.label, endpoint: check.endpoint.absoluteString, reachable: probe.reachable, statusCode: probe.statusCode,
                    detail: probe.detail))
        }
        setResults(results); markUpdated()
    }
    private func runSimpleEndpointDiagnostics(
        isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, checks: [AppEndpointDiagnosticsCheck],
        resultsKP: ReferenceWritableKeyPath<AppState, [BitcoinEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        guard !self[keyPath: isCheckingKP] else { return }
        self[keyPath: isCheckingKP] = true; defer { self[keyPath: isCheckingKP] = false }
        await runSimpleEndpointReachabilityDiagnostics(
            checks: checks, profile: .diagnostics, setResults: { self[keyPath: resultsKP] = $0 },
            markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runPureEVMEndpointDiagnostics(
        isCheckingKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String, context: EVMChainContext,
        resultsKP: ReferenceWritableKeyPath<AppState, [EthereumEndpointHealthResult]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
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
    func probeHTTP(_ url: URL, profile: HttpRetryProfile = .diagnostics) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let resp = try await httpRequest(method: "GET", url: url.absoluteString, headers: [], body: nil, profile: profile)
                let statusCode = Int(resp.statusCode)
                return ((200..<300).contains(statusCode), statusCode, "HTTP \(statusCode)")
            }
        } catch { return (false, nil, error.localizedDescription) }
    }
    func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                let payload = #"{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}"#
                let resp = try await httpPostJson(url: url.absoluteString, bodyJson: payload, headers: [:])
                let statusCode = Int(resp.status)
                if (200..<300).contains(statusCode) {
                    let trimmed = resp.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode)")
            }
        } catch { return (false, nil, error.localizedDescription) }
    }

    // MARK: Pending transaction refresh (AppState mutation; Swift-native)

    func refreshPendingBitcoinTransactions() async {
        await refreshPendingUTXOChainTransactions(chainName: "Bitcoin", chainId: SpectraChainID.bitcoin)
    }
    func refreshPendingBitcoinCashTransactions() async {
        await refreshPendingUTXOChainTransactions(chainName: "Bitcoin Cash", chainId: SpectraChainID.bitcoinCash)
    }
    func refreshPendingBitcoinSVTransactions() async {
        await refreshPendingUTXOChainTransactions(chainName: "Bitcoin SV", chainId: SpectraChainID.bitcoinSv)
    }
    func refreshPendingLitecoinTransactions() async {
        await refreshPendingUTXOChainTransactions(chainName: "Litecoin", chainId: SpectraChainID.litecoin, requireSendKind: false)
    }
    private func refreshPendingUTXOChainTransactions(
        chainName: String, chainId: UInt32, requireSendKind: Bool = true, tracksFinality: Bool = false
    ) async {
        let now = Date()
        let tracked = transactions.filter {
            guard requireSendKind ? $0.kind == .send : true,
                $0.chainName == chainName, $0.transactionHash != nil else { return false }
            if tracksFinality { return $0.status == .pending || $0.status == .confirmed }
            return $0.status == .pending
        }
        if tracked.isEmpty {
            if tracksFinality { statusTrackingByTransactionID = [:] }
            return
        }
        if tracksFinality {
            let trackedIDs = Set(tracked.map(\.id))
            statusTrackingByTransactionID = statusTrackingByTransactionID.filter { trackedIDs.contains($0.key) }
        }
        var resolved: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in tracked {
            guard let hash = transaction.transactionHash, shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let status = try await WalletServiceBridge.shared.fetchUtxoTxStatusTyped(chainId: chainId, txid: hash)
                let confirmed = status.confirmed
                let confirmations = tracksFinality ? (status.confirmations.map(Int.init) ?? transaction.confirmationCount) : nil
                markTransactionStatusPollSuccess(
                    for: transaction, resolvedStatus: confirmed ? .confirmed : .pending, confirmations: confirmations, now: now
                )
                resolved[transaction.id] = PendingTransactionStatusResolution(
                    status: confirmed ? .confirmed : .pending,
                    receiptBlockNumber: status.blockHeight.map(Int.init),
                    confirmations: confirmations,
                    dogecoinNetworkFeeDoge: nil)
            } catch { markTransactionStatusPollFailure(for: transaction, now: now) }
        }
        applyResolvedPendingTransactionStatuses(resolved, staleFailureIDs: stalePendingFailureIDs(from: tracked, now: now), now: now)
    }

    func refreshPendingDogecoinTransactions() async {
        await refreshPendingUTXOChainTransactions(chainName: "Dogecoin", chainId: SpectraChainID.dogecoin, tracksFinality: true)
    }

    func refreshPendingTronTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Tron", chainId: SpectraChainID.tron, addressResolver: resolvedTronAddress)
    }
    func refreshPendingSolanaTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Solana", chainId: SpectraChainID.solana, addressResolver: resolvedSolanaAddress)
    }
    func refreshPendingCardanoTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Cardano", chainId: SpectraChainID.cardano, addressResolver: resolvedCardanoAddress)
    }
    func refreshPendingXRPTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "XRP Ledger", chainId: SpectraChainID.xrp, addressResolver: resolvedXRPAddress)
    }
    func refreshPendingStellarTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Stellar", chainId: SpectraChainID.stellar, addressResolver: resolvedStellarAddress)
    }
    func refreshPendingMoneroTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Monero", chainId: SpectraChainID.monero, addressResolver: resolvedMoneroAddress)
    }
    func refreshPendingSuiTransactions() async {
        await refreshPendingRustHistoryChainTransactions(chainName: "Sui", chainId: SpectraChainID.sui, addressResolver: resolvedSuiAddress)
    }
    func refreshPendingAptosTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Aptos", chainId: SpectraChainID.aptos, addressResolver: resolvedAptosAddress)
    }
    func refreshPendingTONTransactions() async {
        await refreshPendingRustHistoryChainTransactions(chainName: "TON", chainId: SpectraChainID.ton, addressResolver: resolvedTONAddress)
    }
    func refreshPendingICPTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Internet Computer", chainId: SpectraChainID.icp, addressResolver: resolvedICPAddress)
    }
    func refreshPendingNearTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "NEAR", chainId: SpectraChainID.near, addressResolver: resolvedNearAddress)
    }
    func refreshPendingPolkadotTransactions() async {
        await refreshPendingRustHistoryChainTransactions(
            chainName: "Polkadot", chainId: SpectraChainID.polkadot, addressResolver: resolvedPolkadotAddress)
    }

    private func refreshPendingRustHistoryChainTransactions(
        chainName: String, chainId: UInt32, addressResolver: (ImportedWallet) -> String?
    ) async {
        await refreshPendingHistoryBackedTransactions(chainName: chainName, addressResolver: addressResolver) { address in
            guard let confirmed = try? await WalletServiceBridge.shared.fetchHistoryConfirmedTxids(chainId: chainId, address: address) else {
                return ([:], true)
            }
            let map: [String: TransactionStatus] = Dictionary(uniqueKeysWithValues: confirmed.map { ($0, TransactionStatus.confirmed) })
            return (map, false)
        }
    }

    // MARK: Rust-history-fetch bridges (generic)

    private func runRustHistoryDiagnosticsForAllWallets<D>(
        chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        diagsKP: ReferenceWritableKeyPath<AppState, [String: D]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runRustHistoryDiagnosticsForWallet<D>(
        walletID: String, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?, make: @escaping (String, String, Int, String?) -> D,
        diagsKP: ReferenceWritableKeyPath<AppState, [String: D]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { await self.rustHistoryFetch(chainId: chainId, address: $0, make: make) },
            storeDiagnostics: { self[keyPath: diagsKP][$0] = $1 }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnostics(
        chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        diagsKP: ReferenceWritableKeyPath<AppState, [String: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address)) ?? 0)
                return BitcoinHistoryDiagnostics(
                    walletId: "", identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil)
            },
            storeDiagnostics: { walletID, d in
                self[keyPath: diagsKP][walletID] = BitcoinHistoryDiagnostics(
                    walletId: walletID, identifier: d.identifier, sourceUsed: d.sourceUsed, transactionCount: d.transactionCount,
                    nextCursor: d.nextCursor, error: d.error)
            }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    private func runUTXOStyleHistoryDiagnosticsForWallet(
        walletID: String, chainId: UInt32, isRunningKP: ReferenceWritableKeyPath<AppState, Bool>, chainName: String,
        resolveAddress: @escaping (ImportedWallet) -> String?,
        diagsKP: ReferenceWritableKeyPath<AppState, [String: BitcoinHistoryDiagnostics]>, tsKP: ReferenceWritableKeyPath<AppState, Date?>
    ) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID, isRunningKP: isRunningKP, chainName: chainName, resolveAddress: resolveAddress,
            fetchDiagnostics: { address in
                let count = Int((try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address)) ?? 0)
                return BitcoinHistoryDiagnostics(
                    walletId: walletID, identifier: address, sourceUsed: "rust", transactionCount: Int32(count), nextCursor: nil, error: nil
                )
            }, storeDiagnostics: { _, d in self[keyPath: diagsKP][walletID] = d }, markUpdated: { self[keyPath: tsKP] = Date() })
    }
    /// Fetch Rust history JSON and construct a per-chain diagnostics record.
    /// Counting is now delegated to Rust (`diagnosticsHistoryEntryCount`);
    /// the Swift layer only threads the chain-specific `make` constructor.
    private func rustHistoryFetch<D>(chainId: UInt32, address: String, make: (String, String, Int, String?) -> D) async -> D {
        if let count = try? await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: chainId, address: address) {
            return make(address, "rust", Int(count), nil)
        }
        return make(address, "none", 0, "History fetch failed")
    }
}
