import Foundation
import Combine

final class WalletSendState: ObservableObject {
    @Published var lastSentTransaction: TransactionRecord?
    @Published var lastPendingTransactionRefreshAt: Date?
    @Published var ethereumSendPreview: EthereumSendPreview?
    @Published var bitcoinSendPreview: BitcoinSendPreview?
    @Published var bitcoinCashSendPreview: BitcoinSendPreview?
    @Published var bitcoinSVSendPreview: BitcoinSendPreview?
    @Published var litecoinSendPreview: BitcoinSendPreview?
    @Published var dogecoinSendPreview: DogecoinWalletEngine.DogecoinSendPreview?
    @Published var tronSendPreview: TronSendPreview?
    @Published var solanaSendPreview: SolanaSendPreview?
    @Published var xrpSendPreview: XRPSendPreview?
    @Published var stellarSendPreview: StellarSendPreview?
    @Published var moneroSendPreview: MoneroSendPreview?
    @Published var cardanoSendPreview: CardanoSendPreview?
    @Published var suiSendPreview: SuiSendPreview?
    @Published var aptosSendPreview: AptosSendPreview?
    @Published var tonSendPreview: TONSendPreview?
    @Published var icpSendPreview: ICPSendPreview?
    @Published var nearSendPreview: NearSendPreview?
    @Published var polkadotSendPreview: PolkadotSendPreview?
    @Published var isSendingBitcoin: Bool = false
    @Published var isSendingBitcoinCash: Bool = false
    @Published var isSendingBitcoinSV: Bool = false
    @Published var isSendingLitecoin: Bool = false
    @Published var isSendingDogecoin: Bool = false
    @Published var isSendingEthereum: Bool = false
    @Published var isSendingTron: Bool = false
    @Published var isSendingSolana: Bool = false
    @Published var isSendingXRP: Bool = false
    @Published var isSendingStellar: Bool = false
    @Published var isSendingMonero: Bool = false
    @Published var isSendingCardano: Bool = false
    @Published var isSendingSui: Bool = false
    @Published var isSendingAptos: Bool = false
    @Published var isSendingTON: Bool = false
    @Published var isSendingICP: Bool = false
    @Published var isSendingNear: Bool = false
    @Published var isSendingPolkadot: Bool = false
    @Published var tronLastSendErrorDetails: String?
    @Published var tronLastSendErrorAt: Date?
}
