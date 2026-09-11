import Foundation
import SwiftUI
import UIKit
struct LogsView: View {
    let store: AppState
    @State private var searchText: String = ""
    @State private var selectedLevelFilter: LogLevelFilter = .all
    private let allCategoryFilter = "__all__"
    @State private var selectedCategoryFilter: String = "__all__"
    @State private var copiedNotice: SpectraTransientNotice?
    @State private var cachedAvailableCategories: [String] = ["__all__"]
    @State private var cachedFilteredLogs: [AppState.OperationalLogEvent] = []
    private var diagnosticsState: WalletDiagnosticsState { store.diagnostics }
    private enum LogLevelFilter: CaseIterable, Identifiable {
        case all
        case debug
        case info
        case warning
        case error
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return AppLocalization.string("All")
            case .debug: return AppLocalization.string("Debug")
            case .info: return AppLocalization.string("Info")
            case .warning: return AppLocalization.string("Warning")
            case .error: return AppLocalization.string("Error")
            }
        }
    }
    private var availableCategories: [String] { cachedAvailableCategories }
    private var filteredLogs: [AppState.OperationalLogEvent] { cachedFilteredLogs }
    private func rebuildLogPresentation() {
        let categories = Set(diagnosticsState.operationalLogs.map { $0.category })
        cachedAvailableCategories = [allCategoryFilter] + categories.sorted()
        if selectedCategoryFilter != allCategoryFilter, !cachedAvailableCategories.contains(selectedCategoryFilter) {
            selectedCategoryFilter = allCategoryFilter
        }
        cachedFilteredLogs = diagnosticsState.operationalLogs.filter { event in
            let levelMatches: Bool
            switch selectedLevelFilter {
            case .all: levelMatches = true
            case .debug: levelMatches = event.level == .debug
            case .info: levelMatches = event.level == .info
            case .warning: levelMatches = event.level == .warning
            case .error: levelMatches = event.level == .error
            }
            let categoryMatches = selectedCategoryFilter == allCategoryFilter || event.category == selectedCategoryFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches: Bool
            if query.isEmpty {
                searchMatches = true
            } else {
                let haystack = [
                    event.message, event.category, event.chainName ?? "", event.source ?? "", event.metadata ?? "", event.walletID ?? "",
                    event.transactionHash ?? "",
                ].joined(separator: " ").lowercased()
                searchMatches = haystack.contains(query)
            }
            return levelMatches && categoryMatches && searchMatches
        }
    }
    private var summaryText: String {
        let debugCount = filteredLogs.filter { $0.level == .debug }.count
        let infoCount = filteredLogs.filter { $0.level == .info }.count
        let warningCount = filteredLogs.filter { $0.level == .warning }.count
        let errorCount = filteredLogs.filter { $0.level == .error }.count
        return AppLocalization.format(
            "Showing %lld logs • D:%lld I:%lld W:%lld E:%lld", filteredLogs.count, debugCount, infoCount, warningCount, errorCount)
    }
    var body: some View {
        List {
            Section(AppLocalization.string("Status")) {
                Text(store.pendingTransactionRefreshStatusText ?? AppLocalization.string("No refresh status yet")).font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                if let copiedNotice { Text(copiedNotice.text).font(.caption).foregroundStyle(.secondary) }
            }
            Section(AppLocalization.string("Filters")) {
                Picker(AppLocalization.string("Level"), selection: $selectedLevelFilter) {
                    ForEach(LogLevelFilter.allCases) { level in Text(level.title).tag(level) }
                }
                Picker(AppLocalization.string("Category"), selection: $selectedCategoryFilter) {
                    ForEach(availableCategories, id: \.self) { category in
                        let label: String = category == allCategoryFilter ? AppLocalization.string("All") : category
                        Text(label).tag(category)
                    }
                }
            }
            if filteredLogs.isEmpty {
                Section(AppLocalization.string("Events")) {
                    Text(AppLocalization.string("No operational events yet.")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(AppLocalization.string("Events")) {
                    ForEach(filteredLogs) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: event.level)).foregroundStyle(color(for: event.level))
                                Text(event.timestamp.formatted(date: .abbreviated, time: .standard)).font(.caption.bold()).foregroundStyle(
                                    .secondary)
                                Text(event.category).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6)
                                    .padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(event.message).font(.subheadline)
                            if let source = event.source, !source.isEmpty {
                                Text(AppLocalization.format("source: %@", source)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            if let chainName = event.chainName, !chainName.isEmpty {
                                Text(AppLocalization.format("chain: %@", chainName)).font(.caption.monospaced()).foregroundStyle(
                                    .secondary)
                            }
                            if let walletID = event.walletID {
                                Text(AppLocalization.format("wallet: %@", walletID)).font(.caption.monospaced()).foregroundStyle(
                                    .secondary
                                ).textSelection(.enabled)
                            }
                            if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                                Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if let metadata = event.metadata, !metadata.isEmpty {
                                Text(metadata).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Logs")).searchable(
            text: $searchText, prompt: AppLocalization.string("Search message, chain, tx hash, wallet")
        ).onAppear {
            rebuildLogPresentation()
        }.onChange(of: diagnosticsState.operationalLogsRevision) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedLevelFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedCategoryFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: searchText) { _, _ in
            rebuildLogPresentation()
        }.spectraTransientNotice($copiedNotice).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Copy")) {
                    UIPasteboard.general.string = store.exportOperationalLogsText(events: filteredLogs)
                    copiedNotice = SpectraTransientNotice(AppLocalization.format("Copied %lld log entries", filteredLogs.count))
                }.disabled(filteredLogs.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Clear"), role: .destructive) {
                    store.clearOperationalLogs()
                }.disabled(diagnosticsState.operationalLogs.isEmpty)
            }
        }
    }
    private func iconName(for level: AppState.OperationalLogEvent.Level) -> String {
        switch level {
        case .debug: return "ladybug.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    private func color(for level: AppState.OperationalLogEvent.Level) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
