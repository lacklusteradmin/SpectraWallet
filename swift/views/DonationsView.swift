import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
struct DonationsView: View {
    @State private var selectedDonation: DonationDestination?
    @State private var copiedAddress: String?
    private var copy: DonationsContentCopy { DonationsContentCopy.current }
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(copy.heroTitle).font(.title2.weight(.bold))
                            Text(copy.heroSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
                        VStack(spacing: 0) {
                            ForEach(Array(copy.destinations.enumerated()), id: \.element.address) { index, destination in
                                donationRow(
                                    chainName: destination.chainName, title: destination.title, address: destination.address
                                )
                                if index < copy.destinations.count - 1 { Divider().padding(.leading, 58).opacity(0.25) }
                            }
                        }.padding(.vertical, 4).frame(maxWidth: .infinity)
                            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                }
            }.navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .sheet(item: $selectedDonation) { donation in
                    DonationQRCodeView(donation: donation)
                }
        }
    }
    @ViewBuilder
    private func donationRow(chainName: String, title: String, address: String) -> some View {
        let badge =
            Coin.nativeChainBadge(chainName: chainName) ?? (
                assetIdentifier: nil, mark: String(title.prefix(2)).uppercased(), color: Color.mint
            )
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CoinBadge(assetIdentifier: badge.assetIdentifier, fallbackText: badge.mark, color: badge.color, size: 30)
                Text(title).font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = address
                        copiedAddress = address
                    } label: {
                        Image(systemName: copiedAddress == address ? "checkmark" : "doc.on.doc").font(.subheadline.weight(.semibold)).padding(8)
                    }.buttonStyle(.glass)
                    Button {
                        selectedDonation = DonationDestination(
                            title: title, address: address, mark: badge.mark, assetIdentifier: badge.assetIdentifier, color: badge.color)
                    } label: {
                        Image(systemName: "qrcode").font(.subheadline.weight(.semibold)).padding(8)
                    }.buttonStyle(.glass)
                }
            }
            Text(address).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
