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
    /// Every mainnet gets a screen. It used to be the twenty-four a Swift enum
    /// happened to list; the drivers behind the screen are generic over the
    /// chain name, so the other twenty-two worked all along and were simply
    /// unreachable.
    private var chainDestinations: [DiagnosticsDestination] {
        Chain.mainnets.map { chain in
            DiagnosticsDestination(
                id: chain.id,
                title: store.displayChainTitle(for: chain.displayName) + " Diagnostics",
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
///
/// This was a twenty-four-row table of ten closures each — rows that differed
/// only in the chain's display name and in which of five history dictionaries
/// they read. Which of the five is `Chain.diagnosticsShape`, a registry fact,
/// so the table is a function of the chain instead of a copy of the chain list.
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
    /// Two five-way switches on `diagnosticsShape` stood here, reaching into
    /// whichever of core's five registries matched the shape to take `.count`
    /// and `.sourceUsed` — the two fields every shape has. Core knows the
    /// shape and owns the records, so it answers with the two numbers and no
    /// diagnostics record crosses the boundary to be counted.
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
    @State private var copiedDiagnosticsNotice: String?
    @State private var selectedMoneroBackendID: String = MoneroBalanceService.defaultBackendID
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []
    /// Keypool state now lives in core, so it is loaded rather than read
    /// synchronously — see `.task` below.
    @State private var cachedKeypoolDiagnostics: [AppState.ChainKeypoolDiagnostic] = []
    /// Operational events live in core now, so they load rather than read
    /// synchronously — same `.task` as the keypool rows.
    @State private var cachedOperationalEvents: [ChainOperationalEvent] = []
    private let moneroCustomBackendID = "custom"
    private var chainDiagnosticsState: WalletChainDiagnosticsState { store.chainDiagnosticsState }
    private var displayChainTitle: String { store.displayChainTitle(for: chain.displayName) }
    private var diagnosticsLabel: String { displayChainTitle }
    private var moneroBackendChoices: [(id: String, title: String)] {
        let trusted = MoneroBalanceService.trustedBackends.map { ($0.id, $0.displayName) }
        return trusted + [(moneroCustomBackendID, AppLocalization.string("Custom URL"))]
    }
    private var selectedTrustedMoneroBackend: MoneroBalanceService.TrustedBackend? {
        MoneroBalanceService.trustedBackends.first(where: { $0.id == selectedMoneroBackendID })
    }

    /// Self-test and rescan actions, offered on the chains whose diagnostics
    /// are UTXO-shaped. Was a five-row table restating each chain's name and
    /// ticker; both are catalog columns.
    private var utxoActions: (selfTestTitle: String, rescanTitle: String, rescanInFlightTitle: String)? {
        guard chain.diagnosticsShape == .utxo else { return nil }
        let ticker = chain.symbol
        return (
            AppLocalization.format("Run %@ Self-Tests", ticker),
            AppLocalization.format("Run %@ Rescan", ticker),
            AppLocalization.format("Rescanning %@...", ticker)
        )
    }

    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                if chain == .ethereum {
                    Button(
                        store.selfTests(for: "Ethereum").isRunning
                            ? AppLocalization.format("Running %@ Diagnostics...", diagnosticsLabel)
                            : AppLocalization.format("Run %@ Diagnostics", diagnosticsLabel)
                    ) {
                        Task {
                            await store.runEthereumSelfTests()
                        }
                    }.disabled(store.selfTests(for: "Ethereum").isRunning)
                }
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
                        copiedDiagnosticsNotice = AppLocalization.format("%@ diagnostics JSON copied.", diagnosticsLabel)
                    } else {
                        copiedDiagnosticsNotice = AppLocalization.format("No %@ diagnostics available to copy.", diagnosticsLabel)
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
                if let copiedDiagnosticsNotice { Text(copiedDiagnosticsNotice).font(.caption).foregroundStyle(.secondary) }
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
        }.navigationTitle(displayChainTitle + " Diagnostics").onAppear {
            if chain == .monero { syncSelectedMoneroBackendIDFromStore() }
            rebuildCachedRows()
        }.task(id: chain.id) {
            cachedKeypoolDiagnostics = await store.chainKeypoolDiagnostics(for: chain.displayName)
            cachedOperationalEvents = await store.operationalEvents(for: chain.displayName)
        }.onChange(of: copiedDiagnosticsNotice) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copiedDiagnosticsNotice = nil
            }
        }.onChange(of: selectedMoneroBackendID) { _, newValue in
            guard chain == .monero else { return }
            if newValue == moneroCustomBackendID { return }
            if newValue == MoneroBalanceService.defaultBackendID {
                store.moneroBackendBaseURL = ""
                return
            }
            if let trusted = MoneroBalanceService.trustedBackends.first(where: { $0.id == newValue }) {
                store.moneroBackendBaseURL = trusted.baseURL
            }
        }.onChange(of: store.moneroBackendBaseURL) { _, _ in
            guard chain == .monero else { return }
            syncSelectedMoneroBackendIDFromStore()
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
            StandardEndpointRow(endpoint: $0, reachable: nil, detail: "Not checked yet")
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
    ///
    /// Was a twenty-four case switch whose arms were mostly
    /// `XBalanceService.endpointCatalog()` — one-line shims that do nothing but
    /// restate the chain's own name to `AppEndpointDirectory` — and
    /// `EVMChainContext.x.defaultRPCEndpoints`, which does the same. What is
    /// genuinely per-chain is the user-configured override, and there are three.
    private func configuredEndpointsForCurrentChain() -> [String] {
        let name = chain.displayName
        switch chain {
        case .bitcoin:
            let custom = store.bitcoinEsploraEndpoints
                .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return custom.isEmpty
                ? AppEndpointDirectory.bitcoinEsploraBaseURLs(
                    forChainID: store.networkChainID(forFamily: "bitcoin"))
                : custom
        case .monero:
            let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [MoneroBalanceService.defaultPublicBackend.baseURL] : [trimmed]
        case .ethereum:
            let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            var endpoints = custom.isEmpty ? [] : [custom]
            for endpoint in evmEndpoints(for: name) where !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
            return endpoints
        default:
            return chain.isEVM
                ? evmEndpoints(for: name) : AppEndpointDirectory.settingsEndpoints(for: name)
        }
    }
    /// An EVM chain's RPC list, plus whatever explorer endpoints the catalog
    /// supplements it with. Only Ethereum and BNB Chain used to get the
    /// supplement; for every other chain the list is empty, so asking for all
    /// of them costs nothing and stops the next chain that has one from
    /// needing a case here.
    private func evmEndpoints(for name: String) -> [String] {
        var endpoints = AppEndpointDirectory.evmRPCEndpoints(for: name)
        for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: name)
        where !endpoints.contains(endpoint) {
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
    @ViewBuilder
    private var bitcoinSettingsSection: some View {
        Section(AppLocalization.string("Bitcoin Settings")) {
            Picker(
                AppLocalization.string("Send Fee Priority"),
                selection: Binding(
                    get: { store.feePriorityOption(for: "Bitcoin") },
                    set: { store.setFeePriorityOption($0, for: "Bitcoin") })
            ) {
                ForEach(ChainFeePriorityOption.allCases) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }.pickerStyle(.segmented)
            TextField(
                AppLocalization.string("Custom Esplora endpoints (comma-separated, optional)"),
                text: $store.bitcoinEsploraEndpoints
            ).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            if let bitcoinEsploraEndpointsValidationError = store.bitcoinEsploraEndpointsValidationError {
                Text(bitcoinEsploraEndpointsValidationError).font(.caption).foregroundStyle(.red)
            } else {
                Text(copy.bitcoinEsploraHint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder
    private var ethereumSettingsSections: some View {
        Section(AppLocalization.string("Ethereum RPC")) {
            TextField(AppLocalization.string("Ethereum RPC URL (Optional)"), text: $store.ethereumRPCEndpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Text(copy.ethereumRPCNote).font(.caption).foregroundStyle(.secondary)
            if let ethereumRPCEndpointValidationError = store.ethereumRPCEndpointValidationError {
                Text(ethereumRPCEndpointValidationError).font(.caption).foregroundStyle(.red)
            }
        }
        Section(AppLocalization.string("Etherscan (Optional)")) {
            TextField(AppLocalization.string("Etherscan API Key"), text: $store.etherscanAPIKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(copy.etherscanNote).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var moneroSettingsSection: some View {
        Section(AppLocalization.string("Monero Backend")) {
            Picker(AppLocalization.string("Trusted Backend"), selection: $selectedMoneroBackendID) {
                ForEach(moneroBackendChoices, id: \.id) { choice in Text(choice.title).tag(choice.id) }
            }
            if selectedMoneroBackendID == moneroCustomBackendID {
                TextField(AppLocalization.string("Monero Backend URL (Optional)"), text: $store.moneroBackendBaseURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            } else {
                Text(selectedTrustedMoneroBackend?.baseURL ?? MoneroBalanceService.defaultPublicBackend.baseURL)
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            if let moneroBackendBaseURLValidationError = store.moneroBackendBaseURLValidationError {
                Text(moneroBackendBaseURLValidationError).font(.caption).foregroundStyle(.red)
            } else {
                Text(copy.moneroBackendNote).font(.caption).foregroundStyle(.secondary)
            }
            TextField(AppLocalization.string("Monero Backend API Key (Optional)"), text: $store.moneroBackendAPIKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(copy.moneroAPIKeyNote).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var chainSpecificSections: some View {
        switch chain {
        case .bitcoin: bitcoinSettingsSection
        case .ethereum: ethereumSettingsSections
        case .monero: moneroSettingsSection
        default: EmptyView()
        }
        if supportsUTXOChainActions {
            Section(AppLocalization.string("Chain Actions")) {
                Button(isRunningChainSelfTests ? AppLocalization.string("Running Self-Tests...") : chainSelfTestTitle) {
                    runChainSelfTests()
                }.disabled(isRunningChainSelfTests)
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
                ForEach(events.prefix(20)) { event in
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
            if diagnostics.isEmpty {
                Text(AppLocalization.string("No owned-address management state recorded yet.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.walletName).font(.subheadline.weight(.semibold))
                        Text(AppLocalization.format("Next receive index: %lld", Int(item.nextExternalIndex))).font(.caption).foregroundStyle(.secondary)
                        Text(AppLocalization.format("Next change index: %lld", Int(item.nextChangeIndex))).font(.caption).foregroundStyle(.secondary)
                        if let reservedReceiveIndex = item.reservedReceiveIndex {
                            Text(AppLocalization.format("Reserved receive index: %lld", Int(reservedReceiveIndex))).font(.caption).foregroundStyle(.secondary)
                        }
                        if let reservedReceivePath = item.reservedReceivePath, !reservedReceivePath.isEmpty {
                            Text(reservedReceivePath).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let reservedReceiveAddress = item.reservedReceiveAddress, !reservedReceiveAddress.isEmpty {
                            Text(reservedReceiveAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
    }
    private func syncSelectedMoneroBackendIDFromStore() {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectedMoneroBackendID = MoneroBalanceService.defaultBackendID
            return
        }
        if let trusted = MoneroBalanceService.trustedBackends.first(where: { $0.baseURL.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedMoneroBackendID = trusted.id
            return
        }
        selectedMoneroBackendID = moneroCustomBackendID
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
    private func runChainSelfTests() { store.runSelfTests(for: chain.displayName) }
    private func runChainRescan() async { await store.runUTXORescan(chainName: chain.displayName) }
}
private func formatCopy(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
