import SwiftUI

struct StakingView: View {
    let bridge: WalletServiceBridge
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                        introCard
                        chainPickerCard
                        philosophyCard
                    }.spectraScreenPadding()
                }
            }.navigationTitle(AppLocalization.string("Staking")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
    @ViewBuilder
    private var introCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "link.circle.fill").font(.title3).foregroundStyle(.tint)
                Text(AppLocalization.string("Earn While Securing Networks")).font(.title3.weight(.bold))
            }
            Text(AppLocalization.string("Explore staking networks and their validators. Transaction actions are not available in this app yet."))
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraElevatedFill()
    }
    private var chainPickerCard: some View {
        let entries = CoreReferenceTables.stakingChains
        return SpectraRowGroup(
            title: AppLocalization.string("Supported Chains"), trailing: "\(entries.count)", data: entries
        ) { entry in
            NavigationLink(value: entry.chain) { chainRow(entry) }.buttonStyle(.plain)
        }
        .navigationDestination(for: Chain.self) { chain in
            ChainStakingDetailView(chain: chain, bridge: bridge)
        }
    }
    /// The mechanic is left to the chain's page, whose header shows it: here
    /// it wrapped every row to three lines.
    private func chainRow(_ entry: StakingChainEntry) -> some View {
        let chain = entry.chain
        return HStack(spacing: SpectraLayout.Space.m) {
            CoinBadge(
                artworkName: AssetPresentationCatalog.artwork(deploymentId: chain.entry?.nativeDeploymentId),
                fallbackText: chain.gasTokenSymbol, color: chain.stakingTint, size: 36)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                Text(chain.displayName).font(.headline).foregroundStyle(Color.primary).lineLimit(1)
                Text(AppLocalization.string(entry.apyEstimate)).font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            Spacer(minLength: SpectraLayout.Space.s)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }.spectraRowPadding()
    }
    @ViewBuilder
    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            Text(AppLocalization.string("Why non-custodial staking")).font(.headline)
            Text(
                AppLocalization.string(
                    "Staking helps secure proof-of-stake networks by distributing validator power across many independent participants instead of relying on a centralized operator."
                )
            ).font(.subheadline).foregroundStyle(.secondary)
            Text(
                AppLocalization.string(
                    "This page provides staking information and validator queries. It does not sign or submit staking transactions."
                )
            ).font(.subheadline).foregroundStyle(.secondary)
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }
}

private enum StakingDetailSection: String, CaseIterable, Identifiable {
    case overview
    case validators
    case learn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .validators: return "Validators"
        case .learn: return "Learn"
        }
    }
}

extension StakingChainEntry: Identifiable {
    public var id: Chain { chain }
}

extension Chain {
    /// The chain's catalog colour, which every other badge of it uses.
    fileprivate var stakingTint: Color { entry?.color.color ?? .accentColor }
}

struct ChainStakingDetailView: View {
    let chain: Chain
    @State private var vm: StakingViewModel
    @State private var selectedSection: StakingDetailSection = .overview

    init(chain: Chain, bridge: WalletServiceBridge) {
        self.chain = chain
        self._vm = State(wrappedValue: StakingViewModel(chain: chain, bridge: bridge))
    }

    @ViewBuilder
    var body: some View {
        // Core's table is the only way in, and core refuses to load one that
        // misses a staking chain, so every chain reached here has a row.
        if let entry = CoreReferenceTables.stakingEntry(for: chain) {
            content(entry: entry)
        }
    }

    private func content(entry: StakingChainEntry) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                heroCard(entry: entry)
                detailSectionPicker
                selectedDetailSection(entry: entry)
                    .id(selectedSection)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.snappy(duration: 0.24), value: selectedSection)
            }.spectraScreenPadding()
        }
        .background(SpectraBackdrop().ignoresSafeArea())
        .navigationTitle(chain.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.loadValidators() }
        .alert(AppLocalization.string("Error"), isPresented: .isPresent($vm.error)) {
            Button(AppLocalization.string("OK")) { vm.dismissError() }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
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
    }

    @ViewBuilder
    private func selectedDetailSection(entry: StakingChainEntry) -> some View {
        switch selectedSection {
        case .overview:
            statsCard(entry: entry)
        case .validators:
            if vm.validators.isEmpty {
                loadingValidatorsCard
            } else {
                validatorsCard
            }
        case .learn:
            explanationCard(entry: entry)
        }
    }

    @ViewBuilder
    private func heroCard(entry: StakingChainEntry) -> some View {
        HStack(spacing: SpectraLayout.Space.m) {
            CoinBadge(
                artworkName: AssetPresentationCatalog.artwork(deploymentId: chain.entry?.nativeDeploymentId),
                fallbackText: chain.gasTokenSymbol, color: chain.stakingTint, size: 56)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                Text(chain.displayName).font(.title3.weight(.bold)).foregroundStyle(Color.primary)
                Text(AppLocalization.string(entry.apyEstimate)).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Text(AppLocalization.string(entry.shortMechanic)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if vm.isLoading {
                SpectraLoadingGlyph(size: 30, tint: .accentColor)
            }
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraElevatedFill()
    }

    @ViewBuilder
    private func statsCard(entry: StakingChainEntry) -> some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            statRow(label: AppLocalization.string("Estimated APY"), value: AppLocalization.string(entry.apyEstimate), icon: "percent")
            Divider().opacity(0.5)
            statRow(label: AppLocalization.string("Minimum Stake"), value: AppLocalization.string(entry.minimumStake), icon: "scalemass.fill")
            Divider().opacity(0.5)
            statRow(label: AppLocalization.string("Unbonding"), value: AppLocalization.string(entry.unbondingPeriod), icon: "hourglass")
            if !vm.validators.isEmpty {
                Divider().opacity(0.5)
                statRow(
                    label: AppLocalization.string("Validators"),
                    value: "\(vm.validators.count)",
                    icon: "server.rack"
                )
            }
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }

    @ViewBuilder
    private func statRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: SpectraLayout.Space.s) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.tint).frame(width: 20)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var validatorsCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
            Text(AppLocalization.string("Validators")).font(.headline)
            ForEach(vm.validators.prefix(5), id: \.identifier) { v in
                HStack(spacing: SpectraLayout.Space.s) {
                    VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
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
                .padding(.vertical, SpectraLayout.Space.xs)
            }
            if vm.validators.count > 5 {
                Text(AppLocalization.format("+%d more", vm.validators.count - 5))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }

    @ViewBuilder
    private var loadingValidatorsCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            Text(AppLocalization.string("Validators")).font(.headline)
            if vm.isLoading {
                SpectraLoadingRow(title: "Loading validators...")
            } else {
                Text(AppLocalization.string("Validator data will appear here once it is available for this chain."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    @ViewBuilder
    private func explanationCard(entry: StakingChainEntry) -> some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
            Text(AppLocalization.string("How it works")).font(.headline)
            Text(AppLocalization.string(entry.explanation)).font(.subheadline).foregroundStyle(.secondary)
        }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }
}
