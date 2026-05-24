import Foundation
import SwiftUI
import VisionKit

struct SendView: View {
    @Bindable var store: AppState
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?

    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }
    private var isSendBusy: Bool { !store.sendingChains.isEmpty || !store.preparingChains.isEmpty }

    private var selectedNetworkSendCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }

    private static let networkSendChainNames: Set<String> = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism",
        "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "XRP Ledger", "Monero", "Cardano", "Sui", "Aptos", "TON", "NEAR",
        "Polkadot", "Stellar", "Internet Computer",
    ]

    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        coin.map { Self.networkSendChainNames.contains($0.chainName) } ?? false
    }

    var body: some View {
        let selectedCoin = selectedNetworkSendCoin
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SendPrimarySectionsView(
                        store: store, selectedAddressBookEntryID: $selectedAddressBookEntryID,
                        isShowingQRScanner: $isShowingQRScanner, qrScannerErrorMessage: $qrScannerErrorMessage
                    )
                    if hasNetworkSendSections(for: selectedCoin) {
                        networkCard(selectedCoin: selectedCoin)
                    }
                    sendStatusCards
                }
                .padding(20)
                .padding(.bottom, 90)
            }

            sendButton
        }
        .navigationTitle(AppLocalization.string("Send"))
        .navigationBarTitleDisplayMode(.inline)
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
            if old == nil, new != nil { spectraNotificationHaptic(.success) }
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

    // MARK: — Sticky send button

    private var sendButton: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)
            Button {
                spectraHaptic(.heavy)
                Task { await store.submitSend() }
            } label: {
                HStack(spacing: 8) {
                    if isSendBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Text(AppLocalization.string("Send"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSendBusy)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    // MARK: — Network fee card

    @ViewBuilder
    private func networkCard(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            networkCardContent(selectedCoin: selectedCoin)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func networkCardContent(selectedCoin: Coin?) -> some View {
        if let selectedCoin, selectedCoin.isUTXOChain {
            utxoNetworkContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, !selectedCoin.isUTXOChain, !selectedCoin.isEVMChain {
            feePriorityContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, selectedCoin.isUTXOChain, selectedCoin.isNativeCoin {
            utxoFeePreviewContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, selectedCoin.isEVMChain {
            evmNetworkContent(selectedCoin: selectedCoin)
        }
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Tron",
            isPreparing: store.preparingChains.contains("Tron"),
            fee: sendPreviewStore.tronSendPreview.map { ($0.estimatedNetworkFeeTrx, "TRX", "%.6f") },
            footer: "Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.",
            extraCaption: selectedCoin?.symbol == "USDT" ? "USDT on Tron uses TRX for network fees. Keep a TRX balance for gas." : nil)
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "XRP Ledger",
            isPreparing: store.preparingChains.contains("XRP Ledger"),
            fee: sendPreviewStore.xrpSendPreview.map { ($0.estimatedNetworkFeeXrp, "XRP", "%.6f") },
            footer: "Spectra signs and broadcasts XRP transfers in-app.",
            extraLines: sendPreviewStore.xrpSendPreview.map { p in
                [p.sequence > 0 ? "Sequence: \(p.sequence)" : nil, p.lastLedgerSequence > 0 ? "Last Ledger Sequence: \(p.lastLedgerSequence)" : nil].compactMap { $0 }
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Solana",
            isPreparing: store.preparingChains.contains("Solana"),
            fee: sendPreviewStore.solanaSendPreview.map { ($0.estimatedNetworkFeeSol, "SOL", "%.6f") },
            footer: "Spectra signs and broadcasts Solana transfers in-app, including SOL and supported SPL assets.",
            extraCaption: selectedCoin?.symbol != "SOL" ? "Token transfers on Solana still use SOL for network fees." : nil)
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Cardano",
            isPreparing: store.preparingChains.contains("Cardano"),
            fee: sendPreviewStore.cardanoSendPreview.map { ($0.estimatedNetworkFeeAda, "ADA", "%.6f") },
            footer: "Spectra signs and broadcasts ADA transfers in-app.",
            extraLines: sendPreviewStore.cardanoSendPreview.map { p in
                p.ttlSlot > 0 ? [AppLocalization.format("TTL Slot: %lld", p.ttlSlot)] : []
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Monero",
            isPreparing: store.preparingChains.contains("Monero"),
            fee: sendPreviewStore.moneroSendPreview.map { ($0.estimatedNetworkFeeXmr, "XMR", "%.6f") },
            footer: "Spectra prepares Monero sends in-app using the configured backend fee quote.",
            extraLines: sendPreviewStore.moneroSendPreview.map { [AppLocalization.format("Priority: %@", $0.priorityLabel)] } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "NEAR",
            isPreparing: store.preparingChains.contains("NEAR"),
            fee: sendPreviewStore.nearSendPreview.map { ($0.estimatedNetworkFeeNear, "NEAR", "%.6f") },
            footer: "Spectra signs and broadcasts NEAR transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Polkadot",
            isPreparing: store.preparingChains.contains("Polkadot"),
            fee: sendPreviewStore.polkadotSendPreview.map { ($0.estimatedNetworkFeeDot, "DOT", "%.6f") },
            footer: "Spectra signs and broadcasts Polkadot transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Stellar",
            isPreparing: store.preparingChains.contains("Stellar"),
            fee: sendPreviewStore.stellarSendPreview.map { ($0.estimatedNetworkFeeXlm, "XLM", "%.7f") },
            footer: "Spectra signs and broadcasts Stellar payments in-app.",
            extraLines: sendPreviewStore.stellarSendPreview.map { p in
                p.sequence > 0 ? [AppLocalization.format("Sequence: %lld", p.sequence)] : []
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Internet Computer",
            isPreparing: store.preparingChains.contains("Internet Computer"),
            fee: sendPreviewStore.icpSendPreview.map { ($0.estimatedNetworkFeeIcp, "ICP", "%.8f") },
            footer: "Spectra signs and broadcasts ICP transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Sui",
            isPreparing: store.preparingChains.contains("Sui"),
            fee: sendPreviewStore.suiSendPreview.map { ($0.estimatedNetworkFeeSui, "SUI", "%.6f") },
            footer: "Spectra signs and broadcasts Sui transfers in-app.",
            extraLines: sendPreviewStore.suiSendPreview.map {
                [
                    AppLocalization.format("Gas Budget: %llu MIST", $0.gasBudgetMist),
                    AppLocalization.format("Reference Gas Price: %llu", $0.referenceGasPrice),
                ]
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Aptos",
            isPreparing: store.preparingChains.contains("Aptos"),
            fee: sendPreviewStore.aptosSendPreview.map { ($0.estimatedNetworkFeeApt, "APT", "%.6f") },
            footer: "Spectra signs and broadcasts Aptos transfers in-app.",
            extraLines: sendPreviewStore.aptosSendPreview.map {
                [
                    AppLocalization.format("Max Gas Amount: %llu", $0.maxGasAmount),
                    AppLocalization.format("Gas Unit Price: %llu octas", $0.gasUnitPriceOctas),
                ]
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "TON",
            isPreparing: store.preparingChains.contains("TON"),
            fee: sendPreviewStore.tonSendPreview.map { ($0.estimatedNetworkFeeTon, "TON", "%.6f") },
            footer: "Spectra signs and broadcasts TON transfers in-app.",
            extraLines: sendPreviewStore.tonSendPreview.map { [AppLocalization.format("Sequence Number: %u", $0.sequenceNumber)] } ?? [])
        if let selectedCoin { sendPreviewDetailsContent(for: selectedCoin) }
    }

    // MARK: — Network sub-sections

    @ViewBuilder
    private func networkSectionHeader(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func utxoNetworkContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader("Advanced UTXO Mode")
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
                    Text(AppLocalization.string(
                        isMwebSend
                            ? "MWEB peg-in: coins enter the MimbleWimble sidechain. Fee covers both the on-chain peg-in output and the ~1 kB MWEB extension block. Change strategy is ignored for MWEB sends."
                            : "For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address."
                    )).font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle(AppLocalization.string("RBF Intent"), isOn: $store.sendEnableRBF)
                    Toggle(AppLocalization.string("CPFP Intent"), isOn: $store.sendEnableCPFP)
                    if let caption = utxoAdvancedModeCaption(for: selectedCoin.chainName) {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Divider().opacity(0.3).padding(.vertical, 8)
    }

    @ViewBuilder
    private func feePriorityContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader("Fee Priority")
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Divider().opacity(0.3).padding(.vertical, 8)
    }

    @ViewBuilder
    private func utxoFeePreviewContent(selectedCoin: Coin) -> some View {
        let feeSymbol = selectedCoin.symbol
        let utxoPreview = utxoPreview(for: selectedCoin)
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains."))
                .font(.caption).foregroundStyle(.secondary)
            if selectedCoin.chainID == .dogecoin, store.preparingChains.contains("Dogecoin") {
                HStack(spacing: 10) { ProgressView(); Text(AppLocalization.string("Loading UTXOs and fee estimate...")).font(.caption) }
            } else if selectedCoin.chainID == .dogecoin, let dogecoinSendPreview = sendPreviewStore.dogecoinSendPreview {
                if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDoge, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.6f %@ (~%@)",
                            dogecoinSendPreview.estimatedNetworkFeeDoge, feeSymbol, fiatFee
                        )
                    )
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.6f %@", dogecoinSendPreview.estimatedNetworkFeeDoge, feeSymbol))
                }
                Text(AppLocalization.format("Confirmation Preference: %@", confirmationPreferenceText(for: dogecoinSendPreview.feePriority)))
            } else if let utxoPreview {
                Text(AppLocalization.format("Estimated Fee Rate: %@ sat/vB", "\(utxoPreview.estimatedFeeRateSatVb)"))
                if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBtc, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.8f %@ (~%@)",
                            utxoPreview.estimatedNetworkFeeBtc, feeSymbol, fiatFee
                        )
                    )
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.8f %@", utxoPreview.estimatedNetworkFeeBtc, feeSymbol))
                }
            } else {
                Text(AppLocalization.format("Enter amount to preview estimated %@ network fee.", selectedCoin.chainName))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func evmNetworkContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Toggle(AppLocalization.string("Use Custom Fees"), isOn: $store.useCustomEthereumFees)
            if store.useCustomEthereumFees {
                TextField(AppLocalization.string("Max Fee (gwei)"), text: $store.customEthereumMaxFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: 14)
                TextField(AppLocalization.string("Priority Fee (gwei)"), text: $store.customEthereumPriorityFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: 14)
                if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                    Text(customEthereumFeeValidationError).font(.caption).foregroundStyle(.red)
                } else {
                    Text(AppLocalization.string("Custom EIP-1559 fees are applied to this send and preview."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(AppLocalization.string("Manual Nonce"), isOn: $store.ethereumManualNonceEnabled)
            if store.ethereumManualNonceEnabled {
                TextField(AppLocalization.string("Nonce"), text: $store.ethereumManualNonce)
                    .keyboardType(.numberPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: 14)
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
                        spectraHaptic(.medium)
                        Task { await store.prepareEthereumSpeedUpContext() }
                    }
                    Button(AppLocalization.string("Cancel Pending Transaction")) {
                        spectraHaptic(.medium)
                        Task { await store.prepareEthereumCancelContext() }
                    }
                }
                if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage {
                    Text(ethereumReplacementNonceStateMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.preparingChains.contains("Ethereum") {
                HStack(spacing: 10) { ProgressView(); Text(AppLocalization.string("Loading nonce and fee estimate...")).font(.caption) }
            } else if let ethereumSendPreview = sendPreviewStore.ethereumSendPreview {
                Text(AppLocalization.format("Nonce: %lld", ethereumSendPreview.nonce))
                Text(AppLocalization.format("Gas Limit: %lld", ethereumSendPreview.gasLimit))
                Text(AppLocalization.format("Max Fee: %.2f gwei", ethereumSendPreview.maxFeePerGasGwei))
                Text(AppLocalization.format("Priority Fee: %.2f gwei", ethereumSendPreview.maxPriorityFeePerGasGwei))
                let feeSymbol = evmFeeSymbol(for: selectedCoin.chainName)
                if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeEth, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.6f %@ (~%@)",
                            ethereumSendPreview.estimatedNetworkFeeEth, feeSymbol, fiatFee
                        )
                    )
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.6f %@", ethereumSendPreview.estimatedNetworkFeeEth, feeSymbol))
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Text(AppLocalization.string("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(
                AppLocalization.format(
                    "Spectra signs and broadcasts supported %@ transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.",
                    selectedCoin.chainName
                )
            )
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func simpleFeeContent(
        selectedCoin: Coin?, chainName: String, isPreparing: Bool,
        fee: (amount: Double, symbol: String, specifier: String)?,
        footer: String, extraLines: [String] = [], extraCaption: String? = nil
    ) -> some View {
        if let selectedCoin, selectedCoin.chainName == chainName {
            VStack(alignment: .leading, spacing: 10) {
                networkSectionHeader(AppLocalization.format("%@ Network", chainName))
                if isPreparing {
                    HStack(spacing: 10) { ProgressView(); Text(AppLocalization.format("Loading %@ fee estimate...", chainName)).font(.caption) }
                } else if let fee {
                    let feeFormatted = String(format: fee.specifier, fee.amount)
                    if let fiatFee = store.formattedFiatAmount(fromNative: fee.amount, symbol: fee.symbol) {
                        Text(AppLocalization.format("Estimated Network Fee: %@ %@ (~%@)", feeFormatted, fee.symbol, fiatFee)).font(.subheadline.weight(.semibold))
                    } else {
                        Text(AppLocalization.format("Estimated Network Fee: %@ %@", feeFormatted, fee.symbol)).font(.subheadline.weight(.semibold))
                    }
                    ForEach(extraLines, id: \.self) { Text($0) }
                    if let extraCaption { Text(AppLocalization.string(extraCaption)).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text(AppLocalization.format("Enter an amount to load a %@ fee preview. Add a valid destination address before sending.", chainName))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(AppLocalization.string(footer)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sendPreviewDetailsContent(for selectedCoin: Coin) -> some View {
        if let details = store.sendPreviewDetails(for: selectedCoin), details.hasVisibleContent {
            VStack(alignment: .leading, spacing: 8) {
                networkSectionHeader(AppLocalization.string("Preview Details"))
                if let spendableBalance = details.spendableBalance {
                    Text(AppLocalization.format("Spendable Balance: %@", formattedPreviewAssetAmount(spendableBalance, for: selectedCoin)))
                }
                if let feeRateDescription = details.feeRateDescription { Text(AppLocalization.format("Fee Rate: %@", feeRateDescription)) }
                if let estimatedTransactionBytes = details.estimatedTransactionBytes {
                    Text(AppLocalization.format("Estimated Size: %lld bytes", estimatedTransactionBytes))
                }
                if let selectedInputCount = details.selectedInputCount { Text(AppLocalization.format("Selected Inputs: %lld", selectedInputCount)) }
                if let usesChangeOutput = details.usesChangeOutput {
                    Text(AppLocalization.format("Change Output: %@", usesChangeOutput ? AppLocalization.string("Yes") : AppLocalization.string("No")))
                }
                if let maxSendable = details.maxSendable {
                    Text(AppLocalization.format("Max Sendable: %@", formattedPreviewAssetAmount(maxSendable, for: selectedCoin)))
                }
            }
        }
    }

    // MARK: — Status cards

    @ViewBuilder
    private var sendStatusCards: some View {
        if let sendError = store.sendError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(sendError).font(.subheadline).foregroundStyle(.red)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.red.opacity(0.06)), in: .rect(cornerRadius: 20))
        }

        if let sendVerificationNotice = store.sendVerificationNotice {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(store.sendVerificationNoticeIsWarning ? .red : .orange)
                Text(sendVerificationNotice).font(.subheadline)
                    .foregroundStyle(store.sendVerificationNoticeIsWarning ? .red : .orange)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: 20))
        }

        if let lastSentTransaction = store.lastSentTransaction {
            lastSentCard(lastSentTransaction)
        }

        if let chainName = store.sendingChains.first {
            HStack(spacing: 10) {
                ProgressView()
                Text(AppLocalization.format("Broadcasting %@ transaction...", chainName)).font(.caption)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private func lastSentCard(_ tx: TransactionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Last Sent")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                TransactionStatusBadge(status: tx.status)
            }
            Text(AppLocalization.format("%@ sent to %@", tx.symbol, tx.addressPreviewText)).font(.subheadline)
            if let pendingText = store.pendingTransactionRefreshStatusText {
                Text(pendingText).font(.caption2).foregroundStyle(.secondary)
            }
            if let transactionHash = tx.transactionHash {
                Text(transactionHash).font(.caption2.monospaced()).textSelection(.enabled)
            }
            if let explorerURL = tx.transactionExplorerURL, let explorerLabel = tx.transactionExplorerLabel {
                Link(destination: explorerURL) {
                    Label(explorerLabel, systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }.buttonStyle(.glassProminent)
            }
            Button {
                spectraHaptic(.light)
                store.saveLastSentRecipientToAddressBook()
            } label: {
                Label(
                    store.canSaveLastSentRecipientToAddressBook()
                        ? AppLocalization.string("Save Recipient To Address Book")
                        : AppLocalization.string("Recipient Already Saved"),
                    systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .disabled(!store.canSaveLastSentRecipientToAddressBook())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 24))
    }

    // MARK: — Helpers

    private func chainFeePriorityBinding(for chainName: String) -> Binding<ChainFeePriorityOption> {
        Binding(get: { store.feePriorityOption(for: chainName) }, set: { store.setFeePriorityOption($0, for: chainName) })
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
        default: return nil
        }
    }

    private func evmFeeSymbol(for chainName: String) -> String {
        AppEndpointDirectory.appChain(for: chainName)?.nativeSymbol ?? "ETH"
    }

    private func formattedPreviewAssetAmount(_ amount: Double, for coin: Coin) -> String {
        store.formattedAssetAmount(amount, symbol: coin.symbol, chainName: coin.chainName)
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
                if AppEndpointDirectory.appChain(for: chainName)?.isEVM == true { return normalizeEVMAddress(candidate) }
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
