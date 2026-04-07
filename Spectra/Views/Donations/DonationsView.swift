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
                SpectraBackdrop()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                SpectraLogo(size: 58)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(copy.heroTitle)
                                        .font(.title2.bold())
                                        .foregroundStyle(Color.primary)
                                    Text(copy.heroSubtitle)
                                        .foregroundStyle(Color.primary.opacity(0.76))
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 28))
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(copy.destinations, id: \.address) { destination in
                                donationRow(
                                    chainName: destination.chainName,
                                    title: destination.title,
                                    address: destination.address
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(copy.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedDonation) { donation in
                DonationQRCodeView(donation: donation)
            }
        }
    }
    
    @ViewBuilder
    private func donationRow(chainName: String, title: String, address: String) -> some View {
        let badge = Coin.nativeChainBadge(chainName: chainName) ?? (assetIdentifier: nil, mark: String(title.prefix(2)).uppercased(), color: Color.mint)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CoinBadge(assetIdentifier: badge.assetIdentifier, fallbackText: badge.mark, color: badge.color, size: 30)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        UIPasteboard.general.string = address
                        copiedAddress = address
                    } label: {
                        Image(systemName: copiedAddress == address ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedDonation = DonationDestination(title: title, address: address, mark: badge.mark, assetIdentifier: badge.assetIdentifier, color: badge.color)
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(address)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.primary.opacity(0.72))
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 22))
    }
}
