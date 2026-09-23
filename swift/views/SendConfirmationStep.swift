import SwiftUI

/// The pre-build review form and transient send status cards.
///
/// Like `SendNetworkStep`, split out of `SendView`: none of this reads the
/// flow's own state — the current step, the scanner, the address-book
/// selection — so it had no reason to re-evaluate whenever that state moved.
struct SendConfirmationStep: View {
    @Bindable var store: AppState

    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }
    private var isSendBusy: Bool { store.isSending || !store.preparingChains.isEmpty }
    private var selectedCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletId).first(where: { $0.holdingKey == store.sendHoldingKey })
    }

    var body: some View {
        confirmStep(selectedCoin: selectedCoin)
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
                        artworkName: selectedCoin.artworkName,
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
        return store.formattedFiatAmount(amount, of: selectedCoin)
    }

    private var recipientPreviewText: String {
        let trimmed = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AppLocalization.string("No recipient") }
        return trimmed
    }

    private func estimatedNetworkFeeText(for coin: Coin?) -> String? {
        guard let coin,
            let chain = Chain(displayName: coin.chainName),
            let fee = sendPreviewStore.estimatedFee(forChainNamed: coin.chainName)
        else { return nil }
        return store.formattedNetworkFee(fee, chain: chain)
    }
}

/// Transient errors and core-derived confirmation notices.
struct SendStatusCards: View {
    let store: AppState

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


    }

}

/// History details and recipient actions for the displayed durable artifact.
struct SendTransactionCard: View {
    let store: AppState
    let tx: TransactionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Transaction")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                TransactionStatusBadge(status: tx.status)
            }
            Text(AppLocalization.format("%@ sent to %@", tx.symbol, tx.address)).font(.subheadline)
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
                store.saveStagedRecipientToAddressBook()
            } label: {
                Label(
                    store.canSaveStagedRecipientToAddressBook()
                        ? AppLocalization.string("Save Recipient To Address Book")
                        : AppLocalization.string("Recipient Already Saved"),
                    systemImage: store.canSaveStagedRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .disabled(!store.canSaveStagedRecipientToAddressBook())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.card)
    }
}
