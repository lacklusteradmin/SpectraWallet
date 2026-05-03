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
        let chain: StandardDiagnosticsChain
    }
    private var chainDestinations: [DiagnosticsDestination] {
        AppEndpointDirectory.diagnosticsChains.compactMap { descriptor in
            guard let chain = StandardDiagnosticsChain(chainID: descriptor.id) else { return nil }
            let title = store.displayChainTitle(for: descriptor.chainName) + " Diagnostics"
            return DiagnosticsDestination(id: title, title: title, keywords: descriptor.searchKeywords, chain: chain)
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
enum StandardDiagnosticsChain: String, Hashable {
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
    var chainID: AppChainID { AppChainID(rawValue: rawValue) ?? .bitcoin }
    init?(chainID: AppChainID) { self.init(rawValue: chainID.rawValue) }
    var descriptor: AppChainDescriptor { AppEndpointDirectory.appChain(for: chainID) }
    var title: String { descriptor.title }

    static let dispatchTable: [StandardDiagnosticsChain: StandardChainDiagnosticsDispatch] = [
        .bitcoin: .init(
            isRunningHistory: { $0.isRunningBitcoinHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingBitcoinEndpointHealth },
            diagnosticsJSON: { $0.bitcoinDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.bitcoinHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.bitcoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.bitcoinEndpointHealthLastUpdatedAt },
            endpointResults: { $0.bitcoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoin) }
        ),
        .bitcoinCash: .init(
            isRunningHistory: { $0.isRunningBitcoinCashHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingBitcoinCashEndpointHealth },
            diagnosticsJSON: { $0.bitcoinCashDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.bitcoinCashHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.bitcoinCashHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.bitcoinCashEndpointHealthLastUpdatedAt },
            endpointResults: { $0.bitcoinCashEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinCashHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoinCash) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoinCash) }
        ),
        .bitcoinSV: .init(
            isRunningHistory: { $0.isRunningBitcoinSVHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingBitcoinSVEndpointHealth },
            diagnosticsJSON: { $0.bitcoinSVDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.bitcoinSVHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.bitcoinSVHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.bitcoinSVEndpointHealthLastUpdatedAt },
            endpointResults: { $0.bitcoinSVEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinSVHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoinSV) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoinSV) }
        ),
        .litecoin: .init(
            isRunningHistory: { $0.isRunningLitecoinHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingLitecoinEndpointHealth },
            diagnosticsJSON: { $0.litecoinDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.litecoinHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.litecoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.litecoinEndpointHealthLastUpdatedAt },
            endpointResults: { $0.litecoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.litecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .litecoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .litecoin) }
        ),
        .dogecoin: .init(
            isRunningHistory: { $0.isRunningDogecoinHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingDogecoinEndpointHealth },
            diagnosticsJSON: { $0.dogecoinDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.dogecoinHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.dogecoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.dogecoinEndpointHealthLastUpdatedAt },
            endpointResults: { $0.dogecoinEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.dogecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .dogecoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .dogecoin) }
        ),
        .ethereum: .init(
            isRunningHistory: { $0.isRunningEthereumHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingEthereumEndpointHealth },
            diagnosticsJSON: { $0.ethereumDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.ethereumHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.ethereumHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.ethereumEndpointHealthLastUpdatedAt },
            endpointResults: { $0.ethereumEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.ethereumHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ethereum) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ethereum) }
        ),
        .ethereumClassic: .init(
            isRunningHistory: { $0.isRunningETCHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingETCEndpointHealth },
            diagnosticsJSON: { $0.etcDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.etcHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.etcHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.etcEndpointHealthLastUpdatedAt },
            endpointResults: { $0.etcEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.etcHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ethereumClassic) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ethereumClassic) }
        ),
        .arbitrum: .init(
            isRunningHistory: { $0.isRunningArbitrumHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingArbitrumEndpointHealth },
            diagnosticsJSON: { $0.arbitrumDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.arbitrumHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.arbitrumHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.arbitrumEndpointHealthLastUpdatedAt },
            endpointResults: { $0.arbitrumEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.arbitrumHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .arbitrum) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .arbitrum) }
        ),
        .optimism: .init(
            isRunningHistory: { $0.isRunningOptimismHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingOptimismEndpointHealth },
            diagnosticsJSON: { $0.optimismDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.optimismHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.optimismHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.optimismEndpointHealthLastUpdatedAt },
            endpointResults: { $0.optimismEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.optimismHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .optimism) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .optimism) }
        ),
        .bnb: .init(
            isRunningHistory: { $0.isRunningBNBHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingBNBEndpointHealth },
            diagnosticsJSON: { $0.bnbDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.bnbHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.bnbHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.bnbEndpointHealthLastUpdatedAt },
            endpointResults: { $0.bnbEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bnbHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bnb) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bnb) }
        ),
        .avalanche: .init(
            isRunningHistory: { $0.isRunningAvalancheHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingAvalancheEndpointHealth },
            diagnosticsJSON: { $0.avalancheDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.avalancheHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.avalancheHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.avalancheEndpointHealthLastUpdatedAt },
            endpointResults: { $0.avalancheEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.avalancheHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .avalanche) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .avalanche) }
        ),
        .hyperliquid: .init(
            isRunningHistory: { $0.isRunningHyperliquidHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingHyperliquidEndpointHealth },
            diagnosticsJSON: { $0.hyperliquidDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.hyperliquidHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.hyperliquidHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.hyperliquidEndpointHealthLastUpdatedAt },
            endpointResults: { $0.hyperliquidEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.hyperliquidHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .hyperliquid) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .hyperliquid) }
        ),
        .tron: .init(
            isRunningHistory: { $0.isRunningTronHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingTronEndpointHealth },
            diagnosticsJSON: { $0.tronDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.tronHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.tronHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.tronEndpointHealthLastUpdatedAt },
            endpointResults: { $0.tronEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.tronHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .tron) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .tron) }
        ),
        .solana: .init(
            isRunningHistory: { $0.isRunningSolanaHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingSolanaEndpointHealth },
            diagnosticsJSON: { $0.solanaDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.solanaHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.solanaHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.solanaEndpointHealthLastUpdatedAt },
            endpointResults: { $0.solanaEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.solanaHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .solana) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .solana) }
        ),
        .cardano: .init(
            isRunningHistory: { $0.isRunningCardanoHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingCardanoEndpointHealth },
            diagnosticsJSON: { $0.cardanoDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.cardanoHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.cardanoHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.cardanoEndpointHealthLastUpdatedAt },
            endpointResults: { $0.cardanoEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.cardanoHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .cardano) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .cardano) }
        ),
        .xrp: .init(
            isRunningHistory: { $0.isRunningXRPHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingXRPEndpointHealth },
            diagnosticsJSON: { $0.xrpDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.xrpHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.xrpHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.xrpEndpointHealthLastUpdatedAt },
            endpointResults: { $0.xrpEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.xrpHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .xrp) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .xrp) }
        ),
        .stellar: .init(
            isRunningHistory: { $0.isRunningStellarHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingStellarEndpointHealth },
            diagnosticsJSON: { $0.stellarDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.stellarHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.stellarHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.stellarEndpointHealthLastUpdatedAt },
            endpointResults: { $0.stellarEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.stellarHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .stellar) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .stellar) }
        ),
        .monero: .init(
            isRunningHistory: { $0.isRunningMoneroHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingMoneroEndpointHealth },
            diagnosticsJSON: { $0.moneroDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.moneroHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.moneroHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.moneroEndpointHealthLastUpdatedAt },
            endpointResults: { $0.moneroEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.moneroHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .monero) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .monero) }
        ),
        .sui: .init(
            isRunningHistory: { $0.isRunningSuiHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingSuiEndpointHealth },
            diagnosticsJSON: { $0.suiDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.suiHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.suiHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.suiEndpointHealthLastUpdatedAt },
            endpointResults: { $0.suiEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.suiHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .sui) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .sui) }
        ),
        .aptos: .init(
            isRunningHistory: { $0.isRunningAptosHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingAptosEndpointHealth },
            diagnosticsJSON: { $0.aptosDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.aptosHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.aptosHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.aptosEndpointHealthLastUpdatedAt },
            endpointResults: { $0.aptosEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.aptosHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .aptos) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .aptos) }
        ),
        .ton: .init(
            isRunningHistory: { $0.isRunningTONHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingTONEndpointHealth },
            diagnosticsJSON: { $0.tonDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.tonHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.tonHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.tonEndpointHealthLastUpdatedAt },
            endpointResults: { $0.tonEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.tonHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ton) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ton) }
        ),
        .icp: .init(
            isRunningHistory: { $0.isRunningICPHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingICPEndpointHealth },
            diagnosticsJSON: { $0.icpDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.icpHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.icpHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.icpEndpointHealthLastUpdatedAt },
            endpointResults: { $0.icpEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.icpHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .icp) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .icp) }
        ),
        .near: .init(
            isRunningHistory: { $0.isRunningNearHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingNearEndpointHealth },
            diagnosticsJSON: { $0.nearDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.nearHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.nearHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.nearEndpointHealthLastUpdatedAt },
            endpointResults: { $0.nearEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.nearHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .near) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .near) }
        ),
        .polkadot: .init(
            isRunningHistory: { $0.isRunningPolkadotHistoryDiagnostics },
            isCheckingEndpoints: { $0.isCheckingPolkadotEndpointHealth },
            diagnosticsJSON: { $0.polkadotDiagnosticsJSON() },
            historyLastUpdatedAt: { $0.polkadotHistoryDiagnosticsLastUpdatedAt },
            historyWalletCount: { $0.polkadotHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0.polkadotEndpointHealthLastUpdatedAt },
            endpointResults: { $0.polkadotEndpointHealthResults.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.polkadotHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .polkadot) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .polkadot) }
        ),
    ]
    var dispatch: StandardChainDiagnosticsDispatch { Self.dispatchTable[self]! }
}
struct StandardChainDiagnosticsDispatch {
    let isRunningHistory: @MainActor (AppState) -> Bool
    let isCheckingEndpoints: @MainActor (AppState) -> Bool
    let diagnosticsJSON: @MainActor (AppState) -> String?
    let historyLastUpdatedAt: @MainActor (AppState) -> Date?
    let historyWalletCount: @MainActor (AppState) -> Int
    let endpointLastUpdatedAt: @MainActor (AppState) -> Date?
    let endpointResults: @MainActor (AppState) -> [(endpoint: String, reachable: Bool?, detail: String)]
    let historySources: @MainActor (AppState) -> [String]
    let runHistoryDiagnostics: (AppState) async -> Void
    let runEndpointDiagnostics: (AppState) async -> Void
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
    let chain: StandardDiagnosticsChain
    private let copy = DiagnosticsContentCopy.current
    @State private var copiedDiagnosticsNotice: String?
    @State private var selectedMoneroBackendID: String = MoneroBalanceService.defaultBackendID
    @State private var cachedEndpointRows: [StandardEndpointRow] = []
    @State private var cachedHistorySourceRows: [StandardHistorySourceRow] = []
    private let moneroCustomBackendID = "custom"
    private var chainDiagnosticsState: WalletChainDiagnosticsState { store.chainDiagnosticsState }
    private var displayChainTitle: String { store.displayChainTitle(for: chain.descriptor.chainName) }
    private var diagnosticsLabel: String { displayChainTitle }
    private var moneroBackendChoices: [(id: String, title: String)] {
        let trusted = MoneroBalanceService.trustedBackends.map { ($0.id, $0.displayName) }
        return trusted + [(moneroCustomBackendID, AppLocalization.string("Custom URL"))]
    }
    private var selectedTrustedMoneroBackend: MoneroBalanceService.TrustedBackend? {
        MoneroBalanceService.trustedBackends.first(where: { $0.id == selectedMoneroBackendID })
    }

