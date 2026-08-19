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
    static func endpoint(_ id: String) throws -> String { try appCoreEndpointForId(id: id) }
    static func endpoints(for ids: [String]) throws -> [String] { try appCoreEndpointsForIds(ids: ids) }
    static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>, settingsVisibleOnly: Bool) throws -> [AppEndpointRecord] {
        try appCoreEndpointRecordsForChain(
            chainName: chainName, roleMask: roleMask(for: roles), settingsVisibleOnly: settingsVisibleOnly
        )
    }
    static func groupedSettingsEntries(for chainName: String) throws -> [AppEndpointGroupedSettingsEntry] {
        try appCoreGroupedSettingsEntries(chainName: chainName)
    }
    static func diagnosticsChecks(for chainName: String) throws -> [AppEndpointDiagnosticsCheck] {
        try appCoreDiagnosticsChecks(chainName: chainName)
    }
    static func transactionExplorerEntry(for chainName: String) throws -> AppEndpointExplorerEntry? {
        try appCoreTransactionExplorerEntry(chainName: chainName)
    }
    static func bitcoinEsploraBaseURLs(forChainID chainID: String) throws -> [String] { try appCoreBitcoinEsploraBaseUrls(chainId: chainID) }
    static func bitcoinWalletStoreDefaultBaseURLs(forChainID chainID: String) throws -> [String] { try appCoreBitcoinWalletStoreDefaultBaseUrls(chainId: chainID) }
    static func evmRPCEndpoints(for chainName: String) throws -> [String] { try appCoreEvmRpcEndpoints(chainName: chainName) }
    static func explorerSupplementalEndpoints(for chainName: String) throws -> [String] { try appCoreExplorerSupplementalEndpoints(chainName: chainName) }
    static func broadcastProviderOptions(for chainName: String) -> [ChainBroadcastProviderOption] {
        appCoreBroadcastProviderOptions(chainName: chainName).map {
            ChainBroadcastProviderOption(id: $0.id, title: $0.title)
        }
    }
    static func chainBackends() -> [ChainBackendRecord] {
        appCoreChainBackends().map {
            ChainBackendRecord(chainName: $0.chainName, supportedSymbols: $0.supportedSymbols, integrationState: $0.integrationState, supportsSeedImport: $0.supportsSeedImport, supportsBalanceRefresh: $0.supportsBalanceRefresh, supportsReceiveAddress: $0.supportsReceiveAddress, supportsSend: $0.supportsSend)
        }
    }
    static func liveChainNames() -> [String] { appCoreLiveChainNames() }
    private static func roleMask(for roles: Set<AppEndpointRole>) -> UInt32 {
        coreEndpointRoleMask(roles: roles.map(\.rawValue))
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
    /// Every Rust catalog lookup below is infallible at runtime: if the
    /// embedded JSON parses at boot, the queries never fail. Any throw
    /// indicates a corrupted bundle, which is a programmer error we crash on.
    private static func required<T>(_ context: @autoclosure () -> String, _ lookup: () throws -> T) -> T {
        do { return try lookup() } catch {
            preconditionFailure("Rust \(context()) failed: \(error.localizedDescription)")
        }
    }
    static func endpoint(_ id: String) -> String {
        required("endpoint lookup for id \(id)") { try WalletRustEndpointCatalogBridge.endpoint(id) }
    }
    static func endpoints(for ids: [String]) -> [String] {
        required("endpoint lookup for ids \(ids)") { try WalletRustEndpointCatalogBridge.endpoints(for: ids) }
    }
    static func endpointRecords(for chainName: String, roles: Set<AppEndpointRole>? = nil, settingsVisibleOnly: Bool = false) -> [AppEndpointRecord] {
        required("endpoint records for \(chainName)") {
            try WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: roles ?? [], settingsVisibleOnly: settingsVisibleOnly)
        }
    }
    static func groupedSettingsEntries(for chainName: String) -> [AppEndpointGroupedSettingsEntry] {
        required("grouped settings entries for \(chainName)") { try WalletRustEndpointCatalogBridge.groupedSettingsEntries(for: chainName) }
    }
    static func settingsEndpoints(for chainName: String) -> [String] { groupedSettingsEntries(for: chainName).flatMap(\.endpoints) }
    static func diagnosticsChecks(for chainName: String) -> [AppEndpointDiagnosticsCheck] {
        required("diagnostics checks for \(chainName)") { try WalletRustEndpointCatalogBridge.diagnosticsChecks(for: chainName) }
    }
    static func evmRPCEndpoints(for chainName: String) -> [String] {
        required("EVM RPC lookup for \(chainName)") { try WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName) }
    }
    static func explorerSupplementalEndpoints(for chainName: String) -> [String] {
        required("explorer endpoint lookup for \(chainName)") { try WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName) }
    }
    static func transactionExplorerBaseURL(for chainName: String) -> String? {
        required("transaction explorer lookup for \(chainName)") { try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.endpoint }
    }
    static func transactionExplorerLabel(for chainName: String) -> String? {
        required("transaction explorer label lookup for \(chainName)") { try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.label }
    }
    static func bitcoinEsploraBaseURLs(forChainID chainID: String) -> [String] {
        required("Bitcoin Esplora lookup for \(chainID)") { try WalletRustEndpointCatalogBridge.bitcoinEsploraBaseURLs(forChainID: chainID) }
    }
    static func bitcoinWalletStoreDefaultBaseURLs(forChainID chainID: String) -> [String] {
        required("Bitcoin wallet-store lookup for \(chainID)") { try WalletRustEndpointCatalogBridge.bitcoinWalletStoreDefaultBaseURLs(forChainID: chainID) }
    }
    static func transactionExplorerURL(for chainName: String, transactionHash: String) -> URL? {
        guard let urlString = (try? coreTransactionExplorerUrl(chainName: chainName, transactionHash: transactionHash)) ?? nil else { return nil }
        return URL(string: urlString)
    }
    static let liveChainNames = WalletRustEndpointCatalogBridge.liveChainNames()
    static let allBackends: [ChainBackendRecord] = loadChainBackends()
    static func backend(for chainName: String) -> ChainBackendRecord? { allBackends.first { $0.chainName == chainName } }
    static func supportsBalanceRefresh(for chainName: String) -> Bool { backend(for: chainName)?.supportsBalanceRefresh ?? false }
    static func supportsReceiveAddress(for chainName: String) -> Bool { backend(for: chainName)?.supportsReceiveAddress ?? false }
    static func supportsSend(for chainName: String) -> Bool { backend(for: chainName)?.supportsSend ?? false }
    private static func loadChainBackends() -> [ChainBackendRecord] {
        WalletRustEndpointCatalogBridge.chainBackends()
    }
}
