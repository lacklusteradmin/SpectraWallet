import Foundation
import SwiftUI
import Combine
struct DiagnosticsHubView: View {
    let store: AppState
    @State private var searchText: String = ""
    private let copy = DiagnosticsContentCopy.current
    private struct DiagnosticsDestination: Identifiable {
        let id: String
        let title: String
        let keywords: [String]
        let makeView: () -> AnyView
    }
    private var chainDestinations: [DiagnosticsDestination] {
        AppEndpointDirectory.diagnosticsChains.compactMap { descriptor in
            guard let chain = StandardDiagnosticsChain(chainID: descriptor.id) else { return nil }
            let title = store.displayChainTitle(for: descriptor.chainName) + " Diagnostics"
            return DiagnosticsDestination(
                id: title, title: title, keywords: descriptor.searchKeywords, makeView: { AnyView(StandardChainDiagnosticsView(store: store, chain: chain)) }
            )
        }}
    private func filteredDestinations(_ destinations: [DiagnosticsDestination]) -> [DiagnosticsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return destinations }
        return destinations.filter { destination in
            destination.title.localizedCaseInsensitiveContains(query)
                || destination.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }}
    @ViewBuilder
    private func destinationSection(_ title: String, destinations: [DiagnosticsDestination]) -> some View {
        Section(title) {
            ForEach(filteredDestinations(destinations)) { destination in
                NavigationLink {
                    destination.makeView()
                } label: { Text(destination.title) }}}}
    var body: some View {
        Form {
            destinationSection(copy.chainsSectionTitle, destinations: chainDestinations)
        }.navigationTitle(copy.navigationTitle).navigationBarTitleDisplayMode(.inline).searchable(text: $searchText, prompt: copy.searchPrompt)
    }
}
enum StandardDiagnosticsChain: Hashable, CaseIterable {
    case dogecoin
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    case tron
    case solana
    case cardano
    case xrp
    case stellar
    case monero
    case sui
    case aptos
    case ton
    case icp
    case near
    case polkadot
    var chainID: AppChainID {
        switch self {
        case .dogecoin: return .dogecoin
        case .bitcoin: return .bitcoin
        case .bitcoinCash: return .bitcoinCash
        case .bitcoinSV: return .bitcoinSV
        case .litecoin: return .litecoin
        case .ethereum: return .ethereum
        case .ethereumClassic: return .ethereumClassic
        case .arbitrum: return .arbitrum
        case .optimism: return .optimism
        case .bnb: return .bnb
        case .avalanche: return .avalanche
        case .hyperliquid: return .hyperliquid
        case .tron: return .tron
        case .solana: return .solana
        case .cardano: return .cardano
        case .xrp: return .xrp
        case .stellar: return .stellar
        case .monero: return .monero
        case .sui: return .sui
        case .aptos: return .aptos
        case .ton: return .ton
        case .icp: return .icp
        case .near: return .near
        case .polkadot: return .polkadot
        }}
    init?(chainID: AppChainID) {
        switch chainID {
        case .dogecoin: self = .dogecoin
        case .bitcoin: self = .bitcoin
        case .bitcoinCash: self = .bitcoinCash
        case .bitcoinSV: self = .bitcoinSV
        case .litecoin: self = .litecoin
        case .ethereum: self = .ethereum
        case .ethereumClassic: self = .ethereumClassic
        case .arbitrum: self = .arbitrum
        case .optimism: self = .optimism
        case .bnb: self = .bnb
        case .avalanche: self = .avalanche
        case .hyperliquid: self = .hyperliquid
        case .tron: self = .tron
        case .solana: self = .solana
        case .cardano: self = .cardano
        case .xrp: self = .xrp
        case .stellar: self = .stellar
        case .monero: self = .monero
        case .sui: self = .sui
        case .aptos: self = .aptos
        case .ton: self = .ton
        case .icp: self = .icp
        case .near: self = .near
        case .polkadot: self = .polkadot
        }}
    var descriptor: AppChainDescriptor { AppEndpointDirectory.appChain(for: chainID) }
    var title: String { descriptor.title }
    var shortLabel: String { descriptor.shortLabel }
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
    let store: AppState
    @ObservedObject private var chainDiagnosticsState: WalletChainDiagnosticsState
    @StateObject private var refreshSignal: ViewRefreshSignal
    let chain: StandardDiagnosticsChain
    private let copy = DiagnosticsContentCopy.current
    @State private var copiedDiagnosticsNotice: String?
    @State private var selectedMoneroBackendID: String = MoneroBalanceService.defaultBackendID
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []
    private let moneroCustomBackendID = "custom"
    init(store: AppState, chain: StandardDiagnosticsChain) {
        self.store = store
        self.chain = chain
        _chainDiagnosticsState = ObservedObject(wrappedValue: store.chainDiagnosticsState)
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    private var displayChainTitle: String { store.displayChainTitle(for: chain.descriptor.chainName) }
    private var diagnosticsLabel: String { displayChainTitle }
    private var moneroBackendChoices: [(id: String, title: String)] {
        let trusted = MoneroBalanceService.trustedBackends.map { ($0.id, $0.displayName) }
        return trusted + [(moneroCustomBackendID, AppLocalization.string("Custom URL"))]
    }
    private var selectedTrustedMoneroBackend: MoneroBalanceService.TrustedBackend? {
        MoneroBalanceService.trustedBackends.first(where: { $0.id == selectedMoneroBackendID })
    }
    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                if chain == .ethereum {
                    Button(
                        store.isRunningEthereumSelfTests
                            ? localizedFormat("Running %@ Diagnostics...", diagnosticsLabel)
                            : localizedFormat("Run %@ Diagnostics", diagnosticsLabel)
                    ) {
                        Task {
                            await store.runEthereumSelfTests()
                        }}.disabled(store.isRunningEthereumSelfTests)
                }
                Button(
                    isRunningHistory
                        ? localizedFormat("Running %@ History Diagnostics...", diagnosticsLabel)
                        : localizedFormat("Run %@ History Diagnostics", diagnosticsLabel)
                ) {
                    Task {
                        await runHistoryDiagnostics()
                    }}.disabled(isRunningHistory)
                Button(localizedFormat("Copy %@ Diagnostics JSON", diagnosticsLabel)) {
                    if let payload = diagnosticsJSON {
                        UIPasteboard.general.string = payload
                        copiedDiagnosticsNotice = localizedFormat("%@ diagnostics JSON copied.", diagnosticsLabel)
                    } else { copiedDiagnosticsNotice = localizedFormat("No %@ diagnostics available to copy.", diagnosticsLabel) }}
                Button(
                    isCheckingEndpoints
                        ? localizedFormat("Checking %@ Endpoints...", diagnosticsLabel)
                        : localizedFormat("Check %@ Endpoints", diagnosticsLabel)
                ) {
                    Task {
                        await runEndpointDiagnostics()
                    }}.disabled(isCheckingEndpoints)
                if let copiedDiagnosticsNotice { Text(copiedDiagnosticsNotice).font(.caption).foregroundStyle(.secondary) }}
            Section(copy.statusSectionTitle) {
                if let updatedAt = historyLastUpdatedAt { Text(String(format: copy.lastHistoryRunFormat, updatedAt.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) } else { Text(copy.historyNotRunYet).font(.caption).foregroundStyle(.secondary) }
                Text(String(format: copy.walletDiagnosticsCoveredFormat, String(historyWalletCount))).font(.caption).foregroundStyle(.secondary)
                if let primarySource = historySourceRows.first { Text(String(format: copy.mostUsedHistorySourceFormat, primarySource.source, String(primarySource.count))).font(.caption).foregroundStyle(.secondary) }
                if let updatedAt = endpointLastUpdatedAt {
                    let formattedUpdatedAt = updatedAt.formatted(date: .abbreviated, time: .shortened)
                    Text(String(format: copy.lastEndpointCheckFormat, formattedUpdatedAt)).font(.caption).foregroundStyle(.secondary)
                }
                if !endpointRows.isEmpty {
                    let reachableCount = endpointRows.filter { $0.reachable == true }.count
                    Text(String(format: copy.endpointHealthFormat, String(reachableCount), String(endpointRows.count))).font(.caption).foregroundStyle(.secondary)
                }}
            Section(String(format: copy.historySourcesSectionTitleFormat, diagnosticsLabel)) {
                if historySourceRows.isEmpty { Text(copy.noHistoryTelemetryYet).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(historySourceRows) { item in
                        HStack {
                            Text(item.source).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(localizedFormat("diagnostics.countOnly", item.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }}}}
            Section(String(format: copy.endpointReachabilitySectionTitleFormat, diagnosticsLabel)) {
                if endpointRows.isEmpty { Text(copy.noEndpointChecksYet).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(endpointRows) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: endpointStatusIconName(for: result)).foregroundStyle(endpointStatusColor(for: result))
                                Text(result.endpoint).font(.subheadline.weight(.semibold))
                            }
                            Text(result.detail).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }}}
            chainSpecificSections
        }.navigationTitle(displayChainTitle + " Diagnostics").onAppear {
            if chain == .monero { syncSelectedMoneroBackendIDFromStore() }
            rebuildCachedRows()
        }.onChange(of: copiedDiagnosticsNotice) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copiedDiagnosticsNotice = nil
            }}.onChange(of: selectedMoneroBackendID) { _, newValue in
            guard chain == .monero else { return }
            if newValue == moneroCustomBackendID { return }
            if newValue == MoneroBalanceService.defaultBackendID {
                store.moneroBackendBaseURL = ""
                return
            }
            if let trusted = MoneroBalanceService.trustedBackends.first(where: { $0.id == newValue }) {
                store.moneroBackendBaseURL = trusted.baseURL
            }}.onChange(of: store.moneroBackendBaseURL) { _, _ in
            guard chain == .monero else { return }
            syncSelectedMoneroBackendIDFromStore()
        }.onChange(of: historyLastUpdatedAt) { _, _ in
            rebuildHistorySourceRows()
        }.onChange(of: historyWalletCount) { _, _ in
            rebuildHistorySourceRows()
        }.onChange(of: endpointLastUpdatedAt) { _, _ in
            rebuildEndpointRows()
        }}
    private var isRunningHistory: Bool {
        switch chain {
        case .dogecoin: return store.isRunningDogecoinHistoryDiagnostics
        case .bitcoin: return store.isRunningBitcoinHistoryDiagnostics
        case .bitcoinCash: return store.isRunningBitcoinCashHistoryDiagnostics
        case .bitcoinSV: return store.isRunningBitcoinSVHistoryDiagnostics
        case .litecoin: return store.isRunningLitecoinHistoryDiagnostics
        case .ethereum: return store.isRunningEthereumHistoryDiagnostics
        case .ethereumClassic: return store.isRunningETCHistoryDiagnostics
        case .arbitrum: return store.isRunningArbitrumHistoryDiagnostics
        case .optimism: return store.isRunningOptimismHistoryDiagnostics
        case .bnb: return store.isRunningBNBHistoryDiagnostics
        case .avalanche: return store.isRunningAvalancheHistoryDiagnostics
        case .hyperliquid: return store.isRunningHyperliquidHistoryDiagnostics
        case .tron: return store.isRunningTronHistoryDiagnostics
        case .solana: return store.isRunningSolanaHistoryDiagnostics
        case .cardano: return store.isRunningCardanoHistoryDiagnostics
        case .xrp: return store.isRunningXRPHistoryDiagnostics
        case .stellar: return store.isRunningStellarHistoryDiagnostics
        case .monero: return store.isRunningMoneroHistoryDiagnostics
        case .sui: return store.isRunningSuiHistoryDiagnostics
        case .aptos: return store.isRunningAptosHistoryDiagnostics
        case .ton: return store.isRunningTONHistoryDiagnostics
        case .icp: return store.isRunningICPHistoryDiagnostics
        case .near: return store.isRunningNearHistoryDiagnostics
        case .polkadot: return store.isRunningPolkadotHistoryDiagnostics
        }}
    private var isCheckingEndpoints: Bool {
        switch chain {
        case .dogecoin: return store.isCheckingDogecoinEndpointHealth
        case .bitcoin: return store.isCheckingBitcoinEndpointHealth
        case .bitcoinCash: return store.isCheckingBitcoinCashEndpointHealth
        case .bitcoinSV: return store.isCheckingBitcoinSVEndpointHealth
        case .litecoin: return store.isCheckingLitecoinEndpointHealth
        case .ethereum: return store.isCheckingEthereumEndpointHealth
        case .ethereumClassic: return store.isCheckingETCEndpointHealth
        case .arbitrum: return store.isCheckingArbitrumEndpointHealth
        case .optimism: return store.isCheckingOptimismEndpointHealth
        case .bnb: return store.isCheckingBNBEndpointHealth
        case .avalanche: return store.isCheckingAvalancheEndpointHealth
        case .hyperliquid: return store.isCheckingHyperliquidEndpointHealth
        case .tron: return store.isCheckingTronEndpointHealth
        case .solana: return store.isCheckingSolanaEndpointHealth
        case .cardano: return store.isCheckingCardanoEndpointHealth
        case .xrp: return store.isCheckingXRPEndpointHealth
        case .stellar: return store.isCheckingStellarEndpointHealth
        case .monero: return store.isCheckingMoneroEndpointHealth
        case .sui: return store.isCheckingSuiEndpointHealth
        case .aptos: return store.isCheckingAptosEndpointHealth
        case .ton: return store.isCheckingTONEndpointHealth
        case .icp: return store.isCheckingICPEndpointHealth
        case .near: return store.isCheckingNearEndpointHealth
        case .polkadot: return store.isCheckingPolkadotEndpointHealth
        }}
    private var diagnosticsJSON: String? {
        switch chain {
        case .dogecoin: return store.dogecoinDiagnosticsJSON()
        case .bitcoin: return store.bitcoinDiagnosticsJSON()
        case .bitcoinCash: return store.bitcoinCashDiagnosticsJSON()
        case .bitcoinSV: return store.bitcoinSVDiagnosticsJSON()
        case .litecoin: return store.litecoinDiagnosticsJSON()
        case .ethereum: return store.ethereumDiagnosticsJSON()
        case .ethereumClassic: return store.etcDiagnosticsJSON()
        case .arbitrum: return store.arbitrumDiagnosticsJSON()
        case .optimism: return store.optimismDiagnosticsJSON()
        case .bnb: return store.bnbDiagnosticsJSON()
        case .avalanche: return store.avalancheDiagnosticsJSON()
        case .hyperliquid: return store.hyperliquidDiagnosticsJSON()
        case .tron: return store.tronDiagnosticsJSON()
        case .solana: return store.solanaDiagnosticsJSON()
        case .cardano: return store.cardanoDiagnosticsJSON()
        case .xrp: return store.xrpDiagnosticsJSON()
        case .stellar: return store.stellarDiagnosticsJSON()
        case .monero: return store.moneroDiagnosticsJSON()
        case .sui: return store.suiDiagnosticsJSON()
        case .aptos: return store.aptosDiagnosticsJSON()
        case .ton: return store.tonDiagnosticsJSON()
        case .icp: return store.icpDiagnosticsJSON()
        case .near: return store.nearDiagnosticsJSON()
        case .polkadot: return store.polkadotDiagnosticsJSON()
        }}
    private var historyLastUpdatedAt: Date? {
        switch chain {
        case .dogecoin: return store.dogecoinHistoryDiagnosticsLastUpdatedAt
        case .bitcoin: return store.bitcoinHistoryDiagnosticsLastUpdatedAt
        case .bitcoinCash: return store.bitcoinCashHistoryDiagnosticsLastUpdatedAt
        case .bitcoinSV: return store.bitcoinSVHistoryDiagnosticsLastUpdatedAt
        case .litecoin: return store.litecoinHistoryDiagnosticsLastUpdatedAt
        case .ethereum: return store.ethereumHistoryDiagnosticsLastUpdatedAt
        case .ethereumClassic: return store.etcHistoryDiagnosticsLastUpdatedAt
        case .arbitrum: return store.arbitrumHistoryDiagnosticsLastUpdatedAt
        case .optimism: return store.optimismHistoryDiagnosticsLastUpdatedAt
        case .bnb: return store.bnbHistoryDiagnosticsLastUpdatedAt
        case .avalanche: return store.avalancheHistoryDiagnosticsLastUpdatedAt
        case .hyperliquid: return store.hyperliquidHistoryDiagnosticsLastUpdatedAt
        case .tron: return store.tronHistoryDiagnosticsLastUpdatedAt
        case .solana: return store.solanaHistoryDiagnosticsLastUpdatedAt
        case .cardano: return store.cardanoHistoryDiagnosticsLastUpdatedAt
        case .xrp: return store.xrpHistoryDiagnosticsLastUpdatedAt
        case .stellar: return store.stellarHistoryDiagnosticsLastUpdatedAt
        case .monero: return store.moneroHistoryDiagnosticsLastUpdatedAt
        case .sui: return store.suiHistoryDiagnosticsLastUpdatedAt
        case .aptos: return store.aptosHistoryDiagnosticsLastUpdatedAt
        case .ton: return store.tonHistoryDiagnosticsLastUpdatedAt
        case .icp: return store.icpHistoryDiagnosticsLastUpdatedAt
        case .near: return store.nearHistoryDiagnosticsLastUpdatedAt
        case .polkadot: return store.polkadotHistoryDiagnosticsLastUpdatedAt
        }}
    private var historyWalletCount: Int {
        switch chain {
        case .dogecoin: return store.dogecoinHistoryDiagnosticsByWallet.count
        case .bitcoin: return store.bitcoinHistoryDiagnosticsByWallet.count
        case .bitcoinCash: return store.bitcoinCashHistoryDiagnosticsByWallet.count
        case .bitcoinSV: return store.bitcoinSVHistoryDiagnosticsByWallet.count
        case .litecoin: return store.litecoinHistoryDiagnosticsByWallet.count
        case .ethereum: return store.ethereumHistoryDiagnosticsByWallet.count
        case .ethereumClassic: return store.etcHistoryDiagnosticsByWallet.count
        case .arbitrum: return store.arbitrumHistoryDiagnosticsByWallet.count
        case .optimism: return store.optimismHistoryDiagnosticsByWallet.count
        case .bnb: return store.bnbHistoryDiagnosticsByWallet.count
        case .avalanche: return store.avalancheHistoryDiagnosticsByWallet.count
        case .hyperliquid: return store.hyperliquidHistoryDiagnosticsByWallet.count
        case .tron: return store.tronHistoryDiagnosticsByWallet.count
        case .solana: return store.solanaHistoryDiagnosticsByWallet.count
        case .cardano: return store.cardanoHistoryDiagnosticsByWallet.count
        case .xrp: return store.xrpHistoryDiagnosticsByWallet.count
        case .stellar: return store.stellarHistoryDiagnosticsByWallet.count
        case .monero: return store.moneroHistoryDiagnosticsByWallet.count
        case .sui: return store.suiHistoryDiagnosticsByWallet.count
        case .aptos: return store.aptosHistoryDiagnosticsByWallet.count
        case .ton: return store.tonHistoryDiagnosticsByWallet.count
        case .icp: return store.icpHistoryDiagnosticsByWallet.count
        case .near: return store.nearHistoryDiagnosticsByWallet.count
        case .polkadot: return store.polkadotHistoryDiagnosticsByWallet.count
        }}
    private var endpointLastUpdatedAt: Date? {
        switch chain {
        case .dogecoin: return store.dogecoinEndpointHealthLastUpdatedAt
        case .bitcoin: return store.bitcoinEndpointHealthLastUpdatedAt
        case .bitcoinCash: return store.bitcoinCashEndpointHealthLastUpdatedAt
        case .bitcoinSV: return store.bitcoinSVEndpointHealthLastUpdatedAt
        case .litecoin: return store.litecoinEndpointHealthLastUpdatedAt
        case .ethereum: return store.ethereumEndpointHealthLastUpdatedAt
        case .ethereumClassic: return store.etcEndpointHealthLastUpdatedAt
        case .arbitrum: return store.arbitrumEndpointHealthLastUpdatedAt
        case .optimism: return store.optimismEndpointHealthLastUpdatedAt
        case .bnb: return store.bnbEndpointHealthLastUpdatedAt
        case .avalanche: return store.avalancheEndpointHealthLastUpdatedAt
        case .hyperliquid: return store.hyperliquidEndpointHealthLastUpdatedAt
        case .tron: return store.tronEndpointHealthLastUpdatedAt
        case .solana: return store.solanaEndpointHealthLastUpdatedAt
        case .cardano: return store.cardanoEndpointHealthLastUpdatedAt
        case .xrp: return store.xrpEndpointHealthLastUpdatedAt
        case .stellar: return store.stellarEndpointHealthLastUpdatedAt
        case .monero: return store.moneroEndpointHealthLastUpdatedAt
        case .sui: return store.suiEndpointHealthLastUpdatedAt
        case .aptos: return store.aptosEndpointHealthLastUpdatedAt
        case .ton: return store.tonEndpointHealthLastUpdatedAt
        case .icp: return store.icpEndpointHealthLastUpdatedAt
        case .near: return store.nearEndpointHealthLastUpdatedAt
        case .polkadot: return store.polkadotEndpointHealthLastUpdatedAt
        }}
    private var endpointRows: [StandardEndpointRow] { cachedEndpointRows }
    private var historySourceRows: [StandardHistorySourceRow] { cachedHistorySourceRows }
    private func rebuildCachedRows() {
        rebuildEndpointRows()
        rebuildHistorySourceRows()
    }
    private typealias EndpointTuple = (endpoint: String, reachable: Bool?, detail: String)
    private func rawEndpointResultTuples(for chain: StandardDiagnosticsChain) -> [EndpointTuple] {
        switch chain {
        case .bitcoin: return store.bitcoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .bitcoinCash: return store.bitcoinCashEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .bitcoinSV: return store.bitcoinSVEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .litecoin: return store.litecoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .dogecoin: return store.dogecoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .ethereum: return store.ethereumEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .ethereumClassic: return store.etcEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .arbitrum: return store.arbitrumEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .optimism: return store.optimismEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .bnb: return store.bnbEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .avalanche: return store.avalancheEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .hyperliquid: return store.hyperliquidEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .tron: return store.tronEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .solana: return store.solanaEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .cardano: return store.cardanoEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .xrp: return store.xrpEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .monero: return store.moneroEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .sui: return store.suiEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .aptos: return store.aptosEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .ton: return store.tonEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .icp: return store.icpEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .near: return store.nearEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .polkadot: return store.polkadotEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }
        case .stellar: return store.stellarEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) }}}
    private func rebuildEndpointRows() {
        let fallbackRows = configuredEndpointsForCurrentChain().map { StandardEndpointRow(endpoint: $0, reachable: nil, detail: "Not checked yet") }
        let raw = rawEndpointResultTuples(for: chain)
        cachedEndpointRows = raw.isEmpty ? fallbackRows : raw.map { StandardEndpointRow(endpoint: $0.endpoint, reachable: $0.reachable, detail: $0.detail) }}
    private func endpointStatusIconName(for row: StandardEndpointRow) -> String {
        switch row.reachable {
        case true: return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        case nil: return "clock.badge.questionmark"
        }}
    private func endpointStatusColor(for row: StandardEndpointRow) -> Color {
        switch row.reachable {
        case true: return .green
        case false: return .red
        case nil: return .secondary
        }}
    private func configuredEndpointsForCurrentChain() -> [String] {
        switch chain {
        case .bitcoin: let parsedCustom = store.bitcoinEsploraEndpoints.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let trimmed = parsedCustom.filter { !$0.isEmpty }
            return trimmed.isEmpty ? AppEndpointDirectory.bitcoinEsploraBaseURLs(for: store.bitcoinNetworkMode) : trimmed
        case .bitcoinCash: return BitcoinCashBalanceService.endpointCatalog()
        case .bitcoinSV: return BitcoinSVBalanceService.endpointCatalog()
        case .litecoin: return LitecoinBalanceService.endpointCatalog()
        case .dogecoin: return DogecoinBalanceService.endpointCatalog()
        case .ethereum: var endpoints: [String] = []
            let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { endpoints.append(custom) }
            let context = store.evmChainContext(for: "Ethereum") ?? .ethereum
            for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "Ethereum") where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            return endpoints
        case .ethereumClassic: return EVMChainContext.ethereumClassic.defaultRPCEndpoints
        case .arbitrum: return EVMChainContext.arbitrum.defaultRPCEndpoints
        case .optimism: return EVMChainContext.optimism.defaultRPCEndpoints
        case .bnb: var endpoints = EVMChainContext.bnb.defaultRPCEndpoints
            for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "BNB Chain") where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            return endpoints
        case .avalanche: return EVMChainContext.avalanche.defaultRPCEndpoints
        case .hyperliquid: return EVMChainContext.hyperliquid.defaultRPCEndpoints
        case .tron: return TronBalanceService.endpointCatalog()
        case .solana: return SolanaBalanceService.endpointCatalog()
        case .cardano: return CardanoBalanceService.endpointCatalog()
        case .xrp: return XRPBalanceService.endpointCatalog()
        case .stellar: return StellarBalanceService.endpointCatalog()
        case .monero: let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [MoneroBalanceService.defaultPublicBackend.baseURL] : [trimmed]
        case .sui: return SuiBalanceService.endpointCatalog()
        case .aptos: return AptosBalanceService.endpointCatalog()
        case .ton: return TONBalanceService.endpointCatalog()
        case .icp: return ICPBalanceService.endpointCatalog()
        case .near: return NearBalanceService.endpointCatalog()
        case .polkadot: return PolkadotBalanceService.endpointCatalog()
        }}
    private func rebuildHistorySourceRows() {
        let sources: [String]
        switch chain {
        case .dogecoin: sources = store.dogecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bitcoin: sources = store.bitcoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bitcoinCash: sources = store.bitcoinCashHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bitcoinSV: sources = store.bitcoinSVHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .litecoin: sources = store.litecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ethereum: sources = store.ethereumHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ethereumClassic: sources = store.etcHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .arbitrum: sources = store.arbitrumHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .optimism: sources = store.optimismHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .bnb: sources = store.bnbHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .avalanche: sources = store.avalancheHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .hyperliquid: sources = store.hyperliquidHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .tron: sources = store.tronHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .solana: sources = store.solanaHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .cardano: sources = store.cardanoHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .xrp: sources = store.xrpHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .monero: sources = store.moneroHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .sui: sources = store.suiHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .aptos: sources = store.aptosHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .ton: sources = store.tonHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .icp: sources = store.icpHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .near: sources = store.nearHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .polkadot: sources = store.polkadotHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        case .stellar: sources = store.stellarHistoryDiagnosticsByWallet.values.map(\.sourceUsed)
        }
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
            }}
    private func runHistoryDiagnostics() async {
        switch chain {
        case .dogecoin: await store.runDogecoinHistoryDiagnostics()
        case .bitcoin: await store.runBitcoinHistoryDiagnostics()
        case .bitcoinCash: await store.runBitcoinCashHistoryDiagnostics()
        case .bitcoinSV: await store.runBitcoinSVHistoryDiagnostics()
        case .litecoin: await store.runLitecoinHistoryDiagnostics()
        case .ethereum: await store.runEthereumHistoryDiagnostics()
        case .ethereumClassic: await store.runETCHistoryDiagnostics()
        case .arbitrum: await store.runArbitrumHistoryDiagnostics()
        case .optimism: await store.runOptimismHistoryDiagnostics()
        case .bnb: await store.runBNBHistoryDiagnostics()
        case .avalanche: await store.runAvalancheHistoryDiagnostics()
        case .hyperliquid: await store.runHyperliquidHistoryDiagnostics()
        case .tron: await store.runTronHistoryDiagnostics()
        case .solana: await store.runSolanaHistoryDiagnostics()
        case .cardano: await store.runCardanoHistoryDiagnostics()
        case .xrp: await store.runXRPHistoryDiagnostics()
        case .monero: await store.runMoneroHistoryDiagnostics()
        case .sui: await store.runSuiHistoryDiagnostics()
        case .aptos: await store.runAptosHistoryDiagnostics()
        case .ton: await store.runTONHistoryDiagnostics()
        case .icp: await store.runICPHistoryDiagnostics()
        case .near: await store.runNearHistoryDiagnostics()
        case .polkadot: await store.runPolkadotHistoryDiagnostics()
        case .stellar: await store.runStellarHistoryDiagnostics()
        }}
    private func runEndpointDiagnostics() async {
        switch chain {
        case .dogecoin: await store.runDogecoinEndpointReachabilityDiagnostics()
        case .bitcoin: await store.runBitcoinEndpointReachabilityDiagnostics()
        case .bitcoinCash: await store.runBitcoinCashEndpointReachabilityDiagnostics()
        case .bitcoinSV: await store.runBitcoinSVEndpointReachabilityDiagnostics()
        case .litecoin: await store.runLitecoinEndpointReachabilityDiagnostics()
        case .ethereum: await store.runEthereumEndpointReachabilityDiagnostics()
        case .ethereumClassic: await store.runETCEndpointReachabilityDiagnostics()
        case .arbitrum: await store.runArbitrumEndpointReachabilityDiagnostics()
        case .optimism: await store.runOptimismEndpointReachabilityDiagnostics()
        case .bnb: await store.runBNBEndpointReachabilityDiagnostics()
        case .avalanche: await store.runAvalancheEndpointReachabilityDiagnostics()
        case .hyperliquid: await store.runHyperliquidEndpointReachabilityDiagnostics()
        case .tron: await store.runTronEndpointReachabilityDiagnostics()
        case .solana: await store.runSolanaEndpointReachabilityDiagnostics()
        case .cardano: await store.runCardanoEndpointReachabilityDiagnostics()
        case .xrp: await store.runXRPEndpointReachabilityDiagnostics()
        case .monero: await store.runMoneroEndpointReachabilityDiagnostics()
        case .sui: await store.runSuiEndpointReachabilityDiagnostics()
        case .aptos: await store.runAptosEndpointReachabilityDiagnostics()
        case .ton: await store.runTONEndpointReachabilityDiagnostics()
        case .icp: await store.runICPEndpointReachabilityDiagnostics()
        case .near: await store.runNearEndpointReachabilityDiagnostics()
        case .polkadot: await store.runPolkadotEndpointReachabilityDiagnostics()
        case .stellar: await store.runStellarEndpointReachabilityDiagnostics()
        }}
    @ViewBuilder
    private var chainSpecificSections: some View {
        if chain == .bitcoin {
            Section(AppLocalization.string("Bitcoin Settings")) {
                Picker(AppLocalization.string("Send Fee Priority"), selection: Binding(get: { store.bitcoinFeePriority }, set: { store.bitcoinFeePriority = $0 })) {
                    ForEach(BitcoinFeePriority.allCases) { priority in Text(priority.displayName).tag(priority) }}.pickerStyle(.segmented)
                TextField(
                    AppLocalization.string("Custom Esplora endpoints (comma-separated, optional)"), text: Binding(get: { store.bitcoinEsploraEndpoints }, set: { store.bitcoinEsploraEndpoints = $0 })
                ).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                if let bitcoinEsploraEndpointsValidationError = store.bitcoinEsploraEndpointsValidationError { Text(bitcoinEsploraEndpointsValidationError).font(.caption).foregroundStyle(.red) } else { Text(copy.bitcoinEsploraHint).font(.caption).foregroundStyle(.secondary) }}}
        if chain == .ethereum {
            Section(AppLocalization.string("Ethereum RPC")) {
                TextField(
                    AppLocalization.string("Ethereum RPC URL (Optional)"), text: Binding(get: { store.ethereumRPCEndpoint }, set: { store.ethereumRPCEndpoint = $0 })
                ).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Text(copy.ethereumRPCNote).font(.caption).foregroundStyle(.secondary)
                if let ethereumRPCEndpointValidationError = store.ethereumRPCEndpointValidationError { Text(ethereumRPCEndpointValidationError).font(.caption).foregroundStyle(.red) }}
            Section(AppLocalization.string("Etherscan (Optional)")) {
                TextField(
                    AppLocalization.string("Etherscan API Key"), text: Binding(get: { store.etherscanAPIKey }, set: { store.etherscanAPIKey = $0 })
                ).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(copy.etherscanNote).font(.caption).foregroundStyle(.secondary)
            }}
        if chain == .monero {
            Section(AppLocalization.string("Monero Backend")) {
                Picker(AppLocalization.string("Trusted Backend"), selection: $selectedMoneroBackendID) {
                    ForEach(moneroBackendChoices, id: \.id) { choice in Text(choice.title).tag(choice.id) }}
                if selectedMoneroBackendID == moneroCustomBackendID {
                    TextField(
                        AppLocalization.string("Monero Backend URL (Optional)"), text: Binding(get: { store.moneroBackendBaseURL }, set: { store.moneroBackendBaseURL = $0 })
                    ).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } else { Text(selectedTrustedMoneroBackend?.baseURL ?? MoneroBalanceService.defaultPublicBackend.baseURL).font(.caption.monospaced()).textSelection(.enabled) }
                if let moneroBackendBaseURLValidationError = store.moneroBackendBaseURLValidationError { Text(moneroBackendBaseURLValidationError).font(.caption).foregroundStyle(.red) } else { Text(copy.moneroBackendNote).font(.caption).foregroundStyle(.secondary) }
                TextField(
                    AppLocalization.string("Monero Backend API Key (Optional)"), text: Binding(get: { store.moneroBackendAPIKey }, set: { store.moneroBackendAPIKey = $0 })
                ).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(copy.moneroAPIKeyNote).font(.caption).foregroundStyle(.secondary)
            }}
        if supportsUTXOChainActions {
            Section(AppLocalization.string("Chain Actions")) {
                Button(isRunningChainSelfTests ? AppLocalization.string("Running Self-Tests...") : chainSelfTestButtonTitle) {
                    runChainSelfTests()
                }.disabled(isRunningChainSelfTests)
                Button(isRunningChainRescan ? chainRescanInFlightTitle : chainRescanButtonTitle) {
                    Task {
                        await runChainRescan()
                    }}.disabled(isRunningChainRescan)
            }}
        Section(AppLocalization.string("Operational Events")) {
            let events = store.operationalEvents(for: chain.title)
            if events.isEmpty { Text(AppLocalization.string("No operational events recorded yet.")).font(.caption).foregroundStyle(.secondary) } else {
                ForEach(events.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message).font(.subheadline)
                        Text(event.level.rawValue.capitalized).font(.caption.weight(.semibold)).foregroundStyle(event.level == .error ? .red : (event.level == .warning ? .orange : .secondary))
                        if let transactionHash = event.transactionHash, !transactionHash.isEmpty { Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary) }}.padding(.vertical, 2)
                }}}
        Section(AppLocalization.string("Owned Address Management")) {
            let diagnostics = store.chainKeypoolDiagnostics(for: chain.title)
            if diagnostics.isEmpty { Text(AppLocalization.string("No owned-address management state recorded yet.")).font(.caption).foregroundStyle(.secondary) } else {
                ForEach(diagnostics) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.walletName).font(.subheadline.weight(.semibold))
                        Text("Next receive index: \(item.nextExternalIndex)").font(.caption).foregroundStyle(.secondary)
                        Text("Next change index: \(item.nextChangeIndex)").font(.caption).foregroundStyle(.secondary)
                        if let reservedReceiveIndex = item.reservedReceiveIndex { Text("Reserved receive index: \(reservedReceiveIndex)").font(.caption).foregroundStyle(.secondary) }
                        if let reservedReceivePath = item.reservedReceivePath, !reservedReceivePath.isEmpty { Text(reservedReceivePath).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        if let reservedReceiveAddress = item.reservedReceiveAddress, !reservedReceiveAddress.isEmpty { Text(reservedReceiveAddress).font(.caption.monospaced()).foregroundStyle(.secondary) }}.padding(.vertical, 2)
                }}}}
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
    private var supportsUTXOChainActions: Bool {
        switch chain {
        case .bitcoin, .bitcoinCash, .bitcoinSV, .litecoin, .dogecoin: return true
        default: return false
        }}
    private var isRunningChainSelfTests: Bool {
        switch chain {
        case .bitcoin: return store.isRunningBitcoinSelfTests
        case .bitcoinCash: return store.isRunningBitcoinCashSelfTests
        case .bitcoinSV: return store.isRunningBitcoinSVSelfTests
        case .litecoin: return store.isRunningLitecoinSelfTests
        case .dogecoin: return store.isRunningDogecoinSelfTests
        default: return false
        }}
    private var isRunningChainRescan: Bool {
        switch chain {
        case .bitcoin: return store.isRunningBitcoinRescan
        case .bitcoinCash: return store.isRunningBitcoinCashRescan
        case .bitcoinSV: return store.isRunningBitcoinSVRescan
        case .litecoin: return store.isRunningLitecoinRescan
        case .dogecoin: return store.isRunningDogecoinRescan
        default: return false
        }}
    private var chainSelfTestButtonTitle: String {
        switch chain {
        case .bitcoin: return AppLocalization.string("Run BTC Self-Tests")
        case .bitcoinCash: return AppLocalization.string("Run BCH Self-Tests")
        case .bitcoinSV: return AppLocalization.string("Run BSV Self-Tests")
        case .litecoin: return AppLocalization.string("Run LTC Self-Tests")
        case .dogecoin: return AppLocalization.string("Run DOGE Self-Tests")
        default: return AppLocalization.string("Run Self-Tests")
        }}
    private var chainRescanButtonTitle: String {
        switch chain {
        case .bitcoin: return AppLocalization.string("Run BTC Rescan")
        case .bitcoinCash: return AppLocalization.string("Run BCH Rescan")
        case .bitcoinSV: return AppLocalization.string("Run BSV Rescan")
        case .litecoin: return AppLocalization.string("Run LTC Rescan")
        case .dogecoin: return AppLocalization.string("Run DOGE Rescan")
        default: return AppLocalization.string("Run Rescan")
        }}
    private var chainRescanInFlightTitle: String {
        switch chain {
        case .bitcoin: return AppLocalization.string("Rescanning BTC...")
        case .bitcoinCash: return AppLocalization.string("Rescanning BCH...")
        case .bitcoinSV: return AppLocalization.string("Rescanning BSV...")
        case .litecoin: return AppLocalization.string("Rescanning LTC...")
        case .dogecoin: return AppLocalization.string("Rescanning DOGE...")
        default: return AppLocalization.string("Rescanning...")
        }}
    private func runChainSelfTests() {
        switch chain {
        case .bitcoin: store.runBitcoinSelfTests()
        case .bitcoinCash: store.runBitcoinCashSelfTests()
        case .bitcoinSV: store.runBitcoinSVSelfTests()
        case .litecoin: store.runLitecoinSelfTests()
        case .dogecoin: store.runDogecoinSelfTests()
        default: break
        }}
    private func runChainRescan() async {
        switch chain {
        case .bitcoin: await store.runBitcoinRescan()
        case .bitcoinCash: await store.runBitcoinCashRescan()
        case .bitcoinSV: await store.runBitcoinSVRescan()
        case .litecoin: await store.runLitecoinRescan()
        case .dogecoin: await store.runDogecoinRescan()
        default: break
        }}
}
private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
