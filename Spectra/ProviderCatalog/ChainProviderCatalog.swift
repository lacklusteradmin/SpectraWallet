import Foundation

enum ChainProviderCatalog {
    static func endpoints(for chainName: String, roles: Set<AppEndpointRole> = []) -> [AppEndpointRecord] {
        AppEndpointDirectory.records.filter { record in
            guard record.chainName == chainName else { return false }
            guard !roles.isEmpty else { return true }
            return !record.roles.isDisjoint(with: roles)
        }
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