    private struct UTXOChainActions {
        let isSelfTesting: @MainActor (AppState) -> Bool
        let isRescanning: @MainActor (AppState) -> Bool
        let selfTestTitle: String
        let rescanTitle: String
        let rescanInFlightTitle: String
        let runSelfTests: @MainActor (AppState) -> Void
        let runRescan: (AppState) async -> Void
    }
    private static let utxoActions: [StandardDiagnosticsChain: UTXOChainActions] = [
        .bitcoin: .init(
            isSelfTesting: { $0.isRunningBitcoinSelfTests }, isRescanning: { $0.isRunningBitcoinRescan },
            selfTestTitle: "Run BTC Self-Tests", rescanTitle: "Run BTC Rescan", rescanInFlightTitle: "Rescanning BTC...",
            runSelfTests: { $0.runBitcoinSelfTests() }, runRescan: { await $0.runBitcoinRescan() }
        ),
        .bitcoinCash: .init(
            isSelfTesting: { $0.isRunningBitcoinCashSelfTests }, isRescanning: { $0.isRunningBitcoinCashRescan },
            selfTestTitle: "Run BCH Self-Tests", rescanTitle: "Run BCH Rescan", rescanInFlightTitle: "Rescanning BCH...",
            runSelfTests: { $0.runBitcoinCashSelfTests() }, runRescan: { await $0.runBitcoinCashRescan() }
        ),
        .bitcoinSV: .init(
            isSelfTesting: { $0.isRunningBitcoinSVSelfTests }, isRescanning: { $0.isRunningBitcoinSVRescan },
            selfTestTitle: "Run BSV Self-Tests", rescanTitle: "Run BSV Rescan", rescanInFlightTitle: "Rescanning BSV...",
            runSelfTests: { $0.runBitcoinSVSelfTests() }, runRescan: { await $0.runBitcoinSVRescan() }
        ),
        .litecoin: .init(
            isSelfTesting: { $0.isRunningLitecoinSelfTests }, isRescanning: { $0.isRunningLitecoinRescan },
            selfTestTitle: "Run LTC Self-Tests", rescanTitle: "Run LTC Rescan", rescanInFlightTitle: "Rescanning LTC...",
            runSelfTests: { $0.runLitecoinSelfTests() }, runRescan: { await $0.runLitecoinRescan() }
        ),
        .dogecoin: .init(
            isSelfTesting: { $0.isRunningDogecoinSelfTests }, isRescanning: { $0.isRunningDogecoinRescan },
            selfTestTitle: "Run DOGE Self-Tests", rescanTitle: "Run DOGE Rescan", rescanInFlightTitle: "Rescanning DOGE...",
            runSelfTests: { $0.runDogecoinSelfTests() }, runRescan: { await $0.runDogecoinRescan() }
        ),
    ]

