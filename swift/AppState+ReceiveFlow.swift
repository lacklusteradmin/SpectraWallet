import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// Open with no wallet selected unless there is only one to choose.
    func beginReceive() {
        let wallets = receiveEnabledWallets
        guard !wallets.isEmpty else { return }
        receiveFlow.walletId = wallets.count == 1 ? wallets[0].id : ""
        syncReceiveAssetSelection()
        receiveFlow.isPresented = true
    }
    func syncReceiveAssetSelection() {
        receiveFlow.holdingKey = selectedReceiveCoin(for: receiveFlow.walletId)?.holdingKey ?? ""
        receiveFlow.clearAddress()
    }
    func cancelReceive() {
        receiveFlow.isPresented = false
        receiveFlow.clearAddress()
    }
    func refreshReceiveAddress() async {
        let requestId = UUID()
        receiveFlow.requestId = requestId
        receiveFlow.resolvedAddress = ""
        receiveFlow.error = nil
        receiveFlow.isResolving = false
        guard let wallet = wallet(for: receiveFlow.walletId),
            let coin = selectedReceiveCoin(for: receiveFlow.walletId),
            let chain = coin.chain else { return }
        receiveFlow.isResolving = true
        defer {
            if receiveFlow.requestId == requestId { receiveFlow.isResolving = false }
        }
        do {
            let address = try await self.bridge.ready().receiveAddress(
                walletId: wallet.id, chainId: chain.id, reserve: true)
            guard !Task.isCancelled, receiveFlow.requestId == requestId,
                receiveFlow.walletId == wallet.id, receiveFlow.holdingKey == coin.holdingKey else { return }
            receiveFlow.resolvedAddress = address ?? ""
            if address == nil { receiveFlow.error = AppLocalization.string("No receive address is available for this wallet and network.") }
        } catch {
            guard !Task.isCancelled, receiveFlow.requestId == requestId else { return }
            receiveFlow.error = error.localizedDescription
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
