import Combine
import SwiftUI
private func localizedDashboardString(_ key: String) -> String {
    AppLocalization.string(key)
}
private func localizedDashboardFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
private func dashboardConfigButtonLabel() -> some View {
    Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.78)).frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.14)))
}
struct DashboardView: View {
    @ObservedObject var store: AppState
    @State private var dashboardPage: DashboardPage = .assets
    @State private var isShowingPinnedAssetsSheet = false
    @State private var selectedWalletID: String?
    @State private var walletPageIndex: Int = 0
    @State private var selectedAssetGroup: DashboardAssetGroup?
    @State private var isShowingAddWalletPage: Bool = false
    private var deleteWalletMessage: String {
        guard let pendingWallet = store.walletPendingDeletion else { return "" }
        if store.isWatchOnlyWallet(pendingWallet) { return localizedDashboardString("You can't recover this wallet after deletion until you still have this address.") }
        return localizedDashboardString("Please take note of your seed phrase because you can't recover this wallet after deletion.")
    }
    private var selectedWallet: ImportedWallet? {
        guard let selectedWalletID else { return nil }
        return store.wallet(for: selectedWalletID)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 22) {
                        portfolioHeader
                        actionButtons
                        dashboardCardSection
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }.refreshable {
                    await store.performUserInitiatedRefresh()
                }.scrollBounceBehavior(.always)
            }.navigationTitle(localizedDashboardString("Spectra")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        AppNoticesView(store: store)
                    } label: { noticeToolbarLabel }}
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddWalletPage = true
                    } label: { Image(systemName: "plus") }}}.navigationDestination(isPresented: $isShowingAddWalletPage) {
                AddWalletEntryView(store: store)
            }.navigationDestination(isPresented: Binding(
                get: { store.isShowingWalletImporter && store.editingWalletID == nil }, set: { isPresented in
                    if !isPresented { store.isShowingWalletImporter = false }}
            )) {
                SetupView(store: store, draft: store.importDraft)
            }.navigationDestination(isPresented: Binding(
                get: { selectedWallet != nil }, set: { isPresented in
                    if !isPresented { selectedWalletID = nil }}
            )) {
                if let selectedWallet { WalletDetailView(store: store, wallet: selectedWallet) }}.navigationDestination(item: $selectedAssetGroup) { assetGroup in AssetGroupDetailView(store: store, assetGroup: assetGroup) }.navigationDestination(isPresented: Binding(get: { store.isShowingSendSheet }, set: { store.isShowingSendSheet = $0 })) {
                SendView(store: store)
            }.navigationDestination(isPresented: Binding(get: { store.isShowingReceiveSheet }, set: { store.isShowingReceiveSheet = $0 })) {
                ReceiveView(store: store)
            }.alert(localizedDashboardString("Delete Wallet?"), isPresented: Binding(
                get: { store.walletPendingDeletion != nil }, set: { isPresented in
                    if !isPresented { store.walletPendingDeletion = nil }}
            )) {
                Button(localizedDashboardString("Delete"), role: .destructive) {
                    Task {
                        await store.deletePendingWallet()
                    }}
                Button(localizedDashboardString("Cancel"), role: .cancel) {
                    store.walletPendingDeletion = nil
                }} message: {
                Text(deleteWalletMessage)
            }.onChange(of: store.walletsRevision) { _, _ in
                let walletCount = store.wallets.count
                if walletCount == 0 { walletPageIndex = 0 } else if walletPageIndex >= walletCount { walletPageIndex = walletCount - 1 }}}}
    private var portfolioHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SpectraLogo(size: 36)
                    Text(localizedDashboardString("Portfolio")).font(.headline).foregroundStyle(Color.primary.opacity(0.82))
                }
                Text(store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.totalBalanceIfAvailable)).font(.system(size: 42, weight: .black, design: .rounded)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.45).allowsTightening(true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                NavigationLink {
                    PortfolioWalletSelectionView(store: store)
                } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.88))
                }.buttonStyle(.plain)
                Text(localizedFormat("%lld in total", store.cachedIncludedPortfolioWallets.count)).font(.caption2).foregroundStyle(Color.primary.opacity(0.72))
            }}.padding(20).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 30)).padding(.top, 12)
    }
    private var noticeToolbarLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: activeNotices.isEmpty ? "tray" : "exclamationmark.bubble").font(.system(size: 18, weight: .semibold)).frame(width: 24, height: 24)
            if !activeNotices.isEmpty { Text("\(min(activeNotices.count, 9))").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(Color.red)).offset(x: 6, y: -5) }}.frame(width: 32, height: 28, alignment: .center).foregroundStyle(Color.primary).accessibilityLabel(
            activeNotices.isEmpty
                ? localizedDashboardString("No active notices")
                : localizedDashboardFormat("%lld active notices", activeNotices.count)
        )
    }
    private var actionButtons: some View {
        let canSend = store.canBeginSend
        let canReceive = store.canBeginReceive
        return HStack(spacing: 12) {
            Button {
                store.beginSend()
            } label: {
                Label(localizedDashboardString("Send"), systemImage: "arrow.up.right").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }.buttonStyle(.glass).disabled(!canSend).opacity(canSend ? 1.0 : 0.5)
            Button {
                store.beginReceive()
            } label: {
                Label(localizedDashboardString("Receive"), systemImage: "arrow.down.left").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }.buttonStyle(.glassProminent).disabled(!canReceive).opacity(canReceive ? 1.0 : 0.5)
        }}
    private var dashboardCardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeading(dashboardCardTitle, symbol: dashboardCardSymbol)
                Text(dashboardCardCountText).font(.headline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.72))
                Spacer()
                dashboardConfigMenu
            }.frame(maxWidth: .infinity, alignment: .leading)
            switch dashboardPage {
            case .wallets: walletsSectionContent.transition(dashboardContentTransition)
            case .assets: assetsSectionContent.transition(dashboardContentTransition)
            }}.frame(maxWidth: .infinity, alignment: .leading).padding(20).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 30)).contentShape(Rectangle()).animation(.easeOut(duration: 0.16), value: dashboardPage)
    }
    private var walletsSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.wallets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedDashboardString("No wallets yet")).font(.headline).foregroundStyle(Color.primary)
                    Text(localizedDashboardString("Tap the + button in the top right to add your first wallet.")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
            } else {
                let wallets = store.wallets
                let safePageIndex = min(max(walletPageIndex, 0), max(wallets.count - 1, 0))
                TabView(selection: Binding(get: { safePageIndex }, set: { walletPageIndex = $0 })) {
                    ForEach(Array(wallets.enumerated()), id: \.element.id) { index, wallet in
                        let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, "W", .mint)
                        WalletCardView(
                            presentation: WalletCardView.Presentation(
                                walletName: wallet.name, chainTitleText: store.displayChainTitle(for: wallet), totalValueText: store.hideBalances
                                    ? "••••••"
                                    : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: wallet)), assetCountText: localizedFormat("%lld assets", wallet.holdings.filter { $0.amount > 0 }.count), isWatchOnly: store.isWatchOnlyWallet(wallet), badgeAssetIdentifier: badge.0, badgeMark: badge.1, badgeColor: badge.2
                            )
                        ).equatable().contentShape(Rectangle()).onTapGesture {
                            selectedWalletID = wallet.id
                        }.tag(index)
                    }}.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 108)
                HStack(spacing: 10) {
                    Button {
                        walletPageIndex = max(walletPageIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                    }.buttonStyle(.glass).disabled(safePageIndex == 0)
                    Spacer()
                    Text("Wallet \(safePageIndex + 1) of \(wallets.count)").font(.caption).foregroundStyle(Color.primary.opacity(0.72))
                    Spacer()
                    Button {
                        walletPageIndex = min(walletPageIndex + 1, wallets.count - 1)
                    } label: {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }.buttonStyle(.glass).disabled(safePageIndex >= wallets.count - 1)
                }
                HStack(spacing: 6) {
                    ForEach(Array(wallets.indices), id: \.self) { index in Capsule().fill(index == safePageIndex ? Color.primary.opacity(0.85) : Color.primary.opacity(0.2)).frame(width: index == safePageIndex ? 18 : 6, height: 6) }}.frame(maxWidth: .infinity, alignment: .center)
            }}}
    private var assetsSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if visiblePortfolio.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizedDashboardString("No assets to display yet")).font(.headline).foregroundStyle(Color.primary)
                    Text(localizedDashboardString("Import a wallet or pull to refresh to load chain balances.")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: 20))
            } else {
                ForEach(visibleAssetPresentations) { presentation in
                    DashboardAssetRowView(presentation: presentation).equatable().contentShape(Rectangle()).onTapGesture {
                            selectedAssetGroup = presentation.assetGroup
                        }}}}.sheet(isPresented: $isShowingPinnedAssetsSheet) {
            PinnedAssetsView(store: store)
        }}
    private var visiblePortfolio: [DashboardAssetGroup] { store.cachedDashboardAssetGroups }
    private var visibleAssetPresentations: [DashboardAssetRowPresentation] {
        visiblePortfolio.map { assetGroup in
            DashboardAssetRowPresentation(
                assetGroup: assetGroup, amountText: store.formattedAssetAmount(
                    assetGroup.totalAmount, symbol: assetGroup.symbol, chainName: assetGroup.representativeCoin.chainName
                ), totalValueText: store.hideBalances
                    ? "••••••"
                    : store.formattedFiatAmountOrZero(fromUSD: assetGroup.totalValueUSD), priceText: dashboardAssetPriceText(for: assetGroup), chainSummaryText: dashboardChainSummaryText(for: assetGroup)
            )
        }}
    private var activeNotices: [AppNoticeItem] { store.appNoticeItems }
    private var dashboardContentTransition: AnyTransition { .opacity }
    private var dashboardCardTitle: String { dashboardPage == .assets ? localizedDashboardString("My Assets") : localizedDashboardString("My Wallets") }
    private var dashboardCardSymbol: String { dashboardPage == .assets ? "bitcoinsign.circle" : "wallet.pass" }
    private var dashboardCardCountText: String { dashboardPage == .assets ? "\(visiblePortfolio.count)" : "\(store.wallets.count)" }
    private var dashboardConfigMenu: some View {
        Menu {
            Picker(localizedDashboardString("Dashboard Section"), selection: $dashboardPage) {
                Text(localizedDashboardString("Assets")).tag(DashboardPage.assets)
                Text(localizedDashboardString("Wallets")).tag(DashboardPage.wallets)
            }
            if dashboardPage == .assets {
                Divider()
                Button(localizedDashboardString("Customize Assets")) {
                    isShowingPinnedAssetsSheet = true
                }}} label: { dashboardConfigButtonLabel() }.buttonStyle(.plain).accessibilityLabel(
            dashboardPage == .assets
                ? "Configure asset view"
                : "Configure wallet view"
        )
    }
    @ViewBuilder
    private func sectionHeading(_ title: String, symbol: String) -> some View { Label(localizedDashboardString(title), systemImage: symbol).font(.headline).foregroundStyle(Color.primary) }
    private func dashboardAssetPriceText(for assetGroup: DashboardAssetGroup) -> String {
        guard let price = store.currentOrFallbackPriceIfAvailable(for: assetGroup.representativeCoin) else { return store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: nil) }
        return store.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: price)
    }
    private func dashboardChainSummaryText(for assetGroup: DashboardAssetGroup) -> String {
        if assetGroup.chainEntries.isEmpty { return localizedDashboardString("No chain balances yet") }
        if assetGroup.chainEntries.count == 1, let chainName = assetGroup.chainEntries.first?.coin.chainName { return localizedFormat("dashboard.asset.onChain", chainName) }
        let names = assetGroup.chainEntries.map(\.coin.chainName)
        let preview = names.prefix(2).joined(separator: ", ")
        let remainder = names.count - min(names.count, 2)
        if remainder > 0 { return localizedFormat("On %@ +%lld more", preview, remainder) }
        return localizedFormat("dashboard.asset.onChain", preview)
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
        }}
    var label: String {
        switch self {
        case .warning: return localizedDashboardString("Warning")
        case .error: return localizedDashboardString("Error")
        }}
}
struct AppNoticeItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AppNoticeSeverity
    let systemImage: String
    var timestamp: Date? = nil
}
typealias DashboardAssetChainEntry = CoreDashboardAssetChainEntry
extension CoreDashboardAssetChainEntry: Identifiable {
    public var id: String {
        let contract = normalizeDashboardContractAddress(
            contractAddress: coin.contractAddress, chainName: coin.chainName, tokenStandard: coin.tokenStandard
        ) ?? "native"
        return "\(coin.chainName.lowercased())|\(coin.symbol.lowercased())|\(contract)"
    }
    // Legacy uppercased acronym forwarder.
    var valueUSD: Double? { valueUsd }
    init(coin: Coin, valueUSD: Double?) {
        self.init(coin: coin, valueUsd: valueUSD)
    }
}

