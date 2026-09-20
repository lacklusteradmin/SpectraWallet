import SwiftUI
struct DashboardView: View {
    @Bindable var store: AppState
    @State private var dashboardPage: DashboardPage = .assets
    @State private var isNavigatingToPinnedAssets = false
    @State private var selectedWalletID: String?
    @State private var selectedAssetGroup: DashboardAssetGroup?
    private var deleteWalletMessage: String {
        guard let pendingWallet = store.walletPendingDeletion else { return "" }
        if store.isWatchOnlyWallet(pendingWallet) {
            return AppLocalization.string("You can't recover this wallet after deletion until you still have this address.")
        }
        return AppLocalization.string("Please take note of your seed phrase because you can't recover this wallet after deletion.")
    }
    private var selectedWallet: WalletView? {
        guard let selectedWalletID else { return nil }
        return store.wallet(for: selectedWalletID)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SpectraLayout.sectionSpacing) {
                        portfolioHeader
                        actionButtons
                        Picker(AppLocalization.string("Dashboard Section"), selection: $dashboardPage) {
                            Text(AppLocalization.string("Assets")).tag(DashboardPage.assets)
                            Text(AppLocalization.string("Wallets")).tag(DashboardPage.wallets)
                        }
                        .pickerStyle(.segmented)
                        assetsOrWalletsCard
                    }.padding(.horizontal, SpectraLayout.screenHorizontal).padding(.top, SpectraLayout.screenTop).padding(
                        .bottom, SpectraLayout.screenBottom)
                }.refreshable {
                    await store.performUserInitiatedRefresh()
                }.scrollBounceBehavior(.always)
            }
            .navigationTitle(AppLocalization.string("Spectra")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AppNoticesView(store: store)
                    } label: {
                        noticeToolbarLabel
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        TorSettingsView(store: store)
                    } label: {
                        torToolbarIndicator
                    }
                }
                if dashboardPage == .assets {
                    ToolbarItem(placement: .topBarTrailing) {
                        pinAssetsToolbarButton
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        spectraHaptic(.light)
                        store.isShowingAddWalletEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }.accessibilityLabel(AppLocalization.string("Add Wallet"))
                }
            }.navigationDestination(isPresented: $store.isShowingAddWalletEntry) {
                AddWalletEntryView(store: store)
            }.navigationDestination(item: $selectedWalletID) { walletID in
                if let wallet = store.wallets.first(where: { $0.id == walletID }) {
                    WalletDetailView(store: store, wallet: wallet)
                }
            }.navigationDestination(item: $selectedAssetGroup) { assetGroup in AssetGroupDetailView(store: store, assetGroup: assetGroup) }
                .navigationDestination(isPresented: $store.isShowingSendSheet) {
                    SendView(store: store)
                }.navigationDestination(
                    isPresented: $store.isShowingReceiveSheet
                ) {
                    ReceiveView(store: store)
                }.alert(
                    AppLocalization.string("Delete Wallet?"),
                    isPresented: .isPresent($store.walletPendingDeletion)
                ) {
                    Button(AppLocalization.string("Delete"), role: .destructive) {
                        Task {
                            await store.deletePendingWallet()
                        }
                    }
                    Button(AppLocalization.string("Cancel"), role: .cancel) {
                        store.walletPendingDeletion = nil
                    }
                } message: {
                    Text(deleteWalletMessage)
                }.navigationDestination(isPresented: $isNavigatingToPinnedAssets) {
                    PinnedAssetsView(store: store)
                }
        }
    }
    private var portfolioHeader: some View {
        DashboardPortfolioHeader(store: store)
    }
    private var noticeToolbarLabel: some View {
        let notices = activeNotices
        let count = notices.count
        let isEmpty = notices.isEmpty
        return ZStack(alignment: .topTrailing) {
            Image(systemName: isEmpty ? "tray" : "exclamationmark.bubble").font(.system(size: 18, weight: .semibold)).frame(
                width: 24, height: 24)
            if !isEmpty {
                Text("\(min(count, 9))").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red)).offset(x: 6, y: -5)
            }
        }.frame(width: 32, height: 28, alignment: .center).foregroundStyle(Color.primary).accessibilityLabel(
            isEmpty
                ? AppLocalization.string("No active notices")
                : AppLocalization.format("%lld active notices", count)
        )
    }
    private var torToolbarIndicator: some View {
        let status = store.torStatus
        let color: Color
        let icon: String
        switch status {
        case .ready:
            color = .green; icon = "network.badge.shield.half.filled"
        case .bootstrapping:
            color = .orange; icon = "network.badge.shield.half.filled"
        case .error:
            color = .red; icon = "network.slash"
        case .stopped:
            color = Color(.systemGray3); icon = "network"
        }
        return ZStack(alignment: .bottomTrailing) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            if case .bootstrapping(let pct) = status {
                Text("\(pct)%")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .offset(x: 6, y: 4)
            } else if case .error = status {
                Circle().fill(color).frame(width: 7, height: 7).offset(x: 3, y: 3)
            }
        }
        .frame(width: 30, height: 28, alignment: .center)
        .accessibilityLabel(torAccessibilityLabel(status))
    }
    private func torAccessibilityLabel(_ status: TorStatus) -> String {
        switch status {
        case .stopped:          return AppLocalization.string("Tor off")
        case .bootstrapping(let p): return AppLocalization.format("Tor connecting, %lld%%", Int(p))
        case .ready:            return AppLocalization.string("Tor on")
        case .error:            return AppLocalization.string("Tor error")
        }
    }
    private var actionButtons: some View {
        DashboardActionButtons(store: store)
    }
    private var assetsOrWalletsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(dashboardCardTitle).font(.headline)
                Spacer()
                Text(dashboardCardCountText).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            }.padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.cardHeaderVertical)
            Divider().opacity(0.25)
            VStack(spacing: 0) {
                switch dashboardPage {
                case .wallets: walletsCardRows(wallets: store.wallets)
                case .assets: assetsCardRows(portfolio: visiblePortfolio)
                }
            }.padding(.vertical, 4)
        }.frame(maxWidth: .infinity).glassEffect(
            .regular.tint(SpectraLayout.GlassTint.content).interactive(), in: .rect(cornerRadius: SpectraLayout.Radius.hero))
    }
    private var dashboardCardCountText: String {
        let count = dashboardPage == .assets ? visiblePortfolio.count : store.wallets.count
        return "\(count)"
    }
    @ViewBuilder
    private func walletsCardRows(wallets: [WalletView]) -> some View {
        if wallets.isEmpty {
            addWalletEmptyState
        } else {
            ForEach(Array(wallets.enumerated()), id: \.element.id) { index, wallet in
                let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, .mint)
                Button { selectedWalletID = wallet.id } label: {
                    WalletCardView(
                        presentation: WalletCardView.Presentation(
                            walletName: wallet.name, chainTitleText: store.displayChainTitle(for: wallet),
                            totalValueText: store.preferences.hideBalances
                                ? "••••••"
                                : store.formattedWalletTotal(walletID: wallet.id),
                            assetCountText: AppLocalization.format(
                                "%lld assets", wallet.holdings.filter { $0.amount > 0 }.count),
                            isWatchOnly: store.isWatchOnlyWallet(wallet), badgeArtworkName: badge.0,
                            badgeMark: wallet.selectedChain, badgeColor: badge.1
                        )
                    ).equatable().padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.rowVertical)
                }.buttonStyle(.plain)
                    .spectraPressable()
                if index < wallets.count - 1 { Divider().padding(.leading, 64).opacity(0.25) }
            }
        }
    }
    @ViewBuilder
    private func assetsCardRows(portfolio: [DashboardAssetGroup]) -> some View {
        if store.wallets.isEmpty {
            addWalletEmptyState
        } else if portfolio.isEmpty {
            emptyCardState(title: "No assets to display yet",
                           message: "Import a wallet or pull to refresh to load chain balances.",
                           systemImage: "chart.pie")
        } else {
            let presentations = visibleAssetPresentations(portfolio: portfolio)
            ForEach(Array(presentations.enumerated()), id: \.element.id) { index, presentation in
                Button { selectedAssetGroup = presentation.assetGroup } label: {
                    DashboardAssetRowView(presentation: presentation).equatable().padding(.horizontal, SpectraLayout.rowHorizontal).padding(
                        .vertical, SpectraLayout.rowVertical)
                }.buttonStyle(.plain)
                    .spectraPressable()
                if index < presentations.count - 1 { Divider().padding(.leading, 64).opacity(0.25) }
            }
        }
    }
    private func emptyCardState(title: String, message: String, systemImage: String) -> some View {
        SpectraEmptyStateContent(title: title, message: message, systemImage: systemImage)
            .padding(.horizontal, SpectraLayout.rowHorizontal)
            .padding(.vertical, 12)
    }
    private var addWalletEmptyState: some View {
        VStack(spacing: 16) {
            emptyCardState(title: "No wallets yet", message: "Add a wallet to start receiving and sending assets.", systemImage: "wallet.pass")
            Button(AppLocalization.string("Add Wallet")) { store.isShowingAddWalletEntry = true }
                .buttonStyle(.glassProminent)
                .tint(.orange)
        }.padding(20)
    }
    private var visiblePortfolio: [DashboardAssetGroup] { store.cachedDashboardAssetGroups }
    private func visibleAssetPresentations(portfolio: [DashboardAssetGroup]) -> [DashboardAssetRowPresentation] {
        let hideBalances = store.preferences.hideBalances
        return portfolio.map { assetGroup in
            DashboardAssetRowPresentation(
                assetGroup: assetGroup,
                amountText: store.formattedAssetAmount(
                    assetGroup.totalAmount, symbol: assetGroup.symbol, deploymentID: assetGroup.identity.holdingKey
                ),
                totalValueText: hideBalances
                    ? "••••••"
                    : store.formattedFiatAmountOrUnavailable(fromUSD: assetGroup.totalValueUsd),
                priceText: dashboardAssetPriceText(for: assetGroup, hideBalances: hideBalances)
            )
        }
    }
    private var activeNotices: [AppNoticeItem] { store.appNoticeItems }
    private var dashboardCardTitle: String {
        dashboardPage == .assets ? AppLocalization.string("My Assets") : AppLocalization.string("My Wallets")
    }
    // Pinning is an assets-page action, and this was a `Menu` whose entire
    // content sat behind that condition: on the wallets page it presented an
    // empty menu, so the button looked alive and did nothing. One action needs
    // no menu, and the toolbar item is now absent where it has nothing to do.
    private var pinAssetsToolbarButton: some View {
        Button {
            spectraHaptic(.light)
            isNavigatingToPinnedAssets = true
        } label: {
            Image(systemName: "pin")
        }.accessibilityLabel(AppLocalization.string("Pin Assets"))
    }
    private func dashboardAssetPriceText(for assetGroup: DashboardAssetGroup, hideBalances: Bool) -> String {
        if hideBalances { return "••••••" }
        guard let price = store.currentPriceIfAvailable(for: assetGroup.identity) else {
            return store.formattedFiatAmountOrUnavailable(fromUSD: nil)
        }
        return store.formattedFiatAmountOrUnavailable(fromUSD: price)
    }
}
enum DashboardPage {
    case wallets
    case assets
}
enum AppNoticeSeverity {
    case warning
    case error
    var tint: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        }
    }
    var label: String {
        switch self {
        case .warning: return AppLocalization.string("Warning")
        case .error: return AppLocalization.string("Error")
        }
    }
}
struct AppNoticeItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AppNoticeSeverity
    let systemImage: String
    var timestamp: Date? = nil
}
typealias DashboardAssetGroup = CoreDashboardAssetGroup
extension CoreDashboardAssetGroup: Identifiable {
    /// How the row names, colours and prices itself. Core supplies it: the
    /// place most of the asset is held, or the catalog's entry for a pinned
    /// asset held nowhere.
    ///
    /// This was `holdings.first?.coin`, which made every name on the row
    /// optional and left a pinned-but-unheld row with nothing to call itself
    /// unless core put a synthesized holding in the list — which then read as a
    /// place the user holds it.
    var representative: AssetHolding { identity }
    var name: String { identity.name }
    var symbol: String { identity.symbol }
    var artworkName: String { identity.artworkName }
    var color: Color { identity.color }
    var totalAmount: Double { holdings.reduce(0) { $0 + $1.coin.amount } }
}

