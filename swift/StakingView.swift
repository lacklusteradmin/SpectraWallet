import SwiftUI

struct StakingView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SpectraLayout.sectionSpacing) {
                        introCard
                        chainPickerCard
                        philosophyCard
                    }.padding(.horizontal, SpectraLayout.screenHorizontal).padding(.top, SpectraLayout.screenTop).padding(
                        .bottom, SpectraLayout.screenBottom)
                }
            }.navigationTitle(AppLocalization.string("Staking")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
    @ViewBuilder
    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill").font(.title3).foregroundStyle(.orange)
                Text(AppLocalization.string("Earn While Securing Networks")).font(.title3.weight(.bold))
            }
            Text(AppLocalization.string("Pick a chain below to delegate, manage positions, and claim rewards — all non-custodial."))
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(SpectraLayout.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: SpectraLayout.cardCornerRadius))
    }
    @ViewBuilder
    private var chainPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Supported Chains")).font(.headline)
                Spacer()
                Text("\(StakingSupportedChain.allCases.count)").font(.caption.weight(.bold)).foregroundStyle(.orange).padding(
                    .horizontal, 8
                ).padding(.vertical, 3).background(Capsule(style: .continuous).fill(Color.orange.opacity(0.14)))
            }
            VStack(spacing: 8) {
                ForEach(StakingSupportedChain.allCases) { chain in
                    NavigationLink(value: chain) { chainTile(chain) }.buttonStyle(.plain)
                }
            }
        }.padding(SpectraLayout.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: SpectraLayout.cardCornerRadius))
            .navigationDestination(for: StakingSupportedChain.self) { chain in
                ChainStakingDetailView(chain: chain)
            }
    }
    @ViewBuilder
    private func chainTile(_ chain: StakingSupportedChain) -> some View {
        let descriptor = chain.descriptor
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                CoinBadge(
                    assetIdentifier: Coin.iconIdentifier(symbol: descriptor.symbol, chainName: descriptor.chainName),
                    fallbackText: descriptor.symbol, color: descriptor.tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.chainName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(descriptor.apyEstimate).font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(descriptor.shortMechanic).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(
                horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(
                Color.white.opacity(colorScheme == .light ? 0.55 : 0.05))
        ).overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(
                Color.primary.opacity(colorScheme == .light ? 0.10 : 0.07), lineWidth: 1)
        )
    }
    @ViewBuilder
    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Why non-custodial staking")).font(.headline)
            Text(
                AppLocalization.string(
                    "Staking helps secure proof-of-stake networks by distributing validator power across many independent participants instead of relying on a centralized operator."
                )
            ).font(.subheadline).foregroundStyle(.secondary)
            Text(
                AppLocalization.string(
                    "Spectra prioritizes non-custodial flows: keys stay on device, transactions are signed locally, and you pick the validator."
                )
            ).font(.subheadline).foregroundStyle(.secondary)
        }.padding(SpectraLayout.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: SpectraLayout.cardCornerRadius))
    }
}

private struct StakingChainDescriptor {
    let chainName: String
    let symbol: String
    let tint: Color
    let apyEstimate: String
    let shortMechanic: String
    let unbondingPeriod: String
    let minimumStake: String
    let actions: [StakingActionKind]
    let detailedExplanation: String
}