typealias DashboardAssetGroup = CoreDashboardAssetGroup
extension CoreDashboardAssetGroup: Identifiable {
    var name: String { representativeCoin.name }
    var symbol: String { representativeCoin.symbol }
    var iconIdentifier: String { representativeCoin.iconIdentifier }
    var mark: String { representativeCoin.mark }
    var color: Color { representativeCoin.color }
    var totalValueUSD: Double? { totalValueUsd }
    init(id: String, representativeCoin: Coin, totalAmount: Double, totalValueUSD: Double?, chainEntries: [DashboardAssetChainEntry], isPinned: Bool) {
        self.init(id: id, representativeCoin: representativeCoin, totalAmount: totalAmount, totalValueUsd: totalValueUSD, chainEntries: chainEntries, isPinned: isPinned)
    }
}

typealias DashboardPinOption = CoreDashboardPinOption
extension CoreDashboardPinOption: Identifiable {
    public var id: String { symbol }
    var color: Color { Coin.displayColor(for: symbol) }
}
struct AssetGroupDetailView: View {
    @ObservedObject var store: AppState
    let assetGroup: DashboardAssetGroup
    private var supportedTokenEntries: [TokenPreferenceEntry] { store.cachedDashboardSupportedTokenEntriesBySymbol[assetGroup.symbol.uppercased()] ?? [] }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: assetGroup.iconIdentifier, fallbackText: assetGroup.mark, color: assetGroup.color, size: 52
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetGroup.name).font(.headline)
                            Text(assetGroup.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }}
                    dashboardDetailRow(
                        label: localizedDashboardString("Total Amount"), value: store.formattedAssetAmount(
                            assetGroup.totalAmount, symbol: assetGroup.symbol, chainName: assetGroup.representativeCoin.chainName
                        )
                    )
                    dashboardDetailRow(label: localizedDashboardString("Total Value"), value: store.formattedFiatAmountOrZero(fromUSD: assetGroup.totalValueUSD))
                    dashboardDetailRow(label: localizedDashboardString("Chains"), value: "\(assetGroup.chainEntries.count)")
                }.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(localizedDashboardString("Chain Breakdown")).font(.headline).foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(assetGroup.chainEntries.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.68))
                    }
                    if assetGroup.chainEntries.isEmpty { Text(localizedDashboardString("No chain balances yet for this asset.")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72)) } else {
                        ForEach(assetGroup.chainEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.displayChainTitle(for: entry.coin.chainName)).font(.headline)
                                        Text(entry.coin.tokenStandard).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(store.formattedAssetAmount(entry.coin.amount, symbol: entry.coin.symbol, chainName: entry.coin.chainName)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).spectraNumericTextLayout()
                                        Text(store.formattedFiatAmountOrZero(fromUSD: entry.valueUSD)).font(.caption).foregroundStyle(Color.primary.opacity(0.68)).spectraNumericTextLayout()
                                    }}}.padding(.vertical, 4)
                        }
                        Text(localizedDashboardString("This asset view merges balances across chains while preserving the per-chain token standard details here.")).font(.caption).foregroundStyle(Color.primary.opacity(0.62))
                    }}.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.background(SpectraBackdrop()).navigationTitle(assetGroup.symbol).navigationBarTitleDisplayMode(.inline).toolbar {
            if !supportedTokenEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(localizedDashboardString("Details")) {
                        AssetContractsDetailView(store: store, assetGroup: assetGroup)
                    }}}}}
}
struct AssetContractsDetailView: View {
    @ObservedObject var store: AppState
    let assetGroup: DashboardAssetGroup
    private var supportedTokenEntries: [TokenPreferenceEntry] { store.cachedDashboardSupportedTokenEntriesBySymbol[assetGroup.symbol.uppercased()] ?? [] }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: assetGroup.iconIdentifier, fallbackText: assetGroup.mark, color: assetGroup.color, size: 44
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetGroup.name).font(.headline)
                            Text(assetGroup.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }}
                    dashboardDetailRow(label: localizedDashboardString("Supported Chains"), value: "\(supportedTokenEntries.count)")
                }.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizedDashboardString("Contracts")).font(.headline).foregroundStyle(Color.primary)
                    if supportedTokenEntries.isEmpty { Text(localizedDashboardString("No contract addresses are available for this asset.")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72)) } else {
                        ForEach(supportedTokenEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.chain.rawValue).font(.headline)
                                        Text(entry.tokenStandard).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                Text(entry.contractAddress).font(.footnote.monospaced()).foregroundStyle(Color.primary.opacity(0.8)).textSelection(.enabled)
                            }.padding(.vertical, 4)
                        }}}.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.background(SpectraBackdrop()).navigationTitle(localizedFormat("%@ Details", assetGroup.symbol)).navigationBarTitleDisplayMode(.inline)
    }
}
struct PinnedAssetsView: View {
    @ObservedObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    private var filteredOptions: [DashboardPinOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let allOptions = store.cachedAvailableDashboardPinOptions
        guard !query.isEmpty else { return allOptions }
        return allOptions.filter { option in option.symbol.localizedCaseInsensitiveContains(query) || option.name.localizedCaseInsensitiveContains(query) || option.subtitle.localizedCaseInsensitiveContains(query) }}
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredOptions) { option in
                        Toggle(isOn: binding(for: option.symbol)) {
                            DashboardPinnedAssetRowView(
                                option: option, subtitleText: localizedFormat("dashboard.pinnedAsset.symbolSubtitle", option.symbol, option.subtitle)
                            ).equatable()
                        }}} header: {
                    Text(localizedDashboardString("Pinned Assets"))
                } footer: {
                    Text(localizedDashboardString("Pinned assets stay visible in My Assets even when the total balance is zero."))
                }}.navigationTitle(localizedDashboardString("Pinned Assets")).searchable(text: $searchText, prompt: localizedDashboardString("Search assets")).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localizedDashboardString("Reset")) {
                        store.resetPinnedDashboardAssets()
                    }}
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizedDashboardString("Done")) {
                        dismiss()
                    }}}}}
    private func binding(for symbol: String) -> Binding<Bool> {
        Binding(
            get: { store.isDashboardAssetPinned(symbol) }, set: { isPinned in store.setDashboardAssetPinned(isPinned, symbol: symbol) }
        )
    }
}
struct PortfolioWalletSelectionView: View {
    @ObservedObject var store: AppState
    var body: some View {
        List {
            Section {
                ForEach(store.wallets) { wallet in
                    Toggle(isOn: binding(for: wallet.id)) {
                        PortfolioWalletToggleRowView(walletName: wallet.name, chainTitleText: store.displayChainTitle(for: wallet)).equatable()
                    }}} header: {
                Text(localizedDashboardString("Included In Portfolio Total"))
            } footer: {
                Text(localizedDashboardString("Only selected wallets contribute to the portfolio total and the aggregated asset list on the home page."))
            }}.navigationTitle(localizedDashboardString("Portfolio Wallets"))
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
        List {
            if store.appNoticeItems.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedDashboardString("No active notices")).font(.headline)
                        Text(localizedDashboardString("Current wallet, pricing, and chain-state warnings will appear here.")).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            } else {
                Section(localizedDashboardString("Active Notices")) {
                    ForEach(store.appNoticeItems) { notice in DashboardNoticeCardView(notice: notice) }}}}.navigationTitle(localizedDashboardString("Notices"))
    }
}
private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
struct DashboardAssetRowPresentation: Identifiable, Equatable {
    let assetGroup: DashboardAssetGroup
    let amountText: String
    let totalValueText: String
    let priceText: String
    let chainSummaryText: String
    var id: String { assetGroup.id }
}
@ViewBuilder
func dashboardDetailRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
        Text(label).foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Text(value).multilineTextAlignment(.trailing)
    }.font(.caption)
}
struct DashboardAssetRowView: View, Equatable {
    let presentation: DashboardAssetRowPresentation
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.presentation == rhs.presentation }
    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: presentation.assetGroup.iconIdentifier, fallbackText: presentation.assetGroup.mark, color: presentation.assetGroup.color, size: 40
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if presentation.assetGroup.isPinned { Image(systemName: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.red.opacity(0.82)).frame(width: 28, height: 20).background(Color.red.opacity(0.1), in: Capsule()).clipped() }
                    Text(presentation.assetGroup.name).font(.headline).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.tail)
                }
                Text(presentation.amountText).font(.caption).foregroundStyle(Color.primary.opacity(0.72)).spectraNumericTextLayout()
                Text(presentation.chainSummaryText).font(.caption2).foregroundStyle(Color.primary.opacity(0.58))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(presentation.totalValueText).font(.headline).foregroundStyle(Color.primary).spectraNumericTextLayout()
                Text(presentation.priceText).font(.caption).foregroundStyle(Color.primary.opacity(0.68)).spectraNumericTextLayout()
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.42))
        }.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}
struct DashboardPinnedAssetRowView: View, Equatable {
    let option: DashboardPinOption
    let subtitleText: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.option == rhs.option && lhs.subtitleText == rhs.subtitleText }
    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(assetIdentifier: option.assetIdentifier, fallbackText: option.mark, color: option.color, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.name)
                Text(subtitleText).font(.caption).foregroundStyle(.secondary)
            }}}
}
struct PortfolioWalletToggleRowView: View, Equatable {
    let walletName: String
    let chainTitleText: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.walletName == rhs.walletName && lhs.chainTitleText == rhs.chainTitleText }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(walletName)
            Text(chainTitleText).font(.caption).foregroundStyle(.secondary)
        }}
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
            if let timestamp = notice.timestamp { Text(dashboardComponentsLocalizedFormat("Last known healthy sync: %@", timestamp.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) }}.padding(.vertical, 4)
    }
}
private func dashboardComponentsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
