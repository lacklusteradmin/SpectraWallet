import SwiftUI
private struct HistoryRowPresentation: Identifiable, Equatable {
    let transaction: TransactionRecord
    let amountText: String?
    let amountColor: Color?
    let subtitleText: String
    let statusText: String
    let fullTimestampText: String
    let metadataText: String?
    var id: String { transaction.id }
}

private struct HistoryTransactionRowView: View, Equatable {
    let row: HistoryRowPresentation
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                CoinBadge(
                    artworkName: row.transaction.artworkName, fallbackText: row.transaction.symbol,
                    color: row.transaction.badgeColor, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    if let amountText = row.amountText {
                        Text(amountText).font(.headline.weight(.semibold)).foregroundStyle(row.amountColor ?? Color.primary)
                            .spectraNumericTextLayout()
                    }
                    Text(row.subtitleText).spectraHintText().lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(row.statusText).font(.caption2.bold()).foregroundStyle(Color.primary).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(row.transaction.statusColor.opacity(0.85), in: Capsule())
                    Text(row.fullTimestampText).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(
                        .trailing)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if let metadataText = row.metadataText {
                Text(metadataText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
private struct HistoryPresentationSection: Identifiable {
    let title: String
    let rows: [HistoryRowPresentation]
    var id: String { title }
}
struct HistoryView: View {
    let store: AppState
    @State private var selectedFilter: HistoryFilter = .all
    @State private var selectedSortOrder: HistorySortOrder = .newest
    @State private var selectedWalletId: String?
    @State private var searchText: String = ""
    @State private var pageRecords: [TransactionRecord] = []
    @State private var nextOffset: UInt64 = 0
    @State private var hasMoreStoredHistory = false
    @State private var pageError: String?
    @State private var isLoadingPage = false
    @State private var pageRequestId = UUID()
    @State private var loadedFilterKey: String?
    @State private var isRetrying = false
    @State private var recheckingIds: Set<String> = []
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: SpectraLayout.sectionSpacing) {
                        if let error = historyError {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(AppLocalization.string("Unable to load history"), systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                Text(error).font(.subheadline).foregroundStyle(.secondary)
                                Button(AppLocalization.string("Retry")) {
                                    isRetrying = true
                                    Task {
                                        await store.refreshTransactionProjection()
                                        await loadPage(reset: true)
                                        await store.performUserInitiatedRefresh()
                                        isRetrying = false
                                    }
                                }.buttonStyle(.glass).disabled(isRetrying)
                            }.padding(20).spectraCardFill()
                        }
                        if visibleTransactions.isEmpty && historyError == nil {
                            historyEmptyStateCard
                        }
                        ForEach(groupedSections) { section in
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(AppLocalization.format("history.section.titleCount", section.title, section.rows.count))
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                                        Spacer()
                                    }.padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.cardHeaderVertical)
                                    Divider().opacity(0.25)
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                            NavigationLink {
                                                TransactionDetailView(store: store, transaction: row.transaction)
                                            } label: {
                                                HistoryTransactionRowView(row: row).equatable()
                                                    .padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.rowVertical)
                                            }.buttonStyle(.plain).contextMenu {
                                                if row.transaction.status == .pending || row.transaction.status == .failed {
                                                    // `supportsStatusRecheck` carries the `kind == .send`
                                                    // rule for the chains that want it; a blanket gate here
                                                    // hid the button from the one chain that does not.
                                                    if row.transaction.supportsStatusRecheck {
                                                        Button {
                                                            spectraHaptic(.light)
                                                            Task { _ = await store.retryUTXOTransactionStatus(for: row.transaction.id) }
                                                        } label: {
                                                            Label(AppLocalization.string("Recheck"), systemImage: "arrow.clockwise")
                                                        }
                                                    }
                                                    if row.transaction.supportsSignedRebroadcast {
                                                        Button {
                                                            spectraHaptic(.light)
                                                            Task { _ = await store.rebroadcastSignedTransaction(for: row.transaction.id) }
                                                        } label: {
                                                            Label(AppLocalization.string("Rebroadcast"), systemImage: "dot.radiowaves.up.forward")
                                                        }
                                                    }
                                                }
                                            }
                                            if (row.transaction.status == .pending || row.transaction.status == .failed), row.transaction.supportsStatusRecheck {
                                                Button {
                                                    recheckingIds.insert(row.id)
                                                    Task {
                                                        _ = await store.retryUTXOTransactionStatus(for: row.id)
                                                        recheckingIds.remove(row.id)
                                                    }
                                                } label: {
                                                    Label(AppLocalization.string("Recheck"), systemImage: "arrow.clockwise")
                                                        .frame(minHeight: 44)
                                                }
                                                .buttonStyle(.glass)
                                                .disabled(recheckingIds.contains(row.id))
                                                .padding(.bottom, 12)
                                            }
                                            if index < section.rows.count - 1 { Divider().padding(.leading, 64).opacity(0.25) }
                                        }
                                    }.padding(.vertical, 4)
                                }.frame(maxWidth: .infinity).glassEffect(
                                    .regular.tint(SpectraLayout.GlassTint.content).interactive(),
                                    in: .rect(cornerRadius: SpectraLayout.Radius.hero))
                            }
                        if shouldShowPagingControls { historyPagingControls }
                    }.padding(.horizontal, SpectraLayout.screenHorizontal).padding(.top, SpectraLayout.screenTop).padding(
                        .bottom, SpectraLayout.screenBottom)
                }.refreshable {
                    await store.performUserInitiatedRefresh()
                }.scrollBounceBehavior(.always)
            }.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                         prompt: AppLocalization.string("Search wallet, asset, symbol, or address"))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle(AppLocalization.string("History")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { historyFilterMenu }
            }.task(id: queryKey) { await loadPage(reset: true) }
        }
    }
    private var historyFilterMenu: some View {
        Menu {
            Picker(AppLocalization.string("Wallet"), selection: $selectedWalletId) {
                Text(AppLocalization.string("All Wallets")).tag(Optional<String>.none)
                ForEach(store.wallets) { wallet in Text(wallet.name).tag(Optional(wallet.id)) }
            }
            Picker(AppLocalization.string("Type"), selection: $selectedFilter) {
                ForEach(HistoryFilter.allCases) { filter in Text(filter.localizedTitle).tag(filter) }
            }
            Picker(AppLocalization.string("Sort"), selection: $selectedSortOrder) {
                ForEach(HistorySortOrder.allCases) { sortOrder in Text(sortOrder.localizedTitle).tag(sortOrder) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }.accessibilityLabel(AppLocalization.string("Filter history"))
    }

    private var historyWalletIds: Set<String> {
        if let selectedWalletId { return [selectedWalletId] }
        return Set(store.wallets.map(\.id))
    }
    private var canLoadMoreVisibleHistory: Bool { store.canLoadMoreOnChainHistory(for: historyWalletIds) }
    private var shouldShowPagingControls: Bool {
        hasMoreStoredHistory || canLoadMoreVisibleHistory || store.isLoadingMoreOnChainHistory
    }
    private var pagedRows: [HistoryRowPresentation] {
        visibleTransactions.map(historyRowPresentation)
    }
    private var groupedSections: [HistoryPresentationSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: pagedRows) { row in
            if calendar.isDateInToday(row.transaction.createdDate) { return AppLocalization.string("Today") }
            if calendar.isDateInYesterday(row.transaction.createdDate) { return AppLocalization.string("Yesterday") }
            return AppLocalization.string("Older")
        }
        let order: [String]
        switch selectedSortOrder {
        case .newest:
            order = [
                AppLocalization.string("Today"), AppLocalization.string("Yesterday"), AppLocalization.string("Older"),
            ]
        case .oldest:
            order = [
                AppLocalization.string("Older"), AppLocalization.string("Yesterday"), AppLocalization.string("Today"),
            ]
        }
        return order.compactMap { title in
            guard let rows = grouped[title], !rows.isEmpty else { return nil }
            return HistoryPresentationSection(title: title, rows: rows)
        }
    }
    private var historyError: String? { pageError ?? store.historyReadError }
    private var visibleTransactions: [TransactionRecord] { pageRecords }
    private var filterKey: String {
        "\(selectedWalletId ?? "")|\(selectedFilter)|\(selectedSortOrder)|\(searchText)"
    }
    private var queryKey: String { "\(filterKey)|\(store.transactionRevision)|\(store.walletsRevision)" }
    private func loadPage(reset: Bool) async {
        let key = queryKey
        if loadedFilterKey != filterKey {
            pageRecords = []
            hasMoreStoredHistory = false
            loadedFilterKey = filterKey
        }
        let requestId = UUID()
        pageRequestId = requestId
        isLoadingPage = true
        defer { if pageRequestId == requestId { isLoadingPage = false } }
        let filter: HistoryQueryFilter
        switch selectedFilter {
        case .all: filter = .all
        case .sends: filter = .send
        case .receives: filter = .receive
        case .pending: filter = .pending
        }
        do {
            let page = try await WalletServiceBridge.shared.historyPage(HistoryQuery(
                walletId: selectedWalletId, filter: filter, search: searchText,
                oldestFirst: selectedSortOrder == .oldest, offset: reset ? 0 : nextOffset, limit: 20))
            guard !Task.isCancelled, pageRequestId == requestId, queryKey == key else { return }
            if reset { pageRecords = page.records }
            else {
                let present = Set(pageRecords.map(\.id))
                pageRecords += page.records.filter { !present.contains($0.id) }
            }
            nextOffset = page.nextOffset
            hasMoreStoredHistory = page.hasMore
            pageError = nil
        } catch {
            guard !Task.isCancelled, pageRequestId == requestId, queryKey == key else { return }
            pageError = error.localizedDescription
        }
    }
    private var historyPagingControls: some View {
        Button {
            Task {
                if !hasMoreStoredHistory {
                    await store.loadMoreOnChainHistory(for: historyWalletIds)
                    await loadPage(reset: true)
                } else {
                    await loadPage(reset: false)
                }
            }
        } label: {
            HStack {
                if store.isLoadingMoreOnChainHistory { ProgressView() }
                Text(AppLocalization.string(store.isLoadingMoreOnChainHistory ? "Loading" : "Load more"))
            }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(store.isLoadingMoreOnChainHistory || isLoadingPage)
    }
    private var historyEmptyStateCard: some View {
        SpectraEmptyStateCard(
            title: emptyStateTitle,
            message: emptyStateMessage,
            systemImage: store.transactionCount == 0 ? "clock.arrow.circlepath" : "magnifyingglass"
        )
    }
    private var emptyStateTitle: String {
        store.transactionCount == 0
            ? AppLocalization.string("No activity yet")
            : AppLocalization.string("No matches found")
    }
    private var emptyStateMessage: String {
        if store.wallets.isEmpty { return AppLocalization.string("No wallets are currently loaded. Import a wallet to view activity.") }
        if store.transactionCount == 0 {
            return AppLocalization.string("Send funds or receive funds to build a persistent transaction log.")
        }
        return AppLocalization.string("Try a different filter or search term.")
    }
    private func historyRowPresentation(for transaction: TransactionRecord) -> HistoryRowPresentation {
        HistoryRowPresentation(
            transaction: transaction, amountText: signedAmountText(for: transaction), amountColor: amountColor(for: transaction),
            subtitleText: transaction.walletName, statusText: transaction.statusText, fullTimestampText: transaction.fullTimestampText,
            metadataText: store.historyMetadataText(for: transaction)
        )
    }
    private func signedAmountText(for transaction: TransactionRecord) -> String? {
        guard let amountText = store.formattedTransactionAmount(transaction) else { return nil }
        switch transaction.kind {
        case .receive: return "+\(amountText)"
        case .send: return "-\(amountText)"
        }
    }
    private func amountColor(for transaction: TransactionRecord) -> Color {
        Color.spectraTransactionAmountColor(isReceive: transaction.kind == .receive)
    }
}
