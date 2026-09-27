import SwiftUI

/// A projection of core's durable artifact; actions never assemble transaction fields.
struct SendStagesView: View {
    @Bindable var store: AppState
    let artifact: SendArtifact
    @State private var transaction: TransactionRecord?
    @State private var transactionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack {
                Label(AppLocalization.string("Build"), systemImage: "checkmark.circle.fill")
                Spacer()
                Label(AppLocalization.string("Sign"), systemImage: artifact.stage == .signed ? "checkmark.circle.fill" : "circle")
                Spacer()
                Label(AppLocalization.string("Broadcast"), systemImage: artifact.attempts.isEmpty ? "circle" : "antenna.radiowaves.left.and.right")
            }
            .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                Text(verbatim: amountText).font(.title2.weight(.bold)).spectraNumericTextLayout()
                LabeledContent(AppLocalization.string("Network"), value: Chain.displayName(forId: artifact.chainId))
                Divider().opacity(0.4)
                ReviewAddressBlock(
                    store: store, label: "From", walletId: artifact.walletId, chainId: artifact.chainId,
                    address: artifact.sender)
                Divider().opacity(0.4)
                ReviewAddressBlock(
                    store: store, label: "To", walletId: artifact.walletId, chainId: artifact.chainId,
                    address: artifact.recipient)
                Divider().opacity(0.4)
                Text(AppLocalization.string(artifact.stage == .prepared ? "Built. Review the transaction before signing." : artifact.attempts.isEmpty ? "Signed and saved. Not broadcast." : "Submission results are shown below. Node acceptance is not on-chain confirmation."))
                    .foregroundStyle(.secondary)
                DisclosureGroup(AppLocalization.string("Transaction details")) {
                    Text(verbatim: artifact.preparedDetails).font(.caption.monospaced()).textSelection(.enabled)
                    Text(verbatim: artifact.reviewDigest).font(.caption.monospaced()).textSelection(.enabled)
                    if !artifact.signingPayloadHex.isEmpty {
                        Text(verbatim: artifact.signingPayloadHex).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if let payload = artifact.signedPayload {
                    DisclosureGroup(AppLocalization.string("Signed payload")) {
                        Text(verbatim: payload).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .padding(SpectraLayout.Space.l)
            .spectraCardFill()
            ForEach(Array(store.pendingHighRiskSendReasons.dropFirst().enumerated()), id: \.offset) { _, reason in
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.spectraWarning)
            }
            if artifact.stage == .signed {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                    Text(AppLocalization.string("Broadcast destinations")).font(.headline)
                    ForEach(store.sendFlow.endpointChoices, id: \.self) { endpoint in
                        Toggle(isOn: Binding(
                            get: { store.sendFlow.selectedEndpoints.contains(endpoint) },
                            set: { selected in
                                if selected { store.sendFlow.selectedEndpoints.insert(endpoint) }
                                else { store.sendFlow.selectedEndpoints.remove(endpoint) }
                            }
                        )) { Text(verbatim: endpoint).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Text(AppLocalization.string("Only selected nodes receive this submission from Spectra. Those nodes may propagate the transaction to other nodes."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(SpectraLayout.Space.l)
                .spectraCardFill()
            }
            if let transaction, transaction.id == artifact.id {
                SendTransactionCard(store: store, tx: transaction)
                LabeledContent(AppLocalization.string("On-chain status"), value: AppLocalization.string(
                    transaction.status == .confirmed ? "Confirmed" : transaction.status == .failed ? "Failed" : "Awaiting confirmation"))
            }
            ForEach(Array(artifact.attempts.enumerated()), id: \.offset) { _, attempt in
                VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
                    Text(verbatim: attempt.endpoint).font(.caption.monospaced())
                    Text(AppLocalization.string(outcomeText(attempt.outcome))).font(.headline)
                    Text(verbatim: attempt.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let hash = attempt.transactionHash { Text(verbatim: hash).font(.caption.monospaced()).textSelection(.enabled) }
                }
                .padding(SpectraLayout.Space.l)
                .spectraCardFill()
            }
            if let transactionError {
                Text(transactionError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(artifact.id):\(store.transactionRevision)") {
            if transaction?.id != artifact.id {
                transaction = nil
                transactionError = nil
            }
            do {
                let record = try await store.bridge.ready().transaction(id: artifact.id)
                guard !Task.isCancelled else { return }
                transaction = record
                transactionError = nil
            } catch {
                guard !Task.isCancelled else { return }
                transactionError = error.localizedDescription
            }
        }
    }
    /// The amount in the unit a person reads it in. Core stores a token send's
    /// asset as its exact contract, which is the identity, not a name: the
    /// wallet's holding of that contract gives the symbol. A coin's asset is
    /// already its symbol.
    private var amountText: String {
        let symbol = store.availableSendCoins(for: artifact.walletId)
            .first { $0.chainId == artifact.chainId && $0.contractAddress == artifact.asset }?
            .symbol ?? artifact.asset
        return "\(AmountPresentation.localizedDecimal(artifact.amount)) \(symbol)"
    }
    private func outcomeText(_ outcome: SubmissionOutcome) -> String {
        switch outcome {
        case .accepted: "Node accepted"
        case .rejected: "Node rejected"
        case .uncertain: "Submission uncertain"
        }
    }
}
