import Foundation

enum ChainProviderCatalog {
    static func endpoints(for chainName: String, roles: Set<AppEndpointRole> = []) -> [AppEndpointRecord] {
        AppEndpointDirectory.endpointRecords(
            for: chainName,
            roles: roles.isEmpty ? nil : roles
        )
    }

    static func broadcastEndpoints(for chainName: String) -> [AppEndpointRecord] {
        endpoints(for: chainName, roles: [.broadcast, .rpc])
    }

    static func readEndpoints(for chainName: String) -> [AppEndpointRecord] {
        endpoints(for: chainName, roles: [.read, .balance, .history, .utxo, .rpc])
    }

    static func explorerEndpoint(for chainName: String) -> AppEndpointRecord? {
        endpoints(for: chainName, roles: [.explorer]).first
    }
}
