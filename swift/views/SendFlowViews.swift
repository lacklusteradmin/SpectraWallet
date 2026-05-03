import Foundation
import SwiftUI
import VisionKit
struct SendView: View {
    @Bindable var store: AppState
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?
    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }
    private var isSendBusy: Bool {
        !store.sendingChains.isEmpty || !store.preparingChains.isEmpty
    }
    private var selectedNetworkSendCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }
    @ViewBuilder
    private var sendStatusSections: some View {
        if let sendError = store.sendError {
            spectraDetailCard {
                Text(sendError).font(.caption).foregroundStyle(.red)
            }
        }
        if let sendVerificationNotice = store.sendVerificationNotice {
            spectraDetailCard(title: "Verification") {
                Text(sendVerificationNotice).font(.caption).foregroundStyle(store.sendVerificationNoticeIsWarning ? .red : .orange)
            }
        }
        if let lastSentTransaction = store.lastSentTransaction {
            spectraDetailCard(title: "Last Sent") {
                Text("\(lastSentTransaction.symbol) sent to \(lastSentTransaction.addressPreviewText)").font(.subheadline)
                HStack {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TransactionStatusBadge(status: lastSentTransaction.status)
                }
                if let pendingTransactionRefreshStatusText = store.pendingTransactionRefreshStatusText {
                    Text(pendingTransactionRefreshStatusText).font(.caption2).foregroundStyle(.secondary)
                }
                if let transactionHash = lastSentTransaction.transactionHash {
                    Text(transactionHash).font(.caption2.monospaced()).textSelection(.enabled)
                }
                if let transactionExplorerURL = lastSentTransaction.transactionExplorerURL,
                    let transactionExplorerLabel = lastSentTransaction.transactionExplorerLabel
                {
                    Link(destination: transactionExplorerURL) {
                        Label(transactionExplorerLabel, systemImage: "safari").font(.headline).frame(maxWidth: .infinity).padding(
                            .vertical, 12)
                    }.buttonStyle(.glassProminent)
                }
                Button {
                    store.saveLastSentRecipientToAddressBook()
                } label: {
                    Label(
                        store.canSaveLastSentRecipientToAddressBook()
                            ? AppLocalization.string("Save Recipient To Address Book") : AppLocalization.string("Recipient Already Saved"),
                        systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                    ).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.disabled(!store.canSaveLastSentRecipientToAddressBook())
            }
        }
        if let chainName = store.sendingChains.first {
            sendingSection(AppLocalization.string("Broadcasting \(chainName) transaction..."))
        }
    }
    @ViewBuilder
    private func optionalSendingSection(_ isActive: Bool, _ message: String) -> some View {
        if isActive { sendingSection(message) }
    }
    private func sendingSection(_ title: String) -> some View {
        spectraDetailCard {
            HStack(spacing: 10) {
                ProgressView()
                Text(title).font(.caption)
            }
        }
    }
    private static let networkSendChainNames: Set<String> = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism",
        "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "XRP Ledger", "Monero", "Cardano", "Sui", "Aptos", "TON", "NEAR",
        "Polkadot", "Stellar", "Internet Computer",
    ]
    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        coin.map { Self.networkSendChainNames.contains($0.chainName) } ?? false
    }
    private func chainFeePriorityBinding(for chainName: String) -> Binding<ChainFeePriorityOption> {
        Binding(
            get: { store.feePriorityOption(for: chainName) }, set: { store.setFeePriorityOption($0, for: chainName) }
        )
    }
    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        switch coin.chainID {
        case .litecoin: return sendPreviewStore.litecoinSendPreview
        case .bitcoinCash: return sendPreviewStore.bitcoinCashSendPreview
        default: return sendPreviewStore.bitcoinSendPreview
        }
    }
    private func utxoAdvancedModeCaption(for chainName: String) -> String? {
        switch AppEndpointDirectory.appChain(for: chainName)?.id {
        case .bitcoin:
            return AppLocalization.string("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        case .bitcoinCash:
            return AppLocalization.string("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
        case .dogecoin:
            return AppLocalization.string("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        default:
            return nil
        }
    }
    private func evmFeeSymbol(for chainName: String) -> String {
        AppEndpointDirectory.appChain(for: chainName)?.nativeSymbol ?? "ETH"
    }
    private func formattedPreviewAssetAmount(_ amount: Double, for coin: Coin) -> String {
        store.formattedAssetAmount(amount, symbol: coin.symbol, chainName: coin.chainName)
    }
    @ViewBuilder
    private func sendPreviewDetailsSection(for selectedCoin: Coin) -> some View {
        if let details = store.sendPreviewDetails(for: selectedCoin), details.hasVisibleContent {
            Section(AppLocalization.string("Preview Details")) {
                if let spendableBalance = details.spendableBalance {
                    Text("Spendable Balance: \(formattedPreviewAssetAmount(spendableBalance, for: selectedCoin))")
                }
                if let feeRateDescription = details.feeRateDescription { Text("Fee Rate: \(feeRateDescription)") }
                if let estimatedTransactionBytes = details.estimatedTransactionBytes {
                    Text("Estimated Size: \(estimatedTransactionBytes) bytes")
                }
                if let selectedInputCount = details.selectedInputCount { Text("Selected Inputs: \(selectedInputCount)") }
                if let usesChangeOutput = details.usesChangeOutput {
                    let changeOutputLabel = usesChangeOutput ? AppLocalization.string("Yes") : AppLocalization.string("No")
                    Text("Change Output: \(changeOutputLabel)")
                }
                if let maxSendable = details.maxSendable {
                    Text("Max Sendable: \(formattedPreviewAssetAmount(maxSendable, for: selectedCoin))")
                }
            }
        }
    }
    @ViewBuilder
    private func networkSendSections(selectedCoin: Coin?) -> some View {
        if let selectedCoin, selectedCoin.isUTXOChain {
            Section(AppLocalization.string("Advanced UTXO Mode")) {
                Toggle(AppLocalization.string("Enable Advanced Controls"), isOn: $store.sendAdvancedMode)
                if store.sendAdvancedMode {
                    Stepper(
                        "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")",
                        value: $store.sendUTXOMaxInputCount, in: 0...50
                    )
                    if selectedCoin.chainID == .litecoin {
                        let isMwebSend = store.sendAddress.hasPrefix("ltcmweb1") || store.sendAddress.hasPrefix("tmweb1")
                        Toggle(AppLocalization.string("Enable RBF Policy"), isOn: $store.sendEnableRBF)
                        if !isMwebSend {
                            Picker(AppLocalization.string("Change Strategy"), selection: $store.sendLitecoinChangeStrategy) {
                                ForEach(LitecoinChangeStrategy.allCases) { strategy in Text(strategy.displayName).tag(strategy) }
                            }.pickerStyle(.menu)
                        }
                        Text(
                            AppLocalization.string(
                                isMwebSend
                                    ? "MWEB peg-in: coins enter the MimbleWimble sidechain. Fee covers both the on-chain peg-in output and the ~1 kB MWEB extension block. Change strategy is ignored for MWEB sends."
                                    : "For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address."
                            )
                        ).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle(AppLocalization.string("RBF Intent"), isOn: $store.sendEnableRBF)
                        Toggle(AppLocalization.string("CPFP Intent"), isOn: $store.sendEnableCPFP)
                        if let caption = utxoAdvancedModeCaption(for: selectedCoin.chainName) {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if let selectedCoin, !selectedCoin.isUTXOChain {
            Section(AppLocalization.string("Fee Priority")) {
                Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
                }.pickerStyle(.segmented)
                Text(
                    AppLocalization.string(
                        "Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build.")
                ).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let selectedCoin, selectedCoin.isUTXOChain, selectedCoin.isNativeCoin {
            let feeSymbol = selectedCoin.symbol
            let utxoPreview = utxoPreview(for: selectedCoin)
            Section(AppLocalization.string("\(selectedCoin.chainName) Network")) {
                Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
                }.pickerStyle(.segmented)
                Text(
                    AppLocalization.string(
                        "Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains."
                    )
                ).font(.caption).foregroundStyle(.secondary)
                if selectedCoin.chainID == .dogecoin, store.preparingChains.contains("Dogecoin") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(AppLocalization.string("Loading UTXOs and fee estimate...")).font(.caption)
                    }
                } else if selectedCoin.chainID == .dogecoin, let dogecoinSendPreview = sendPreviewStore.dogecoinSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDoge, symbol: feeSymbol) {
                        Text(
                            "Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDoge, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))"
                        )
                    } else {
                        Text("Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDoge, specifier: "%.6f") \(feeSymbol)")
                    }
                    Text("Confirmation Preference: \(confirmationPreferenceText(for: dogecoinSendPreview.feePriority))")
                } else if let utxoPreview {
                    Text("Estimated Fee Rate: \(utxoPreview.estimatedFeeRateSatVb) sat/vB")
                    if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBtc, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBtc, specifier: "%.8f") \(feeSymbol) (~\(fiatFee))")
                    } else {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBtc, specifier: "%.8f") \(feeSymbol)")
                    }
                } else {
                    Text("Enter amount to preview estimated \(selectedCoin.chainName) network fee.").font(.caption).foregroundStyle(
                        .secondary)
                }
            }
        }
        if let selectedCoin, selectedCoin.isEVMChain {
            Section(AppLocalization.string("\(selectedCoin.chainName) Network")) {
                Toggle(AppLocalization.string("Use Custom Fees"), isOn: $store.useCustomEthereumFees)
                if store.useCustomEthereumFees {
                    TextField(AppLocalization.string("Max Fee (gwei)"), text: $store.customEthereumMaxFeeGwei).keyboardType(.decimalPad)
                    TextField(AppLocalization.string("Priority Fee (gwei)"), text: $store.customEthereumPriorityFeeGwei).keyboardType(.decimalPad)
                    if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                        Text(customEthereumFeeValidationError).font(.caption).foregroundStyle(.red)
                    } else {
                        Text(AppLocalization.string("Custom EIP-1559 fees are applied to this send and preview.")).font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
                Toggle(AppLocalization.string("Manual Nonce"), isOn: $store.ethereumManualNonceEnabled)
                if store.ethereumManualNonceEnabled {
                    TextField(AppLocalization.string("Nonce"), text: $store.ethereumManualNonce).keyboardType(.numberPad)
                    if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
                        Text(customEthereumNonceValidationError).font(.caption).foregroundStyle(.red)
                    }
                }
                if selectedCoin.chainID == .ethereum {
                    if store.isPreparingEthereumReplacementContext {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(AppLocalization.string("Preparing replacement/cancel context...")).font(.caption)
                        }
                    } else if store.hasPendingEthereumSendForSelectedWallet {
                        Button(AppLocalization.string("Speed Up Pending Transaction")) {
                            Task { await store.prepareEthereumSpeedUpContext() }
                        }
                        Button(AppLocalization.string("Cancel Pending Transaction")) {
                            Task { await store.prepareEthereumCancelContext() }
                        }
                    }
                    if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage {
                        Text(ethereumReplacementNonceStateMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.preparingChains.contains("Ethereum") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(AppLocalization.string("Loading nonce and fee estimate...")).font(.caption)
                    }
                } else if let ethereumSendPreview = sendPreviewStore.ethereumSendPreview {
                    Text("Nonce: \(ethereumSendPreview.nonce)")
                    Text("Gas Limit: \(ethereumSendPreview.gasLimit)")
                    Text("Max Fee: \(ethereumSendPreview.maxFeePerGasGwei, specifier: "%.2f") gwei")
                    Text("Priority Fee: \(ethereumSendPreview.maxPriorityFeePerGasGwei, specifier: "%.2f") gwei")
                    let feeSymbol = evmFeeSymbol(for: selectedCoin.chainName)
                    if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeEth, symbol: feeSymbol) {
                        Text(
                            "Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeEth, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))"
                        ).font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeEth, specifier: "%.6f") \(feeSymbol)").font(
                            .subheadline.weight(.semibold))
                    }
                } else {
                    Text(AppLocalization.string("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(
                    AppLocalization.string(
                        "Spectra signs and broadcasts supported \(selectedCoin.chainName) transfers. This preview is the live nonce and fee estimate for the transaction you are about to send."
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
        }
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Tron", isPreparing: store.preparingChains.contains("Tron"),
            fee: sendPreviewStore.tronSendPreview.map { ($0.estimatedNetworkFeeTrx, "TRX", "%.6f") },
            footer: "Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.",
            extraCaption: selectedCoin?.symbol == "USDT" ? "USDT on Tron uses TRX for network fees. Keep a TRX balance for gas." : nil
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "XRP Ledger", isPreparing: store.preparingChains.contains("XRP Ledger"),
            fee: sendPreviewStore.xrpSendPreview.map { ($0.estimatedNetworkFeeXrp, "XRP", "%.6f") },
            footer: "Spectra signs and broadcasts XRP transfers in-app.",
            extraLines: sendPreviewStore.xrpSendPreview.map { p in
                [
                    p.sequence > 0 ? "Sequence: \(p.sequence)" : nil,
                    p.lastLedgerSequence > 0 ? "Last Ledger Sequence: \(p.lastLedgerSequence)" : nil,
                ].compactMap { $0 }
            } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Solana", isPreparing: store.preparingChains.contains("Solana"),
            fee: sendPreviewStore.solanaSendPreview.map { ($0.estimatedNetworkFeeSol, "SOL", "%.6f") },
            footer: "Spectra signs and broadcasts Solana transfers in-app, including SOL and supported SPL assets.",
            extraCaption: selectedCoin?.symbol != "SOL" ? "Token transfers on Solana still use SOL for network fees." : nil
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Cardano", isPreparing: store.preparingChains.contains("Cardano"),
            fee: sendPreviewStore.cardanoSendPreview.map { ($0.estimatedNetworkFeeAda, "ADA", "%.6f") },
            footer: "Spectra signs and broadcasts ADA transfers in-app.",
            extraLines: sendPreviewStore.cardanoSendPreview.map { p in p.ttlSlot > 0 ? ["TTL Slot: \(p.ttlSlot)"] : [] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Monero", isPreparing: store.preparingChains.contains("Monero"),
            fee: sendPreviewStore.moneroSendPreview.map { ($0.estimatedNetworkFeeXmr, "XMR", "%.6f") },
            footer: "Spectra prepares Monero sends in-app using the configured backend fee quote.",
            extraLines: sendPreviewStore.moneroSendPreview.map { ["Priority: \($0.priorityLabel)"] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "NEAR", isPreparing: store.preparingChains.contains("NEAR"),
            fee: sendPreviewStore.nearSendPreview.map { ($0.estimatedNetworkFeeNear, "NEAR", "%.6f") },
            footer: "Spectra signs and broadcasts NEAR transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Polkadot", isPreparing: store.preparingChains.contains("Polkadot"),
            fee: sendPreviewStore.polkadotSendPreview.map { ($0.estimatedNetworkFeeDot, "DOT", "%.6f") },
            footer: "Spectra signs and broadcasts Polkadot transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Stellar", isPreparing: store.preparingChains.contains("Stellar"),
            fee: sendPreviewStore.stellarSendPreview.map { ($0.estimatedNetworkFeeXlm, "XLM", "%.7f") },
            footer: "Spectra signs and broadcasts Stellar payments in-app.",
            extraLines: sendPreviewStore.stellarSendPreview.map { p in p.sequence > 0 ? ["Sequence: \(p.sequence)"] : [] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Internet Computer", isPreparing: store.preparingChains.contains("Internet Computer"),
            fee: sendPreviewStore.icpSendPreview.map { ($0.estimatedNetworkFeeIcp, "ICP", "%.8f") },
            footer: "Spectra signs and broadcasts ICP transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Sui", isPreparing: store.preparingChains.contains("Sui"),
            fee: sendPreviewStore.suiSendPreview.map { ($0.estimatedNetworkFeeSui, "SUI", "%.6f") },
            footer: "Spectra signs and broadcasts Sui transfers in-app.",
            extraLines: sendPreviewStore.suiSendPreview.map {
                ["Gas Budget: \($0.gasBudgetMist) MIST", "Reference Gas Price: \($0.referenceGasPrice)"]
            } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Aptos", isPreparing: store.preparingChains.contains("Aptos"),
            fee: sendPreviewStore.aptosSendPreview.map { ($0.estimatedNetworkFeeApt, "APT", "%.6f") },
            footer: "Spectra signs and broadcasts Aptos transfers in-app.",
            extraLines: sendPreviewStore.aptosSendPreview.map {
                ["Max Gas Amount: \($0.maxGasAmount)", "Gas Unit Price: \($0.gasUnitPriceOctas) octas"]
            } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "TON", isPreparing: store.preparingChains.contains("TON"),
            fee: sendPreviewStore.tonSendPreview.map { ($0.estimatedNetworkFeeTon, "TON", "%.6f") },
            footer: "Spectra signs and broadcasts TON transfers in-app.",
            extraLines: sendPreviewStore.tonSendPreview.map { ["Sequence Number: \($0.sequenceNumber)"] } ?? []
        )
        if let selectedCoin { sendPreviewDetailsSection(for: selectedCoin) }
    }
    @ViewBuilder
    private func simpleSendNetworkSection(
        for selectedCoin: Coin?, chainName: String, isPreparing: Bool, fee: (amount: Double, symbol: String, specifier: String)?,
        footer: String, extraLines: [String] = [], extraCaption: String? = nil
    ) -> some View {
        if let selectedCoin, selectedCoin.chainName == chainName {
            Section("\(chainName) Network") {
                if isPreparing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading \(chainName) fee estimate...").font(.caption)
                    }
                } else if let fee {
                    let feeFormatted = String(format: fee.specifier, fee.amount)
                    if let fiatFee = store.formattedFiatAmount(fromNative: fee.amount, symbol: fee.symbol) {
                        Text("Estimated Network Fee: \(feeFormatted) \(fee.symbol) (~\(fiatFee))").font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(feeFormatted) \(fee.symbol)").font(.subheadline.weight(.semibold))
                    }
                    ForEach(extraLines, id: \.self) { Text($0) }
                    if let extraCaption { Text(extraCaption).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Enter an amount to load a \(chainName) fee preview. Add a valid destination address before sending.").font(
                        .caption
                    ).foregroundStyle(.secondary)
                }
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var body: some View {
        let selectedCoin = selectedNetworkSendCoin
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SendPrimarySectionsView(
                        store: store, selectedAddressBookEntryID: $selectedAddressBookEntryID, isShowingQRScanner: $isShowingQRScanner,
                        qrScannerErrorMessage: $qrScannerErrorMessage
                    )
                    if hasNetworkSendSections(for: selectedCoin) {
                        VStack(alignment: .leading, spacing: 18) { networkSendSections(selectedCoin: selectedCoin) }.padding(18)
                            .spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                    }
                    sendStatusSections
                }.padding(20)
            }.navigationTitle(AppLocalization.string("Send")).sheet(isPresented: $isShowingQRScanner) {
                SendQRScannerSheet { payload in applyScannedRecipientPayload(payload) }
            }.alert(AppLocalization.string("QR Scanner"), isPresented: .isPresent($qrScannerErrorMessage)) {
                Button(AppLocalization.string("OK"), role: .cancel) {}
            } message: {
                if let qrScannerErrorMessage { Text(verbatim: qrScannerErrorMessage) }
            }.onChange(of: store.sendHoldingKey) { _, _ in
                selectedAddressBookEntryID = ""
            }.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Send")) {
                        Task {
                            await store.submitSend()
                        }
                    }.disabled(isSendBusy)
                }
            }.alert(AppLocalization.string("High-Risk Send"), isPresented: $store.isShowingHighRiskSendConfirmation) {
                Button(AppLocalization.string("Cancel"), role: .cancel) {
                    store.clearHighRiskSendConfirmation()
                }
                Button(AppLocalization.string("Send Anyway"), role: .destructive) {
                    Task {
                        await store.confirmHighRiskSendAndSubmit()
                    }
                }
            } message: {
                Text(
                    store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                        ? "This transfer has elevated risk."
                        : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• "))
            }
        }
    }
    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = AppLocalization.string("The scanned QR code did not contain a usable address.")
            return
        }
        let selectedChainName = store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })?
            .chainName
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
                if AppEndpointDirectory.appChain(for: chainName)?.isEVM == true {
                    return normalizeEVMAddress(candidate)
                }
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
            let suffix = String(withoutQuery[withoutQuery.index(after: colonIndex)...])
            appendCandidate(suffix)
        }
        if let components = URLComponents(string: trimmed) {
            if let host = components.host { appendCandidate(host + components.path) }
            if let firstPathComponent = components.path.split(separator: "/").first { appendCandidate(String(firstPathComponent)) }
        }
        return candidates
    }
    private static let addressValidationKindByChain: [String: String] = [
        "Bitcoin Cash": "bitcoinCash", "Bitcoin SV": "bitcoinSV", "Litecoin": "litecoin",
        "Ethereum": "evm", "Ethereum Classic": "evm", "Arbitrum": "evm", "Optimism": "evm",
        "BNB Chain": "evm", "Avalanche": "evm", "Hyperliquid": "evm",
        "Tron": "tron", "Solana": "solana", "Cardano": "cardano", "XRP Ledger": "xrp",
        "Monero": "monero", "Sui": "sui", "Aptos": "aptos", "TON": "ton",
        "Internet Computer": "internetComputer", "NEAR": "near",
    ]
    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        if chainName == "Bitcoin" {
            return AddressValidation.isValid(address, kind: "bitcoin", networkMode: store.bitcoinNetworkMode.rawValue)
        }
        if chainName == "Dogecoin" {
            let mode = (store.wallet(for: store.sendWalletID)?.dogecoinNetworkMode ?? store.dogecoinNetworkMode).rawValue
            return AddressValidation.isValid(address, kind: "dogecoin", networkMode: mode)
        }
        guard let kind = Self.addressValidationKindByChain[chainName] else { return false }
        return AddressValidation.isValid(address, kind: kind)
    }
    private func confirmationPreferenceText(for priority: String) -> String {
        switch DogecoinFeePriority(rawValue: priority) ?? .normal {
        case .economy: return "Economy (cost-optimized)"
        case .normal: return "Normal (balanced)"
        case .priority: return "Priority (faster confirmation bias)"
        }
    }
}
