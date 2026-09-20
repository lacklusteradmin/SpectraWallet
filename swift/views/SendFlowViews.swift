import Foundation
import SwiftUI
import VisionKit

private enum SendFlowStep: Int, CaseIterable, Identifiable {
    case from
    case recipient
    case amount
    case confirm
    case result

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .from: return "From"
        case .recipient: return "To"
        case .amount: return "Amount"
        case .confirm: return "Review"
        case .result: return "Sent"
        }
    }

    var systemImage: String {
        switch self {
        case .from: return "creditcard.fill"
        case .recipient: return "person.crop.circle.badge.arrow.forward.fill"
        case .amount: return "number.circle.fill"
        case .confirm: return "checkmark.shield.fill"
        case .result: return "checkmark.circle.fill"
        }
    }

    static let composerSteps: [SendFlowStep] = [.from, .recipient, .amount, .confirm]
}

struct SendView: View {
    @Bindable var store: AppState
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?
    @State private var currentStep: SendFlowStep = .from
    @State private var flowDirection: Int = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var validatedRecipientKey: String?
    @State private var recipientError: String?
    @State private var isValidatingRecipient = false
    @State private var quotedInputKey: String?
    @State private var recipientValidationAttempt = 0
    @State private var sendWalletPassword = ""

    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }
    private var isSendBusy: Bool { !store.sendingChains.isEmpty || !store.preparingChains.isEmpty }

    private var selectedNetworkSendCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }

    var body: some View {
        let selectedCoin = selectedNetworkSendCoin
        ZStack {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if currentStep != .result {
                        stepProgress
                    }

                    stepContent
                        .id(currentStep)
                        .transition(stepTransition)

                    if currentStep != .result {
                        SendStatusCards(store: store)
                    }
                }
                .padding(20)

            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { flowBottomBar(selectedCoin: selectedCoin) }
        .navigationTitle(AppLocalization.string(currentStep.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppLocalization.string("Done")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.cancelSend()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(AppLocalization.string("Close"))
            }
        }
        .task(id: "\(recipientKey)|\(recipientValidationAttempt)") {
            let key = recipientKey
            validatedRecipientKey = nil
            recipientError = nil
            isValidatingRecipient = false
            guard let coin = selectedNetworkSendCoin,
                  !store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isValidatingRecipient = true
            defer { if recipientKey == key { isValidatingRecipient = false } }
            do {
                try await Task.sleep(for: .milliseconds(350))
                _ = try await store.resolveSendDestination(input: store.sendAddress, for: coin.chainName)
                guard !Task.isCancelled, recipientKey == key else { return }
                validatedRecipientKey = key
            } catch {
                guard !Task.isCancelled, recipientKey == key else { return }
                recipientError = AppLocalization.string("Check the address and selected network, then try again.")
            }
        }
        .sheet(isPresented: $isShowingQRScanner) {
            SendQRScannerSheet { payload in applyScannedRecipientPayload(payload) }
        }
        .alert(AppLocalization.string("QR Scanner"), isPresented: .isPresent($qrScannerErrorMessage)) {
            Button(AppLocalization.string("OK"), role: .cancel) {}
        } message: {
            if let qrScannerErrorMessage { Text(verbatim: qrScannerErrorMessage) }
        }
        .onDisappear { sendWalletPassword = "" }
        .onChange(of: store.isShowingHighRiskSendConfirmation) { _, showing in
            if !showing { sendWalletPassword = "" }
        }
        .onChange(of: store.sendHoldingKey) { _, _ in selectedAddressBookEntryID = "" }
        .onChange(of: store.lastSentTransaction?.id) { old, new in
            if old == nil, new != nil {
                spectraNotificationHaptic(.success)
                go(to: .result)
            }
        }
        .task(id: previewRefreshKey) {
            let key = previewRefreshKey
            quotedInputKey = nil
            do {
                try await Task.sleep(for: .milliseconds(350))
                while !store.preparingChains.isEmpty {
                    try await Task.sleep(for: .milliseconds(100))
                }
                try Task.checkCancellation()
                await store.refreshSendPreview()
                guard !Task.isCancelled, previewRefreshKey == key else { return }
                quotedInputKey = key
            } catch { return }
        }
        .alert(AppLocalization.string("Confirm Send"), isPresented: $store.isShowingHighRiskSendConfirmation) {
            if store.pendingSendReview?.requiresWalletPassword == true {
                SecureField(AppLocalization.string("Wallet Password"), text: $sendWalletPassword)
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                sendWalletPassword = ""
                store.clearHighRiskSendConfirmation()
            }
            Button(AppLocalization.string("Send"), role: .destructive) {
                let password = store.pendingSendReview?.requiresWalletPassword == true ? sendWalletPassword : nil
                sendWalletPassword = ""
                Task { await store.confirmHighRiskSendAndSubmit(password: password) }
            }
            .disabled(store.pendingSendReview?.requiresWalletPassword == true && sendWalletPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(
                store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                    ? AppLocalization.string("This transfer has elevated risk.")
                    : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• ")
            )
        }
    }

    // MARK: - Flow shell

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .from:
            SendFromPage(store: store)
        case .recipient:
            SendRecipientPage(
                store: store,
                selectedAddressBookEntryID: $selectedAddressBookEntryID,
                isShowingQRScanner: $isShowingQRScanner,
                qrScannerErrorMessage: $qrScannerErrorMessage,
                validationError: recipientError,
                isValidating: isValidatingRecipient,
                isValidated: validatedRecipientKey == recipientKey,
                retryValidation: { recipientValidationAttempt += 1 }
            )
        case .amount:
            SendAmountPage(store: store, quoteIsCurrent: quotedInputKey == previewRefreshKey)
        case .confirm:
            SendConfirmationStep(store: store, showsResult: false)
        case .result:
            SendConfirmationStep(store: store, showsResult: true)
        }
    }

    private var stepTransition: AnyTransition {
        let insertionEdge: Edge = flowDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = flowDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var stepProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.format("Step %lld of %lld · %@", currentStep.rawValue + 1,
                                        SendFlowStep.composerSteps.count, AppLocalization.string(currentStep.title)))
                .font(.subheadline.weight(.semibold))
            ProgressView(value: Double(currentStep.rawValue + 1), total: Double(SendFlowStep.composerSteps.count))
                .tint(.orange)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func flowBottomBar(selectedCoin: Coin?) -> some View {
        SpectraBottomActionBar {
            if currentStep != .from && currentStep != .result {
                Button {
                    spectraHaptic(.light)
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(AppLocalization.string("Back"))
                .spectraPressable()
            }

            Button {
                handlePrimaryAction(selectedCoin: selectedCoin)
            } label: {
                HStack(spacing: 8) {
                    if primaryShowsProgress {
                        SpectraLoadingGlyph(size: 20, tint: .white)
                    } else {
                        Image(systemName: primaryActionSystemImage)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Text(AppLocalization.string(primaryActionTitle))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .spectraPressable()
            .disabled(!canUsePrimaryAction(selectedCoin: selectedCoin))
        }
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .from, .recipient: return "Next"
        case .amount: return "Review"
        case .confirm: return "Send"
        case .result: return "Done"
        }
    }

    private var primaryActionSystemImage: String {
        switch currentStep {
        case .confirm: return "arrow.up.circle.fill"
        case .result: return "checkmark"
        default: return "chevron.right"
        }
    }

    private var primaryShowsProgress: Bool {
        currentStep == .confirm && isSendBusy
    }

    private func handlePrimaryAction(selectedCoin: Coin?) {
        switch currentStep {
        case .from:
            go(to: .recipient)
        case .recipient:
            go(to: .amount)
        case .amount:
            guard let coin = selectedCoin else { return }
            let input = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    let resolved = try await store.resolveSendDestination(input: input, for: coin.chainName)
                    guard currentStep == .amount,
                          store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines) == input,
                          selectedNetworkSendCoin?.holdingKey == coin.holdingKey else { return }
                    store.reviewedSendDestination = (input, coin.chainName, resolved.address)
                    if resolved.usedEns { store.sendDestinationInfoMessage = AppLocalization.format("Resolved ENS %@ to %@.", input, resolved.address) }
                    go(to: .confirm)
                } catch { store.sendError = error.localizedDescription }
            }
        case .confirm:
            spectraHaptic(.heavy)
            Task { await store.submitSend() }
        case .result:
            store.cancelSend()
        }
    }

    private func canUsePrimaryAction(selectedCoin: Coin?) -> Bool {
        switch currentStep {
        case .from:
            return store.selectedWalletForSend() != nil && selectedCoin != nil
        case .recipient:
            return validatedRecipientKey == recipientKey
        case .amount:
            return store.sendAmountIsValid
        case .confirm:
            return !isSendBusy
                && store.selectedWalletForSend() != nil
                && selectedCoin != nil
                && validatedRecipientKey == recipientKey
                && store.sendAmountIsValid
                && quotedInputKey == previewRefreshKey
                && store.customEvmFeeValidationError == nil
                && store.evmNonceValidationError == nil
        case .result:
            return true
        }
    }

    private func goBack() {
        guard let previous = SendFlowStep(rawValue: currentStep.rawValue - 1) else { return }
        go(to: previous)
    }

    private func go(to step: SendFlowStep) {
        flowDirection = step.rawValue >= currentStep.rawValue ? 1 : -1
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            currentStep = step
        }
    }

    private var recipientKey: String { [store.sendWalletID, store.sendHoldingKey, store.sendAddress].joined(separator: "|") }

    private var previewRefreshKey: String {
        [
            store.sendWalletID,
            store.sendHoldingKey,
            store.sendAddress,
            store.sendAmount,
            store.useCustomEvmFees.description,
            store.customEvmMaxFeeGwei,
            store.customEvmPriorityFeeGwei,
            store.evmManualNonceEnabled.description,
            store.evmManualNonce,
            String(describing: store.selectedSendCoin.map { store.feePriority(forChain: $0.chainName) }),
        ].joined(separator: "|")
    }

    private func applyScannedRecipientPayload(_ payload: String) {
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            qrScannerErrorMessage = AppLocalization.string("The scanned QR code did not contain a usable address.")
            return
        }
        // Core reads the payload — bare address or payment URI — against the
        // network the wallet is on, and hands back the stored form. With no
        // network there is nothing to judge an address against, so nothing is
        // filled in.
        guard let network = scannedPayloadNetwork,
            let address = scannedSendAddress(chainName: network.displayName, payload: payload)
        else {
            qrScannerErrorMessage = AppLocalization.string("The scanned QR code does not contain a valid address for the selected asset.")
            return
        }
        store.sendAddress = address
        qrScannerErrorMessage = nil
    }

    /// The network a scanned address must belong to: the one the sending wallet
    /// is on for the selected asset's family.
    private var scannedPayloadNetwork: Chain? {
        guard let coin = store.selectedSendCoin, let family = Chain(displayName: coin.chainName)?.id else { return nil }
        let networkID = store.selectedWalletForSend()?.networkChainId ?? store.networkChainID(forFamily: family)
        return Chain(id: networkID)
    }
}
