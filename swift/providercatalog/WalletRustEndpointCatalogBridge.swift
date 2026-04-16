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
struct AppEndpointGroupedSettingsEntry: Decodable, Sendable {
    let title: String
    let endpoints: [String]
}
struct AppEndpointDiagnosticsCheck: Decodable, Sendable {
    let endpoint: String
    let probeURL: String
}
struct AppEndpointExplorerEntry: Decodable, Sendable {
    let endpoint: String
    let label: String
}
enum WalletRustEndpointCatalogBridge {
    nonisolated static func endpoint(_ id: String) throws -> String { try decodePayload(String.self, json: try appCoreEndpointForIdJson(id: id)) }
    nonisolated static func endpoints(for ids: [String]) throws -> [String] { try decodePayload([String].self, json: try appCoreEndpointsForIdsJson(idsJson: encodeJSONString(ids))) }
    nonisolated static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>, settingsVisibleOnly: Bool) throws -> [AppEndpointRecord] {
        try decodePayload(
            [AppEndpointRecord].self, json: try appCoreEndpointRecordsForChainJson(
                chainName: chainName, roleMask: roleMask(for: roles), settingsVisibleOnly: settingsVisibleOnly
            )
        )
    }
    nonisolated static func groupedSettingsEntries(for chainName: String) throws -> [AppEndpointGroupedSettingsEntry] { try decodePayload([AppEndpointGroupedSettingsEntry].self, json: try appCoreGroupedSettingsEntriesJson(chainName: chainName)) }
    nonisolated static func diagnosticsChecks(for chainName: String) throws -> [AppEndpointDiagnosticsCheck] { try decodePayload([AppEndpointDiagnosticsCheck].self, json: try appCoreDiagnosticsChecksJson(chainName: chainName)) }
    nonisolated static func transactionExplorerEntry(for chainName: String) throws -> AppEndpointExplorerEntry? { try decodePayload(AppEndpointExplorerEntry?.self, json: try appCoreTransactionExplorerEntryJson(chainName: chainName)) }
    nonisolated static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try decodePayload([String].self, json: try appCoreBitcoinEsploraBaseUrlsJson(network: networkMode.rawValue)) }
    nonisolated static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] { try decodePayload([String].self, json: try appCoreBitcoinWalletStoreDefaultBaseUrlsJson(network: networkMode.rawValue)) }
    nonisolated static func evmRPCEndpoints(for chainName: String) throws -> [String] { try decodePayload([String].self, json: try appCoreEvmRpcEndpointsJson(chainName: chainName)) }
    nonisolated static func explorerSupplementalEndpoints(for chainName: String) throws -> [String] { try decodePayload([String].self, json: try appCoreExplorerSupplementalEndpointsJson(chainName: chainName)) }
    nonisolated static func broadcastProviderOptions(for chainName: String) throws -> [ChainBroadcastProviderOption] { try decodePayload([ChainBroadcastProviderOption].self, json: try appCoreBroadcastProviderOptionsJson(chainName: chainName)) }
    nonisolated static func chainBackends() throws -> [ChainBackendRecord] { try decodePayload([ChainBackendRecord].self, json: try appCoreChainBackendsJson()) }
    nonisolated static func liveChainNames() throws -> [String] { try decodePayload([String].self, json: try appCoreLiveChainNamesJson()) }
    nonisolated static func appChainDescriptors() throws -> [AppChainDescriptor] { try decodePayload([AppChainDescriptor].self, json: try appCoreAppChainDescriptorsJson()) }
    nonisolated private static func decodePayload<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        guard let payload = json.data(using: .utf8), !payload.isEmpty else { throw WalletRustEndpointCatalogBridgeError.invalidPayload("Rust endpoint catalog returned an empty payload.") }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustEndpointCatalogBridgeError.invalidPayload(error.localizedDescription)
        }}
    nonisolated private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { throw WalletRustEndpointCatalogBridgeError.invalidPayload("Encoded endpoint catalog request was not valid UTF-8 JSON.") }
        return json
    }
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
