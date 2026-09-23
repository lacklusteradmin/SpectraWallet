import SwiftUI

/// A projection of core's durable artifact; actions never assemble transaction fields.
struct SendStagesView: View {
    @Bindable var store: AppState
    let artifact: SendArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(AppLocalization.string("Build"), systemImage: "checkmark.circle.fill")
                Spacer()
                Label(AppLocalization.string("Sign"), systemImage: artifact.stage == .signed ? "checkmark.circle.fill" : "circle")
                Spacer()
                Label(AppLocalization.string("Broadcast"), systemImage: artifact.attempts.isEmpty ? "circle" : "antenna.radiowaves.left.and.right")
            }
            .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: artifact.amount).font(.title2.weight(.bold))
                LabeledContent(AppLocalization.string("Asset")) {
                    Text(verbatim: artifact.asset).textSelection(.enabled)
                }
                LabeledContent(AppLocalization.string("Network"), value: artifact.chainId)
                Text(AppLocalization.string("From")).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: artifact.sender).font(.body.monospaced()).textSelection(.enabled)
                Text(AppLocalization.string("To")).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: artifact.recipient).font(.body.monospaced()).textSelection(.enabled)
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
            .padding(18)
            .spectraCardFill(cornerRadius: SpectraLayout.Radius.card)
            ForEach(Array(store.pendingHighRiskSendReasons.dropFirst().enumerated()), id: \.offset) { _, reason in
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            if artifact.stage == .signed {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Broadcast destinations")).font(.headline)
                    ForEach(store.sendEndpointChoices, id: \.self) { endpoint in
                        Toggle(isOn: Binding(
                            get: { store.selectedSendEndpoints.contains(endpoint) },
                            set: { selected in
                                if selected { store.selectedSendEndpoints.insert(endpoint) }
                                else { store.selectedSendEndpoints.remove(endpoint) }
                            }
                        )) { Text(verbatim: endpoint).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Text(AppLocalization.string("Only selected nodes receive this submission from Spectra. Those nodes may propagate the transaction to other nodes."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
                .spectraCardFill(cornerRadius: SpectraLayout.Radius.card)
            }
            if let transaction = store.transactions.first(where: { $0.id == artifact.id }) {
                SendTransactionCard(store: store, tx: transaction)
                LabeledContent(AppLocalization.string("On-chain status"), value: AppLocalization.string(
                    transaction.status == .confirmed ? "Confirmed" : transaction.status == .failed ? "Failed" : "Awaiting confirmation"))
            }
            ForEach(Array(artifact.attempts.enumerated()), id: \.offset) { _, attempt in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: attempt.endpoint).font(.caption.monospaced())
                    Text(AppLocalization.string(outcomeText(attempt.outcome))).font(.headline)
                    Text(verbatim: attempt.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let hash = attempt.transactionHash { Text(verbatim: hash).font(.caption.monospaced()).textSelection(.enabled) }
                }
                .padding(18)
                .spectraCardFill(cornerRadius: SpectraLayout.Radius.card)
            }
        }
    }
    private func outcomeText(_ outcome: SubmissionOutcome) -> String {
        switch outcome {
        case .accepted: "Node accepted"
        case .rejected: "Node rejected"
        case .uncertain: "Submission uncertain"
        }
    }
}
