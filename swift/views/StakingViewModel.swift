import Foundation

@MainActor @Observable final class StakingViewModel {
    let chain: Chain

    var validators: [StakingValidator] = []
    var positions: [StakingPosition] = []
    var nominationPools: [StakingValidator] = []  // Polkadot only
    var isLoading = false
    var error: Error?
    var preview: StakingActionPreview?

    init(chain: Chain) {
        self.chain = chain
    }

    // ── Data loading ─────────────────────────────────────────────────────────

    func loadValidators() async {
        isLoading = true
        error = nil
        do {
            validators = try await StakingBridge.shared.fetchValidators(chainId: chain.id)
            if chain == .polkadot {
                nominationPools = try await StakingBridge.shared.polkadotFetchNominationPools()
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }


    func dismissError() { error = nil }
    func dismissPreview() { preview = nil }
    private func beginTx() { isLoading = true; error = nil; preview = nil }

    /// Build the transaction for one staking action.
    ///
    /// Twenty-three functions stood here — one per (chain, action) pair, each
    /// `beginTx()`, one bridge call, `catch { error }`, `isLoading = false`,
    /// identical but for which of twenty-three bridge names it called. Not one
    /// of them had a caller: the view reads `validators`, `positions`,
    /// `preview` and `error`, and nothing ever asked the model to build. They
    /// were three layers of wrapper over a function the UI had not been wired
    /// to yet.
    func buildTx(_ request: StakingActionRequest) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.buildStakingTx(request)
        } catch { self.error = error }
        isLoading = false
    }
}
