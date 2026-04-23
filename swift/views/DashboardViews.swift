import SwiftUI
struct DashboardView: View {
    @Bindable var store: AppState
    @State private var dashboardPage: DashboardPage = .assets
    @State private var isShowingPinnedAssetsSheet = false
    @State private var selectedWalletID: String?
    @State private var selectedAssetGroup: DashboardAssetGroup?
    private var deleteWalletMessage: String {
        guard let pendingWallet = store.walletPendingDeletion else { return "" }
        if store.isWatchOnlyWallet(pendingWallet) {
            return AppLocalization.string("You can't recover this wallet after deletion until you still have this address.")
        }
        return AppLocalization.string("Please take note of your seed phrase because you can't recover this wallet after deletion.")
    }
    private var selectedWallet: ImportedWallet? {
        guard let selectedWalletID else { return nil }
        return store.wallet(for: selectedWalletID)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        portfolioHeader
                        actionButtons
                        assetsOrWalletsCard
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
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
                ToolbarItem(placement: .topBarTrailing) {
                    dashboardSectionMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.isShowingAddWalletEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
                }.sheet(isPresented: $isShowingPinnedAssetsSheet) {
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
    private var actionButtons: some View {
        DashboardActionButtons(store: store)
    }
    private var assetsOrWalletsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(dashboardCardTitle).font(.headline)
                Spacer()
                Text(dashboardCardCountText).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            }.padding(.horizontal, 20).padding(.vertical, 16)
            Divider().opacity(0.35)
            VStack(spacing: 0) {
                switch dashboardPage {
                case .wallets: walletsCardRows(wallets: store.wallets)
                case .assets: assetsCardRows(portfolio: visiblePortfolio)
                }
            }.padding(.vertical, 4)
        }.frame(maxWidth: .infinity).glassEffect(.regular.tint(.white.opacity(0.03)).interactive(), in: .rect(cornerRadius: 28))
    }
    private var dashboardCardCountText: String {
        let count = dashboardPage == .assets ? visiblePortfolio.count : store.wallets.count
        return "\(count)"
    }
    @ViewBuilder
    private func walletsCardRows(wallets: [ImportedWallet]) -> some View {
        if wallets.isEmpty {
            emptyCardState(title: AppLocalization.string("No wallets yet"),
                           message: AppLocalization.string("Tap the + button in the top right to add your first wallet."))
        } else {
            ForEach(Array(wallets.enumerated()), id: \.element.id) { index, wallet in
                let badge = Coin.nativeChainBadge(chainName: wallet.selectedChain) ?? (nil, .mint)
                Button { selectedWalletID = wallet.id } label: {
                    WalletCardView(
                        presentation: WalletCardView.Presentation(
                            walletName: wallet.name, chainTitleText: store.displayChainTitle(for: wallet),
                            totalValueText: store.preferences.hideBalances
                                ? "••••••"
                                : store.formattedFiatAmountOrZero(fromUSD: store.currentTotalIfAvailable(for: wallet)),
                            assetCountText: AppLocalization.format(
                                "%lld assets", wallet.holdings.filter { $0.amount > 0 }.count),
                            isWatchOnly: store.isWatchOnlyWallet(wallet), badgeAssetIdentifier: badge.0,
                            badgeMark: wallet.selectedChain, badgeColor: badge.1
                        )
                    ).equatable().padding(.horizontal, 20).padding(.vertical, 12)
                }.buttonStyle(.plain)
                if index < wallets.count - 1 { Divider().padding(.leading, 72).opacity(0.25) }
            }
        }
    }
    @ViewBuilder
    private func assetsCardRows(portfolio: [DashboardAssetGroup]) -> some View {
        if portfolio.isEmpty {
            emptyCardState(title: AppLocalization.string("No assets to display yet"),
                           message: AppLocalization.string("Import a wallet or pull to refresh to load chain balances."))
        } else {
            let presentations = visibleAssetPresentations(portfolio: portfolio)
            ForEach(Array(presentations.enumerated()), id: \.element.id) { index, presentation in
                Button { selectedAssetGroup = presentation.assetGroup } label: {
                    DashboardAssetRowView(presentation: presentation).equatable().padding(.horizontal, 20).padding(.vertical, 12)
                }.buttonStyle(.plain)
                if index < presentations.count - 1 { Divider().padding(.leading, 72).opacity(0.25) }
            }
        }
    }
    private func emptyCardState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var visiblePortfolio: [DashboardAssetGroup] { store.cachedDashboardAssetGroups }
    private func visibleAssetPresentations(portfolio: [DashboardAssetGroup]) -> [DashboardAssetRowPresentation] {
        let hideBalances = store.preferences.hideBalances
        return portfolio.map { assetGroup in
            DashboardAssetRowPresentation(
                assetGroup: assetGroup,
                amountText: store.formattedAssetAmount(
                    assetGroup.totalAmount, symbol: assetGroup.symbol, chainName: assetGroup.representativeCoin.chainName
                ),
                totalValueText: hideBalances
                    ? "••••••"
                    : store.formattedFiatAmountOrZero(fromUSD: assetGroup.totalValueUSD),
                priceText: dashboardAssetPriceText(for: assetGroup, hideBalances: hideBalances),
                chainSummaryText: dashboardChainSummaryText(for: assetGroup)
            )
        }
    }
    private var activeNotices: [AppNoticeItem] { store.appNoticeItems }
    private var dashboardCardTitle: String {
        dashboardPage == .assets ? AppLocalization.string("My Assets") : AppLocalization.string("My Wallets")
    }
    private var dashboardSectionMenu: some View {
        Menu {
            Picker(AppLocalization.string("Dashboard Section"), selection: $dashboardPage) {
                Text(AppLocalization.string("Assets")).tag(DashboardPage.assets)
                Text(AppLocalization.string("Wallets")).tag(DashboardPage.wallets)
            }
            if dashboardPage == .assets {
                Divider()
                Button(AppLocalization.string("Customize Assets")) {
                    isShowingPinnedAssetsSheet = true
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }.accessibilityLabel(
            dashboardPage == .assets
                ? "Configure asset view"
                : "Configure wallet view"
        )
    }
    private func dashboardAssetPriceText(for assetGroup: DashboardAssetGroup, hideBalances: Bool) -> String {
        if hideBalances { return "••••••" }
        guard let price = store.currentOrFallbackPriceIfAvailable(for: assetGroup.representativeCoin) else {
            return store.formattedFiatAmountOrZero(fromUSD: nil)
        }
        return store.formattedFiatAmountOrZero(fromUSD: price)
    }
    private func dashboardChainSummaryText(for assetGroup: DashboardAssetGroup) -> String {
        if assetGroup.chainEntries.isEmpty { return AppLocalization.string("No chain balances yet") }
        if assetGroup.chainEntries.count == 1, let chainName = assetGroup.chainEntries.first?.coin.chainName {
            return AppLocalization.format("dashboard.asset.onChain", chainName)
        }
        let names = assetGroup.chainEntries.map(\.coin.chainName)
        let preview = names.prefix(2).joined(separator: ", ")
        let remainder = names.count - min(names.count, 2)
        if remainder > 0 { return AppLocalization.format("On %@ +%lld more", preview, remainder) }
        return AppLocalization.format("dashboard.asset.onChain", preview)
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
typealias DashboardAssetChainEntry = CoreDashboardAssetChainEntry
extension CoreDashboardAssetChainEntry: Identifiable {
    public var id: String {
        let contract =
            normalizeDashboardContractAddress(
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
    var color: Color { representativeCoin.color }
    var totalValueUSD: Double? { totalValueUsd }
    init(
        id: String, representativeCoin: Coin, totalAmount: Double, totalValueUSD: Double?, chainEntries: [DashboardAssetChainEntry],
        isPinned: Bool
    ) {
        self.init(
            id: id, representativeCoin: representativeCoin, totalAmount: totalAmount, totalValueUsd: totalValueUSD,
            chainEntries: chainEntries, isPinned: isPinned)
    }
}

typealias DashboardPinOption = CoreDashboardPinOption
extension CoreDashboardPinOption: Identifiable {
    public var id: String { symbol }
    var color: Color { Coin.displayColor(for: symbol) }
}
struct AssetGroupDetailView: View {
    let store: AppState
    let assetGroup: DashboardAssetGroup
    private var supportedTokenEntries: [TokenPreferenceEntry] {
        store.cachedDashboardSupportedTokenEntriesBySymbol[assetGroup.symbol.uppercased()] ?? []
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: assetGroup.iconIdentifier, fallbackText: assetGroup.symbol, color: assetGroup.color, size: 52
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetGroup.name).font(.headline)
                            Text(assetGroup.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    DashboardDetailRow(
                        label: AppLocalization.string("Total Amount"),
                        value: store.formattedAssetAmount(
                            assetGroup.totalAmount, symbol: assetGroup.symbol, chainName: assetGroup.representativeCoin.chainName
                        )
                    )
                    DashboardDetailRow(
                        label: AppLocalization.string("Total Value"),
                        value: store.formattedFiatAmountOrZero(fromUSD: assetGroup.totalValueUSD))
                    DashboardDetailRow(label: AppLocalization.string("Chains"), value: "\(assetGroup.chainEntries.count)")
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(AppLocalization.string("Chain Breakdown")).font(.headline).foregroundStyle(Color.primary)
                        Spacer()
                        Text("\(assetGroup.chainEntries.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if assetGroup.chainEntries.isEmpty {
                        Text(AppLocalization.string("No chain balances yet for this asset.")).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(assetGroup.chainEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.displayChainTitle(for: entry.coin.chainName)).font(.headline)
                                        Text(entry.coin.tokenStandard).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(
                                            store.formattedAssetAmount(
                                                entry.coin.amount, symbol: entry.coin.symbol, chainName: entry.coin.chainName)
                                        ).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).spectraNumericTextLayout()
                                        Text(store.formattedFiatAmountOrZero(fromUSD: entry.valueUSD)).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
                                    }
                                }
                            }.padding(.vertical, 4)
                        }
                        Text(
                            AppLocalization.string(
                                "This asset view merges balances across chains while preserving the per-chain token standard details here.")
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.navigationTitle(assetGroup.symbol).navigationBarTitleDisplayMode(.inline).toolbar {
            if !supportedTokenEntries.isEmpty {
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
    private var supportedTokenEntries: [TokenPreferenceEntry] {
        store.cachedDashboardSupportedTokenEntriesBySymbol[assetGroup.symbol.uppercased()] ?? []
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CoinBadge(
                            assetIdentifier: assetGroup.iconIdentifier, fallbackText: assetGroup.symbol, color: assetGroup.color, size: 44
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assetGroup.name).font(.headline)
                            Text(assetGroup.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    DashboardDetailRow(label: AppLocalization.string("Supported Chains"), value: "\(supportedTokenEntries.count)")
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.string("Contracts")).font(.headline).foregroundStyle(Color.primary)
                    if supportedTokenEntries.isEmpty {
                        Text(AppLocalization.string("No contract addresses are available for this asset.")).font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(supportedTokenEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.chain.rawValue).font(.headline)
                                        Text(entry.tokenStandard).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                Text(entry.contractAddress).font(.footnote.monospaced()).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }.padding(.vertical, 4)
                        }
                    }
                }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
        }.navigationTitle(AppLocalization.format("%@ Details", assetGroup.symbol)).navigationBarTitleDisplayMode(
            .inline)
    }
}
struct PinnedAssetsView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            List {
                Section {
                    ForEach(filteredOptions) { option in
                        Toggle(isOn: binding(for: option.symbol)) {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalization.string("Reset")) {
                        store.resetPinnedDashboardAssets()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
    private func binding(for symbol: String) -> Binding<Bool> {
        Binding(
            get: { store.isDashboardAssetPinned(symbol) }, set: { isPinned in store.setDashboardAssetPinned(isPinned, symbol: symbol) }
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
    let chainSummaryText: String
    var id: String { assetGroup.id }
}
struct DashboardDetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.caption)
    }
}
struct DashboardAssetRowView: View, Equatable {
    let presentation: DashboardAssetRowPresentation
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.presentation == rhs.presentation }
    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: presentation.assetGroup.iconIdentifier, fallbackText: presentation.assetGroup.symbol,
                color: presentation.assetGroup.color, size: 40
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if presentation.assetGroup.isPinned {
                        Image(systemName: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.red.opacity(0.82)).frame(
                            width: 28, height: 20
                        ).background(Color.red.opacity(0.1), in: Capsule()).clipped()
                    }
                    Text(presentation.assetGroup.name).font(.headline).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.tail)
                }
                Text(presentation.amountText).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
                Text(presentation.chainSummaryText).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
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
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.option == rhs.option && lhs.subtitleText == rhs.subtitleText }
    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(assetIdentifier: option.assetIdentifier, fallbackText: option.symbol, color: option.color, size: 34)
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
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.walletName == rhs.walletName && lhs.chainTitleText == rhs.chainTitleText }
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
                    dashboardComponentsLocalizedFormat(
                        "Last known healthy sync: %@", timestamp.formatted(date: .abbreviated, time: .shortened))
                ).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
