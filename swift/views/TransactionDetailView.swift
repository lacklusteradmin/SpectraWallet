import Foundation
import SwiftUI
import UIKit
struct TransactionDetailView: View {
    let store: AppState
    let transaction: TransactionRecord
    @State private var replacementMessage: String?
    @State private var liveTransaction: TransactionRecord?
    /// Which ends to show and whether each is the wallet's own: core's
    /// answer, cached for the body. View state: losing it costs a redraw.
    @State private var endpoints: TransactionEndpoints?
    init(store: AppState, transaction: TransactionRecord) {
        self.store = store
        self.transaction = transaction
    }
    private var displayedTransaction: TransactionRecord { liveTransaction ?? transaction }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            CoinBadge(
                                artworkName: displayedTransaction.artworkName, fallbackText: displayedTransaction.symbol,
                                color: displayedTransaction.badgeColor, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayedTransaction.titleText).font(.title3.bold()).foregroundStyle(Color.primary)
                                Text(displayedTransaction.subtitleText).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            statusChip
                        }
                        Text(store.amounts.formattedTransactionDetailAmount(displayedTransaction))
                            .font(.title.weight(.bold)).foregroundStyle(Color.primary)
                            .spectraNumericTextLayout(minimumScaleFactor: 0.5)
                    }.padding(20).spectraBubbleFill().spectraCardFill(cornerRadius: SpectraLayout.Radius.hero)
                    transactionTimelineCard
                    spectraDetailCard(title: "Overview") {
                        detailRow(label: "Type", value: displayedTransaction.kind == .send ? AppLocalization.string("Send") : AppLocalization.string("Receive"))
                        detailRow(label: "Status", value: displayedTransaction.statusText)
                        detailRow(label: "Wallet", value: displayedTransaction.walletName)
                        detailRow(label: "Asset", value: displayedTransaction.assetDisplayName)
                        detailRow(label: "Network", value: displayedTransaction.chainName)
                        detailRow(label: "Timestamp", value: displayedTransaction.fullTimestampText)
                        detailRow(label: "Amount", value: store.amounts.formattedTransactionDetailAmount(displayedTransaction))
                        if let historySourceText = store.amounts.historySourceText(for: displayedTransaction) {
                            detailRow(label: "History Source", value: historySourceText)
                        }
                        if let receiptBlockNumberText = displayedTransaction.receiptBlockNumberText {
                            detailRow(label: "Block", value: receiptBlockNumberText)
                        }
                        if let confirmationCountText = displayedTransaction.storedConfirmationCountText {
                            detailRow(label: "Confirmations", value: confirmationCountText)
                        }
                        if let receiptGasUsed = displayedTransaction.receiptGasUsed { detailRow(label: "Gas Used", value: receiptGasUsed) }
                        if let receiptEffectiveGasPriceText = store.amounts.receiptEffectiveGasPriceText(for: displayedTransaction) {
                            detailRow(label: "Effective Gas Price", value: receiptEffectiveGasPriceText)
                        }
                        if let receiptNetworkFeeText = store.amounts.receiptNetworkFeeText(for: displayedTransaction) {
                            detailRow(label: "Network Fee", value: receiptNetworkFeeText)
                        }
                        if let confirmedNetworkFeeText = store.amounts.confirmedNetworkFeeText(for: displayedTransaction) {
                            detailRow(label: "Confirmed Fee", value: confirmedNetworkFeeText)
                        }
                        if let storedFeeRateText = store.amounts.storedFeeRateText(for: displayedTransaction) {
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
                        if let failureReason = displayedTransaction.localizedFailureReason {
                            detailRow(label: "Failure", value: failureReason)
                        }
                    }
                    // Core says which rows can still be replaced; this row is
                    // one of them or it is not. The old test — the chain named
                    // "Ethereum", a send, pending — left every other EVM chain
                    // without the actions and offered Speed Up on token
                    // transfers it could not rebuild.
                    if let pending = store.replaceableSend(forTransaction: displayedTransaction.id) {
                        spectraDetailCard(title: AppLocalization.format("%@ Mempool Actions", Chain.displayName(forId: pending.chainId))) {
                            if store.sendFlow.isPreparingReplacement {
                                SpectraLoadingRow(title: "Preparing replacement/cancel context...")
                            } else {
                                if pending.canSpeedUp {
                                    Button {
                                        Task {
                                            replacementMessage = await store.openReplacementComposer(
                                                for: displayedTransaction.id, cancel: false
                                            )
                                        }
                                    } label: {
                                        Text(AppLocalization.string("Speed Up This Transaction")).font(.headline).frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }.buttonStyle(.glassProminent)
                                }
                                Button {
                                    Task {
                                        replacementMessage = await store.openReplacementComposer(
                                            for: displayedTransaction.id, cancel: true
                                        )
                                    }
                                } label: {
                                    Text(AppLocalization.string("Cancel This Transaction")).font(.headline).frame(maxWidth: .infinity).padding(
                                        .vertical, 12)
                                }.buttonStyle(.glass)
                                Text(
                                    AppLocalization.string(
                                        pending.canSpeedUp
                                            ? "This opens the Send composer with the same nonce and higher fee defaults so you can safely speed up or cancel the pending transaction."
                                            : "This opens the Send composer with the same nonce and higher fee defaults so you can cancel the pending transfer. A token transfer cannot be rebuilt from its record, so it cannot be sped up."
                                    )
                                ).font(.caption).foregroundStyle(.secondary)
                            }
                            if let replacementMessage {
                                Text(replacementMessage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    spectraDetailCard(title: "Addresses") {
                        if let from = endpoints?.from {
                            TransactionAddressBlock(label: "From", value: from.address, isMine: from.isMine)
                        }
                        if let to = endpoints?.to {
                            TransactionAddressBlock(label: "To", value: to.address, isMine: to.isMine)
                        }
                    }
                    if let transactionHash = displayedTransaction.transactionHash {
                        spectraDetailCard(title: "Transaction Hash") {
                            Text(transactionHash).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(
                                .enabled
                            ).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.input)
                            if let transactionExplorerURL = displayedTransaction.transactionExplorerURL,
                                let transactionExplorerLabel = displayedTransaction.transactionExplorerLabel
                            {
                                Link(destination: transactionExplorerURL) {
                                    Label(transactionExplorerLabel, systemImage: "safari").font(.subheadline.weight(.semibold)).padding(
                                        .horizontal, 12
                                    ).padding(.vertical, 8)
                                }.buttonStyle(.glassProminent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let rawTransactionText = displayedTransaction.rawTransactionText {
                        spectraDetailCard(title: "Raw Transaction") {
                            Text(rawTransactionText).font(.body.monospaced()).foregroundStyle(.secondary).textSelection(
                                .enabled
                            ).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.input)
                        }
                    }
                }.padding(20)
            }
        }.navigationTitle(AppLocalization.string("Transaction")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: refreshKey) { await rebuildDisplayedTransactionState() }
    }
    /// The two revision counters the rebuild depends on, bundled because
    /// `.task(id:)` takes one `Equatable` value. One cancellable task replaces
    /// a `.task` plus two `onChange` closures that each spawned a detached one:
    /// a revision arriving mid-rebuild now cancels the stale pass instead of
    /// racing it to the `live*` assignments.
    private var refreshKey: RefreshKey {
        RefreshKey(transactions: store.transactionRevision, wallets: store.walletsRevision)
    }
    private struct RefreshKey: Equatable {
        let transactions: UInt64
        let wallets: UInt64
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
                    detail: displayedTransaction.localizedFailureReason
                        ?? AppLocalization.string("Network or local validation failed."),
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
    private func rebuildDisplayedTransactionState() async {
        liveTransaction = (try? await store.bridge.ready().transaction(id: transaction.id)) ?? transaction
        endpoints = try? await store.bridge.ready().transactionEndpoints(transactionId: transaction.id)
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

/// A transfer endpoint with independent copy feedback.
/// `.task(id:)` clears the feedback and is cancelled with the view.
private struct TransactionAddressBlock: View {
    let label: String
    let value: String
    let isMine: Bool
    @State private var didCopy = false

    var body: some View {
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
            ).spectraElevatedFill(cornerRadius: SpectraLayout.Radius.input)
            Button {
                UIPasteboard.general.string = value
                didCopy = true
                spectraHaptic(.light)
            } label: {
                Label(
                    didCopy
                        ? AppLocalization.string("Copied")
                        : AppLocalization.string("Copy Address"), systemImage: didCopy ? "checkmark" : "doc.on.doc"
                ).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
            }.buttonStyle(.glass)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
