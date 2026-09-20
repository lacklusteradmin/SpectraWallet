import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// Open with no wallet selected unless there is only one to choose.
    func beginReceive() {
        let wallets = receiveEnabledWallets
        guard !wallets.isEmpty else { return }
        receiveWalletId = wallets.count == 1 ? wallets[0].id : ""
        syncReceiveAssetSelection()
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletId)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestId = UUID()
        isResolvingReceiveAddress = false
    }
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestId = UUID()
        isResolvingReceiveAddress = false
    }
    func refreshReceiveAddress() async {
        let requestId = UUID()
        receiveAddressRequestId = requestId
        receiveResolvedAddress = ""
        receiveAddressError = nil
        isResolvingReceiveAddress = false
        guard let wallet = wallet(for: receiveWalletId),
            let coin = selectedReceiveCoin(for: receiveWalletId),
            let chain = Chain(displayName: coin.chainName) else { return }
        isResolvingReceiveAddress = true
        defer {
            if receiveAddressRequestId == requestId { isResolvingReceiveAddress = false }
        }
        do {
            let address = try await self.bridge.receiveAddress(
                walletId: wallet.id, chainId: chain.id, reserve: true)
            guard !Task.isCancelled, receiveAddressRequestId == requestId,
                receiveWalletId == wallet.id, receiveHoldingKey == coin.holdingKey else { return }
            receiveResolvedAddress = address ?? ""
            if address == nil { receiveAddressError = AppLocalization.string("No receive address is available for this wallet and network.") }
        } catch {
            guard !Task.isCancelled, receiveAddressRequestId == requestId else { return }
            receiveAddressError = error.localizedDescription
        }
    }
    func availableReceiveCoins(for walletId: String) -> [Coin] { cachedAvailableReceiveCoinsByWalletId[walletId] ?? [] }
    /// Choose the native holding, or the first token if none is native,
    /// for the receive screen's symbol and icon. This does not select an address.
    func selectedReceiveCoin(for walletId: String) -> Coin? {
        let receiveCoins = availableReceiveCoins(for: walletId)
        return receiveCoins.first { $0.contractAddress == nil } ?? receiveCoins.first
    }
    var receiveEnabledWallets: [WalletView] { cachedReceiveEnabledWallets }
    var canBeginReceive: Bool { !receiveEnabledWallets.isEmpty }
}
