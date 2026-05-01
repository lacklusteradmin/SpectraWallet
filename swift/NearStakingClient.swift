import Foundation

// NEAR staking — function calls to `staking_pool` contracts. Each validator
// runs its own pool contract at a `*.poolv1.near` or `*.pool.near` address.

@MainActor
struct NearStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildDepositAndStakePreview(walletAddress _: String, poolAccountId _: String, amountYoctoNear _: String) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildUnstakePreview(walletAddress _: String, poolAccountId _: String, amountYoctoNear _: String) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildWithdrawPreview(walletAddress _: String, poolAccountId _: String, amountYoctoNear _: String) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
}
