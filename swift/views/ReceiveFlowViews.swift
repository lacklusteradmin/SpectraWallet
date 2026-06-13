import Foundation
import SwiftUI
import UIKit

struct ReceiveView: View {
    @Bindable var store: AppState
    @State private var qrWallet: ImportedWallet? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(store.receiveEnabledWallets) { wallet in
                    WalletReceiveCard(wallet: wallet) {
                        store.receiveWalletID = wallet.id
                        store.syncReceiveAssetSelection()
                        spectraHaptic(.light)
                        qrWallet = wallet
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(AppLocalization.string("Receive"))
        .sheet(item: $qrWallet) { wallet in
            ReceiveQRSheet(store: store, wallet: wallet)
        }
    }
}

private struct WalletReceiveCard: View {
    let wallet: ImportedWallet
    let onShowQR: () -> Void
    @State private var didCopy: Bool = false

    var body: some View {
        let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, Color.mint)
        let address = walletStaticAddress(for: wallet)

        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: badge.assetIdentifier,
                fallbackText: wallet.selectedChain,
                color: badge.color,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(wallet.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(wallet.selectedChain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let address {
                    Text(address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(AppLocalization.string("Tap QR to view address"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let address {
                    Button {
                        UIPasteboard.general.string = address
                        didCopy = true
                        spectraHaptic(.light)
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            didCopy = false
                        }
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                }

                Button { onShowQR() } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 22))
    }

    private func walletStaticAddress(for wallet: ImportedWallet) -> String? {
        let raw: String?
        switch wallet.selectedChain {
        case "Bitcoin": raw = wallet.bitcoinAddress
        case "Bitcoin Cash": raw = wallet.bitcoinCashAddress
        case "Bitcoin SV": raw = wallet.bitcoinSvAddress
        case "Litecoin": raw = wallet.litecoinAddress
        case "Dogecoin": raw = wallet.dogecoinAddress
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain",
             "Avalanche", "Hyperliquid", "Polygon", "Base", "Linea", "Scroll",
             "Blast", "Mantle", "Sei", "Celo", "Cronos", "opBNB", "zkSync Era",
             "Sonic", "Berachain", "Unichain", "Ink", "X Layer":
            raw = wallet.ethereumAddress
        case "Tron": raw = wallet.tronAddress
        case "Solana": raw = wallet.solanaAddress
        case "XRP Ledger": raw = wallet.xrpAddress
        case "Stellar": raw = wallet.stellarAddress
        case "Monero": raw = wallet.moneroAddress
        case "Cardano": raw = wallet.cardanoAddress
        case "Sui": raw = wallet.suiAddress
        case "Aptos": raw = wallet.aptosAddress
        case "TON": raw = wallet.tonAddress
        case "Internet Computer": raw = wallet.icpAddress
        case "NEAR": raw = wallet.nearAddress
        case "Polkadot": raw = wallet.polkadotAddress
        case "Zcash": raw = wallet.zcashAddress
        case "Bitcoin Gold": raw = wallet.bitcoinGoldAddress
        case "Decred": raw = wallet.decredAddress
        case "Kaspa": raw = wallet.kaspaAddress
        case "Dash": raw = wallet.dashAddress
        case "Bittensor": raw = wallet.bittensorAddress
        default: raw = nil
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ReceiveQRSheet: View {
    @Bindable var store: AppState
    let wallet: ImportedWallet
    @State private var didCopy: Bool = false
    @State private var isShowingShareSheet: Bool = false
    @State private var qrExportMessage: String?
    @State private var qrImageSaver: PhotoLibraryImageSaver?
    @Environment(\.dismiss) private var dismiss

    private var resolvedAddress: String { store.receiveAddress() }
    private var canUse: Bool { !resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var qrImage: UIImage? {
        let addr = resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return addr.isEmpty ? nil : QRCodeRenderer.makeImage(from: addr)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    qrCard
                    addressCard
                    actionCard
                }
                .padding(20)
            }
            .navigationTitle(wallet.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done")) { dismiss() }
                }
            }
            .task(id: wallet.id) { await store.refreshReceiveAddress() }
            .sheet(isPresented: $isShowingShareSheet) {
                if let qrImage { ActivityItemSheet(activityItems: [qrImage]) }
            }
            .alert(
                AppLocalization.string("QR Code Export"),
                isPresented: .isPresent($qrExportMessage)
            ) {
                Button(AppLocalization.string("OK"), role: .cancel) { qrExportMessage = nil }
            } message: {
                if let qrExportMessage { Text(verbatim: qrExportMessage) }
            }
        }
    }

    @ViewBuilder
    private var qrCard: some View {
        let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, Color.mint)
        VStack(spacing: 16) {
            if canUse {
                QRCodeImage(address: resolvedAddress)
                    .frame(width: 220, height: 220)
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                SpectraShimmer(cornerRadius: 24, height: 256)
                    .frame(width: 256)
            }
            HStack(spacing: 10) {
                CoinBadge(
                    assetIdentifier: badge.assetIdentifier,
                    fallbackText: wallet.selectedChain,
                    color: badge.color,
                    size: 28
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(wallet.name).font(.headline)
                    Text(wallet.selectedChain).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(AppLocalization.string("Scan to receive"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("Address")).font(.headline)
            if canUse {
                Text(resolvedAddress)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
            } else {
                VStack(spacing: 6) {
                    SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: .infinity)
                    SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: .infinity)
                    SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: 180, alignment: .leading)
                }
                .padding(14)
                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
            }
            if didCopy {
                Label(AppLocalization.string("Address copied to clipboard."), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private var actionCard: some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = resolvedAddress
                didCopy = true
                spectraHaptic(.light)
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Label(
                    AppLocalization.string("Copy Address"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canUse || store.isResolvingReceiveAddress)

            Button {
                guard let qrImage else { return }
                isShowingShareSheet = true
                _ = qrImage
            } label: {
                Label(AppLocalization.string("Share QR Code"), systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .disabled(qrImage == nil)

            Button {
                guard let qrImage else { return }
                let saver = PhotoLibraryImageSaver { result in
                    switch result {
                    case .success: qrExportMessage = AppLocalization.string("QR code saved to Photos.")
                    case .failure(let error): qrExportMessage = error.localizedDescription
                    }
                    qrImageSaver = nil
                }
                qrImageSaver = saver
                saver.save(qrImage)
            } label: {
                Label(AppLocalization.string("Save QR Code"), systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .disabled(qrImage == nil)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
}
