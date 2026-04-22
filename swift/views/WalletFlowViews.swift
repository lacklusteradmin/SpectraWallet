import Foundation
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
import VisionKit
func localizedWalletFlowString(_ key: String) -> String {
    AppLocalization.string(key)
}
struct TransactionStatusBadge: View {
    let status: TransactionStatus
    private var statusText: String { status.localizedTitle }
    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .mint
        case .failed: return .red
        }
    }
    private var badgeScale: CGFloat {
        switch status {
        case .pending: return 1.0
        case .confirmed: return 1.05
        case .failed: return 0.97
        }
    }
    var body: some View {
        Text(statusText.uppercased()).font(.caption2.bold()).tracking(0.6).frame(minWidth: 86).padding(.horizontal, 10).padding(
            .vertical, 6
        ).background(statusColor.opacity(0.16), in: Capsule()).foregroundStyle(statusColor).scaleEffect(badgeScale).animation(
            .spring(response: 0.35, dampingFraction: 0.74), value: status)
    }
}
struct SendQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void
    var body: some View {
        NavigationStack {
            QRCodeScannerView { payload in
                onScan(payload)
                dismiss()
            }.ignoresSafeArea(edges: .bottom).navigationTitle(localizedWalletFlowString("Scan QR Code")).navigationBarTitleDisplayMode(
                .inline
            ).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localizedWalletFlowString("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasResolvedPayload = false
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) { resolve(item, from: dataScanner) }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let firstItem = addedItems.first else { return }
            resolve(firstItem, from: dataScanner)
        }
        private func resolve(_ item: RecognizedItem, from dataScanner: DataScannerViewController) {
            guard !hasResolvedPayload else { return }
            guard case .barcode(let barcode) = item,
                let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty
            else { return }
            hasResolvedPayload = true
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}
struct WalletCardView: View, Equatable {
    struct Presentation: Equatable {
        let walletName: String
        let chainTitleText: String
        let totalValueText: String
        let assetCountText: String
        let isWatchOnly: Bool
        let badgeAssetIdentifier: String?
        let badgeMark: String
        let badgeColor: Color
    }
    let presentation: Presentation
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.presentation == rhs.presentation }
    private var watchOnlyBadge: some View {
        Image(systemName: "eye").font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoinBadge(
                    assetIdentifier: presentation.badgeAssetIdentifier, fallbackText: presentation.badgeMark,
                    color: presentation.badgeColor, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if presentation.isWatchOnly { watchOnlyBadge }
                        Text(presentation.walletName).font(.headline).foregroundStyle(Color.primary)
                    }
                    Text(presentation.chainTitleText).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(presentation.totalValueText).font(.headline).foregroundStyle(Color.primary).spectraNumericTextLayout()
                    Text(presentation.assetCountText).font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }.contentShape(Rectangle())
    }
}
struct QRCodeRenderer {
    static func makeImage(from string: String, scale: CGFloat = 12) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
struct ActivityItemSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
@MainActor
final class PhotoLibraryImageSaver: NSObject {
    private let completion: (Result<Void, Error>) -> Void
    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }
    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc
    private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error { completion(.failure(error)) } else { completion(.success(())) }
    }
}
struct DonationQRCodeView: View {
    let donation: DonationDestination
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 24) {
                    CoinBadge(
                        assetIdentifier: donation.assetIdentifier, fallbackText: donation.mark, color: donation.color, size: 54
                    )
                    Text(localizedWalletFlowString("Scan to Donate")).font(.title2.bold()).foregroundStyle(Color.primary)
                    Text(donation.title).font(.headline).foregroundStyle(.secondary)
                    QRCodeImage(address: donation.address).frame(width: 220, height: 220).padding(18).background(
                        Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    Text(donation.address).font(.footnote.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(
                        .center
                    ).textSelection(.enabled).padding(.horizontal, 24)
                    Spacer()
                }.padding(20)
            }.navigationTitle(localizedWalletFlowString("QR Code")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizedWalletFlowString("Done")) {
                        dismiss()
                    }.buttonStyle(.glass)
                }
            }
        }
    }
}
struct QRCodeImage: View {
    let address: String
    var body: some View {
        if let image = qrUIImage {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().padding(28).foregroundStyle(.black)
        }
    }
    private var qrUIImage: UIImage? { QRCodeRenderer.makeImage(from: address) }
}
struct WalletDetailView: View {
    let store: AppState
    let wallet: ImportedWallet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSeedPhrasePasswordPrompt: Bool = false
    @State private var isShowingSeedPhraseSheet: Bool = false
    @State private var seedPhrasePasswordInput: String = ""
    @State private var revealedSeedPhrase: String = ""
    @State private var seedPhraseErrorMessage: String?
    @State private var isRevealingSeedPhrase: Bool = false
    @State private var didCopyWalletAddress: Bool = false
    @State private var isShowingDeleteWalletAlert: Bool = false
    @State private var isShowingAdvancedPage: Bool = false
    init(store: AppState, wallet: ImportedWallet) {
        self.store = store
        self.wallet = wallet
    }
    private struct HoldingPresentation: Identifiable {
        let coin: Coin
        let amountText: String
        let valueText: String
        var id: String { coin.id }
    }
    private struct DetailPresentation {
        let wallet: ImportedWallet
        let nonZeroAssetCount: Int
        let walletAddress: String?
        let derivationPathsText: String?
        let walletBadge: (assetIdentifier: String?, mark: String, color: Color)
        let visibleHoldingPresentations: [HoldingPresentation]
        let walletTotalValueText: String
    }
    private static let firstActivityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private var isWatchOnly: Bool { store.isWatchOnlyWallet(displayedWallet) }
    private var isPrivateKeyWallet: Bool { store.isPrivateKeyWallet(displayedWallet) }
    private var requiresSeedPhrasePassword: Bool { store.walletRequiresSeedPhrasePassword(displayedWallet.id) }
    private var displayedWallet: ImportedWallet {
        store.wallets.first(where: { $0.id == wallet.id }) ?? wallet
    }
    private var firstActivityDateText: String {
        guard let firstDate = store.cachedFirstActivityDateByWalletID[wallet.id] else {
            return localizedWalletFlowString("No activity yet")
        }
        return Self.firstActivityFormatter.string(from: firstDate)
    }
    private var detailPresentation: DetailPresentation {
        let wallet = displayedWallet
        let visibleHoldings = wallet.holdings.filter { $0.amount > 0 }
            .map { holding in (coin: holding, quotedValue: store.currentValueIfAvailable(for: holding) ?? -1) }
            .sorted {
                if abs($0.quotedValue - $1.quotedValue) > 0.000001 { return $0.quotedValue > $1.quotedValue }
                return $0.coin.symbol.localizedCaseInsensitiveCompare($1.coin.symbol) == .orderedAscending
            }
        let holdingPresentations = visibleHoldings.map { entry in
            HoldingPresentation(
                coin: entry.coin,
                amountText: store.formattedAssetAmount(entry.coin.amount, symbol: entry.coin.symbol, chainName: entry.coin.chainName),
                valueText: store.preferences.hideBalances
                    ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: entry.quotedValue >= 0 ? entry.quotedValue : nil)
            )
        }
        return DetailPresentation(
            wallet: wallet, nonZeroAssetCount: visibleHoldings.count,
            walletAddress: [
                wallet.bitcoinAddress, wallet.bitcoinCashAddress, wallet.litecoinAddress, wallet.dogecoinAddress, wallet.ethereumAddress,
                wallet.tronAddress, wallet.solanaAddress, wallet.xrpAddress, wallet.moneroAddress, wallet.cardanoAddress, wallet.suiAddress,
                wallet.aptosAddress, wallet.tonAddress, wallet.nearAddress, wallet.polkadotAddress, wallet.stellarAddress,
            ]
            .compactMap { $0 }
            .first, derivationPathsText: derivationPathsText(for: wallet),
            walletBadge: Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, "W", .mint),
            visibleHoldingPresentations: holdingPresentations,
            walletTotalValueText: store.preferences.hideBalances
                ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: wallet))
        )
    }
    private func derivationPathsText(for wallet: ImportedWallet) -> String? {
        guard !isWatchOnly, !isPrivateKeyWallet else { return nil }
        let chainMappings: [String: SeedDerivationChain] = [
            "Bitcoin": .bitcoin, "Bitcoin Cash": .bitcoinCash, "Bitcoin SV": .bitcoinSV, "Litecoin": .litecoin, "Dogecoin": .dogecoin,
            "Ethereum": .ethereum, "Ethereum Classic": .ethereumClassic, "Arbitrum": .arbitrum, "Optimism": .optimism,
            "BNB Chain": .ethereum, "Avalanche": .avalanche, "Hyperliquid": .hyperliquid, "Tron": .tron, "Solana": .solana,
            "Cardano": .cardano, "XRP Ledger": .xrp, "Sui": .sui, "Aptos": .aptos, "TON": .ton, "Internet Computer": .internetComputer,
            "NEAR": .near, "Polkadot": .polkadot, "Stellar": .stellar,
        ]
        guard let derivationChain = chainMappings[wallet.selectedChain] else { return nil }
        return walletFlowLocalizedFormat(
            "wallet.detail.chainPath", wallet.selectedChain, wallet.seedDerivationPaths.path(for: derivationChain))
    }
    private var watchOnlyBadge: some View {
        Label(localizedWalletFlowString("Watching"), systemImage: "eye").font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(
            .horizontal, 10
        ).padding(.vertical, 6).background(Color.orange.opacity(0.15), in: Capsule())
    }
    private var deleteWalletMessage: String {
        if isWatchOnly {
            return localizedWalletFlowString("You can't recover this wallet after deletion until you still have this address.")
        }
        if isPrivateKeyWallet {
            return localizedWalletFlowString("Please keep this private key because you can't recover this wallet after deletion.")
        }
        return localizedWalletFlowString("Please take note of your seed phrase because you can't recover this wallet after deletion.")
    }
    private func clearSeedRevealState() {
        isShowingSeedPhrasePasswordPrompt = false
        isShowingSeedPhraseSheet = false
        seedPhrasePasswordInput = ""
        revealedSeedPhrase = ""
        seedPhraseErrorMessage = nil
    }
    private func handleWalletPresenceChange(walletStillExists: Bool) {
        guard !walletStillExists else { return }
        isShowingDeleteWalletAlert = false
        clearSeedRevealState()
        dismiss()
    }
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase != .active else { return }
        clearSeedRevealState()
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    CoinBadge(
                        assetIdentifier: detailPresentation.walletBadge.assetIdentifier, fallbackText: detailPresentation.walletBadge.mark,
                        color: detailPresentation.walletBadge.color, size: 46
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(detailPresentation.wallet.name).font(.title2.weight(.bold)).foregroundStyle(Color.primary)
                            Spacer(minLength: 0)
                            if isWatchOnly { watchOnlyBadge }
                        }
                        Text(store.displayChainTitle(for: detailPresentation.wallet)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                VStack(alignment: .leading, spacing: 12) {
                    detailRow(
                        label: "Mode",
                        value: isWatchOnly
                            ? localizedWalletFlowString("Watch Addresses")
                            : (isPrivateKeyWallet ? localizedWalletFlowString("Private Key") : localizedWalletFlowString("Seed-Based")))
                    detailRow(label: "Current Value", value: detailPresentation.walletTotalValueText)
                    detailRow(label: "Asset Count", value: "\(detailPresentation.nonZeroAssetCount)")
                    detailRow(label: "First Activity", value: firstActivityDateText)
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(localizedWalletFlowString("Holdings")).font(.headline).foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(detailPresentation.visibleHoldingPresentations.count)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if detailPresentation.visibleHoldingPresentations.isEmpty {
                        Text(localizedWalletFlowString("No assets loaded for this wallet yet.")).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(detailPresentation.visibleHoldingPresentations) { holding in
                            holdingRow(holding)
                        }
                    }
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                if let walletAddress = detailPresentation.walletAddress {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(localizedWalletFlowString("Wallet Address")).font(.headline).foregroundStyle(Color.primary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = walletAddress
                                didCopyWalletAddress = true
                            } label: {
                                Label(
                                    didCopyWalletAddress ? localizedWalletFlowString("Copied") : localizedWalletFlowString("Copy"),
                                    systemImage: didCopyWalletAddress ? "checkmark" : "doc.on.doc"
                                ).font(.caption.weight(.semibold))
                            }.buttonStyle(.borderless).foregroundStyle(Color.primary)
                        }
                        Text(walletAddress).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                }
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.beginEditingWallet(wallet)
                        }
                    } label: {
                        Label(localizedWalletFlowString("Edit Name"), systemImage: "pencil").font(.subheadline.weight(.semibold)).frame(
                            maxWidth: .infinity
                        ).padding(.vertical, 9)
                    }.buttonStyle(.glass)
                    if !isWatchOnly && !isPrivateKeyWallet {
                        Button {
                            if requiresSeedPhrasePassword {
                                seedPhrasePasswordInput = ""
                                isShowingSeedPhrasePasswordPrompt = true
                            } else {
                                Task {
                                    await revealSeedPhrase()
                                }
                            }
                        } label: {
                            Label(
                                isRevealingSeedPhrase
                                    ? localizedWalletFlowString("Checking Face ID...")
                                    : (requiresSeedPhrasePassword
                                        ? localizedWalletFlowString("Show Seed Phrase (Password)")
                                        : localizedWalletFlowString("Show Seed Phrase")),
                                systemImage: requiresSeedPhrasePassword ? "lock.shield" : "faceid"
                            ).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.glass).disabled(isRevealingSeedPhrase || !store.canRevealSeedPhrase(for: wallet.id))
                    }
                    Button(role: .destructive) {
                        isShowingDeleteWalletAlert = true
                    } label: {
                        Label(localizedWalletFlowString("Delete Wallet"), systemImage: "trash").font(.subheadline.weight(.semibold)).frame(
                            maxWidth: .infinity
                        ).padding(.vertical, 9)
                    }.buttonStyle(.glass)
                }
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.refreshable {
            await store.refreshWalletBalance(wallet.id)
        }.navigationTitle(localizedWalletFlowString("Wallet Details")).navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedWalletFlowString("Advanced")) {
                    isShowingAdvancedPage = true
                }
            }
        }.navigationDestination(isPresented: $isShowingAdvancedPage) {
            WalletAdvancedDetailsView(
                walletID: detailPresentation.wallet.id, derivationPathsText: detailPresentation.derivationPathsText
            )
        }.navigationDestination(
            isPresented: Binding(
                get: { store.isShowingWalletImporter && store.editingWalletID == wallet.id },
                set: { isPresented in
                    if !isPresented { store.isShowingWalletImporter = false }
                }
            )
        ) {
            SetupView(store: store, draft: store.importDraft)
        }.alert(localizedWalletFlowString("Delete Wallet?"), isPresented: $isShowingDeleteWalletAlert) {
            Button(localizedWalletFlowString("Delete"), role: .destructive) {
                Task {
                    store.confirmDeleteWallet(wallet)
                    await store.deletePendingWallet()
                }
            }
            Button(localizedWalletFlowString("Cancel"), role: .cancel) {
                isShowingDeleteWalletAlert = false
            }
        } message: {
            Text(deleteWalletMessage)
        }.alert(
            localizedWalletFlowString("Cannot Reveal Seed Phrase"),
            isPresented: .isPresent($seedPhraseErrorMessage)
        ) {
            Button(localizedWalletFlowString("OK"), role: .cancel) {}
        } message: {
            Text(seedPhraseErrorMessage ?? "Unknown error")
        }.onChange(of: wallet.id) { _, _ in
            didCopyWalletAddress = false
        }.onChange(of: store.wallets.contains(where: { $0.id == wallet.id })) { _, walletStillExists in
            handleWalletPresenceChange(walletStillExists: walletStillExists)
        }.onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }.sheet(
            isPresented: $isShowingSeedPhrasePasswordPrompt,
            onDismiss: {
                seedPhrasePasswordInput = ""
            }
        ) {
            NavigationStack {
                ZStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(
                            localizedWalletFlowString(
                                "This wallet has an optional seed phrase password. Enter it after Face ID to reveal the recovery phrase.")
                        ).font(.subheadline).foregroundStyle(.secondary)
                        SecureField(localizedWalletFlowString("Wallet Password"), text: $seedPhrasePasswordInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().padding(14)
                            .spectraInputFieldStyle().foregroundStyle(Color.primary)
                        Button {
                            isShowingSeedPhrasePasswordPrompt = false
                            Task {
                                await revealSeedPhrase(password: seedPhrasePasswordInput)
                            }
                        } label: {
                            Text(localizedWalletFlowString("Reveal Seed Phrase")).font(.headline).frame(maxWidth: .infinity)
                        }.buttonStyle(.glassProminent).disabled(
                            seedPhrasePasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }.padding(20)
                }.navigationTitle(localizedWalletFlowString("Wallet Password")).navigationBarTitleDisplayMode(.inline).toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localizedWalletFlowString("Cancel")) {
                            isShowingSeedPhrasePasswordPrompt = false
                        }
                    }
                }
            }
        }.sheet(
            isPresented: $isShowingSeedPhraseSheet,
            onDismiss: {
                revealedSeedPhrase = ""
            }
        ) {
            NavigationStack {
                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(
                                localizedWalletFlowString(
                                    "Write this down and keep it offline. Anyone with this phrase can control your funds.")
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Text(revealedSeedPhrase).font(.body.monospaced()).foregroundStyle(Color.primary).privacySensitive().padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading).spectraInputFieldStyle(cornerRadius: 16)
                        }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                            .padding(20)
                    }
                }.navigationTitle(localizedWalletFlowString("Seed Phrase")).navigationBarTitleDisplayMode(.inline).toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localizedWalletFlowString("Done")) {
                            isShowingSeedPhraseSheet = false
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder
    private func holdingRow(_ holding: HoldingPresentation) -> some View {
        HStack(spacing: 12) {
            CoinBadge(
                assetIdentifier: holding.coin.iconIdentifier, fallbackText: holding.coin.mark, color: holding.coin.color, size: 34
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(holding.coin.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Text("\(holding.coin.symbol) • \(holding.coin.tokenStandard)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(holding.amountText).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).spectraNumericTextLayout()
                Text(holding.valueText).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
            }
        }.padding(.vertical, 4)
    }
    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizedWalletFlowString(label)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).foregroundStyle(Color.primary).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func revealSeedPhrase(password: String? = nil) async {
        guard !isRevealingSeedPhrase else { return }
        isRevealingSeedPhrase = true
        defer { isRevealingSeedPhrase = false }
        do {
            let phrase = try await store.revealSeedPhrase(for: wallet, password: password)
            revealedSeedPhrase = phrase
            seedPhrasePasswordInput = ""
            isShowingSeedPhraseSheet = true
        } catch {
            seedPhraseErrorMessage = error.localizedDescription
        }
    }
}
private struct WalletAdvancedDetailsView: View {
    let walletID: String
    let derivationPathsText: String?
    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        WalletDetailRow(label: "Wallet ID", value: walletID)
                        if let derivationPathsText { WalletDetailRow(label: "Derivation Paths", value: derivationPathsText) }
                    }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                }.padding(20)
            }
        }.navigationTitle(localizedWalletFlowString("Advanced")).navigationBarTitleDisplayMode(.inline)
    }
}
private struct WalletDetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizedWalletFlowString(label)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).foregroundStyle(Color.primary).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
func walletFlowLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
struct SeedPathSlotEditor: View {
    let title: String
    @Binding var path: String
    let defaultPath: String
    let presetOptions: [SeedDerivationPathPreset]
    private var segments: [DerivationPathSegment] {
        coreParseDerivationPath(rawPath: path) ?? coreParseDerivationPath(rawPath: defaultPath) ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
                Button(localizedWalletFlowString("Reset")) {
                    path = defaultPath
                }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("m").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(segments.indices, id: \.self) { index in
                        let segment = segments[index]
                        HStack(spacing: 4) {
                            Text(verbatim: "/").font(.caption.monospaced()).foregroundStyle(.secondary)
                            TextField(
                                "0",
                                text: Binding(
                                    get: { String(segment.value) }, set: { updateSegment(at: index, value: $0) }
                                )
                            ).keyboardType(.numberPad).font(.caption.monospaced()).foregroundStyle(Color.primary).padding(.horizontal, 10)
                                .padding(.vertical, 8).spectraInputFieldStyle(cornerRadius: 12)
                            if segment.isHardened {
                                Text(verbatim: "'").font(.caption.monospaced().weight(.bold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !presetOptions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedWalletFlowString("Derivation Paths")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(presetOptions) { preset in
                            Button {
                                path = preset.path
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(preset.title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(preset.detail).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(
                                        1
                                    ).truncationMode(.middle)
                                }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                                            preset.path == path ? Color.orange.opacity(0.16) : Color.white.opacity(0.04))
                                    ).overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(
                                            preset.path == path ? Color.orange.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1
                                        )
                                    )
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    private func updateSegment(at index: Int, value: String) {
        guard var resolvedSegments = coreParseDerivationPath(rawPath: path) ?? coreParseDerivationPath(rawPath: defaultPath),
            resolvedSegments.indices.contains(index), let numericValue = UInt32(value.filter(\.isNumber))
        else { return }
        resolvedSegments[index].value = numericValue
        path = coreDerivationPathString(segments: resolvedSegments)
    }
}
