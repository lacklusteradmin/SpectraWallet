import Foundation
import SwiftUI
import VisionKit

struct SendView: View {
    let store: WalletStore
    @ObservedObject private var flowState: WalletFlowState
    @ObservedObject private var sendState: WalletSendState
    @ObservedObject private var runtimeState: WalletRuntimeState
    @State private var selectedAddressBookEntryID: String = ""
    @State private var isShowingQRScanner: Bool = false
    @State private var qrScannerErrorMessage: String?

    init(store: WalletStore) {
        self.store = store
        _flowState = ObservedObject(wrappedValue: store.flowState)
        _sendState = ObservedObject(wrappedValue: store.sendState)
        _runtimeState = ObservedObject(wrappedValue: store.runtimeState)
    }

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

    private var sendLitecoinChangeStrategyBinding: Binding<LitecoinWalletEngine.ChangeStrategy> {
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
        sendState.isSendingBitcoin
            || sendState.isSendingBitcoinCash
            || sendState.isSendingBitcoinSV
            || sendState.isSendingLitecoin
            || sendState.isSendingEthereum
            || sendState.isSendingDogecoin
            || sendState.isSendingTron
            || sendState.isSendingSolana
            || sendState.isSendingXRP
            || sendState.isSendingStellar
            || sendState.isSendingMonero
            || sendState.isSendingCardano
            || sendState.isSendingSui
            || sendState.isSendingAptos
            || sendState.isSendingTON
            || sendState.isSendingICP
            || sendState.isSendingNear
            || sendState.isSendingPolkadot
            || runtimeState.isPreparingEthereumSend
            || runtimeState.isPreparingDogecoinSend
            || runtimeState.isPreparingTronSend
            || runtimeState.isPreparingSolanaSend
            || runtimeState.isPreparingXRPSend
            || runtimeState.isPreparingStellarSend
            || runtimeState.isPreparingMoneroSend
            || runtimeState.isPreparingCardanoSend
            || runtimeState.isPreparingSuiSend
            || runtimeState.isPreparingAptosSend
            || runtimeState.isPreparingTONSend
            || runtimeState.isPreparingICPSend
            || runtimeState.isPreparingNearSend
            || runtimeState.isPreparingPolkadotSend
    }

    private var selectedNetworkSendCoin: Coin? {
        store.availableSendCoins(for: flowState.sendWalletID)
            .first(where: { $0.holdingKey == flowState.sendHoldingKey })
    }

