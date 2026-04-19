import Foundation
import Combine

@MainActor
final class SendPreviewStore: ObservableObject {
    @Published var ethereumSendPreview: EthereumSendPreview?
    @Published var bitcoinSendPreview: BitcoinSendPreview?
    @Published var bitcoinCashSendPreview: BitcoinSendPreview?
    @Published var bitcoinSVSendPreview: BitcoinSendPreview?
    @Published var litecoinSendPreview: BitcoinSendPreview?
    @Published var dogecoinSendPreview: DogecoinSendPreview?
    @Published var tronSendPreview: TronSendPreview?
    @Published var solanaSendPreview: SolanaSendPreview?
    @Published var xrpSendPreview: XrpSendPreview?
    @Published var stellarSendPreview: StellarSendPreview?
    @Published var moneroSendPreview: MoneroSendPreview?
    @Published var cardanoSendPreview: CardanoSendPreview?
    @Published var suiSendPreview: SuiSendPreview?
    @Published var aptosSendPreview: AptosSendPreview?
    @Published var tonSendPreview: TonSendPreview?
    @Published var icpSendPreview: IcpSendPreview?
    @Published var nearSendPreview: NearSendPreview?
    @Published var polkadotSendPreview: PolkadotSendPreview?
}