typealias DashboardPinOption = CoreDashboardPinOption
extension CoreDashboardPinOption: Identifiable {
    public var id: String { tokenId }
    var color: Color { Coin.displayColor(for: symbol) }
}
struct AssetGroupDetailView: View {
    let store: AppState
    let assetGroup: DashboardAssetGroup
    /// Where the coin lives, from core's asset wiki — the same join the wiki
    /// screen renders, rather than a second dashboard-only cache of it.
    private var places: [AssetWikiPlace] {
        CachedCoreHelpers.assetWikiEntry(tokenID: assetGroup.id)?.livesOn ?? []
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                AssetDetailHeroCard(assetGroup: assetGroup, store: store)
                AssetSummaryStatsCard(assetGroup: assetGroup, store: store)
                AssetChainBreakdownCard(assetGroup: assetGroup, store: store)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.background(SpectraBackdrop().ignoresSafeArea())
            .navigationTitle(assetGroup.symbol).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if !places.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(AppLocalization.string("Details")) {
                            AssetContractsDetailView(store: store, assetGroup: assetGroup)
                        }
                    }
                }
            }
    }
}
struct AssetContractsDetailView: View {
    let store: AppState
    let assetGroup: DashboardAssetGroup
    private var places: [AssetWikiPlace] {
        CachedCoreHelpers.assetWikiEntry(tokenID: assetGroup.id)?.livesOn ?? []
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                AssetDetailHeroCard(assetGroup: assetGroup, store: store, compact: true)
                AssetPlacesCard(places: places, symbol: assetGroup.symbol)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.background(SpectraBackdrop().ignoresSafeArea())
            .navigationTitle(AppLocalization.format("%@ Details", assetGroup.symbol)).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
private struct AssetDetailHeroCard: View {
    let assetGroup: DashboardAssetGroup
    let store: AppState
    var compact: Bool = false
    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                artworkName: assetGroup.artworkName, fallbackText: assetGroup.symbol,
                color: assetGroup.color, size: compact ? 48 : 60
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(assetGroup.name).font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(assetGroup.symbol).font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(assetGroup.color)
                if !compact {
                    Text(store.formattedFiatAmountOrUnavailable(fromUSD: assetGroup.totalValueUsd))
                        .font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
                        .spectraNumericTextLayout(minimumScaleFactor: 0.7)
                }
            }
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .spectraElevatedFill()
    }
}
private struct AssetSummaryStatsCard: View {
    let assetGroup: DashboardAssetGroup
    let store: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statRow(
                label: AppLocalization.string("Total Amount"),
                value: store.formattedAssetAmount(
                    assetGroup.totalAmount, symbol: assetGroup.symbol, deploymentID: assetGroup.identity.holdingKey),
                icon: "scalemass.fill")
            Divider().opacity(0.4)
            statRow(
                label: AppLocalization.string("Total Value"),
                value: store.formattedFiatAmountOrUnavailable(fromUSD: assetGroup.totalValueUsd),
                icon: "dollarsign.circle.fill")
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }
    @ViewBuilder
    private func statRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).spectraNumericTextLayout(
                minimumScaleFactor: 0.7
            ).multilineTextAlignment(.trailing)
        }
    }
}
/// Every place the row's asset is held, largest first.
private struct AssetChainBreakdownCard: View {
    let assetGroup: DashboardAssetGroup
    let store: AppState

