import Foundation

struct WalletTransferAvailabilityCoordinator {
    static func availableSendCoins(
        in wallet: ImportedWallet,
        hasSigningMaterial: Bool,
        supportsEVMToken: (Coin) -> Bool,
        supportsSolanaSendCoin: (Coin) -> Bool
    ) -> [Coin] {
        wallet.holdings.filter { coin in
            guard ChainBackendRegistry.supportsSend(for: coin.chainName) else {
                return false
            }
            if ChainBackendRegistry.liveChainNames.contains(coin.chainName),
               !hasSigningMaterial {
                return false
            }
            if coin.chainName == "Ethereum" {
                return coin.symbol == "ETH" || supportsEVMToken(coin)
            }
            if coin.chainName == "Ethereum Classic" {
                return coin.symbol == "ETC"
            }
            if coin.chainName == "BNB Chain" {
                return coin.symbol == "BNB" || supportsEVMToken(coin)
            }
            if coin.chainName == "Avalanche" {
                return coin.symbol == "AVAX" || supportsEVMToken(coin)
            }
            if coin.chainName == "Hyperliquid" {
                return coin.symbol == "HYPE"
            }
            if coin.chainName == "Solana" {
                return supportsSolanaSendCoin(coin)
            }
            return true
        }
    }

    static func availableReceiveCoins(in wallet: ImportedWallet) -> [Coin] {
        wallet.holdings.filter { coin in
            ChainBackendRegistry.supportsReceiveAddress(for: coin.chainName)
        }
    }

    static func availableReceiveChains(for coins: [Coin]) -> [String] {
        var seenChains: Set<String> = []
        var orderedChains: [String] = []
        for coin in coins where seenChains.insert(coin.chainName).inserted {
            orderedChains.append(coin.chainName)
        }
        return orderedChains
    }
}
