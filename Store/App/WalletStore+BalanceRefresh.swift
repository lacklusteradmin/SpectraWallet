import Foundation
import SwiftUI

@MainActor
extension WalletStore {
    // MARK: - Per-Chain Balance Refresh
    // Balance fetching is now Rust-driven. These stubs trigger an immediate Rust
    // refresh cycle so on-demand callers (send flow, pull-to-refresh) get fresh data.

    func refreshBitcoinBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshBitcoinCashBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshBitcoinSVBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshLitecoinBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshDogecoinBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func ledgerDerivedDogecoinBalance(for walletID: UUID) -> Double? {
        ledgerDerivedNativeBalanceIfAvailable(for: walletID, chainName: "Dogecoin", symbol: "DOGE")
    }

    func ledgerDerivedNativeBalanceIfAvailable(
        for walletID: UUID,
        chainName: String,
        symbol: String
    ) -> Double? {
        _ = walletID
        _ = chainName
        _ = symbol
        return nil
    }

    func resolvedTronNativeBalance(
        fetchedNativeBalance: Double,
        tokenBalances: [TronTokenBalanceSnapshot],
        wallet: ImportedWallet
    ) -> Double {
        _ = tokenBalances
        _ = wallet
        return fetchedNativeBalance
    }

    func refreshEthereumBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshBNBBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshArbitrumBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshOptimismBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshETCBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshAvalancheBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshHyperliquidBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshTronBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshSolanaBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshCardanoBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshXRPBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshStellarBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshMoneroBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshSuiBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshAptosBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshTONBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshICPBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshNearBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }

    func refreshPolkadotBalances() async {
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
    }


    func applyBitcoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BTC",
            chainName: "Bitcoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin",
                symbol: "BTC",
                marketDataID: "1",
                coinGeckoID: "bitcoin",
                chainName: "Bitcoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 64000,
                mark: "B",
                color: .orange
            )
        )
    }

    func applyBitcoinCashBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BCH",
            chainName: "Bitcoin Cash",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin Cash",
                symbol: "BCH",
                marketDataID: "1831",
                coinGeckoID: "bitcoin-cash",
                chainName: "Bitcoin Cash",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 420,
                mark: "BC",
                color: .orange
            )
        )
    }

    func applyBitcoinSVBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BSV",
            chainName: "Bitcoin SV",
            amount: balance,
            defaultCoin: Coin(
                name: "Bitcoin SV",
                symbol: "BSV",
                marketDataID: "3602",
                coinGeckoID: "bitcoin-cash-sv",
                chainName: "Bitcoin SV",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 80,
                mark: "BS",
                color: .orange
            )
        )
    }

    func applyLitecoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "LTC",
            chainName: "Litecoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Litecoin",
                symbol: "LTC",
                marketDataID: "2",
                coinGeckoID: "litecoin",
                chainName: "Litecoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 90,
                mark: "L",
                color: .gray
            )
        )
    }

    func applyDogecoinBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "DOGE",
            chainName: "Dogecoin",
            amount: balance,
            defaultCoin: Coin(
                name: "Dogecoin",
                symbol: "DOGE",
                marketDataID: "74",
                coinGeckoID: "dogecoin",
                chainName: "Dogecoin",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.15,
                mark: "D",
                color: .brown
            )
        )
    }

    func applyEthereumNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Ethereum",
            amount: balance,
            defaultCoin: Coin(
                name: "Ethereum",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Ethereum",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "E",
                color: .blue
            )
        )
    }

    func applyETCNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETC",
            chainName: "Ethereum Classic",
            amount: balance,
            defaultCoin: Coin(
                name: "Ethereum Classic",
                symbol: "ETC",
                marketDataID: "1321",
                coinGeckoID: "ethereum-classic",
                chainName: "Ethereum Classic",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 30,
                mark: "EC",
                color: .green
            )
        )
    }

    func applyBNBNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "BNB",
            chainName: "BNB Chain",
            amount: balance,
            defaultCoin: Coin(
                name: "BNB",
                symbol: "BNB",
                marketDataID: "1839",
                coinGeckoID: "binancecoin",
                chainName: "BNB Chain",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 450,
                mark: "BN",
                color: .yellow
            )
        )
    }

    func applyArbitrumNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Arbitrum",
            amount: balance,
            defaultCoin: Coin(
                name: "Ether",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Arbitrum",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "AR",
                color: .cyan
            )
        )
    }

    func applyOptimismNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ETH",
            chainName: "Optimism",
            amount: balance,
            defaultCoin: Coin(
                name: "Ether",
                symbol: "ETH",
                marketDataID: "1027",
                coinGeckoID: "ethereum",
                chainName: "Optimism",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 3500,
                mark: "OP",
                color: .red
            )
        )
    }

    func applyAvalancheNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "AVAX",
            chainName: "Avalanche",
            amount: balance,
            defaultCoin: Coin(
                name: "Avalanche",
                symbol: "AVAX",
                marketDataID: "5805",
                coinGeckoID: "avalanche-2",
                chainName: "Avalanche",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 35,
                mark: "AV",
                color: .red
            )
        )
    }

    func applyHyperliquidNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "HYPE",
            chainName: "Hyperliquid",
            amount: balance,
            defaultCoin: Coin(
                name: "Hyperliquid",
                symbol: "HYPE",
                marketDataID: "0",
                coinGeckoID: "hyperliquid",
                chainName: "Hyperliquid",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0,
                mark: "HY",
                color: .mint
            )
        )
    }

    func applyETCBalances(
        nativeBalance: Double,
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = holdings.filter { $0.chainName != "Ethereum Classic" || $0.symbol == "ETC" }
        if let etcIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETC" && $0.chainName == "Ethereum Classic" }) {
            let existing = updatedHoldings[etcIndex]
            updatedHoldings[etcIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyETCNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }
        return updatedHoldings
    }

    func applyAvalancheBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledAvalancheTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Avalanche" || $0.symbol == "AVAX" }
        if let avaxIndex = updatedHoldings.firstIndex(where: { $0.symbol == "AVAX" && $0.chainName == "Avalanche" }) {
            let existing = updatedHoldings[avaxIndex]
            updatedHoldings[avaxIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyAvalancheNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = normalizeEVMAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Avalanche",
                    tokenStandard: "ARC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyArbitrumBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledArbitrumTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Arbitrum" || $0.symbol == "ETH" }
        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Arbitrum" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyArbitrumNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = normalizeEVMAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Arbitrum",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" || token.symbol == "USD1" || token.symbol == "USDE" || token.symbol == "USDD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyOptimismBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledOptimismTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Optimism" || $0.symbol == "ETH" }
        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Optimism" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyOptimismNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = normalizeEVMAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Optimism",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" || token.symbol == "USD1" || token.symbol == "USDE" || token.symbol == "USDD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyHyperliquidBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledHyperliquidTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )
        var updatedHoldings = holdings.filter { $0.chainName != "Hyperliquid" || $0.symbol == "HYPE" }
        if let hypeIndex = updatedHoldings.firstIndex(where: { $0.symbol == "HYPE" && $0.chainName == "Hyperliquid" }) {
            let existing = updatedHoldings[hypeIndex]
            updatedHoldings[hypeIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings = applyHyperliquidNativeBalanceOnly(nativeBalance, to: updatedHoldings)
        }

        for token in trackedTokens {
            let normalizedContract = normalizeEVMAddress(token.contractAddress)
            let amount = tokenBalanceLookup[normalizedContract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Hyperliquid",
                    tokenStandard: TokenTrackingChain.hyperliquid.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "USDE" || token.symbol == "USDB" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }
        return updatedHoldings
    }

    func applyTronNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "TRX",
            chainName: "Tron",
            amount: balance,
            defaultCoin: Coin(
                name: "Tron",
                symbol: "TRX",
                marketDataID: "1958",
                coinGeckoID: "tron",
                chainName: "Tron",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.12,
                mark: "T",
                color: .teal
            )
        )
    }

    func applySolanaNativeBalanceOnly(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "SOL",
            chainName: "Solana",
            amount: balance,
            defaultCoin: Coin(
                name: "Solana",
                symbol: "SOL",
                marketDataID: "5426",
                coinGeckoID: "solana",
                chainName: "Solana",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 150,
                mark: "S",
                color: .purple
            )
        )
    }

    func applyEthereumBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledEthereumTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Ethereum" && holding.symbol != "ETH")
        }

        if let ethIndex = updatedHoldings.firstIndex(where: { $0.symbol == "ETH" && $0.chainName == "Ethereum" }) {
            let existing = updatedHoldings[ethIndex]
            updatedHoldings[ethIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Ethereum",
                    symbol: "ETH",
                    marketDataID: "1027",
                    coinGeckoID: "ethereum",
                    chainName: "Ethereum",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 3500,
                    mark: "E",
                    color: .blue
                )
            )
        }

        for token in trackedTokens {
            let contract = normalizeEVMAddress(token.contractAddress)
            let amount = tokenBalanceLookup[contract].map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Ethereum",
                    tokenStandard: "ERC-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyBNBBalances(
        nativeBalance: Double,
        tokenBalances: [EthereumTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledBNBTrackedTokens()
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeEVMAddress($0.contractAddress), $0) }
        )

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "BNB Chain" && holding.symbol != "BNB")
        }

        if !updatedHoldings.contains(where: { $0.symbol == "BNB" && $0.chainName == "BNB Chain" }) {
            updatedHoldings.append(
                Coin(
                    name: "BNB",
                    symbol: "BNB",
                    marketDataID: "1839",
                    coinGeckoID: "binancecoin",
                    chainName: "BNB Chain",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 450,
                    mark: "BN",
                    color: .yellow
                )
            )
        }

        if let bnbIndex = updatedHoldings.firstIndex(where: { $0.symbol == "BNB" && $0.chainName == "BNB Chain" }) {
            let existing = updatedHoldings[bnbIndex]
            updatedHoldings[bnbIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        }

        for token in trackedTokens {
            let normalizedContract = normalizeEVMAddress(token.contractAddress)
            let tokenBalance = tokenBalanceLookup[normalizedContract]
            let amount = tokenBalance.map { NSDecimalNumber(decimal: $0.balance).doubleValue } ?? 0
            guard amount > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "BNB Chain",
                    tokenStandard: "BEP-20",
                    contractAddress: token.contractAddress,
                    amount: amount,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "DAI" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyTronBalances(
        nativeBalance: Double,
        tokenBalances: [TronTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledTokenPreferences(for: .tron)
        let tokenBalanceLookup: [String: Double] = Dictionary(uniqueKeysWithValues: tokenBalances.compactMap { snapshot in
            guard let contract = snapshot.contractAddress else { return nil }
            return (contract.lowercased(), snapshot.balance)
        })

        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Tron" && holding.symbol != "TRX")
        }

        if let trxIndex = updatedHoldings.firstIndex(where: { $0.symbol == "TRX" && $0.chainName == "Tron" }) {
            let existing = updatedHoldings[trxIndex]
            updatedHoldings[trxIndex] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: nativeBalance,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Tron",
                    symbol: "TRX",
                    marketDataID: "1958",
                    coinGeckoID: "tron",
                    chainName: "Tron",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 0.12,
                    mark: "T",
                    color: .teal
                )
            )
        }

        for token in trackedTokens {
            let balance = tokenBalanceLookup[token.contractAddress.lowercased()] ?? 0
            guard balance > 0 else { continue }
            let stableSymbols = Set(["USDT", "USDC", "USDD", "TUSD", "FDUSD"])
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Tron",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: balance,
                    priceUSD: stableSymbols.contains(token.symbol) ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyCardanoBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ADA",
            chainName: "Cardano",
            amount: balance,
            defaultCoin: Coin(
                name: "Cardano",
                symbol: "ADA",
                marketDataID: "2010",
                coinGeckoID: "cardano",
                chainName: "Cardano",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.55,
                mark: "A",
                color: .indigo
            )
        )
    }

    func applyXRPBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XRP",
            chainName: "XRP Ledger",
            amount: balance,
            defaultCoin: Coin(
                name: "XRP",
                symbol: "XRP",
                marketDataID: "52",
                coinGeckoID: "ripple",
                chainName: "XRP Ledger",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.6,
                mark: "X",
                color: .cyan
            )
        )
    }

    func applyStellarBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XLM",
            chainName: "Stellar",
            amount: balance,
            defaultCoin: Coin(
                name: "Stellar Lumens",
                symbol: "XLM",
                marketDataID: "171",
                coinGeckoID: "stellar",
                chainName: "Stellar",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 0.12,
                mark: "X",
                color: .blue
            )
        )
    }

    func applyMoneroBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "XMR",
            chainName: "Monero",
            amount: balance,
            defaultCoin: Coin(
                name: "Monero",
                symbol: "XMR",
                marketDataID: "328",
                coinGeckoID: "monero",
                chainName: "Monero",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 120,
                mark: "M",
                color: .indigo
            )
        )
    }

    func applySuiBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "SUI",
            chainName: "Sui",
            amount: balance,
            defaultCoin: Coin(
                name: "Sui",
                symbol: "SUI",
                marketDataID: "20947",
                coinGeckoID: "sui",
                chainName: "Sui",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 1.0,
                mark: "S",
                color: .mint
            )
        )
    }

    func applySuiBalances(
        nativeBalance: Double,
        tokenBalances: [SuiTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let trackedTokens = enabledTokenPreferences(for: .sui)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeSuiTokenIdentifier($0.coinType), $0) }
        )
        let packageBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (suiPackageIdentifier(from: $0.coinType), $0) }
        )

        var updatedHoldings = applySuiBalance(nativeBalance, to: holdings).filter { holding in
            !(holding.chainName == "Sui" && holding.symbol != "SUI")
        }

        for token in trackedTokens {
            let normalizedCoinType = normalizeSuiTokenIdentifier(token.contractAddress)
            guard let snapshot = tokenBalanceLookup[normalizedCoinType]
                ?? packageBalanceLookup[suiPackageIdentifier(from: token.contractAddress)],
                  snapshot.balance > 0 else {
                continue
            }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Sui",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func suiPackageIdentifier(from value: String?) -> String {
        let normalized = normalizeSuiTokenIdentifier(value ?? "")
        guard let package = normalized.split(separator: "::", omittingEmptySubsequences: false).first else {
            return normalized
        }
        return String(package)
    }

    func applyAptosBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "APT",
            chainName: "Aptos",
            amount: balance,
            defaultCoin: Coin(
                name: "Aptos",
                symbol: "APT",
                marketDataID: "21794",
                coinGeckoID: "aptos",
                chainName: "Aptos",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 8,
                mark: "AP",
                color: .cyan
            )
        )
    }

    func applyAptosBalances(
        nativeBalance: Double,
        tokenBalances: [AptosTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = applyAptosBalance(nativeBalance, to: holdings)
        let trackedTokens = enabledTokenPreferences(for: .aptos)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (normalizeAptosTokenIdentifier($0.coinType), $0) }
        )
        let tokenBalanceLookupByPackage = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (aptosPackageIdentifier(from: $0.coinType), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "Aptos" && holding.symbol != "APT")
        }

        for token in trackedTokens {
            let normalizedIdentifier = normalizeAptosTokenIdentifier(token.contractAddress)
            guard let snapshot = tokenBalanceLookup[normalizedIdentifier]
                ?? tokenBalanceLookupByPackage[aptosPackageIdentifier(from: normalizedIdentifier)],
                  snapshot.balance > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Aptos",
                    tokenStandard: token.tokenStandard,
                    contractAddress: snapshot.coinType,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" || token.symbol == "TUSD" || token.symbol == "USDE"
                        ? 1.0
                        : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyTONBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "TON",
            chainName: "TON",
            amount: balance,
            defaultCoin: Coin(
                name: "Toncoin",
                symbol: "TON",
                marketDataID: "11419",
                coinGeckoID: "the-open-network",
                chainName: "TON",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 7,
                mark: "TN",
                color: .blue
            )
        )
    }

    func applyTONBalances(
        nativeBalance: Double,
        tokenBalances: [TONJettonBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = applyTONBalance(nativeBalance, to: holdings)
        let trackedTokens = enabledTokenPreferences(for: .ton)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { (TONBalanceService.normalizeJettonMasterAddress($0.masterAddress), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "TON" && holding.symbol != "TON")
        }

        for token in trackedTokens {
            guard let snapshot = tokenBalanceLookup[TONBalanceService.normalizeJettonMasterAddress(token.contractAddress)],
                  snapshot.balance > 0 else {
                continue
            }

            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "TON",
                    tokenStandard: token.tokenStandard,
                    contractAddress: snapshot.masterAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDT" || token.symbol == "USDC" || token.symbol == "FDUSD" || token.symbol == "TUSD" || token.symbol == "USD1" || token.symbol == "USDE"
                        ? 1.0
                        : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyICPBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "ICP",
            chainName: "Internet Computer",
            amount: balance,
            defaultCoin: Coin(
                name: "Internet Computer",
                symbol: "ICP",
                marketDataID: "2416",
                coinGeckoID: "internet-computer",
                chainName: "Internet Computer",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 12,
                mark: "IC",
                color: .indigo
            )
        )
    }

    func applyNearBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "NEAR",
            chainName: "NEAR",
            amount: balance,
            defaultCoin: Coin(
                name: "NEAR Protocol",
                symbol: "NEAR",
                marketDataID: "6535",
                coinGeckoID: "near",
                chainName: "NEAR",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 6,
                mark: "N",
                color: .indigo
            )
        )
    }

    func applyNearBalances(
        nativeBalance: Double?,
        tokenBalances: [NearTokenBalanceSnapshot]?,
        to holdings: [Coin]
    ) -> [Coin] {
        var updatedHoldings = holdings
        if let nativeBalance {
            updatedHoldings = applyNearBalance(nativeBalance, to: updatedHoldings)
        }

        guard let tokenBalances else { return updatedHoldings }

        let trackedTokens = enabledTokenPreferences(for: .near)
        let tokenBalanceLookup = Dictionary(
            uniqueKeysWithValues: tokenBalances.map { ($0.contractAddress.lowercased(), $0) }
        )

        updatedHoldings = updatedHoldings.filter { holding in
            !(holding.chainName == "NEAR" && holding.symbol != "NEAR")
        }

        for token in trackedTokens {
            guard let snapshot = tokenBalanceLookup[token.contractAddress.lowercased()],
                  snapshot.balance > 0 else { continue }
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "NEAR",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.contractAddress,
                    amount: snapshot.balance,
                    priceUSD: token.symbol == "USDC" || token.symbol == "USDT" || token.symbol == "FDUSD" || token.symbol == "TUSD" ? 1.0 : 0,
                    mark: Coin.displayMark(for: token.symbol),
                    color: Coin.displayColor(for: token.symbol)
                )
            )
        }

        return updatedHoldings
    }

    func applyPolkadotBalance(_ balance: Double, to holdings: [Coin]) -> [Coin] {
        upsertNativeHolding(
            in: holdings,
            symbol: "DOT",
            chainName: "Polkadot",
            amount: balance,
            defaultCoin: Coin(
                name: "Polkadot",
                symbol: "DOT",
                marketDataID: "6636",
                coinGeckoID: "polkadot",
                chainName: "Polkadot",
                tokenStandard: "Native",
                contractAddress: nil,
                amount: balance,
                priceUSD: 7,
                mark: "P",
                color: .pink
            )
        )
    }

    func upsertNativeHolding(
        in holdings: [Coin],
        symbol: String,
        chainName: String,
        amount: Double,
        defaultCoin: Coin
    ) -> [Coin] {
        if let index = holdings.firstIndex(where: { $0.symbol == symbol && $0.chainName == chainName }) {
            var updatedHoldings = holdings
            let existing = holdings[index]
            updatedHoldings[index] = Coin(
                name: existing.name,
                symbol: existing.symbol,
                marketDataID: existing.marketDataID,
                coinGeckoID: existing.coinGeckoID,
                chainName: existing.chainName,
                tokenStandard: existing.tokenStandard,
                contractAddress: existing.contractAddress,
                amount: amount,
                priceUSD: existing.priceUSD,
                mark: existing.mark,
                color: existing.color
            )
            return updatedHoldings
        }

        var updatedHoldings = holdings
        updatedHoldings.append(defaultCoin)
        return updatedHoldings
    }

    // Merges SOL + SPL token snapshots into canonical coin holdings for one wallet.
    func applySolanaPortfolio(
        nativeBalance: Double,
        tokenBalances: [SolanaSPLTokenBalanceSnapshot],
        to holdings: [Coin]
    ) -> [Coin] {
        let existingSolanaTokensByMint = Dictionary(
            uniqueKeysWithValues: holdings.compactMap { holding -> (String, Coin)? in
                guard holding.chainName == "Solana",
                      holding.symbol != "SOL",
                      let mint = holding.contractAddress else {
                    return nil
                }
                return (mint, holding)
            }
        )
        var updatedHoldings = holdings.filter { holding in
            !(holding.chainName == "Solana" && holding.symbol != "SOL")
        }

        if let solanaIndex = updatedHoldings.firstIndex(where: { $0.symbol == "SOL" && $0.chainName == "Solana" }) {
            let solana = updatedHoldings[solanaIndex]
            updatedHoldings[solanaIndex] = Coin(
                name: solana.name,
                symbol: solana.symbol,
                marketDataID: solana.marketDataID,
                coinGeckoID: solana.coinGeckoID,
                chainName: solana.chainName,
                tokenStandard: solana.tokenStandard,
                contractAddress: solana.contractAddress,
                amount: nativeBalance,
                priceUSD: solana.priceUSD,
                mark: solana.mark,
                color: solana.color
            )
        } else {
            updatedHoldings.append(
                Coin(
                    name: "Solana",
                    symbol: "SOL",
                    marketDataID: "5426",
                    coinGeckoID: "solana",
                    chainName: "Solana",
                    tokenStandard: "Native",
                    contractAddress: nil,
                    amount: nativeBalance,
                    priceUSD: 150,
                    mark: "S",
                    color: .purple
                )
            )
        }

        for token in tokenBalances where token.balance > 0 {
            let existing = existingSolanaTokensByMint[token.mintAddress]
            updatedHoldings.append(
                Coin(
                    name: token.name,
                    symbol: token.symbol,
                    marketDataID: token.marketDataID,
                    coinGeckoID: token.coinGeckoID,
                    chainName: "Solana",
                    tokenStandard: token.tokenStandard,
                    contractAddress: token.mintAddress,
                    amount: token.balance,
                    priceUSD: existing?.priceUSD ?? defaultPriceUSDForSolanaToken(symbol: token.symbol),
                    mark: String(token.symbol.prefix(1)).uppercased(),
                    color: .mint
                )
            )
        }

        return updatedHoldings
    }

    func defaultPriceUSDForSolanaToken(symbol: String) -> Double {
        switch symbol.uppercased() {
        case "USDT", "USDC", "FDUSD":
            return 1.0
        default:
            return 0
        }
    }

    func configuredEthereumRPCEndpointURL() -> URL? {
        guard ethereumRPCEndpointValidationError == nil else { return nil }
        let trimmedEndpoint = ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { return nil }
        return URL(string: trimmedEndpoint)
    }

    func normalizedEtherscanAPIKey() -> String? {
        let trimmed = etherscanAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func fetchEthereumPortfolio(for address: String) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        let ethereumContext = evmChainContext(for: "Ethereum") ?? .ethereum
        let balanceJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.ethereum, address: address)
        let nativeBalance = RustBalanceDecoder.evmNativeBalance(from: balanceJSON) ?? 0
        let tokenBalances = ethereumContext.isEthereumMainnet
            ? ((try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                chainId: SpectraChainID.ethereum,
                address: address,
                tokens: enabledEthereumTrackedTokens().map { ($0.contractAddress, $0.symbol, $0.decimals) }
            )) ?? [])
            : []
        return (nativeBalance, tokenBalances)
    }

    func fetchEVMNativePortfolio(
        for address: String,
        chainName: String
    ) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        guard let chain = evmChainContext(for: chainName),
              let chainId = SpectraChainID.id(for: chainName) else {
            throw EthereumWalletEngineError.invalidResponse
        }
        let balanceJSON = try await WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address)
        let nativeBalance = RustBalanceDecoder.evmNativeBalance(from: balanceJSON) ?? 0
        let tokenBalances: [EthereumTokenBalanceSnapshot]
        let trackedForChain: [EthereumSupportedToken]
        if chain.isEthereumMainnet {
            trackedForChain = enabledEthereumTrackedTokens()
        } else if chain == .arbitrum {
            trackedForChain = enabledArbitrumTrackedTokens()
        } else if chain == .optimism {
            trackedForChain = enabledOptimismTrackedTokens()
        } else if chain == .bnb {
            trackedForChain = enabledBNBTrackedTokens()
        } else if chain == .avalanche {
            trackedForChain = enabledAvalancheTrackedTokens()
        } else if chain == .hyperliquid {
            trackedForChain = enabledHyperliquidTrackedTokens()
        } else {
            trackedForChain = []
        }
        if !trackedForChain.isEmpty {
            tokenBalances = (try? await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                chainId: chainId,
                address: address,
                tokens: trackedForChain.map { ($0.contractAddress, $0.symbol, $0.decimals) }
            )) ?? []
        } else {
            tokenBalances = []
        }
        return (nativeBalance, tokenBalances)
    }

    // MARK: - Phase 3 — Rust-driven refresh cycle

    /// Apply a balance JSON payload pushed by `BalanceRefreshEngine`.
    /// Decodes chain-specific fields and updates the wallet's native holding.
    func applyRustBalance(chainId: UInt32, walletId: String, json: String) {
        guard let walletIdx = wallets.firstIndex(where: { $0.id.uuidString == walletId }) else { return }
        let wallet = wallets[walletIdx]

        let updatedHoldings: [Coin]?
        switch chainId {
        case SpectraChainID.bitcoin:
            // confirmed_sats (UInt64 or Number) / 1e8
            if let sats = RustBalanceDecoder.uint64Field("confirmed_sats", from: json) {
                updatedHoldings = applyBitcoinBalance(Double(sats) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.ethereum, SpectraChainID.base:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyEthereumNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.solana:
            if let lamports = RustBalanceDecoder.uint64Field("lamports", from: json) {
                updatedHoldings = applySolanaNativeBalanceOnly(Double(lamports) / 1e9, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.dogecoin:
            if let koin = RustBalanceDecoder.uint64Field("balance_koin", from: json) {
                updatedHoldings = applyDogecoinBalance(Double(koin) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.xrp:
            if let drops = RustBalanceDecoder.uint64Field("drops", from: json) {
                updatedHoldings = applyXRPBalance(Double(drops) / 1e6, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.litecoin:
            if let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                updatedHoldings = applyLitecoinBalance(Double(sat) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.bitcoinCash:
            if let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                updatedHoldings = applyBitcoinCashBalance(Double(sat) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.tron:
            if let sun = RustBalanceDecoder.uint64Field("sun", from: json) {
                updatedHoldings = applyTronNativeBalanceOnly(Double(sun) / 1e6, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.stellar:
            if let stroops = RustBalanceDecoder.int64Field("stroops", from: json) {
                updatedHoldings = applyStellarBalance(Double(abs(stroops)) / 1e7, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.cardano:
            if let lovelace = RustBalanceDecoder.uint64Field("lovelace", from: json) {
                updatedHoldings = applyCardanoBalance(Double(lovelace) / 1e6, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.polkadot:
            if let planck = RustBalanceDecoder.uint128StringField("planck", from: json) {
                updatedHoldings = applyPolkadotBalance(planck / 10_000_000_000, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.arbitrum:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyArbitrumNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.optimism:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyOptimismNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.avalanche:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyAvalancheNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.sui:
            if let mist = RustBalanceDecoder.uint64Field("mist", from: json) {
                updatedHoldings = applySuiBalance(Double(mist) / 1e9, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.aptos:
            if let octas = RustBalanceDecoder.uint64Field("octas", from: json) {
                updatedHoldings = applyAptosBalance(Double(octas) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.ton:
            if let nanotons = RustBalanceDecoder.uint64Field("nanotons", from: json) {
                updatedHoldings = applyTONBalance(Double(nanotons) / 1e9, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.near:
            if let near = RustBalanceDecoder.yoctoNearToDouble(from: json) {
                updatedHoldings = applyNearBalance(near, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.icp:
            if let e8s = RustBalanceDecoder.uint64Field("e8s", from: json) {
                updatedHoldings = applyICPBalance(Double(e8s) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.monero:
            if let piconeros = RustBalanceDecoder.uint64Field("piconeros", from: json) {
                updatedHoldings = applyMoneroBalance(Double(piconeros) / 1e12, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.ethereumClassic:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyETCNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.bitcoinSv:
            if let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                updatedHoldings = applyBitcoinSVBalance(Double(sat) / 1e8, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.bsc:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyBNBNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        case SpectraChainID.hyperliquid:
            if let bal = RustBalanceDecoder.evmNativeBalance(from: json) {
                updatedHoldings = applyHyperliquidNativeBalanceOnly(bal, to: wallet.holdings)
            } else { updatedHoldings = nil }
        default:
            updatedHoldings = nil
        }

        if let updatedHoldings {
            wallets[walletIdx] = walletByReplacingHoldings(wallet, with: updatedHoldings)
        }
    }

    // MARK: - Refresh engine wiring

    /// Build the refresh entry list from the current wallet snapshot and push to Rust.
    func updateRefreshEngineEntries() {
        let entries: [[String: Any]] = wallets.compactMap { wallet -> [String: Any]? in
            guard let chainId = SpectraChainID.id(for: wallet.selectedChain),
                  let address = resolvedRefreshAddress(for: wallet) else { return nil }
            return ["chain_id": chainId, "wallet_id": wallet.id.uuidString, "address": address]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8) else { return }
        Task { try? await WalletServiceBridge.shared.setRefreshEntries(json) }
    }

    /// Start the Rust-owned balance refresh cycle. Call once at app launch.
    func setupRustRefreshEngine() {
        let observer = WalletBalanceObserver()
        observer.store = self
        Task {
            try? await WalletServiceBridge.shared.setBalanceObserver(observer)
            try? await WalletServiceBridge.shared.startBalanceRefresh(intervalSecs: 30)
        }
        updateRefreshEngineEntries()
    }

    /// Resolve the canonical fetch key for a wallet's selected chain.
    /// For Bitcoin HD wallets returns the xpub; for all others the chain address.
    private func resolvedRefreshAddress(for wallet: ImportedWallet) -> String? {
        switch wallet.selectedChain {
        case "Bitcoin":
            if let xpub = wallet.bitcoinXPub,
               !xpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return xpub
            }
            return resolvedBitcoinAddress(for: wallet)
        case "Ethereum", "Arbitrum", "Optimism", "Avalanche",
             "BNB Chain", "Hyperliquid", "Ethereum Classic", "Base":
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

}