    /// Held nowhere, so there is no breakdown to draw.
    ///
    /// A pinned asset the user holds none of has no holdings at all — core
    /// names the row from its `identity` instead of synthesizing a place. The
    /// amount is checked too, because a real holding that has been emptied says
    /// the same thing to the reader and deserves the same sentence.
    private var holdsNothing: Bool { assetGroup.holdings.isEmpty || assetGroup.totalAmount <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLocalization.string("Chain Breakdown")).font(.headline).foregroundStyle(Color.primary)
                Spacer()
                if !holdsNothing, assetGroup.holdings.count > 1 {
                    Text("\(assetGroup.holdings.count)").font(.caption.weight(.bold)).foregroundStyle(.orange).padding(
                        .horizontal, 8
                    ).padding(.vertical, 3).background(Capsule(style: .continuous).fill(Color.orange.opacity(0.14)))
                }
            }
            if holdsNothing {
                Text(AppLocalization.string("No balance on any chain."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(assetGroup.holdings.enumerated()), id: \.offset) { index, holding in
                    AssetChainBreakdownRow(
                        chainName: holding.coin.chainName,
                        chainTitle: store.displayChainTitle(for: holding.coin.chainName),
                        tokenStandard: holding.coin.tokenStandard,
                        amountText: store.formattedAssetAmount(
                            holding.coin.amount, symbol: holding.coin.symbol,
                            deploymentID: holding.coin.holdingKey),
                        valueText: store.formattedFiatAmountOrUnavailable(fromUSD: holding.valueUsd),
                        fallbackColor: holding.coin.color
                    )
                    if index < assetGroup.holdings.count - 1 { Divider().opacity(0.3) }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .spectraCardFill()
    }
}

/// One chain the asset is held on.
///
/// The badge is the **chain's**, which is what the row is about. It drew the
/// asset's, so USDC on Ethereum and USDC on Solana were two rows under two
/// identical USDC marks — the one thing that told them apart was the title
/// beside it. `fallbackColor` is the asset's, for a chain the registry has no
/// artwork for.
private struct AssetChainBreakdownRow: View {
    let chainName: String
    let chainTitle: String
    let tokenStandard: String
    let amountText: String
    let valueText: String
    let fallbackColor: Color
    var body: some View {
        let badge = Coin.nativeChainBadge(chainName: chainName) ?? (nil, fallbackColor)
        return HStack(alignment: .center, spacing: 12) {
            CoinBadge(
                artworkName: badge.artworkName,
                fallbackText: chainTitle, color: badge.color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(chainTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                Text(tokenStandard).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).spectraNumericTextLayout()
                Text(valueText).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
            }
        }
    }
}
struct PinnedAssetsView: View {
    let store: AppState
    @State private var searchText: String = ""
    private var filteredOptions: [DashboardPinOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let allOptions = store.cachedAvailableDashboardPinOptions
        guard !query.isEmpty else { return allOptions }
        return allOptions.filter { option in
            option.symbol.localizedCaseInsensitiveContains(query) || option.name.localizedCaseInsensitiveContains(query)
                || option.subtitle.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        List {
            Section {
                ForEach(filteredOptions) { option in
                    Toggle(isOn: binding(for: option)) {
                        DashboardPinnedAssetRowView(
                            option: option,
                            subtitleText: AppLocalization.format("dashboard.pinnedAsset.symbolSubtitle", option.symbol, option.subtitle)
                        ).equatable()
                    }
                }
            } header: {
                Text(AppLocalization.string("Pinned Assets"))
            } footer: {
                Text(AppLocalization.string("Pinned assets stay visible in My Assets even when the total balance is zero."))
            }
        }.navigationTitle(AppLocalization.string("Pinned Assets")).searchable(
            text: $searchText, prompt: AppLocalization.string("Search assets")
        ).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Reset")) {
                    store.resetPinnedDashboardAssets()
                }
            }
        }
    }
    private func binding(for option: DashboardPinOption) -> Binding<Bool> {
        Binding(
            get: { option.isPinned }, set: { isPinned in store.setDashboardAssetPinned(isPinned, tokenID: option.tokenId) }
        )
    }
}
struct PortfolioWalletSelectionView: View {
    let store: AppState
    var body: some View {
        List {
            Section {
                ForEach(store.wallets) { wallet in
                    Toggle(isOn: binding(for: wallet.id)) {
                        PortfolioWalletToggleRowView(walletName: wallet.name, chainTitleText: store.displayChainTitle(for: wallet))
                            .equatable()
                    }
                }
            } header: {
                Text(AppLocalization.string("Included In Portfolio Total"))
            } footer: {
                Text(
                    AppLocalization.string(
                        "Only selected wallets contribute to the portfolio total and the aggregated asset list on the home page."))
            }
        }.navigationTitle(AppLocalization.string("Portfolio Wallets"))
    }
    private func binding(for walletID: String) -> Binding<Bool> {
        Binding(
            get: {
                store.wallets.first(where: { $0.id == walletID })?.includeInPortfolioTotal ?? true
            }, set: { isIncluded in store.setPortfolioInclusion(isIncluded, for: walletID) }
        )
    }
}
struct AppNoticesView: View {
    let store: AppState
    var body: some View {
        let notices = store.appNoticeItems
        return List {
            if notices.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("No active notices")).font(.headline)
                        Text(AppLocalization.string("Current wallet, pricing, and chain-state warnings will appear here.")).font(
                            .subheadline
                        ).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            } else {
                Section(AppLocalization.string("Active Notices")) {
                    ForEach(notices) { notice in DashboardNoticeCardView(notice: notice) }
                }
            }
        }.navigationTitle(AppLocalization.string("Notices"))
    }
}
struct DashboardAssetRowPresentation: Identifiable, Equatable {
    let assetGroup: DashboardAssetGroup
    let amountText: String
    let totalValueText: String
    let priceText: String
    var id: String { assetGroup.id }
}
struct DashboardAssetRowView: View, Equatable {
    let presentation: DashboardAssetRowPresentation
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.presentation == rhs.presentation }
    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(
                artworkName: presentation.assetGroup.artworkName, fallbackText: presentation.assetGroup.symbol,
                color: presentation.assetGroup.color, size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if presentation.assetGroup.isPinned {
                        Image(systemName: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.red.opacity(0.82)).frame(
                            width: 24, height: 18
                        ).background(Color.red.opacity(0.1), in: Capsule()).clipped()
                    }
                    Text(presentation.assetGroup.name).font(.headline).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.tail)
                }
                Text(presentation.amountText).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(presentation.totalValueText).font(.headline).foregroundStyle(Color.primary).spectraNumericTextLayout()
                Text(presentation.priceText).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }.contentShape(Rectangle())
    }
}
struct DashboardPinnedAssetRowView: View, Equatable {
    let option: DashboardPinOption
    let subtitleText: String
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.option == rhs.option && lhs.subtitleText == rhs.subtitleText }
    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(artworkName: option.artworkName, fallbackText: option.symbol, color: option.color, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.name)
                Text(subtitleText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct PortfolioWalletToggleRowView: View, Equatable {
    let walletName: String
    let chainTitleText: String
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.walletName == rhs.walletName && lhs.chainTitleText == rhs.chainTitleText }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(walletName)
            Text(chainTitleText).font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct DashboardNoticeCardView: View {
    let notice: AppNoticeItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: notice.systemImage).foregroundStyle(notice.severity.tint)
                Text(notice.title).font(.headline)
                Spacer()
                Text(notice.severity.label).font(.caption.weight(.semibold)).foregroundStyle(notice.severity.tint)
            }
            Text(notice.message).font(.subheadline).foregroundStyle(.primary)
            if let timestamp = notice.timestamp {
                Text(
                    AppLocalization.format(
                        "Last known healthy sync: %@", timestamp.formatted(date: .abbreviated, time: .shortened))
                ).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

// ── Dashboard top-level sections ────────────────────────────────────────
// Each section is a standalone `View` struct so its internal TupleView
// types don't cascade into `DashboardView.body`'s opaque return. This
// matches the SetupView refactor and Apple's preferred pattern of many
// focused `View` structs rather than long computed-var bodies.

private struct DashboardPortfolioHeader: View {
    @Bindable var store: AppState
    var body: some View {
        NavigationLink {
            PortfolioWalletSelectionView(store: store)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AppLocalization.string("Portfolio")).font(.subheadline).foregroundStyle(.secondary)
                    let quoted = store.portfolioQuotedTotal
                    Text(store.preferences.hideBalances ? "••••••" : store.formattedQuotedTotal(quoted))
                        .font(.title.weight(.bold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                    Text(AppLocalization.format("%lld in total", store.cachedIncludedPortfolioWallets.count)).font(.footnote).foregroundStyle(.secondary)

                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(SpectraLayout.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
                .spectraElevatedFill()
        }.buttonStyle(.plain)
    }
}

private struct DashboardActionButtons: View {
    @Bindable var store: AppState
    var body: some View {
        let canSend = store.canBeginSend
        let canReceive = store.canBeginReceive
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { spectraHaptic(.medium); store.beginSend() } label: {
                    Label(AppLocalization.string("Send"), systemImage: "arrow.up.right")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                }.buttonStyle(.glass)
                    .spectraPressable()
                    .disabled(!canSend)
                Button { spectraHaptic(.medium); store.beginReceive() } label: {
                    Label(AppLocalization.string("Receive"), systemImage: "arrow.down.left")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                }.buttonStyle(.glassProminent)
                    .spectraPressable()
                    .disabled(!canReceive)
            }
        }
    }
}
