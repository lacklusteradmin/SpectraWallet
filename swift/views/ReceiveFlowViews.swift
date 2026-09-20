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

    private var selectedWallet: WalletView? {
        store.receiveEnabledWallets.first(where: { $0.id == store.receiveWalletID })
    }

    private var selectedCoin: Coin? {
        store.selectedReceiveCoin(for: store.receiveWalletID)
    }

    private var resolvedAddress: String {
        store.receiveResolvedAddress
    }

    private var canUseResolvedAddress: Bool {
        !resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isResolvingReceiveAddress
    }

    /// The QR as an image, for sharing and saving. `nil` until an address
    /// resolves, which is what disables both buttons.
    private var qrImage: UIImage? {
        let address = resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return canUseResolvedAddress ? QRCodeRenderer.makeImage(from: address) : nil
    }

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    receiveProgress
                    stepContent
                        .id(currentStep)
                        .transition(stepTransition)
                }
                .padding(20)

            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) { receiveBottomBar }
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
                    in: RoundedRectangle(cornerRadius: SpectraLayout.Radius.pill, style: .continuous)
                )
            }
        }
        .padding(6)
        .spectraCardFill(cornerRadius: SpectraLayout.Radius.compact)
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
                        WalletReceiveCard(
                            wallet: wallet,
                            isSelected: wallet.id == store.receiveWalletID
                        ) {
                            select(wallet)
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
            if let coin {
                Label(coin.chainName, systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(AppLocalization.format("Receive only %@ assets on this network. Check the sender's network before transferring.", coin.chainName))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            if canUseResolvedAddress {
                QRCodeImage(address: resolvedAddress)
                    .frame(width: 184, height: 184)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: SpectraLayout.Radius.card, style: .continuous))
            } else {
                receiveQRCodePlaceholder(size: 216)
            }

            HStack(spacing: 12) {
                if let coin {
                    CoinBadge(
                        artworkName: coin.artworkName,
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

            Text(canUseResolvedAddress ? resolvedAddress : (store.receiveAddressError ?? AppLocalization.string("Loading receive address…")))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .spectraElevatedFill()
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
        .spectraCardFill()
    }

    private var receiveBottomBar: some View {
        SpectraBottomActionBar {
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
            }

            Button {
                switch currentStep {
                case .wallet:
                    spectraHaptic(.light)
                    go(to: .address)
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
                .frame(minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(isPrimaryActionDisabled)
        }
    }

    private var copyStepSystemImage: String {
        if currentStep == .wallet { return "chevron.right" }
        return didCopy ? "checkmark" : "doc.on.doc"
    }

    private var isPrimaryActionDisabled: Bool {
        switch currentStep {
        case .wallet: return selectedWallet == nil
        case .address: return !canUseResolvedAddress
        }
    }

    private func select(_ wallet: WalletView) {
        guard store.receiveWalletID != wallet.id else { return }
        spectraHaptic(.light)
        store.receiveWalletID = wallet.id
        store.syncReceiveAssetSelection()
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

/// A row on the wallet step. The whole card is the selection control, and
/// selecting is all it does.
///
/// It used to show `wallet.addresses[slot]` with a copy button beside it — a
/// second receive address, produced differently from the one the next screen
/// hands out. That one is core's `receive_address`, which on a UTXO chain
/// reserves a keypool index (never 0) and registers what it derives as owned,
/// so wherever core could derive, the card offered an address core does not
/// watch. Receive addresses come from core; this row picks a wallet.
private struct WalletReceiveCard: View {
    let wallet: WalletView
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, Color.mint)

        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    CoinBadge(
                        artworkName: badge.artworkName,
                        fallbackText: wallet.selectedChain,
                        color: badge.color,
                        size: 42
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(badge.color)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .light ? 1 : 0.88)))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallet.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(wallet.selectedChain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(isSelected ? badge.color.opacity(0.14) : SpectraLayout.GlassTint.elevated),
                in: .rect(cornerRadius: SpectraLayout.Radius.compact)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: SpectraLayout.Radius.compact, style: .continuous)
                        .stroke(badge.color.opacity(0.9), lineWidth: 1.8)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// `SpectraLoadingGlyph` and `SpectraShimmer` carry `@State`, so their
/// memberwise initializers are main-actor isolated; a nonisolated free
/// function cannot call them.
@MainActor private func receiveQRCodePlaceholder(size: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: SpectraLayout.Radius.hero, style: .continuous)
            .fill(Color.white.opacity(0.82))
        VStack(spacing: 14) {
            SpectraLoadingGlyph(size: 42, tint: .orange)
            VStack(spacing: 8) {
                SpectraShimmer(height: 14)
                    .frame(width: size * 0.58)
                SpectraShimmer(height: 14)
                    .frame(width: size * 0.42)
            }
        }
    }
    .frame(width: size, height: size)
}
