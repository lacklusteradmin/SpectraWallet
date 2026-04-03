import Foundation

extension WalletStore {
    var isSendingBitcoin: Bool {
        get { sendState.isSendingBitcoin }
        set { sendState.isSendingBitcoin = newValue }
    }

    var isSendingBitcoinCash: Bool {
        get { sendState.isSendingBitcoinCash }
        set { sendState.isSendingBitcoinCash = newValue }
    }

    var isSendingBitcoinSV: Bool {
        get { sendState.isSendingBitcoinSV }
        set { sendState.isSendingBitcoinSV = newValue }
    }

    var isSendingLitecoin: Bool {
        get { sendState.isSendingLitecoin }
        set { sendState.isSendingLitecoin = newValue }
    }

    var isSendingDogecoin: Bool {
        get { sendState.isSendingDogecoin }
        set { sendState.isSendingDogecoin = newValue }
    }

    var isSendingEthereum: Bool {
        get { sendState.isSendingEthereum }
        set { sendState.isSendingEthereum = newValue }
    }

    var isSendingTron: Bool {
        get { sendState.isSendingTron }
        set { sendState.isSendingTron = newValue }
    }

    var isSendingSolana: Bool {
        get { sendState.isSendingSolana }
        set { sendState.isSendingSolana = newValue }
    }

    var isSendingXRP: Bool {
        get { sendState.isSendingXRP }
        set { sendState.isSendingXRP = newValue }
    }

    var isSendingStellar: Bool {
        get { sendState.isSendingStellar }
        set { sendState.isSendingStellar = newValue }
    }

    var isSendingMonero: Bool {
        get { sendState.isSendingMonero }
        set { sendState.isSendingMonero = newValue }
    }

    var isSendingCardano: Bool {
        get { sendState.isSendingCardano }
        set { sendState.isSendingCardano = newValue }
    }

    var isSendingSui: Bool {
        get { sendState.isSendingSui }
        set { sendState.isSendingSui = newValue }
    }

    var isSendingAptos: Bool {
        get { sendState.isSendingAptos }
        set { sendState.isSendingAptos = newValue }
    }

    var isSendingTON: Bool {
        get { sendState.isSendingTON }
        set { sendState.isSendingTON = newValue }
    }

    var isSendingICP: Bool {
        get { sendState.isSendingICP }
        set { sendState.isSendingICP = newValue }
    }

    var isSendingNear: Bool {
        get { sendState.isSendingNear }
        set { sendState.isSendingNear = newValue }
    }

    var isSendingPolkadot: Bool {
        get { sendState.isSendingPolkadot }
        set { sendState.isSendingPolkadot = newValue }
    }

    var tronLastSendErrorDetails: String? {
        get { sendState.tronLastSendErrorDetails }
        set { sendState.tronLastSendErrorDetails = newValue }
    }

    var tronLastSendErrorAt: Date? {
        get { sendState.tronLastSendErrorAt }
        set { sendState.tronLastSendErrorAt = newValue }
    }
}
