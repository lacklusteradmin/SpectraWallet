import Foundation
import SwiftUI

@MainActor
extension WalletStore {
    // MARK: - Diagnostics and Endpoint Health
    func runBitcoinHistoryDiagnostics() async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }

        let btcWallets = wallets.filter { $0.selectedChain == "Bitcoin" }
        guard !btcWallets.isEmpty else {
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for wallet in btcWallets {
            do {
                let page = try await withTimeout(seconds: 20) {
                    try await self.fetchBitcoinHistoryPage(
                        for: wallet,
                        limit: HistoryPaging.endpointBatchSize,
                        cursor: nil
                    )
                }
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
                if identifier.isEmpty {
                    bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                        walletID: wallet.id,
                        identifier: "missing address/xpub",
                        sourceUsed: "none",
                        transactionCount: 0,
                        nextCursor: nil,
                        error: "Wallet has no BTC address or xpub configured."
                    )
                    continue
                }

                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: identifier,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor,
                    error: nil
                )
            } catch {
                let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: identifier,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
            bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    func runBitcoinHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningBitcoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Bitcoin" else { return }
        isRunningBitcoinHistoryDiagnostics = true
        defer { isRunningBitcoinHistoryDiagnostics = false }

        do {
            let page = try await withTimeout(seconds: 20) {
                try await self.fetchBitcoinHistoryPage(
                    for: wallet,
                    limit: HistoryPaging.endpointBatchSize,
                    cursor: nil
                )
            }
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? wallet.name
            if identifier.isEmpty {
                bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: "missing address/xpub",
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: "Wallet has no BTC address or xpub configured."
                )
                bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
                return
            }

            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: page.sourceUsed,
                transactionCount: page.snapshots.count,
                nextCursor: page.nextCursor,
                error: nil
            )
        } catch {
            let identifier = wallet.bitcoinAddress ?? wallet.bitcoinXPub ?? "unknown"
            bitcoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: identifier,
                sourceUsed: "none",
                transactionCount: 0,
                nextCursor: nil,
                error: error.localizedDescription
            )
        }
        bitcoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinEndpointHealth else { return }
        isCheckingBitcoinEndpointHealth = true
        defer { isCheckingBitcoinEndpointHealth = false }

        let endpoints = effectiveBitcoinEsploraEndpoints()
        var results: [BitcoinEndpointHealthResult] = []

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probeTarget = url.appending(path: "blocks/tip/height")
            let probe = await probeHTTP(probeTarget)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
            bitcoinEndpointHealthResults = results
            bitcoinEndpointHealthLastUpdatedAt = Date()
        }
    }

    func runLitecoinHistoryDiagnostics() async {
        guard !isRunningLitecoinHistoryDiagnostics else { return }
        isRunningLitecoinHistoryDiagnostics = true
        defer { isRunningLitecoinHistoryDiagnostics = false }

        let ltcWallets = wallets.filter { $0.selectedChain == "Litecoin" }
        guard !ltcWallets.isEmpty else {
            litecoinHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for wallet in ltcWallets {
            guard let litecoinAddress = resolvedLitecoinAddress(for: wallet) else {
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: "missing litecoin address",
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: "Wallet has no LTC address configured."
                )
                continue
            }

            do {
                let page = try await withTimeout(seconds: 20) {
                    try await LitecoinBalanceService.fetchTransactionPage(
                        for: litecoinAddress,
                        limit: HistoryPaging.endpointBatchSize,
                        cursor: nil
                    )
                }
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: litecoinAddress,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor,
                    error: nil
                )
            } catch {
                litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: litecoinAddress,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
            litecoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }

    func runLitecoinHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningLitecoinHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Litecoin",
              let litecoinAddress = resolvedLitecoinAddress(for: wallet) else { return }
        isRunningLitecoinHistoryDiagnostics = true
        defer { isRunningLitecoinHistoryDiagnostics = false }

        do {
            let page = try await withTimeout(seconds: 20) {
                try await LitecoinBalanceService.fetchTransactionPage(
                    for: litecoinAddress,
                    limit: HistoryPaging.endpointBatchSize,
                    cursor: nil
                )
            }
            litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: litecoinAddress,
                sourceUsed: page.sourceUsed,
                transactionCount: page.snapshots.count,
                nextCursor: page.nextCursor,
                error: nil
            )
        } catch {
            litecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: litecoinAddress,
                sourceUsed: "none",
                transactionCount: 0,
                nextCursor: nil,
                error: error.localizedDescription
            )
        }
        litecoinHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runLitecoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingLitecoinEndpointHealth else { return }
        isCheckingLitecoinEndpointHealth = true
        defer { isCheckingLitecoinEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: LitecoinBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.litecoinEndpointHealthResults = $0 },
            markUpdated: { self.litecoinEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBitcoinCashHistoryDiagnostics() async {
        guard !isRunningBitcoinCashHistoryDiagnostics else { return }
        isRunningBitcoinCashHistoryDiagnostics = true
        defer { isRunningBitcoinCashHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin Cash",
                  let address = resolvedBitcoinCashAddress(for: wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: address,
                sourceUsed: "running",
                transactionCount: 0,
                nextCursor: nil,
                error: "Running..."
            )
            bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let page = try await withTimeout(seconds: 15) {
                    try await BitcoinCashBalanceService.fetchTransactionPage(
                        for: address,
                        limit: HistoryPaging.endpointBatchSize
                    )
                }
                bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor ?? "",
                    error: nil
                )
            } catch {
                bitcoinCashHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
        }

        bitcoinCashHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinCashEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinCashEndpointHealth else { return }
        isCheckingBitcoinCashEndpointHealth = true
        defer { isCheckingBitcoinCashEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: BitcoinCashBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.bitcoinCashEndpointHealthResults = $0 },
            markUpdated: { self.bitcoinCashEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBitcoinSVHistoryDiagnostics() async {
        guard !isRunningBitcoinSVHistoryDiagnostics else { return }
        isRunningBitcoinSVHistoryDiagnostics = true
        defer { isRunningBitcoinSVHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin SV",
                  let address = resolvedBitcoinSVAddress(for: wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                walletID: wallet.id,
                identifier: address,
                sourceUsed: "running",
                transactionCount: 0,
                nextCursor: nil,
                error: "Running..."
            )
            bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                let page = try await withTimeout(seconds: 15) {
                    try await BitcoinSVBalanceService.fetchTransactionPage(
                        for: address,
                        limit: HistoryPaging.endpointBatchSize
                    )
                }
                bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: page.sourceUsed,
                    transactionCount: page.snapshots.count,
                    nextCursor: page.nextCursor ?? "",
                    error: nil
                )
            } catch {
                bitcoinSVHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletID: wallet.id,
                    identifier: address,
                    sourceUsed: "none",
                    transactionCount: 0,
                    nextCursor: nil,
                    error: error.localizedDescription
                )
            }
        }

        bitcoinSVHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBitcoinSVEndpointReachabilityDiagnostics() async {
        guard !isCheckingBitcoinSVEndpointHealth else { return }
        isCheckingBitcoinSVEndpointHealth = true
        defer { isCheckingBitcoinSVEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: BitcoinSVBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.bitcoinSVEndpointHealthResults = $0 },
            markUpdated: { self.bitcoinSVEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runTronHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningTronHistoryDiagnostics },
            setRunning: { self.isRunningTronHistoryDiagnostics = $0 },
            chainName: "Tron",
            resolveAddress: { self.resolvedTronAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.tron, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return TronHistoryDiagnostics(address: address, tronScanTxCount: entries.count, tronScanTRC20Count: 0, sourceUsed: "rust", error: nil)
                }
                return TronHistoryDiagnostics(address: address, tronScanTxCount: 0, tronScanTRC20Count: 0, sourceUsed: "none", error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tronHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tronHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTronHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningTronHistoryDiagnostics },
            setRunning: { self.isRunningTronHistoryDiagnostics = $0 },
            chainName: "Tron",
            resolveAddress: { self.resolvedTronAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.tron, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return TronHistoryDiagnostics(address: address, tronScanTxCount: entries.count, tronScanTRC20Count: 0, sourceUsed: "rust", error: nil)
                }
                return TronHistoryDiagnostics(address: address, tronScanTxCount: 0, tronScanTRC20Count: 0, sourceUsed: "none", error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tronHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tronHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTronEndpointReachabilityDiagnostics() async {
        guard !isCheckingTronEndpointHealth else { return }
        isCheckingTronEndpointHealth = true
        defer { isCheckingTronEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: TronBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.tronEndpointHealthResults = $0 },
            markUpdated: { self.tronEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runSolanaHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningSolanaHistoryDiagnostics },
            setRunning: { self.isRunningSolanaHistoryDiagnostics = $0 },
            chainName: "Solana",
            resolveAddress: { self.resolvedSolanaAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.solana, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return SolanaHistoryDiagnostics(address: address, rpcCount: entries.count, sourceUsed: "rust", error: nil)
                }
                return SolanaHistoryDiagnostics(address: address, rpcCount: 0, sourceUsed: "none", error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.solanaHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.solanaHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSolanaHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningSolanaHistoryDiagnostics },
            setRunning: { self.isRunningSolanaHistoryDiagnostics = $0 },
            chainName: "Solana",
            resolveAddress: { self.resolvedSolanaAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.solana, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return SolanaHistoryDiagnostics(address: address, rpcCount: entries.count, sourceUsed: "rust", error: nil)
                }
                return SolanaHistoryDiagnostics(address: address, rpcCount: 0, sourceUsed: "none", error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.solanaHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.solanaHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSolanaEndpointReachabilityDiagnostics() async {
        guard !isCheckingSolanaEndpointHealth else { return }
        isCheckingSolanaEndpointHealth = true
        defer { isCheckingSolanaEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: SolanaBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.solanaEndpointHealthResults = $0 },
            markUpdated: { self.solanaEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runCardanoHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningCardanoHistoryDiagnostics },
            setRunning: { self.isRunningCardanoHistoryDiagnostics = $0 },
            chainName: "Cardano",
            resolveAddress: { self.resolvedCardanoAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.cardano, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return CardanoHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return CardanoHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.cardanoHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.cardanoHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runCardanoHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningCardanoHistoryDiagnostics },
            setRunning: { self.isRunningCardanoHistoryDiagnostics = $0 },
            chainName: "Cardano",
            resolveAddress: { self.resolvedCardanoAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.cardano, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return CardanoHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return CardanoHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.cardanoHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.cardanoHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runCardanoEndpointReachabilityDiagnostics() async {
        guard !isCheckingCardanoEndpointHealth else { return }
        isCheckingCardanoEndpointHealth = true
        defer { isCheckingCardanoEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: CardanoBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.cardanoEndpointHealthResults = $0 },
            markUpdated: { self.cardanoEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runXRPHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningXRPHistoryDiagnostics },
            setRunning: { self.isRunningXRPHistoryDiagnostics = $0 },
            chainName: "XRP Ledger",
            resolveAddress: { self.resolvedXRPAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.xrp, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return XRPHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return XRPHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.xrpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.xrpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runXRPHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningXRPHistoryDiagnostics },
            setRunning: { self.isRunningXRPHistoryDiagnostics = $0 },
            chainName: "XRP Ledger",
            resolveAddress: { self.resolvedXRPAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.xrp, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return XRPHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return XRPHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.xrpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.xrpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runXRPEndpointReachabilityDiagnostics() async {
        guard !isCheckingXRPEndpointHealth else { return }
        isCheckingXRPEndpointHealth = true
        defer { isCheckingXRPEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: XRPBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.xrpEndpointHealthResults = $0 },
            markUpdated: { self.xrpEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runStellarHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningStellarHistoryDiagnostics },
            setRunning: { self.isRunningStellarHistoryDiagnostics = $0 },
            chainName: "Stellar",
            resolveAddress: { self.resolvedStellarAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.stellar, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return StellarHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return StellarHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.stellarHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.stellarHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runStellarHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningStellarHistoryDiagnostics },
            setRunning: { self.isRunningStellarHistoryDiagnostics = $0 },
            chainName: "Stellar",
            resolveAddress: { self.resolvedStellarAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.stellar, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return StellarHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return StellarHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.stellarHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.stellarHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runStellarEndpointReachabilityDiagnostics() async {
        guard !isCheckingStellarEndpointHealth else { return }
        isCheckingStellarEndpointHealth = true
        defer { isCheckingStellarEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: StellarBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.stellarEndpointHealthResults = $0 },
            markUpdated: { self.stellarEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runMoneroHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningMoneroHistoryDiagnostics },
            setRunning: { self.isRunningMoneroHistoryDiagnostics = $0 },
            chainName: "Monero",
            resolveAddress: { self.resolvedMoneroAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.monero, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return MoneroHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return MoneroHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.moneroHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.moneroHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runMoneroHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningMoneroHistoryDiagnostics },
            setRunning: { self.isRunningMoneroHistoryDiagnostics = $0 },
            chainName: "Monero",
            resolveAddress: { self.resolvedMoneroAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.monero, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return MoneroHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return MoneroHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.moneroHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.moneroHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runMoneroEndpointReachabilityDiagnostics() async {
        guard !isCheckingMoneroEndpointHealth else { return }
        isCheckingMoneroEndpointHealth = true
        defer { isCheckingMoneroEndpointHealth = false }

        guard let baseURL = MoneroBalanceService.configuredBackendBaseURL() else {
            moneroEndpointHealthResults = [
                BitcoinEndpointHealthResult(
                    endpoint: "monero.backend.baseURL",
                    reachable: false,
                    statusCode: nil,
                    detail: "Monero backend is not configured."
                )
            ]
            moneroEndpointHealthLastUpdatedAt = Date()
            return
        }

        let probeURL = baseURL.appendingPathComponent("v1/monero/balance")
        let probe = await probeHTTP(probeURL, profile: .litecoinDiagnostics)
        moneroEndpointHealthResults = [
            BitcoinEndpointHealthResult(
                endpoint: baseURL.absoluteString,
                reachable: probe.reachable,
                statusCode: probe.statusCode,
                detail: probe.detail
            )
        ]
        moneroEndpointHealthLastUpdatedAt = Date()
    }

    func runSuiHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningSuiHistoryDiagnostics },
            setRunning: { self.isRunningSuiHistoryDiagnostics = $0 },
            chainName: "Sui",
            resolveAddress: { self.resolvedSuiAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.sui, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return SuiHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return SuiHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.suiHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.suiHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runSuiHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningSuiHistoryDiagnostics },
            setRunning: { self.isRunningSuiHistoryDiagnostics = $0 },
            chainName: "Sui",
            resolveAddress: { self.resolvedSuiAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.sui, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return SuiHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return SuiHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.suiHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.suiHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runAptosHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningAptosHistoryDiagnostics },
            setRunning: { self.isRunningAptosHistoryDiagnostics = $0 },
            chainName: "Aptos",
            resolveAddress: { self.resolvedAptosAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.aptos, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return AptosHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return AptosHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.aptosHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.aptosHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runAptosHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningAptosHistoryDiagnostics },
            setRunning: { self.isRunningAptosHistoryDiagnostics = $0 },
            chainName: "Aptos",
            resolveAddress: { self.resolvedAptosAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.aptos, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return AptosHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return AptosHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.aptosHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.aptosHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTONHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningTONHistoryDiagnostics },
            setRunning: { self.isRunningTONHistoryDiagnostics = $0 },
            chainName: "TON",
            resolveAddress: { self.resolvedTONAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.ton, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return TONHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return TONHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tonHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tonHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runTONHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningTONHistoryDiagnostics },
            setRunning: { self.isRunningTONHistoryDiagnostics = $0 },
            chainName: "TON",
            resolveAddress: { self.resolvedTONAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.ton, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return TONHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return TONHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.tonHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.tonHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runICPHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningICPHistoryDiagnostics },
            setRunning: { self.isRunningICPHistoryDiagnostics = $0 },
            chainName: "Internet Computer",
            resolveAddress: { self.resolvedICPAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.icp, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return ICPHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return ICPHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.icpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.icpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runICPHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningICPHistoryDiagnostics },
            setRunning: { self.isRunningICPHistoryDiagnostics = $0 },
            chainName: "Internet Computer",
            resolveAddress: { self.resolvedICPAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.icp, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return ICPHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return ICPHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.icpHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.icpHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runNearHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningNearHistoryDiagnostics },
            setRunning: { self.isRunningNearHistoryDiagnostics = $0 },
            chainName: "NEAR",
            resolveAddress: { self.resolvedNearAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.near, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return NearHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return NearHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.nearHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.nearHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runNearHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningNearHistoryDiagnostics },
            setRunning: { self.isRunningNearHistoryDiagnostics = $0 },
            chainName: "NEAR",
            resolveAddress: { self.resolvedNearAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.near, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return NearHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return NearHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.nearHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.nearHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runPolkadotHistoryDiagnostics() async {
        await runAddressHistoryDiagnosticsForAllWallets(
            isRunning: { self.isRunningPolkadotHistoryDiagnostics },
            setRunning: { self.isRunningPolkadotHistoryDiagnostics = $0 },
            chainName: "Polkadot",
            resolveAddress: { self.resolvedPolkadotAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.polkadot, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return PolkadotHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return PolkadotHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.polkadotHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.polkadotHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runPolkadotHistoryDiagnostics(for walletID: UUID) async {
        await runAddressHistoryDiagnosticsForWallet(
            walletID: walletID,
            isRunning: { self.isRunningPolkadotHistoryDiagnostics },
            setRunning: { self.isRunningPolkadotHistoryDiagnostics = $0 },
            chainName: "Polkadot",
            resolveAddress: { self.resolvedPolkadotAddress(for: $0) },
            fetchDiagnostics: { address in
                if let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                    chainId: SpectraChainID.polkadot, address: address
                ) {
                    let entries = decodeRustHistoryJSON(json: json)
                    return PolkadotHistoryDiagnostics(address: address, sourceUsed: "rust", transactionCount: entries.count, error: nil)
                }
                return PolkadotHistoryDiagnostics(address: address, sourceUsed: "none", transactionCount: 0, error: "History fetch failed")
            },
            storeDiagnostics: { walletID, diagnostics in
                self.polkadotHistoryDiagnosticsByWallet[walletID] = diagnostics
            },
            markUpdated: { self.polkadotHistoryDiagnosticsLastUpdatedAt = Date() }
        )
    }

    func runAddressHistoryDiagnosticsForAllWallets<Diagnostics>(
        isRunning: () -> Bool,
        setRunning: (Bool) -> Void,
        chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics,
        storeDiagnostics: (UUID, Diagnostics) -> Void,
        markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        setRunning(true)
        defer { setRunning(false) }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == chainName,
                  let address = resolveAddress(wallet) else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            markUpdated()
            return
        }

        for (wallet, address) in walletsToRefresh {
            let diagnostics = await fetchDiagnostics(address)
            storeDiagnostics(wallet.id, diagnostics)
        }
        markUpdated()
    }

    func runAddressHistoryDiagnosticsForWallet<Diagnostics>(
        walletID: UUID,
        isRunning: () -> Bool,
        setRunning: (Bool) -> Void,
        chainName: String,
        resolveAddress: (ImportedWallet) -> String?,
        fetchDiagnostics: (String) async -> Diagnostics,
        storeDiagnostics: (UUID, Diagnostics) -> Void,
        markUpdated: () -> Void
    ) async {
        guard !isRunning() else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == chainName,
              let address = resolveAddress(wallet) else { return }

        setRunning(true)
        defer { setRunning(false) }

        let diagnostics = await fetchDiagnostics(address)
        storeDiagnostics(wallet.id, diagnostics)
        markUpdated()
    }

    func runSuiEndpointReachabilityDiagnostics() async {
        guard !isCheckingSuiEndpointHealth else { return }
        isCheckingSuiEndpointHealth = true
        defer { isCheckingSuiEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: SuiBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.suiEndpointHealthResults = $0 },
            markUpdated: { self.suiEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runAptosEndpointReachabilityDiagnostics() async {
        guard !isCheckingAptosEndpointHealth else { return }
        isCheckingAptosEndpointHealth = true
        defer { isCheckingAptosEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: AptosBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.aptosEndpointHealthResults = $0 },
            markUpdated: { self.aptosEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runTONEndpointReachabilityDiagnostics() async {
        guard !isCheckingTONEndpointHealth else { return }
        isCheckingTONEndpointHealth = true
        defer { isCheckingTONEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: TONBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.tonEndpointHealthResults = $0 },
            markUpdated: { self.tonEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runICPEndpointReachabilityDiagnostics() async {
        guard !isCheckingICPEndpointHealth else { return }
        isCheckingICPEndpointHealth = true
        defer { isCheckingICPEndpointHealth = false }

        await runSimpleEndpointReachabilityDiagnostics(
            checks: ICPBalanceService.diagnosticsChecks(),
            profile: .litecoinDiagnostics,
            setResults: { self.icpEndpointHealthResults = $0 },
            markUpdated: { self.icpEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runNearEndpointReachabilityDiagnostics() async {
        guard !isCheckingNearEndpointHealth else { return }
        isCheckingNearEndpointHealth = true
        defer { isCheckingNearEndpointHealth = false }

        var results: [BitcoinEndpointHealthResult] = []
        let rpcEndpoints = Set(NearBalanceService.rpcEndpointCatalog())

        for (endpoint, probeURL) in NearBalanceService.diagnosticsChecks() {
            if rpcEndpoints.contains(endpoint) {
                guard let url = URL(string: endpoint) else {
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: false,
                            statusCode: nil,
                            detail: "Invalid URL"
                        )
                    )
                    continue
                }
                do {
                    let payload = try JSONSerialization.data(withJSONObject: [
                        "jsonrpc": "2.0",
                        "id": "spectra-near-health",
                        "method": "status",
                        "params": []
                    ])
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 15
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = payload
                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                    let detail = reachable
                        ? "OK"
                        : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: reachable,
                            statusCode: http?.statusCode,
                            detail: detail
                        )
                    )
                } catch {
                    results.append(
                        BitcoinEndpointHealthResult(
                            endpoint: endpoint,
                            reachable: false,
                            statusCode: nil,
                            detail: error.localizedDescription
                        )
                    )
                }
                continue
            }

            guard let url = URL(string: probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probe = await probeHTTP(url, profile: .litecoinDiagnostics)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }

        nearEndpointHealthResults = results
        nearEndpointHealthLastUpdatedAt = Date()
    }

    func runPolkadotEndpointReachabilityDiagnostics() async {
        guard !isCheckingPolkadotEndpointHealth else { return }
        isCheckingPolkadotEndpointHealth = true
        defer { isCheckingPolkadotEndpointHealth = false }

        var results: [BitcoinEndpointHealthResult] = []

        for (endpoint, probeURL) in PolkadotBalanceService.diagnosticsChecks() {
            if PolkadotBalanceService.sidecarEndpointCatalog().contains(endpoint) {
                guard let url = URL(string: probeURL) else {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                    continue
                }
                do {
                    let (_, response) = try await ProviderHTTP.data(from: url, profile: .litecoinDiagnostics)
                    let http = response as? HTTPURLResponse
                    let reachable = http.map { (200 ... 299).contains($0.statusCode) } ?? false
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: reachable ? "OK" : "HTTP \(http?.statusCode ?? -1)"))
                } catch {
                    results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
                }
                continue
            }

            guard let url = URL(string: endpoint) else {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: "Invalid URL"))
                continue
            }
            do {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0",
                    "id": "spectra-dot-health",
                    "method": "chain_getHeader",
                    "params": []
                ])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinDiagnostics)
                let http = response as? HTTPURLResponse
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let reachable = http.map { (200 ... 299).contains($0.statusCode) } == true && json?["result"] != nil
                let detail = reachable ? "OK" : ((json?["error"] as? [String: Any]).flatMap { $0["message"] as? String } ?? "HTTP \(http?.statusCode ?? -1)")
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: reachable, statusCode: http?.statusCode, detail: detail))
            } catch {
                results.append(BitcoinEndpointHealthResult(endpoint: endpoint, reachable: false, statusCode: nil, detail: error.localizedDescription))
            }
        }

        polkadotEndpointHealthResults = results
        polkadotEndpointHealthLastUpdatedAt = Date()
    }

    func runEthereumHistoryDiagnostics() async {
        guard !isRunningEthereumHistoryDiagnostics else { return }
        isRunningEthereumHistoryDiagnostics = true
        defer { isRunningEthereumHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Ethereum",
                  let ethereumAddress = resolvedEthereumAddress(for: wallet) else {
                return nil
            }
            return (wallet, ethereumAddress)
        }
        guard !walletsToRefresh.isEmpty else {
            ethereumHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            ethereumHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                ethereumHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Ethereum",
                    address: address
                )
            } catch {
                ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        ethereumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runEthereumHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningEthereumHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "Ethereum",
              let address = resolvedEthereumAddress(for: wallet) else { return }

        isRunningEthereumHistoryDiagnostics = true
        defer { isRunningEthereumHistoryDiagnostics = false }

        ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address),
            rpcTransferCount: 0,
            rpcError: "Running...",
            blockscoutTransferCount: 0,
            blockscoutError: nil,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "running"
        )
        ethereumHistoryDiagnosticsLastUpdatedAt = Date()

        do {
            ethereumHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                chainName: "Ethereum",
                address: address
            )
        } catch {
            ethereumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: error.localizedDescription,
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "none"
            )
        }
        ethereumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runETCHistoryDiagnostics() async {
        guard !isRunningETCHistoryDiagnostics else { return }
        isRunningETCHistoryDiagnostics = true
        defer { isRunningETCHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Ethereum Classic",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Ethereum Classic") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            etcHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            etcHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            etcHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                etcHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Ethereum Classic",
                    address: address
                )
            } catch {
                etcHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        etcHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBNBHistoryDiagnostics() async {
        guard !isRunningBNBHistoryDiagnostics else { return }
        isRunningBNBHistoryDiagnostics = true
        defer { isRunningBNBHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "BNB Chain",
                  let address = resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            bnbHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            bnbHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                bnbHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "BNB Chain",
                    address: address
                )
            } catch {
                bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        bnbHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runArbitrumHistoryDiagnostics() async {
        guard !isRunningArbitrumHistoryDiagnostics else { return }
        isRunningArbitrumHistoryDiagnostics = true
        defer { isRunningArbitrumHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Arbitrum",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Arbitrum") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            arbitrumHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            arbitrumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            arbitrumHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                arbitrumHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Arbitrum",
                    address: address
                )
            } catch {
                arbitrumHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        arbitrumHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runOptimismHistoryDiagnostics() async {
        guard !isRunningOptimismHistoryDiagnostics else { return }
        isRunningOptimismHistoryDiagnostics = true
        defer { isRunningOptimismHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Optimism",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Optimism") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            optimismHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            optimismHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            optimismHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                optimismHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Optimism",
                    address: address
                )
            } catch {
                optimismHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        optimismHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runAvalancheHistoryDiagnostics() async {
        guard !isRunningAvalancheHistoryDiagnostics else { return }
        isRunningAvalancheHistoryDiagnostics = true
        defer { isRunningAvalancheHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Avalanche",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Avalanche") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            avalancheHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            avalancheHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            avalancheHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                avalancheHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Avalanche",
                    address: address
                )
            } catch {
                avalancheHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        avalancheHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runHyperliquidHistoryDiagnostics() async {
        guard !isRunningHyperliquidHistoryDiagnostics else { return }
        isRunningHyperliquidHistoryDiagnostics = true
        defer { isRunningHyperliquidHistoryDiagnostics = false }

        let walletsToRefresh = wallets.compactMap { wallet -> (ImportedWallet, String)? in
            guard wallet.selectedChain == "Hyperliquid",
                  let address = resolvedEVMAddress(for: wallet, chainName: "Hyperliquid") else {
                return nil
            }
            return (wallet, address)
        }
        guard !walletsToRefresh.isEmpty else {
            hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()
            return
        }

        for (wallet, address) in walletsToRefresh {
            hyperliquidHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: "Running...",
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "running"
            )
            hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()

            do {
                hyperliquidHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                    chainName: "Hyperliquid",
                    address: address
                )
            } catch {
                hyperliquidHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                    address: normalizeEVMAddress(address),
                    rpcTransferCount: 0,
                    rpcError: error.localizedDescription,
                    blockscoutTransferCount: 0,
                    blockscoutError: nil,
                    etherscanTransferCount: 0,
                    etherscanError: nil,
                    ethplorerTransferCount: 0,
                    ethplorerError: nil,
                    sourceUsed: "none"
                )
            }
        }

        hyperliquidHistoryDiagnosticsLastUpdatedAt = Date()
    }

    func runBNBHistoryDiagnostics(for walletID: UUID) async {
        guard !isRunningBNBHistoryDiagnostics else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }),
              wallet.selectedChain == "BNB Chain",
              let address = resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else { return }

        isRunningBNBHistoryDiagnostics = true
        defer { isRunningBNBHistoryDiagnostics = false }

        bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address),
            rpcTransferCount: 0,
            rpcError: "Running...",
            blockscoutTransferCount: 0,
            blockscoutError: nil,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "running"
        )
        bnbHistoryDiagnosticsLastUpdatedAt = Date()

        do {
            bnbHistoryDiagnosticsByWallet[wallet.id] = try await Self.rustEVMHistoryDiagnostics(
                chainName: "BNB Chain",
                address: address
            )
        } catch {
            bnbHistoryDiagnosticsByWallet[wallet.id] = EthereumTokenTransferHistoryDiagnostics(
                address: normalizeEVMAddress(address),
                rpcTransferCount: 0,
                rpcError: error.localizedDescription,
                blockscoutTransferCount: 0,
                blockscoutError: nil,
                etherscanTransferCount: 0,
                etherscanError: nil,
                ethplorerTransferCount: 0,
                ethplorerError: nil,
                sourceUsed: "none"
            )
        }
        bnbHistoryDiagnosticsLastUpdatedAt = Date()
    }

    // MARK: - Rust EVM history diagnostics helper

    /// Fetch one page of EVM history via Rust and return a populated diagnostics struct.
    /// Counts appear as `etherscanTransferCount`; all other provider counts are zeroed.
    /// Throws `WalletServiceBridgeError.unsupportedChain` for chains not yet in Rust.
    private static func rustEVMHistoryDiagnostics(
        chainName: String,
        address: String
    ) async throws -> EthereumTokenTransferHistoryDiagnostics {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        let historyJSON = try await WalletServiceBridge.shared.fetchEVMHistoryPageJSON(
            chainId: chainId,
            address: address,
            tokens: [],
            page: 1,
            pageSize: 50
        )
        let count: Int
        if let data = historyJSON.data(using: .utf8),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let native = obj["native"] as? [[String: Any]] {
            count = native.count
        } else {
            count = 0
        }
        return EthereumTokenTransferHistoryDiagnostics(
            address: normalizeEVMAddress(address),
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: 0,
            blockscoutError: nil,
            etherscanTransferCount: count,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "rust"
        )
    }

    func runEthereumEndpointReachabilityDiagnostics() async {
        guard !isCheckingEthereumEndpointHealth else { return }
        isCheckingEthereumEndpointHealth = true
        defer { isCheckingEthereumEndpointHealth = false }

        let context = evmChainContext(for: "Ethereum") ?? .ethereum
        var checks = evmEndpointChecks(chainName: "Ethereum", context: context)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.ethereumChainName).map { ($0.0, $0.1, false) })

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.ethereumEndpointHealthResults = $0 },
            markUpdated: { self.ethereumEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runETCEndpointReachabilityDiagnostics() async {
        guard !isCheckingETCEndpointHealth else { return }
        isCheckingETCEndpointHealth = true
        defer { isCheckingETCEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Ethereum Classic", context: .ethereumClassic)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.etcEndpointHealthResults = $0 },
            markUpdated: { self.etcEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runBNBEndpointReachabilityDiagnostics() async {
        guard !isCheckingBNBEndpointHealth else { return }
        isCheckingBNBEndpointHealth = true
        defer { isCheckingBNBEndpointHealth = false }

        var checks = evmEndpointChecks(chainName: "BNB Chain", context: .bnb)
        checks.append(contentsOf: ChainBackendRegistry.EVMExplorerRegistry.diagnosticProbeEntries(for: ChainBackendRegistry.bnbChainName).map { ($0.0, $0.1, false) })

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.bnbEndpointHealthResults = $0 },
            markUpdated: { self.bnbEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runArbitrumEndpointReachabilityDiagnostics() async {
        guard !isCheckingArbitrumEndpointHealth else { return }
        isCheckingArbitrumEndpointHealth = true
        defer { isCheckingArbitrumEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Arbitrum", context: .arbitrum)
        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.arbitrumEndpointHealthResults = $0 },
            markUpdated: { self.arbitrumEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runOptimismEndpointReachabilityDiagnostics() async {
        guard !isCheckingOptimismEndpointHealth else { return }
        isCheckingOptimismEndpointHealth = true
        defer { isCheckingOptimismEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Optimism", context: .optimism)
        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.optimismEndpointHealthResults = $0 },
            markUpdated: { self.optimismEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runAvalancheEndpointReachabilityDiagnostics() async {
        guard !isCheckingAvalancheEndpointHealth else { return }
        isCheckingAvalancheEndpointHealth = true
        defer { isCheckingAvalancheEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Avalanche", context: .avalanche)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.avalancheEndpointHealthResults = $0 },
            markUpdated: { self.avalancheEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func runHyperliquidEndpointReachabilityDiagnostics() async {
        guard !isCheckingHyperliquidEndpointHealth else { return }
        isCheckingHyperliquidEndpointHealth = true
        defer { isCheckingHyperliquidEndpointHealth = false }

        let checks = evmEndpointChecks(chainName: "Hyperliquid", context: .hyperliquid)

        await runLabeledEVMEndpointDiagnostics(
            checks: checks,
            setResults: { self.hyperliquidEndpointHealthResults = $0 },
            markUpdated: { self.hyperliquidEndpointHealthLastUpdatedAt = Date() }
        )
    }

    func evmEndpointChecks(
        chainName: String,
        context: EVMChainContext
    ) -> [(label: String, endpoint: URL, isRPC: Bool)] {
        var checks: [(label: String, endpoint: URL, isRPC: Bool)] = []
        if let configured = configuredEVMRPCEndpointURL(for: chainName) {
            checks.append(("Configured RPC", configured, true))
        }
        for rpc in context.defaultRPCEndpoints {
            guard let url = URL(string: rpc),
                  !checks.contains(where: { $0.endpoint == url }) else {
                continue
            }
            checks.append(("Fallback RPC", url, true))
        }
        return checks
    }

    func runSimpleEndpointReachabilityDiagnostics(
        checks: [(endpoint: String, probeURL: String)],
        profile: NetworkRetryProfile,
        setResults: ([BitcoinEndpointHealthResult]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [BitcoinEndpointHealthResult] = []
        for check in checks {
            guard let url = URL(string: check.probeURL) else {
                results.append(
                    BitcoinEndpointHealthResult(
                        endpoint: check.endpoint,
                        reachable: false,
                        statusCode: nil,
                        detail: "Invalid URL"
                    )
                )
                continue
            }
            let probe = await probeHTTP(url, profile: profile)
            results.append(
                BitcoinEndpointHealthResult(
                    endpoint: check.endpoint,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }

    func runLabeledEVMEndpointDiagnostics(
        checks: [(label: String, endpoint: URL, isRPC: Bool)],
        setResults: ([EthereumEndpointHealthResult]) -> Void,
        markUpdated: () -> Void
    ) async {
        var results: [EthereumEndpointHealthResult] = []
        for check in checks {
            let probe: (reachable: Bool, statusCode: Int?, detail: String)
            if check.isRPC {
                probe = await probeEthereumRPC(check.endpoint)
            } else {
                probe = await probeHTTP(check.endpoint)
            }
            results.append(
                EthereumEndpointHealthResult(
                    label: check.label,
                    endpoint: check.endpoint.absoluteString,
                    reachable: probe.reachable,
                    statusCode: probe.statusCode,
                    detail: probe.detail
                )
            )
        }
        setResults(results)
        markUpdated()
    }

    // Utility wrapper to cap the duration of provider/network calls during refresh.
    func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timedOut(seconds: seconds)
            }

            guard let firstResult = try await group.next() else {
                throw TimeoutError.timedOut(seconds: seconds)
            }
            group.cancelAll()
            return firstResult
        }
    }

    func probeHTTP(
        _ url: URL,
        profile: NetworkRetryProfile = .diagnostics
    ) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (_, response) = try await NetworkResilience.data(for: request, profile: profile)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                if let statusCode {
                    let isSuccess = (200 ..< 300).contains(statusCode)
                    return (isSuccess, statusCode, "HTTP \(statusCode)")
                }
                return (true, nil, "Connected")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    func probeEthereumRPC(_ url: URL) async -> (reachable: Bool, statusCode: Int?, detail: String) {
        do {
            return try await withTimeout(seconds: 10) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = """
                {"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}
                """.data(using: .utf8)

                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                if let statusCode, (200 ..< 300).contains(statusCode) {
                    let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (true, statusCode, trimmed.isEmpty ? "OK" : String(trimmed.prefix(120)))
                }
                return (false, statusCode, "HTTP \(statusCode ?? -1)")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    func refreshPendingBitcoinTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.bitcoin, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                let blockHeight = obj["block_height"] as? Int
                let resolvedStatus: TransactionStatus = confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingBitcoinCashTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin Cash"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.bitcoinCash, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                let blockHeight = obj["block_height"] as? Int
                let resolvedStatus: TransactionStatus = confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingBitcoinSVTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Bitcoin SV"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.bitcoinSv, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                let blockHeight = obj["block_height"] as? Int
                let resolvedStatus: TransactionStatus = confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func refreshPendingLitecoinTransactions() async {
        let now = Date()
        let pendingTransactions = transactions.filter { transaction in
            transaction.chainName == "Litecoin"
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }

        guard !pendingTransactions.isEmpty else { return }

        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for transaction in pendingTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }
            guard shouldPollTransactionStatus(for: transaction, now: now) else { continue }
            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.litecoin, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let confirmed = obj["confirmed"] as? Bool ?? false
                let blockHeight = obj["block_height"] as? Int
                let resolvedStatus: TransactionStatus = confirmed ? .confirmed : .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: blockHeight,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            } catch {
                markTransactionStatusPollFailure(for: transaction, now: now)
                continue
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: pendingTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    // Updates status/confirmations for pending DOGE sends and records operational telemetry.
    func refreshPendingDogecoinTransactions() async {
        let now = Date()
        let trackedTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == "Dogecoin"
                && (transaction.status == .pending || transaction.status == .confirmed)
                && transaction.transactionHash != nil
        }

        guard !trackedTransactions.isEmpty else {
            dogecoinStatusTrackingByTransactionID = [:]
            return
        }

        let trackedIDs = Set(trackedTransactions.map(\.id))
        dogecoinStatusTrackingByTransactionID = dogecoinStatusTrackingByTransactionID.filter { trackedIDs.contains($0.key) }

        var resolvedStatuses: [UUID: DogecoinTransactionStatus] = [:]

        for transaction in trackedTransactions {
            guard let transactionHash = transaction.transactionHash else { continue }

            if !shouldPollDogecoinStatus(for: transaction, now: now) {
                continue
            }

            do {
                let json = try await WalletServiceBridge.shared.fetchUTXOTxStatusJSON(
                    chainId: SpectraChainID.dogecoin, txid: transactionHash)
                let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let status = DogecoinTransactionStatus(
                    confirmed: obj["confirmed"] as? Bool ?? false,
                    blockHeight: obj["block_height"] as? Int,
                    networkFeeDOGE: nil,
                    confirmations: (obj["confirmations"] as? Int)
                )
                resolvedStatuses[transaction.id] = status
                markDogecoinStatusPollSuccess(
                    for: transaction,
                    status: status,
                    now: now
                )
            } catch {
                markDogecoinStatusPollFailure(for: transaction, now: now)
                continue
            }
        }

        let staleFailureCandidates = trackedTransactions.filter { transaction in
            guard transaction.status == .pending else { return false }
            let age = now.timeIntervalSince(transaction.createdAt)
            guard age >= Self.pendingFailureTimeoutSeconds else { return false }
            let tracker = dogecoinStatusTrackingByTransactionID[transaction.id]
            return (tracker?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures
        }
        let staleFailureIDs = Set(staleFailureCandidates.map { $0.id })

        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }

        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        transactions = transactions.map { transaction in
            if let status = resolvedStatuses[transaction.id] {
                let resolvedStatus: TransactionStatus = status.confirmed ? .confirmed : .pending
                let resolvedConfirmations = status.confirmations ?? transaction.dogecoinConfirmations
                let reachedFinality = (resolvedConfirmations ?? 0) >= Self.standardFinalityConfirmations
                if reachedFinality {
                    var tracker = dogecoinStatusTrackingByTransactionID[transaction.id] ?? DogecoinStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = true
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    dogecoinStatusTrackingByTransactionID[transaction.id] = tracker
                }

                return TransactionRecord(
                    id: transaction.id,
                    walletID: transaction.walletID,
                    kind: transaction.kind,
                    status: resolvedStatus,
                    walletName: transaction.walletName,
                    assetName: transaction.assetName,
                    symbol: transaction.symbol,
                    chainName: transaction.chainName,
                    amount: transaction.amount,
                    address: transaction.address,
                    transactionHash: transaction.transactionHash,
                    receiptBlockNumber: status.blockHeight,
                    receiptGasUsed: transaction.receiptGasUsed,
                    receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
                    receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
                    feePriorityRaw: transaction.feePriorityRaw,
                    feeRateDescription: transaction.feeRateDescription,
                    confirmationCount: resolvedConfirmations,
                    dogecoinConfirmedNetworkFeeDOGE: status.networkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDOGE,
                    dogecoinConfirmations: resolvedConfirmations,
                    dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
                    dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
                    usedChangeOutput: transaction.usedChangeOutput,
                    dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
                    dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
                    failureReason: nil,
                    transactionHistorySource: transaction.transactionHistorySource,
                    createdAt: transaction.createdAt
                )
            }

            guard staleFailureIDs.contains(transaction.id) else { return transaction }

            return TransactionRecord(
                id: transaction.id,
                walletID: transaction.walletID,
                kind: transaction.kind,
                status: .failed,
                walletName: transaction.walletName,
                assetName: transaction.assetName,
                symbol: transaction.symbol,
                chainName: transaction.chainName,
                amount: transaction.amount,
                address: transaction.address,
                transactionHash: transaction.transactionHash,
                receiptBlockNumber: transaction.receiptBlockNumber,
                receiptGasUsed: transaction.receiptGasUsed,
                receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
                receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
                feePriorityRaw: transaction.feePriorityRaw,
                feeRateDescription: transaction.feeRateDescription,
                confirmationCount: transaction.confirmationCount,
                dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
                dogecoinConfirmations: transaction.dogecoinConfirmations,
                dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
                dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
                usedChangeOutput: transaction.usedChangeOutput,
                dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
                dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
                failureReason: transaction.failureReason ?? localizedStoreString("Dogecoin transaction appears stuck and could not be confirmed after extended retries."),
                transactionHistorySource: transaction.transactionHistorySource,
                createdAt: transaction.createdAt
            )
        }

        for (transactionID, status) in resolvedStatuses {
            guard let oldTransaction = oldByID[transactionID],
                  let newTransaction = transactions.first(where: { $0.id == transactionID }) else {
                continue
            }

            if oldTransaction.status != .confirmed, status.confirmed {
                appendChainOperationalEvent(
                    .info,
                    chainName: "Dogecoin",
                    message: localizedStoreString("DOGE transaction confirmed."),
                    transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }

            if oldTransaction.dogecoinConfirmations != newTransaction.dogecoinConfirmations,
               newTransaction.status == .confirmed,
               let confirmations = newTransaction.dogecoinConfirmations,
               confirmations >= Self.standardFinalityConfirmations,
               oldTransaction.dogecoinConfirmations ?? 0 < Self.standardFinalityConfirmations {
                appendChainOperationalEvent(
                    .info,
                    chainName: "Dogecoin",
                    message: localizedStoreFormat("DOGE transaction reached finality (%d confirmations).", confirmations),
                    transactionHash: newTransaction.transactionHash
                )
                sendTransactionStatusNotification(for: oldTransaction, newStatus: .confirmed)
            }
        }

        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID],
                  oldTransaction.status != .failed else {
                continue
            }
            appendChainOperationalEvent(
                .error,
                chainName: "Dogecoin",
                message: localizedStoreString("DOGE transaction marked failed after extended retries."),
                transactionHash: oldTransaction.transactionHash
            )
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }
    }

    func refreshPendingTronTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Tron",
            addressResolver: { self.resolvedTronAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.tron, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingSolanaTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Solana",
            addressResolver: { self.resolvedSolanaAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.solana, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingCardanoTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Cardano",
            addressResolver: { self.resolvedCardanoAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.cardano, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingXRPTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "XRP Ledger",
            addressResolver: { self.resolvedXRPAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.xrp, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingStellarTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Stellar",
            addressResolver: { self.resolvedStellarAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.stellar, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingMoneroTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Monero",
            addressResolver: { self.resolvedMoneroAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.monero, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingSuiTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Sui",
            addressResolver: { self.resolvedSuiAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.sui, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingAptosTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Aptos",
            addressResolver: { self.resolvedAptosAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.aptos, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingTONTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "TON",
            addressResolver: { self.resolvedTONAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.ton, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingICPTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Internet Computer",
            addressResolver: { self.resolvedICPAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.icp, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingNearTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "NEAR",
            addressResolver: { self.resolvedNearAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.near, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    func refreshPendingPolkadotTransactions() async {
        await refreshPendingHistoryBackedTransactions(
            chainName: "Polkadot",
            addressResolver: { self.resolvedPolkadotAddress(for: $0) }
        ) { address in
            guard let json = try? await WalletServiceBridge.shared.fetchHistoryJSON(
                chainId: SpectraChainID.polkadot, address: address
            ) else { return ([:], true) }
            return (rustHistoryStatusMap(json: json), false)
        }
    }

    /// Build a txid → TransactionStatus map from a Rust history JSON response.
    /// All entries from Rust are treated as confirmed (Rust only surfaces confirmed txs for these chains).
    private func rustHistoryStatusMap(json: String) -> [String: TransactionStatus] {
        var statusByHash: [String: TransactionStatus] = [:]
        for entry in decodeRustHistoryJSON(json: json) {
            if let txid = (entry["txid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !txid.isEmpty {
                statusByHash[txid] = .confirmed
            }
        }
        return statusByHash
    }

}
