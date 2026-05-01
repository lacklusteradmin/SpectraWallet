import Foundation

// Sui staking — `0x3::sui_system::request_add_stake` Move call.

@MainActor
struct SuiStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildAddStakePreview(walletAddress _: String, amountMist _: UInt64, validatorAddress _: String) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildWithdrawStakePreview(walletAddress _: String, stakedSuiObjectId _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
}
