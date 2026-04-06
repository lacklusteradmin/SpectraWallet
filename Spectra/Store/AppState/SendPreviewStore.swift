import Foundation

extension WalletStore {
    var lastSentTransaction: TransactionRecord? {
        get { sendState.lastSentTransaction }
        set { sendState.lastSentTransaction = newValue }
    }

    var lastPendingTransactionRefreshAt: Date? {
        get { sendState.lastPendingTransactionRefreshAt }
        set { sendState.lastPendingTransactionRefreshAt = newValue }
    }

    var ethereumSendPreview: EthereumSendPreview? {
        get { sendState.ethereumSendPreview }
        set { sendState.ethereumSendPreview = newValue }
    }

    var bitcoinSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinSendPreview }
        set { sendState.bitcoinSendPreview = newValue }
    }

    var bitcoinCashSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinCashSendPreview }
        set { sendState.bitcoinCashSendPreview = newValue }
    }

    var bitcoinSVSendPreview: BitcoinSendPreview? {
        get { sendState.bitcoinSVSendPreview }
        set { sendState.bitcoinSVSendPreview = newValue }
    }

    var litecoinSendPreview: BitcoinSendPreview? {
        get { sendState.litecoinSendPreview }
        set { sendState.litecoinSendPreview = newValue }
    }

    var dogecoinSendPreview: DogecoinWalletEngine.DogecoinSendPreview? {
        get { sendState.dogecoinSendPreview }
        set { sendState.dogecoinSendPreview = newValue }
    }

    var tronSendPreview: TronSendPreview? {
        get { sendState.tronSendPreview }
        set { sendState.tronSendPreview = newValue }
    }

    var solanaSendPreview: SolanaSendPreview? {
        get { sendState.solanaSendPreview }
        set { sendState.solanaSendPreview = newValue }
    }

    var xrpSendPreview: XRPSendPreview? {
        get { sendState.xrpSendPreview }
        set { sendState.xrpSendPreview = newValue }
    }

    var stellarSendPreview: StellarSendPreview? {
        get { sendState.stellarSendPreview }
        set { sendState.stellarSendPreview = newValue }
    }

    var moneroSendPreview: MoneroSendPreview? {
        get { sendState.moneroSendPreview }
        set { sendState.moneroSendPreview = newValue }
    }

    var cardanoSendPreview: CardanoSendPreview? {
        get { sendState.cardanoSendPreview }
        set { sendState.cardanoSendPreview = newValue }
    }

    var suiSendPreview: SuiSendPreview? {
        get { sendState.suiSendPreview }
        set { sendState.suiSendPreview = newValue }
    }

    var aptosSendPreview: AptosSendPreview? {
        get { sendState.aptosSendPreview }
        set { sendState.aptosSendPreview = newValue }
    }

    var tonSendPreview: TONSendPreview? {
        get { sendState.tonSendPreview }
        set { sendState.tonSendPreview = newValue }
    }

    var icpSendPreview: ICPSendPreview? {
        get { sendState.icpSendPreview }
        set { sendState.icpSendPreview = newValue }
    }

    var nearSendPreview: NearSendPreview? {
        get { sendState.nearSendPreview }
        set { sendState.nearSendPreview = newValue }
    }

    var polkadotSendPreview: PolkadotSendPreview? {
        get { sendState.polkadotSendPreview }
        set { sendState.polkadotSendPreview = newValue }
    }
}
