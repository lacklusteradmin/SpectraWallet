import Foundation
import SwiftUI
import UIKit
struct DonationsView: View {
    @State private var copiedAddress: String?
    private var copy: DonationsContentCopy { DonationsContentCopy.current }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                heroCard
                addressesCard
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.background(SpectraBackdrop().ignoresSafeArea())
            .navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onDisappear { copiedAddress = nil }
    }
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "heart.fill").font(.largeTitle.weight(.bold)).foregroundStyle(.orange)
            Text(copy.navigationTitle).font(.title.weight(.bold)).foregroundStyle(Color.primary)
            Text(copy.heroSubtitle).font(.subheadline).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }
    private var addressesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Addresses")).font(.headline).foregroundStyle(Color.primary)
            ForEach(copy.destinations, id: \.address) { destination in
                donationRow(chainName: destination.chainName, title: destination.title, address: destination.address)
                if destination.address != copy.destinations.last?.address {
                    Divider().opacity(0.25)
                }
            }
            Text(AppLocalization.string("Tap an address to copy it.")).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
    @ViewBuilder
    private func donationRow(chainName: String, title: String, address: String) -> some View {
        let badge = Coin.nativeChainBadge(chainName: chainName) ?? (assetIdentifier: nil, color: Color.mint)
        let isCopied = copiedAddress == address
        HStack(spacing: 12) {
            CoinBadge(assetIdentifier: badge.assetIdentifier, fallbackText: title, color: badge.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                Text(address).font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = address
                copiedAddress = address
                spectraHaptic(.light)
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.body.weight(.semibold))
                    .accessibilityLabel(AppLocalization.string(isCopied ? "Copied" : "Copy"))
            }.buttonStyle(.glass).tint(isCopied ? .green : .orange)
        }.padding(.vertical, 4)
    }
}
