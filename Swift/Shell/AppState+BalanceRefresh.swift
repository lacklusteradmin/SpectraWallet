import Foundation
import SwiftUI
@MainActor
extension AppState {
    func refreshBalances() async { try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh() }

    /// Called by the Rust balance refresh engine when a new native balance arrives.
    /// Pushes the update to Rust wallet_state, then syncs the returned holdings
    /// back to the Swift wallet so the UI reflects the Rust-canonical amounts.
    func applyRustBalance(chainId: UInt32, walletId: String, json: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let walletIdx = wallets.firstIndex(where: { $0.id == walletId }),
                  let walletJson = try? await WalletServiceBridge.shared.updateNativeBalance(
                      walletId: walletId, chainId: chainId, balanceJson: json)
            else { return }
            if let updated = holdingsApplied(from: walletJson, to: wallets[walletIdx]) {
                wallets[walletIdx] = updated
            }}}

    /// Decode the `holdings` array from a WalletSummary JSON blob and apply
    /// their amounts to `wallet`.  Visual properties (color, mark, priceUsd)
    /// are preserved from the existing Coin if found; new holdings get defaults.
    /// Returns `nil` if the JSON could not be parsed.
    private func holdingsApplied(from walletJson: String, to wallet: ImportedWallet) -> ImportedWallet? {
        guard let data = walletJson.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let holdingsArr = obj["holdings"] as? [[String: Any]]
        else { return nil }
        // Build lookup: (chainName, symbol, contractAddress?) → existing Coin
        var lookup: [String: Coin] = [:]
        for coin in wallet.holdings {
            lookup[holdingLookupKey(coin)] = coin
        }
        var merged = wallet.holdings
        for h in holdingsArr {
            guard let symbol   = h["symbol"]    as? String,
                  let chainName = h["chainName"] as? String,
                  let amount    = h["amount"]    as? Double
            else { continue }
            let contract  = h["contractAddress"] as? String
            let key = holdingLookupKeyFromParts(symbol: symbol, chainName: chainName, contract: contract)
            if let idx = merged.firstIndex(where: { holdingLookupKey($0) == key }) {
                // Update amount in-place, preserve all other fields.
                let old = merged[idx]
                merged[idx] = CoreCoin(
                    id: old.id,
                    name: old.name, symbol: old.symbol, marketDataId: old.marketDataId,
                    coinGeckoId: old.coinGeckoId, chainName: old.chainName,
                    tokenStandard: old.tokenStandard, contractAddress: old.contractAddress,
                    amount: amount, priceUsd: old.priceUsd, mark: old.mark)
            } else if amount > 0 {
                // New holding from Rust not yet in Swift — add with defaults.
                let name         = h["name"]          as? String ?? symbol
                let tokenStd     = h["tokenStandard"] as? String ?? "Native"
                let marketDataId = h["marketDataId"]  as? String ?? ""
                let coinGeckoId  = h["coinGeckoId"]   as? String ?? ""
                let mark         = String(symbol.prefix(2)).uppercased()
                var newCoin = CoreCoin(
                    id: UUID().uuidString,
                    name: name, symbol: symbol, marketDataId: marketDataId,
                    coinGeckoId: coinGeckoId, chainName: chainName,
                    tokenStandard: tokenStd, contractAddress: contract,
                    amount: amount, priceUsd: 0, mark: mark)
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
        let entries: [[String: Any]] = wallets.compactMap { wallet -> [String: Any]? in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain),
                  let address = resolvedRefreshAddress(for: wallet) else { return nil }
            return ["chain_id": chainId, "wallet_id": wallet.id, "address": address]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8) else { return }
        Task { try? await WalletServiceBridge.shared.setRefreshEntries(json) }
    }

    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
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
    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
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
