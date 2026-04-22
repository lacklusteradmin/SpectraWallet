import SwiftUI
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
                CoinBadge(
                    assetIdentifier: row.transaction.assetIdentifier, fallbackText: row.transaction.symbol,
                    color: row.transaction.badgeColor, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    if let amountText = row.amountText {
                        Text(amountText).font(.headline.weight(.semibold)).foregroundStyle(row.amountColor ?? Color.primary)
                            .spectraNumericTextLayout()
                    }
                    Text(row.subtitleText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(row.statusText).font(.caption2.bold()).foregroundStyle(Color.primary).padding(.horizontal, 8).padding(.vertical, 5)
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
    @State private var selectedWalletID: String?
    @State private var searchText: String = ""
    @State private var currentPageIndex: Int = 0
    private let entriesPerPage = 10
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if visibleTransactions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(emptyStateTitle).font(.body)
                                Text(emptyStateMessage).font(.footnote).foregroundStyle(.secondary)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
                        } else {
                            ForEach(groupedSections) { section in
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(AppLocalization.format("history.section.titleCount", section.title, section.rows.count))
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                                        Spacer()
                                    }.padding(.horizontal, 20).padding(.vertical, 14)
                                    Divider().opacity(0.35)
                                    VStack(spacing: 0) {
                                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                            NavigationLink {
                                                HistoryDetailView(store: store, transaction: row.transaction)
                                            } label: {
                                                HistoryTransactionRowView(row: row).equatable()
                                                    .padding(.horizontal, 20).padding(.vertical, 12)
                                            }.buttonStyle(.plain).contextMenu {
                                                if row.transaction.kind == .send,
                                                    row.transaction.status == .pending || row.transaction.status == .failed
                                                {
                                                    if ["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"].contains(row.transaction.chainName) {
                                                        Button {
                                                            Task { _ = await store.retryUTXOTransactionStatus(for: row.transaction.id) }
                                                        } label: {
                                                            Label(AppLocalization.string("Recheck"), systemImage: "arrow.clockwise")
                                                        }
                                                    }
                                                    if row.transaction.supportsSignedRebroadcast {
                                                        Button {
                                                            Task { _ = await store.rebroadcastSignedTransaction(for: row.transaction.id) }
                                                        } label: {
                                                            Label(AppLocalization.string("Rebroadcast"), systemImage: "dot.radiowaves.up.forward")
                                                        }
                                                    }
                                                }
                                            }
                                            if index < section.rows.count - 1 { Divider().padding(.leading, 72).opacity(0.25) }
                                        }
                                    }.padding(.vertical, 4)
                                }.frame(maxWidth: .infinity).glassEffect(.regular.tint(.white.opacity(0.03)).interactive(), in: .rect(cornerRadius: 28))
                            }
                        }
                        if shouldShowPagingControls { historyPagingControls }
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                }.refreshable {
                    await store.performUserInitiatedRefresh()
                }.scrollBounceBehavior(.always)
            }.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                         prompt: AppLocalization.string("Search wallet, asset, symbol, or address"))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle(AppLocalization.string("History")).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { historyFilterMenu.buttonStyle(.glass) }
            }.onChange(of: selectedFilter) { _, _ in
                resetPaging()
            }.onChange(of: selectedSortOrder) { _, _ in
                resetPaging()
            }.onChange(of: selectedWalletID) { _, _ in
                resetPaging()
            }.onChange(of: searchText) { _, _ in
                resetPaging()
            }.onChange(of: currentPageIndex) { _, _ in
                prefetchHistoryIfNeeded()
            }
        }
    }
    private var historyFilterMenu: some View {
        Menu {
            Picker(AppLocalization.string("Wallet"), selection: $selectedWalletID) {
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
    private var clampedPageIndex: Int {
        guard totalLoadedPages > 0 else { return 0 }
        return min(currentPageIndex, totalLoadedPages - 1)
    }
    private var totalLoadedPages: Int { max(1, Int(ceil(Double(visibleTransactions.count) / Double(entriesPerPage)))) }
    private var hasNextLoadedPage: Bool { clampedPageIndex < totalLoadedPages - 1 }
    private var loadedHistoryWalletIDs: Set<String> { Set(visibleTransactions.compactMap(\.walletID)) }
    private var canLoadMoreVisibleHistory: Bool { store.canLoadMoreOnChainHistory(for: loadedHistoryWalletIDs) }
    private var shouldShowPagingControls: Bool {
        !visibleRows.isEmpty
            && (clampedPageIndex > 0 || hasNextLoadedPage || canLoadMoreVisibleHistory || store.isLoadingMoreOnChainHistory)
    }
    private var pagedRows: [HistoryRowPresentation] {
        let startIndex = clampedPageIndex * entriesPerPage
        return Array(visibleRows.dropFirst(startIndex).prefix(entriesPerPage))
    }
    private var groupedSections: [HistoryPresentationSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: pagedRows) { row in
            if calendar.isDateInToday(row.transaction.createdAt) { return AppLocalization.string("Today") }
            if calendar.isDateInYesterday(row.transaction.createdAt) { return AppLocalization.string("Yesterday") }
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
    private var visibleTransactions: [TransactionRecord] {
        guard !store.wallets.isEmpty else { return [] }
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let transactionByID = store.cachedTransactionByID
        let filteredTransactions: [TransactionRecord] = store.normalizedHistoryIndex.compactMap { entry in
            guard let transaction = transactionByID[entry.transactionID] else { return nil }
            if let selectedWalletID, transaction.walletID != selectedWalletID { return nil }
            switch selectedFilter {
            case .all: break
            case .sends: guard entry.kind == .send else { return nil }
            case .receives: guard entry.kind == .receive else { return nil }
            case .pending: guard entry.status == .pending else { return nil }
            }
            if !trimmedQuery.isEmpty && !entry.searchIndex.contains(trimmedQuery) { return nil }
            return transaction
        }
        switch selectedSortOrder {
        case .newest: return filteredTransactions
        case .oldest: return Array(filteredTransactions.reversed())
        }
    }
    private var visibleRows: [HistoryRowPresentation] {
        visibleTransactions.map(historyRowPresentation)
    }
    private func resetPaging() {
        currentPageIndex = 0
    }
    private func prefetchHistoryIfNeeded() {
        let candidateWalletIDs = historyPrefetchCandidateWalletIDs()
        guard !candidateWalletIDs.isEmpty else { return }
        Task {
            await store.loadMoreOnChainHistory(for: candidateWalletIDs)
        }
    }
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
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(AppLocalization.string("Last"))
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }.buttonStyle(.plain).disabled(clampedPageIndex == 0 || store.isLoadingMoreOnChainHistory).opacity(
                (clampedPageIndex == 0 || store.isLoadingMoreOnChainHistory) ? 0.4 : 1)
            Text(AppLocalization.format("Page %lld", clampedPageIndex + 1)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 8).background(Color.white.opacity(0.06), in: Capsule())
            Button {
                Task {
                    if hasNextLoadedPage {
                        currentPageIndex = clampedPageIndex + 1
                        return
                    }
                    let candidateWalletIDs = historyPrefetchCandidateWalletIDs()
                    guard !candidateWalletIDs.isEmpty else { return }
                    let previousPageCount = totalLoadedPages
                    await store.loadMoreOnChainHistory(for: candidateWalletIDs)
                    if totalLoadedPages > previousPageCount {
                        currentPageIndex = min(clampedPageIndex + 1, totalLoadedPages - 1)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(store.isLoadingMoreOnChainHistory ? AppLocalization.string("Loading") : AppLocalization.string("Next"))
                    if store.isLoadingMoreOnChainHistory {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "chevron.right")
                    }
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }.buttonStyle(.plain).disabled((!hasNextLoadedPage && !canLoadMoreVisibleHistory) || store.isLoadingMoreOnChainHistory).opacity(
                ((!hasNextLoadedPage && !canLoadMoreVisibleHistory) || store.isLoadingMoreOnChainHistory) ? 0.4 : 1)
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
    private var emptyStateTitle: String {
        store.normalizedHistoryIndex.isEmpty
            ? AppLocalization.string("No activity yet")
            : AppLocalization.string("No matches found")
    }
    private var emptyStateMessage: String {
        if store.wallets.isEmpty { return AppLocalization.string("No wallets are currently loaded. Import a wallet to view activity.") }
        if store.normalizedHistoryIndex.isEmpty {
            return AppLocalization.string("Send funds or receive funds to build a persistent transaction log.")
        }
        return AppLocalization.string("Try a different filter or search term.")
    }
    private var selectedWalletName: String {
        guard let selectedWalletID, let wallet = store.wallet(for: selectedWalletID) else { return AppLocalization.string("All Wallets") }
        return wallet.name
    }
    @ViewBuilder
    private func filterCapsuleLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
            }
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle(cornerRadius: 16)
    }
    private func historyRowPresentation(for transaction: TransactionRecord) -> HistoryRowPresentation {
        HistoryRowPresentation(
            transaction: transaction, amountText: signedAmountText(for: transaction), amountColor: amountColor(for: transaction),
            subtitleText: String(
                format: CommonLocalizationContent.current.transactionSubtitleFormat, transaction.assetName,
                store.displayChainTitle(for: transaction), transaction.walletName
            ), statusText: transaction.statusText, fullTimestampText: transaction.fullTimestampText,
            metadataText: transaction.historyMetadataText
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
        switch transaction.kind {
        case .receive: return .mint
        case .send: return .red
        }
    }
}