extension StakingSupportedChain {
    fileprivate var descriptor: StakingChainDescriptor {
        switch self {
        case .solana:
            return StakingChainDescriptor(
                chainName: "Solana", symbol: "SOL", tint: .purple, apyEstimate: "~6–7% APY",
                shortMechanic: "Delegate to a vote account; rewards each epoch (~2 days).",
                unbondingPeriod: "2–3 days deactivation", minimumStake: "≥ 0.001 SOL recommended",
                actions: [.stake, .unstake, .withdraw],
                detailedExplanation:
                    "Each stake position is its own on-chain stake account. Spectra creates a fresh keypair, initializes the account with `StakeProgram`, and delegates to the vote account you pick. Rewards land at every epoch boundary."
            )
        case .cardano:
            return StakingChainDescriptor(
                chainName: "Cardano", symbol: "ADA", tint: .indigo, apyEstimate: "~3% APY",
                shortMechanic: "Delegate to a stake pool; rewards every 5-day epoch.",
                unbondingPeriod: "No unbonding (instant)", minimumStake: "2 ADA registration deposit",
                actions: [.stake, .restake, .claimRewards, .unstake],
                detailedExplanation:
                    "First-time delegations register your stake address (refundable 2 ADA deposit) and attach a delegation certificate to your chosen pool. Re-delegating is just a new certificate — funds never leave your wallet."
            )
        case .sui:
            return StakingChainDescriptor(
                chainName: "Sui", symbol: "SUI", tint: .mint, apyEstimate: "~3% APY",
                shortMechanic: "Move call `request_add_stake` to a validator; epoch ~24h.",
                unbondingPeriod: "Until end of current epoch", minimumStake: "1 SUI",
                actions: [.stake, .unstake],
                detailedExplanation:
                    "Staking creates a `StakedSui` object owned by your wallet. To unstake, the same object is passed to `request_withdraw_stake`; principal + rewards return at the next epoch boundary."
            )
        case .aptos:
            return StakingChainDescriptor(
                chainName: "Aptos", symbol: "APT", tint: .cyan, apyEstimate: "~7% APY",
                shortMechanic: "Add stake to a delegation pool; epoch ~2h.",
                unbondingPeriod: "~30-day lockup cycle", minimumStake: "11 APT to a delegation pool",
                actions: [.stake, .unstake, .withdraw],
                detailedExplanation:
                    "Calls `0x1::delegation_pool::add_stake` against a pool address. Stake activates at the next epoch. Unlock moves it to a pending-inactive bucket; after the lockup cycle (typically 30 days) it becomes withdrawable."
            )
        case .near:
            return StakingChainDescriptor(
                chainName: "NEAR", symbol: "NEAR", tint: .indigo, apyEstimate: "~9% APY",
                shortMechanic: "`deposit_and_stake` on a `*.poolv1.near` contract.",
                unbondingPeriod: "~52h (4 epochs)", minimumStake: "Pool-dependent",
                actions: [.stake, .unstake, .withdraw],
                detailedExplanation:
                    "Each validator runs its own staking-pool contract. Spectra calls `deposit_and_stake` with NEAR attached. Unstake places funds into a pending bucket; after 4 epochs (~52h) they're withdrawable via `withdraw`."
            )
        case .polkadot:
            return StakingChainDescriptor(
                chainName: "Polkadot", symbol: "DOT", tint: .pink, apyEstimate: "~14% APY",
                shortMechanic: "Bond + nominate up to 16 validators, OR join a nomination pool.",
                unbondingPeriod: "28 days", minimumStake: "Direct: 250 DOT · Pool: 1 DOT",
                actions: [.stake, .unstake, .withdraw, .restake],
                detailedExplanation:
                    "Two paths: direct nomination (`staking::bond` + `staking::nominate`, requires the chain's active minimum bond, currently ~250 DOT) or nomination pools (`nomination_pools::join`, no minimum, recommended for smaller stakers)."
            )
        case .icp:
            return StakingChainDescriptor(
                chainName: "Internet Computer", symbol: "ICP", tint: .indigo, apyEstimate: "Up to ~14% APY",
                shortMechanic: "Lock ICP into a neuron; rewards scale with dissolve delay.",
                unbondingPeriod: "Dissolve delay (6 months – 8 years)", minimumStake: "1 ICP",
                actions: [.stake, .restake, .claimRewards, .unstake, .withdraw],
                detailedExplanation:
                    "Staking on ICP means creating an NNS neuron with a chosen dissolve delay (≥ 6 months for rewards eligibility, up to 8 years for max maturity bonus). Voting on proposals — directly or via followees — drives the reward rate."
            )
        }
    }
}

struct ChainStakingDetailView: View {
    let chain: StakingSupportedChain
    @State private var vm: StakingViewModel
    @State private var pendingAction: StakingActionKind? = nil
    @Environment(\.colorScheme) private var colorScheme

    init(chain: StakingSupportedChain) {
        self.chain = chain
        self._vm = State(wrappedValue: StakingViewModel(chain: chain))
    }

