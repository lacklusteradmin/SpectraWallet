import Foundation

// Solana staking — `StakeProgram` create / delegate / deactivate / withdraw.
// Wired through to `core/src/staking/chains/solana.rs` via UniFFI once the
// Rust side ships a real client; for now methods throw `notYetImplemented`.

@MainActor
struct SolanaStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildCreateAndDelegatePreview(walletAddress _: String, amountLamports _: UInt64, voteAccount _: String) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildDeactivatePreview(walletAddress _: String, stakeAccount _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
    func buildWithdrawPreview(walletAddress _: String, stakeAccount _: String, amountLamports _: UInt64) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
}
