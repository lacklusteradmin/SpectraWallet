import Foundation
import Synchronization

/// Immutable core metadata, indexed once. Identity normalization stays in core;
/// render passes reuse its answer rather than send a whole holding over FFI.
enum AssetPresentationCatalog {
    private struct HoldingKey: Hashable {
        let chain: String
        let standard: String
        let contract: String?
    }
    private static let identities = Mutex<[HoldingKey: String]>([:])
    private static let deployments = listAllBuiltinTokenDeployments()
    private static let artworkByDeployment = Dictionary(
        uniqueKeysWithValues: deployments.map { ($0.deploymentId, $0.artworkName) })

    static func identity(for holding: AssetHolding) -> String {
        let key = HoldingKey(chain: holding.chainName, standard: holding.tokenStandard,
                             contract: holding.contractAddress)
        return identities.withLock { cache in
            if let cached = cache[key] { return cached }
            let id = holdingIdentity(holding: holding)
            cache[key] = id
            return id
        }
    }
    static func artwork(deploymentId: String?) -> String {
        deploymentId.flatMap { artworkByDeployment[$0] } ?? ""
    }
}
