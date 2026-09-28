import Foundation
import XCTest

@testable import Spectra

/// The staking chain list is `Chain.supportsStaking`, and core's dispatch
/// reads it. What is hand-written is the editorial copy: an APY estimate, an
/// unbonding period and a paragraph per chain. That is not a registry fact and
/// should not become one — but it does have to cover the chains the registry
/// offers, which is what these assert.
@MainActor
final class StakingChainTableTests: XCTestCase {
    func testEveryStakingChainHasADescriptor() {
        XCTAssertFalse(Chain.stakingChains.isEmpty)
        for chain in Chain.stakingChains {
            XCTAssertNotNil(
                chain.stakingDescriptor,
                "\(chain.displayName) is offered by the staking tab and has no copy to show")
        }
    }

    /// The inverse: copy for a chain the registry does not offer is a page no
    /// one can reach, and the tile it would render would claim an APY for a
    /// chain Spectra cannot stake on.
    func testNoDescriptorNamesAChainTheTabDoesNotOffer() {
        let offered = Set(Chain.stakingChains)
        for chain in Chain.all where chain.stakingDescriptor != nil {
            XCTAssertTrue(
                offered.contains(chain),
                "\(chain.displayName) has staking copy and is not in Chain.stakingChains")
        }
    }

    /// The picker is mainnets only. A testnet tile would route to a client
    /// built against mainnet endpoints and list mainnet validators.
    func testTheStakingPickerOffersMainnetsOnly() {
        for chain in Chain.stakingChains {
            XCTAssertFalse(chain.isTestnet, "\(chain.displayName) is a testnet and was offered")
        }
    }
}
