import SwiftUI

struct StakingView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        introCard
                        chainPickerCard
                        philosophyCard
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
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
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
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
                        .spectraPressable()
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: SpectraLayout.cardCornerRadius))
            .navigationDestination(for: StakingSupportedChain.self) { chain in
                ChainStakingDetailView(chain: chain)
            }
    }
    @ViewBuilder
    private func chainTile(_ chain: StakingSupportedChain) -> some View {
        let descriptor = chain.descriptor
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CoinBadge(
                    assetIdentifier: Coin.iconIdentifier(symbol: descriptor.symbol, chainName: descriptor.chainName),
                    fallbackText: descriptor.symbol, color: descriptor.tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.chainName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(descriptor.apyEstimate).font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(descriptor.shortMechanic).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(
                horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
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
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
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

private enum StakingDetailSection: String, CaseIterable, Identifiable {
    case overview
    case validators
    case actions
    case learn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .validators: return "Validators"
        case .actions: return "Actions"
        case .learn: return "Learn"
        }
    }
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
    @State private var selectedSection: StakingDetailSection = .overview
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
                detailSectionPicker
                selectedDetailSection(descriptor: descriptor)
                    .id(selectedSection)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.snappy(duration: 0.24), value: selectedSection)
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
    }

    @ViewBuilder
    private var detailSectionPicker: some View {
        Picker(AppLocalization.string("Staking Section"), selection: $selectedSection) {
            ForEach(StakingDetailSection.allCases) { section in
                Text(AppLocalization.string(section.title)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func selectedDetailSection(descriptor: StakingChainDescriptor) -> some View {
        switch selectedSection {
        case .overview:
            statsCard(descriptor: descriptor)
            if !vm.positions.isEmpty { positionsCard }
        case .validators:
            if vm.validators.isEmpty {
                loadingValidatorsCard
            } else {
                validatorsCard
            }
        case .actions:
            actionsCard(descriptor: descriptor)
            if !vm.positions.isEmpty { positionsCard }
        case .learn:
            explanationCard(descriptor: descriptor)
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
                SpectraLoadingGlyph(size: 30, tint: .orange)
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
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private var loadingValidatorsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Validators")).font(.headline)
            if vm.isLoading {
                SpectraLoadingRow(title: "Loading validators...")
            } else {
                Text(AppLocalization.string("Validator data will appear here once it is available for this chain."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
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
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func actionButton(_ action: StakingActionKind) -> some View {
        Button {
            spectraHaptic(.medium)
            Task { await vm.loadValidators() }
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
            .spectraPressable()
    }

    @ViewBuilder
    private func explanationCard(descriptor: StakingChainDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("How it works")).font(.headline)
            Text(descriptor.detailedExplanation).font(.subheadline).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
}

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
