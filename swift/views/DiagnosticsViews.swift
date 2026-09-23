import Foundation
import SwiftUI
import UniformTypeIdentifiers
struct DiagnosticsHubView: View {
    let store: AppState
    @State private var isCheckingAllEndpoints = false
    @State private var diagnosticsNotice: String?
    @State private var isShowingDiagnosticsImporter = false
    @State private var isShowingDiagnosticsExportsBrowser = false
    @State private var lastExportedDiagnosticsURL: URL?
    @State private var searchText: String = ""
    private let copy = DiagnosticsContentCopy.current
    private struct DiagnosticsDestination: Identifiable {
        let id: String
        let title: String
        let keywords: [String]
        let chain: Chain
    }
    /// Every mainnet has a diagnostics screen.
    private var chainDestinations: [DiagnosticsDestination] {
        Chain.mainnets.map { chain in
            DiagnosticsDestination(
                id: chain.id,
                title: AppLocalization.format("%@ Diagnostics", store.selectedNetworkTitle(forFamilyName: chain.displayName)),
                keywords: chain.searchKeywords, chain: chain)
        }
    }
    private func filteredDestinations(_ destinations: [DiagnosticsDestination]) -> [DiagnosticsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return destinations }
        return destinations.filter { destination in
            destination.title.localizedCaseInsensitiveContains(query)
                || destination.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    @ViewBuilder
    private func destinationSection(_ title: String, destinations: [DiagnosticsDestination]) -> some View {
        Section(title) {
            ForEach(filteredDestinations(destinations)) { destination in
                NavigationLink {
                    StandardChainDiagnosticsView(store: store, chain: destination.chain)
                } label: {
                    Text(destination.title)
                }
            }
        }
    }
    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                Button(AppLocalization.string(isCheckingAllEndpoints ? "Running Diagnostics..." : "Run All Endpoint Checks")) {
                    isCheckingAllEndpoints = true
                    Task {
                        for chain in Chain.mainnets { await store.runEndpointDiagnostics(for: chain) }
                        isCheckingAllEndpoints = false
                        diagnosticsNotice = AppLocalization.string("Endpoint checks completed.")
                    }
                }.disabled(isCheckingAllEndpoints)
            }
            destinationSection(copy.chainsSectionTitle, destinations: chainDestinations)
            Section(AppLocalization.string("Diagnostics Bundle")) {
                Button(AppLocalization.string("Export Diagnostics Bundle")) {
                    do {
                        let url = try store.exportDiagnosticsBundle()
                        lastExportedDiagnosticsURL = url
                        diagnosticsNotice = AppLocalization.format("Diagnostics exported to %@", url.lastPathComponent)
                    } catch {
                        diagnosticsNotice = AppLocalization.format("Export failed: %@", error.localizedDescription)
                    }
                }
                Button(AppLocalization.string("Past Exports")) {
                    isShowingDiagnosticsExportsBrowser = true
                }
                if let lastExportedDiagnosticsURL {
                    ShareLink(item: lastExportedDiagnosticsURL) {
                        Label(AppLocalization.string("Share Last Export"), systemImage: "square.and.arrow.up")
                    }
                }
                Button(AppLocalization.string("Import Diagnostics Bundle")) {
                    isShowingDiagnosticsImporter = true
                }
            }
            if let diagnosticsNotice {
                Section {
                    Text(diagnosticsNotice).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline).searchable(
            text: $searchText, prompt: copy.searchPrompt).sheet(isPresented: $isShowingDiagnosticsExportsBrowser) {
            DiagnosticsExportsBrowserView(model: .live(store: store))
        }.fileImporter(
            isPresented: $isShowingDiagnosticsImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileURL = try result.get().first else { return }
                let didAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { fileURL.stopAccessingSecurityScopedResource() }
                }
                let payload = try store.importDiagnosticsBundle(from: fileURL)
                diagnosticsNotice = AppLocalization.format(
                    "Imported diagnostics bundle (%@).", payload.generatedAtDate.formatted(date: .abbreviated, time: .shortened))
            } catch {
                diagnosticsNotice = AppLocalization.format("Import failed: %@", error.localizedDescription)
            }
        }
    }
}
/// How one chain's diagnostics screen reads store state.
struct StandardChainDiagnosticsDispatch {
    let chain: Chain
    private var name: String { chain.displayName }

