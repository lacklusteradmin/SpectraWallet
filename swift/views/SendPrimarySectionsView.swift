import Foundation
import SwiftUI
import VisionKit

@MainActor
fileprivate struct SendComposerPresentation {
    let sendWallets: [ImportedWallet]
    let selectedWallet: ImportedWallet?
    let availableSendCoins: [Coin]
    let selectedCoin: Coin?
    let selectedCoinAmountText: String?
    let selectedCoinApproximateFiatText: String?
    let addressBookEntries: [AddressBookEntry]

    init(store: AppState) {
        sendWallets = store.sendEnabledWallets
        selectedWallet = sendWallets.first(where: { $0.id == store.sendWalletID })
        availableSendCoins = store.availableSendCoins(for: store.sendWalletID)
        selectedCoin = availableSendCoins.first(where: { $0.holdingKey == store.sendHoldingKey })
        selectedCoinAmountText = selectedCoin.map { store.formattedAssetAmount($0.amount, symbol: $0.symbol, chainName: $0.chainName) }
        let sendAmount = Double(store.sendAmount) ?? 0
        if let selectedCoin, !sendAmount.isZero {
            selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol)
        } else {
            selectedCoinApproximateFiatText = nil
        }
        addressBookEntries = store.sendAddressBookEntries
    }
}

@MainActor
struct SendFromPage: View {
    @Bindable var store: AppState
    @ScaledMetric(relativeTo: .body) private var chipWidth = 142.0

