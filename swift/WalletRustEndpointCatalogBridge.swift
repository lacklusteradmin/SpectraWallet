import Foundation
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

    /// The chains the catalog actually has endpoints for.
    ///
    /// The endpoints screen used to filter on `supports_endpoint_catalog`, a
    /// per-chain flag in `chains.toml` that was `false` for exactly one chain —
    /// Bitcoin SV — which has three `whatsonchain` records in the catalog. So
    /// the flag did not describe the catalog, it hid part of it. Asking the
    /// catalog cannot disagree with the catalog.
    static func hasEndpoints(_ chainName: String) -> Bool {
        guard let entry = entry(chainName) else { return false }
        return !entry.groupedSettings.isEmpty
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

    /// A chain's RPC endpoints followed by any explorer endpoints that
    /// supplement them, deduplicated.
    ///
    /// Only a handful of chains have a supplement; for the rest the second
    /// list is empty, so asking for both costs nothing and stops the next
    /// chain that gains one from needing a case anywhere. Two view files each
    /// had a private copy of this.
    static func evmEndpointsWithSupplemental(for chainName: String) -> [String] {
        var endpoints = evmRPCEndpoints(for: chainName)
        for endpoint in explorerSupplementalEndpoints(for: chainName)
        where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        return endpoints
    }
    static func transactionExplorerLabel(for chainName: String) -> String? {
        entry(chainName)?.transactionExplorer?.label
    }
    static func bitcoinEsploraBaseURLs(forChainID chainID: String) -> [String] {
        byChainID[chainID]?.bitcoinEsplora ?? []
    }
    static func bitcoinWalletStoreDefaultBaseURLs(forChainID chainID: String) -> [String] {
        byChainID[chainID]?.bitcoinWalletStore ?? []
    }
    /// Built from the explorer record this bridge already holds.
    ///
    /// Was an export whose only content beyond `endpoint + hash` was a
    /// `chain_name == "Aptos"` branch appending `?network=mainnet`. That is a
    /// property of the explorer's URL format, so it is a catalog column now
    /// and every chain's URL is the same expression.
    static func transactionExplorerURL(for chainName: String, transactionHash: String) -> URL? {
        guard let explorer = entry(chainName)?.transactionExplorer else { return nil }
        return URL(string: "\(explorer.endpoint)\(transactionHash)\(explorer.txSuffix)")
    }
    /// Every chain the registry knows.
    static let liveChainNames: [String] = Chain.all.map(\.displayName)
}
