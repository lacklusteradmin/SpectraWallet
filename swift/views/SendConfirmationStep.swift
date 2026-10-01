import SwiftUI

/// The pre-build review form and transient send status cards.
///
/// Like `SendNetworkStep`, split out of `SendView`: none of this reads the
/// flow's own state — the current step, the scanner, the address-book
/// selection — so it had no reason to re-evaluate whenever that state moved.
struct SendConfirmationStep: View {
    @Bindable var store: AppState

    private var isSendBusy: Bool { store.sendFlow.session.isBusy || store.sendFlow.isPreparingPreview }
    private var selectedCoin: Coin? {
        store.availableSendCoins(for: store.sendFlow.walletId).first(where: { $0.holdingKey == store.sendFlow.holdingKey })
    }

    var body: some View {
        confirmStep(selectedCoin: selectedCoin)
    }

    private func confirmStep(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            confirmationCard(selectedCoin: selectedCoin)
            DisclosureGroup(AppLocalization.string("Fee and advanced settings")) {
                SendNetworkStep(store: store)
                    .padding(.top, SpectraLayout.Space.s)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, SpectraLayout.Space.xs)
        }
    }

    private func confirmationCard(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack(spacing: SpectraLayout.Space.m) {
                if let selectedCoin {
                    CoinBadge(
                        artworkName: selectedCoin.artworkName,
                        fallbackText: selectedCoin.symbol,
                        color: selectedCoin.color,
                        size: 44
                    )
                }
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(confirmAmountText(selectedCoin: selectedCoin))
                        .font(.title2.weight(.bold))
                        .spectraNumericTextLayout()
                    Text("≈ \(store.amounts.formattedFiat(confirmedQuote?.amountValue))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .spectraNumericTextLayout()
                }
            }

            Divider().opacity(0.35)

            if recipientAddress.isEmpty {
                confirmationRow(label: "To", value: AppLocalization.string("No recipient"))
            } else {
                ReviewAddressBlock(
                    store: store, label: "To", walletId: store.sendFlow.walletId,
                    chain: selectedCoin?.chainId, address: recipientAddress)
            }

            Divider().opacity(0.35)

            VStack(spacing: SpectraLayout.Space.s) {
                confirmationRow(label: "From", value: store.selectedWalletForSend()?.name ?? AppLocalization.string("Not selected"))
                confirmationRow(label: "Network", value: selectedCoin?.chainName ?? AppLocalization.string("Not selected"))
                confirmationRow(label: "Network Fee", value: networkFeeText ?? AppLocalization.string("Estimating…"))
            }

            if store.sendFlow.isCheckingDestination || isSendBusy {
                SpectraLoadingRow(
                    title: isSendBusy ? "Preparing transaction..." : "Checking recipient...",
                    subtitle: isSendBusy ? "Keep this screen open while Spectra prepares the transfer." : nil
                )
            }

            if let warning = store.sendFlow.destinationRiskWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.spectraWarning)
            }
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }

    private func confirmationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SpectraLayout.Space.m) {
            Text(AppLocalization.string(label)).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: SpectraLayout.Space.s)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .spectraNumericTextLayout(minimumScaleFactor: 0.8)
        }
    }

    private func confirmAmountText(selectedCoin: Coin?) -> String {
        let symbol = selectedCoin?.symbol ?? ""
        let amount = store.sendFlow.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amount.isEmpty else { return AppLocalization.string("No amount") }
        let localized = AmountPresentation.localizedDecimal(amount)
        return symbol.isEmpty ? localized : "\(localized) \(symbol)"
    }

    private var confirmedQuote: OwnedSendPreview? { store.sendQuoteForEnteredAmount }

    private var recipientAddress: String {
        store.sendFlow.address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var networkFeeText: String? {
        guard let quote = confirmedQuote, let fee = quote.networkFee else { return nil }
        let chain = quote.chainId
        return store.amounts.compactNetworkFee(fee, value: quote.networkFeeValue, chain: chain)
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
        if let sendError = store.sendFlow.session.error {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(sendError).font(.subheadline).foregroundStyle(.red)
            }
            .padding(SpectraLayout.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.red.opacity(0.06)), in: .rect(cornerRadius: SpectraLayout.Radius.card))
        }

        if let sendVerificationNotice = store.sendFlow.verificationNotice {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(store.sendFlow.verificationNoticeIsWarning ? .red : .spectraWarning)
                Text(sendVerificationNotice).font(.subheadline)
                    .foregroundStyle(store.sendFlow.verificationNoticeIsWarning ? .red : .spectraWarning)
            }
            .padding(SpectraLayout.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.spectraWarning.opacity(0.06)), in: .rect(cornerRadius: SpectraLayout.Radius.card))
        }


    }

}

/// History details and recipient actions for the displayed durable artifact.
struct SendTransactionCard: View {
    let store: AppState
    let tx: TransactionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
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
            if let explorer = tx.explorerLink {
                Link(destination: explorer.url) {
                    Label(explorer.label, systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpectraLayout.Space.s)
                }.buttonStyle(.glassProminent)
            }
            Button {
                spectraHaptic(.light)
                store.saveRecipientToAddressBook(tx)
            } label: {
                Label(
                    store.canSaveRecipientToAddressBook(tx)
                        ? AppLocalization.string("Save Recipient To Address Book")
                        : AppLocalization.string("Recipient Already Saved"),
                    systemImage: store.canSaveRecipientToAddressBook(tx) ? "book.closed" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpectraLayout.Space.s)
            }
            .buttonStyle(.glass)
            .disabled(!store.canSaveRecipientToAddressBook(tx))
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }
}
