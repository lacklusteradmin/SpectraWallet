import Foundation
import SwiftUI
import VisionKit
struct SendPrimarySectionsView: View {
    @Bindable var store: AppState
    @Binding var selectedAddressBookEntryID: String
    @Binding var isShowingQRScanner: Bool
    @Binding var qrScannerErrorMessage: String?
    private struct Presentation {
        let sendWallets: [ImportedWallet]
        let selectedWallet: ImportedWallet?
        let availableSendCoins: [Coin]
        let selectedCoin: Coin?
        let selectedCoinAmountText: String?
        let selectedCoinApproximateFiatText: String?
        let addressBookEntries: [AddressBookEntry]
    }
    private var presentation: Presentation {
        let sendWallets = store.sendEnabledWallets
        let selectedWallet = sendWallets.first(where: { $0.id == store.sendWalletID })
        let availableSendCoins = store.availableSendCoins(for: store.sendWalletID)
        let selectedCoin = availableSendCoins.first(where: { $0.holdingKey == store.sendHoldingKey })
        let selectedCoinAmountText = selectedCoin.map { store.formattedAssetAmount($0.amount, symbol: $0.symbol, chainName: $0.chainName) }
        let sendAmount = Double(store.sendAmount) ?? 0
        let selectedCoinApproximateFiatText: String?
        if let selectedCoin, !sendAmount.isZero {
            selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol)
        } else {
            selectedCoinApproximateFiatText = nil
        }
        return Presentation(
            sendWallets: sendWallets, selectedWallet: selectedWallet, availableSendCoins: availableSendCoins, selectedCoin: selectedCoin,
            selectedCoinAmountText: selectedCoinAmountText, selectedCoinApproximateFiatText: selectedCoinApproximateFiatText,
            addressBookEntries: store.sendAddressBookEntries
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sendSummarySection
            walletAssetSection
            recipientSection
            amountSection
        }
    }
    private var sendSummarySection: some View {
        spectraDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let selectedCoin = presentation.selectedCoin {
                        CoinBadge(
                            assetIdentifier: selectedCoin.iconIdentifier, fallbackText: selectedCoin.symbol, color: selectedCoin.color,
                            size: 42
                        )
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill").font(.system(size: 38)).foregroundStyle(.mint)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Send")).font(.title3.weight(.bold))
                        if let wallet = presentation.selectedWallet { Text(wallet.name).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let selectedCoin = presentation.selectedCoin {
                        Text(selectedCoin.symbol).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6).background(
                            selectedCoin.color.opacity(0.18), in: Capsule()
                        ).foregroundStyle(selectedCoin.color)
                    }
                }
                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalization.string("Available")).font(.caption).foregroundStyle(.secondary)
                            Text(presentation.selectedCoinAmountText ?? "").font(.headline.weight(.semibold)).spectraNumericTextLayout()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(AppLocalization.string("Network")).font(.caption).foregroundStyle(.secondary)
                            Text(selectedCoin.chainName).font(.subheadline.weight(.semibold))
                        }
                    }
                } else {
                    Text(AppLocalization.string("Choose a wallet and asset to prepare a transfer with live fee previews and risk checks."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var walletAssetSection: some View {
        spectraDetailCard(title: "Wallet & Asset") {
            VStack(alignment: .leading, spacing: 12) {
                Picker(AppLocalization.string("Wallet"), selection: $store.sendWalletID) {
                    ForEach(presentation.sendWallets) { wallet in Text(wallet.name).tag(wallet.id) }
                }.onChange(of: store.sendWalletID) { _, _ in
                    store.syncSendAssetSelection()
                }
                Picker(AppLocalization.string("Asset"), selection: $store.sendHoldingKey) {
                    ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in
                        Text("\(coin.name) on \(store.displayChainTitle(for: coin.chainName))").tag(coin.holdingKey)
                    }
                }
            }
        }
    }
    private var recipientSection: some View {
        spectraDetailCard(title: "Recipient") {
            VStack(alignment: .leading, spacing: 12) {
                if !presentation.addressBookEntries.isEmpty {
                    Picker(AppLocalization.string("Saved Recipient"), selection: $selectedAddressBookEntryID) {
                        Text(AppLocalization.string("None")).tag("")
                        ForEach(presentation.addressBookEntries) { entry in
                            Text("\(entry.name) • \(entry.chainName)").tag(entry.id.uuidString)
                        }
                    }.onChange(of: selectedAddressBookEntryID) { _, newValue in
                        guard let selectedEntry = presentation.addressBookEntries.first(where: { $0.id.uuidString == newValue }) else {
                            return
                        }
                        store.sendAddress = selectedEntry.address
                    }
                }
                HStack(spacing: 10) {
                    TextField(AppLocalization.string("Recipient address"), text: $store.sendAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().padding(.horizontal, 12).padding(.vertical, 10).glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 14))
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
                        Image(systemName: "qrcode.viewfinder").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                    }.buttonStyle(.glass).accessibilityLabel(AppLocalization.string("Scan QR Code"))
                }
                if let qrScannerErrorMessage { Text(qrScannerErrorMessage).font(.caption).foregroundStyle(.orange) }
                if presentation.selectedCoin?.chainName == "Litecoin",
                   store.sendAddress.hasPrefix("ltcmweb1") || store.sendAddress.hasPrefix("tmweb1") {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill").font(.caption2.weight(.semibold))
                        Text("MWEB · Privacy Send").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing).opacity(0.9))
                    .clipShape(.capsule)
                }
                if store.isCheckingSendDestinationBalance {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(AppLocalization.string("Checking destination on-chain balance...")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let sendDestinationRiskWarning = store.sendDestinationRiskWarning {
                    Text(sendDestinationRiskWarning).font(.caption).foregroundStyle(.orange)
                }
                if let sendDestinationInfoMessage = store.sendDestinationInfoMessage {
                    Text(sendDestinationInfoMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var amountSection: some View {
        spectraDetailCard(title: "Amount") {
            VStack(alignment: .leading, spacing: 12) {
                TextField(AppLocalization.string("Amount"), text: $store.sendAmount).keyboardType(.decimalPad).padding(.horizontal, 12)
                    .padding(.vertical, 10).glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 14))
                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        Text(AppLocalization.string("Using")).foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedCoin.symbol).font(.subheadline.weight(.semibold))
                    }
                    if let fiatAmount = presentation.selectedCoinApproximateFiatText {
                        HStack {
                            Text(AppLocalization.string("Approx. Value")).foregroundStyle(.secondary)
                            Spacer()
                            Text(fiatAmount).font(.subheadline.weight(.semibold)).spectraNumericTextLayout()
                        }
                    }
                }
            }
        }
    }
}