    @MainActor func isRunningHistory(_ store: AppState) -> Bool {
        store[historyRunFor: name].isRunning
    }
    @MainActor func isCheckingEndpoints(_ store: AppState) -> Bool {
        store[endpointHealthFor: name].isChecking
    }
    @MainActor func diagnosticsJSON(_ store: AppState) -> String? {
        store.diagnosticsJSON(for: name)
    }
    @MainActor func historyLastUpdatedAt(_ store: AppState) -> Date? {
        store[historyRunFor: name].lastUpdatedAt
    }
    @MainActor func endpointLastUpdatedAt(_ store: AppState) -> Date? {
        store[endpointHealthFor: name].lastUpdatedAt
    }
    @MainActor func endpointResults(_ store: AppState)
        -> [(endpoint: String, reachable: Bool?, detail: String)]
    {
        store[endpointHealthFor: name].results.map { ($0.endpoint, $0.reachable, $0.detail) }
    }
    /// How many wallets reported, and which source each used.
    ///
    /// Core knows the shape and owns the records, so it answers with the two
    /// numbers and no diagnostics record crosses the boundary to be counted.
    ///
    /// `revision` is unused, and is the point: reading it makes the summary
    /// depend on the observable that changes when a run writes, so the screen
    /// still refreshes when one finishes.
    @MainActor func historySummary(_ store: AppState) -> DiagnosticsRunSummary {
        _ = store.chainDiagnosticsState.diagnosticsRevision
        return diagnosticsRunSummary(chainName: name)
    }
    func runHistoryDiagnostics(_ store: AppState) async {
        await store.runHistoryDiagnostics(for: chain)
    }
    func runEndpointDiagnostics(_ store: AppState) async {
        await store.runEndpointDiagnostics(for: chain)
    }
}
extension Chain {
    var dispatch: StandardChainDiagnosticsDispatch { StandardChainDiagnosticsDispatch(chain: self) }
}
private struct StandardEndpointRow: Identifiable {
    let id = UUID()
    let endpoint: String
    let reachable: Bool?
    let detail: String
}
private struct StandardHistorySourceRow: Identifiable {
    let source: String
    let count: Int
    var id: String { source }
}
struct StandardChainDiagnosticsView: View {
    @Bindable var store: AppState
    let chain: Chain
    private let copy = DiagnosticsContentCopy.current
    @State private var isRefreshing = false
    @State private var refreshNotice: String?
    @State private var copiedDiagnosticsNotice: SpectraTransientNotice?
    @State private var configuredEndpoints: [String] = []
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []
    /// Keypool state now lives in core, so it is loaded rather than read
    /// synchronously — see `.task` below.
    @State private var keypoolError: String?
    @State private var cachedKeypoolDiagnostics: [KeypoolDiagnostic] = []
    /// Operational events live in core now, so they load rather than read
    /// synchronously — same `.task` as the keypool rows.
    @State private var cachedOperationalEvents: [DiagnosticLog] = []
    private var chainDiagnosticsState: WalletChainDiagnosticsState { store.chainDiagnosticsState }
    private var displayChainTitle: String { store.selectedNetworkTitle(forFamilyName: chain.displayName) }
    private var diagnosticsLabel: String { displayChainTitle }
    /// Esplora bases are a Bitcoin-family catalog column; a chain with any has
    /// the custom-Esplora setting.
    private var hasEsploraBases: Bool { !AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainId: chain.id).isEmpty }

    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                Button(AppLocalization.string(isRefreshing ? "Refreshing..." : "Refresh Balances and History")) {
                    isRefreshing = true
                    refreshNotice = nil
                    Task {
                        let succeeded = await store.performUserInitiatedRefresh(forChain: chain.displayName)
                        isRefreshing = false
                        refreshNotice = refreshOutcomeMessage(succeeded: succeeded)
                    }
                }.disabled(isRefreshing)
                if let refreshNotice {
                    Text(refreshNotice).font(.caption).foregroundStyle(.secondary)
                }
                Button(
                    isRunningHistory
                        ? AppLocalization.string("Running History Diagnostics...")
                        : AppLocalization.string("Run History Diagnostics")
                ) {
                    Task {
                        await runHistoryDiagnostics()
                    }
                }.disabled(isRunningHistory)
                Button(AppLocalization.string("Copy Diagnostics JSON")) {
                    if let payload = diagnosticsJSON {
                        UIPasteboard.general.string = payload
                        copiedDiagnosticsNotice = SpectraTransientNotice(
                            AppLocalization.format("%@ diagnostics JSON copied.", diagnosticsLabel))
                    } else {
                        copiedDiagnosticsNotice = SpectraTransientNotice(
                            AppLocalization.format("No %@ diagnostics available to copy.", diagnosticsLabel))
                    }
                }
                Button(
                    isCheckingEndpoints
                        ? AppLocalization.string("Checking Endpoints...")
                        : AppLocalization.string("Check Endpoints")
                ) {
                    Task {
                        await runEndpointDiagnostics()
                    }
                }.disabled(isCheckingEndpoints)
                Button(isRunningChainSelfTests ? AppLocalization.string("Running Self-Tests...") : AppLocalization.string("Run Self-Tests")) {
                    Task { await runChainSelfTests() }
                }.disabled(isRunningChainSelfTests)
                if chain.supportsDeepUTXODiscovery {
                    Button(AppLocalization.string(isRunningChainRescan ? "Rescanning..." : "Run Rescan")) {
                        Task {
                            await runChainRescan()
                        }
                    }.disabled(isRunningChainRescan)
                }
                if let copiedDiagnosticsNotice {
                    Text(copiedDiagnosticsNotice.text).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(copy.statusSectionTitle) {
                if let updatedAt = historyLastUpdatedAt {
                    Text(formatCopy(copy.lastHistoryRunFormat, updatedAt.formatted(date: .abbreviated, time: .shortened))).font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(copy.historyNotRunYet).font(.caption).foregroundStyle(.secondary)
                }
                Text(formatCopy(copy.walletDiagnosticsCoveredFormat, String(historyWalletCount))).font(.caption).foregroundStyle(.secondary)
                if let primarySource = historySourceRows.first {
                    Text(formatCopy(copy.mostUsedHistorySourceFormat, primarySource.source, String(primarySource.count))).font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let updatedAt = endpointLastUpdatedAt {
                    let formattedUpdatedAt = updatedAt.formatted(date: .abbreviated, time: .shortened)
                    Text(formatCopy(copy.lastEndpointCheckFormat, formattedUpdatedAt)).font(.caption).foregroundStyle(.secondary)
                }
                if !endpointRows.isEmpty {
                    let reachableCount = endpointRows.filter { $0.reachable == true }.count
                    Text(formatCopy(copy.endpointHealthFormat, String(reachableCount), String(endpointRows.count))).font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(formatCopy(copy.historySourcesSectionTitleFormat, diagnosticsLabel)) {
                if historySourceRows.isEmpty {
                    Text(copy.noHistoryTelemetryYet).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(historySourceRows) { item in
                        HStack {
                            Text(item.source).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(AppLocalization.format("diagnostics.countOnly", item.count)).font(.caption.monospacedDigit()).foregroundStyle(
                                .secondary)
                        }
                    }
                }
            }
            Section(formatCopy(copy.endpointReachabilitySectionTitleFormat, diagnosticsLabel)) {
                if endpointRows.isEmpty {
                    Text(copy.noEndpointChecksYet).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(endpointRows) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: endpointStatusIconName(for: result)).foregroundStyle(endpointStatusColor(for: result))
                                Text(result.endpoint).font(.subheadline.weight(.semibold))
                            }
                            Text(result.detail).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }
                }
            }
            chainSpecificSections
        }.navigationTitle(AppLocalization.format("%@ Diagnostics", displayChainTitle)).onAppear {
            rebuildCachedRows()
        }.task(id: chain.id) {
            do {
                let network = store.selectedChainId(forFamily: chain.id)
                configuredEndpoints = try await store.bridge.endpointDirectory()
                    .filter { $0.record.chainId == network && !$0.apiName.isEmpty }.map(\.record.endpoint)
                rebuildEndpointRows()
            } catch { keypoolError = error.localizedDescription }

            do {
                cachedKeypoolDiagnostics = try await store.chainKeypoolDiagnostics(for: chain.displayName)
                keypoolError = nil
            } catch {
                cachedKeypoolDiagnostics = []
                keypoolError = error.localizedDescription
            }
            cachedOperationalEvents = await store.operationalEvents(for: chain.displayName)
        }.spectraTransientNotice($copiedDiagnosticsNotice).onChange(of: historyLastUpdatedAt) { _, _ in
            rebuildHistorySourceRows()
        }.onChange(of: historyWalletCount) { _, _ in
            rebuildHistorySourceRows()
        }.onChange(of: endpointLastUpdatedAt) { _, _ in
            rebuildEndpointRows()
        }
    }
    private var isRunningHistory: Bool { chain.dispatch.isRunningHistory(store) }
    private var isCheckingEndpoints: Bool { chain.dispatch.isCheckingEndpoints(store) }
    private var diagnosticsJSON: String? { chain.dispatch.diagnosticsJSON(store) }
    private var historyLastUpdatedAt: Date? { chain.dispatch.historyLastUpdatedAt(store) }
    private var historyWalletCount: Int { Int(chain.dispatch.historySummary(store).walletCount) }
    private var endpointLastUpdatedAt: Date? { chain.dispatch.endpointLastUpdatedAt(store) }
    private var endpointRows: [StandardEndpointRow] { cachedEndpointRows }
    private var historySourceRows: [StandardHistorySourceRow] { cachedHistorySourceRows }
    private func rebuildCachedRows() {
        rebuildEndpointRows()
        rebuildHistorySourceRows()
    }
    private func rebuildEndpointRows() {
        let fallbackRows = configuredEndpointsForCurrentChain().map {
            StandardEndpointRow(endpoint: $0, reachable: nil, detail: AppLocalization.string("Not checked yet"))
        }
        let raw = chain.dispatch.endpointResults(store)
        cachedEndpointRows =
            raw.isEmpty ? fallbackRows : raw.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }
    }
    private func endpointStatusIconName(for row: StandardEndpointRow) -> String {
        switch row.reachable {
        case true: return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        case nil: return "clock.badge.questionmark"
        }
    }
    private func endpointStatusColor(for row: StandardEndpointRow) -> Color {
        switch row.reachable {
        case true: return .green
        case false: return .red
        case nil: return .secondary
        }
    }
    /// The endpoints this chain would actually use, as the screen lists them.
    private func configuredEndpointsForCurrentChain() -> [String] { configuredEndpoints }
    private func rebuildHistorySourceRows() {
        let sources = chain.dispatch.historySummary(store).sources
        var counts: [String: Int] = [:]
        for source in sources {
            let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            counts[normalized, default: 0] += 1
        }
        cachedHistorySourceRows = counts.map { StandardHistorySourceRow(source: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.source < rhs.source
            }
    }
    private func runHistoryDiagnostics() async { await chain.dispatch.runHistoryDiagnostics(store) }
    private func runEndpointDiagnostics() async { await chain.dispatch.runEndpointDiagnostics(store) }
    /// Fee priority and custom Esplora bases, for a chain the catalog gives
    /// Esplora bases to.
    @ViewBuilder
    private var esploraSettingsSection: some View {
        Section(AppLocalization.format("%@ Settings", chain.displayName)) {
            Picker(
                AppLocalization.string("Send Fee Priority"),
                selection: Binding(
                    get: { store.feePriority(forChain: chain.displayName) },
                    set: { store.setFeePriority($0, forChain: chain.displayName) })
            ) {
                ForEach(FeePriority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }.pickerStyle(.segmented)
        }
    }
    @ViewBuilder
    private var chainSpecificSections: some View {
        // Which settings a chain has is what the registry and the catalog say
        // about it, not which chain it is.
        if hasEsploraBases { esploraSettingsSection }
        Section {
            NavigationLink { EndpointCatalogSettingsView(store: store) } label: {
                Text(EndpointsContentCopy.current.navigationTitle)
            }
        }
        Section(AppLocalization.string("Operational Events")) {
            let events = cachedOperationalEvents
            if events.isEmpty {
                Text(AppLocalization.string("No operational events recorded yet.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(20)) { log in
                    let event = log.input
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message).font(.subheadline)
                        Text(event.level.displayName).font(.caption.weight(.semibold)).foregroundStyle(
                            event.level == .error ? .red : (event.level == .warning ? .orange : .secondary))
                        if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                            Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        Section(AppLocalization.string("Owned Address Management")) {
            let diagnostics = cachedKeypoolDiagnostics
            if let keypoolError {
                Text(keypoolError).font(.caption).foregroundStyle(.red)
            } else if diagnostics.isEmpty {
                Text(AppLocalization.string("No owned-address management state recorded yet.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.walletName).font(.subheadline.weight(.semibold))
                        Text(AppLocalization.format("Next receive index: %lld", Int(item.keypool.nextExternalIndex))).font(.caption).foregroundStyle(.secondary)
                        Text(AppLocalization.format("Next change index: %lld", Int(item.keypool.nextChangeIndex))).font(.caption).foregroundStyle(.secondary)
                        if let reservedReceiveIndex = item.keypool.reservedReceiveIndex {
                            Text(AppLocalization.format("Reserved receive index: %lld", Int(reservedReceiveIndex))).font(.caption).foregroundStyle(.secondary)
                        }
                        if let reservedReceivePath = item.reservedReceive?.derivationPath, !reservedReceivePath.isEmpty {
                            Text(reservedReceivePath).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let reservedReceiveAddress = item.reservedReceive?.address, !reservedReceiveAddress.isEmpty {
                            Text(reservedReceiveAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
    }
    private var isRunningChainSelfTests: Bool { store.selfTests(for: chain.displayName).isRunning }
    private var isRunningChainRescan: Bool { store[rescanFor: chain.displayName].isRunning }
    private func runChainSelfTests() async { await store.runSelfTests(for: chain.displayName) }
    private func runChainRescan() async { await store.runUTXORescan(chainName: chain.displayName) }
}
private func formatCopy(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
