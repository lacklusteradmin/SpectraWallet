import Foundation

// Aptos staking — `0x1::delegation_pool::add_stake` Move call.

@MainActor
struct AptosStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildAddStakePreview(walletAddress _: String, poolAddress _: String, amountOctas _: UInt64) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildUnlockPreview(walletAddress _: String, poolAddress _: String, amountOctas _: UInt64) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildWithdrawPreview(walletAddress _: String, poolAddress _: String, amountOctas _: UInt64) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
}
