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

    static func groupedSettingsEntries(for chainId: String) -> [AppEndpointGroupedSettingsEntry] {
        entry(chainId)?.groupedSettings ?? []
    }
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
