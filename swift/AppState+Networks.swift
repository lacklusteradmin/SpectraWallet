import Foundation

@MainActor
extension AppState {
    /// The title of the network a chain family is on — "Bitcoin",
    /// "Bitcoin Testnet4". The registry names chains, so this is a lookup
    /// rather than a family switch plus string surgery on a mode name.
    func selectedNetworkTitle(forFamilyName chainName: String) -> String {
        guard let family = Chain(displayName: chainName)?.id, !family.isEmpty else {
            return chainName
        }
        let chainId = selectedChainId(forFamily: family)
        return Chain(id: chainId)?.displayName ?? chainId
    }

    /// Switch a family's network. Core stores it — resetting the family's
    /// derivation state and history feed in the same command — and hands the
    /// settings back.
    func selectChainForFamily(_ chainId: String) {
        enqueueStateCommand(.selectChainForFamily(chainId: chainId))
    }
}
