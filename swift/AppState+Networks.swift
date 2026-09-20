import Foundation

@MainActor
extension AppState {
    /// The title of the network a chain family is on — "Bitcoin",
    /// "Bitcoin Testnet4". The registry names chains, so this is a lookup
    /// rather than a family switch plus string surgery on a mode name.
    func displayChainTitle(for chainName: String) -> String {
        guard let family = Chain(displayName: chainName)?.id, !family.isEmpty else {
            return chainName
        }
        let chainId = selectedChainId(forFamily: family)
        return Chain(id: chainId)?.displayName ?? chainId
    }
    /// The network a wallet is on — "Bitcoin Testnet4" — which is its own,
    /// whatever the app is set to now.
    func displayChainTitle(for wallet: WalletView) -> String {
        Chain(id: wallet.chainId)?.displayName ?? wallet.selectedChain
    }
    /// A transaction names the network it was on when it was recorded.
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        transaction.chainName
    }
    func supportsDeepUTXODiscovery(chainName: String) -> Bool { (Chain(displayName: chainName)?.supportsDeepUTXODiscovery ?? false) }
    /// The networks this chain family offers, mainnet first. Core answers, so
    /// no front end enumerates them.
    nonisolated func networkChoices(forChainId chainId: String) -> [NetworkChoice] {
        (Chain(id: chainId)?.networkChoices ?? [])
    }
}
