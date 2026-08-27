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

    // ── Solana ───────────────────────────────────────────────────────────────

    func solanaBuildStakeTx(walletAddress: String, amountLamports: UInt64, voteAccount: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.solanaBuildStakeTx(
                walletAddress: walletAddress, amountLamports: amountLamports, voteAccount: voteAccount)
        } catch { self.error = error }
        isLoading = false
    }

    func solanaBuildDeactivateTx(walletAddress: String, stakeAccount: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.solanaBuildDeactivateTx(
                walletAddress: walletAddress, stakeAccount: stakeAccount)
        } catch { self.error = error }
        isLoading = false
    }

    func solanaBuildWithdrawTx(walletAddress: String, stakeAccount: String, amountLamports: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.solanaBuildWithdrawTx(
                walletAddress: walletAddress, stakeAccount: stakeAccount, amountLamports: amountLamports)
        } catch { self.error = error }
        isLoading = false
    }

    // ── Cardano ──────────────────────────────────────────────────────────────

    func cardanoBuildDelegateTx(walletAddress: String, poolId: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.cardanoBuildDelegateTx(
                walletAddress: walletAddress, poolId: poolId)
        } catch { self.error = error }
        isLoading = false
    }

    func cardanoBuildClaimRewardsTx(walletAddress: String, amountLovelace: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.cardanoBuildClaimRewardsTx(
                walletAddress: walletAddress, amountLovelace: amountLovelace)
        } catch { self.error = error }
        isLoading = false
    }

    func cardanoBuildDeregisterTx(walletAddress: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.cardanoBuildDeregisterTx(
                walletAddress: walletAddress)
        } catch { self.error = error }
        isLoading = false
    }

    // ── Sui ──────────────────────────────────────────────────────────────────

    func suiBuildAddStakeTx(walletAddress: String, amountMist: UInt64, validatorAddress: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.suiBuildAddStakeTx(
                walletAddress: walletAddress, amountMist: amountMist, validatorAddress: validatorAddress)
        } catch { self.error = error }
        isLoading = false
    }

    func suiBuildWithdrawStakeTx(walletAddress: String, stakedSuiObjectId: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.suiBuildWithdrawStakeTx(
                walletAddress: walletAddress, stakedSuiObjectId: stakedSuiObjectId)
        } catch { self.error = error }
        isLoading = false
    }

    // ── Aptos ────────────────────────────────────────────────────────────────

    func aptosBuildAddStakeTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.aptosBuildAddStakeTx(
                walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
        } catch { self.error = error }
        isLoading = false
    }

    func aptosBuildUnlockTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.aptosBuildUnlockTx(
                walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
        } catch { self.error = error }
        isLoading = false
    }

    func aptosBuildWithdrawTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.aptosBuildWithdrawTx(
                walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
        } catch { self.error = error }
        isLoading = false
    }

    // ── NEAR ─────────────────────────────────────────────────────────────────

    func nearBuildDepositAndStakeTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.nearBuildDepositAndStakeTx(
                walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
        } catch { self.error = error }
        isLoading = false
    }

    func nearBuildUnstakeTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.nearBuildUnstakeTx(
                walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
        } catch { self.error = error }
        isLoading = false
    }

    func nearBuildWithdrawTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.nearBuildWithdrawTx(
                walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
        } catch { self.error = error }
        isLoading = false
    }

    // ── Polkadot ─────────────────────────────────────────────────────────────

    func polkadotBuildBondAndNominateTx(walletAddress: String, amountPlanck: String, validatorAddresses: [String]) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.polkadotBuildBondAndNominateTx(
                walletAddress: walletAddress, amountPlanck: amountPlanck, validatorAddresses: validatorAddresses)
        } catch { self.error = error }
        isLoading = false
    }

    func polkadotBuildJoinPoolTx(walletAddress: String, amountPlanck: String, poolId: UInt32) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.polkadotBuildJoinPoolTx(
                walletAddress: walletAddress, amountPlanck: amountPlanck, poolId: poolId)
        } catch { self.error = error }
        isLoading = false
    }

    func polkadotBuildUnbondTx(walletAddress: String, amountPlanck: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.polkadotBuildUnbondTx(
                walletAddress: walletAddress, amountPlanck: amountPlanck)
        } catch { self.error = error }
        isLoading = false
    }

    func polkadotBuildWithdrawUnbondedTx(walletAddress: String) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.polkadotBuildWithdrawUnbondedTx(
                walletAddress: walletAddress)
        } catch { self.error = error }
        isLoading = false
    }

    // ── ICP ──────────────────────────────────────────────────────────────────

    func icpBuildCreateNeuronTx(walletAddress: String, amountE8s: UInt64, dissolveDelayMonths: UInt32) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.icpBuildCreateNeuronTx(
                walletAddress: walletAddress, amountE8s: amountE8s, dissolveDelayMonths: dissolveDelayMonths)
        } catch { self.error = error }
        isLoading = false
    }

    func icpBuildIncreaseDissolveDelayTx(walletAddress: String, neuronId: UInt64, additionalMonths: UInt32) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.icpBuildIncreaseDissolveDelayTx(
                walletAddress: walletAddress, neuronId: neuronId, additionalMonths: additionalMonths)
        } catch { self.error = error }
        isLoading = false
    }

    func icpBuildStartDissolvingTx(walletAddress: String, neuronId: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.icpBuildStartDissolvingTx(
                walletAddress: walletAddress, neuronId: neuronId)
        } catch { self.error = error }
        isLoading = false
    }

    func icpBuildDisburseTx(walletAddress: String, neuronId: UInt64, amountE8s: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.icpBuildDisburseTx(
                walletAddress: walletAddress, neuronId: neuronId, amountE8s: amountE8s)
        } catch { self.error = error }
        isLoading = false
    }

    func icpBuildClaimMaturityTx(walletAddress: String, neuronId: UInt64) async {
        beginTx()
        do {
            preview = try await StakingBridge.shared.icpBuildClaimMaturityTx(
                walletAddress: walletAddress, neuronId: neuronId)
        } catch { self.error = error }
        isLoading = false
    }
}
