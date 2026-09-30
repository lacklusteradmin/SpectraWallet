import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
typealias TokenPreferenceEntry = CoreTokenPreferenceEntry
nonisolated extension CoreTokenPreferenceEntry: Identifiable {
    public var id: String { token.deploymentId }
    /// The chain hosting this token.
    var hostingChain: Chain? { token.chainId.hostsTokens ? token.chainId : nil }
}

extension Coin {
    /// A chain's network artwork and catalog colour.
    static func nativeChainBadge(for chain: Chain?) -> (artworkName: String?, color: Color)? {
        guard let entry = chain?.entry else { return nil }
        return (entry.artworkName, entry.color.color)
    }
    var artworkName: String { AssetPresentationCatalog.artwork(deploymentId: holdingKey) }

}
