import Foundation
typealias AppEndpointGroupedSettingsEntry = AppCoreGroupedSettingsEntry
enum AppEndpointDirectory {
    /// The endpoint catalog, read once, or the error screens should display.
    /// Core networking uses its own catalog.
    private static let loaded: Result<[AppCoreChainEndpoints], Error> = Result { try chainEndpoints() }
    /// Why the catalog could not be read, for a screen to show.
    static var loadError: String? {
        if case .failure(let error) = loaded { return error.localizedDescription }
        return nil
    }
    private static let byChainId: [String: AppCoreChainEndpoints] = Dictionary(
        uniqueKeysWithValues: ((try? loaded.get()) ?? []).map { ($0.chainId, $0) })

    private static func entry(_ chainId: String) -> AppCoreChainEndpoints? {
        byChainId[chainId]
    }

    /// The chains with endpoints in the catalog.
    static func hasEndpoints(_ chainId: String) -> Bool {
        guard let entry = entry(chainId) else { return false }
        return !entry.groupedSettings.isEmpty
    }

    /// What the catalog says one endpoint is, as a line a settings row can
    /// show under the URL — "evm-json-rpc · Balance · Fees · Broadcast".
    ///
    /// `nil` for an endpoint the catalog does not list, which is the honest
    /// answer for one the user typed in themselves.
    static func tagSummary(for endpoint: String) -> String? {
        guard let tag = endpointTag(endpoint: endpoint) else { return nil }
        let parts = [tag.api].compactMap { $0 } + tag.capabilities.map { AppLocalization.string("endpointCapability.\($0)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func groupedSettingsEntries(for chainId: String) -> [AppEndpointGroupedSettingsEntry] {
        entry(chainId)?.groupedSettings ?? []
    }
    static func settingsEndpoints(for chainId: String) -> [String] { groupedSettingsEntries(for: chainId).flatMap(\.endpoints) }
    static func serviceEndpoints(for chainId: String) -> [String] { entry(chainId)?.serviceEndpoints ?? [] }
    static func backends(for chainId: String) -> [String] { entry(chainId)?.backends ?? [] }
    static func evmRPCEndpoints(for chainId: String) -> [String] { entry(chainId)?.evmRpc ?? [] }
    static func transactionExplorerLabel(for chainId: String) -> String? {
        entry(chainId)?.transactionExplorer?.label
    }
    static func bitcoinEsploraBaseURLs(forChainId chainId: String) -> [String] {
        byChainId[chainId]?.bitcoinEsplora ?? []
    }
    /// Build the transaction URL from the explorer record's URL format.
    static func transactionExplorerURL(for chainId: String, transactionHash: String) -> URL? {
        guard let explorer = entry(chainId)?.transactionExplorer else { return nil }
        return URL(string: "\(explorer.endpoint)\(transactionHash)\(explorer.txSuffix)")
    }
}
