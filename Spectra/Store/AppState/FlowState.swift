import Foundation
import Combine

final class WalletFlowState: ObservableObject {
    @Published var importError: String?
    @Published var isImportingWallet: Bool = false
    @Published var isShowingWalletImporter: Bool = false
    @Published var isShowingSendSheet: Bool = false
    @Published var isShowingReceiveSheet: Bool = false
    @Published var walletPendingDeletion: ImportedWallet?
    @Published var editingWalletID: UUID?
    @Published var sendWalletID: String = ""
    @Published var sendHoldingKey: String = ""
    @Published var sendAmount: String = ""
    @Published var sendAddress: String = ""
    @Published var sendError: String?
    @Published var sendDestinationRiskWarning: String?
    @Published var sendDestinationInfoMessage: String?
    @Published var isCheckingSendDestinationBalance: Bool = false
    @Published var pendingHighRiskSendReasons: [String] = []
    @Published var isShowingHighRiskSendConfirmation: Bool = false
    @Published var sendVerificationNotice: String?
    @Published var sendVerificationNoticeIsWarning: Bool = false
    @Published var receiveWalletID: String = ""
    @Published var receiveChainName: String = ""
    @Published var receiveHoldingKey: String = ""
    @Published var receiveResolvedAddress: String = ""
    @Published var isResolvingReceiveAddress: Bool = false
}
