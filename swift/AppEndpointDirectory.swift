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
    private static let byChainId: [Chain: AppCoreChainEndpoints] = Dictionary(
        uniqueKeysWithValues: ((try? loaded.get()) ?? []).map { ($0.chainId, $0) })

    static func groupedSettingsEntries(for chain: Chain) -> [AppEndpointGroupedSettingsEntry] {
        byChainId[chain]?.groupedSettings ?? []
    }
}
