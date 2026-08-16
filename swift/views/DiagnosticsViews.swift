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
enum StandardDiagnosticsChain: String, Hashable, CaseIterable {
    case dogecoin
    case bitcoin
    case bitcoinCash         = "bitcoin-cash"
    case bitcoinSV           = "bitcoin-sv"
    case litecoin
    case ethereum
    case ethereumClassic     = "ethereum-classic"
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
    case icp                 = "internet-computer"
    case near
    case polkadot
    var chainID: AppChainID { AppChainID(rawValue: rawValue) ?? .bitcoin }
    init?(chainID: AppChainID) { self.init(rawValue: chainID.rawValue) }
    var descriptor: AppChainDescriptor { AppEndpointDirectory.appChain(for: chainID) }
    /// "Bitcoin Diagnostics" — a screen heading, not a chain name.
    var title: String { descriptor.title }
    /// The chain itself. `title` reads like this but is not: passing it where
    /// a chain name belongs silently resolves to nothing.
    var chainName: String { descriptor.chainName }

    @MainActor static let dispatchTable: [StandardDiagnosticsChain: StandardChainDiagnosticsDispatch] = [
        .bitcoin: .init(
            isRunningHistory: { $0[historyRunFor: "Bitcoin"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Bitcoin"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Bitcoin") },
            historyLastUpdatedAt: { $0[historyRunFor: "Bitcoin"].lastUpdatedAt },
            historyWalletCount: { $0.bitcoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Bitcoin"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Bitcoin"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoin) }
        ),
        .bitcoinCash: .init(
            isRunningHistory: { $0[historyRunFor: "Bitcoin Cash"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Bitcoin Cash"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Bitcoin Cash") },
            historyLastUpdatedAt: { $0[historyRunFor: "Bitcoin Cash"].lastUpdatedAt },
            historyWalletCount: { $0.bitcoinCashHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Bitcoin Cash"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Bitcoin Cash"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinCashHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoinCash) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoinCash) }
        ),
        .bitcoinSV: .init(
            isRunningHistory: { $0[historyRunFor: "Bitcoin SV"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Bitcoin SV"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Bitcoin SV") },
            historyLastUpdatedAt: { $0[historyRunFor: "Bitcoin SV"].lastUpdatedAt },
            historyWalletCount: { $0.bitcoinSVHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Bitcoin SV"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Bitcoin SV"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bitcoinSVHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bitcoinSV) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bitcoinSV) }
        ),
        .litecoin: .init(
            isRunningHistory: { $0[historyRunFor: "Litecoin"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Litecoin"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Litecoin") },
            historyLastUpdatedAt: { $0[historyRunFor: "Litecoin"].lastUpdatedAt },
            historyWalletCount: { $0.litecoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Litecoin"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Litecoin"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.litecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .litecoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .litecoin) }
        ),
        .dogecoin: .init(
            isRunningHistory: { $0[historyRunFor: "Dogecoin"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Dogecoin"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Dogecoin") },
            historyLastUpdatedAt: { $0[historyRunFor: "Dogecoin"].lastUpdatedAt },
            historyWalletCount: { $0.dogecoinHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Dogecoin"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Dogecoin"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.dogecoinHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .dogecoin) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .dogecoin) }
        ),
        .ethereum: .init(
            isRunningHistory: { $0[historyRunFor: "Ethereum"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Ethereum"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Ethereum") },
            historyLastUpdatedAt: { $0[historyRunFor: "Ethereum"].lastUpdatedAt },
            historyWalletCount: { $0.ethereumHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Ethereum"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Ethereum"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.ethereumHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ethereum) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ethereum) }
        ),
        .ethereumClassic: .init(
            isRunningHistory: { $0[historyRunFor: "Ethereum Classic"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Ethereum Classic"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Ethereum Classic") },
            historyLastUpdatedAt: { $0[historyRunFor: "Ethereum Classic"].lastUpdatedAt },
            historyWalletCount: { $0.etcHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Ethereum Classic"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Ethereum Classic"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.etcHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ethereumClassic) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ethereumClassic) }
        ),
        .arbitrum: .init(
            isRunningHistory: { $0[historyRunFor: "Arbitrum"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Arbitrum"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Arbitrum") },
            historyLastUpdatedAt: { $0[historyRunFor: "Arbitrum"].lastUpdatedAt },
            historyWalletCount: { $0.arbitrumHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Arbitrum"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Arbitrum"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.arbitrumHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .arbitrum) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .arbitrum) }
        ),
        .optimism: .init(
            isRunningHistory: { $0[historyRunFor: "Optimism"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Optimism"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Optimism") },
            historyLastUpdatedAt: { $0[historyRunFor: "Optimism"].lastUpdatedAt },
            historyWalletCount: { $0.optimismHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Optimism"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Optimism"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.optimismHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .optimism) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .optimism) }
        ),
        .bnb: .init(
            isRunningHistory: { $0[historyRunFor: "BNB Chain"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "BNB Chain"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "BNB Chain") },
            historyLastUpdatedAt: { $0[historyRunFor: "BNB Chain"].lastUpdatedAt },
            historyWalletCount: { $0.bnbHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "BNB Chain"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "BNB Chain"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.bnbHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .bnb) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .bnb) }
        ),
        .avalanche: .init(
            isRunningHistory: { $0[historyRunFor: "Avalanche"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Avalanche"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Avalanche") },
            historyLastUpdatedAt: { $0[historyRunFor: "Avalanche"].lastUpdatedAt },
            historyWalletCount: { $0.avalancheHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Avalanche"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Avalanche"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.avalancheHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .avalanche) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .avalanche) }
        ),
        .hyperliquid: .init(
            isRunningHistory: { $0[historyRunFor: "Hyperliquid"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Hyperliquid"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Hyperliquid") },
            historyLastUpdatedAt: { $0[historyRunFor: "Hyperliquid"].lastUpdatedAt },
            historyWalletCount: { $0.hyperliquidHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Hyperliquid"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Hyperliquid"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.hyperliquidHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .hyperliquid) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .hyperliquid) }
        ),
        .tron: .init(
            isRunningHistory: { $0[historyRunFor: "Tron"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Tron"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Tron") },
            historyLastUpdatedAt: { $0[historyRunFor: "Tron"].lastUpdatedAt },
            historyWalletCount: { $0.tronHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Tron"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Tron"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.tronHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .tron) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .tron) }
        ),
        .solana: .init(
            isRunningHistory: { $0[historyRunFor: "Solana"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Solana"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Solana") },
            historyLastUpdatedAt: { $0[historyRunFor: "Solana"].lastUpdatedAt },
            historyWalletCount: { $0.solanaHistoryDiagnosticsByWallet.count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Solana"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Solana"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0.solanaHistoryDiagnosticsByWallet.values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .solana) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .solana) }
        ),
        .cardano: .init(
            isRunningHistory: { $0[historyRunFor: "Cardano"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Cardano"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Cardano") },
            historyLastUpdatedAt: { $0[historyRunFor: "Cardano"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Cardano"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Cardano"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Cardano"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Cardano"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .cardano) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .cardano) }
        ),
        .xrp: .init(
            isRunningHistory: { $0[historyRunFor: "XRP Ledger"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "XRP Ledger"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "XRP Ledger") },
            historyLastUpdatedAt: { $0[historyRunFor: "XRP Ledger"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "XRP Ledger"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "XRP Ledger"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "XRP Ledger"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "XRP Ledger"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .xrp) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .xrp) }
        ),
        .stellar: .init(
            isRunningHistory: { $0[historyRunFor: "Stellar"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Stellar"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Stellar") },
            historyLastUpdatedAt: { $0[historyRunFor: "Stellar"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Stellar"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Stellar"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Stellar"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Stellar"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .stellar) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .stellar) }
        ),
        .monero: .init(
            isRunningHistory: { $0[historyRunFor: "Monero"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Monero"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Monero") },
            historyLastUpdatedAt: { $0[historyRunFor: "Monero"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Monero"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Monero"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Monero"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Monero"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .monero) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .monero) }
        ),
        .sui: .init(
            isRunningHistory: { $0[historyRunFor: "Sui"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Sui"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Sui") },
            historyLastUpdatedAt: { $0[historyRunFor: "Sui"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Sui"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Sui"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Sui"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Sui"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .sui) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .sui) }
        ),
        .aptos: .init(
            isRunningHistory: { $0[historyRunFor: "Aptos"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Aptos"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Aptos") },
            historyLastUpdatedAt: { $0[historyRunFor: "Aptos"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Aptos"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Aptos"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Aptos"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Aptos"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .aptos) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .aptos) }
        ),
        .ton: .init(
            isRunningHistory: { $0[historyRunFor: "TON"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "TON"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "TON") },
            historyLastUpdatedAt: { $0[historyRunFor: "TON"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "TON"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "TON"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "TON"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "TON"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .ton) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .ton) }
        ),
        .icp: .init(
            isRunningHistory: { $0[historyRunFor: "Internet Computer"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Internet Computer"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Internet Computer") },
            historyLastUpdatedAt: { $0[historyRunFor: "Internet Computer"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Internet Computer"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Internet Computer"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Internet Computer"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Internet Computer"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .icp) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .icp) }
        ),
        .near: .init(
            isRunningHistory: { $0[historyRunFor: "NEAR"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "NEAR"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "NEAR") },
            historyLastUpdatedAt: { $0[historyRunFor: "NEAR"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "NEAR"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "NEAR"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "NEAR"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "NEAR"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .near) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .near) }
        ),
        .polkadot: .init(
            isRunningHistory: { $0[historyRunFor: "Polkadot"].isRunning },
            isCheckingEndpoints: { $0[endpointHealthFor: "Polkadot"].isChecking },
            diagnosticsJSON: { $0.diagnosticsJSON(for: "Polkadot") },
            historyLastUpdatedAt: { $0[historyRunFor: "Polkadot"].lastUpdatedAt },
            historyWalletCount: { $0[simpleHistoryFor: "Polkadot"].count },
            endpointLastUpdatedAt: { $0[endpointHealthFor: "Polkadot"].lastUpdatedAt },
            endpointResults: { $0[endpointHealthFor: "Polkadot"].results.map { ($0.endpoint, $0.reachable, $0.detail) } },
            historySources: { $0[simpleHistoryFor: "Polkadot"].values.map(\.sourceUsed) },
            runHistoryDiagnostics: { await $0.runHistoryDiagnostics(for: .polkadot) },
            runEndpointDiagnostics: { await $0.runEndpointDiagnostics(for: .polkadot) }
        ),
    ]
    @MainActor var dispatch: StandardChainDiagnosticsDispatch { Self.dispatchTable[self]! }
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
    /// Keypool state now lives in core, so it is loaded rather than read
    /// synchronously — see `.task` below.
    @State private var cachedKeypoolDiagnostics: [AppState.ChainKeypoolDiagnostic] = []
    /// Operational events live in core now, so they load rather than read
    /// synchronously — same `.task` as the keypool rows.
    @State private var cachedOperationalEvents: [ChainOperationalEvent] = []
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
            isSelfTesting: { $0.selfTests(for: "Bitcoin").isRunning }, isRescanning: { $0.isRunningBitcoinRescan },
            selfTestTitle: "Run BTC Self-Tests", rescanTitle: "Run BTC Rescan", rescanInFlightTitle: "Rescanning BTC...",
            runSelfTests: { $0.runSelfTests(for: "Bitcoin") }, runRescan: { await $0.runBitcoinRescan() }
        ),
        .bitcoinCash: .init(
            isSelfTesting: { $0.selfTests(for: "Bitcoin Cash").isRunning }, isRescanning: { $0.isRunningBitcoinCashRescan },
            selfTestTitle: "Run BCH Self-Tests", rescanTitle: "Run BCH Rescan", rescanInFlightTitle: "Rescanning BCH...",
            runSelfTests: { $0.runSelfTests(for: "Bitcoin Cash") }, runRescan: { await $0.runBitcoinCashRescan() }
        ),
        .bitcoinSV: .init(
            isSelfTesting: { $0.selfTests(for: "Bitcoin SV").isRunning }, isRescanning: { $0.isRunningBitcoinSVRescan },
            selfTestTitle: "Run BSV Self-Tests", rescanTitle: "Run BSV Rescan", rescanInFlightTitle: "Rescanning BSV...",
            runSelfTests: { $0.runSelfTests(for: "Bitcoin SV") }, runRescan: { await $0.runBitcoinSVRescan() }
        ),
        .litecoin: .init(
            isSelfTesting: { $0.selfTests(for: "Litecoin").isRunning }, isRescanning: { $0.isRunningLitecoinRescan },
            selfTestTitle: "Run LTC Self-Tests", rescanTitle: "Run LTC Rescan", rescanInFlightTitle: "Rescanning LTC...",
            runSelfTests: { $0.runSelfTests(for: "Litecoin") }, runRescan: { await $0.runLitecoinRescan() }
        ),
        .dogecoin: .init(
            isSelfTesting: { $0.selfTests(for: "Dogecoin").isRunning }, isRescanning: { $0.isRunningDogecoinRescan },
            selfTestTitle: "Run DOGE Self-Tests", rescanTitle: "Run DOGE Rescan", rescanInFlightTitle: "Rescanning DOGE...",
            runSelfTests: { $0.runSelfTests(for: "Dogecoin") }, runRescan: { await $0.runDogecoinRescan() }
        ),
    ]

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
        }.task(id: chain.title) {
            cachedKeypoolDiagnostics = await store.chainKeypoolDiagnostics(for: chain.title)
            cachedOperationalEvents = await store.operationalEvents(for: chain.title)
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
            return trimmed.isEmpty ? AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainID: store.networkChainID(forFamily: "bitcoin")) : trimmed
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
