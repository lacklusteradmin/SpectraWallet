import Foundation
import Testing

@testable import Spectra

/// The staking tab renders core's table. Core refuses to load one that misses
/// a staking chain or names another; these check the table arrives intact.
@MainActor
struct StakingChainTableTests {
    @Test func everyStakingRowResolvesForItsDetailPage() {
        #expect(!CoreReferenceTables.stakingChains.isEmpty)
        for entry in CoreReferenceTables.stakingChains {
            #expect(CoreReferenceTables.stakingEntry(for: entry.chain)?.chain == entry.chain)
        }
    }

    /// The picker is mainnets only. A testnet tile would route to a client
    /// built against mainnet endpoints and list mainnet validators.
    @Test func theStakingPickerOffersMainnetsOnly() {
        for entry in CoreReferenceTables.stakingChains {
            #expect(!entry.chain.isTestnet, "\(entry.chain.displayName) is a testnet and was offered")
        }
    }
}
