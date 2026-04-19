import Foundation
import SwiftUI
import UIKit
struct HistoryDetailView: View {
    @ObservedObject var store: AppState
    let transaction: TransactionRecord
    @State private var didCopyAddress = false
    @State private var ethereumReplacementMessage: String?
    @State private var liveTransaction: TransactionRecord?
    @State private var liveOwnedAddresses: Set<String> = []
    init(store: AppState, transaction: TransactionRecord) {
        self.store = store
        self.transaction = transaction
    }
    private var displayedTransaction: TransactionRecord { liveTransaction ?? transaction }
    private var ownedAddresses: Set<String> { liveOwnedAddresses }
    private var fromAddressText: String? {
        if displayedTransaction.kind == .send {
            return nonEmptyAddress(displayedTransaction.sourceAddress)
                ?? firstOwnedAddress
        }
        let counterparty = nonEmptyAddress(displayedTransaction.addressPreviewText)
        if normalizedAddress(counterparty) != normalizedAddress(walletSideAddress) { return counterparty }
        return nil
    }
    private var toAddressText: String? {
        if displayedTransaction.kind == .send {
            let counterparty = nonEmptyAddress(displayedTransaction.addressPreviewText)
            if normalizedAddress(counterparty) != normalizedAddress(fromAddressText) { return counterparty }
            return nil
        }
        return walletSideAddress
            ?? firstOwnedAddress
    }
    private var walletSideAddress: String? {
        if let sourceAddress = nonEmptyAddress(displayedTransaction.sourceAddress), isOwnedAddress(sourceAddress) { return sourceAddress }
        if let previewAddress = nonEmptyAddress(displayedTransaction.addressPreviewText), isOwnedAddress(previewAddress) { return previewAddress }
        return nil
    }
    private var firstOwnedAddress: String? {
        guard let walletID = displayedTransaction.walletID else { return nil }
        return store.knownOwnedAddresses(for: walletID).first
    }
    private func localized(_ key: String) -> String { AppLocalization.string(key) }
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            CoinBadge(assetIdentifier: displayedTransaction.assetIdentifier, fallbackText: displayedTransaction.symbol, color: displayedTransaction.badgeColor, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayedTransaction.titleText).font(.title3.bold()).foregroundStyle(Color.primary)
                                Text(
                                    String(
                                        format: CommonLocalizationContent.current.transactionSubtitleFormat, displayedTransaction.assetName, store.displayChainTitle(for: displayedTransaction), displayedTransaction.walletName
                                    )
                                ).font(.subheadline).foregroundStyle(Color.primary.opacity(0.74))
                            }
                            Spacer()
                            statusChip
                        }
                        if let amountText = store.formattedTransactionDetailAmount(displayedTransaction) { Text(amountText).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Color.primary).spectraNumericTextLayout(minimumScaleFactor: 0.5) }}.padding(20).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 28))
                    detailCard(title: "Overview") {
                        detailRow(label: "Type", value: displayedTransaction.kind == .send ? localized("Send") : localized("Receive"))
                        detailRow(label: "Status", value: displayedTransaction.statusText)
                        detailRow(label: "Wallet", value: displayedTransaction.walletName)
                        detailRow(label: "Asset", value: displayedTransaction.assetName)
                        detailRow(label: "Network", value: store.displayChainTitle(for: displayedTransaction))
                        detailRow(label: "Timestamp", value: displayedTransaction.fullTimestampText)
                        if let amountText = store.formattedTransactionDetailAmount(displayedTransaction) { detailRow(label: "Amount", value: amountText) }
                        if let historySourceText = displayedTransaction.historySourceText { detailRow(label: "History Source", value: historySourceText) }
                        if let receiptBlockNumberText = displayedTransaction.receiptBlockNumberText { detailRow(label: "Block", value: receiptBlockNumberText) }
                        if let confirmationCountText = displayedTransaction.storedConfirmationCountText { detailRow(label: "Confirmations", value: confirmationCountText) }
                        if let receiptGasUsed = displayedTransaction.receiptGasUsed { detailRow(label: "Gas Used", value: receiptGasUsed) }
                        if let receiptEffectiveGasPriceText = displayedTransaction.receiptEffectiveGasPriceText { detailRow(label: "Effective Gas Price", value: receiptEffectiveGasPriceText) }
                        if let receiptNetworkFeeText = displayedTransaction.receiptNetworkFeeText { detailRow(label: "Network Fee", value: receiptNetworkFeeText) }
                        if let storedFeePriorityText = displayedTransaction.storedFeePriorityText { detailRow(label: "Fee Priority", value: storedFeePriorityText) }
                        if let dogecoinConfirmedNetworkFeeDoge = displayedTransaction.dogecoinConfirmedNetworkFeeDoge { detailRow(label: "Confirmed Fee", value: String(format: "%.6f DOGE", dogecoinConfirmedNetworkFeeDoge)) }
                        if let storedFeeRateText = displayedTransaction.storedFeeRateText { detailRow(label: "Fee Rate", value: storedFeeRateText) }
                        if let storedUsedChangeOutputText = displayedTransaction.storedUsedChangeOutputText { detailRow(label: "Used Change Output", value: storedUsedChangeOutputText) }
                        if let rawTransactionFormatText = displayedTransaction.rawTransactionFormatText { detailRow(label: "Signed Payload Format", value: rawTransactionFormatText) }
                        if let sourceDerivationPath = displayedTransaction.sourceDerivationPath { detailRow(label: "Source Path", value: sourceDerivationPath) }
                        if let changeDerivationPath = displayedTransaction.changeDerivationPath { detailRow(label: "Change Path", value: changeDerivationPath) }
                        if let sourceAddress = displayedTransaction.sourceAddress { detailRow(label: "Source Address", value: sourceAddress) }
                        if let changeAddress = displayedTransaction.changeAddress { detailRow(label: "Change Address", value: changeAddress) }
                        if let failureReason = displayedTransaction.failureReason { detailRow(label: "Failure", value: failureReason) }}
                    if displayedTransaction.chainName == "Ethereum", displayedTransaction.kind == .send, displayedTransaction.status == .pending {
                        detailCard(title: "Ethereum Mempool Actions") {
                            if store.isPreparingEthereumReplacementContext {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(localized("Preparing replacement/cancel context...")).font(.caption).foregroundStyle(Color.primary.opacity(0.78))
                                }
                            } else {
                                Button {
                                    Task {
                                        ethereumReplacementMessage = await store.openEthereumReplacementComposer(
                                            for: displayedTransaction.id, cancel: false
                                        )
                                    }} label: {
                                    Text(localized("Speed Up This Transaction")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                                }.buttonStyle(.glassProminent)
                                Button {
                                    Task {
                                        ethereumReplacementMessage = await store.openEthereumReplacementComposer(
                                            for: displayedTransaction.id, cancel: true
                                        )
                                    }} label: {
                                    Text(localized("Cancel This Transaction")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                                }.buttonStyle(.glass)
                                Text(localized("This opens the Send composer with the same nonce and higher fee defaults so you can safely speed up or cancel the pending transaction.")).font(.caption).foregroundStyle(Color.primary.opacity(0.72))
                            }
                            if let ethereumReplacementMessage { Text(ethereumReplacementMessage).font(.caption).foregroundStyle(Color.primary.opacity(0.72)) }}}
                    detailCard(title: "Addresses") {
                        if let fromAddressText { addressBlock(label: "From", value: fromAddressText, isMine: isOwnedAddress(fromAddressText)) }
                        if let toAddressText { addressBlock(label: "To", value: toAddressText, isMine: isOwnedAddress(toAddressText)) }}
                    if let transactionHash = displayedTransaction.transactionHash {
                        detailCard(title: "Transaction Hash") {
                            Text(transactionHash).font(.body.monospaced()).foregroundStyle(Color.primary.opacity(0.82)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            if let transactionExplorerURL = displayedTransaction.transactionExplorerURL, let transactionExplorerLabel = displayedTransaction.transactionExplorerLabel {
                                Link(destination: transactionExplorerURL) {
                                    Label(transactionExplorerLabel, systemImage: "safari").font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                                }.buttonStyle(.glassProminent).frame(maxWidth: .infinity, alignment: .leading)
                            }}}
                    if let rawTransactionHexText = displayedTransaction.rawTransactionHexText {
                        detailCard(title: "Raw Transaction Hex") {
                            Text(rawTransactionHexText).font(.body.monospaced()).foregroundStyle(Color.primary.opacity(0.82)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }}}.padding(20)
            }}.navigationTitle(localized("Transaction")).navigationBarTitleDisplayMode(.inline).onAppear {
            rebuildDisplayedTransactionState()
        }.onChange(of: store.transactionRevision) { _, _ in
            rebuildDisplayedTransactionState()
        }.onChange(of: store.walletsRevision) { _, _ in
            rebuildDisplayedTransactionState()
        }}
    private var statusChip: some View {
        Text(displayedTransaction.statusText).font(.caption.bold()).foregroundStyle(Color.primary).padding(.horizontal, 10).padding(.vertical, 6).background(displayedTransaction.statusColor.opacity(0.32), in: Capsule()).overlay(
                Capsule().stroke(displayedTransaction.statusColor.opacity(0.45), lineWidth: 1)
            )
    }
    @ViewBuilder
    private func detailCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(title)).font(.headline.weight(.semibold)).foregroundStyle(Color.primary)
            content()
        }.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(localized(label)).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.58)).frame(width: 122, alignment: .leading)
            Text(value).font(.body).foregroundStyle(Color.primary.opacity(0.84)).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2)
    }
    @ViewBuilder
    private func addressBlock(label: String, value: String, isMine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(localized(label)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                if isMine {
                    Text(localized("Mine")).font(.caption.bold()).foregroundStyle(Color.primary).padding(.horizontal, 8).padding(.vertical, 4).background(Color.mint.opacity(0.22), in: Capsule()).overlay(
                            Capsule().stroke(Color.mint.opacity(0.35), lineWidth: 1)
                        )
                }}
            Text(value).font(.body.monospaced()).foregroundStyle(Color.primary.opacity(0.82)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                UIPasteboard.general.string = value
                didCopyAddress = true
            } label: {
                Label(
                    didCopyAddress
                        ? localized("Copied")
                        : localized("Copy Address"), systemImage: didCopyAddress ? "checkmark" : "doc.on.doc"
                ).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            }.buttonStyle(.glass).frame(maxWidth: .infinity, alignment: .leading)
        }}
    private func nonEmptyAddress(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
    private func normalizedAddress(_ value: String?) -> String? {
        guard let trimmed = nonEmptyAddress(value) else { return nil }
        switch displayedTransaction.chainName {
        case "Ethereum", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return trimmed.lowercased()
        default: return trimmed
        }}
    private func isOwnedAddress(_ value: String?) -> Bool {
        guard let normalized = normalizedAddress(value) else { return false }
        return ownedAddresses.contains(normalized)
    }
    private func rebuildDisplayedTransactionState() {
        let resolvedTransaction = store.transactions.first(where: { $0.id == transaction.id }) ?? transaction
        liveTransaction = resolvedTransaction
        guard let walletID = resolvedTransaction.walletID else {
            liveOwnedAddresses = []
            return
        }
        liveOwnedAddresses = Set(store.knownOwnedAddresses(for: walletID).compactMap { normalizedAddress($0) })
    }
}
