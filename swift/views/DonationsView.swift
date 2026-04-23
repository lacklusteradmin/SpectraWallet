import Foundation
import SwiftUI
import UIKit
struct DonationsView: View {
    @State private var copiedAddress: String?
    private var copy: DonationsContentCopy { DonationsContentCopy.current }
    var body: some View {
        Form {
            Section {
                Text(copy.heroSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                ForEach(copy.destinations, id: \.address) { destination in
                    donationRow(
                        chainName: destination.chainName, title: destination.title, address: destination.address
                    )
                }
            } header: {
                Text(AppLocalization.string("Addresses"))
            } footer: {
                Text(AppLocalization.string("Tap an address to copy it."))
            }
        }.navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline)
            .onDisappear { copiedAddress = nil }
    }
    @ViewBuilder
    private func donationRow(chainName: String, title: String, address: String) -> some View {
        let badge = Coin.nativeChainBadge(chainName: chainName) ?? (assetIdentifier: nil, color: Color.mint)
        let isCopied = copiedAddress == address
        Button {
            UIPasteboard.general.string = address
            copiedAddress = address
        } label: {
            HStack(spacing: 12) {
                CoinBadge(assetIdentifier: badge.assetIdentifier, fallbackText: title, color: badge.color, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Color.primary)
                    Text(address).font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
