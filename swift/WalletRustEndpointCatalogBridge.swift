import Foundation
typealias AppEndpointGroupedSettingsEntry = AppCoreGroupedSettingsEntry
enum AppEndpointDirectory {
    /// The endpoint catalog, read once, or why it could not be.
    ///
    /// A failure here used to be a `preconditionFailure` — and so did a lookup
    /// by record id, and one by chain — so a catalog that did not load took
    /// the whole app down from whichever settings row asked first. Core does
    /// its networking from its own copy; this one feeds screens that list
    /// endpoints, and a screen that cannot list them says so.
    private static let loaded: Result<[AppCoreChainEndpoints], Error> = Result { try appCoreChainEndpoints() }
    /// Why the catalog could not be read, for a screen to show.
    static var loadError: String? {
        if case .failure(let error) = loaded { return error.localizedDescription }
        return nil
    }
    private static let byChainName: [String: AppCoreChainEndpoints] = Dictionary(
        uniqueKeysWithValues: ((try? loaded.get()) ?? []).map { ($0.chainName, $0) })
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

    static func groupedSettingsEntries(for chainName: String) -> [AppEndpointGroupedSettingsEntry] {
        entry(chainName)?.groupedSettings ?? []
    }
    static func settingsEndpoints(for chainName: String) -> [String] { groupedSettingsEntries(for: chainName).flatMap(\.endpoints) }
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
}
