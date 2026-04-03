import Foundation
import SwiftUI

extension WalletStore {
    var walletPendingDeletion: ImportedWallet? {
        get { flowState.walletPendingDeletion }
        set { flowState.walletPendingDeletion = newValue }
    }

    var editingWalletID: UUID? {
        get { flowState.editingWalletID }
        set { flowState.editingWalletID = newValue }
    }

    var importError: String? {
        get { flowState.importError }
        set { flowState.importError = newValue }
    }

    var isImportingWallet: Bool {
        get { flowState.isImportingWallet }
        set { flowState.isImportingWallet = newValue }
    }

    var isShowingWalletImporter: Bool {
        get { flowState.isShowingWalletImporter }
        set { flowState.isShowingWalletImporter = newValue }
    }

    var isShowingSendSheet: Bool {
        get { flowState.isShowingSendSheet }
        set { flowState.isShowingSendSheet = newValue }
    }

    var sendWalletID: String {
        get { flowState.sendWalletID }
        set { flowState.sendWalletID = newValue }
    }

    var sendHoldingKey: String {
        get { flowState.sendHoldingKey }
        set { flowState.sendHoldingKey = newValue }
    }

    var sendAmount: String {
        get { flowState.sendAmount }
        set { flowState.sendAmount = newValue }
    }

    var sendAddress: String {
        get { flowState.sendAddress }
        set { flowState.sendAddress = newValue }
    }

    var sendError: String? {
        get { flowState.sendError }
        set { flowState.sendError = newValue }
    }

    var sendDestinationRiskWarning: String? {
        get { flowState.sendDestinationRiskWarning }
        set { flowState.sendDestinationRiskWarning = newValue }
    }

    var sendDestinationInfoMessage: String? {
        get { flowState.sendDestinationInfoMessage }
        set { flowState.sendDestinationInfoMessage = newValue }
    }

    var isCheckingSendDestinationBalance: Bool {
        get { flowState.isCheckingSendDestinationBalance }
        set { flowState.isCheckingSendDestinationBalance = newValue }
    }

    var pendingHighRiskSendReasons: [String] {
        get { flowState.pendingHighRiskSendReasons }
        set { flowState.pendingHighRiskSendReasons = newValue }
    }

    var isShowingHighRiskSendConfirmation: Bool {
        get { flowState.isShowingHighRiskSendConfirmation }
        set { flowState.isShowingHighRiskSendConfirmation = newValue }
    }

    var sendVerificationNotice: String? {
        get { flowState.sendVerificationNotice }
        set { flowState.sendVerificationNotice = newValue }
    }

    var sendVerificationNoticeIsWarning: Bool {
        get { flowState.sendVerificationNoticeIsWarning }
        set { flowState.sendVerificationNoticeIsWarning = newValue }
    }

    var sendWalletIDBinding: Binding<String> {
        Binding(get: { self.flowState.sendWalletID }, set: { self.flowState.sendWalletID = $0 })
    }

    var sendHoldingKeyBinding: Binding<String> {
        Binding(get: { self.flowState.sendHoldingKey }, set: { self.flowState.sendHoldingKey = $0 })
    }

    var sendAddressBinding: Binding<String> {
        Binding(get: { self.flowState.sendAddress }, set: { self.flowState.sendAddress = $0 })
    }

    var sendAmountBinding: Binding<String> {
        Binding(get: { self.flowState.sendAmount }, set: { self.flowState.sendAmount = $0 })
    }

    var isShowingHighRiskSendConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.flowState.isShowingHighRiskSendConfirmation },
            set: { self.flowState.isShowingHighRiskSendConfirmation = $0 }
        )
    }

    var isShowingSendSheetBinding: Binding<Bool> {
        Binding(get: { self.flowState.isShowingSendSheet }, set: { self.flowState.isShowingSendSheet = $0 })
    }

}
