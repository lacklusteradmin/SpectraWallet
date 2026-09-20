import Foundation
typealias AppEndpointGroupedSettingsEntry = AppCoreGroupedSettingsEntry
enum AppEndpointDirectory {
    /// The endpoint catalog, read once, or the error screens should display.
    /// Core networking uses its own catalog.
    private static let loaded: Result<[AppCoreChainEndpoints], Error> = Result { try appCoreChainEndpoints() }
    /// Why the catalog could not be read, for a screen to show.
    static var loadError: String? {
        if case .failure(let error) = loaded { return error.localizedDescription }
        return nil
    }
    private static let byChainID: [String: AppCoreChainEndpoints] = Dictionary(
        uniqueKeysWithValues: ((try? loaded.get()) ?? []).map { ($0.chainId, $0) })

    private static func entry(_ networkID: String) -> AppCoreChainEndpoints? {
        byChainID[networkID]
    }

    /// The chains with endpoints in the catalog.
    static func hasEndpoints(_ networkID: String) -> Bool {
        guard let entry = entry(networkID) else { return false }
        return !entry.groupedSettings.isEmpty
    }

    /// What the catalog says one endpoint is, as a line a settings row can
    /// show under the URL — "Node · Balance · Fees · Broadcast".
    ///
    /// `nil` for an endpoint the catalog does not list, which is the honest
    /// answer for one the user typed in themselves.
    static func tagSummary(for endpoint: String) -> String? {
        guard let tag = appCoreEndpointTag(endpoint: endpoint) else { return nil }
        let kind = AppLocalization.string("endpointKind.\(tag.kind)")
        let parts = [kind] + tag.capabilities.map { AppLocalization.string("endpointCapability.\($0)") }
        return parts.joined(separator: " · ")
    }

    static func groupedSettingsEntries(for networkID: String) -> [AppEndpointGroupedSettingsEntry] {
        entry(networkID)?.groupedSettings ?? []
    }
    static func settingsEndpoints(for networkID: String) -> [String] { groupedSettingsEntries(for: networkID).flatMap(\.endpoints) }
    static func evmRPCEndpoints(for networkID: String) -> [String] { entry(networkID)?.evmRpc ?? [] }
    static func explorerSupplementalEndpoints(for networkID: String) -> [String] {
        entry(networkID)?.explorerSupplemental ?? []
    }

    /// A chain's RPC endpoints followed by any explorer endpoints that
    /// supplement them, deduplicated.
    ///
    /// Only a handful of chains have a supplement; for the rest the second
    /// list is empty, so asking for both costs nothing and stops the next
    /// chain that gains one from needing a case anywhere. Two view files each
    /// had a private copy of this.
    static func evmEndpointsWithSupplemental(for networkID: String) -> [String] {
        var endpoints = evmRPCEndpoints(for: networkID)
        for endpoint in explorerSupplementalEndpoints(for: networkID)
        where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        return endpoints
    }
    static func transactionExplorerLabel(for networkID: String) -> String? {
        entry(networkID)?.transactionExplorer?.label
    }
    static func bitcoinEsploraBaseURLs(forChainID chainID: String) -> [String] {
        byChainID[chainID]?.bitcoinEsplora ?? []
    }
    /// Build the transaction URL from the explorer record's URL format.
    static func transactionExplorerURL(for networkID: String, transactionHash: String) -> URL? {
        guard let explorer = entry(networkID)?.transactionExplorer else { return nil }
        return URL(string: "\(explorer.endpoint)\(transactionHash)\(explorer.txSuffix)")
    }
}
