import SwiftUI

/// The send flow's confirmation and result pages, plus the status cards that
/// report what the last send did.
///
/// Like `SendNetworkStep`, split out of `SendView`: none of this reads the
/// flow's own state — the current step, the scanner, the address-book
/// selection — so it had no reason to re-evaluate whenever that state moved.
struct SendConfirmationStep: View {
    @Bindable var store: AppState
    /// `true` renders the post-send result page instead of the confirmation.
    let showsResult: Bool

    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }
    private var isSendBusy: Bool { !store.sendingChains.isEmpty || !store.preparingChains.isEmpty }
    private var selectedCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }

    var body: some View {
        if showsResult {
            resultStep
        } else {
            confirmStep(selectedCoin: selectedCoin)
        }
    }

    private func confirmStep(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Review",
                subtitle: "Confirm the transaction details before broadcasting.",
                systemImage: "checkmark.shield.fill"
            )

            confirmationCard(selectedCoin: selectedCoin)
            DisclosureGroup(AppLocalization.string("Fee and advanced settings")) {
                SendNetworkStep(store: store)
                    .padding(.top, 12)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private func confirmationCard(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let selectedCoin {
                    CoinBadge(
                        assetIdentifier: selectedCoin.iconIdentifier,
                        fallbackText: selectedCoin.symbol,
                        color: selectedCoin.color,
                        size: 44
                    )
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(confirmAmountText(selectedCoin: selectedCoin))
                        .font(.title2.weight(.bold))
                        .spectraNumericTextLayout()
                    Text(recipientPreviewText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Divider().opacity(0.35)

            VStack(spacing: 12) {
                confirmationRow(label: "Wallet", value: store.selectedWalletForSend()?.name ?? AppLocalization.string("Not selected"), icon: "wallet.pass.fill")
                confirmationRow(label: "Asset", value: selectedCoin.map { "\($0.symbol) · \($0.chainName)" } ?? AppLocalization.string("Not selected"), icon: "circle.hexagongrid.fill")
                confirmationRow(label: "Network Fee", value: estimatedNetworkFeeText(for: selectedCoin) ?? AppLocalization.string("Refreshing preview"), icon: "speedometer")
                if let fiatText = confirmFiatAmountText(selectedCoin: selectedCoin) {
                    confirmationRow(label: "Approx. Value", value: fiatText, icon: "dollarsign.circle.fill")
                }
            }

            if store.isCheckingSendDestinationBalance || isSendBusy {
                SpectraLoadingRow(
                    title: isSendBusy ? "Preparing transaction..." : "Checking recipient...",
                    subtitle: isSendBusy ? "Keep this screen open while Spectra prepares the transfer." : nil
                )
            }

            if let warning = store.sendDestinationRiskWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Sent",
                subtitle: "The transaction has been queued for network confirmation.",
                systemImage: "checkmark.circle.fill"
            )

            if let lastSentTransaction = store.lastSentTransaction {
                SendLastSentCard(store: store, tx: lastSentTransaction)
            } else if let chainName = store.sendingChains.first {
                SpectraLoadingCard(
                    title: AppLocalization.format("Broadcasting %@ transaction...", chainName),
                    subtitle: "Waiting for the network to accept the signed transaction.",
                    lineCount: 2
                )
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
                .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: SpectraLayout.Radius.compact))
            }
        }
    }

    private func confirmationRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string(label)).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func confirmAmountText(selectedCoin: Coin?) -> String {
        let symbol = selectedCoin?.symbol ?? ""
        let amount = store.sendAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amount.isEmpty else { return AppLocalization.string("No amount") }
        return symbol.isEmpty ? amount : "\(amount) \(symbol)"
    }

    private func confirmFiatAmountText(selectedCoin: Coin?) -> String? {
        guard let selectedCoin, let amount = Double(store.sendAmount), amount > 0 else { return nil }
        return store.formattedFiatAmount(fromNative: amount, symbol: selectedCoin.symbol)
    }

    private var recipientPreviewText: String {
        let trimmed = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AppLocalization.string("No recipient") }
        return trimmed
    }

    private func estimatedNetworkFeeText(for coin: Coin?) -> String? {
        // The fee's symbol and precision are registry columns —
        // `gasTokenSymbol` and `sendExecutionShape.feeDecimals` — and
        // `estimatedFee(forChainNamed:)` already keys the preview by chain.
        // `utxo_and_e8s_chains_use_eight` pins the precision side.
        guard let coin,
            let chain = Chain(displayName: coin.chainName),
            let fee = sendPreviewStore.estimatedFee(forChainNamed: coin.chainName)
        else { return nil }
        let decimals = Int(chain.sendExecutionShape?.feeDecimals ?? 6)
        return String(format: "%.\(decimals)f %@", fee, chain.gasTokenSymbol)
    }
}


/// The cards under the send flow that report what the last send is doing.
/// Shown on every step except the result page, which says it in full itself.
struct SendStatusCards: View {
    let store: AppState

    private var isSendBusy: Bool { !store.sendingChains.isEmpty || !store.preparingChains.isEmpty }

    var body: some View {
        sendStatusCards
    }

    @ViewBuilder
    private var sendStatusCards: some View {
        if let sendError = store.sendError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(sendError).font(.subheadline).foregroundStyle(.red)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.red.opacity(0.06)), in: .rect(cornerRadius: SpectraLayout.Radius.compact))
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
            .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: SpectraLayout.Radius.compact))
        }

        if let lastSentTransaction = store.lastSentTransaction {
            SendLastSentCard(store: store, tx: lastSentTransaction)
        }

        if let chainName = store.sendingChains.first {
            SpectraLoadingCard(
                title: AppLocalization.format("Broadcasting %@ transaction...", chainName),
                subtitle: "Submitting the signed transaction.",
                lineCount: 2
            )
        }
    }

}

/// The "last sent" summary, shown both under the flow and on the result page.
struct SendLastSentCard: View {
    let store: AppState
    let tx: TransactionRecord

    var body: some View {
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
                    .spectraPressable()
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
            .spectraPressable()
            .disabled(!store.canSaveLastSentRecipientToAddressBook())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.card)
    }
}
