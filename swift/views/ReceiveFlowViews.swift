import Foundation
import SwiftUI
import UIKit
struct ReceiveView: View {
    @ObservedObject var store: AppState
    @State private var didCopyReceiveAddress: Bool = false
    @State private var isShowingReceiveQRShareSheet: Bool = false
    @State private var receiveQRExportMessage: String?
    @State private var receiveQRImageSaver: PhotoLibraryImageSaver?
    private struct Presentation {
        let resolvedAddress: String
        let canUseAddress: Bool
        let qrImage: UIImage?
        let receiveWallets: [ImportedWallet]
        let selectedCoin: Coin?
        let sameChainSymbolsText: String? }
    init(store: AppState) {
        self.store = store
    }
    private func localized(_ key: String) -> String { AppLocalization.string(key) }
    private var presentation: Presentation {
        let resolvedAddress = store.receiveAddress()
        let trimmedAddress = resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCoin = store.selectedReceiveCoin(for: store.receiveWalletID)
        let sameChainSymbolsText = selectedCoin.map { coin in
            let chainSymbols = Array(
                Set(
                    store.availableReceiveCoins(for: store.receiveWalletID).filter { $0.chainName == coin.chainName }.map(\.symbol)
                )
            ).sorted().joined(separator: ", ")
            return chainSymbols.isEmpty ? nil : chainSymbols
        } ?? nil
        return Presentation(
            resolvedAddress: resolvedAddress, canUseAddress: !trimmedAddress.isEmpty, qrImage: trimmedAddress.isEmpty ? nil : QRCodeRenderer.makeImage(from: resolvedAddress), receiveWallets: store.receiveEnabledWallets, selectedCoin: selectedCoin, sameChainSymbolsText: sameChainSymbolsText
        )
    }
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    receiveDetailCard(title: "Wallet") {
                        Picker("Wallet", selection: store.receiveWalletIDBinding) {
                            ForEach(presentation.receiveWallets) { wallet in Text(wallet.name).tag(wallet.id) }}.onChange(of: store.receiveWalletID) { _, _ in
                            store.syncReceiveAssetSelection()
                        }}
                    receiveAddressSections
                }.padding(20)
            }.navigationTitle(localized("Receive")).task(id: store.receiveWalletID) {
                await store.refreshReceiveAddress()
            }.sheet(isPresented: $isShowingReceiveQRShareSheet) {
                if let receiveQRImage = presentation.qrImage { ActivityItemSheet(activityItems: [receiveQRImage]) }}.alert(localized("QR Code Export"), isPresented: Binding(
                get: { receiveQRExportMessage != nil }, set: { isPresented in
                    if !isPresented { receiveQRExportMessage = nil }}
            )) {
                Button(localized("OK"), role: .cancel) {
                    receiveQRExportMessage = nil
                }} message: {
                if let receiveQRExportMessage { Text(verbatim: receiveQRExportMessage) }}.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = presentation.resolvedAddress
                        didCopyReceiveAddress = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            didCopyReceiveAddress = false
                        }} label: { Label(localized("Copy"), systemImage: didCopyReceiveAddress ? "checkmark" : "doc.on.doc") }.disabled(!presentation.canUseAddress || store.isResolvingReceiveAddress)
                }}}}
    @ViewBuilder
    private var receiveAddressSections: some View {
        receiveDetailCard(title: "QR Code") {
            VStack(alignment: .center, spacing: 12) {
                if presentation.canUseAddress {
                    QRCodeImage(address: presentation.resolvedAddress).frame(width: 184, height: 184).padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(localized("Scan to receive")).font(.headline)
                    Text(localized("Share this QR code or copy the address below.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        guard let receiveQRImage = presentation.qrImage else { return }
                        let saver = PhotoLibraryImageSaver { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success: receiveQRExportMessage = localized("QR code saved to Photos.")
                                case .failure(let error): receiveQRExportMessage = error.localizedDescription
                                }
                                receiveQRImageSaver = nil
                            }}
                        receiveQRImageSaver = saver
                        saver.save(receiveQRImage)
                    } label: {
                        Label(localized("Save QR Code"), systemImage: "square.and.arrow.down").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.glass).disabled(presentation.qrImage == nil)
                } else {
                    ProgressView()
                    Text(localized("Preparing receive address...")).font(.headline)
                    Text(localized("Spectra is resolving the current address for this wallet.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }}.frame(maxWidth: .infinity).padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
        }
        receiveDetailCard(title: "Address") {
            Text(presentation.resolvedAddress).font(.body.monospaced()).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 18))
            if didCopyReceiveAddress { Label(localized("Address copied to clipboard."), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }}
        if let receiveCoin = presentation.selectedCoin {
            receiveDetailCard(title: "Asset Details") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: receiveCoin.iconIdentifier, fallbackText: receiveCoin.mark, color: receiveCoin.color, size: 34
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receiveCoin.name).font(.headline)
                            Text(receiveCoin.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    LabeledContent(localized("Network"), value: receiveCoin.chainName)
                    LabeledContent(localized("Standard"), value: receiveCoin.tokenStandard)
                    if let chainSymbols = presentation.sameChainSymbolsText, chainSymbols.contains(",") {
                        LabeledContent(localized("Also Receives")) {
                            Text(chainSymbols).multilineTextAlignment(.trailing)
                        }}
                    if let contractAddress = receiveCoin.contractAddress {
                        LabeledContent(localized("Contract")) {
                            Text(contractAddress).font(.footnote.monospaced()).textSelection(.enabled)
                        }}}}}}
    @ViewBuilder
    private func receiveDetailCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(title)).font(.headline.weight(.semibold)).foregroundStyle(Color.primary)
            content()
        }.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
}
