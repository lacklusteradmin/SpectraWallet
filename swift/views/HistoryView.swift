import SwiftUI
private func localizedHistoryString(_ key: String) -> String {
    AppLocalization.string(key)
}
private struct HistoryRowPresentation: Identifiable, Equatable {
    let transaction: TransactionRecord
    let amountText: String?
    let amountColor: Color?
    let subtitleText: String
    let statusText: String
    let fullTimestampText: String
    let metadataText: String?
    var id: UUID { transaction.id }
}

private struct HistoryTransactionRowView: View, Equatable {
    let row: HistoryRowPresentation
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoinBadge(assetIdentifier: row.transaction.assetIdentifier, fallbackText: row.transaction.symbol, color: row.transaction.badgeColor, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    if let amountText = row.amountText { Text(amountText).font(.headline.weight(.semibold)).foregroundStyle(row.amountColor ?? Color.primary).spectraNumericTextLayout() }
                    Text(row.subtitleText).font(.caption).foregroundStyle(Color.primary.opacity(0.72))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(row.statusText).font(.caption2.bold()).foregroundStyle(Color.primary).padding(.horizontal, 8).padding(.vertical, 5).background(row.transaction.statusColor.opacity(0.85), in: Capsule())
                    Text(row.fullTimestampText).font(.caption2).foregroundStyle(Color.primary.opacity(0.6)).multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.35))
            }
            if let metadataText = row.metadataText { Text(metadataText).font(.caption2).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1) }}.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 22))
    }
}
private struct HistoryPresentationSection: Identifiable {
    let title: String
    let rows: [HistoryRowPresentation]
    var id: String { title }
}
struct HistoryView: View {
    @ObservedObject var store: AppState
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedSortOrder: HistorySortOrder = .newest
    @State private var selectedWalletID: String?
    @State private var searchText: String = ""
    @State private var currentPageIndex: Int = 0
    @State private var pendingScrollToTopToken = UUID()
    @State private var visibleTransactions: [TransactionRecord] = []
    @State private var visibleRows: [HistoryRowPresentation] = []
    @State private var groupedSectionsCache: [HistoryPresentationSection] = []
    private let entriesPerPage = 10
    init(store: AppState) {
        self.store = store
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    SpectraBackdrop()
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Color.clear.frame(height: 1).id("history-top")
                            controlsCard
                            if visibleTransactions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(emptyStateTitle).font(.headline).foregroundStyle(Color.primary)
                                    Text(emptyStateMessage).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
                                }.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                            } else {
                                ForEach(groupedSections) { section in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(localizedFormat("history.section.titleCount", section.title, section.rows.count)).font(.headline).foregroundStyle(Color.primary.opacity(0.88))
                                        ForEach(section.rows) { row in
                                            VStack(alignment: .leading, spacing: 10) {
                                                NavigationLink {
                                                    HistoryDetailView(store: store, transaction: row.transaction)
                                                } label: { HistoryTransactionRowView(row: row).equatable() }.buttonStyle(.plain).swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                    if row.transaction.kind == .send, row.transaction.status == .pending || row.transaction.status == .failed {
                                                        if ["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"].contains(row.transaction.chainName) {
                                                            Button {
                                                                Task {
                                                                    _ = await store.retryUTXOTransactionStatus(for: row.transaction.id)
                                                                }} label: { Label(localizedHistoryString("Recheck"), systemImage: "arrow.clockwise") }.tint(.blue)
                                                        }
                                                        if row.transaction.supportsSignedRebroadcast {
                                                            Button {
                                                                Task {
                                                                    _ = await store.rebroadcastSignedTransaction(for: row.transaction.id)
                                                                }} label: { Label(localizedHistoryString("Rebroadcast"), systemImage: "dot.radiowaves.up.forward") }.tint(.mint)
                                                        }}}}}}.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
                                }}
                            if shouldShowPagingControls { historyPagingControls }}.padding(20)
                    }.refreshable {
                        await store.performUserInitiatedRefresh()
                    }.scrollBounceBehavior(.always)
                }.onChange(of: pendingScrollToTopToken) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("history-top", anchor: .top)
                    }}}.navigationTitle(localizedHistoryString("History")).navigationBarTitleDisplayMode(.inline).onAppear {
                rebuildVisibleTransactions(resetPaging: true)
            }.onChange(of: store.transactionRevision) { _, _ in
                rebuildVisibleTransactions()
            }.onChange(of: store.normalizedHistoryRevision) { _, _ in
                rebuildVisibleTransactions()
            }.onChange(of: store.walletsRevision) { _, _ in
                rebuildVisibleTransactions()
            }.onChange(of: selectedFilter) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }.onChange(of: selectedSortOrder) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }.onChange(of: selectedWalletID) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }.onChange(of: searchText) { _, _ in
                rebuildVisibleTransactions(resetPaging: true)
            }.onChange(of: currentPageIndex) { _, _ in
                rebuildGroupedSections()
                prefetchHistoryIfNeeded()
            }}}
    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(localizedHistoryString("Search wallet, asset, symbol, or address"), text: $searchText).textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 14).padding(.vertical, 12).spectraInputFieldStyle(cornerRadius: 16).foregroundStyle(Color.primary)
            HStack(spacing: 10) {
                Menu {
                    Picker(localizedHistoryString("Wallet"), selection: $selectedWalletID) {
                        Text(localizedHistoryString("All Wallets")).tag(Optional<UUID>.none)
                        ForEach(store.wallets) { wallet in Text(wallet.name).tag(Optional(wallet.id)) }}} label: {
                    filterCapsuleLabel(
                        title: localizedHistoryString("Wallet"), value: selectedWalletName, systemImage: "wallet.pass"
                    )
                }
                Menu {
                    Picker(localizedHistoryString("Type"), selection: $selectedFilter) {
                        ForEach(HistoryFilter.allCases) { filter in Text(filter.localizedTitle).tag(filter) }}} label: {
                    filterCapsuleLabel(
                        title: localizedHistoryString("Type"), value: selectedFilter.localizedTitle, systemImage: "line.3.horizontal.decrease.circle"
                    )
                }
                Menu {
                    Picker(localizedHistoryString("Sort"), selection: $selectedSortOrder) {
                        ForEach(HistorySortOrder.allCases) { sortOrder in Text(sortOrder.localizedTitle).tag(sortOrder) }}} label: {
                    filterCapsuleLabel(
                        title: localizedHistoryString("Sort"), value: selectedSortOrder.localizedTitle, systemImage: "arrow.up.arrow.down.circle"
                    )
                }}.frame(maxWidth: .infinity, alignment: .leading)
            if selectedWalletID != nil || selectedFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    Text(localizedFormat("%lld results", visibleTransactions.count)).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.8))
                    Spacer()
                    Button(localizedHistoryString("Clear Filters")) {
                        selectedWalletID = nil
                        selectedFilter = .all
                        selectedSortOrder = .newest
                        searchText = ""
                    }.font(.caption.weight(.semibold)).foregroundStyle(.mint).buttonStyle(.plain)
                }}}.padding(18).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    private var clampedPageIndex: Int {
        guard totalLoadedPages > 0 else { return 0 }
        return min(currentPageIndex, totalLoadedPages - 1)
    }
    private var totalLoadedPages: Int { max(1, Int(ceil(Double(visibleTransactions.count) / Double(entriesPerPage)))) }
    private var hasNextLoadedPage: Bool { clampedPageIndex < totalLoadedPages - 1 }
    private var loadedHistoryWalletIDs: Set<String> { Set(visibleTransactions.compactMap(\.walletID)) }
    private var canLoadMoreVisibleHistory: Bool { store.canLoadMoreOnChainHistory(for: loadedHistoryWalletIDs) }
    private var shouldShowPagingControls: Bool { !visibleRows.isEmpty && (clampedPageIndex > 0 || hasNextLoadedPage || canLoadMoreVisibleHistory || store.isLoadingMoreOnChainHistory) }
    private var pagedRows: [HistoryRowPresentation] {
        let startIndex = clampedPageIndex * entriesPerPage
        return Array(visibleRows.dropFirst(startIndex).prefix(entriesPerPage))
    }
    private var groupedSections: [HistoryPresentationSection] { groupedSectionsCache }
    private func rebuildGroupedSections() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: pagedRows) { row in
            if calendar.isDateInToday(row.transaction.createdAt) { return localizedHistoryString("Today") }
            if calendar.isDateInYesterday(row.transaction.createdAt) { return localizedHistoryString("Yesterday") }
            return localizedHistoryString("Older")
        }
        let order: [String]
        switch selectedSortOrder {
        case .newest: order = [
                localizedHistoryString("Today"), localizedHistoryString("Yesterday"), localizedHistoryString("Older")
            ]
        case .oldest: order = [
                localizedHistoryString("Older"), localizedHistoryString("Yesterday"), localizedHistoryString("Today")
            ]
        }
        groupedSectionsCache = order.compactMap { title in
            guard let rows = grouped[title], !rows.isEmpty else { return nil }
            return HistoryPresentationSection(title: title, rows: rows)
        }}
    private func rebuildVisibleTransactions(resetPaging: Bool = false) {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rebuiltTransactions: [TransactionRecord]
        if store.wallets.isEmpty { rebuiltTransactions = [] } else {
            let transactionByID = store.cachedTransactionByID
            let filteredTransactions: [TransactionRecord] = store.normalizedHistoryIndex.compactMap { entry in
                guard let transaction = transactionByID[entry.transactionID] else { return nil }
                if let selectedWalletID, transaction.walletID != selectedWalletID { return nil }
                switch selectedFilter {
                case .all: break
                case .sends: guard entry.kind == .send else { return nil }
                case .receives: guard entry.kind == .receive else { return nil }
                case .pending: guard entry.status == .pending else { return nil }}
                if !trimmedQuery.isEmpty && !entry.searchIndex.contains(trimmedQuery) { return nil }
                return transaction
            }
            switch selectedSortOrder {
            case .newest: rebuiltTransactions = filteredTransactions
            case .oldest: rebuiltTransactions = Array(filteredTransactions.reversed())
            }}
        visibleTransactions = rebuiltTransactions
        visibleRows = rebuiltTransactions.map(historyRowPresentation)
        rebuildGroupedSections()
        if resetPaging {
            currentPageIndex = 0
            pendingScrollToTopToken = UUID()
        } else if currentPageIndex != clampedPageIndex { currentPageIndex = clampedPageIndex }}
    private func prefetchHistoryIfNeeded() {
        let candidateWalletIDs = historyPrefetchCandidateWalletIDs()
        guard !candidateWalletIDs.isEmpty else { return }
        Task {
            await store.loadMoreOnChainHistory(for: candidateWalletIDs)
        }}
    private func historyPrefetchCandidateWalletIDs() -> Set<String> {
        let currentPageWalletIDs = Set(pagedRows.compactMap(\.transaction.walletID))
        guard !currentPageWalletIDs.isEmpty else { return [] }
        let nextLoadedTransactions = Array(visibleTransactions.dropFirst((clampedPageIndex + 1) * entriesPerPage))
        var remainingCountByWallet: [String: Int] = [:]
        for transaction in nextLoadedTransactions {
            guard let walletID = transaction.walletID else { continue }
            remainingCountByWallet[walletID, default: 0] += 1
        }
        let candidateWalletIDs = currentPageWalletIDs.filter { walletID in remainingCountByWallet[walletID, default: 0] <= entriesPerPage }
        return Set(candidateWalletIDs.filter { store.canLoadMoreOnChainHistory(for: [$0]) })
    }
    private var historyPagingControls: some View {
        HStack(spacing: 14) {
            Button {
                currentPageIndex = max(0, clampedPageIndex - 1)
                pendingScrollToTopToken = UUID()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(localizedHistoryString("Last"))
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }.buttonStyle(.plain).disabled(clampedPageIndex == 0 || store.isLoadingMoreOnChainHistory).opacity((clampedPageIndex == 0 || store.isLoadingMoreOnChainHistory) ? 0.4 : 1)
            Text(localizedFormat("Page %lld", clampedPageIndex + 1)).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.78)).padding(.horizontal, 14).padding(.vertical, 8).background(Color.white.opacity(0.06), in: Capsule())
            Button {
                Task {
                    if hasNextLoadedPage {
                        currentPageIndex = clampedPageIndex + 1
                        pendingScrollToTopToken = UUID()
                        return
                    }
                    let candidateWalletIDs = historyPrefetchCandidateWalletIDs()
                    guard !candidateWalletIDs.isEmpty else { return }
                    let previousPageCount = totalLoadedPages
                    await store.loadMoreOnChainHistory(for: candidateWalletIDs)
                    if totalLoadedPages > previousPageCount {
                        currentPageIndex = min(clampedPageIndex + 1, totalLoadedPages - 1)
                        pendingScrollToTopToken = UUID()
                    }}} label: {
                HStack(spacing: 6) {
                    Text(store.isLoadingMoreOnChainHistory ? localizedHistoryString("Loading") : localizedHistoryString("Next"))
                    if store.isLoadingMoreOnChainHistory { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "chevron.right") }}.font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }.buttonStyle(.plain).disabled((!hasNextLoadedPage && !canLoadMoreVisibleHistory) || store.isLoadingMoreOnChainHistory).opacity(((!hasNextLoadedPage && !canLoadMoreVisibleHistory) || store.isLoadingMoreOnChainHistory) ? 0.4 : 1)
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity).glassEffect(.regular.tint(.white.opacity(0.028)), in: .capsule)
    }
    private var emptyStateTitle: String {
        store.normalizedHistoryIndex.isEmpty
            ? localizedHistoryString("No activity yet")
            : localizedHistoryString("No matches found")
    }
    private var emptyStateMessage: String {
        if store.wallets.isEmpty { return localizedHistoryString("No wallets are currently loaded. Import a wallet to view activity.") }
        if store.normalizedHistoryIndex.isEmpty { return localizedHistoryString("Send funds or receive funds to build a persistent transaction log.") }
        return localizedHistoryString("Try a different filter or search term.")
    }
    private var selectedWalletName: String {
        guard let selectedWalletID, let wallet = store.wallet(for: selectedWalletID) else { return localizedHistoryString("All Wallets") }
        return wallet.name
    }
    @ViewBuilder
    private func filterCapsuleLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Color.primary.opacity(0.62))
                Text(value).font(.caption.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
            }
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Color.primary.opacity(0.62))
        }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle(cornerRadius: 16)
    }
    private func historyRowPresentation(for transaction: TransactionRecord) -> HistoryRowPresentation {
        HistoryRowPresentation(
            transaction: transaction, amountText: signedAmountText(for: transaction), amountColor: amountColor(for: transaction), subtitleText: String(
                format: CommonLocalizationContent.current.transactionSubtitleFormat, transaction.assetName, store.displayChainTitle(for: transaction), transaction.walletName
            ), statusText: transaction.statusText, fullTimestampText: transaction.fullTimestampText, metadataText: transaction.historyMetadataText
        )
    }
    private func signedAmountText(for transaction: TransactionRecord) -> String? {
        guard let amountText = store.formattedTransactionAmount(transaction) else { return nil }
        switch transaction.kind {
        case .receive: return "+\(amountText)"
        case .send: return "-\(amountText)"
        }}
    private func amountColor(for transaction: TransactionRecord) -> Color {
        switch transaction.kind {
        case .receive: return .mint
        case .send: return .red
        }}
}
private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
