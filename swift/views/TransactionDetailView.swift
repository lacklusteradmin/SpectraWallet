import Foundation
import SwiftUI
import UIKit
struct HistoryDetailView: View {
    let store: AppState
    let transaction: TransactionRecord
    @State private var didCopyAddress = false
    @State private var ethereumReplacementMessage: String?
    @State private var liveTransaction: TransactionRecord?
    @State private var liveOwnedAddresses: Set<String> = []
    /// Core answers the owned-address question asynchronously, so the view
    /// caches the one value its body needs. View state: losing it on restart
    /// costs a redraw and nothing else.
    @State private var liveFirstOwnedAddress: String?
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
        if let previewAddress = nonEmptyAddress(displayedTransaction.addressPreviewText), isOwnedAddress(previewAddress) {
            return previewAddress
        }
        return nil
    }
    private var firstOwnedAddress: String? { liveFirstOwnedAddress }
    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            CoinBadge(
                                assetIdentifier: displayedTransaction.assetIdentifier, fallbackText: displayedTransaction.symbol,
                                color: displayedTransaction.badgeColor, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayedTransaction.titleText).font(.title3.bold()).foregroundStyle(Color.primary)
                                Text(
                                    String(
                                        format: CommonLocalizationContent.current.transactionSubtitleFormat, displayedTransaction.assetName,
                                        store.displayChainTitle(for: displayedTransaction), displayedTransaction.walletName
                                    )
                                ).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            statusChip
                        }
                        if let amountText = store.formattedTransactionDetailAmount(displayedTransaction) {
                            Text(amountText).font(.title.weight(.bold)).foregroundStyle(Color.primary)
                                .spectraNumericTextLayout(minimumScaleFactor: 0.5)
                        }
                    }.padding(20).spectraBubbleFill().spectraCardFill(cornerRadius: 28)
                    transactionTimelineCard
                    spectraDetailCard(title: "Overview") {
                        detailRow(label: "Type", value: displayedTransaction.kind == .send ? AppLocalization.string("Send") : AppLocalization.string("Receive"))
                        detailRow(label: "Status", value: displayedTransaction.statusText)
                        detailRow(label: "Wallet", value: displayedTransaction.walletName)
                        detailRow(label: "Asset", value: displayedTransaction.assetName)
                        detailRow(label: "Network", value: store.displayChainTitle(for: displayedTransaction))
                        detailRow(label: "Timestamp", value: displayedTransaction.fullTimestampText)
                        if let amountText = store.formattedTransactionDetailAmount(displayedTransaction) {
                            detailRow(label: "Amount", value: amountText)
                        }
                        if let historySourceText = displayedTransaction.historySourceText {
                            detailRow(label: "History Source", value: historySourceText)
                        }
                        if let receiptBlockNumberText = displayedTransaction.receiptBlockNumberText {
                            detailRow(label: "Block", value: receiptBlockNumberText)
                        }
                        if let confirmationCountText = displayedTransaction.storedConfirmationCountText {
                            detailRow(label: "Confirmations", value: confirmationCountText)
                        }
                        if let receiptGasUsed = displayedTransaction.receiptGasUsed { detailRow(label: "Gas Used", value: receiptGasUsed) }
                        if let receiptEffectiveGasPriceText = displayedTransaction.receiptEffectiveGasPriceText {
                            detailRow(label: "Effective Gas Price", value: receiptEffectiveGasPriceText)
                        }
                        if let receiptNetworkFeeText = displayedTransaction.receiptNetworkFeeText {
                            detailRow(label: "Network Fee", value: receiptNetworkFeeText)
                        }
                        if let storedFeePriorityText = displayedTransaction.storedFeePriorityText {
                            detailRow(label: "Fee Priority", value: storedFeePriorityText)
                        }
                        if let dogecoinConfirmedNetworkFeeDoge = displayedTransaction.dogecoinConfirmedNetworkFeeDoge {
                            detailRow(label: "Confirmed Fee", value: String(format: "%.6f DOGE", dogecoinConfirmedNetworkFeeDoge))
                        }
                        if let storedFeeRateText = displayedTransaction.storedFeeRateText {
                            detailRow(label: "Fee Rate", value: storedFeeRateText)
                        }
                        if let storedUsedChangeOutputText = displayedTransaction.storedUsedChangeOutputText {
                            detailRow(label: "Used Change Output", value: storedUsedChangeOutputText)
                        }
                        if let rawTransactionFormatText = displayedTransaction.rawTransactionFormatText {
                            detailRow(label: "Signed Payload Format", value: rawTransactionFormatText)
                        }
                        if let sourceDerivationPath = displayedTransaction.sourceDerivationPath {
                            detailRow(label: "Source Path", value: sourceDerivationPath)
                        }
                        if let changeDerivationPath = displayedTransaction.changeDerivationPath {
                            detailRow(label: "Change Path", value: changeDerivationPath)
                        }
                        if let sourceAddress = displayedTransaction.sourceAddress {
                            detailRow(label: "Source Address", value: sourceAddress)
                        }
                        if let changeAddress = displayedTransaction.changeAddress {
                            detailRow(label: "Change Address", value: changeAddress)
                        }
                        if let failureReason = displayedTransaction.failureReason { detailRow(label: "Failure", value: failureReason) }
                    }
                    if displayedTransaction.chainName == "Ethereum", displayedTransaction.kind == .send,
                        displayedTransaction.status == .pending
                    {
                        spectraDetailCard(title: "Ethereum Mempool Actions") {
                            if store.isPreparingEthereumReplacementContext {
                                SpectraLoadingRow(title: "Preparing replacement/cancel context...")
                            } else {
                                Button {
                                    Task {
                                        ethereumReplacementMessage = await store.openEthereumReplacementComposer(
                                            for: displayedTransaction.id, cancel: false
                                        )
                                    }
                                } label: {
                                    Text(AppLocalization.string("Speed Up This Transaction")).font(.headline).frame(maxWidth: .infinity).padding(
                                        .vertical, 12)
                                }.buttonStyle(.glassProminent)
                                    .spectraPressable()
                                Button {
                                    Task {
                                        ethereumReplacementMessage = await store.openEthereumReplacementComposer(
                                            for: displayedTransaction.id, cancel: true
                                        )
                                    }
                                } label: {
                                    Text(AppLocalization.string("Cancel This Transaction")).font(.headline).frame(maxWidth: .infinity).padding(
                                        .vertical, 12)
                                }.buttonStyle(.glass)
                                    .spectraPressable()
                                Text(
                                    AppLocalization.string(
                                        "This opens the Send composer with the same nonce and higher fee defaults so you can safely speed up or cancel the pending transaction."
                                    )
                                ).font(.caption).foregroundStyle(.secondary)
                            }
                            if let ethereumReplacementMessage {
                                Text(ethereumReplacementMessage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    spectraDetailCard(title: "Addresses") {
                        if let fromAddressText {
                            addressBlock(label: "From", value: fromAddressText, isMine: isOwnedAddress(fromAddressText))
                        }
                        if let toAddressText { addressBlock(label: "To", value: toAddressText, isMine: isOwnedAddress(toAddressText)) }
                    }
                    if let transactionHash = displayedTransaction.transactionHash {
                        spectraDetailCard(title: "Transaction Hash") {
                            Text(transactionHash).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(
                                .enabled
                            ).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
                            if let transactionExplorerURL = displayedTransaction.transactionExplorerURL,
                                let transactionExplorerLabel = displayedTransaction.transactionExplorerLabel
                            {
                                Link(destination: transactionExplorerURL) {
                                    Label(transactionExplorerLabel, systemImage: "safari").font(.subheadline.weight(.semibold)).padding(
                                        .horizontal, 12
                                    ).padding(.vertical, 8)
                                }.buttonStyle(.glassProminent)
                                    .spectraPressable()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let rawTransactionHexText = displayedTransaction.rawTransactionHexText {
                        spectraDetailCard(title: "Raw Transaction Hex") {
                            Text(rawTransactionHexText).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(
                                .enabled
                            ).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
                        }
                    }
                }.padding(20)
            }
        }.navigationTitle(AppLocalization.string("Transaction")).navigationBarTitleDisplayMode(.inline).task {
            await rebuildDisplayedTransactionState()
        }.onChange(of: store.transactionRevision) { _, _ in
            Task { await rebuildDisplayedTransactionState() }
        }.onChange(of: store.walletsRevision) { _, _ in
            Task { await rebuildDisplayedTransactionState() }
        }
    }
    private var statusChip: some View {
        Text(displayedTransaction.statusText).font(.caption.bold()).foregroundStyle(Color.primary).padding(.horizontal, 10).padding(
            .vertical, 6
        ).background(displayedTransaction.statusColor.opacity(0.32), in: Capsule()).overlay(
            Capsule().stroke(displayedTransaction.statusColor.opacity(0.45), lineWidth: 1)
        )
    }
    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(AppLocalization.string(label)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(
                width: 122, alignment: .leading)
            Text(value).font(.body).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2)
    }
    @ViewBuilder
    private func addressBlock(label: String, value: String, isMine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(AppLocalization.string(label)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                if isMine {
                    Text(AppLocalization.string("Mine")).font(.caption.bold()).foregroundStyle(Color.primary).padding(.horizontal, 8).padding(
                        .vertical, 4
                    ).background(Color.mint.opacity(0.22), in: Capsule()).overlay(
                        Capsule().stroke(Color.mint.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            Text(value).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).padding(14).frame(
                maxWidth: .infinity, alignment: .leading
            ).glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
            Button {
                UIPasteboard.general.string = value
                didCopyAddress = true
            } label: {
                Label(
                    didCopyAddress
                        ? AppLocalization.string("Copied")
                        : AppLocalization.string("Copy Address"), systemImage: didCopyAddress ? "checkmark" : "doc.on.doc"
                ).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            }.buttonStyle(.glass)
                .spectraPressable()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var transactionTimelineCard: some View {
        spectraDetailCard(title: "Timeline") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(transactionTimelineItems.enumerated()), id: \.element.id) { index, item in
                    timelineRow(item, isLast: index == transactionTimelineItems.count - 1)
                }
            }
        }
    }
    private var transactionTimelineItems: [TransactionTimelineItem] {
        var items: [TransactionTimelineItem] = [
            TransactionTimelineItem(
                id: "recorded",
                title: displayedTransaction.kind == .send ? "Created" : "Recorded",
                detail: displayedTransaction.fullTimestampText,
                systemImage: displayedTransaction.kind == .send ? "paperplane.fill" : "arrow.down.circle.fill",
                tint: .orange,
                isComplete: true,
                isCurrent: false
            )
        ]

        if let transactionHash = nonEmptyAddress(displayedTransaction.transactionHash) {
            items.append(
                TransactionTimelineItem(
                    id: "network-hash",
                    title: displayedTransaction.kind == .send ? "Broadcast" : "Detected",
                    detail: AppLocalization.format("Hash %@", shortTransactionHash(transactionHash)),
                    systemImage: "link",
                    tint: .blue,
                    isComplete: true,
                    isCurrent: displayedTransaction.status == .pending
                )
            )
        } else {
            items.append(
                TransactionTimelineItem(
                    id: "network-hash",
                    title: "Awaiting Network Hash",
                    detail: "Spectra has not attached a network transaction hash yet.",
                    systemImage: "hourglass",
                    tint: .orange,
                    isComplete: false,
                    isCurrent: displayedTransaction.status == .pending
                )
            )
        }

        switch displayedTransaction.status {
        case .pending:
            items.append(
                TransactionTimelineItem(
                    id: "pending",
                    title: "Pending Confirmation",
                    detail: "Spectra will keep refreshing this transaction.",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange,
                    isComplete: false,
                    isCurrent: true
                )
            )
        case .confirmed:
            items.append(
                TransactionTimelineItem(
                    id: "confirmed",
                    title: "Confirmed",
                    detail: confirmedTimelineDetail,
                    systemImage: "checkmark.seal.fill",
                    tint: .mint,
                    isComplete: true,
                    isCurrent: true
                )
            )
        case .failed:
            items.append(
                TransactionTimelineItem(
                    id: "failed",
                    title: "Failed",
                    detail: displayedTransaction.failureReason ?? AppLocalization.string("Network or local validation failed."),
                    systemImage: "xmark.octagon.fill",
                    tint: .red,
                    isComplete: false,
                    isCurrent: true
                )
            )
        }
        return items
    }
    private var confirmedTimelineDetail: String {
        var parts: [String] = []
        if let receiptBlockNumberText = displayedTransaction.receiptBlockNumberText {
            parts.append(AppLocalization.format("Block %@", receiptBlockNumberText))
        }
        if let storedConfirmationCountText = displayedTransaction.storedConfirmationCountText {
            parts.append(storedConfirmationCountText)
        }
        return parts.isEmpty ? AppLocalization.string("Network has confirmed this transaction.") : parts.joined(separator: " - ")
    }
    private func shortTransactionHash(_ hash: String) -> String {
        guard hash.count > 20 else { return hash }
        return "\(hash.prefix(10))...\(hash.suffix(6))"
    }
    private func timelineRow(_ item: TransactionTimelineItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.isComplete || item.isCurrent ? item.tint : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill((item.isComplete || item.isCurrent ? item.tint : Color.primary).opacity(0.14))
                    )
                if !isLast {
                    Rectangle()
                        .fill(item.isComplete ? item.tint.opacity(0.35) : Color.primary.opacity(0.12))
                        .frame(width: 2, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(AppLocalization.string(item.title))
                        .font(.subheadline.weight(.semibold))
                    if item.isCurrent {
                        Text(AppLocalization.string("Current"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(item.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(item.tint.opacity(0.14), in: Capsule())
                    }
                }
                Text(AppLocalization.string(item.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
    private func nonEmptyAddress(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
    private func normalizedAddress(_ value: String?) -> String? {
        guard let trimmed = nonEmptyAddress(value) else { return nil }
        let isEVM = AppEndpointDirectory.appChain(for: displayedTransaction.chainName)?.isEVM ?? false
        return isEVM ? trimmed.lowercased() : trimmed
    }
    private func isOwnedAddress(_ value: String?) -> Bool {
        guard let normalized = normalizedAddress(value) else { return false }
        return ownedAddresses.contains(normalized)
    }
    private func rebuildDisplayedTransactionState() async {
        let resolvedTransaction = store.transactions.first(where: { $0.id == transaction.id }) ?? transaction
        liveTransaction = resolvedTransaction
        guard let walletID = resolvedTransaction.walletID else {
            liveOwnedAddresses = []
            liveFirstOwnedAddress = nil
            return
        }
        let owned = await store.knownOwnedAddresses(for: walletID)
        liveOwnedAddresses = Set(owned.compactMap { normalizedAddress($0) })
        liveFirstOwnedAddress = owned.first
    }
    private struct TransactionTimelineItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let tint: Color
        let isComplete: Bool
        let isCurrent: Bool
    }
}