    var body: some View {
        let descriptor = chain.descriptor
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                heroCard(descriptor: descriptor)
                statsCard(descriptor: descriptor)
                if !vm.validators.isEmpty { validatorsCard }
                if !vm.positions.isEmpty { positionsCard }
                actionsCard(descriptor: descriptor)
                explanationCard(descriptor: descriptor)
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(descriptor.chainName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.loadValidators() }
        .alert(AppLocalization.string("Error"), isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.dismissError() } }
        )) {
            Button(AppLocalization.string("OK")) { vm.dismissError() }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
        .sheet(isPresented: Binding(
            get: { vm.preview != nil },
            set: { if !$0 { vm.dismissPreview() } }
        )) {
            if let preview = vm.preview {
                StakingPreviewSheet(preview: preview, onDismiss: { vm.dismissPreview() })
            }
        }
        .sheet(item: $pendingAction) { action in
            StakingActionInputSheet(chain: chain, action: action, vm: vm) {
                pendingAction = nil
            }
        }
    }

    @ViewBuilder
    private func heroCard(descriptor: StakingChainDescriptor) -> some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: Coin.iconIdentifier(symbol: descriptor.symbol, chainName: descriptor.chainName),
                fallbackText: descriptor.symbol, color: descriptor.tint, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.chainName).font(.title3.weight(.bold)).foregroundStyle(Color.primary)
                Text(descriptor.apyEstimate).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Text(descriptor.shortMechanic).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if vm.isLoading {
                ProgressView().tint(.orange)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private func statsCard(descriptor: StakingChainDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            statRow(label: AppLocalization.string("Estimated APY"), value: descriptor.apyEstimate, icon: "percent")
            Divider().opacity(0.5)
            statRow(label: AppLocalization.string("Minimum Stake"), value: descriptor.minimumStake, icon: "scalemass.fill")
            Divider().opacity(0.5)
            statRow(label: AppLocalization.string("Unbonding"), value: descriptor.unbondingPeriod, icon: "hourglass")
            if !vm.validators.isEmpty {
                Divider().opacity(0.5)
                statRow(
                    label: AppLocalization.string("Validators"),
                    value: "\(vm.validators.count)",
                    icon: "server.rack"
                )
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private func statRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 20)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var validatorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("Validators")).font(.headline)
            ForEach(vm.validators.prefix(5), id: \.identifier) { v in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let commission = v.commission {
                            Text(AppLocalization.format("%.0f%% commission", commission * 100))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(AppLocalization.format("%.1f%% APY", v.apy * 100))
                        .font(.caption.weight(.bold)).foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            }
            if vm.validators.count > 5 {
                Text(AppLocalization.format("+%d more", vm.validators.count - 5))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private var positionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("Your Positions")).font(.headline)
            ForEach(vm.positions, id: \.validatorIdentifier) { pos in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pos.validatorDisplayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(pos.status.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pos.stakedAmountSmallestUnit).font(.caption.weight(.semibold)).foregroundStyle(Color.primary)
                }
                .padding(.vertical, 4)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private func actionsCard(descriptor: StakingChainDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Actions")).font(.headline)
            VStack(spacing: 8) {
                ForEach(descriptor.actions) { action in
                    actionButton(action)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }

    @ViewBuilder
    private func actionButton(_ action: StakingActionKind) -> some View {
        Button {
            spectraHaptic(.medium)
            pendingAction = action
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemIconName).font(.title3.weight(.semibold)).foregroundStyle(.orange).frame(
                    width: 28, height: 28
                ).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(action.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 12).background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    Color.white.opacity(colorScheme == .light ? 0.55 : 0.05))
            ).overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                    Color.primary.opacity(colorScheme == .light ? 0.10 : 0.07), lineWidth: 1)
            )
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func explanationCard(descriptor: StakingChainDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("How it works")).font(.headline)
            Text(descriptor.detailedExplanation).font(.subheadline).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
    }
}

// ── Action input sheet ────────────────────────────────────────────────────────

private struct StakingActionInputSheet: View {
    let chain: StakingSupportedChain
    let action: StakingActionKind
    let vm: StakingViewModel
    let onDismiss: () -> Void

