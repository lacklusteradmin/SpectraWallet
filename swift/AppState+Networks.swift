import Foundation

@MainActor
extension AppState {
    /// The title of the network a chain family is on — "Bitcoin",
    /// "Bitcoin Testnet4".
    func selectedNetworkTitle(forFamily family: Chain) -> String {
        selectedChain(forFamily: family).displayName
    }

    /// Switch a family's network. Core stores it — resetting the family's
    /// derivation state and history feed in the same command — and hands the
    /// settings back.
    func selectChainForFamily(_ chain: Chain) {
        sendStateCommand(.selectChainForFamily(chainId: chain))
    }
}
