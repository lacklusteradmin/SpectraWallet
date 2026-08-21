import Foundation
enum WalletRustEndpointCatalogBridgeError: LocalizedError {
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreReturnedNullResponse: return "The Rust endpoint catalog returned an empty response."
        case .rustCoreFailed(let message): return message
        }}
}
typealias AppEndpointGroupedSettingsEntry = AppCoreGroupedSettingsEntry
typealias AppEndpointDiagnosticsCheck = AppCoreDiagnosticsCheck
typealias AppEndpointExplorerEntry = AppCoreExplorerEntry
typealias AppEndpointRecord = AppCoreEndpointRecord
enum WalletRustEndpointCatalogBridge {
    static func endpoints(for ids: [String]) throws -> [String] { try appCoreEndpointsForIds(ids: ids) }
    static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>, settingsVisibleOnly: Bool) throws -> [AppEndpointRecord] {
        try appCoreEndpointRecordsForChain(
            chainName: chainName, roles: roles.map(\.rawValue),
            settingsVisibleOnly: settingsVisibleOnly)
    }
    static func chainBackends() -> [ChainBackendRecord] {
        appCoreChainBackends().map {
            ChainBackendRecord(chainName: $0.chainName, supportedSymbols: $0.supportedSymbols, integrationState: $0.integrationState, supportsSeedImport: $0.supportsSeedImport, supportsBalanceRefresh: $0.supportsBalanceRefresh, supportsReceiveAddress: $0.supportsReceiveAddress, supportsSend: $0.supportsSend)
        }
    }
}
enum AppEndpointRole: String, Hashable, CaseIterable, Decodable {
    case read
    case balance
    case history
    case utxo
    case fee
    case broadcast
    case verification
    case rpc
    case explorer
    case backend
}
enum AppEndpointDirectory {
    /// The endpoint catalog, read once.
    ///
    /// It used to be eight exports, each taking a chain and re-walking the
    /// same table — so a settings screen made six calls for one chain. The
    /// catalog is static once the embedded JSON parses, which is why a
    /// `preconditionFailure` here is right: a throw means a corrupt bundle,
    /// not a runtime condition.
    private static let byChainName: [String: AppCoreChainEndpoints] = {
        do {
            return Dictionary(
                uniqueKeysWithValues: try appCoreChainEndpoints().map { ($0.chainName, $0) })
        } catch {
            preconditionFailure("Rust endpoint catalog failed: \(error.localizedDescription)")
        }
    }()
    private static let byChainID: [String: AppCoreChainEndpoints] = Dictionary(
        uniqueKeysWithValues: byChainName.values.map { ($0.chainId, $0) })

    private static func entry(_ chainName: String) -> AppCoreChainEndpoints? {
        byChainName[chainName]
    }

    static func endpoints(for ids: [String]) -> [String] {
        do { return try WalletRustEndpointCatalogBridge.endpoints(for: ids) } catch {
            preconditionFailure("Rust endpoint lookup for ids \(ids) failed: \(error.localizedDescription)")
        }
    }
    static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>? = nil, settingsVisibleOnly: Bool = false) -> [AppEndpointRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: roles ?? [], settingsVisibleOnly: settingsVisibleOnly)
        } catch {
            preconditionFailure("Rust endpoint records for \(chainName) failed: \(error.localizedDescription)")
        }
    }
    static func groupedSettingsEntries(for chainName: String) -> [AppEndpointGroupedSettingsEntry] {
        entry(chainName)?.groupedSettings ?? []
    }
    static func settingsEndpoints(for chainName: String) -> [String] { groupedSettingsEntries(for: chainName).flatMap(\.endpoints) }
    static func diagnosticsChecks(for chainName: String) -> [AppEndpointDiagnosticsCheck] {
        entry(chainName)?.diagnosticsChecks ?? []
    }
    static func evmRPCEndpoints(for chainName: String) -> [String] { entry(chainName)?.evmRpc ?? [] }
    static func explorerSupplementalEndpoints(for chainName: String) -> [String] {
        entry(chainName)?.explorerSupplemental ?? []
    }
    static func transactionExplorerBaseURL(for chainName: String) -> String? {
        entry(chainName)?.transactionExplorer?.endpoint
    }
    static func transactionExplorerLabel(for chainName: String) -> String? {
        entry(chainName)?.transactionExplorer?.label
    }
    static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        (entry(chainName)?.broadcastProviders ?? []).map {
            ChainBroadcastProviderOption(id: $0.id, title: $0.title)
        }
    }
    static func bitcoinEsploraBaseURLs(forChainID chainID: String) -> [String] {
        byChainID[chainID]?.bitcoinEsplora ?? []
    }
    static func bitcoinWalletStoreDefaultBaseURLs(forChainID chainID: String) -> [String] {
        byChainID[chainID]?.bitcoinWalletStore ?? []
    }
    static func transactionExplorerURL(for chainName: String, transactionHash: String) -> URL? {
        guard let urlString = (try? coreTransactionExplorerUrl(chainName: chainName, transactionHash: transactionHash)) ?? nil else { return nil }
        return URL(string: urlString)
    }
    static let allBackends: [ChainBackendRecord] = WalletRustEndpointCatalogBridge.chainBackends()
    /// The chains a build can actually talk to. Derived from the backends
    /// rather than asked for separately — `app_core_live_chain_names` was that
    /// list filtered by `integrationState`, which this side can do.
    static let liveChainNames: [String] = allBackends
        .filter { $0.integrationState == .live }
        .map(\.chainName)
    static func backend(for chainName: String) -> ChainBackendRecord? { allBackends.first { $0.chainName == chainName } }
    static func supportsBalanceRefresh(for chainName: String) -> Bool { backend(for: chainName)?.supportsBalanceRefresh ?? false }
    static func supportsReceiveAddress(for chainName: String) -> Bool { backend(for: chainName)?.supportsReceiveAddress ?? false }
    static func supportsSend(for chainName: String) -> Bool { backend(for: chainName)?.supportsSend ?? false }
}