    @State private var walletAddress = ""
    @State private var amountText = ""
    @State private var validatorOrPoolId = ""
    @State private var selectedValidatorIdx = 0
    @State private var useValidatorPicker = false
    @State private var dissolveDelayMonths: Double = 6
    @State private var neuronIdText = ""
    @State private var additionalMonths: Double = 12
    @Environment(\.colorScheme) private var colorScheme

    private var spec: ActionInputSpec { ActionInputSpec(chain: chain, action: action) }

    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        inputField(
                            label: AppLocalization.string("Your Wallet Address"),
                            hint: spec.walletHint,
                            text: $walletAddress,
                            keyboardType: .default
                        )
                        if spec.needsValidatorId {
                            validatorField
                        }
                        if spec.needsAmount {
                            inputField(
                                label: AppLocalization.string("Amount"),
                                hint: spec.amountHint,
                                text: $amountText,
                                keyboardType: .decimalPad
                            )
                        }
                        if spec.needsDissolveDelay {
                            dissolveDelayField
                        }
                        if spec.needsNeuronId {
                            inputField(
                                label: AppLocalization.string("Neuron ID"),
                                hint: "e.g. 6914974521667616512",
                                text: $neuronIdText,
                                keyboardType: .numberPad
                            )
                        }
                        if spec.needsAdditionalMonths {
                            additionalMonthsField
                        }
                        confirmButton
                    }.padding(20)
                }
            }
            .navigationTitle(action.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { onDismiss() }
                }
            }
        }
        .onAppear {
            if !vm.validators.isEmpty {
                useValidatorPicker = true
                validatorOrPoolId = vm.validators[0].identifier
            }
        }
    }

    @ViewBuilder
    private var validatorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.validatorIdLabel).font(.subheadline.weight(.semibold))
            if useValidatorPicker && !vm.validators.isEmpty {
                Picker(spec.validatorIdLabel, selection: $selectedValidatorIdx) {
                    ForEach(vm.validators.indices, id: \.self) { idx in
                        Text(vm.validators[idx].displayName).tag(idx)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .light ? 0.55 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .onChange(of: selectedValidatorIdx) { _, newIdx in
                    validatorOrPoolId = vm.validators[newIdx].identifier
                }
            } else {
                inputField(
                    label: nil,
                    hint: spec.validatorIdHint,
                    text: $validatorOrPoolId,
                    keyboardType: .default
                )
            }
        }
    }

    @ViewBuilder
    private var dissolveDelayField: some View {
        sliderField(
            label: AppLocalization.string("Dissolve Delay"),
            subtitle: AppLocalization.format("%.0f months (~%.1f years)", dissolveDelayMonths, dissolveDelayMonths / 12),
            value: $dissolveDelayMonths, range: 6...96
        )
    }

    @ViewBuilder
    private var additionalMonthsField: some View {
        sliderField(
            label: AppLocalization.string("Additional Delay"),
            subtitle: AppLocalization.format("%.0f additional months", additionalMonths),
            value: $additionalMonths, range: 1...96
        )
    }

    @ViewBuilder
    private func sliderField(label: String, subtitle: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1).tint(.orange)
        }.padding(14).background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .light ? 0.55 : 0.07))
        ).overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func inputField(label: String?, hint: String, text: Binding<String>, keyboardType: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(label).font(.subheadline.weight(.semibold)) }
            TextField(hint, text: text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .light ? 0.55 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        Button {
            spectraHaptic(.medium)
            Task {
                await buildTx()
                onDismiss()
            }
        } label: {
            HStack {
                Spacer()
                if vm.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(AppLocalization.string("Preview Transaction")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange))
        }.buttonStyle(.plain).disabled(walletAddress.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
    }

    // ── Dispatch to the right VM method ──────────────────────────────────────

    private func buildTx() async {
        let address = walletAddress.trimmingCharacters(in: .whitespaces)
        let valId = useValidatorPicker && !vm.validators.isEmpty
            ? vm.validators[min(selectedValidatorIdx, vm.validators.count - 1)].identifier
            : validatorOrPoolId.trimmingCharacters(in: .whitespaces)

        switch chain {
        case .solana:   await buildSolana(address: address, valId: valId)
        case .cardano:  await buildCardano(address: address, valId: valId)
        case .sui:      await buildSui(address: address, valId: valId)
        case .aptos:    await buildAptos(address: address, valId: valId)
        case .near:     await buildNear(address: address, valId: valId)
        case .polkadot: await buildPolkadot(address: address, valId: valId)
        case .icp:      await buildIcp(address: address)
        }
    }

    private func buildSolana(address: String, valId: String) async {
        switch action {
        case .stake:
            await vm.solanaBuildStakeTx(walletAddress: address, amountLamports: toSmallestUnit(amountText, decimals: 9), voteAccount: valId)
        case .unstake:
            await vm.solanaBuildDeactivateTx(walletAddress: address, stakeAccount: valId)
        case .withdraw:
            await vm.solanaBuildWithdrawTx(walletAddress: address, stakeAccount: valId, amountLamports: toSmallestUnit(amountText, decimals: 9))
        default: break
        }
    }

    private func buildCardano(address: String, valId: String) async {
        switch action {
        case .stake, .restake:
            await vm.cardanoBuildDelegateTx(walletAddress: address, poolId: valId)
        case .claimRewards:
            await vm.cardanoBuildClaimRewardsTx(walletAddress: address, amountLovelace: toSmallestUnit(amountText, decimals: 6))
        case .unstake:
            await vm.cardanoBuildDeregisterTx(walletAddress: address)
        default: break
        }
    }

    private func buildSui(address: String, valId: String) async {
        switch action {
        case .stake:
            await vm.suiBuildAddStakeTx(walletAddress: address, amountMist: toSmallestUnit(amountText, decimals: 9), validatorAddress: valId)
        case .unstake:
            await vm.suiBuildWithdrawStakeTx(walletAddress: address, stakedSuiObjectId: valId)
        default: break
        }
    }

    private func buildAptos(address: String, valId: String) async {
        switch action {
        case .stake:
            await vm.aptosBuildAddStakeTx(walletAddress: address, poolAddress: valId, amountOctas: toSmallestUnit(amountText, decimals: 8))
        case .unstake:
            await vm.aptosBuildUnlockTx(walletAddress: address, poolAddress: valId, amountOctas: toSmallestUnit(amountText, decimals: 8))
        case .withdraw:
            await vm.aptosBuildWithdrawTx(walletAddress: address, poolAddress: valId, amountOctas: toSmallestUnit(amountText, decimals: 8))
        default: break
        }
    }

    private func buildNear(address: String, valId: String) async {
        let yocto = nearToYocto(amountText)
        switch action {
        case .stake:
            await vm.nearBuildDepositAndStakeTx(walletAddress: address, poolAccountId: valId, amountYoctoNear: yocto)
        case .unstake:
            await vm.nearBuildUnstakeTx(walletAddress: address, poolAccountId: valId, amountYoctoNear: yocto)
        case .withdraw:
            await vm.nearBuildWithdrawTx(walletAddress: address, poolAccountId: valId, amountYoctoNear: yocto)
        default: break
        }
    }

    private func buildPolkadot(address: String, valId: String) async {
        let planck = dotToPlanck(amountText)
        switch action {
        case .stake:
            await vm.polkadotBuildJoinPoolTx(walletAddress: address, amountPlanck: planck, poolId: UInt32(valId) ?? 1)
        case .restake:
            await vm.polkadotBuildBondAndNominateTx(walletAddress: address, amountPlanck: planck, validatorAddresses: [valId])
        case .unstake:
            await vm.polkadotBuildUnbondTx(walletAddress: address, amountPlanck: planck)
        case .withdraw:
            await vm.polkadotBuildWithdrawUnbondedTx(walletAddress: address)
        default: break
        }
    }

    private func buildIcp(address: String) async {
        let neuronId = UInt64(neuronIdText.trimmingCharacters(in: .whitespaces)) ?? 0
        switch action {
        case .stake:
            await vm.icpBuildCreateNeuronTx(walletAddress: address, amountE8s: toSmallestUnit(amountText, decimals: 8), dissolveDelayMonths: UInt32(dissolveDelayMonths))
        case .restake:
            await vm.icpBuildIncreaseDissolveDelayTx(walletAddress: address, neuronId: neuronId, additionalMonths: UInt32(additionalMonths))
        case .claimRewards:
            await vm.icpBuildClaimMaturityTx(walletAddress: address, neuronId: neuronId)
        case .unstake:
            await vm.icpBuildStartDissolvingTx(walletAddress: address, neuronId: neuronId)
        case .withdraw:
            await vm.icpBuildDisburseTx(walletAddress: address, neuronId: neuronId, amountE8s: toSmallestUnit(amountText, decimals: 8))
        default: break
        }
    }

    // ── Unit conversion helpers ───────────────────────────────────────────────

    private func toSmallestUnit(_ display: String, decimals: Int) -> UInt64 {
        guard let value = Double(display.replacingOccurrences(of: ",", with: ".")) else { return 0 }
        return UInt64(max(0, value * pow(10.0, Double(decimals))))
    }

    private func nearToYocto(_ near: String) -> String {
        guard let dec = Decimal(string: near.replacingOccurrences(of: ",", with: ".")) else { return "0" }
        let factor = Decimal(string: "1000000000000000000000000")! // 10^24
        return NSDecimalNumber(decimal: dec * factor).stringValue
    }

    private func dotToPlanck(_ dot: String) -> String {
        guard let dec = Decimal(string: dot.replacingOccurrences(of: ",", with: ".")) else { return "0" }
        let factor = Decimal(10_000_000_000) // 10^10
        return NSDecimalNumber(decimal: dec * factor).stringValue
    }
}

