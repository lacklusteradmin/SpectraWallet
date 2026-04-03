import Foundation
import SolanaSwift

enum SolanaProvider {
    static let endpointReliabilityNamespace = "solana.rpc"
    static let balanceRPCBaseURLs = ChainBackendRegistry.SolanaRuntimeEndpoints.balanceRPCBaseURLs
    static let sendRPCBaseURLs = ChainBackendRegistry.SolanaRuntimeEndpoints.sendRPCBaseURLs

    static func balanceEndpointCatalog() -> [String] {
        balanceRPCBaseURLs
    }

    static func sendEndpointCatalog() -> [String] {
        sendRPCBaseURLs
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.solanaChainName)
    }

    static func rpcClient(baseURL: String) -> SolanaAPIClient {
        JSONRPCAPIClient(endpoint: APIEndPoint(address: baseURL, network: .mainnetBeta))
    }

    static func orderedSendRPCBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        let candidates = filteredSendRPCBaseURLs(providerIDs: providerIDs)
        return ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: candidates
        )
    }

    static func filteredSendRPCBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else {
            return sendRPCBaseURLs
        }
        return sendRPCBaseURLs.filter { endpoint in
            switch endpoint {
            case "https://api.mainnet-beta.solana.com":
                return providerIDs.contains("solana-mainnet-beta")
            case "https://rpc.ankr.com/solana":
                return providerIDs.contains("solana-ankr")
            default:
                return false
            }
        }
    }
}
