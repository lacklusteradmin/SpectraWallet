import Foundation
import SwiftUI

extension WalletStore {
    var isShowingReceiveSheet: Bool {
        get { flowState.isShowingReceiveSheet }
        set { flowState.isShowingReceiveSheet = newValue }
    }

    var receiveWalletID: String {
        get { flowState.receiveWalletID }
        set { flowState.receiveWalletID = newValue }
    }

    var receiveChainName: String {
        get { flowState.receiveChainName }
        set { flowState.receiveChainName = newValue }
    }

    var receiveHoldingKey: String {
        get { flowState.receiveHoldingKey }
        set { flowState.receiveHoldingKey = newValue }
    }

    var receiveResolvedAddress: String {
        get { flowState.receiveResolvedAddress }
        set { flowState.receiveResolvedAddress = newValue }
    }

    var isResolvingReceiveAddress: Bool {
        get { flowState.isResolvingReceiveAddress }
        set { flowState.isResolvingReceiveAddress = newValue }
    }

    var receiveWalletIDBinding: Binding<String> {
        Binding(get: { self.flowState.receiveWalletID }, set: { self.flowState.receiveWalletID = $0 })
    }

    var isShowingReceiveSheetBinding: Binding<Bool> {
        Binding(get: { self.flowState.isShowingReceiveSheet }, set: { self.flowState.isShowingReceiveSheet = $0 })
    }
}
