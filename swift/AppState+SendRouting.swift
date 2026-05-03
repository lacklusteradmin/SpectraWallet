import Foundation
extension AppState {
    private enum SendPreviewKind: String {
        case bitcoin
        case bitcoinCash
        case bitcoinSV
        case litecoin
        case ethereum
        case dogecoin
        case tron
        case solana
        case xrp
        case stellar
        case monero
        case cardano
        case sui
        case aptos
        case ton
        case icp
        case near
        case polkadot
    }
    func refreshSendPreview() async {
        guard let selectedSendCoin = selectedSendCoin else {
            resetAllSendPreviews()
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
            isCheckingSendDestinationBalance = false
            return
        }
        await refreshSendDestinationRiskWarning(for: selectedSendCoin)
        let activePreview = plannedPreviewKind(for: selectedSendCoin)
        resetInactiveSendPreviews(except: activePreview)
        switch activePreview {
        case .bitcoin: await refreshBitcoinSendPreview()
        case .bitcoinCash: await refreshBitcoinCashSendPreview()
        case .bitcoinSV: await refreshBitcoinSVSendPreview()
        case .litecoin: await refreshLitecoinSendPreview()
        case .ethereum: await refreshEthereumSendPreview()
        case .dogecoin: await refreshDogecoinSendPreview()
        case .tron: await refreshTronSendPreview()
        case .solana: await refreshSolanaSendPreview()
        case .xrp: await refreshXrpSendPreview()
        case .stellar: await refreshStellarSendPreview()
        case .monero: await refreshMoneroSendPreview()
        case .cardano: await refreshCardanoSendPreview()
        case .sui: await refreshSuiSendPreview()
        case .aptos: await refreshAptosSendPreview()
        case .ton: await refreshTonSendPreview()
        case .icp: await refreshIcpSendPreview()
        case .near: await refreshNearSendPreview()
        case .polkadot: await refreshPolkadotSendPreview()
        case nil: break
        }
    }
    private func plannedPreviewKind(for coin: Coin) -> SendPreviewKind? {
        let request = SendPreviewRoutingRequest(
            asset: rustSendAssetRoutingInput(for: coin)
        )
        let plan = corePlanSendPreviewRouting(request: request)
        guard let activePreviewKind = plan.activePreviewKind else { return nil }
        return SendPreviewKind(rawValue: activePreviewKind)
    }
    private func rustSendAssetRoutingInput(for coin: Coin) -> SendAssetRoutingInput {
        SendAssetRoutingInput(
            chainName: coin.chainName, symbol: coin.symbol, isEvmChain: isEVMChain(coin.chainName),
            supportsSolanaSendCoin: isSupportedSolanaSendCoin(coin), supportsNearTokenSend: isSupportedNearTokenSend(coin)
        )
    }
    private func resetAllSendPreviews() {
        sendPreviewStore.bitcoinSendPreview = nil
        sendPreviewStore.bitcoinCashSendPreview = nil
        sendPreviewStore.bitcoinSVSendPreview = nil
        sendPreviewStore.litecoinSendPreview = nil
        sendPreviewStore.ethereumSendPreview = nil
        sendPreviewStore.dogecoinSendPreview = nil
        sendPreviewStore.tronSendPreview = nil
        sendPreviewStore.solanaSendPreview = nil
        sendPreviewStore.xrpSendPreview = nil
        sendPreviewStore.stellarSendPreview = nil
        sendPreviewStore.moneroSendPreview = nil
        sendPreviewStore.cardanoSendPreview = nil
        sendPreviewStore.suiSendPreview = nil
        sendPreviewStore.aptosSendPreview = nil
        sendPreviewStore.tonSendPreview = nil
        sendPreviewStore.icpSendPreview = nil
        sendPreviewStore.nearSendPreview = nil
        sendPreviewStore.polkadotSendPreview = nil
        preparingChains = []
    }
    private func resetInactiveSendPreviews(except activePreview: SendPreviewKind?) {
        if activePreview != .bitcoin { sendPreviewStore.bitcoinSendPreview = nil }
        if activePreview != .bitcoinCash { sendPreviewStore.bitcoinCashSendPreview = nil }
        if activePreview != .bitcoinSV { sendPreviewStore.bitcoinSVSendPreview = nil }
        if activePreview != .litecoin { sendPreviewStore.litecoinSendPreview = nil }
        if activePreview != .ethereum {
            sendPreviewStore.ethereumSendPreview = nil
            preparingChains.remove("Ethereum")
        }
        if activePreview != .dogecoin {
            sendPreviewStore.dogecoinSendPreview = nil
            preparingChains.remove("Dogecoin")
        }
        if activePreview != .tron {
            sendPreviewStore.tronSendPreview = nil
            preparingChains.remove("Tron")
        }
        if activePreview != .solana {
            sendPreviewStore.solanaSendPreview = nil
            preparingChains.remove("Solana")
        }
        if activePreview != .xrp {
            sendPreviewStore.xrpSendPreview = nil
            preparingChains.remove("XRP Ledger")
        }
        if activePreview != .stellar {
            sendPreviewStore.stellarSendPreview = nil
            preparingChains.remove("Stellar")
        }
        if activePreview != .monero {
            sendPreviewStore.moneroSendPreview = nil
            preparingChains.remove("Monero")
        }
        if activePreview != .cardano {
            sendPreviewStore.cardanoSendPreview = nil
            preparingChains.remove("Cardano")
        }
        if activePreview != .sui {
            sendPreviewStore.suiSendPreview = nil
            preparingChains.remove("Sui")
        }
        if activePreview != .aptos {
            sendPreviewStore.aptosSendPreview = nil
            preparingChains.remove("Aptos")
        }
        if activePreview != .ton {
            sendPreviewStore.tonSendPreview = nil
            preparingChains.remove("TON")
        }
        if activePreview != .icp {
            sendPreviewStore.icpSendPreview = nil
            preparingChains.remove("Internet Computer")
        }
        if activePreview != .near {
            sendPreviewStore.nearSendPreview = nil
            preparingChains.remove("NEAR")
        }
        if activePreview != .polkadot {
            sendPreviewStore.polkadotSendPreview = nil
            preparingChains.remove("Polkadot")
        }
    }
}
