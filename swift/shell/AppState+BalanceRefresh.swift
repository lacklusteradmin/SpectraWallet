import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Pending balance updates accumulated during a refresh cycle. Flushed as a
    /// single `wallets` mutation so SwiftUI only re-renders once per batch.
    private struct PendingBalanceUpdate {
        let chainId: UInt32
        let walletId: String
        let json: String
    }
    private static var pendingBalanceUpdates: [PendingBalanceUpdate] = []
    private static var balanceFlushTask: Task<Void, Never>?

    /// Called by the Rust balance refresh engine when a new native balance arrives.
    /// Accumulates updates and flushes them as a single wallets mutation after a
    /// short debounce window, so 50+ balance callbacks produce one SwiftUI re-render.
    func applyRustBalance(chainId: UInt32, walletId: String, json: String) {
        Self.pendingBalanceUpdates.append(PendingBalanceUpdate(chainId: chainId, walletId: walletId, json: json))
        Self.balanceFlushTask?.cancel()
        Self.balanceFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let batch = Self.pendingBalanceUpdates
            Self.pendingBalanceUpdates = []
            guard !batch.isEmpty else { return }
            await self.flushBalanceBatch(batch)
        }
    }

    private func flushBalanceBatch(_ batch: [PendingBalanceUpdate]) async {
        var walletsCopy = wallets
        let walletIndexById = Dictionary(uniqueKeysWithValues: walletsCopy.enumerated().map { ($1.id, $0) })
        var anyChanged = false
        for update in batch {
            guard let idx = walletIndexById[update.walletId],
                  let summary = try? await WalletServiceBridge.shared.updateNativeBalanceTyped(
                      walletId: update.walletId, chainId: update.chainId, balanceJson: update.json)
            else { continue }
            if let updated = holdingsAppliedFromSummary(summary, to: walletsCopy[idx]) {
                walletsCopy[idx] = updated
                anyChanged = true
            }
        }
        if anyChanged { wallets = walletsCopy }
    }

    /// Decode the `holdings` array from a WalletSummary JSON blob and apply
    /// their amounts to `wallet`.  Visual properties (color, mark, priceUsd)
    /// are preserved from the existing Coin if found; new holdings get defaults.
    /// Returns `nil` if the JSON could not be parsed.
    private func holdingsAppliedFromSummary(_ summary: WalletSummary, to wallet: ImportedWallet) -> ImportedWallet? {
        guard !summary.holdings.isEmpty else { return nil }
        var merged = wallet.holdings
        for h in summary.holdings {
            let key = holdingLookupKeyFromParts(symbol: h.symbol, chainName: h.chainName, contract: h.contractAddress)
            if let idx = merged.firstIndex(where: { holdingLookupKey($0) == key }) {
                let old = merged[idx]
                merged[idx] = CoreCoin(
                    id: old.id,
                    name: old.name, symbol: old.symbol, marketDataId: old.marketDataId,
                    coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                    tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                    amount: h.amount, priceUsd: old.priceUsd, mark: old.mark)
            } else if h.amount > 0 {
                let mark = String(h.symbol.prefix(2)).uppercased()
                var newCoin = CoreCoin(
                    id: UUID().uuidString,
                    name: h.name, symbol: h.symbol, marketDataId: h.marketDataId,
                    coinGeckoId: h.coinGeckoId, chainName: h.chainName,
                    tokenStandard: h.tokenStandard, contractAddress: h.contractAddress,
                    amount: h.amount, priceUsd: 0, mark: mark)
                newCoin.color = .blue
                merged.append(newCoin)
            }
        }
        return walletByReplacingHoldings(wallet, with: merged)
    }

    private func holdingLookupKey(_ coin: Coin) -> String {
        holdingLookupKeyFromParts(symbol: coin.symbol, chainName: coin.chainName, contract: coin.contractAddress)
    }
    private func holdingLookupKeyFromParts(symbol: String, chainName: String, contract: String?) -> String {
        if let contract { return "\(chainName):\(contract.lowercased())" }
        return "\(chainName):\(symbol)"
    }

    func updateRefreshEngineEntries() {
        let entries: [RefreshEntry] = wallets.compactMap { wallet in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain),
                  let address = resolvedRefreshAddress(for: wallet) else { return nil }
            return RefreshEntry(chainId: chainId, walletId: wallet.id, address: address)
        }
        Task { try? await WalletServiceBridge.shared.setRefreshEntriesTyped(entries) }
    }

    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver(noPointer: .init())
        observer.store = self
        Task {
            try? await WalletServiceBridge.shared.setBalanceObserver(observer)
            try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: 30)
        }
        updateRefreshEngineEntries()
    }

    private func resolvedRefreshAddress(for wallet: ImportedWallet) -> String? {
        switch wallet.selectedChain {
        case "Bitcoin":
            if let xpub = wallet.bitcoinXpub, !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return xpub }
            return resolvedBitcoinAddress(for: wallet)
        case "Ethereum", "Arbitrum", "Optimism", "Avalanche", "BNB Chain", "Hyperliquid", "Ethereum Classic", "Base":
            return resolvedEVMAddress(for: wallet, chainName: wallet.selectedChain)
        case "Solana":    return resolvedSolanaAddress(for: wallet)
        case "Tron":      return resolvedTronAddress(for: wallet)
        case "Sui":       return resolvedSuiAddress(for: wallet)
        case "Aptos":     return resolvedAptosAddress(for: wallet)
        case "TON":       return resolvedTONAddress(for: wallet)
        case "ICP":       return resolvedICPAddress(for: wallet)
        case "NEAR":      return resolvedNearAddress(for: wallet)
        case "XRP Ledger":   return resolvedXRPAddress(for: wallet)
        case "Stellar":      return resolvedStellarAddress(for: wallet)
        case "Cardano":      return resolvedCardanoAddress(for: wallet)
        case "Polkadot":     return resolvedPolkadotAddress(for: wallet)
        case "Monero":       return resolvedMoneroAddress(for: wallet)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV":   return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin":     return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin":     return resolvedDogecoinAddress(for: wallet)
        default:             return nil
        }
    }

    // EVM helpers kept because they're still called from SendFlow / DiagnosticsEndpoints.
    func configuredEthereumRPCEndpointURL() -> URL? {
        guard ethereumRPCEndpointValidationError == nil else { return nil }
        let trimmed = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [TokenBalanceResult]) {
        let ethereumContext = evmChainContext(for: "Ethereum") ?? .ethereum
        let balanceJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.ethereum, address: address)
        let nativeBalance = RustBalanceDecoder.evmNativeBalance(from: balanceJSON) ?? 0
        let tokenBalances = ethereumContext.isEthereumMainnet
            ? ((try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                chainId: SpectraChainID.ethereum, address: address,
                tokens: enabledEthereumTrackedTokens().map { ($0.contractAddress, $0.symbol, $0.decimals) }
            )) ?? [])
            : []
        return (nativeBalance, tokenBalances)
    }
    // Removed (were dead code — only called from hydrateImportedWalletBalances which was never called):
    //   initialNativeHolding, mergeNativeHolding, applyEVMTokenHoldings,
    //   applySolanaPortfolio, applyTronPortfolio, mergeRustHoldingAmounts,
    //   normalizedEtherscanAPIKey, fetchEVMNativePortfolio.
}
