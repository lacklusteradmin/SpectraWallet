import Foundation

enum PolkadotProvider {
    static let endpointReliabilityNamespace = "polkadot.sidecar"
    static let sidecarBaseURLs = ChainBackendRegistry.PolkadotRuntimeEndpoints.sidecarBaseURLs
    static let rpcBaseURLs = ChainBackendRegistry.PolkadotRuntimeEndpoints.rpcBaseURLs

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.polkadotChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.polkadotChainName)
    }

    static func orderedSidecarEndpoints() -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: sidecarBaseURLs
        )
    }

    struct SidecarBalanceInfo: Decodable {
        let free: String?
        let nonce: Int?
    }

    struct TransactionMaterial: Decodable {
        struct At: Decodable {
            let hash: String
            let height: String
        }

        let at: At
        let genesisHash: String
        let specVersion: String
        let txVersion: String
    }

    struct FeeEstimateEnvelope: Decodable {
        let estimatedFee: String?
        let partialFee: String?
        let inclusionFee: FeeComponent?

        struct FeeComponent: Decodable {
            let baseFee: String?
            let lenFee: String?
            let adjustedWeightFee: String?
        }
    }

    struct BroadcastEnvelope: Decodable {
        let hash: String?
        let txHash: String?
    }
}
