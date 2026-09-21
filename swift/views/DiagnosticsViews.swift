import Foundation
import SwiftUI
struct DiagnosticsHubView: View {
    let store: AppState
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
            destinationSection(copy.chainsSectionTitle, destinations: chainDestinations)
        }.navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline).searchable(
            text: $searchText, prompt: copy.searchPrompt)
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
    @State private var copiedDiagnosticsNotice: SpectraTransientNotice?
    @State private var selectedBackendId: String = ""
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []
    /// Keypool state now lives in core, so it is loaded rather than read
    /// synchronously — see `.task` below.
    @State private var keypoolError: String?
    @State private var cachedKeypoolDiagnostics: [KeypoolDiagnostic] = []
    /// Operational events live in core now, so they load rather than read
    /// synchronously — same `.task` as the keypool rows.
    @State private var cachedOperationalEvents: [DiagnosticLog] = []
    private let customBackendId = "custom"
    private var chainDiagnosticsState: WalletChainDiagnosticsState { store.chainDiagnosticsState }
    private var displayChainTitle: String { store.selectedNetworkTitle(forFamilyName: chain.displayName) }
    private var diagnosticsLabel: String { displayChainTitle }
    /// The backends the catalog lists for this chain, first being the one core
    /// uses when the setting is empty.
    ///
    /// Was `MoneroBalanceService`: three catalog record ids, three display
    /// names and a default id written out in Swift, read by index — so a
    /// catalog with two backends crashed the screen on `[2]`.
    private var catalogBackends: [String] { AppEndpointDirectory.backends(for: chain.id) }
    private var backendChoices: [(id: String, title: String)] {
        catalogBackends.enumerated().map { index, url in
            let host = URL(string: url)?.host ?? url
            return (url, index == 0 ? AppLocalization.format("%@ (Default)", host) : host)
        } + [(customBackendId, AppLocalization.string("Custom URL"))]
    }
    /// Esplora bases are a Bitcoin-family catalog column; a chain with any has
    /// the custom-Esplora setting.
    private var hasEsploraBases: Bool { !AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainId: chain.id).isEmpty }

    /// Self-test and rescan actions, offered on the chains a rescan means
    /// something for — the ones whose addresses HD discovery walks.
    private var utxoActions: (selfTestTitle: String, rescanTitle: String, rescanInFlightTitle: String)? {
        guard chain.supportsDeepUTXODiscovery else { return nil }
        let ticker = chain.gasTokenSymbol
        return (
            AppLocalization.format("Run %@ Self-Tests", ticker),
            AppLocalization.format("Run %@ Rescan", ticker),
            AppLocalization.format("Rescanning %@...", ticker)
        )
    }

    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                Button(
                    isRunningHistory
                        ? AppLocalization.format("Running %@ History Diagnostics...", diagnosticsLabel)
                        : AppLocalization.format("Run %@ History Diagnostics", diagnosticsLabel)
                ) {
                    Task {
                        await runHistoryDiagnostics()
                    }
                }.disabled(isRunningHistory)
                Button(AppLocalization.format("Copy %@ Diagnostics JSON", diagnosticsLabel)) {
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
                        ? AppLocalization.format("Checking %@ Endpoints...", diagnosticsLabel)
                        : AppLocalization.format("Check %@ Endpoints", diagnosticsLabel)
                ) {
                    Task {
                        await runEndpointDiagnostics()
                    }
                }.disabled(isCheckingEndpoints)
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
            if chain.sendsThroughBackend { syncSelectedBackendIDFromStore() }
            rebuildCachedRows()
        }.task(id: chain.id) {
            do {
                cachedKeypoolDiagnostics = try await store.chainKeypoolDiagnostics(for: chain.displayName)
                keypoolError = nil
            } catch {
                cachedKeypoolDiagnostics = []
                keypoolError = error.localizedDescription
            }
            cachedOperationalEvents = await store.operationalEvents(for: chain.displayName)
        }.spectraTransientNotice($copiedDiagnosticsNotice).onChange(of: selectedBackendId) { _, newValue in
            guard chain.sendsThroughBackend, newValue != customBackendId else { return }
            // The first is what an empty setting already means.
            store.updateSetting(.moneroBackendBaseUrl(value: newValue == catalogBackends.first ? "" : newValue))
        }.onChange(of: store.appSettings.moneroBackendBaseUrl) { _, _ in
            guard chain.sendsThroughBackend else { return }
            syncSelectedBackendIDFromStore()
        }.onChange(of: historyLastUpdatedAt) { _, _ in
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
    private func configuredEndpointsForCurrentChain() -> [String] {
        let name = chain.displayName
        if hasEsploraBases {
            let custom = parseBitcoinEsploraEndpoints(raw: store.appSettings.bitcoinEsploraEndpoints)
            return custom.isEmpty
                ? AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainId: store.selectedChainId(forFamily: chain.id))
                : custom
        }
        if chain.sendsThroughBackend {
            let stored = store.appSettings.moneroBackendBaseUrl
            return stored.isEmpty ? catalogBackends : [stored]
        }
        guard chain.isEVM else { return AppEndpointDirectory.serviceEndpoints(for: store.selectedChainId(forFamily: chain.id)) }
        let custom = store.rpcEndpoint(forChain: name)
        var endpoints = custom.isEmpty ? [] : [custom]
        for endpoint in AppEndpointDirectory.evmRPCEndpoints(for: store.selectedChainId(forFamily: chain.id)) where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        return endpoints
    }
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
            SettingTextField(
                title: AppLocalization.string("Custom Esplora endpoints (comma-separated, optional)"),
                value: store.appSettings.bitcoinEsploraEndpoints, endpoint: .bitcoinEsploraList
            ) { store.updateSetting(.bitcoinEsploraEndpoints(value: $0)) }
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Text(copy.bitcoinEsploraHint).font(.caption).foregroundStyle(.secondary)
        }
    }
    /// The custom RPC, for every EVM chain.
    ///
    /// Core has kept a custom RPC per chain since `rpc_endpoint_by_chain`
    /// replaced `ethereum_rpc_endpoint`, and this screen already listed a
    /// custom RPC first for any EVM chain that had one — but only Ethereum's
    /// screen offered a way to set it.
    @ViewBuilder
    private var rpcSettingsSection: some View {
        Section(AppLocalization.format("%@ RPC", chain.displayName)) {
            SettingTextField(
                title: AppLocalization.format("%@ RPC URL (Optional)", chain.displayName),
                value: store.rpcEndpoint(forChain: chain.displayName), endpoint: .evmRpc
            ) { store.setRPCEndpoint($0, forChain: chain.displayName) }
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Text(copy.customRPCNote).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var backendSettingsSection: some View {
        Section(AppLocalization.format("%@ Backend", chain.displayName)) {
            Picker(AppLocalization.string("Trusted Backend"), selection: $selectedBackendId) {
                ForEach(backendChoices, id: \.id) { choice in Text(choice.title).tag(choice.id) }
            }
            if selectedBackendId == customBackendId {
                SettingTextField(
                    title: AppLocalization.format("%@ Backend URL (Optional)", chain.displayName),
                    value: store.appSettings.moneroBackendBaseUrl, endpoint: .moneroBackend
                ) { store.updateSetting(.moneroBackendBaseUrl(value: $0)) }
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            } else {
                Text(selectedBackendId.isEmpty ? (catalogBackends.first ?? "") : selectedBackendId)
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            Text(copy.backendNote).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var chainSpecificSections: some View {
        // Which settings a chain has is what the registry and the catalog say
        // about it, not which chain it is.
        if hasEsploraBases { esploraSettingsSection }
        if chain.isEVM { rpcSettingsSection }
        if chain.sendsThroughBackend { backendSettingsSection }
        // Core provides a self-test suite for every chain in the catalog.
        Section(AppLocalization.string("Chain Actions")) {
            Button(isRunningChainSelfTests ? AppLocalization.string("Running Self-Tests...") : chainSelfTestTitle) {
                Task { await runChainSelfTests() }
            }.disabled(isRunningChainSelfTests)
            if supportsUTXOChainActions {
                Button(isRunningChainRescan ? chainRescanInFlightTitle : chainRescanTitle) {
                    Task {
                        await runChainRescan()
                    }
                }.disabled(isRunningChainRescan)
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
    private func syncSelectedBackendIDFromStore() {
        let trimmed = store.appSettings.moneroBackendBaseUrl
        if trimmed.isEmpty {
            selectedBackendId = catalogBackends.first ?? customBackendId
        } else {
            selectedBackendId =
                catalogBackends.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? customBackendId
        }
    }
    private var supportsUTXOChainActions: Bool { utxoActions != nil }
    private var isRunningChainSelfTests: Bool { store.selfTests(for: chain.displayName).isRunning }
    private var isRunningChainRescan: Bool { store[rescanFor: chain.displayName].isRunning }
    private var chainSelfTestTitle: String {
        utxoActions?.selfTestTitle ?? AppLocalization.string("Run Self-Tests")
    }
    private var chainRescanTitle: String {
        utxoActions?.rescanTitle ?? AppLocalization.string("Run Rescan")
    }
    private var chainRescanInFlightTitle: String {
        utxoActions?.rescanInFlightTitle ?? AppLocalization.string("Rescanning...")
    }
    private func runChainSelfTests() async { await store.runSelfTests(for: chain.displayName) }
    private func runChainRescan() async { await store.runUTXORescan(chainName: chain.displayName) }
}
private func formatCopy(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