// ── ActionInputSpec — describes which fields a given chain+action needs ────────

private struct ActionInputSpec {
    let walletHint: String
    let needsAmount: Bool
    let amountHint: String
    let needsValidatorId: Bool
    let validatorIdLabel: String
    let validatorIdHint: String
    let needsDissolveDelay: Bool
    let needsNeuronId: Bool
    let needsAdditionalMonths: Bool

    init(chain: StakingSupportedChain, action: StakingActionKind) {
        walletHint = chain.addressHint

        switch (chain, action) {

        // Solana
        case (.solana, .stake):
            needsAmount = true; amountHint = "e.g. 1.5 (SOL)"
            needsValidatorId = true; validatorIdLabel = "Vote Account"; validatorIdHint = "Vote account pubkey"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.solana, .unstake):
            needsAmount = false; amountHint = ""
            needsValidatorId = true; validatorIdLabel = "Stake Account"; validatorIdHint = "Stake account pubkey"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.solana, .withdraw):
            needsAmount = true; amountHint = "e.g. 1.5 (SOL)"
            needsValidatorId = true; validatorIdLabel = "Stake Account"; validatorIdHint = "Stake account pubkey"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // Cardano
        case (.cardano, .stake), (.cardano, .restake):
            needsAmount = false; amountHint = ""
            needsValidatorId = true; validatorIdLabel = "Pool ID (Bech32)"; validatorIdHint = "pool1..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.cardano, .claimRewards):
            needsAmount = true; amountHint = "e.g. 5.0 (ADA)"
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.cardano, .unstake):
            needsAmount = false; amountHint = ""
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // Sui
        case (.sui, .stake):
            needsAmount = true; amountHint = "e.g. 1.0 (SUI)"
            needsValidatorId = true; validatorIdLabel = "Validator Address"; validatorIdHint = "0x..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.sui, .unstake):
            needsAmount = false; amountHint = ""
            needsValidatorId = true; validatorIdLabel = "StakedSui Object ID"; validatorIdHint = "0x..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // Aptos
        case (.aptos, .stake):
            needsAmount = true; amountHint = "e.g. 11.0 (APT)"
            needsValidatorId = true; validatorIdLabel = "Delegation Pool Address"; validatorIdHint = "0x..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.aptos, .unstake):
            needsAmount = true; amountHint = "e.g. 11.0 (APT)"
            needsValidatorId = true; validatorIdLabel = "Delegation Pool Address"; validatorIdHint = "0x..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.aptos, .withdraw):
            needsAmount = true; amountHint = "e.g. 11.0 (APT)"
            needsValidatorId = true; validatorIdLabel = "Delegation Pool Address"; validatorIdHint = "0x..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // NEAR
        case (.near, .stake):
            needsAmount = true; amountHint = "e.g. 1.0 (NEAR)"
            needsValidatorId = true; validatorIdLabel = "Pool Account ID"; validatorIdHint = "pool.poolv1.near"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.near, .unstake):
            needsAmount = true; amountHint = "e.g. 1.0 (NEAR)"
            needsValidatorId = true; validatorIdLabel = "Pool Account ID"; validatorIdHint = "pool.poolv1.near"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.near, .withdraw):
            needsAmount = true; amountHint = "e.g. 1.0 (NEAR)"
            needsValidatorId = true; validatorIdLabel = "Pool Account ID"; validatorIdHint = "pool.poolv1.near"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // Polkadot
        case (.polkadot, .stake):
            needsAmount = true; amountHint = "e.g. 1.0 (DOT)"
            needsValidatorId = true; validatorIdLabel = "Pool ID"; validatorIdHint = "1"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.polkadot, .restake):
            needsAmount = true; amountHint = "e.g. 250.0 (DOT)"
            needsValidatorId = true; validatorIdLabel = "Validator Address"; validatorIdHint = "5Grpc4..."
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.polkadot, .unstake):
            needsAmount = true; amountHint = "e.g. 1.0 (DOT)"
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        case (.polkadot, .withdraw):
            needsAmount = false; amountHint = ""
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false

        // ICP
        case (.icp, .stake):
            needsAmount = true; amountHint = "e.g. 1.0 (ICP)"
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = true; needsNeuronId = false; needsAdditionalMonths = false

        case (.icp, .restake):
            needsAmount = false; amountHint = ""
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = true; needsAdditionalMonths = true

        case (.icp, .unstake):
            needsAmount = false; amountHint = ""
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = true; needsAdditionalMonths = false

        case (.icp, .claimRewards):
            needsAmount = false; amountHint = ""
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = true; needsAdditionalMonths = false

        case (.icp, .withdraw):
            needsAmount = true; amountHint = "e.g. 1.0 (ICP)"
            needsValidatorId = false; validatorIdLabel = ""; validatorIdHint = ""
            needsDissolveDelay = false; needsNeuronId = true; needsAdditionalMonths = false

        // Fallback for any unhandled combination
        default:
            needsAmount = true; amountHint = "Amount in native units"
            needsValidatorId = true; validatorIdLabel = "Validator / Pool ID"; validatorIdHint = "Identifier"
            needsDissolveDelay = false; needsNeuronId = false; needsAdditionalMonths = false
        }
    }
}

