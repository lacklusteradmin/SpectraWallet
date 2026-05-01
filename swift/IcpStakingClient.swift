import Foundation

// Internet Computer staking — neuron lock-ups via the NNS governance canister.
// Min 1 ICP per neuron; min dissolve delay for voting rewards is 6 months
// (max is 8 years for max maturity bonus).

@MainActor
struct IcpStakingClient {
    func fetchValidators() async throws -> [StakingValidator] { throw StakingError.NotYetImplemented }
    func fetchPositions(walletAddress _: String) async throws -> [StakingPosition] { throw StakingError.NotYetImplemented }
    func buildCreateNeuronPreview(walletAddress _: String, amountE8s _: UInt64, dissolveDelayMonths _: UInt32) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildIncreaseDissolveDelayPreview(walletAddress _: String, neuronId _: UInt64, additionalMonths _: UInt32) async throws
        -> StakingActionPreview
    { throw StakingError.NotYetImplemented }
    func buildStartDissolvingPreview(walletAddress _: String, neuronId _: UInt64) async throws -> StakingActionPreview {
        throw StakingError.NotYetImplemented
    }
    func buildDisbursePreview(walletAddress _: String, neuronId _: UInt64, amountE8s _: UInt64) async throws -> StakingActionPreview
    {
        throw StakingError.NotYetImplemented
    }
}