    private var presentation: SendComposerPresentation { SendComposerPresentation(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Choose Asset",
                subtitle: "Pick the wallet and asset to send from.",
                systemImage: "creditcard.fill"
            )

            fromCard
        }
    }

    private var fromCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppLocalization.string("From")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if presentation.sendWallets.count > 1 {
                    Picker("", selection: $store.sendWalletID) {
                        ForEach(presentation.sendWallets) { wallet in Text(wallet.name).tag(wallet.id) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: store.sendWalletID) { _, _ in store.syncSendAssetSelection() }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if let selectedWallet = presentation.selectedWallet {
                let badge = Coin.nativeChainBadge(chainName: selectedWallet.selectedChain) ?? (nil, Color.mint)
                HStack(spacing: 12) {
                    CoinBadge(
                        assetIdentifier: badge.assetIdentifier,
                        fallbackText: selectedWallet.selectedChain,
                        color: badge.color,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedWallet.name).font(.headline)
                        Text(selectedWallet.selectedChain).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if !presentation.availableSendCoins.isEmpty {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppLocalization.string("Assets")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in
                                coinChip(coin: coin, isSelected: coin.holdingKey == store.sendHoldingKey)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }

    private func coinChip(coin: Coin, isSelected: Bool) -> some View {
        Button {
            guard !isSelected else { return }
            store.sendHoldingKey = coin.holdingKey
            spectraHaptic(.light)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CoinBadge(
                        assetIdentifier: coin.iconIdentifier,
                        fallbackText: coin.symbol,
                        color: coin.color,
                        size: 28
                    )
                    Text(coin.symbol).font(.headline)
                }
                Text(store.formattedAssetAmount(coin.amount, symbol: coin.symbol, chainName: coin.chainName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .spectraNumericTextLayout()
            }
            .frame(width: chipWidth, alignment: .leading)
            .padding(14)
            .background(
                isSelected
                    ? coin.color.opacity(0.18)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: SpectraLayout.Radius.input, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SpectraLayout.Radius.input, style: .continuous)
                    .strokeBorder(isSelected ? coin.color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct SendRecipientPage: View {
    @Bindable var store: AppState
    @Binding var selectedAddressBookEntryID: String
    @Binding var isShowingQRScanner: Bool
    @Binding var qrScannerErrorMessage: String?
    let validationError: String?
    let isValidating: Bool
    let isValidated: Bool
    let retryValidation: () -> Void
    @FocusState private var addressFocused: Bool

    private var presentation: SendComposerPresentation { SendComposerPresentation(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Recipient",
                subtitle: "Enter a destination address or scan a QR code.",
                systemImage: "person.crop.circle.badge.arrow.forward.fill"
            )

            toCard
        }
    }

    private var toCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("To")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: 10) {
                TextField(AppLocalization.string("Recipient address"), text: $store.sendAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
                    .focused($addressFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.chip)

                Button {
                    guard DataScannerViewController.isSupported else {
                        qrScannerErrorMessage = AppLocalization.string("QR scanning is not supported on this device.")
                        return
                    }
                    guard DataScannerViewController.isAvailable else {
                        qrScannerErrorMessage = AppLocalization.string(
                            "QR scanning is unavailable right now. Check camera permission and try again.")
                        return
                    }
                    isShowingQRScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(AppLocalization.string("Scan QR Code"))
            }

            if !presentation.addressBookEntries.isEmpty {
                Picker(AppLocalization.string("Saved Recipient"), selection: $selectedAddressBookEntryID) {
                    Text(AppLocalization.string("None")).tag("")
                    ForEach(presentation.addressBookEntries) { entry in
                        Text("\(entry.name) · \(entry.chainName)").tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.subheadline)
                .onChange(of: selectedAddressBookEntryID) { _, newValue in
                    guard let entry = presentation.addressBookEntries.first(where: { $0.id == newValue }) else { return }
                    store.sendAddress = entry.address
                }
            }

            if isValidating {
                ProgressView(AppLocalization.string("Checking recipient..."))
            } else if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.red)
                Button(AppLocalization.string("Retry"), action: retryValidation).buttonStyle(.glass)
            } else if isValidated {
                Label(AppLocalization.string("Address format verified for this network"), systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            recipientMessages
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill()
    }

    @ViewBuilder
    private var recipientMessages: some View {
        if let qrScannerErrorMessage {
            Label(qrScannerErrorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }

        if presentation.selectedCoin?.chainName == "Litecoin",
           store.sendAddress.hasPrefix("ltcmweb1") || store.sendAddress.hasPrefix("tmweb1") {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.caption2.weight(.semibold))
                Text(AppLocalization.string("MWEB · Privacy Send")).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing).opacity(0.9)
            )
            .clipShape(.capsule)
        }

        if store.isCheckingSendDestinationBalance {
            SpectraLoadingRow(title: "Checking destination on-chain balance...")
        }

        if let warning = store.sendDestinationRiskWarning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }

        if let info = store.sendDestinationInfoMessage {
            Text(info).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct SendAmountPage: View {
    @Bindable var store: AppState
    let quoteIsCurrent: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: SendComposerPresentation { SendComposerPresentation(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Amount",
                subtitle: "Set the amount and compare it against your available balance.",
                systemImage: "number.circle.fill"
            )

            amountCard
        }
    }

    private var amountCard: some View {
        VStack(spacing: 16) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))) {
                TextField("0", text: $store.sendAmount)
                    .keyboardType(.decimalPad)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityLabel(AppLocalization.string("Amount"))
                    .multilineTextAlignment(.trailing)
                    .spectraNumericTextLayout()
                    .frame(maxWidth: .infinity)

                if let selectedCoin = presentation.selectedCoin {
                    Text(selectedCoin.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selectedCoin.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(selectedCoin.color)
                }
            }

            if let fiatText = presentation.selectedCoinApproximateFiatText {
                Text("≈ \(fiatText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .spectraNumericTextLayout()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Balance")).font(.caption).foregroundStyle(.secondary)
                    if let amountText = presentation.selectedCoinAmountText {
                        Text(amountText)
                            .font(.subheadline.weight(.semibold))
                            .spectraNumericTextLayout()
                    }
                }
                Spacer()
                if quoteIsCurrent, let maximum = store.sendShortcutAmount(percentage: 100), let coin = presentation.selectedCoin {
                    Text(AppLocalization.format("Estimated maximum: %@ %@", maximum, coin.symbol))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(AppLocalization.string("A fee estimate is required for amount shortcuts. Enter an amount to continue."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !store.sendAmount.isEmpty && !store.sendAmountIsValid {
                    Text(AppLocalization.string("Enter a positive decimal amount within this asset's precision."))
                        .font(.subheadline).foregroundStyle(.red)
                }
                if let selectedCoin = presentation.selectedCoin, selectedCoin.amount > 0 {
                    HStack(spacing: 6) {
                        ForEach([UInt32(10), 50, 100], id: \.self) { percentage in
                            percentButton(percentage: percentage)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .spectraElevatedFill()
    }

    private func percentButton(percentage: UInt32) -> some View {
        let amount = quoteIsCurrent ? store.sendShortcutAmount(percentage: percentage) : nil
        return Button {
            guard let amount else { return }
            store.sendAmount = amount
            spectraHaptic(.light)
        } label: {
            Text(percentage == 100 ? "MAX" : "\(percentage)%")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(amount == nil)
        .accessibilityLabel(percentage == 100
            ? AppLocalization.string("Maximum after estimated fees")
            : AppLocalization.format("%lld percent of estimated maximum", Int(percentage)))
    }
}