extension StakingSupportedChain {
    fileprivate var addressHint: String {
        switch self {
        case .solana:   return "Solana base58 public key"
        case .cardano:  return "addr1... or stake1..."
        case .sui:      return "0x..."
        case .aptos:    return "0x..."
        case .near:     return "account.near"
        case .polkadot: return "5Grpc4... (SS58)"
        case .icp:      return "Principal ID or account identifier"
        }
    }
}

// ── Preview sheet ─────────────────────────────────────────────────────────────

private struct StakingPreviewSheet: View {
    let preview: StakingActionPreview
    let onDismiss: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewRow(label: AppLocalization.string("Action"), value: preview.kind.displayName)
                    previewRow(label: AppLocalization.string("Validator"), value: preview.validatorDisplayName)
                    previewRow(label: AppLocalization.string("Amount"), value: preview.amountDisplay)
                    previewRow(label: AppLocalization.string("Estimated Fee"), value: preview.estimatedFeeDisplay)
                    if preview.unbondingPeriodSeconds > 0 {
                        let days = preview.unbondingPeriodSeconds / 86400
                        previewRow(label: AppLocalization.string("Unbonding"), value: AppLocalization.format("%d days", days))
                    }
                    ForEach(preview.notes, id: \.self) { note in
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .navigationTitle(AppLocalization.string("Transaction Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Close")) { onDismiss() }
                }
            }
        }
    }
    @ViewBuilder
    private func previewRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
        Divider().opacity(0.4)
    }
}
