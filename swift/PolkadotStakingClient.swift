import Foundation

// Polkadot staking — direct nomination OR nomination pools.
// Direct path: `staking::bond` + `staking::nominate` (≥250 DOT min).
// Pool path: `nomination_pools::join` (no minimum).

@MainActor
struct PolkadotStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchNominationPools() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildBondAndNominatePreview(walletAddress _: String, amountPlanck _: String, validatorAddresses _: [String]) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildJoinPoolPreview(walletAddress _: String, amountPlanck _: String, poolId _: UInt32) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildUnbondPreview(walletAddress _: String, amountPlanck _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
    func buildWithdrawUnbondedPreview(walletAddress _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
}
