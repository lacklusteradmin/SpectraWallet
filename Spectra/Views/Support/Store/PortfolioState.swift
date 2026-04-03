import Foundation
import Combine

final class WalletPortfolioState: ObservableObject {
    @Published var wallets: [ImportedWallet] = [] {
        didSet {
            walletsRevision &+= 1
        }
    }
    @Published private(set) var walletsRevision: UInt64 = 0

    var walletByID: [UUID: ImportedWallet] = [:]
    var walletByIDString: [String: ImportedWallet] = [:]
    var includedPortfolioWallets: [ImportedWallet] = []
    var includedPortfolioHoldings: [Coin] = []
    var includedPortfolioHoldingsBySymbol: [String: [Coin]] = [:]
    var uniqueWalletPriceRequestCoins: [Coin] = []
    var portfolio: [Coin] = []
    var availableSendCoinsByWalletID: [String: [Coin]] = [:]
    var availableReceiveCoinsByWalletID: [String: [Coin]] = [:]
    var availableReceiveChainsByWalletID: [String: [String]] = [:]
    var sendEnabledWallets: [ImportedWallet] = []
    var receiveEnabledWallets: [ImportedWallet] = []
    var refreshableChainNames: Set<String> = []
    var signingMaterialWalletIDs: Set<UUID> = []
    var privateKeyBackedWalletIDs: Set<UUID> = []
}
