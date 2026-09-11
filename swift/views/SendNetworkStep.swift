import SwiftUI

/// The send flow's network page: fee estimates and the per-chain options that
/// go with them.
///
/// Split out of `SendView`, where these sections were `private func`s on the
/// same struct as the rest of the flow. Nothing here reads the flow's own
/// state — the step, the scanner, the address-book selection — so they gave
/// SwiftUI no diffing boundary of their own: a step change re-evaluated every
/// fee row along with it.
struct SendNetworkStep: View {
    @Bindable var store: AppState

    private var sendPreviewStore: SendPreviewStore { store.sendPreviewStore }

    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        guard let coin, let chain = Chain(displayName: coin.chainName) else { return false }
        return chain.hasSendPreview
    }

    var body: some View {
        networkStep(selectedCoin: selectedCoin)
    }

    private var selectedCoin: Coin? {
        store.availableSendCoins(for: store.sendWalletID).first(where: { $0.holdingKey == store.sendHoldingKey })
    }

    private func networkStep(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            spectraPageHeader(
                title: "Network",
                subtitle: "Review fee estimates and advanced chain options.",
                systemImage: "antenna.radiowaves.left.and.right"
            )

            if hasNetworkSendSections(for: selectedCoin) {
                networkCard(selectedCoin: selectedCoin)
            } else {
                noNetworkPreviewCard(selectedCoin: selectedCoin)
            }
        }
    }

    private func noNetworkPreviewCard(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            networkSectionHeader("Network")
            if let selectedCoin {
                Text(AppLocalization.format("Spectra will prepare the %@ transfer with the default %@ network policy.", selectedCoin.symbol, selectedCoin.chainName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(AppLocalization.string("Select an asset to load network details."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    // MARK: - Network fee card

    @ViewBuilder
    private func networkCard(selectedCoin: Coin?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            networkCardContent(selectedCoin: selectedCoin)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.card)
    }

    @ViewBuilder
    private func networkCardContent(selectedCoin: Coin?) -> some View {
        if let selectedCoin, selectedCoin.isUTXOChain {
            utxoNetworkContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, !selectedCoin.isUTXOChain, !selectedCoin.isEVMChain {
            feePriorityContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, selectedCoin.isUTXOChain, selectedCoin.isNativeCoin {
            utxoFeePreviewContent(selectedCoin: selectedCoin)
        }
        if let selectedCoin, selectedCoin.isEVMChain {
            evmNetworkContent(selectedCoin: selectedCoin)
        }
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Tron",
            footer: "Spectra signs and broadcasts Tron transfers in-app, including TRX and TRC-20 USDT.",
            extraCaption: selectedCoin?.symbol == "USDT" ? "USDT on Tron uses TRX for network fees. Keep a TRX balance for gas." : nil)
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "XRP Ledger",
            footer: "Spectra signs and broadcasts XRP transfers in-app.",
            extraLines: sendPreviewStore.xrpSendPreview.map { p in
                [p.sequence > 0 ? "Sequence: \(p.sequence)" : nil, p.lastLedgerSequence > 0 ? "Last Ledger Sequence: \(p.lastLedgerSequence)" : nil].compactMap { $0 }
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Solana",
            footer: "Spectra signs and broadcasts Solana transfers in-app, including SOL and supported SPL assets.",
            extraCaption: selectedCoin?.symbol != "SOL" ? "Token transfers on Solana still use SOL for network fees." : nil)
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Cardano",
            footer: "Spectra signs and broadcasts ADA transfers in-app.",
            extraLines: sendPreviewStore.cardanoSendPreview.map { p in
                p.ttlSlot > 0 ? [AppLocalization.format("TTL Slot: %lld", p.ttlSlot)] : []
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Monero",
            footer: "Spectra prepares Monero sends in-app using the configured backend fee quote.",
            extraLines: sendPreviewStore.moneroSendPreview.map { [AppLocalization.format("Priority: %@", $0.priorityLabel)] } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "NEAR",
            footer: "Spectra signs and broadcasts NEAR transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Polkadot",
            footer: "Spectra signs and broadcasts Polkadot transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Stellar",
            footer: "Spectra signs and broadcasts Stellar payments in-app.",
            extraLines: sendPreviewStore.stellarSendPreview.map { p in
                p.sequence > 0 ? [AppLocalization.format("Sequence: %lld", p.sequence)] : []
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Internet Computer",
            footer: "Spectra signs and broadcasts ICP transfers in-app.")
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Sui",
            footer: "Spectra signs and broadcasts Sui transfers in-app.",
            extraLines: sendPreviewStore.suiSendPreview.map {
                [
                    AppLocalization.format("Gas Budget: %llu MIST", $0.gasBudgetMist),
                    AppLocalization.format("Reference Gas Price: %llu", $0.referenceGasPrice),
                ]
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "Aptos",
            footer: "Spectra signs and broadcasts Aptos transfers in-app.",
            extraLines: sendPreviewStore.aptosSendPreview.map {
                [
                    AppLocalization.format("Max Gas Amount: %llu", $0.maxGasAmount),
                    AppLocalization.format("Gas Unit Price: %llu octas", $0.gasUnitPriceOctas),
                ]
            } ?? [])
        simpleFeeContent(selectedCoin: selectedCoin, chainName: "TON",
            footer: "Spectra signs and broadcasts TON transfers in-app.",
            extraLines: sendPreviewStore.tonSendPreview.map { [AppLocalization.format("Sequence Number: %u", $0.sequenceNumber)] } ?? [])
        if let selectedCoin { sendPreviewDetailsContent(for: selectedCoin) }
    }

    // MARK: — Network sub-sections


    @ViewBuilder
    private func utxoNetworkContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader("Advanced UTXO Mode")
            Toggle(AppLocalization.string("Enable Advanced Controls"), isOn: $store.sendAdvancedMode)
            if store.sendAdvancedMode {
                Stepper(
                    "Max Inputs: \(store.sendUTXOMaxInputCount == 0 ? "Auto" : "\(store.sendUTXOMaxInputCount)")",
                    value: $store.sendUTXOMaxInputCount, in: 0...50
                )
                if selectedCoin.chain == .litecoin {
                    let isMwebSend = store.sendAddress.hasPrefix("ltcmweb1") || store.sendAddress.hasPrefix("tmweb1")
                    Toggle(AppLocalization.string("Enable RBF Policy"), isOn: $store.sendEnableRBF)
                    if !isMwebSend {
                        Picker(AppLocalization.string("Change Strategy"), selection: $store.sendLitecoinChangeStrategy) {
                            ForEach(LitecoinChangeStrategy.allCases) { strategy in Text(strategy.displayName).tag(strategy) }
                        }.pickerStyle(.menu)
                    }
                    Text(AppLocalization.string(
                        isMwebSend
                            ? "MWEB peg-in: coins enter the MimbleWimble sidechain. Fee covers both the on-chain peg-in output and the ~1 kB MWEB extension block. Change strategy is ignored for MWEB sends."
                            : "For LTC sends, max input cap is applied for coin selection, RBF policy is encoded in input sequence numbers, and change strategy controls whether change uses a derived change path or your source address."
                    )).font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle(AppLocalization.string("RBF Intent"), isOn: $store.sendEnableRBF)
                    Toggle(AppLocalization.string("CPFP Intent"), isOn: $store.sendEnableCPFP)
                    if let caption = utxoAdvancedModeCaption(for: selectedCoin.chainName) {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Divider().opacity(0.3).padding(.vertical, 8)
    }

    @ViewBuilder
    private func feePriorityContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader("Fee Priority")
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Divider().opacity(0.3).padding(.vertical, 8)
    }

    @ViewBuilder
    private func utxoFeePreviewContent(selectedCoin: Coin) -> some View {
        let feeSymbol = selectedCoin.symbol
        let utxoPreview = utxoPreview(for: selectedCoin)
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainName)) {
                ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains."))
                .font(.caption).foregroundStyle(.secondary)
            if selectedCoin.chain == .dogecoin, store.preparingChains.contains("Dogecoin") {
                SpectraLoadingRow(title: "Loading UTXOs and fee estimate...")
            } else if selectedCoin.chain == .dogecoin, let dogecoinSendPreview = sendPreviewStore.dogecoinSendPreview {
                if let fiatFee = store.formattedFiatAmount(fromNative: dogecoinSendPreview.estimatedNetworkFee, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.6f %@ (~%@)",
                            dogecoinSendPreview.estimatedNetworkFee, feeSymbol, fiatFee
                        )
                    )
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.6f %@", dogecoinSendPreview.estimatedNetworkFee, feeSymbol))
                }
                Text(AppLocalization.format("Confirmation Preference: %@", confirmationPreferenceText(for: dogecoinSendPreview.feePriority)))
            } else if let utxoPreview {
                Text(AppLocalization.format("Estimated Fee Rate: %@ sat/vB", "\(utxoPreview.estimatedFeeRateSatVb)"))
                if let fiatFee = store.formattedFiatAmount(fromNative: utxoPreview.estimatedNetworkFee, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.8f %@ (~%@)",
                            utxoPreview.estimatedNetworkFee, feeSymbol, fiatFee
                        )
                    )
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.8f %@", utxoPreview.estimatedNetworkFee, feeSymbol))
                }
            } else {
                Text(AppLocalization.format("Enter amount to preview estimated %@ network fee.", selectedCoin.chainName))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func evmNetworkContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Toggle(AppLocalization.string("Use Custom Fees"), isOn: $store.useCustomEvmFees)
            if store.useCustomEvmFees {
                TextField(AppLocalization.string("Max Fee (gwei)"), text: $store.customEvmMaxFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                TextField(AppLocalization.string("Priority Fee (gwei)"), text: $store.customEvmPriorityFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                if let customEvmFeeValidationError = store.customEvmFeeValidationError {
                    Text(customEvmFeeValidationError).font(.caption).foregroundStyle(.red)
                } else {
                    Text(AppLocalization.string("Custom EIP-1559 fees are applied to this send and preview."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(AppLocalization.string("Manual Nonce"), isOn: $store.evmManualNonceEnabled)
            if store.evmManualNonceEnabled {
                TextField(AppLocalization.string("Nonce"), text: $store.evmManualNonce)
                    .keyboardType(.numberPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                if let evmNonceValidationError = store.evmNonceValidationError {
                    Text(evmNonceValidationError).font(.caption).foregroundStyle(.red)
                }
            }
            // Replacement is offered wherever core says a pending send can
            // still be replaced — every EVM chain, not the one named Ethereum.
            if store.isPreparingReplacementContext {
                SpectraLoadingRow(title: "Preparing replacement/cancel context...")
            } else if let pending = store.replaceableSendForSelectedWallet {
                if pending.canSpeedUp {
                    Button(AppLocalization.string("Speed Up Pending Transaction")) {
                        spectraHaptic(.medium)
                        Task { await store.prepareSpeedUpContext() }
                    }
                }
                Button(AppLocalization.string("Cancel Pending Transaction")) {
                    spectraHaptic(.medium)
                    Task { await store.prepareCancelContext() }
                }
            }
            if let replacementNonceStateMessage = store.replacementNonceStateMessage {
                Text(replacementNonceStateMessage).font(.caption).foregroundStyle(.secondary)
            }
            if store.preparingChains.contains("Ethereum") {
                SpectraLoadingRow(title: "Loading nonce and fee estimate...")
            } else if let evmSendPreview = sendPreviewStore.evmSendPreview {
                Text(AppLocalization.format("Nonce: %lld", evmSendPreview.nonce))
                Text(AppLocalization.format("Gas Limit: %lld", evmSendPreview.gasLimit))
                Text(AppLocalization.format("Max Fee: %.2f gwei", evmSendPreview.maxFeePerGasGwei))
                Text(AppLocalization.format("Priority Fee: %.2f gwei", evmSendPreview.maxPriorityFeePerGasGwei))
                let feeSymbol = evmFeeSymbol(for: selectedCoin.chainName)
                if let fiatFee = store.formattedFiatAmount(fromNative: evmSendPreview.estimatedNetworkFee, symbol: feeSymbol) {
                    Text(
                        AppLocalization.format(
                            "Estimated Network Fee: %.6f %@ (~%@)",
                            evmSendPreview.estimatedNetworkFee, feeSymbol, fiatFee
                        )
                    )
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(AppLocalization.format("Estimated Network Fee: %.6f %@", evmSendPreview.estimatedNetworkFee, feeSymbol))
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Text(AppLocalization.string("Enter an amount to load a live nonce and fee preview. Add a valid destination address before sending."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(
                AppLocalization.format(
                    "Spectra signs and broadcasts supported %@ transfers. This preview is the live nonce and fee estimate for the transaction you are about to send.",
                    selectedCoin.chainName
                )
            )
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One chain's fee card.
    ///
    /// `isPreparing` and the fee triple used to be passed in at all eleven call
    /// sites: `store.preparingChains.contains(chainName)`, and the preview's
    /// fee with its symbol and format specifier. All four follow from the chain
    /// name — the symbol is `gasTokenSymbol`, the precision is
    /// `sendExecutionShape.feeDecimals`, and the preview is keyed by chain.
    /// What a caller still supplies is what the registry cannot: the footer
    /// sentence and whatever that chain shows beside its fee.
    @ViewBuilder
    private func simpleFeeContent(
        selectedCoin: Coin?, chainName: String,
        footer: String, extraLines: [String] = [], extraCaption: String? = nil
    ) -> some View {
        let isPreparing = store.preparingChains.contains(chainName)
        let chain = Chain(displayName: chainName)
        let fee: (amount: Double, symbol: String, specifier: String)? =
            sendPreviewStore.estimatedFee(forChainNamed: chainName).map { amount in
                (amount, chain?.gasTokenSymbol ?? "",
                 "%.\(Int(chain?.sendExecutionShape?.feeDecimals ?? 6))f")
            }
        if let selectedCoin, selectedCoin.chainName == chainName {
            VStack(alignment: .leading, spacing: 10) {
                networkSectionHeader(AppLocalization.format("%@ Network", chainName))
                if isPreparing {
                    SpectraLoadingRow(title: AppLocalization.format("Loading %@ fee estimate...", chainName))
                } else if let fee {
                    let feeFormatted = String(format: fee.specifier, fee.amount)
                    if let fiatFee = store.formattedFiatAmount(fromNative: fee.amount, symbol: fee.symbol) {
                        Text(AppLocalization.format("Estimated Network Fee: %@ %@ (~%@)", feeFormatted, fee.symbol, fiatFee)).font(.subheadline.weight(.semibold))
                    } else {
                        Text(AppLocalization.format("Estimated Network Fee: %@ %@", feeFormatted, fee.symbol)).font(.subheadline.weight(.semibold))
                    }
                    ForEach(extraLines, id: \.self) { Text($0) }
                    if let extraCaption { Text(AppLocalization.string(extraCaption)).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text(AppLocalization.format("Enter an amount to load a %@ fee preview. Add a valid destination address before sending.", chainName))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(AppLocalization.string(footer)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sendPreviewDetailsContent(for selectedCoin: Coin) -> some View {
        if let details = store.sendPreviewDetails(for: selectedCoin), details.hasVisibleContent {
            VStack(alignment: .leading, spacing: 8) {
                networkSectionHeader(AppLocalization.string("Preview Details"))
                if let spendableBalance = details.spendableBalance {
                    Text(AppLocalization.format("Spendable Balance: %@", formattedPreviewAssetAmount(spendableBalance, for: selectedCoin)))
                }
                if let feeRateDescription = details.feeRateDescription { Text(AppLocalization.format("Fee Rate: %@", feeRateDescription)) }
                if let estimatedTransactionBytes = details.estimatedTransactionBytes {
                    Text(AppLocalization.format("Estimated Size: %lld bytes", estimatedTransactionBytes))
                }
                if let selectedInputCount = details.selectedInputCount { Text(AppLocalization.format("Selected Inputs: %lld", selectedInputCount)) }
                if let usesChangeOutput = details.usesChangeOutput {
                    Text(AppLocalization.format("Change Output: %@", usesChangeOutput ? AppLocalization.string("Yes") : AppLocalization.string("No")))
                }
                if let maxSendable = details.maxSendable {
                    Text(AppLocalization.format("Max Sendable: %@", formattedPreviewAssetAmount(maxSendable, for: selectedCoin)))
                }
            }
        }
    }

    private func chainFeePriorityBinding(for chainName: String) -> Binding<ChainFeePriorityOption> {
        Binding(get: { store.feePriorityOption(for: chainName) }, set: { store.setFeePriorityOption($0, for: chainName) })
    }

    /// The preview stored under this coin's own slot.
    ///
    /// Two arms named a chain and everything else fell through to Bitcoin's,
    /// so a send on Bitcoin SV, Dogecoin, Zcash, Dash, Decred or Bitcoin Gold
    /// showed Bitcoin's fee.
    private func utxoPreview(for coin: Coin) -> BitcoinSendPreview? {
        if case .utxo(let preview) = sendPreviewStore.taggedPreview(forChainNamed: coin.chainName) {
            return preview
        }
        return nil
    }

    private func utxoAdvancedModeCaption(for chainName: String) -> String? {
        switch Chain(displayName: chainName) {
        case .bitcoin:
            return AppLocalization.string("For Bitcoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        case .bitcoinCash:
            return AppLocalization.string("For Bitcoin Cash sends, advanced mode records RBF intent and applies the max-input cap for coin selection.")
        case .dogecoin:
            return AppLocalization.string("For Dogecoin sends, advanced mode records RBF/CPFP intent and applies the max-input cap for coin selection.")
        default: return nil
        }
    }

    private func evmFeeSymbol(for chainName: String) -> String {
        Chain(displayName: chainName)?.gasTokenSymbol ?? "ETH"
    }

    private func formattedPreviewAssetAmount(_ amount: Double, for coin: Coin) -> String {
        store.formattedAssetAmount(amount, symbol: coin.symbol, chainName: coin.chainName)
    }

    private func confirmationPreferenceText(for priority: String) -> String {
        switch ChainFeePriorityOption(rawValue: priority) ?? .normal {
        case .economy: return "Economy (cost-optimized)"
        case .normal: return "Normal (balanced)"
        case .priority: return "Priority (faster confirmation bias)"
        }
    }
}

/// Shared by the network card and the no-preview card that replaces it.
@ViewBuilder
private func networkSectionHeader(_ title: String) -> some View {
    Text(AppLocalization.string(title))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.bottom, 8)
}
