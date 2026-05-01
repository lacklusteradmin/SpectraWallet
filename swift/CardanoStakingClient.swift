import Foundation

// Cardano staking — Shelley stake-address registration + delegation cert.
// Wired through to `core/src/staking/chains/cardano.rs` via UniFFI once the
// Rust side ships a real client; for now methods throw `notYetImplemented`.

@MainActor
struct CardanoStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func isStakeAddressRegistered(stakeAddress _: String) async throws -> Bool { throw StakingError.NotYetImplemented }
    func buildRegisterAndDelegatePreview(walletAddress _: String, poolId _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
    func buildClaimRewardsPreview(walletAddress _: String, amountLovelace _: UInt64) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
    func buildDeregisterPreview(walletAddress _: String) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
}