    var body: some View {
        Form {
            Section(copy.actionsSectionTitle) {
                if chain == .ethereum {
                    Button(
                        store.isRunningEthereumSelfTests
                            ? AppLocalization.format("Running %@ Diagnostics...", diagnosticsLabel)
                            : AppLocalization.format("Run %@ Diagnostics", diagnosticsLabel)
                    ) {
                        Task {
                            await store.runEthereumSelfTests()
                        }
                    }.disabled(store.isRunningEthereumSelfTests)
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
    private var historyWalletCount: Int { chain.dispatch.historyWalletCount(store) }
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
    private func configuredEndpointsForCurrentChain() -> [String] {
        switch chain {
        case .bitcoin:
            let parsedCustom = store.bitcoinEsploraEndpoints.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            let trimmed = parsedCustom.filter { !$0.isEmpty }
            return trimmed.isEmpty ? AppEndpointDirectory.bitcoinEsploraBaseURLs(for: store.bitcoinNetworkMode) : trimmed
        case .bitcoinCash: return BitcoinCashBalanceService.endpointCatalog()
        case .bitcoinSV: return BitcoinSVBalanceService.endpointCatalog()
        case .litecoin: return LitecoinBalanceService.endpointCatalog()
        case .dogecoin: return DogecoinBalanceService.endpointCatalog()
        case .ethereum:
            var endpoints: [String] = []
            let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { endpoints.append(custom) }
            let context = store.evmChainContext(for: "Ethereum") ?? .ethereum
            for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "Ethereum") where !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
            return endpoints
        case .ethereumClassic: return EVMChainContext.ethereumClassic.defaultRPCEndpoints
        case .arbitrum: return EVMChainContext.arbitrum.defaultRPCEndpoints
        case .optimism: return EVMChainContext.optimism.defaultRPCEndpoints
        case .bnb:
            var endpoints = EVMChainContext.bnb.defaultRPCEndpoints
            for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "BNB Chain") where !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
            return endpoints
        case .avalanche: return EVMChainContext.avalanche.defaultRPCEndpoints
        case .hyperliquid: return EVMChainContext.hyperliquid.defaultRPCEndpoints
        case .tron: return TronBalanceService.endpointCatalog()
        case .solana: return SolanaBalanceService.endpointCatalog()
        case .cardano: return CardanoBalanceService.endpointCatalog()
        case .xrp: return XRPBalanceService.endpointCatalog()
        case .stellar: return StellarBalanceService.endpointCatalog()
        case .monero:
            let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [MoneroBalanceService.defaultPublicBackend.baseURL] : [trimmed]
        case .sui: return SuiBalanceService.endpointCatalog()
        case .aptos: return AptosBalanceService.endpointCatalog()
        case .ton: return TONBalanceService.endpointCatalog()
        case .icp: return ICPBalanceService.endpointCatalog()
        case .near: return NearBalanceService.endpointCatalog()
        case .polkadot: return PolkadotBalanceService.endpointCatalog()
        }
    }
    private func rebuildHistorySourceRows() {
        let sources = chain.dispatch.historySources(store)
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
            Picker(AppLocalization.string("Send Fee Priority"), selection: $store.bitcoinFeePriority) {
                ForEach(BitcoinFeePriority.allCases) { priority in Text(priority.displayName).tag(priority) }
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
                Button(isRunningChainSelfTests ? AppLocalization.string("Running Self-Tests...") : chainSelfTestButtonTitle) {
                    runChainSelfTests()
                }.disabled(isRunningChainSelfTests)
                Button(isRunningChainRescan ? chainRescanInFlightTitle : chainRescanButtonTitle) {
                    Task {
                        await runChainRescan()
                    }
                }.disabled(isRunningChainRescan)
            }
        }
        Section(AppLocalization.string("Operational Events")) {
            let events = store.operationalEvents(for: chain.title)
            if events.isEmpty {
                Text(AppLocalization.string("No operational events recorded yet.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message).font(.subheadline)
                        Text(event.level.rawValue.capitalized).font(.caption.weight(.semibold)).foregroundStyle(
                            event.level == .error ? .red : (event.level == .warning ? .orange : .secondary))
                        if let transactionHash = event.transactionHash, !transactionHash.isEmpty {
                            Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        Section(AppLocalization.string("Owned Address Management")) {
            let diagnostics = store.chainKeypoolDiagnostics(for: chain.title)
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
    private var supportsUTXOChainActions: Bool { Self.utxoActions[chain] != nil }
    private var isRunningChainSelfTests: Bool { Self.utxoActions[chain]?.isSelfTesting(store) ?? false }
    private var isRunningChainRescan: Bool { Self.utxoActions[chain]?.isRescanning(store) ?? false }
    private var chainSelfTestButtonTitle: String {
        Self.utxoActions[chain].map { AppLocalization.string($0.selfTestTitle) } ?? AppLocalization.string("Run Self-Tests")
    }
    private var chainRescanButtonTitle: String {
        Self.utxoActions[chain].map { AppLocalization.string($0.rescanTitle) } ?? AppLocalization.string("Run Rescan")
    }
    private var chainRescanInFlightTitle: String {
        Self.utxoActions[chain].map { AppLocalization.string($0.rescanInFlightTitle) } ?? AppLocalization.string("Rescanning...")
    }
    private func runChainSelfTests() { Self.utxoActions[chain]?.runSelfTests(store) }
    private func runChainRescan() async { await Self.utxoActions[chain]?.runRescan(store) }
}
private func formatCopy(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
