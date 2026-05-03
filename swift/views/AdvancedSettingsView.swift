import Foundation
import SwiftUI
import UniformTypeIdentifiers
struct AdvancedSettingsView: View {
    @Bindable var store: AppState
    @State private var isRunningMaintenance = false
    @State private var maintenanceNotice: String?
    @State private var isShowingDiagnosticsImporter = false
    @State private var isShowingDiagnosticsExportsBrowser = false
    @State private var lastExportedDiagnosticsURL: URL?
    private let singleChainRefreshNames = [
        "Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid",
        "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar",
    ]
    var body: some View {
        @Bindable var preferences = store.preferences
        return Form {
            Section(AppLocalization.string("Security")) {
                Toggle(
                    AppLocalization.string("Biometric Confirmation For Send Actions"),
                    isOn: Binding(
                        get: { preferences.requireBiometricForSendActions }, set: { preferences.requireBiometricForSendActions = $0 }
                    )
                )
                Toggle(
                    AppLocalization.string("Strict RPC Only (Disable Ledger Fallback)"),
                    isOn: $preferences.useStrictRPCOnly
                )
                Text(AppLocalization.string("When enabled, balances only come from live RPC responses.")).font(.caption).foregroundStyle(
                    .secondary)
                Button(AppLocalization.string("Lock App Now")) {
                    store.isAppLocked = true
                    maintenanceNotice = AppLocalization.string("App locked.")
                }
            }
            Section(AppLocalization.string("Quick Maintenance")) {
                Button(
                    isRunningMaintenance
                        ? AppLocalization.string("Refreshing...") : AppLocalization.string("Refresh Now (Balances + History)")
                ) {
                    Task {
                        isRunningMaintenance = true
                        await store.performUserInitiatedRefresh()
                        isRunningMaintenance = false
                        maintenanceNotice = AppLocalization.string("Manual refresh completed.")
                    }
                }.disabled(isRunningMaintenance)
                Button(
                    isRunningMaintenance
                        ? AppLocalization.string("Running Diagnostics...") : AppLocalization.string("Run All Endpoint Checks")
                ) {
                    Task {
                        isRunningMaintenance = true
                        await store.runBitcoinEndpointReachabilityDiagnostics()
                        await store.runEndpointDiagnostics(for: .bitcoinCash)
                        await store.runEndpointDiagnostics(for: .litecoin)
                        await store.runEthereumEndpointReachabilityDiagnostics()
                        await store.runEndpointDiagnostics(for: .ethereumClassic)
                        await store.runEndpointDiagnostics(for: .arbitrum)
                        await store.runEndpointDiagnostics(for: .optimism)
                        await store.runBNBEndpointReachabilityDiagnostics()
                        await store.runEndpointDiagnostics(for: .avalanche)
                        await store.runEndpointDiagnostics(for: .hyperliquid)
                        await store.runEndpointDiagnostics(for: .tron)
                        await store.runEndpointDiagnostics(for: .solana)
                        await store.runEndpointDiagnostics(for: .cardano)
                        await store.runEndpointDiagnostics(for: .xrp)
                        await store.runMoneroEndpointReachabilityDiagnostics()
                        await store.runEndpointDiagnostics(for: .sui)
                        await store.runEndpointDiagnostics(for: .aptos)
                        await store.runEndpointDiagnostics(for: .ton)
                        await store.runEndpointDiagnostics(for: .icp)
                        await store.runNearEndpointReachabilityDiagnostics()
                        await store.runPolkadotEndpointReachabilityDiagnostics()
                        await store.runEndpointDiagnostics(for: .stellar)
                        isRunningMaintenance = false
                        maintenanceNotice = AppLocalization.string("Endpoint checks completed.")
                    }
                }.disabled(isRunningMaintenance)
                ForEach(singleChainRefreshNames, id: \.self) { chainName in
                    Button(refreshButtonTitle(for: chainName)) {
                        refreshSingleChain(chainName)
                    }.disabled(isRunningMaintenance)
                }
                if let maintenanceNotice { Text(maintenanceNotice).font(.caption).foregroundStyle(.secondary) }
            }
            Section(AppLocalization.string("Diagnostics Bundle")) {
                Button(AppLocalization.string("Export Diagnostics Bundle")) {
                    do {
                        let url = try store.exportDiagnosticsBundle()
                        lastExportedDiagnosticsURL = url
                        maintenanceNotice = AppLocalization.format("Diagnostics exported to %@", url.lastPathComponent)
                    } catch {
                        maintenanceNotice = AppLocalization.format("Export failed: %@", error.localizedDescription)
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
            Section(AppLocalization.string("Status")) {
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                if let pendingRefresh = store.pendingTransactionRefreshStatusText {
                    Text(pendingRefresh).font(.caption).foregroundStyle(.secondary)
                }
                Text(AppLocalization.format("Wallets: %lld", store.wallets.count)).font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.format("Tracked token checks enabled: %lld", store.tokenPreferences.filter { $0.isEnabled }.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(AppLocalization.string("Advanced")).sheet(isPresented: $isShowingDiagnosticsExportsBrowser) {
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
                maintenanceNotice = AppLocalization.format(
                    "Imported diagnostics bundle (%@).", payload.generatedAt.formatted(date: .abbreviated, time: .shortened))
            } catch {
                maintenanceNotice = AppLocalization.format("Import failed: %@", error.localizedDescription)
            }
        }
    }
    private func refreshSingleChain(_ chainName: String) {
        Task {
            isRunningMaintenance = true
            await store.performUserInitiatedRefresh(forChain: chainName)
            isRunningMaintenance = false
            maintenanceNotice = AppLocalization.format("%@ refresh completed.", chainName)
        }
    }
    private func refreshButtonTitle(for chainName: String, label: String? = nil) -> String {
        let title = label ?? chainName
        return isRunningMaintenance ? AppLocalization.format("Refreshing %@...", title) : AppLocalization.format("Refresh %@", title)
    }
}
