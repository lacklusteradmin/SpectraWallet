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

                    stepContent(selectedCoin: selectedCoin)
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
        .alert(AppLocalization.string("High-Risk Send"), isPresented: $store.isShowingHighRiskSendConfirmation) {
            Button(AppLocalization.string("Cancel"), role: .cancel) { store.clearHighRiskSendConfirmation() }
            Button(AppLocalization.string("Send Anyway"), role: .destructive) {
                Task { await store.confirmHighRiskSendAndSubmit() }
            }
        } message: {
            Text(
                store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                    ? "This transfer has elevated risk."
                    : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• ")
            )
        }
    }

    // MARK: - Flow shell

    @ViewBuilder
    private func stepContent(selectedCoin: Coin?) -> some View {
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
        VStack(spacing: 0) {
            Divider().opacity(0.2)
            HStack(spacing: 12) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
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
                    if resolved.usedEns { store.sendDestinationInfoMessage = "Resolved ENS \(input) to \(resolved.address)." }
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
            store.sendAdvancedMode.description,
            store.sendUTXOMaxInputCount.description,
            store.sendEnableRBF.description,
            store.sendEnableCPFP.description,
            store.sendLitecoinChangeStrategy.rawValue,
            store.feePriorityByChain.description,
        ].joined(separator: "|")
    }

    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = AppLocalization.string("The scanned QR code did not contain a usable address.")
            return
        }
        let selectedChainName = store.availableSendCoins(for: store.sendWalletID)
            .first(where: { $0.holdingKey == store.sendHoldingKey })?.chainName
        guard let resolvedAddress = resolvedRecipientAddress(from: trimmedPayload, chainName: selectedChainName) else {
            qrScannerErrorMessage = AppLocalization.string("The scanned QR code does not contain a valid address for the selected asset.")
            return
        }
        store.sendAddress = resolvedAddress
        qrScannerErrorMessage = nil
    }

    private func resolvedRecipientAddress(from payload: String, chainName: String?) -> String? {
        let candidates = qrAddressCandidates(from: payload)
        guard let chainName else { return candidates.first }
        for candidate in candidates {
            if isValidScannedAddress(candidate, for: chainName) {
                if Chain(displayName: chainName)?.isEVM == true { return normalizeEVMAddress(candidate) }
                return candidate
            }
        }
        return nil
    }

    private func qrAddressCandidates(from payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var candidates: [String] = []
        func appendCandidate(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }
        appendCandidate(trimmed)
        let withoutQuery = trimmed.components(separatedBy: "?").first ?? trimmed
        appendCandidate(withoutQuery)
        if let colonIndex = withoutQuery.firstIndex(of: ":") {
            appendCandidate(String(withoutQuery[withoutQuery.index(after: colonIndex)...]))
        }
        if let components = URLComponents(string: trimmed) {
            if let host = components.host { appendCandidate(host + components.path) }
            if let firstPathComponent = components.path.split(separator: "/").first { appendCandidate(String(firstPathComponent)) }
        }
        return candidates
    }

    /// A scanned address is judged against the network the wallet is actually
    /// on — which is a chain, so the registry answers both halves.
    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        let family = Chain(displayName: chainName)?.id ?? ""
        guard !family.isEmpty else { return false }
        let selected =
            store.wallet(for: store.sendWalletID).map {
                store.walletNetworkChainID(for: $0, family: family)
            } ?? store.networkChainID(forFamily: family)
        let kind = (Chain(id: selected)?.addressValidationKind ?? "")
        guard !kind.isEmpty else { return false }
        return AddressValidation.isValid(address, kind: kind)
    }
}
