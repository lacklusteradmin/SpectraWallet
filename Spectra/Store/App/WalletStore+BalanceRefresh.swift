import Foundation
import SwiftUI

@MainActor
extension WalletStore {
    // MARK: - Per-Chain Balance Refresh
    func refreshBitcoinBalances() async {
        await WalletFetchLayer.refreshBitcoinBalances(using: self)
    }

    func refreshBitcoinCashBalances() async {
        await WalletFetchLayer.refreshBitcoinCashBalances(using: self)
    }

    func refreshBitcoinSVBalances() async {
        await WalletFetchLayer.refreshBitcoinSVBalances(using: self)
    }

    // LTC balance refresh pipeline with deterministic derivation and API fallback behavior.
    func refreshLitecoinBalances() async {
        await WalletFetchLayer.refreshLitecoinBalances(using: self)
    }

    // DOGE balance refresh with discovery/keypool awareness and ledger-derived fallback support.
    func refreshDogecoinBalances() async {
        await WalletFetchLayer.refreshDogecoinBalances(using: self)
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

    // ETH native + tracked token refresh, then holdings merge into wallet snapshot.
    func refreshEthereumBalances() async {
        await WalletFetchLayer.refreshEthereumBalances(using: self)
    }

    func refreshBNBBalances() async {
        await WalletFetchLayer.refreshBNBBalances(using: self)
    }

    func refreshArbitrumBalances() async {
        await WalletFetchLayer.refreshArbitrumBalances(using: self)
    }

    func refreshOptimismBalances() async {
        await WalletFetchLayer.refreshOptimismBalances(using: self)
    }

    func refreshETCBalances() async {
        await WalletFetchLayer.refreshETCBalances(using: self)
    }

    func refreshAvalancheBalances() async {
        await WalletFetchLayer.refreshAvalancheBalances(using: self)
    }

    func refreshHyperliquidBalances() async {
        await WalletFetchLayer.refreshHyperliquidBalances(using: self)
    }

    func refreshTronBalances() async {
        await WalletFetchLayer.refreshTronBalances(using: self)
    }

    // SOL native + SPL token refresh path.
    // This is where tracked contract/mint preferences directly affect asset visibility.
    func refreshSolanaBalances() async {
        await WalletFetchLayer.refreshSolanaBalances(using: self)
    }

    // ADA balance refresh for selected wallets/chains.
    func refreshCardanoBalances() async {
        await WalletFetchLayer.refreshCardanoBalances(using: self)
    }

    // XRP balance refresh for selected wallets/chains.
    func refreshXRPBalances() async {
        await WalletFetchLayer.refreshXRPBalances(using: self)
    }

    func refreshStellarBalances() async {
        await WalletFetchLayer.refreshStellarBalances(using: self)
    }

    // XMR balance refresh for selected wallets/chains.
    func refreshMoneroBalances() async {
        await WalletFetchLayer.refreshMoneroBalances(using: self)
    }

    // SUI balance refresh for selected wallets/chains.
    func refreshSuiBalances() async {
        await WalletFetchLayer.refreshSuiBalances(using: self)
    }

    func refreshAptosBalances() async {
        await WalletFetchLayer.refreshAptosBalances(using: self)
    }

    func refreshTONBalances() async {
        await WalletFetchLayer.refreshTONBalances(using: self)
    }

    func refreshICPBalances() async {
        await WalletFetchLayer.refreshICPBalances(using: self)
    }

    func refreshNearBalances() async {
        await WalletFetchLayer.refreshNearBalances(using: self)
    }

    func refreshPolkadotBalances() async {
        await WalletFetchLayer.refreshPolkadotBalances(using: self)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let contract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
            uniqueKeysWithValues: tokenBalances.map { (EthereumWalletEngine.normalizeAddress($0.contractAddress), $0) }
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
            let normalizedContract = EthereumWalletEngine.normalizeAddress(token.contractAddress)
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
        // If a custom endpoint is invalid, fall back to built-in provider rotation instead of hard-failing ETH.
        let useFallbackEndpoint = ethereumRPCEndpointValidationError != nil
            && !ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rpcEndpoint = useFallbackEndpoint ? nil : configuredEVMRPCEndpointURL(for: "Ethereum")
        let accountSnapshot = try await EthereumWalletEngine.fetchAccountSnapshot(
            for: address,
            rpcEndpoint: rpcEndpoint,
            chainID: ethereumContext.expectedChainID,
            chain: ethereumContext
        )
        let tokenBalances = ethereumContext.isEthereumMainnet
            ? ((try? await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledEthereumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: ethereumContext
            )) ?? [])
            : []
        return (
            EthereumWalletEngine.nativeBalanceETH(from: accountSnapshot),
            tokenBalances
        )
    }

    func fetchEVMNativePortfolio(
        for address: String,
        chainName: String
    ) async throws -> (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot]) {
        guard let chain = evmChainContext(for: chainName) else {
            throw EthereumWalletEngineError.invalidResponse
        }
        let useFallbackEndpoint = chain.isEthereumFamily
            && ethereumRPCEndpointValidationError != nil
            && !ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rpcEndpoint = useFallbackEndpoint ? nil : configuredEVMRPCEndpointURL(for: chainName)
        let accountSnapshot = try await EthereumWalletEngine.fetchAccountSnapshot(
            for: address,
            rpcEndpoint: rpcEndpoint,
            chainID: chain.expectedChainID,
            chain: chain
        )
        let tokenBalances: [EthereumTokenBalanceSnapshot]
        if chain.isEthereumMainnet {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledEthereumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .arbitrum {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledArbitrumTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .optimism {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledOptimismTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .bnb {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledBNBTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .avalanche {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledAvalancheTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else if chain == .hyperliquid {
            tokenBalances = try await EthereumWalletEngine.fetchTokenBalances(
                for: address,
                trackedTokens: enabledHyperliquidTrackedTokens(),
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        } else {
            tokenBalances = try await EthereumWalletEngine.fetchSupportedTokenBalances(
                for: address,
                rpcEndpoint: rpcEndpoint,
                chain: chain
            )
        }
        return (
            EthereumWalletEngine.nativeBalanceETH(from: accountSnapshot),
            tokenBalances
        )
    }

}
