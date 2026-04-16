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
        }}
    private func plannedPreviewKind(for coin: Coin) -> SendPreviewKind? {
        let request = WalletRustSendPreviewRoutingRequest(
            asset: rustSendAssetRoutingInput(for: coin)
        )
        let plan = WalletRustAppCoreBridge.planSendPreviewRouting(request)
        guard let activePreviewKind = plan.activePreviewKind else { return nil }
        return SendPreviewKind(rawValue: activePreviewKind)
    }
    private func rustSendAssetRoutingInput(for coin: Coin) -> WalletRustSendAssetRoutingInput {
        WalletRustSendAssetRoutingInput(
            chainName: coin.chainName, symbol: coin.symbol, isEVMChain: isEVMChain(coin.chainName), supportsSolanaSendCoin: isSupportedSolanaSendCoin(coin), supportsNearTokenSend: isSupportedNearTokenSend(coin)
        )
    }
    private func resetAllSendPreviews() {
        bitcoinSendPreview = nil
        bitcoinCashSendPreview = nil
        bitcoinSVSendPreview = nil
        litecoinSendPreview = nil
        ethereumSendPreview = nil
        dogecoinSendPreview = nil
        tronSendPreview = nil
        solanaSendPreview = nil
        xrpSendPreview = nil
        stellarSendPreview = nil
        moneroSendPreview = nil
        cardanoSendPreview = nil
        suiSendPreview = nil
        aptosSendPreview = nil
        tonSendPreview = nil
        icpSendPreview = nil
        nearSendPreview = nil
        polkadotSendPreview = nil
        isPreparingEthereumSend = false
        isPreparingDogecoinSend = false
        isPreparingTronSend = false
        isPreparingSolanaSend = false
        isPreparingXRPSend = false
        isPreparingStellarSend = false
        isPreparingMoneroSend = false
        isPreparingCardanoSend = false
        isPreparingSuiSend = false
        isPreparingAptosSend = false
        isPreparingTONSend = false
        isPreparingICPSend = false
        isPreparingNearSend = false
        isPreparingPolkadotSend = false
    }
    private func resetInactiveSendPreviews(except activePreview: SendPreviewKind?) {
        if activePreview != .bitcoin { bitcoinSendPreview = nil }
        if activePreview != .bitcoinCash { bitcoinCashSendPreview = nil }
        if activePreview != .bitcoinSV { bitcoinSVSendPreview = nil }
        if activePreview != .litecoin { litecoinSendPreview = nil }
        if activePreview != .ethereum {
            ethereumSendPreview = nil
            isPreparingEthereumSend = false
        }
        if activePreview != .dogecoin {
            dogecoinSendPreview = nil
            isPreparingDogecoinSend = false
        }
        if activePreview != .tron {
            tronSendPreview = nil
            isPreparingTronSend = false
        }
        if activePreview != .solana {
            solanaSendPreview = nil
            isPreparingSolanaSend = false
        }
        if activePreview != .xrp {
            xrpSendPreview = nil
            isPreparingXRPSend = false
        }
        if activePreview != .stellar {
            stellarSendPreview = nil
            isPreparingStellarSend = false
        }
        if activePreview != .monero {
            moneroSendPreview = nil
            isPreparingMoneroSend = false
        }
        if activePreview != .cardano {
            cardanoSendPreview = nil
            isPreparingCardanoSend = false
        }
        if activePreview != .sui {
            suiSendPreview = nil
            isPreparingSuiSend = false
        }
        if activePreview != .aptos {
            aptosSendPreview = nil
            isPreparingAptosSend = false
        }
        if activePreview != .ton {
            tonSendPreview = nil
            isPreparingTONSend = false
        }
        if activePreview != .icp {
            icpSendPreview = nil
            isPreparingICPSend = false
        }
        if activePreview != .near {
            nearSendPreview = nil
            isPreparingNearSend = false
        }
        if activePreview != .polkadot {
            polkadotSendPreview = nil
            isPreparingPolkadotSend = false
        }}
}
