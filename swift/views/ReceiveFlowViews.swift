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
    @State private var qrWallet: ImportedWallet? = nil
    @State private var currentStep: ReceiveFlowStep = .wallet
    @State private var flowDirection: Int = 1

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
        .sheet(item: $qrWallet) { wallet in
            ReceiveQRSheet(store: store, wallet: wallet)
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
            receivePageHeader(
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
            receivePageHeader(
                title: "Receive Address",
                subtitle: "Review the network, copy the address, or open the full QR screen.",
                systemImage: "qrcode"
            )

            receiveAddressHero
            receiveChainCard
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

    private var receiveChainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Network")).font(.headline)
            Picker(AppLocalization.string("Receive Chain"), selection: $store.receiveChainName) {
                ForEach(store.availableReceiveChains(for: store.receiveWalletID), id: \.self) { chain in
                    Text(chain).tag(chain)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: store.receiveChainName) { _, _ in
                store.syncReceiveAssetSelection()
                Task { await store.refreshReceiveAddress() }
            }

            if let coin = selectedCoin {
                HStack(spacing: 10) {
                    CoinBadge(
                        assetIdentifier: coin.iconIdentifier,
                        fallbackText: coin.symbol,
                        color: coin.color,
                        size: 28
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coin.symbol).font(.subheadline.weight(.semibold))
                        Text(coin.chainName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    private var receiveActionCard: some View {
        VStack(spacing: 10) {
            Button {
                guard let selectedWallet else { return }
                qrWallet = selectedWallet
            } label: {
                Label(AppLocalization.string("Open Full QR"), systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .spectraPressable()
            .disabled(selectedWallet == nil)

            Button {
                UIPasteboard.general.string = resolvedAddress
                spectraHaptic(.light)
            } label: {
                Label(AppLocalization.string("Copy Address"), systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .spectraPressable()
            .disabled(!canUseResolvedAddress || store.isResolvingReceiveAddress)
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
                        guard let selectedWallet else { return }
                        qrWallet = selectedWallet
                    }
                } label: {
                    Label(
                        AppLocalization.string(currentStep == .wallet ? "Continue" : "Show QR"),
                        systemImage: currentStep == .wallet ? "chevron.right" : "qrcode"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.glassProminent)
                .spectraPressable()
                .disabled(store.receiveEnabledWallets.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
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
        "\(currentStep.rawValue)|\(store.receiveWalletID)|\(store.receiveChainName)|\(store.receiveHoldingKey)"
    }

    private func receivePageHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(title)).font(.title2.weight(.bold))
                Text(AppLocalization.string(subtitle)).font(.subheadline).foregroundStyle(.secondary)
            }
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
                receiveQRCodePlaceholder(size: 256)
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
                receiveAddressPlaceholder
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