private func dashboardComponentsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}

// ── Dashboard top-level sections ────────────────────────────────────────
// Each section is a standalone `View` struct so its internal TupleView
// types don't cascade into `DashboardView.body`'s opaque return. This
// matches the SetupView refactor and Apple's preferred pattern of many
// focused `View` structs rather than long computed-var bodies.

private struct DashboardPortfolioHeader: View {
    @Bindable var store: AppState
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("Portfolio")).font(.subheadline).foregroundStyle(.secondary)
                Text(store.preferences.hideBalances ? "••••••" : store.formattedFiatAmountOrZero(fromUSD: store.totalBalanceIfAvailable))
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                Text(AppLocalization.format("%lld in total", store.cachedIncludedPortfolioWallets.count)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                PortfolioWalletSelectionView(store: store)
            } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).padding(10)
            }.buttonStyle(.glass)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
    }
}

private struct DashboardActionButtons: View {
    @Bindable var store: AppState
    var body: some View {
        let canSend = store.canBeginSend
        let canReceive = store.canBeginReceive
        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { store.beginSend() } label: {
                    Label(AppLocalization.string("Send"), systemImage: "arrow.up.right")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                }.buttonStyle(.glass).disabled(!canSend)
                Button { store.beginReceive() } label: {
                    Label(AppLocalization.string("Receive"), systemImage: "arrow.down.left")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                }.buttonStyle(.glassProminent).disabled(!canReceive)
            }
        }
    }
}
