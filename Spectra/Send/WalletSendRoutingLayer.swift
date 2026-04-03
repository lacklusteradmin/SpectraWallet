import Foundation

extension WalletSendLayer {
    private enum SendPreviewKind {
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

    static func refreshSendPreview(using store: WalletStore) async {
        guard let selectedSendCoin = store.selectedSendCoin else {
            resetAllSendPreviews(on: store)
            store.sendDestinationRiskWarning = nil
            store.sendDestinationInfoMessage = nil
            store.isCheckingSendDestinationBalance = false
            return
        }

        await store.refreshSendDestinationRiskWarning(for: selectedSendCoin)

        let activePreview = previewKind(for: selectedSendCoin, using: store)
        resetInactiveSendPreviews(except: activePreview, on: store)

        switch activePreview {
        case .bitcoin:
            await refreshBitcoinSendPreview(using: store)
        case .bitcoinCash:
            await refreshBitcoinCashSendPreview(using: store)
        case .bitcoinSV:
            await refreshBitcoinSVSendPreview(using: store)
        case .litecoin:
            await refreshLitecoinSendPreview(using: store)
        case .ethereum:
            await refreshEthereumSendPreview(using: store)
        case .dogecoin:
            await refreshDogecoinSendPreview(using: store)
        case .tron:
            await refreshTronSendPreview(using: store)
        case .solana:
            await refreshSolanaSendPreview(using: store)
        case .xrp:
            await refreshXRPSendPreview(using: store)
        case .stellar:
            await refreshStellarSendPreview(using: store)
        case .monero:
            await refreshMoneroSendPreview(using: store)
        case .cardano:
            await refreshCardanoSendPreview(using: store)
        case .sui:
            await refreshSuiSendPreview(using: store)
        case .aptos:
            await refreshAptosSendPreview(using: store)
        case .ton:
            await refreshTONSendPreview(using: store)
        case .icp:
            await refreshICPSendPreview(using: store)
        case .near:
            await refreshNearSendPreview(using: store)
        case .polkadot:
            await refreshPolkadotSendPreview(using: store)
        case nil:
            break
        }
    }

    private static func previewKind(for coin: Coin, using store: WalletStore) -> SendPreviewKind? {
        switch (coin.chainName, coin.symbol) {
        case ("Bitcoin", "BTC"):
            return .bitcoin
        case ("Bitcoin Cash", "BCH"):
            return .bitcoinCash
        case ("Bitcoin SV", "BSV"):
            return .bitcoinSV
        case ("Litecoin", "LTC"):
            return .litecoin
        case ("Dogecoin", "DOGE"):
            return .dogecoin
        case ("Tron", "TRX"), ("Tron", "USDT"):
            return .tron
        case ("XRP Ledger", "XRP"):
            return .xrp
        case ("Stellar", "XLM"):
            return .stellar
        case ("Monero", "XMR"):
            return .monero
        case ("Cardano", "ADA"):
            return .cardano
        case ("Sui", "SUI"):
            return .sui
        case ("Aptos", "APT"):
            return .aptos
        case ("TON", "TON"):
            return .ton
        case ("Internet Computer", "ICP"):
            return .icp
        case ("NEAR", "NEAR"):
            return .near
        case ("Polkadot", "DOT"):
            return .polkadot
        default:
            if store.isEVMChain(coin.chainName) {
                return .ethereum
            }
            if store.isSupportedSolanaSendCoin(coin) {
                return .solana
            }
            return nil
        }
    }

    private static func resetAllSendPreviews(on store: WalletStore) {
        store.bitcoinSendPreview = nil
        store.bitcoinCashSendPreview = nil
        store.bitcoinSVSendPreview = nil
        store.litecoinSendPreview = nil
        store.ethereumSendPreview = nil
        store.dogecoinSendPreview = nil
        store.tronSendPreview = nil
        store.solanaSendPreview = nil
        store.xrpSendPreview = nil
        store.stellarSendPreview = nil
        store.moneroSendPreview = nil
        store.cardanoSendPreview = nil
        store.suiSendPreview = nil
        store.aptosSendPreview = nil
        store.tonSendPreview = nil
        store.icpSendPreview = nil
        store.nearSendPreview = nil
        store.polkadotSendPreview = nil
        store.isPreparingEthereumSend = false
        store.isPreparingDogecoinSend = false
        store.isPreparingTronSend = false
        store.isPreparingSolanaSend = false
        store.isPreparingXRPSend = false
        store.isPreparingStellarSend = false
        store.isPreparingMoneroSend = false
        store.isPreparingCardanoSend = false
        store.isPreparingSuiSend = false
        store.isPreparingAptosSend = false
        store.isPreparingTONSend = false
        store.isPreparingICPSend = false
        store.isPreparingNearSend = false
        store.isPreparingPolkadotSend = false
    }

    private static func resetInactiveSendPreviews(except activePreview: SendPreviewKind?, on store: WalletStore) {
        if activePreview != .bitcoin { store.bitcoinSendPreview = nil }
        if activePreview != .bitcoinCash { store.bitcoinCashSendPreview = nil }
        if activePreview != .bitcoinSV { store.bitcoinSVSendPreview = nil }
        if activePreview != .litecoin { store.litecoinSendPreview = nil }
        if activePreview != .ethereum {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
        }
        if activePreview != .dogecoin {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
        }
        if activePreview != .tron {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
        }
        if activePreview != .solana {
            store.solanaSendPreview = nil
            store.isPreparingSolanaSend = false
        }
        if activePreview != .xrp {
            store.xrpSendPreview = nil
            store.isPreparingXRPSend = false
        }
        if activePreview != .stellar {
            store.stellarSendPreview = nil
            store.isPreparingStellarSend = false
        }
        if activePreview != .monero {
            store.moneroSendPreview = nil
            store.isPreparingMoneroSend = false
        }
        if activePreview != .cardano {
            store.cardanoSendPreview = nil
            store.isPreparingCardanoSend = false
        }
        if activePreview != .sui {
            store.suiSendPreview = nil
            store.isPreparingSuiSend = false
        }
        if activePreview != .aptos {
            store.aptosSendPreview = nil
            store.isPreparingAptosSend = false
        }
        if activePreview != .ton {
            store.tonSendPreview = nil
            store.isPreparingTONSend = false
        }
        if activePreview != .icp {
            store.icpSendPreview = nil
            store.isPreparingICPSend = false
        }
        if activePreview != .near {
            store.nearSendPreview = nil
            store.isPreparingNearSend = false
        }
        if activePreview != .polkadot {
            store.polkadotSendPreview = nil
            store.isPreparingPolkadotSend = false
        }
    }
}
