import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Called by the Rust balance refresh engine after each successful balance
    /// fetch. Accumulates updates and flushes them as a single wallets mutation
    /// after a short debounce so a burst of 50+ callbacks produces one SwiftUI
    /// re-render. `pendingBalanceUpdates` + `balanceFlushTask` are instance
    /// properties on AppState (not static) so they're released when the
    /// AppState is; the prior `static var` held WalletSummary values and a
    /// scheduled Task process-wide, keeping memory around across AppState
    /// lifecycles (previews, lock/unlock reinit).
    func applyRustBalance(walletId: String, summary: WalletSummary) {
        pendingBalanceUpdates.append(PendingBalanceUpdate(walletId: walletId, summary: summary))
        balanceFlushTask?.cancel()
        balanceFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
            guard !Task.isCancelled, let self else { return }
            let batch = self.pendingBalanceUpdates
            self.pendingBalanceUpdates = []
            guard !batch.isEmpty else { return }
            Task { @MainActor in await self.flushBalanceBatch(batch) }
        }
    }

    private func flushBalanceBatch(_ batch: [PendingBalanceUpdate]) async {
        var walletsCopy = wallets
        let walletIndexById = Dictionary(uniqueKeysWithValues: walletsCopy.enumerated().map { ($1.id, $0) })
        var anyChanged = false
        var changedWallets: [ImportedWallet] = []
        for update in batch {
            guard let idx = walletIndexById[update.walletId] else {
                print("[BalanceRefresh] flushBatch: walletId \(update.walletId) not found in \(walletsCopy.map(\.id))")
                continue
            }
            if let updated = holdingsAppliedFromSummary(update.summary, to: walletsCopy[idx]) {
                walletsCopy[idx] = updated
                changedWallets.append(updated)
                anyChanged = true
                print("[BalanceRefresh] applied balance for wallet '\(walletsCopy[idx].name)' holdings=\(updated.holdings.map { "\($0.symbol):\($0.amount)" })")
            } else {
                print("[BalanceRefresh] holdingsAppliedFromSummary returned nil for wallet '\(walletsCopy[idx].name)' incoming=\(update.summary.holdings.map { "\($0.symbol):\($0.amount)" }) existing=\(walletsCopy[idx].holdings.map { "\($0.symbol):\($0.amount)" })")
            }
        }
        // Only the wallets whose holdings moved are written — a refresh cycle
        // mostly returns balances that have not changed.
        if anyChanged { await updateWalletsIfPresent(changedWallets) }
    }

    private func holdingsAppliedFromSummary(_ summary: WalletSummary, to wallet: ImportedWallet) -> ImportedWallet? {
        guard !summary.holdings.isEmpty else { return nil }
        let existingKeys = wallet.holdings.map { holdingKey($0.chainName, $0.symbol, $0.contractAddress) }
        var merged = wallet.holdings
        var anyChanged = false
        for incoming in summary.holdings {
            let key = holdingKey(incoming.chainName, incoming.symbol, incoming.contractAddress)
            if let idx = existingKeys.firstIndex(of: key) {
                guard merged[idx].amount != incoming.amount else { continue }
                let old = merged[idx]
                merged[idx] = AssetHolding(
                    name: old.name, symbol: old.symbol,
                    coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                    tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                    amount: incoming.amount, priceUsd: old.priceUsd)
                anyChanged = true
            } else if incoming.amount > 0 {
                merged.append(AssetHolding(
                    name: incoming.name, symbol: incoming.symbol,
                    coinGeckoId: incoming.coinGeckoId, chainName: incoming.chainName,
                    tokenStandard: incoming.tokenStandard, contractAddress: incoming.contractAddress,
                    amount: incoming.amount, priceUsd: 0))
                anyChanged = true
            }
        }
        return anyChanged ? walletByReplacingHoldings(wallet, with: merged) : nil
    }

    private func holdingKey(_ chainName: String, _ symbol: String, _ contract: String?) -> String {
        contract.map { "\(chainName):\($0.lowercased())" } ?? "\(chainName):\(symbol)"
    }

    /// Fetch ERC-20/EVM token balances for all EVM wallets and merge them into holdings.
    /// Called after each native refresh cycle so token balances stay current alongside native balances.
    /// Fetch and apply known-token balances for every chain that hosts
    /// tokens.
    ///
    /// This was two functions with the same body: one gated on `isEVMChain`
    /// and one on `chainName == "Solana"`, differing only in how they
    /// normalised a contract address. Eighteen chains have a
    /// `tokenHostingChain` — twelve EVM plus Solana, Tron, Sui, Aptos, TON
    /// and NEAR — so **Tron, Sui, Aptos, TON and NEAR known tokens had their
    /// balances fetched by nothing**. Core can fetch all of them; the refresh
    /// engine only fetches native balances, and Swift only asked for two
    /// families.
    ///
    /// The contract normaliser is core's, which is what makes the merge safe:
    /// EVM lowercases, and a TON jetton address is case-significant base64
    /// that `normalizeEVMAddress` would have corrupted.
    func refreshKnownTokenBalances() async {
        for wallet in wallets {
            guard let tokenChain = TokenHostingChain.forChainName(wallet.selectedChain),
                let chainId = Chain(displayName: wallet.selectedChain)?.id,
                let address = resolvedAddress(for: wallet, chainName: wallet.selectedChain)
            else { continue }
            let known = enabledTokenPreferences(for: tokenChain)
            guard !known.isEmpty else { continue }
            let descriptors = known.map {
                TokenDescriptor(
                    contract: $0.token.contract, symbol: $0.token.symbol,
                    decimals: UInt8(clamping: $0.token.decimals), name: $0.token.name)
            }
            guard let results = try? await WalletServiceBridge.shared.fetchTokenBalances(
                chainId: chainId, address: address, tokens: descriptors
            ) else { continue }
            guard let currentIdx = wallets.firstIndex(where: { $0.id == wallet.id }) else { continue }
            var holdings = wallets[currentIdx].holdings
            let existingKeys = holdings.map { holdingKey($0.chainName, $0.symbol, $0.contractAddress) }
            var holdingsChanged = false
            for result in results {
                let amount = Double(result.balanceDisplay) ?? 0
                let contract = normalizedKnownTokenIdentifier(
                    for: tokenChain, contractAddress: result.contractAddress)
                let key = holdingKey(wallet.selectedChain, result.symbol, contract.isEmpty ? nil : contract)
                if let existingIdx = existingKeys.firstIndex(of: key) {
                    guard holdings[existingIdx].amount != amount else { continue }
                    let old = holdings[existingIdx]
                    holdings[existingIdx] = AssetHolding(
                        name: old.name, symbol: old.symbol,
                        coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                        tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                        amount: amount, priceUsd: old.priceUsd)
                    holdingsChanged = true
                } else if amount > 0 {
                    guard let entry = known.first(where: {
                        normalizedKnownTokenIdentifier(for: tokenChain, contractAddress: $0.token.contract) == contract
                    }) else { continue }
                    holdings.append(AssetHolding(
                        name: entry.token.name, symbol: entry.token.symbol,
                        coinGeckoId: entry.token.coingeckoId, chainName: wallet.selectedChain,
                        tokenStandard: entry.token.tokenStandard, contractAddress: entry.token.contract,
                        amount: amount, priceUsd: 0))
                    holdingsChanged = true
                }
            }
            if holdingsChanged {
                await updateWalletsIfPresent([walletByReplacingHoldings(wallets[currentIdx], with: holdings)])
            }
        }
    }

    func updateRefreshEngineEntries() {
        let entries: [RefreshEntry] = wallets.compactMap { wallet in
            guard let chainId = Chain(displayName: wallet.selectedChain)?.id,
                let address = resolvedRefreshAddress(for: wallet)
            else {
                print("[BalanceRefresh] dropped wallet '\(wallet.name)' chain=\(wallet.selectedChain) chainId=\(Chain(displayName: wallet.selectedChain)?.id ?? "nil") addr=\(resolvedRefreshAddress(for: wallet) ?? "nil")")
                return nil
            }
            return RefreshEntry(chainId: chainId, walletId: wallet.id, address: address)
        }
        print("[BalanceRefresh] setEntries count=\(entries.count) walletCount=\(wallets.count)")
        Task(priority: .utility) {
            try? WalletServiceBridge.shared.setRefreshEntriesTyped(entries)
            if !entries.isEmpty {
                try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
            }
        }
    }

    /// Install the Rust balance-refresh observer and start the periodic
    /// refresh loop. Interval is driven by the user's
    /// `automaticRefreshFrequencyMinutes` preference (default 5 min) — NOT a
    /// hardcoded 30 s, which was firing at 10× the requested rate and
    /// keeping the phone warm with constant radio activity.
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
        observer.store = self
        Task { [weak self] in
            try? WalletServiceBridge.shared.setBalanceObserver(observer)
            await self?.restartBalanceRefreshForCurrentConfiguration()
        }
        updateRefreshEngineEntries()
    }
    /// Stop-then-start the refresh engine using the current effective
    /// interval. Called when the refresh-frequency preference changes or
    /// when the app transitions active/inactive — contexts where we want
    /// the interval value or the running state to actually change.
    func restartBalanceRefreshForCurrentConfiguration() async {
        try? WalletServiceBridge.shared.stopBalanceRefresh()
        guard appIsActive else { return }
        // No wallets = no entries to refresh. Keeping the tokio interval
        // alive just to wake every N minutes and no-op is pure idle heat,
        // so don't start it at all until the user imports a wallet.
        // `applyWalletCollectionSideEffects` calls
        // `startBalanceRefreshIfNeeded` when wallets change.
        guard !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

    /// Idempotent start path used after wallet mutations. Skips work when
    /// the app is inactive or there are no wallets, and relies on the
    /// Rust engine's own "already running" guard to make repeat calls
    /// cheap instead of stopping + restarting each time.
    func startBalanceRefreshIfNeeded() async {
        guard appIsActive, !wallets.isEmpty else { return }
        let minutes = max(1, preferences.automaticRefreshFrequencyMinutes)
        let intervalSecs = UInt64(minutes * 60)
        try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: intervalSecs)
    }

    private func resolvedRefreshAddress(for wallet: ImportedWallet) -> String? {
        if wallet.selectedChain == "Bitcoin",
           let xpub = wallet.bitcoinXpub,
           !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return xpub
        }
        return resolvedAddress(for: wallet, chainName: wallet.selectedChain)
    }

    // EVM helpers kept because they're still called from SendFlow / DiagnosticsEndpoints.
    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [TokenBalanceResult]) {
        // Was `?? .ethereum`, which resolved to a *fabricated* context with
        // chain id 0 when the registry lookup missed — a fallback that can only
        // fire when the registry has no Ethereum, and then reports mainnet as
        // not-mainnet. `false` says the same thing without inventing a chain.
        let isEthereumMainnet = EVMChainContext(chainName: "Ethereum")?.isEthereumMainnet ?? false
        let summary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: Chain.ethereum.id, address: address)
        let nativeBalance = Double(summary.amountDisplay) ?? 0
        let tokenBalances =
            isEthereumMainnet
            ? ((try? await WalletServiceBridge.shared.fetchTokenBalances(
                chainId: Chain.ethereum.id, address: address,
                tokens: enabledKnownTokens(for: .ethereum).map { TokenDescriptor(contract: $0.token.contract, symbol: $0.token.symbol, decimals: UInt8($0.token.decimals), name: nil) }
            )) ?? [])
            : []
        return (nativeBalance, tokenBalances)
    }
}
