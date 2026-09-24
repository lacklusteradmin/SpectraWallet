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

    /// The quote for the selected holding; nil while none is current.
    private var quote: OwnedSendPreview? { store.sendQuote }

    private func hasNetworkSendSections(for coin: Coin?) -> Bool {
        coin?.chain?.hasSendPreview ?? false
    }

    /// The quoted fee, with its display-currency value when core had one.
    private func networkFeeText(_ quote: OwnedSendPreview, chain: Chain) -> String? {
        guard let fee = quote.networkFee else { return nil }
        return AppLocalization.format(
            "Estimated Network Fee: %@", store.amounts.formattedNetworkFee(fee, value: quote.networkFeeValue, chain: chain))
    }

    var body: some View {
        networkStep(selectedCoin: selectedCoin)
    }

    private var selectedCoin: Coin? {
        store.availableSendCoins(for: store.sendFlow.walletId).first(where: { $0.holdingKey == store.sendFlow.holdingKey })
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

    /// One branch per preview shape. The chain decides which, through the
    /// registry; nothing here names one.
    @ViewBuilder
    private func networkCardContent(selectedCoin: Coin?) -> some View {
        if let selectedCoin, let chain = selectedCoin.chain {
            if chain.isEVM {
                evmNetworkContent(selectedCoin: selectedCoin, chain: chain)
            } else if selectedCoin.isUTXOChain, selectedCoin.isNativeCoin {
                utxoFeePreviewContent(selectedCoin: selectedCoin, chain: chain)
            } else {
                feePriorityContent(selectedCoin: selectedCoin)
                simpleFeeContent(selectedCoin: selectedCoin, chain: chain)
            }
            sendPreviewDetailsContent(for: selectedCoin)
        }
    }

    // MARK: — Network sub-sections

    @ViewBuilder
    private func feePriorityContent(selectedCoin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader("Fee Priority")
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainId)) {
                ForEach(FeePriority.allCases, id: \.self) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores this preference per chain. Some networks still use provider-managed fee estimation in this build."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Divider().opacity(0.3).padding(.vertical, 8)
    }

    @ViewBuilder
    private func utxoFeePreviewContent(selectedCoin: Coin, chain: Chain) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Picker(AppLocalization.string("Fee Priority"), selection: chainFeePriorityBinding(for: selectedCoin.chainId)) {
                ForEach(FeePriority.allCases, id: \.self) { priority in Text(priority.displayName).tag(priority) }
            }.pickerStyle(.segmented)
            Text(AppLocalization.string("Spectra stores fee priority separately for each UTXO chain and applies it to live send previews for supported chains."))
                .font(.caption).foregroundStyle(.secondary)
            // Loading was shown for the chain named Dogecoin only; every other
            // UTXO chain showed its stale preview, or the prompt, mid-fetch.
            if store.sendFlow.isPreparingPreview {
                SpectraLoadingRow(title: "Loading UTXOs and fee estimate...")
            } else if let quote {
                if case .utxo(let preview) = quote.preview {
                    Text(AppLocalization.format("Estimated Fee Rate: %@ sat/vB", "\(preview.estimatedFeeRateSatVb)"))
                }
                if let fee = networkFeeText(quote, chain: chain) { Text(fee) }
                if case .dogecoin(let preview) = quote.preview {
                    Text(AppLocalization.format("Confirmation Preference: %@", confirmationPreferenceText(for: preview.feePriority)))
                }
            } else {
                Text(AppLocalization.format("Enter amount to preview estimated %@ network fee.", selectedCoin.chainName))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func evmNetworkContent(selectedCoin: Coin, chain: Chain) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", selectedCoin.chainName))
            Toggle(AppLocalization.string("Use Custom Fees"), isOn: Bindable(store.sendFlow).useCustomEvmFees)
            if store.sendFlow.useCustomEvmFees {
                TextField(AppLocalization.string("Max Fee (gwei)"), text: Bindable(store.sendFlow).customEvmMaxFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                TextField(AppLocalization.string("Priority Fee (gwei)"), text: Bindable(store.sendFlow).customEvmPriorityFeeGwei)
                    .keyboardType(.decimalPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                if let customEvmFeeValidationError = store.customEvmFeeValidationError {
                    Text(customEvmFeeValidationError).font(.caption).foregroundStyle(.red)
                } else {
                    Text(AppLocalization.string("Custom EIP-1559 fees are applied to this send and preview."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(AppLocalization.string("Manual Nonce"), isOn: Bindable(store.sendFlow).evmManualNonceEnabled)
            if store.sendFlow.evmManualNonceEnabled {
                TextField(AppLocalization.string("Nonce"), text: Bindable(store.sendFlow).evmManualNonce)
                    .keyboardType(.numberPad).padding(.horizontal, 12).padding(.vertical, 10)
                    .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                if let evmNonceValidationError = store.evmNonceValidationError {
                    Text(evmNonceValidationError).font(.caption).foregroundStyle(.red)
                }
            }
            // Replacement is offered wherever core says a pending send can
            // still be replaced — every EVM chain, not the one named Ethereum.
            if store.sendFlow.isPreparingReplacement {
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
            if store.sendFlow.isPreparingPreview {
                SpectraLoadingRow(title: "Loading nonce and fee estimate...")
            } else if let quote, case .ethereum(let evmSendPreview) = quote.preview {
                Text(AppLocalization.format("Nonce: %lld", evmSendPreview.nonce))
                Text(AppLocalization.format("Gas Limit: %lld", evmSendPreview.gasLimit))
                Text(AppLocalization.format("Max Fee: %@", store.amounts.formattedGasPrice(gwei: evmSendPreview.maxFeePerGasGwei, chain: chain)))
                Text(AppLocalization.format("Priority Fee: %@", store.amounts.formattedGasPrice(gwei: evmSendPreview.maxPriorityFeePerGasGwei, chain: chain)))
                if let fee = networkFeeText(quote, chain: chain) {
                    Text(fee).font(.subheadline.weight(.semibold))
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

    /// The fee card for every chain whose preview is neither the UTXO nor the
    /// EVM shape.
    ///
    /// Was twelve calls, each naming a chain and handing over its sentence,
    /// eleven of which rendered nothing on any given screen. The twelve were
    /// the registry's `simple_preview_chain` list plus Tron and minus
    /// Bittensor, whose send had a preview and got no card. What each call
    /// supplied is now read: the sentence from `sendBroadcastMode`, the gas
    /// caption from whether the coin is the chain's native asset, and the
    /// extra lines from a switch over core's preview enum.
    @ViewBuilder
    private func simpleFeeContent(selectedCoin: Coin, chain: Chain) -> some View {
        let chainName = selectedCoin.chainName
        VStack(alignment: .leading, spacing: 10) {
            networkSectionHeader(AppLocalization.format("%@ Network", chainName))
            if store.sendFlow.isPreparingPreview {
                SpectraLoadingRow(title: AppLocalization.format("Loading %@ fee estimate...", chainName))
            } else if let quote {
                if let fee = networkFeeText(quote, chain: chain) {
                    Text(fee).font(.subheadline.weight(.semibold))
                }
                ForEach(previewDetailLines(quote.preview), id: \.self) { Text($0) }
                // Every token pays its chain's gas token, which Tron and
                // Solana each said in a sentence of their own and no other
                // token-hosting chain said at all.
                if !selectedCoin.isNativeCoin {
                    Text(AppLocalization.format("Token transfers on %@ pay network fees in %@. Keep a %@ balance for fees.", chainName, chain.gasTokenSymbol, chain.gasTokenSymbol))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(AppLocalization.format("Enter an amount to load a %@ fee preview. Add a valid destination address before sending.", chainName))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(broadcastModeText(for: chain)).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What core does with a send on this chain, as the card says it.
    private func broadcastModeText(for chain: Chain) -> String {
        switch chain.sendBroadcastMode {
        case .signsAndBroadcasts:
            return AppLocalization.format("Spectra signs and broadcasts %@ transfers in-app.", chain.displayName)
        case .preparesWithBackend:
            return AppLocalization.format("Spectra prepares %@ sends in-app using the configured backend fee quote.", chain.displayName)
        case nil:
            return ""
        }
    }

    /// The chain-specific fields a preview carries beside its fee.
    ///
    /// Exhaustive over core's enum on purpose: a new preview variant is a
    /// compile error here rather than a card that quietly shows only the fee.
    private func previewDetailLines(_ preview: SendPreview) -> [String] {
        switch preview {
        case .xrp(let p):
            return [
                p.sequence > 0 ? AppLocalization.format("Sequence: %lld", p.sequence) : nil,
                p.lastLedgerSequence > 0 ? AppLocalization.format("Last Ledger Sequence: %lld", p.lastLedgerSequence) : nil,
            ].compactMap { $0 }
        case .stellar(let p):
            return p.sequence > 0 ? [AppLocalization.format("Sequence: %lld", p.sequence)] : []
        case .cardano(let p):
            return p.ttlSlot > 0 ? [AppLocalization.format("TTL Slot: %lld", p.ttlSlot)] : []
        case .monero(let p):
            return [AppLocalization.format("Priority: %@", p.priorityLabel)]
        case .sui(let p):
            return [
                AppLocalization.format("Gas Budget: %llu MIST", p.gasBudgetMist),
                AppLocalization.format("Reference Gas Price: %llu", p.referenceGasPrice),
            ]
        case .aptos(let p):
            return [
                AppLocalization.format("Max Gas Amount: %llu", p.maxGasAmount),
                AppLocalization.format("Gas Unit Price: %llu octas", p.gasUnitPriceOctas),
            ]
        case .ton(let p):
            return [AppLocalization.format("Sequence Number: %u", p.sequenceNumber)]
        case .utxo, .dogecoin, .ethereum, .tron, .solana, .icp, .near, .polkadot, .bittensor:
            return []
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

    private func chainFeePriorityBinding(for chainId: String) -> Binding<FeePriority> {
        Binding(get: { store.feePriority(forChainId: chainId) }, set: { store.setFeePriority($0, forChainId: chainId) })
    }

    private func formattedPreviewAssetAmount(_ amount: String, for coin: Coin) -> String {
        store.amounts.formattedAssetAmount(amount, symbol: coin.symbol, deploymentId: coin.holdingKey)
    }

    /// Core reads the stored spelling; the parenthetical is this view's.
    private func confirmationPreferenceText(for priority: String) -> String {
        switch parseFeePriority(raw: priority) {
        case .economy: return AppLocalization.string("Economy (cost-optimized)")
        case .normal: return AppLocalization.string("Normal (balanced)")
        case .priority: return AppLocalization.string("Priority (faster confirmation bias)")
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
