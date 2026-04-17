import Foundation
enum WalletRustEndpointCatalogBridgeError: LocalizedError {
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case invalidPayload(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreReturnedNullResponse: return "The Rust endpoint catalog returned an empty response."
        case .rustCoreFailed(let message): return message
        case .invalidPayload(let message): return message
        }}
}
struct AppEndpointGroupedSettingsEntry: Sendable {
    let title: String
    let endpoints: [String]
}
struct AppEndpointDiagnosticsCheck: Sendable {
    let endpoint: String
    let probeURL: String
}
struct AppEndpointExplorerEntry: Sendable {
    let endpoint: String
    let label: String
}
enum WalletRustEndpointCatalogBridge {
    nonisolated static func endpoint(_ id: String) throws -> String { try appCoreEndpointForId(id: id) }
    nonisolated static func endpoints(for ids: [String]) throws -> [String] { try appCoreEndpointsForIds(ids: ids) }
    nonisolated static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>, settingsVisibleOnly: Bool) throws -> [AppEndpointRecord] {
        try decodePayload(
            [AppEndpointRecord].self, json: try appCoreEndpointRecordsForChainJson(
                chainName: chainName, roleMask: roleMask(for: roles), settingsVisibleOnly: settingsVisibleOnly
            )
        )
    }
    nonisolated static func groupedSettingsEntries(for chainName: String) throws -> [AppEndpointGroupedSettingsEntry] {
        try appCoreGroupedSettingsEntries(chainName: chainName).map {
            AppEndpointGroupedSettingsEntry(title: $0.title, endpoints: $0.endpoints)
        }
    }
    nonisolated static func diagnosticsChecks(for chainName: String) throws -> [AppEndpointDiagnosticsCheck] {
        try appCoreDiagnosticsChecks(chainName: chainName).map {
            AppEndpointDiagnosticsCheck(endpoint: $0.endpoint, probeURL: $0.probeUrl)
        }
    }
    nonisolated static func transactionExplorerEntry(for chainName: String) throws -> AppEndpointExplorerEntry? {
        try appCoreTransactionExplorerEntry(chainName: chainName).map {
            AppEndpointExplorerEntry(endpoint: $0.endpoint, label: $0.label)
        }
    }
    nonisolated static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try appCoreBitcoinEsploraBaseUrls(network: networkMode.rawValue) }
    nonisolated static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try appCoreBitcoinWalletStoreDefaultBaseUrls(network: networkMode.rawValue) }
    nonisolated static func evmRPCEndpoints(for chainName: String) throws -> [String] { try appCoreEvmRpcEndpoints(chainName: chainName) }
    nonisolated static func explorerSupplementalEndpoints(for chainName: String) throws -> [String] { try appCoreExplorerSupplementalEndpoints(chainName: chainName) }
    nonisolated static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        appCoreBroadcastProviderOptions(chainName: chainName).map {
            ChainBroadcastProviderOption(id: $0.id, title: $0.title)
        }
    }
    nonisolated static func chainBackends() throws -> [ChainBackendRecord] {
        try appCoreChainBackends().map {
            guard let state = ChainIntegrationState(rawValue: $0.integrationState) else {
                throw WalletRustEndpointCatalogBridgeError.invalidPayload("Unknown integration state: \($0.integrationState)")
            }
            return ChainBackendRecord(chainName: $0.chainName, supportedSymbols: $0.supportedSymbols, integrationState: state, supportsSeedImport: $0.supportsSeedImport, supportsBalanceRefresh: $0.supportsBalanceRefresh, supportsReceiveAddress: $0.supportsReceiveAddress, supportsSend: $0.supportsSend)
        }
    }
    nonisolated static func liveChainNames() -> [String] { appCoreLiveChainNames() }
    nonisolated static func appChainDescriptors() throws -> [AppChainDescriptor] {
        try appCoreAppChainDescriptors().compactMap {
            guard let chainID = AppChainID(rawValue: $0.id) else { return nil }
            return AppChainDescriptor(id: chainID, chainName: $0.chainName, shortLabel: $0.shortLabel, nativeSymbol: $0.nativeSymbol, searchKeywords: $0.searchKeywords, supportsDiagnostics: $0.supportsDiagnostics, supportsEndpointCatalog: $0.supportsEndpointCatalog, isEVM: $0.isEvm)
        }
    }
    nonisolated private static func decodePayload<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        guard let payload = json.data(using: .utf8), !payload.isEmpty else { throw WalletRustEndpointCatalogBridgeError.invalidPayload("Rust endpoint catalog returned an empty payload.") }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustEndpointCatalogBridgeError.invalidPayload(error.localizedDescription)
        }}
    nonisolated private static func roleMask(for roles: Set<AppEndpointRole>) -> UInt32 {
        roles.reduce(into: UInt32.zero) { partialResult, role in
            let bit: UInt32 = switch role {
            case .read: 1 << 0
            case .balance: 1 << 1
            case .history: 1 << 2
            case .utxo: 1 << 3
            case .fee: 1 << 4
            case .broadcast: 1 << 5
            case .verification: 1 << 6
            case .rpc: 1 << 7
            case .explorer: 1 << 8
            case .backend: 1 << 9
            }
            partialResult |= bit
        }}
}
