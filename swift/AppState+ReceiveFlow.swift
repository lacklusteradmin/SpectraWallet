import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// Opens the flow with nothing chosen, unless there is only one wallet to
    /// choose. It used to seed `receiveWalletID` with whichever wallet sorted
    /// first, which the wallet step then never showed as selected — so
    /// "Continue" carried a wallet the user had never picked and could not see.
    func beginReceive() {
        let wallets = receiveEnabledWallets
        guard !wallets.isEmpty else { return }
        receiveWalletID = wallets.count == 1 ? wallets[0].id : ""
        syncReceiveAssetSelection()
        isShowingReceiveSheet = true
    }
    func syncReceiveAssetSelection() {
        receiveHoldingKey = selectedReceiveCoin(for: receiveWalletID)?.holdingKey ?? ""
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestID = UUID()
        isResolvingReceiveAddress = false
    }
    func cancelReceive() {
        isShowingReceiveSheet = false
        receiveResolvedAddress = ""
        receiveAddressError = nil
        receiveAddressRequestID = UUID()
        isResolvingReceiveAddress = false
    }
    func refreshReceiveAddress() async {
        let requestID = UUID()
        receiveAddressRequestID = requestID
        receiveResolvedAddress = ""
        receiveAddressError = nil
        isResolvingReceiveAddress = false
        guard let wallet = wallet(for: receiveWalletID),
            let coin = selectedReceiveCoin(for: receiveWalletID),
            let chain = Chain(displayName: coin.chainName) else { return }
        isResolvingReceiveAddress = true
        defer {
            if receiveAddressRequestID == requestID { isResolvingReceiveAddress = false }
        }
        do {
            let address = try await WalletServiceBridge.shared.receiveAddress(
                walletID: wallet.id, chainId: chain.id, reserve: true)
            guard !Task.isCancelled, receiveAddressRequestID == requestID,
                receiveWalletID == wallet.id, receiveHoldingKey == coin.holdingKey else { return }
            receiveResolvedAddress = address ?? ""
            if address == nil { receiveAddressError = AppLocalization.string("No receive address is available for this wallet and network.") }
        } catch {
            guard !Task.isCancelled, receiveAddressRequestID == requestID else { return }
            receiveAddressError = error.localizedDescription
        }
    }
    func availableReceiveCoins(for walletID: String) -> [Coin] { cachedAvailableReceiveCoinsByWalletID[walletID] ?? [] }
    /// Which holding the receive screen presents itself as — the native one,
    /// or the first token if there is no native holding. Every holding on a
    /// chain is received at the same address, so this picks a symbol and an
    /// icon, not a destination; it was an FFI round trip carrying one boolean
    /// per holding.
    func selectedReceiveCoin(for walletID: String) -> Coin? {
        let receiveCoins = availableReceiveCoins(for: walletID)
        return receiveCoins.first { $0.contractAddress == nil } ?? receiveCoins.first
    }
    var receiveEnabledWallets: [WalletView] { cachedReceiveEnabledWallets }
    var canBeginReceive: Bool { !receiveEnabledWallets.isEmpty }
}
