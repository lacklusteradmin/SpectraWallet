import Foundation
import SwiftUI
import VisionKit
private func localizedSendString(_ key: String) -> String {
    AppLocalization.string(key)
}
struct SendView: View {
    @ObservedObject var store: AppState
    @ObservedObject var sendPreviewStore: SendPreviewStore
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?
    init(store: AppState) {
        self.store = store
        self.sendPreviewStore = store.sendPreviewStore
    }
    private func localized(_ key: String) -> String { localizedSendString(key) }
    private var sendAdvancedModeBinding: Binding<Bool> {
        Binding(get: { store.sendAdvancedMode }, set: { store.sendAdvancedMode = $0 })
    }
    private var sendUTXOMaxInputCountBinding: Binding<Int> {
        Binding(get: { store.sendUTXOMaxInputCount }, set: { store.sendUTXOMaxInputCount = $0 })
    }
    private var sendEnableRBFBinding: Binding<Bool> {
        Binding(get: { store.sendEnableRBF }, set: { store.sendEnableRBF = $0 })
    }
    private var sendEnableCPFPBinding: Binding<Bool> {
        Binding(get: { store.sendEnableCPFP }, set: { store.sendEnableCPFP = $0 })
    }
    private var sendLitecoinChangeStrategyBinding: Binding<LitecoinChangeStrategy> {
        Binding(get: { store.sendLitecoinChangeStrategy }, set: { store.sendLitecoinChangeStrategy = $0 })
    }
    private var useCustomEthereumFeesBinding: Binding<Bool> {
        Binding(get: { store.useCustomEthereumFees }, set: { store.useCustomEthereumFees = $0 })
    }
    private var customEthereumMaxFeeGweiBinding: Binding<String> {
        Binding(get: { store.customEthereumMaxFeeGwei }, set: { store.customEthereumMaxFeeGwei = $0 })
    }
    private var customEthereumPriorityFeeGweiBinding: Binding<String> {
        Binding(get: { store.customEthereumPriorityFeeGwei }, set: { store.customEthereumPriorityFeeGwei = $0 })
    }
    private var ethereumManualNonceEnabledBinding: Binding<Bool> {
        Binding(get: { store.ethereumManualNonceEnabled }, set: { store.ethereumManualNonceEnabled = $0 })
    }
    private var ethereumManualNonceBinding: Binding<String> {
        Binding(get: { store.ethereumManualNonce }, set: { store.ethereumManualNonce = $0 })
    }
    private var isSendBusy: Bool {
        store.isSendingBitcoin
            || store.isSendingBitcoinCash
            || store.isSendingBitcoinSV
            || store.isSendingLitecoin
            || store.isSendingEthereum
            || store.isSendingDogecoin
            || store.isSendingTron
            || store.isSendingSolana
            || store.isSendingXRP
            || store.isSendingStellar
            || store.isSendingMonero
            || store.isSendingCardano
            || store.isSendingSui
            || store.isSendingAptos
            || store.isSendingTON
            || store.isSendingICP
            || store.isSendingNear
            || store.isSendingPolkadot
            || store.isPreparingEthereumSend
            || store.isPreparingDogecoinSend
            || store.isPreparingTronSend
            || store.isPreparingSolanaSend
            || store.isPreparingXRPSend
            || store.isPreparingStellarSend
            || store.isPreparingMoneroSend
            || store.isPreparingCardanoSend
            || store.isPreparingSuiSend
            || store.isPreparingAptosSend
            || store.isPreparingTONSend
            || store.isPreparingICPSend
            || store.isPreparingNearSend
            || store.isPreparingPolkadotSend
    }
    private var selectedNetworkSendCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }
    @ViewBuilder
    private var sendStatusSections: some View {
        if let sendError = store.sendError {
            sendDetailCard {
                Text(sendError).font(.caption).foregroundStyle(.red)
            }}
        if let sendVerificationNotice = store.sendVerificationNotice {
            sendDetailCard(title: "Verification") {
                Text(sendVerificationNotice).font(.caption).foregroundStyle(store.sendVerificationNoticeIsWarning ? .red : .orange)
            }}
        if let lastSentTransaction = store.lastSentTransaction {
            sendDetailCard(title: "Last Sent") {
                Text("\(lastSentTransaction.symbol) sent to \(lastSentTransaction.addressPreviewText)").font(.subheadline)
                HStack {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TransactionStatusBadge(status: lastSentTransaction.status)
                }
                if let pendingTransactionRefreshStatusText = store.pendingTransactionRefreshStatusText { Text(pendingTransactionRefreshStatusText).font(.caption2).foregroundStyle(.secondary) }
                if let transactionHash = lastSentTransaction.transactionHash { Text(transactionHash).font(.caption2.monospaced()).textSelection(.enabled) }
                if let transactionExplorerURL = lastSentTransaction.transactionExplorerURL, let transactionExplorerLabel = lastSentTransaction.transactionExplorerLabel {
                    Link(destination: transactionExplorerURL) {
                        Label(transactionExplorerLabel, systemImage: "safari").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.glassProminent)
                }
                Button {
                    store.saveLastSentRecipientToAddressBook()
                } label: {
                    Label(
                        store.canSaveLastSentRecipientToAddressBook() ? localized("Save Recipient To Address Book") : localized("Recipient Already Saved"), systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                    ).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.disabled(!store.canSaveLastSentRecipientToAddressBook())
            }}
        optionalSendingSection(store.isSendingBitcoin, localized("Broadcasting Bitcoin transaction..."))
        optionalSendingSection(store.isSendingBitcoinCash, localized("Broadcasting Bitcoin Cash transaction..."))
        optionalSendingSection(store.isSendingBitcoinSV, localized("Broadcasting Bitcoin SV transaction..."))
        optionalSendingSection(store.isSendingLitecoin, localized("Broadcasting Litecoin transaction..."))
        optionalSendingSection(store.isSendingEthereum, localized("Broadcasting \(store.selectedSendCoin?.chainName ?? "EVM") transaction..."))
        optionalSendingSection(store.isSendingDogecoin, localized("Broadcasting Dogecoin transaction..."))
        optionalSendingSection(store.isSendingTron, localized("Broadcasting Tron transaction..."))
        optionalSendingSection(store.isSendingSolana, localized("Broadcasting Solana transaction..."))
        optionalSendingSection(store.isSendingXRP, localized("Broadcasting XRP transaction..."))
        optionalSendingSection(store.isSendingStellar, localized("Broadcasting Stellar transaction..."))
        optionalSendingSection(store.isSendingMonero, localized("Broadcasting Monero transaction..."))
        optionalSendingSection(store.isSendingCardano, localized("Broadcasting Cardano transaction..."))
        optionalSendingSection(store.isSendingSui, localized("Broadcasting Sui transaction..."))
        optionalSendingSection(store.isSendingAptos, localized("Broadcasting Aptos transaction..."))
        optionalSendingSection(store.isSendingTON, localized("Broadcasting TON transaction..."))
        optionalSendingSection(store.isSendingICP, localized("Broadcasting Internet Computer transaction..."))
        optionalSendingSection(store.isSendingNear, localized("Broadcasting NEAR transaction..."))
        optionalSendingSection(store.isSendingPolkadot, localized("Broadcasting Polkadot transaction..."))
    }
    @ViewBuilder
    private func optionalSendingSection(_ isActive: Bool, _ message: String) -> some View {
        if isActive { sendingSection(message) }}
    private func sendingSection(_ title: String) -> some View {
        sendDetailCard {
            HStack(spacing: 10) {
                ProgressView()
                Text(title).font(.caption)
            }}}
    private static let networkSendChainNames: Set<String> = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "XRP Ledger", "Monero", "Cardano", "Sui", "Aptos", "TON", "NEAR", "Polkadot", "Stellar", "Internet Computer"
    ]
    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        coin.map { Self.networkSendChainNames.contains($0.chainName) } ?? false
    }
    private func chainFeePriorityBinding(for chainName: String) -> Binding<ChainFeePriorityOption> {
        Binding(
            get: { store.feePriorityOption(for: chainName) }, set: { store.setFeePriorityOption($0, for: chainName) }
        )
    }
    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        if coin.chainName == "Litecoin" { return store.litecoinSendPreview }
        if coin.chainName == "Bitcoin Cash" { return store.bitcoinCashSendPreview }
        return store.bitcoinSendPreview
    }
    private func utxoAdvancedModeCaption(for chainName: String) -> String? {
        switch chainName {
        case "Bitcoin":
            return localized("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        case "Bitcoin Cash":
            return localized("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
        case "Dogecoin":
            return localized("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        default:
            return nil
        }
    }
    private func evmFeeSymbol(for chainName: String) -> String {
        switch chainName {
        case "BNB Chain": return "BNB"
        case "Ethereum Classic": return "ETC"
        case "Avalanche": return "AVAX"
        case "Hyperliquid": return "HYPE"
        default: return "ETH"
        }
    }
    private func formattedPreviewAssetAmount(_ amount: Double, for coin: Coin) -> String { store.formattedAssetAmount(amount, symbol: coin.symbol, chainName: coin.chainName) }
    @ViewBuilder
    private func sendPreviewDetailsSection(for selectedCoin: Coin) -> some View {
        if let details = store.sendPreviewDetails(for: selectedCoin), details.hasVisibleContent {
            Section(localized("Preview Details")) {
                if let spendableBalance = details.spendableBalance { Text("Spendable Balance: \(formattedPreviewAssetAmount(spendableBalance, for: selectedCoin))") }
                if let feeRateDescription = details.feeRateDescription { Text("Fee Rate: \(feeRateDescription)") }
                if let estimatedTransactionBytes = details.estimatedTransactionBytes { Text("Estimated Size: \(estimatedTransactionBytes) bytes") }
                if let selectedInputCount = details.selectedInputCount { Text("Selected Inputs: \(selectedInputCount)") }
                if let usesChangeOutput = details.usesChangeOutput {
                    let changeOutputLabel = usesChangeOutput ? localized("Yes") : localized("No")
                    Text("Change Output: \(changeOutputLabel)")
                }
                if let maxSendable = details.maxSendable { Text("Max Sendable: \(formattedPreviewAssetAmount(maxSendable, for: selectedCoin))") }}}}
    @ViewBuilder
    private func networkSendSections(selectedCoin: Coin?) -> some View {
        if let selectedCoin, selectedCoin.chainName == "Bitcoin" || selectedCoin.chainName == "Bitcoin Cash" || selectedCoin.chainName == "Bitcoin SV" || selectedCoin.chainName == "Litecoin" || selectedCoin.chainName == "Dogecoin" {
            Section(localized("Advanced UTXO Mode")) {
                Toggle(localized("Enable Advanced Controls"), isOn: sendAdvancedModeBinding)
                if store.sendAdvancedMode {
                    Stepper(
                        "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")", value: sendUTXOMaxInputCountBinding, in: 0 ... 50
                    )
                    if selectedCoin.chainName == "Litecoin" {
                        Toggle(localized("Enable RBF Policy"), isOn: sendEnableRBFBinding)
                        Picker(localized("Change Strategy"), selection: sendLitecoinChangeStrategyBinding) {
                            ForEach(LitecoinChangeStrategy.allCases) { strategy in Text(strategy.displayName).tag(strategy) }}.pickerStyle(.menu)
                        Text(localized("For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address.")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle(localized("RBF Intent"), isOn: sendEnableRBFBinding)
                        Toggle(localized("CPFP Intent"), isOn: sendEnableCPFPBinding)
                        if let caption = utxoAdvancedModeCaption(for: selectedCoin.chainName) {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if let selectedCoin, selectedCoin.chainName != "Bitcoin", selectedCoin.chainName != "Bitcoin Cash", selectedCoin.chainName != "Bitcoin SV", selectedCoin.chainName != "Litecoin", selectedCoin.chainName != "Dogecoin" {
            Section(localized("Fee Priority")) {
                Picker(localized("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }}.pickerStyle(.segmented)
                Text(localized("Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build.")).font(.caption).foregroundStyle(.secondary)
            }}
        if let selectedCoin, ((selectedCoin.chainName == "Bitcoin" && selectedCoin.symbol == "BTC")
               || (selectedCoin.chainName == "Bitcoin Cash" && selectedCoin.symbol == "BCH")
               || (selectedCoin.chainName == "Bitcoin SV" && selectedCoin.symbol == "BSV")
               || (selectedCoin.chainName == "Litecoin" && selectedCoin.symbol == "LTC")
               || (selectedCoin.chainName == "Dogecoin" && selectedCoin.symbol == "DOGE")) {
            let feeSymbol = selectedCoin.symbol
            let utxoPreview = utxoPreview(for: selectedCoin)
            Section(localized("\(selectedCoin.chainName) Network")) {
                Picker(localized("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }}.pickerStyle(.segmented)
                Text(localized("Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains.")).font(.caption).foregroundStyle(.secondary)
                if selectedCoin.chainName == "Dogecoin", store.isPreparingDogecoinSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localized("Loading UTXOs and fee estimate...")).font(.caption)
                    }
                } else if selectedCoin.chainName == "Dogecoin", let dogecoinSendPreview = store.dogecoinSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDoge, symbol: feeSymbol) { Text("Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDoge, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))") } else { Text("Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDoge, specifier: "%.6f") \(feeSymbol)") }
                    Text("Confirmation Preference: \(confirmationPreferenceText(for: dogecoinSendPreview.feePriority))")
                } else if let utxoPreview {
                    Text("Estimated Fee Rate: \(utxoPreview.estimatedFeeRateSatVb) sat/vB")
                    if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBtc, symbol: feeSymbol) { Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBtc, specifier: "%.8f") \(feeSymbol) (~\(fiatFee))") } else { Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBtc, specifier: "%.8f") \(feeSymbol)") }
                } else { Text("Enter amount to preview estimated \(selectedCoin.chainName) network fee.").font(.caption).foregroundStyle(.secondary) }}}
        if let selectedCoin, (selectedCoin.chainName == "Ethereum" || selectedCoin.chainName == "Ethereum Classic" || selectedCoin.chainName == "Arbitrum" || selectedCoin.chainName == "Optimism" || selectedCoin.chainName == "BNB Chain" || selectedCoin.chainName == "Avalanche" || selectedCoin.chainName == "Hyperliquid") {
            Section(localized("\(selectedCoin.chainName) Network")) {
                Toggle(localized("Use Custom Fees"), isOn: useCustomEthereumFeesBinding)
                if store.useCustomEthereumFees {
                    TextField(localized("Max Fee (gwei)"), text: customEthereumMaxFeeGweiBinding).keyboardType(.decimalPad)
                    TextField(localized("Priority Fee (gwei)"), text: customEthereumPriorityFeeGweiBinding).keyboardType(.decimalPad)
                    if let customEthereumFeeValidationError = store.customEthereumFeeValidationError { Text(customEthereumFeeValidationError).font(.caption).foregroundStyle(.red) } else { Text(localized("Custom EIP-1559 fees are applied to this send and preview.")).font(.caption).foregroundStyle(.secondary) }}
                Toggle(localized("Manual Nonce"), isOn: ethereumManualNonceEnabledBinding)
                if store.ethereumManualNonceEnabled {
                    TextField(localized("Nonce"), text: ethereumManualNonceBinding).keyboardType(.numberPad)
                    if let customEthereumNonceValidationError = store.customEthereumNonceValidationError { Text(customEthereumNonceValidationError).font(.caption).foregroundStyle(.red) }}
                if selectedCoin.chainName == "Ethereum" {
                    if store.isPreparingEthereumReplacementContext {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(localized("Preparing replacement/cancel context...")).font(.caption)
                        }
                    } else if store.hasPendingEthereumSendForSelectedWallet {
                        Button(localized("Speed Up Pending Transaction")) {
                            Task { await store.prepareEthereumSpeedUpContext() }}
                        Button(localized("Cancel Pending Transaction")) {
                            Task { await store.prepareEthereumCancelContext() }}}
                    if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage { Text(ethereumReplacementNonceStateMessage).font(.caption).foregroundStyle(.secondary) }}
                if store.isPreparingEthereumSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(localized("Loading nonce and fee estimate...")).font(.caption)
                    }
                } else if let ethereumSendPreview = store.ethereumSendPreview {
                    Text("Nonce: \(ethereumSendPreview.nonce)")
                    Text("Gas Limit: \(ethereumSendPreview.gasLimit)")
                    Text("Max Fee: \(ethereumSendPreview.maxFeePerGasGwei, specifier: "%.2f") gwei")
                    Text("Priority Fee: \(ethereumSendPreview.maxPriorityFeePerGasGwei, specifier: "%.2f") gwei")
                    let feeSymbol = evmFeeSymbol(for: selectedCoin.chainName)
                    if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeEth, symbol: feeSymbol) { Text("Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeEth, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))").font(.subheadline.weight(.semibold)) } else { Text("Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeEth, specifier: "%.6f") \(feeSymbol)").font(.subheadline.weight(.semibold)) }
                } else { Text(localized("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending.")).font(.caption).foregroundStyle(.secondary) }
                Text(localized("Spectra signs and broadcasts supported \(selectedCoin.chainName) transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.")).font(.caption).foregroundStyle(.secondary)
            }}
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Tron", isPreparing: store.isPreparingTronSend, fee: store.tronSendPreview.map { ($0.estimatedNetworkFeeTrx, "TRX", "%.6f") }, footer: "Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.", extraCaption: selectedCoin?.symbol == "USDT" ? "USDT on Tron uses TRX for network fees. Keep a TRX balance for gas." : nil
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "XRP Ledger", isPreparing: store.isPreparingXRPSend, fee: store.xrpSendPreview.map { ($0.estimatedNetworkFeeXrp, "XRP", "%.6f") }, footer: "Spectra signs and broadcasts XRP transfers in-app.", extraLines: store.xrpSendPreview.map { p in
                [p.sequence > 0 ? "Sequence: \(p.sequence)" : nil, p.lastLedgerSequence > 0 ? "Last Ledger Sequence: \(p.lastLedgerSequence)" : nil].compactMap { $0 }} ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Solana", isPreparing: store.isPreparingSolanaSend, fee: store.solanaSendPreview.map { ($0.estimatedNetworkFeeSol, "SOL", "%.6f") }, footer: "Spectra signs and broadcasts Solana transfers in-app, including SOL and supported SPL assets.", extraCaption: selectedCoin?.symbol != "SOL" ? "Token transfers on Solana still use SOL for network fees." : nil
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Cardano", isPreparing: store.isPreparingCardanoSend, fee: store.cardanoSendPreview.map { ($0.estimatedNetworkFeeAda, "ADA", "%.6f") }, footer: "Spectra signs and broadcasts ADA transfers in-app.", extraLines: store.cardanoSendPreview.map { p in p.ttlSlot > 0 ? ["TTL Slot: \(p.ttlSlot)"] : [] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Monero", isPreparing: store.isPreparingMoneroSend, fee: store.moneroSendPreview.map { ($0.estimatedNetworkFeeXmr, "XMR", "%.6f") }, footer: "Spectra prepares Monero sends in-app using the configured backend fee quote.", extraLines: store.moneroSendPreview.map { ["Priority: \($0.priorityLabel)"] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "NEAR", isPreparing: store.isPreparingNearSend, fee: store.nearSendPreview.map { ($0.estimatedNetworkFeeNear, "NEAR", "%.6f") }, footer: "Spectra signs and broadcasts NEAR transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Polkadot", isPreparing: store.isPreparingPolkadotSend, fee: store.polkadotSendPreview.map { ($0.estimatedNetworkFeeDot, "DOT", "%.6f") }, footer: "Spectra signs and broadcasts Polkadot transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Stellar", isPreparing: store.isPreparingStellarSend, fee: store.stellarSendPreview.map { ($0.estimatedNetworkFeeXlm, "XLM", "%.7f") }, footer: "Spectra signs and broadcasts Stellar payments in-app.", extraLines: store.stellarSendPreview.map { p in p.sequence > 0 ? ["Sequence: \(p.sequence)"] : [] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Internet Computer", isPreparing: store.isPreparingICPSend, fee: store.icpSendPreview.map { ($0.estimatedNetworkFeeIcp, "ICP", "%.8f") }, footer: "Spectra signs and broadcasts ICP transfers in-app."
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Sui", isPreparing: store.isPreparingSuiSend, fee: store.suiSendPreview.map { ($0.estimatedNetworkFeeSui, "SUI", "%.6f") }, footer: "Spectra signs and broadcasts Sui transfers in-app.", extraLines: store.suiSendPreview.map { ["Gas Budget: \($0.gasBudgetMist) MIST", "Reference Gas Price: \($0.referenceGasPrice)"] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "Aptos", isPreparing: store.isPreparingAptosSend, fee: store.aptosSendPreview.map { ($0.estimatedNetworkFeeApt, "APT", "%.6f") }, footer: "Spectra signs and broadcasts Aptos transfers in-app.", extraLines: store.aptosSendPreview.map { ["Max Gas Amount: \($0.maxGasAmount)", "Gas Unit Price: \($0.gasUnitPriceOctas) octas"] } ?? []
        )
        simpleSendNetworkSection(
            for: selectedCoin, chainName: "TON", isPreparing: store.isPreparingTONSend, fee: store.tonSendPreview.map { ($0.estimatedNetworkFeeTon, "TON", "%.6f") }, footer: "Spectra signs and broadcasts TON transfers in-app.", extraLines: store.tonSendPreview.map { ["Sequence Number: \($0.sequenceNumber)"] } ?? []
        )
        if let selectedCoin { sendPreviewDetailsSection(for: selectedCoin) }}
    @ViewBuilder
    private func simpleSendNetworkSection(
        for selectedCoin: Coin?, chainName: String, isPreparing: Bool, fee: (amount: Double, symbol: String, specifier: String)?, footer: String, extraLines: [String] = [], extraCaption: String? = nil
    ) -> some View {
        if let selectedCoin, selectedCoin.chainName == chainName {
            Section("\(chainName) Network") {
                if isPreparing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading \(chainName) fee estimate...").font(.caption)
                    }
                } else if let fee {
                    let feeFormatted = String(format: fee.specifier, fee.amount)
                    if let fiatFee = store.formattedFiatAmount(fromNative: fee.amount, symbol: fee.symbol) { Text("Estimated Network Fee: \(feeFormatted) \(fee.symbol) (~\(fiatFee))").font(.subheadline.weight(.semibold)) } else { Text("Estimated Network Fee: \(feeFormatted) \(fee.symbol)").font(.subheadline.weight(.semibold)) }
                    ForEach(extraLines, id: \.self) { Text($0) }
                    if let extraCaption { Text(extraCaption).font(.caption).foregroundStyle(.secondary) }
                } else { Text("Enter an amount to load a \(chainName) fee preview. Add a valid destination address before sending.").font(.caption).foregroundStyle(.secondary) }
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }}}
    var body: some View {
        let selectedCoin = selectedNetworkSendCoin
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SendPrimarySectionsView(
                        store: store, selectedAddressBookEntryID: $selectedAddressBookEntryID, isShowingQRScanner: $isShowingQRScanner, qrScannerErrorMessage: $qrScannerErrorMessage
                    )
                    if hasNetworkSendSections(for: selectedCoin) {
                        VStack(alignment: .leading, spacing: 18) { networkSendSections(selectedCoin: selectedCoin) }.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                    }
                    sendStatusSections
                }.padding(20)
            }.navigationTitle(localized("Send")).sheet(isPresented: $isShowingQRScanner) {
                SendQRScannerSheet { payload in applyScannedRecipientPayload(payload) }}.alert(localized("QR Scanner"), isPresented: qrScannerAlertBinding) {
                Button(localized("OK"), role: .cancel) {}} message: {
                if let qrScannerErrorMessage { Text(verbatim: qrScannerErrorMessage) }}.onChange(of: store.sendHoldingKey) { _, _ in
                selectedAddressBookEntryID = ""
            }.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localized("Send")) {
                        Task {
                            await store.submitSend()
                        }}.disabled(isSendBusy)
                }}.alert(localized("High-Risk Send"), isPresented: store.isShowingHighRiskSendConfirmationBinding) {
                Button(localized("Cancel"), role: .cancel) {
                    store.clearHighRiskSendConfirmation()
                }
                Button(localized("Send Anyway"), role: .destructive) {
                    Task {
                        await store.confirmHighRiskSendAndSubmit()
                    }}} message: {
                Text(store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                     ? "This transfer has elevated risk."
                     : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• "))
            }}}
    @ViewBuilder
    private func sendDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(localizedSendString(title)).font(.headline.weight(.semibold)).foregroundStyle(Color.primary) }
            VStack(alignment: .leading, spacing: 12) { content() }}.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    private var qrScannerAlertBinding: Binding<Bool> {
        Binding(
            get: { qrScannerErrorMessage != nil }, set: { isPresented in
                if !isPresented { qrScannerErrorMessage = nil }}
        )
    }
    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = localizedSendString("The scanned QR code did not contain a usable address.")
            return
        }
        let selectedChainName = store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })? .chainName
        guard let resolvedAddress = resolvedRecipientAddress(from: trimmedPayload, chainName: selectedChainName) else {
            qrScannerErrorMessage = localizedSendString("The scanned QR code does not contain a valid address for the selected asset.")
            return
        }
        store.sendAddress = resolvedAddress
        qrScannerErrorMessage = nil
    }
    private func resolvedRecipientAddress(from payload: String, chainName: String?) -> String? {
        let candidates = qrAddressCandidates(from: payload)
        guard let chainName else { return candidates.first }
        for candidate in candidates {
            if isValidScannedAddress(candidate, for: chainName) {
                if chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid" { return normalizeEVMAddress(candidate) }
                return candidate
            }}
        return nil
    }
    private func qrAddressCandidates(from payload: String) -> [String] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var candidates: [String] = []
        func appendCandidate(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }
        appendCandidate(trimmed)
        let withoutQuery = trimmed.components(separatedBy: "?").first ?? trimmed
        appendCandidate(withoutQuery)
        if let colonIndex = withoutQuery.firstIndex(of: ":") {
            let suffix = String(withoutQuery[withoutQuery.index(after: colonIndex)...])
            appendCandidate(suffix)
        }
        if let components = URLComponents(string: trimmed) {
            if let host = components.host { appendCandidate(host + components.path) }
            if let firstPathComponent = components.path.split(separator: "/").first { appendCandidate(String(firstPathComponent)) }}
        return candidates
    }
    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin": return AddressValidation.isValid(address, kind: "bitcoin", networkMode: store.bitcoinNetworkMode.rawValue)
        case "Bitcoin Cash": return AddressValidation.isValid(address, kind: "bitcoinCash")
        case "Bitcoin SV": return AddressValidation.isValid(address, kind: "bitcoinSV")
        case "Litecoin": return AddressValidation.isValid(address, kind: "litecoin")
        case "Dogecoin": return AddressValidation.isValid(address, kind: "dogecoin", networkMode: (store.wallet(for: store.sendWalletID)?.dogecoinNetworkMode ?? store.dogecoinNetworkMode).rawValue)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid": return AddressValidation.isValid(address, kind: "evm")
        case "Tron": return AddressValidation.isValid(address, kind: "tron")
        case "Solana": return AddressValidation.isValid(address, kind: "solana")
        case "Cardano": return AddressValidation.isValid(address, kind: "cardano")
        case "XRP Ledger": return AddressValidation.isValid(address, kind: "xrp")
        case "Monero": return AddressValidation.isValid(address, kind: "monero")
        case "Sui": return AddressValidation.isValid(address, kind: "sui")
        case "Aptos": return AddressValidation.isValid(address, kind: "aptos")
        case "TON": return AddressValidation.isValid(address, kind: "ton")
        case "Internet Computer": return AddressValidation.isValid(address, kind: "internetComputer")
        case "NEAR": return AddressValidation.isValid(address, kind: "near")
        default: return false
        }}
    private func confirmationPreferenceText(for priority: String) -> String {
        switch DogecoinFeePriority(rawValue: priority) ?? .normal {
        case .economy: return "Economy (cost-optimized)"
        case .normal: return "Normal (balanced)"
        case .priority: return "Priority (faster confirmation bias)"
        }}
}
private struct SendPrimarySectionsView: View {
    let store: AppState
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
        if let selectedCoin, !sendAmount.isZero { selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol) } else { selectedCoinApproximateFiatText = nil }
        return Presentation(
            sendWallets: sendWallets, selectedWallet: selectedWallet, availableSendCoins: availableSendCoins, selectedCoin: selectedCoin, selectedCoinAmountText: selectedCoinAmountText, selectedCoinApproximateFiatText: selectedCoinApproximateFiatText, addressBookEntries: store.sendAddressBookEntries
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sendSummarySection
            walletAssetSection
            recipientSection
            amountSection
        }}
    private var sendSummarySection: some View {
        sendDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let selectedCoin = presentation.selectedCoin {
                        CoinBadge(
                            assetIdentifier: selectedCoin.iconIdentifier, fallbackText: selectedCoin.mark, color: selectedCoin.color, size: 42
                        )
                    } else { Image(systemName: "arrow.up.right.circle.fill").font(.system(size: 38)).foregroundStyle(.mint) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedSendString("Send")).font(.title3.weight(.bold))
                        if let wallet = presentation.selectedWallet { Text(wallet.name).font(.subheadline).foregroundStyle(.secondary) }}
                    Spacer()
                    if let selectedCoin = presentation.selectedCoin { Text(selectedCoin.symbol).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6).background(selectedCoin.color.opacity(0.18), in: Capsule()).foregroundStyle(selectedCoin.color) }}
                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizedSendString("Available")).font(.caption).foregroundStyle(.secondary)
                            Text(presentation.selectedCoinAmountText ?? "").font(.headline.weight(.semibold)).spectraNumericTextLayout()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(localizedSendString("Network")).font(.caption).foregroundStyle(.secondary)
                            Text(selectedCoin.chainName).font(.subheadline.weight(.semibold))
                        }}
                } else { Text(localizedSendString("Choose a wallet and asset to prepare a transfer with live fee previews and risk checks.")).font(.subheadline).foregroundStyle(.secondary) }}}}
    private var walletAssetSection: some View {
        sendDetailCard(title: "Wallet & Asset") {
            VStack(alignment: .leading, spacing: 12) {
                Picker(localizedSendString("Wallet"), selection: store.sendWalletIDBinding) {
                    ForEach(presentation.sendWallets) { wallet in Text(wallet.name).tag(wallet.id) }}.onChange(of: store.sendWalletID) { _, _ in
                    store.syncSendAssetSelection()
                }
                Picker(localizedSendString("Asset"), selection: store.sendHoldingKeyBinding) {
                    ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in Text("\(coin.name) on \(store.displayChainTitle(for: coin.chainName))").tag(coin.holdingKey) }}}}}
    private var recipientSection: some View {
        sendDetailCard(title: "Recipient") {
            VStack(alignment: .leading, spacing: 12) {
                if !presentation.addressBookEntries.isEmpty {
                    Picker(localizedSendString("Saved Recipient"), selection: $selectedAddressBookEntryID) {
                        Text(localizedSendString("None")).tag("")
                        ForEach(presentation.addressBookEntries) { entry in Text("\(entry.name) • \(entry.chainName)").tag(entry.id.uuidString) }}.onChange(of: selectedAddressBookEntryID) { _, newValue in
                        guard let selectedEntry = presentation.addressBookEntries.first(where: { $0.id.uuidString == newValue }) else {
                            return
                        }
                        store.sendAddress = selectedEntry.address
                    }}
                HStack(spacing: 10) {
                    TextField(localizedSendString("Recipient address"), text: store.sendAddressBinding).textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 12).padding(.vertical, 10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button {
                        guard DataScannerViewController.isSupported else {
                            qrScannerErrorMessage = localizedSendString("QR scanning is not supported on this device.")
                            return
                        }
                        guard DataScannerViewController.isAvailable else {
                            qrScannerErrorMessage = localizedSendString("QR scanning is unavailable right now. Check camera permission and try again.")
                            return
                        }
                        isShowingQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                    }.buttonStyle(.glass).accessibilityLabel(localizedSendString("Scan QR Code"))
                }
                if let qrScannerErrorMessage { Text(qrScannerErrorMessage).font(.caption).foregroundStyle(.orange) }
                if store.isCheckingSendDestinationBalance {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(localizedSendString("Checking destination on-chain balance...")).font(.caption).foregroundStyle(.secondary)
                    }}
                if let sendDestinationRiskWarning = store.sendDestinationRiskWarning { Text(sendDestinationRiskWarning).font(.caption).foregroundStyle(.orange) }
                if let sendDestinationInfoMessage = store.sendDestinationInfoMessage { Text(sendDestinationInfoMessage).font(.caption).foregroundStyle(.secondary) }}}}
    private var amountSection: some View {
        sendDetailCard(title: "Amount") {
            VStack(alignment: .leading, spacing: 12) {
                TextField(localizedSendString("Amount"), text: store.sendAmountBinding).keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        Text(localizedSendString("Using")).foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedCoin.symbol).font(.subheadline.weight(.semibold))
                    }
                    if let fiatAmount = presentation.selectedCoinApproximateFiatText {
                        HStack {
                            Text(localizedSendString("Approx. Value")).foregroundStyle(.secondary)
                            Spacer()
                            Text(fiatAmount).font(.subheadline.weight(.semibold)).spectraNumericTextLayout()
                        }}}}}}
    private func sendDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(localizedSendString(title)).font(.headline.weight(.semibold)).foregroundStyle(Color.primary) }
            VStack(alignment: .leading, spacing: 12) { content() }}.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
}
