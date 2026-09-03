import Foundation
import SwiftUI
import UIKit

private enum ReceiveFlowStep: Int, CaseIterable, Identifiable {
    case wallet
    case address

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .wallet: return "Wallet"
        case .address: return "Address"
        }
    }

    var systemImage: String {
        switch self {
        case .wallet: return "wallet.pass.fill"
        case .address: return "qrcode"
        }
    }
}

struct ReceiveView: View {
    @Bindable var store: AppState
    @State private var currentStep: ReceiveFlowStep = .wallet
    @State private var flowDirection: Int = 1
    @State private var didCopy: Bool = false
    @State private var isShowingShareSheet: Bool = false
    @State private var qrExportMessage: String?
    @State private var qrImageSaver: PhotoLibraryImageSaver?

    private var selectedWallet: ImportedWallet? {
        store.receiveEnabledWallets.first(where: { $0.id == store.receiveWalletID })
    }

    private var selectedCoin: Coin? {
        store.selectedReceiveCoin(for: store.receiveWalletID)
    }

    private var resolvedAddress: String {
        store.receiveAddress()
    }

    private var canUseResolvedAddress: Bool {
        !resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resolvedAddress != AppLocalization.string("Select a wallet and chain")
    }

    /// The QR as an image, for sharing and saving. `nil` until an address
    /// resolves, which is what disables both buttons.
    private var qrImage: UIImage? {
        let address = resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return canUseResolvedAddress ? QRCodeRenderer.makeImage(from: address) : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    receiveProgress
                    stepContent
                        .id(currentStep)
                        .transition(stepTransition)
                }
                .padding(20)
                .padding(.bottom, 96)
            }

            receiveBottomBar
        }
        .navigationTitle(AppLocalization.string(currentStep.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.cancelReceive()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(AppLocalization.string("Close"))
            }
        }
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
        .task(id: receiveRefreshKey) {
            guard currentStep == .address else { return }
            await store.refreshReceiveAddress()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .wallet:
            walletStep
        case .address:
            addressStep
        }
    }

    private var receiveProgress: some View {
        HStack(spacing: 8) {
            ForEach(ReceiveFlowStep.allCases) { step in
                HStack(spacing: 6) {
                    Image(systemName: step.systemImage)
                        .font(.caption.weight(.semibold))
                    Text(AppLocalization.string(step.title))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .primary : .tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    step == currentStep ? Color.orange.opacity(0.18) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        }
        .padding(6)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 22))
    }

    private var stepTransition: AnyTransition {
        let insertionEdge: Edge = flowDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = flowDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var walletStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Choose Wallet",
                subtitle: "Pick where the incoming transfer should land.",
                systemImage: "wallet.pass.fill"
            )

            if store.receiveEnabledWallets.isEmpty {
                SpectraEmptyStateCard(
                    title: "No receive wallets",
                    message: "Import a wallet to generate receive addresses.",
                    systemImage: "wallet.pass"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.receiveEnabledWallets) { wallet in
                        WalletReceiveCard(wallet: wallet) {
                            choose(wallet)
                        }
                    }
                }
            }
        }
    }

    private var addressStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Receive Address",
                subtitle: "Scan the code, or copy the address to share it.",
                systemImage: "qrcode"
            )

            receiveAddressHero
            receiveActionCard
        }
    }

    private var receiveAddressHero: some View {
        let wallet = selectedWallet
        let coin = selectedCoin
        return VStack(spacing: 16) {
            if canUseResolvedAddress {
                QRCodeImage(address: resolvedAddress)
                    .frame(width: 184, height: 184)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                receiveQRCodePlaceholder(size: 216)
            }

            HStack(spacing: 12) {
                if let coin {
                    CoinBadge(
                        assetIdentifier: coin.iconIdentifier,
                        fallbackText: coin.symbol,
                        color: coin.color,
                        size: 36
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet?.name ?? AppLocalization.string("Wallet"))
                        .font(.headline)
                    Text(coin.map { "\($0.symbol) · \($0.chainName)" } ?? AppLocalization.string("Select a chain"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(resolvedAddress)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }

    /// Share and save. Copy is the bottom bar's primary action rather than a
    /// third button here — it is the one thing nearly every visit is for.
    ///
    /// These two used to be the only reason to open a second screen: a full-QR
    /// sheet showing the same code, the same wallet and chain, and the same
    /// address this one already shows, reachable from two buttons that did the
    /// same thing ("Open Full QR" here, "Show QR" in the bottom bar).
    private var receiveActionCard: some View {
        VStack(spacing: 10) {
            Button {
                guard qrImage != nil else { return }
                isShowingShareSheet = true
            } label: {
                Label(AppLocalization.string("Share QR Code"), systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .spectraPressable()
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
            .spectraPressable()
            .disabled(qrImage == nil)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    private var receiveBottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)
            HStack(spacing: 12) {
                if currentStep == .address {
                    Button {
                        spectraHaptic(.light)
                        go(to: .wallet)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.glass)
                    .spectraPressable()
                }

                Button {
                    switch currentStep {
                    case .wallet:
                        if selectedWallet == nil, let first = store.receiveEnabledWallets.first {
                            choose(first)
                        } else {
                            go(to: .address)
                        }
                    case .address:
                        UIPasteboard.general.string = resolvedAddress
                        didCopy = true
                        spectraHaptic(.light)
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            didCopy = false
                        }
                    }
                } label: {
                    Label(
                        AppLocalization.string(currentStep == .wallet ? "Continue" : "Copy Address"),
                        systemImage: copyStepSystemImage
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.glassProminent)
                .spectraPressable()
                .disabled(isPrimaryActionDisabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private var copyStepSystemImage: String {
        if currentStep == .wallet { return "chevron.right" }
        return didCopy ? "checkmark" : "doc.on.doc"
    }

    private var isPrimaryActionDisabled: Bool {
        if store.receiveEnabledWallets.isEmpty { return true }
        guard currentStep == .address else { return false }
        return !canUseResolvedAddress || store.isResolvingReceiveAddress
    }

    private func choose(_ wallet: ImportedWallet) {
        store.receiveWalletID = wallet.id
        store.syncReceiveAssetSelection()
        spectraHaptic(.light)
        go(to: .address)
    }

    private func go(to step: ReceiveFlowStep) {
        flowDirection = step.rawValue >= currentStep.rawValue ? 1 : -1
        withAnimation(.snappy(duration: 0.28)) {
            currentStep = step
        }
    }

    private var receiveRefreshKey: String {
        "\(currentStep.rawValue)|\(store.receiveWalletID)|\(store.receiveHoldingKey)"
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

    /// The address stored for the wallet's own chain.
    private func walletStaticAddress(for wallet: ImportedWallet) -> String? {
        let trimmed =
            wallet.address(forChainNamed: wallet.selectedChain)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func receiveQRCodePlaceholder(size: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.82))
        VStack(spacing: 14) {
            SpectraLoadingGlyph(size: 42, tint: .orange)
            VStack(spacing: 8) {
                SpectraShimmer(cornerRadius: 6, height: 14)
                    .frame(width: size * 0.58)
                SpectraShimmer(cornerRadius: 6, height: 14)
                    .frame(width: size * 0.42)
            }
        }
    }
    .frame(width: size, height: size)
}

private var receiveAddressPlaceholder: some View {
    VStack(alignment: .leading, spacing: 8) {
        SpectraLoadingRow(title: "Resolving receive address...")
        SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: .infinity)
        SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: .infinity)
        SpectraShimmer(cornerRadius: 5, height: 13).frame(maxWidth: 180, alignment: .leading)
    }
}