    @ViewBuilder
    private var sendStatusSections: some View {
        if let sendError = flowState.sendError {
            sendDetailCard {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        if let sendVerificationNotice = flowState.sendVerificationNotice {
            sendDetailCard(title: "Verification") {
                Text(sendVerificationNotice)
                    .font(.caption)
                    .foregroundStyle(flowState.sendVerificationNoticeIsWarning ? .red : .orange)
            }
        }

        if let lastSentTransaction = sendState.lastSentTransaction {
            sendDetailCard(title: "Last Sent") {
                Text("\(lastSentTransaction.symbol) sent to \(lastSentTransaction.addressPreviewText)")
                    .font(.subheadline)
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TransactionStatusBadge(status: lastSentTransaction.status)
                }
                if let pendingTransactionRefreshStatusText = store.pendingTransactionRefreshStatusText {
                    Text(pendingTransactionRefreshStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let transactionHash = lastSentTransaction.transactionHash {
                    Text(transactionHash)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }

                if let transactionExplorerURL = lastSentTransaction.transactionExplorerURL,
                   let transactionExplorerLabel = lastSentTransaction.transactionExplorerLabel {
                    Link(destination: transactionExplorerURL) {
                        Label(transactionExplorerLabel, systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                }

                Button {
                    store.saveLastSentRecipientToAddressBook()
                } label: {
                    Label(
                        store.canSaveLastSentRecipientToAddressBook() ? "Save Recipient To Address Book" : "Recipient Already Saved",
                        systemImage: store.canSaveLastSentRecipientToAddressBook() ? "book.closed" : "checkmark.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .disabled(!store.canSaveLastSentRecipientToAddressBook())
            }
        }

        if sendState.isSendingBitcoin {
            sendingSection("Broadcasting Bitcoin transaction...")
        }
        if sendState.isSendingBitcoinCash {
            sendingSection("Broadcasting Bitcoin Cash transaction...")
        }
        if sendState.isSendingBitcoinSV {
            sendingSection("Broadcasting Bitcoin SV transaction...")
        }
        if sendState.isSendingLitecoin {
            sendingSection("Broadcasting Litecoin transaction...")
        }
        if sendState.isSendingEthereum {
            sendingSection("Broadcasting \(store.selectedSendCoin?.chainName ?? "EVM") transaction...")
        }
        if sendState.isSendingDogecoin {
            sendingSection("Broadcasting Dogecoin transaction...")
        }
        if sendState.isSendingTron {
            sendingSection("Broadcasting Tron transaction...")
        }
        if sendState.isSendingSolana {
            sendingSection("Broadcasting Solana transaction...")
        }
        if sendState.isSendingXRP {
            sendingSection("Broadcasting XRP transaction...")
        }
        if sendState.isSendingStellar {
            sendingSection("Broadcasting Stellar transaction...")
        }
        if sendState.isSendingMonero {
            sendingSection("Broadcasting Monero transaction...")
        }
        if sendState.isSendingCardano {
            sendingSection("Broadcasting Cardano transaction...")
        }
        if sendState.isSendingSui {
            sendingSection("Broadcasting Sui transaction...")
        }
        if sendState.isSendingAptos {
            sendingSection("Broadcasting Aptos transaction...")
        }
        if sendState.isSendingTON {
            sendingSection("Broadcasting TON transaction...")
        }
        if sendState.isSendingICP {
            sendingSection("Broadcasting Internet Computer transaction...")
        }
        if sendState.isSendingNear {
            sendingSection("Broadcasting NEAR transaction...")
        }
        if sendState.isSendingPolkadot {
            sendingSection("Broadcasting Polkadot transaction...")
        }
    }

    private func sendingSection(_ title: String) -> some View {
        sendDetailCard {
            HStack(spacing: 10) {
                ProgressView()
                Text(title)
                    .font(.caption)
            }
        }
    }

    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        guard let coin else { return false }
        let chainName = coin.chainName
        return !store.availableBroadcastProviders(for: chainName).isEmpty
            || chainName == "Bitcoin"
            || chainName == "Bitcoin Cash"
            || chainName == "Bitcoin SV"
            || chainName == "Litecoin"
            || chainName == "Dogecoin"
            || chainName == "Ethereum"
            || chainName == "Ethereum Classic"
            || chainName == "Arbitrum"
            || chainName == "Optimism"
            || chainName == "BNB Chain"
            || chainName == "Avalanche"
            || chainName == "Hyperliquid"
            || chainName == "Tron"
            || chainName == "Solana"
            || chainName == "XRP Ledger"
            || chainName == "Monero"
            || chainName == "Cardano"
            || chainName == "Sui"
            || chainName == "Aptos"
            || chainName == "TON"
            || chainName == "NEAR"
            || chainName == "Polkadot"
            || chainName == "Stellar"
            || chainName == "Internet Computer"
    }

    private func broadcastProviderBinding(
        providerID: String,
        chainName: String
    ) -> Binding<Bool> {
        Binding(
            get: { store.isBroadcastProviderEnabled(providerID, for: chainName) },
            set: { newValue in
                store.setBroadcastProvider(providerID, enabled: newValue, for: chainName)
            }
        )
    }

    private func chainFeePriorityBinding(for chainName: String) -> Binding<ChainFeePriorityOption> {
        Binding(
            get: { store.feePriorityOption(for: chainName) },
            set: { store.setFeePriorityOption($0, for: chainName) }
        )
    }

    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        if coin.chainName == "Litecoin" {
            return store.litecoinSendPreview
        }
        if coin.chainName == "Bitcoin Cash" {
            return store.bitcoinCashSendPreview
        }
        return store.bitcoinSendPreview
    }

    private func formattedPreviewAssetAmount(_ amount: Double, for coin: Coin) -> String {
        store.formattedAssetAmount(amount, symbol: coin.symbol, chainName: coin.chainName)
    }

    @ViewBuilder
    private func sendPreviewDetailsSection(for selectedCoin: Coin) -> some View {
        if let details = store.sendPreviewDetails(for: selectedCoin),
           details.hasVisibleContent {
            Section("Preview Details") {
                if let spendableBalance = details.spendableBalance {
                    Text("Spendable Balance: \(formattedPreviewAssetAmount(spendableBalance, for: selectedCoin))")
                }
                if let feeRateDescription = details.feeRateDescription {
                    Text("Fee Rate: \(feeRateDescription)")
                }
                if let estimatedTransactionBytes = details.estimatedTransactionBytes {
                    Text("Estimated Size: \(estimatedTransactionBytes) bytes")
                }
                if let selectedInputCount = details.selectedInputCount {
                    Text("Selected Inputs: \(selectedInputCount)")
                }
                if let usesChangeOutput = details.usesChangeOutput {
                    let changeOutputLabel = usesChangeOutput ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No", comment: "")
                    Text("Change Output: \(changeOutputLabel)")
                }
                if let maxSendable = details.maxSendable {
                    Text("Max Sendable: \(formattedPreviewAssetAmount(maxSendable, for: selectedCoin))")
                }
            }
        }
    }

    @ViewBuilder
    private func networkSendSections(selectedCoin: Coin?) -> some View {
        if let selectedCoin,
           selectedCoin.chainName == "Bitcoin" || selectedCoin.chainName == "Bitcoin Cash" || selectedCoin.chainName == "Bitcoin SV" || selectedCoin.chainName == "Litecoin" || selectedCoin.chainName == "Dogecoin" {
            Section("Advanced UTXO Mode") {
                Toggle("Enable Advanced Controls", isOn: sendAdvancedModeBinding)
                if store.sendAdvancedMode {
                    Stepper(
                        "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")",
                        value: sendUTXOMaxInputCountBinding,
                        in: 0 ... 50
                    )
                    if selectedCoin.chainName == "Litecoin" {
                        Toggle("Enable RBF Policy", isOn: sendEnableRBFBinding)
                        Picker("Change Strategy", selection: sendLitecoinChangeStrategyBinding) {
                            ForEach(LitecoinWalletEngine.ChangeStrategy.allCases) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("RBF Intent", isOn: sendEnableRBFBinding)
                        Toggle("CPFP Intent", isOn: sendEnableCPFPBinding)
                        if selectedCoin.chainName == "Bitcoin" {
                            Text("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Bitcoin Cash" {
                            Text("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedCoin.chainName == "Dogecoin" {
                            Text("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if let selectedCoin,
           selectedCoin.chainName != "Bitcoin",
           selectedCoin.chainName != "Bitcoin Cash",
           selectedCoin.chainName != "Bitcoin SV",
           selectedCoin.chainName != "Litecoin",
           selectedCoin.chainName != "Dogecoin" {
            Section("Fee Priority") {
                Picker("Fee Priority", selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Text("Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin,
           ((selectedCoin.chainName == "Bitcoin" && selectedCoin.symbol == "BTC")
               || (selectedCoin.chainName == "Bitcoin Cash" && selectedCoin.symbol == "BCH")
               || (selectedCoin.chainName == "Bitcoin SV" && selectedCoin.symbol == "BSV")
               || (selectedCoin.chainName == "Litecoin" && selectedCoin.symbol == "LTC")
               || (selectedCoin.chainName == "Dogecoin" && selectedCoin.symbol == "DOGE")) {
            let feeSymbol = selectedCoin.symbol
            let utxoPreview = utxoPreview(for: selectedCoin)
            Section("\(selectedCoin.chainName) Network") {
                Picker("Fee Priority", selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                    ForEach(ChainFeePriorityOption.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Text("Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedCoin.chainName == "Dogecoin", runtimeState.isPreparingDogecoinSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading UTXOs and fee estimate...")
                            .font(.caption)
                    }
                } else if selectedCoin.chainName == "Dogecoin", let dogecoinSendPreview = store.dogecoinSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFeeDOGE, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDOGE, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))")
                    } else {
                        Text("Estimated Network Fee: \(dogecoinSendPreview.estimatedNetworkFeeDOGE, specifier: "%.6f") \(feeSymbol)")
                    }
                    Text("Confirmation Preference: \(confirmationPreferenceText(for: dogecoinSendPreview.feePriority))")
                } else if let utxoPreview {
                    Text("Estimated Fee Rate: \(utxoPreview.estimatedFeeRateSatVb) sat/vB")
                    if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFeeBTC, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol) (~\(fiatFee))")
                    } else {
                        Text("Estimated Network Fee: \(utxoPreview.estimatedNetworkFeeBTC, specifier: "%.8f") \(feeSymbol)")
                    }
                } else {
                    Text("Enter amount to preview estimated \(selectedCoin.chainName) network fee.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let selectedCoin,
           (selectedCoin.chainName == "Ethereum" || selectedCoin.chainName == "Ethereum Classic" || selectedCoin.chainName == "Arbitrum" || selectedCoin.chainName == "Optimism" || selectedCoin.chainName == "BNB Chain" || selectedCoin.chainName == "Avalanche" || selectedCoin.chainName == "Hyperliquid") {
            Section("\(selectedCoin.chainName) Network") {
                Toggle("Use Custom Fees", isOn: useCustomEthereumFeesBinding)

                if store.useCustomEthereumFees {
                    TextField("Max Fee (gwei)", text: customEthereumMaxFeeGweiBinding)
                        .keyboardType(.decimalPad)
                    TextField("Priority Fee (gwei)", text: customEthereumPriorityFeeGweiBinding)
                        .keyboardType(.decimalPad)

                    if let customEthereumFeeValidationError = store.customEthereumFeeValidationError {
                        Text(customEthereumFeeValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Custom EIP-1559 fees are applied to this send and preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Manual Nonce", isOn: ethereumManualNonceEnabledBinding)
                if store.ethereumManualNonceEnabled {
                    TextField("Nonce", text: ethereumManualNonceBinding)
                        .keyboardType(.numberPad)
                    if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
                        Text(customEthereumNonceValidationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if selectedCoin.chainName == "Ethereum" {
                    if runtimeState.isPreparingEthereumReplacementContext {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing replacement/cancel context...")
                                .font(.caption)
                        }
                    } else if store.hasPendingEthereumSendForSelectedWallet {
                        Button("Speed Up Pending Transaction") {
                            Task { await store.prepareEthereumSpeedUpContext() }
                        }
                        Button("Cancel Pending Transaction") {
                            Task { await store.prepareEthereumCancelContext() }
                        }
                    }

                    if let ethereumReplacementNonceStateMessage = store.ethereumReplacementNonceStateMessage {
                        Text(ethereumReplacementNonceStateMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if runtimeState.isPreparingEthereumSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading nonce and fee estimate...")
                            .font(.caption)
                    }
                } else if let ethereumSendPreview = store.ethereumSendPreview {
                    Text("Nonce: \(ethereumSendPreview.nonce)")
                    Text("Gas Limit: \(ethereumSendPreview.gasLimit)")
                    Text("Max Fee: \(ethereumSendPreview.maxFeePerGasGwei, specifier: "%.2f") gwei")
                    Text("Priority Fee: \(ethereumSendPreview.maxPriorityFeePerGasGwei, specifier: "%.2f") gwei")
                    let feeSymbol = selectedCoin.chainName == "BNB Chain" ? "BNB" : (selectedCoin.chainName == "Ethereum Classic" ? "ETC" : (selectedCoin.chainName == "Avalanche" ? "AVAX" : (selectedCoin.chainName == "Hyperliquid" ? "HYPE" : "ETH")))
                    if let fiatFee = store.formattedFiatAmount(fromNative: ethereumSendPreview.estimatedNetworkFeeETH, symbol: feeSymbol) {
                        Text("Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeETH, specifier: "%.6f") \(feeSymbol) (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(ethereumSendPreview.estimatedNetworkFeeETH, specifier: "%.6f") \(feeSymbol)")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts supported \(selectedCoin.chainName) transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Tron" {
            Section("Tron Network") {
                if runtimeState.isPreparingTronSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Tron fee estimate...")
                            .font(.caption)
                    }
                } else if let tronSendPreview = store.tronSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: tronSendPreview.estimatedNetworkFeeTRX, symbol: "TRX") {
                        Text("Estimated Network Fee: \(tronSendPreview.estimatedNetworkFeeTRX, specifier: "%.6f") TRX (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(tronSendPreview.estimatedNetworkFeeTRX, specifier: "%.6f") TRX")
                            .font(.subheadline.weight(.semibold))
                    }
                    if selectedCoin.symbol == "USDT" {
                        Text("USDT on Tron uses TRX for network fees. Keep a TRX balance for gas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter an amount to load a Tron fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "XRP Ledger" {
            Section("XRP Ledger Network") {
                if runtimeState.isPreparingXRPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading XRP fee estimate...")
                            .font(.caption)
                    }
                } else if let xrpSendPreview = store.xrpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: xrpSendPreview.estimatedNetworkFeeXRP, symbol: "XRP") {
                        Text("Estimated Network Fee: \(xrpSendPreview.estimatedNetworkFeeXRP, specifier: "%.6f") XRP (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(xrpSendPreview.estimatedNetworkFeeXRP, specifier: "%.6f") XRP")
                            .font(.subheadline.weight(.semibold))
                    }
                    if xrpSendPreview.sequence > 0 {
                        Text("Sequence: \(xrpSendPreview.sequence)")
                    }
                    if xrpSendPreview.lastLedgerSequence > 0 {
                        Text("Last Ledger Sequence: \(xrpSendPreview.lastLedgerSequence)")
                    }
                } else {
                    Text("Enter an amount to load an XRP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts XRP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Solana" {
            Section("Solana Network") {
                if runtimeState.isPreparingSolanaSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Solana fee estimate...")
                            .font(.caption)
                    }
                } else if let solanaSendPreview = store.solanaSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: solanaSendPreview.estimatedNetworkFeeSOL, symbol: "SOL") {
                        Text("Estimated Network Fee: \(solanaSendPreview.estimatedNetworkFeeSOL, specifier: "%.6f") SOL (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(solanaSendPreview.estimatedNetworkFeeSOL, specifier: "%.6f") SOL")
                            .font(.subheadline.weight(.semibold))
                    }
                    if selectedCoin.symbol != "SOL" {
                        Text("Token transfers on Solana still use SOL for network fees.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter an amount to load a Solana fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Solana transfers in-app, including SOL and supported SPL assets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Cardano" {
            Section("Cardano Network") {
                if runtimeState.isPreparingCardanoSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Cardano fee estimate...")
                            .font(.caption)
                    }
                } else if let cardanoSendPreview = store.cardanoSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: cardanoSendPreview.estimatedNetworkFeeADA, symbol: "ADA") {
                        Text("Estimated Network Fee: \(cardanoSendPreview.estimatedNetworkFeeADA, specifier: "%.6f") ADA (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(cardanoSendPreview.estimatedNetworkFeeADA, specifier: "%.6f") ADA")
                            .font(.subheadline.weight(.semibold))
                    }
                    if cardanoSendPreview.ttlSlot > 0 {
                        Text("TTL Slot: \(cardanoSendPreview.ttlSlot)")
                    }
                } else {
                    Text("Enter an amount to load a Cardano fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ADA transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Monero" {
            Section("Monero Network") {
                if runtimeState.isPreparingMoneroSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Monero fee estimate...")
                            .font(.caption)
                    }
                } else if let moneroSendPreview = store.moneroSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: moneroSendPreview.estimatedNetworkFeeXMR, symbol: "XMR") {
                        Text("Estimated Network Fee: \(moneroSendPreview.estimatedNetworkFeeXMR, specifier: "%.6f") XMR (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(moneroSendPreview.estimatedNetworkFeeXMR, specifier: "%.6f") XMR")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Priority: \(moneroSendPreview.priorityLabel)")
                } else {
                    Text("Enter an amount to load a Monero fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra prepares Monero sends in-app using the configured backend fee quote.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "NEAR" {
            Section("NEAR Network") {
                if runtimeState.isPreparingNearSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading NEAR fee estimate...")
                            .font(.caption)
                    }
                } else if let nearSendPreview = store.nearSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: nearSendPreview.estimatedNetworkFeeNEAR, symbol: "NEAR") {
                        Text("Estimated Network Fee: \(nearSendPreview.estimatedNetworkFeeNEAR, specifier: "%.6f") NEAR (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(nearSendPreview.estimatedNetworkFeeNEAR, specifier: "%.6f") NEAR")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a NEAR fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts NEAR transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Polkadot" {
            Section("Polkadot Network") {
                if runtimeState.isPreparingPolkadotSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Polkadot fee estimate...")
                            .font(.caption)
                    }
                } else if let polkadotSendPreview = store.polkadotSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: polkadotSendPreview.estimatedNetworkFeeDOT, symbol: "DOT") {
                        Text("Estimated Network Fee: \(polkadotSendPreview.estimatedNetworkFeeDOT, specifier: "%.6f") DOT (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(polkadotSendPreview.estimatedNetworkFeeDOT, specifier: "%.6f") DOT")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load a Polkadot fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Polkadot transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Stellar" {
            Section("Stellar Network") {
                if runtimeState.isPreparingStellarSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Stellar fee estimate...")
                            .font(.caption)
                    }
                } else if let stellarSendPreview = store.stellarSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: stellarSendPreview.estimatedNetworkFeeXLM, symbol: "XLM") {
                        Text("Estimated Network Fee: \(stellarSendPreview.estimatedNetworkFeeXLM, specifier: "%.7f") XLM (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(stellarSendPreview.estimatedNetworkFeeXLM, specifier: "%.7f") XLM")
                            .font(.subheadline.weight(.semibold))
                    }
                    if stellarSendPreview.sequence > 0 {
                        Text("Sequence: \(stellarSendPreview.sequence)")
                    }
                } else {
                    Text("Enter an amount to load a Stellar fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Stellar payments in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Internet Computer" {
            Section("Internet Computer Network") {
                if runtimeState.isPreparingICPSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading ICP fee estimate...")
                            .font(.caption)
                    }
                } else if let icpSendPreview = store.icpSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: icpSendPreview.estimatedNetworkFeeICP, symbol: "ICP") {
                        Text("Estimated Network Fee: \(icpSendPreview.estimatedNetworkFeeICP, specifier: "%.8f") ICP (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(icpSendPreview.estimatedNetworkFeeICP, specifier: "%.8f") ICP")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Enter an amount to load an ICP fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts ICP transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Sui" {
            Section("Sui Network") {
                if runtimeState.isPreparingSuiSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Sui fee estimate...")
                            .font(.caption)
                    }
                } else if let suiSendPreview = store.suiSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: suiSendPreview.estimatedNetworkFeeSUI, symbol: "SUI") {
                        Text("Estimated Network Fee: \(suiSendPreview.estimatedNetworkFeeSUI, specifier: "%.6f") SUI (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(suiSendPreview.estimatedNetworkFeeSUI, specifier: "%.6f") SUI")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Gas Budget: \(suiSendPreview.gasBudgetMist) MIST")
                    Text("Reference Gas Price: \(suiSendPreview.referenceGasPrice)")
                } else {
                    Text("Enter an amount to load a Sui fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Sui transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "Aptos" {
            Section("Aptos Network") {
                if runtimeState.isPreparingAptosSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Aptos fee estimate...")
                            .font(.caption)
                    }
                } else if let aptosSendPreview = store.aptosSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: aptosSendPreview.estimatedNetworkFeeAPT, symbol: "APT") {
                        Text("Estimated Network Fee: \(aptosSendPreview.estimatedNetworkFeeAPT, specifier: "%.6f") APT (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(aptosSendPreview.estimatedNetworkFeeAPT, specifier: "%.6f") APT")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Max Gas Amount: \(aptosSendPreview.maxGasAmount)")
                    Text("Gas Unit Price: \(aptosSendPreview.gasUnitPriceOctas) octas")
                } else {
                    Text("Enter an amount to load an Aptos fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts Aptos transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin, selectedCoin.chainName == "TON" {
            Section("TON Network") {
                if runtimeState.isPreparingTONSend {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading TON fee estimate...")
                            .font(.caption)
                    }
                } else if let tonSendPreview = store.tonSendPreview {
                    if let fiatFee = store.formattedFiatAmount(fromNative: tonSendPreview.estimatedNetworkFeeTON, symbol: "TON") {
                        Text("Estimated Network Fee: \(tonSendPreview.estimatedNetworkFeeTON, specifier: "%.6f") TON (~\(fiatFee))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Estimated Network Fee: \(tonSendPreview.estimatedNetworkFeeTON, specifier: "%.6f") TON")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Sequence Number: \(tonSendPreview.sequenceNumber)")
                } else {
                    Text("Enter an amount to load a TON fee preview. Add a valid destination address before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spectra signs and broadcasts TON transfers in-app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedCoin {
            sendPreviewDetailsSection(for: selectedCoin)
        }

        if let selectedCoin {
            let providers = store.availableBroadcastProviders(for: selectedCoin.chainName)
            if !providers.isEmpty {
                Section("Broadcast Providers") {
                    ForEach(providers) { provider in
                        Toggle(
                            provider.title,
                            isOn: broadcastProviderBinding(
                                providerID: provider.id,
                                chainName: selectedCoin.chainName
                            )
                        )
                    }

                    Text("Choose which providers Spectra is allowed to broadcast through for this chain. At least one provider must remain enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        let selectedCoin = selectedNetworkSendCoin

        ZStack {
            SpectraBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SendPrimarySectionsView(
                        store: store,
                        flowState: flowState,
                        selectedAddressBookEntryID: $selectedAddressBookEntryID,
                        isShowingQRScanner: $isShowingQRScanner,
                        qrScannerErrorMessage: $qrScannerErrorMessage
                    )
                    if hasNetworkSendSections(for: selectedCoin) {
                        VStack(alignment: .leading, spacing: 18) {
                            networkSendSections(selectedCoin: selectedCoin)
                        }
                        .padding(18)
                        .spectraBubbleFill()
                        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                    }
                    sendStatusSections
                }
                .padding(20)
            }
            .navigationTitle("Send")
            .sheet(isPresented: $isShowingQRScanner) {
                SendQRScannerSheet { payload in
                    applyScannedRecipientPayload(payload)
                }
            }
            .alert("QR Scanner", isPresented: qrScannerAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                if let qrScannerErrorMessage {
                    Text(verbatim: qrScannerErrorMessage)
                }
            }
            .onChange(of: flowState.sendHoldingKey) { _, _ in
                selectedAddressBookEntryID = ""
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            await store.submitSend()
                        }
                    }
                    .disabled(isSendBusy)
                }
            }
            .alert("High-Risk Send", isPresented: store.isShowingHighRiskSendConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    store.clearHighRiskSendConfirmation()
                }
                Button("Send Anyway", role: .destructive) {
                    Task {
                        await store.confirmHighRiskSendAndSubmit()
                    }
                }
            } message: {
                Text(store.pendingHighRiskSendReasons.joined(separator: "\n• ").isEmpty
                     ? "This transfer has elevated risk."
                     : "• " + store.pendingHighRiskSendReasons.joined(separator: "\n• "))
            }
        }
    }

    @ViewBuilder
    private func sendDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }

    private var qrScannerAlertBinding: Binding<Bool> {
        Binding(
            get: { qrScannerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    qrScannerErrorMessage = nil
                }
            }
        )
    }

    private func applyScannedRecipientPayload(_ payload: String) {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            qrScannerErrorMessage = "The scanned QR code did not contain a usable address."
            return
        }

        let selectedChainName = store.availableSendCoins(for: store.sendWalletID)
            .first(where: { $0.holdingKey == store.sendHoldingKey })?
            .chainName

        guard let resolvedAddress = resolvedRecipientAddress(from: trimmedPayload, chainName: selectedChainName) else {
            qrScannerErrorMessage = "The scanned QR code does not contain a valid address for the selected asset."
            return
        }

        store.sendAddress = resolvedAddress
        qrScannerErrorMessage = nil
    }

    private func resolvedRecipientAddress(from payload: String, chainName: String?) -> String? {
        let candidates = qrAddressCandidates(from: payload)
        guard let chainName else {
            return candidates.first
        }

        for candidate in candidates {
            if isValidScannedAddress(candidate, for: chainName) {
                if chainName == "Ethereum" || chainName == "Ethereum Classic" || chainName == "Arbitrum" || chainName == "Optimism" || chainName == "BNB Chain" || chainName == "Avalanche" || chainName == "Hyperliquid" {
                    return EthereumWalletEngine.normalizeAddress(candidate)
                }
                return candidate
            }
        }
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
            if let host = components.host {
                appendCandidate(host + components.path)
            }
            if let firstPathComponent = components.path.split(separator: "/").first {
                appendCandidate(String(firstPathComponent))
            }
        }

        return candidates
    }

    private func isValidScannedAddress(_ address: String, for chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin":
            return AddressValidation.isValidBitcoinAddress(address, networkMode: store.bitcoinNetworkMode)
        case "Bitcoin Cash":
            return AddressValidation.isValidBitcoinCashAddress(address)
        case "Bitcoin SV":
            return AddressValidation.isValidBitcoinSVAddress(address)
        case "Litecoin":
            return AddressValidation.isValidLitecoinAddress(address)
        case "Dogecoin":
            let networkMode: DogecoinNetworkMode = store.dogecoinAllowTestnet ? .testnet : .mainnet
            return AddressValidation.isValidDogecoinAddress(address, networkMode: networkMode)
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            return AddressValidation.isValidEthereumAddress(address)
        case "Tron":
            return AddressValidation.isValidTronAddress(address)
        case "Solana":
            return AddressValidation.isValidSolanaAddress(address)
        case "Cardano":
            return AddressValidation.isValidCardanoAddress(address)
        case "XRP Ledger":
            return AddressValidation.isValidXRPAddress(address)
        case "Monero":
            return AddressValidation.isValidMoneroAddress(address)
        case "Sui":
            return AddressValidation.isValidSuiAddress(address)
        case "Aptos":
            return AddressValidation.isValidAptosAddress(address)
        case "TON":
            return AddressValidation.isValidTONAddress(address)
        case "Internet Computer":
            return AddressValidation.isValidICPAddress(address)
        case "NEAR":
            return AddressValidation.isValidNearAddress(address)
        default:
            return false
        }
    }

    private func confirmationPreferenceText(for priority: DogecoinWalletEngine.FeePriority) -> String {
        switch priority {
        case .economy:
            return "Economy (cost-optimized)"
        case .normal:
            return "Normal (balanced)"
        case .priority:
            return "Priority (faster confirmation bias)"
        }
    }
}

private struct SendPrimarySectionsView: View {
    let store: WalletStore
    @ObservedObject var flowState: WalletFlowState
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
        let selectedWallet = sendWallets.first(where: { $0.id.uuidString == flowState.sendWalletID })
        let availableSendCoins = store.availableSendCoins(for: flowState.sendWalletID)
        let selectedCoin = availableSendCoins.first(where: { $0.holdingKey == flowState.sendHoldingKey })
        let selectedCoinAmountText = selectedCoin.map {
            store.formattedAssetAmount($0.amount, symbol: $0.symbol, chainName: $0.chainName)
        }
        let sendAmount = Double(flowState.sendAmount) ?? 0
        let selectedCoinApproximateFiatText: String?
        if let selectedCoin, !sendAmount.isZero {
            selectedCoinApproximateFiatText = store.formattedFiatAmount(fromNative: sendAmount, symbol: selectedCoin.symbol)
        } else {
            selectedCoinApproximateFiatText = nil
        }

        return Presentation(
            sendWallets: sendWallets,
            selectedWallet: selectedWallet,
            availableSendCoins: availableSendCoins,
            selectedCoin: selectedCoin,
            selectedCoinAmountText: selectedCoinAmountText,
            selectedCoinApproximateFiatText: selectedCoinApproximateFiatText,
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
        sendDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let selectedCoin = presentation.selectedCoin {
                        CoinBadge(
                            assetIdentifier: selectedCoin.iconIdentifier,
                            fallbackText: selectedCoin.mark,
                            color: selectedCoin.color,
                            size: 42
                        )
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.mint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send")
                            .font(.title3.weight(.bold))
                        if let wallet = presentation.selectedWallet {
                            Text(wallet.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let selectedCoin = presentation.selectedCoin {
                        Text(selectedCoin.symbol)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedCoin.color.opacity(0.18), in: Capsule())
                            .foregroundStyle(selectedCoin.color)
                    }
                }

                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(presentation.selectedCoinAmountText ?? "")
                                .font(.headline.weight(.semibold))
                                .spectraNumericTextLayout()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedCoin.chainName)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } else {
                    Text("Choose a wallet and asset to prepare a transfer with live fee previews and risk checks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var walletAssetSection: some View {
        sendDetailCard(title: "Wallet & Asset") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Wallet", selection: store.sendWalletIDBinding) {
                    ForEach(presentation.sendWallets) { wallet in
                        Text(wallet.name).tag(wallet.id.uuidString)
                    }
                }
                .onChange(of: flowState.sendWalletID) { _, _ in
                    store.syncSendAssetSelection()
                }

                Picker("Asset", selection: store.sendHoldingKeyBinding) {
                    ForEach(presentation.availableSendCoins, id: \.holdingKey) { coin in
                        Text("\(coin.name) on \(store.displayNetworkName(for: coin.chainName))").tag(coin.holdingKey)
                    }
                }
            }
        }
    }

    private var recipientSection: some View {
        sendDetailCard(title: "Recipient") {
            VStack(alignment: .leading, spacing: 12) {
                if !presentation.addressBookEntries.isEmpty {
                    Picker("Saved Recipient", selection: $selectedAddressBookEntryID) {
                        Text("None").tag("")
                        ForEach(presentation.addressBookEntries) { entry in
                            Text("\(entry.name) • \(entry.chainName)").tag(entry.id.uuidString)
                        }
                    }
                    .onChange(of: selectedAddressBookEntryID) { _, newValue in
                        guard let selectedEntry = presentation.addressBookEntries.first(where: { $0.id.uuidString == newValue }) else {
                            return
                        }
                        store.sendAddress = selectedEntry.address
                    }
                }

                HStack(spacing: 10) {
                    TextField("Recipient address", text: store.sendAddressBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        guard DataScannerViewController.isSupported else {
                            qrScannerErrorMessage = "QR scanning is not supported on this device."
                            return
                        }
                        guard DataScannerViewController.isAvailable else {
                            qrScannerErrorMessage = "QR scanning is unavailable right now. Check camera permission and try again."
                            return
                        }
                        isShowingQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Scan QR Code")
                }

                if let qrScannerErrorMessage {
                    Text(qrScannerErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if flowState.isCheckingSendDestinationBalance {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking destination on-chain balance...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let sendDestinationRiskWarning = flowState.sendDestinationRiskWarning {
                    Text(sendDestinationRiskWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let sendDestinationInfoMessage = flowState.sendDestinationInfoMessage {
                    Text(sendDestinationInfoMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var amountSection: some View {
        sendDetailCard(title: "Amount") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Amount", text: store.sendAmountBinding)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let selectedCoin = presentation.selectedCoin {
                    HStack {
                        Text("Using")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedCoin.symbol)
                            .font(.subheadline.weight(.semibold))
                    }

                    if let fiatAmount = presentation.selectedCoinApproximateFiatText {
                        HStack {
                            Text("Approx. Value")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(fiatAmount)
                                .font(.subheadline.weight(.semibold))
                                .spectraNumericTextLayout()
                        }
                    }
                }
            }
        }
    }

    private func sendDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
}
