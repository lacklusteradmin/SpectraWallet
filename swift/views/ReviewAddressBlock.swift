import SwiftUI
import UIKit

/// One end of a send under review: its label, who holds it, and the address
/// in full.
///
/// Nothing is cut — a review shows every character it is about to sign. The
/// address is set in groups of four with the first and last groups primary,
/// the way a reader checks it against another screen, and the spaces between
/// groups are where it wraps, so the system never hyphenates it.
///
/// The holder is core's answer (`addressHolder`), asked again whenever the
/// address changes. View state: losing it costs a lookup.
struct ReviewAddressBlock: View {
    let store: AppState
    let label: String
    let walletId: String
    let chainId: String
    let address: String
    @State private var holder: EndpointHolder?

    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
            HStack(spacing: SpectraLayout.Space.s) {
                Text(AppLocalization.string(label)).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: SpectraLayout.Space.s)
                if let holder { EndpointHolderLabel(holder: holder) }
            }
            Text(groupedAddress(address)).font(.body.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: address))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = address
                    } label: {
                        Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc")
                    }
                }
        }
        .task(id: "\(walletId)|\(chainId)|\(address)") {
            holder = nil
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !walletId.isEmpty, !chainId.isEmpty else { return }
            let answer = try? await store.bridge.ready().addressHolder(walletId: walletId, chainId: chainId, address: trimmed)
            guard !Task.isCancelled else { return }
            holder = answer
        }
    }
}

/// `address` in groups of four, a `0x` prefix riding on the first, with the
/// first and last groups primary and the rest secondary.
private func groupedAddress(_ address: String) -> AttributedString {
    let hasHexPrefix = address.hasPrefix("0x")
    let body = Array(hasHexPrefix ? address.dropFirst(2) : Substring(address))
    var groups = stride(from: 0, to: body.count, by: 4).map { String(body[$0..<min($0 + 4, body.count)]) }
    guard !groups.isEmpty else { return AttributedString(address) }
    if hasHexPrefix { groups[0] = "0x" + groups[0] }
    var text = AttributedString()
    for (index, group) in groups.enumerated() {
        if index > 0 { text += AttributedString(" ") }
        var part = AttributedString(group)
        part.swiftUI.foregroundColor = index == 0 || index == groups.count - 1 ? .primary : .secondary
        text += part
    }
    return text
}
