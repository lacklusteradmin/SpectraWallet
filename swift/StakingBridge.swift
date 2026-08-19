import Foundation

@MainActor final class StakingBridge {
    static let shared = StakingBridge()
    private var _service: StakingService?

    private func service() -> StakingService {
        if let existing = _service { return existing }
        let svc = StakingService(endpoints: Self.buildEndpoints())
        _service = svc
        return svc
    }

    // ── Common ───────────────────────────────────────────────────────────────

    func fetchValidators(chainId: String) async throws -> [StakingValidator] {
        try await service().fetchValidators(chainId: chainId)
    }

    func fetchPositions(chainId: String, walletAddress: String) async throws -> [StakingPosition] {
        try await service().fetchPositions(chainId: chainId, walletAddress: walletAddress)
    }

    // ── Polkadot-specific ────────────────────────────────────────────────────

    func polkadotFetchNominationPools() async throws -> [StakingValidator] {
        try await service().polkadotFetchNominationPools()
    }

    // ── Cardano-specific ─────────────────────────────────────────────────────

    func cardanoIsStakeAddressRegistered(stakeAddress: String) async throws -> Bool {
        try await service().cardanoIsStakeAddressRegistered(stakeAddress: stakeAddress)
    }

    // ── Solana ───────────────────────────────────────────────────────────────

    func solanaBuildStakeTx(walletAddress: String, amountLamports: UInt64, voteAccount: String) async throws -> StakingActionPreview {
        try await service().solanaBuildStakeTx(walletAddress: walletAddress, amountLamports: amountLamports, voteAccount: voteAccount)
    }

    func solanaBuildDeactivateTx(walletAddress: String, stakeAccount: String) async throws -> StakingActionPreview {
        try await service().solanaBuildDeactivateTx(walletAddress: walletAddress, stakeAccount: stakeAccount)
    }

    func solanaBuildWithdrawTx(walletAddress: String, stakeAccount: String, amountLamports: UInt64) async throws -> StakingActionPreview {
        try await service().solanaBuildWithdrawTx(walletAddress: walletAddress, stakeAccount: stakeAccount, amountLamports: amountLamports)
    }

    // ── Cardano ──────────────────────────────────────────────────────────────

    func cardanoBuildDelegateTx(walletAddress: String, poolId: String) async throws -> StakingActionPreview {
        try await service().cardanoBuildDelegateTx(walletAddress: walletAddress, poolId: poolId)
    }

    func cardanoBuildClaimRewardsTx(walletAddress: String, amountLovelace: UInt64) async throws -> StakingActionPreview {
        try await service().cardanoBuildClaimRewardsTx(walletAddress: walletAddress, amountLovelace: amountLovelace)
    }

    func cardanoBuildDeregisterTx(walletAddress: String) async throws -> StakingActionPreview {
        try await service().cardanoBuildDeregisterTx(walletAddress: walletAddress)
    }

    // ── Sui ──────────────────────────────────────────────────────────────────

    func suiBuildAddStakeTx(walletAddress: String, amountMist: UInt64, validatorAddress: String) async throws -> StakingActionPreview {
        try await service().suiBuildAddStakeTx(walletAddress: walletAddress, amountMist: amountMist, validatorAddress: validatorAddress)
    }

    func suiBuildWithdrawStakeTx(walletAddress: String, stakedSuiObjectId: String) async throws -> StakingActionPreview {
        try await service().suiBuildWithdrawStakeTx(walletAddress: walletAddress, stakedSuiObjectId: stakedSuiObjectId)
    }

    // ── Aptos ────────────────────────────────────────────────────────────────

    func aptosBuildAddStakeTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async throws -> StakingActionPreview {
        try await service().aptosBuildAddStakeTx(walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
    }

    func aptosBuildUnlockTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async throws -> StakingActionPreview {
        try await service().aptosBuildUnlockTx(walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
    }

    func aptosBuildWithdrawTx(walletAddress: String, poolAddress: String, amountOctas: UInt64) async throws -> StakingActionPreview {
        try await service().aptosBuildWithdrawTx(walletAddress: walletAddress, poolAddress: poolAddress, amountOctas: amountOctas)
    }

    // ── NEAR ─────────────────────────────────────────────────────────────────

    func nearBuildDepositAndStakeTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async throws -> StakingActionPreview {
        try await service().nearBuildDepositAndStakeTx(walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
    }

    func nearBuildUnstakeTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async throws -> StakingActionPreview {
        try await service().nearBuildUnstakeTx(walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
    }

    func nearBuildWithdrawTx(walletAddress: String, poolAccountId: String, amountYoctoNear: String) async throws -> StakingActionPreview {
        try await service().nearBuildWithdrawTx(walletAddress: walletAddress, poolAccountId: poolAccountId, amountYoctoNear: amountYoctoNear)
    }

    // ── Polkadot ─────────────────────────────────────────────────────────────

    func polkadotBuildBondAndNominateTx(walletAddress: String, amountPlanck: String, validatorAddresses: [String]) async throws -> StakingActionPreview {
        try await service().polkadotBuildBondAndNominateTx(walletAddress: walletAddress, amountPlanck: amountPlanck, validatorAddresses: validatorAddresses)
    }

    func polkadotBuildJoinPoolTx(walletAddress: String, amountPlanck: String, poolId: UInt32) async throws -> StakingActionPreview {
        try await service().polkadotBuildJoinPoolTx(walletAddress: walletAddress, amountPlanck: amountPlanck, poolId: poolId)
    }

    func polkadotBuildUnbondTx(walletAddress: String, amountPlanck: String) async throws -> StakingActionPreview {
        try await service().polkadotBuildUnbondTx(walletAddress: walletAddress, amountPlanck: amountPlanck)
    }

    func polkadotBuildWithdrawUnbondedTx(walletAddress: String) async throws -> StakingActionPreview {
        try await service().polkadotBuildWithdrawUnbondedTx(walletAddress: walletAddress)
    }

    // ── ICP ──────────────────────────────────────────────────────────────────

    func icpBuildCreateNeuronTx(walletAddress: String, amountE8s: UInt64, dissolveDelayMonths: UInt32) async throws -> StakingActionPreview {
        try await service().icpBuildCreateNeuronTx(walletAddress: walletAddress, amountE8s: amountE8s, dissolveDelayMonths: dissolveDelayMonths)
    }

    func icpBuildIncreaseDissolveDelayTx(walletAddress: String, neuronId: UInt64, additionalMonths: UInt32) async throws -> StakingActionPreview {
        try await service().icpBuildIncreaseDissolveDelayTx(walletAddress: walletAddress, neuronId: neuronId, additionalMonths: additionalMonths)
    }

    func icpBuildStartDissolvingTx(walletAddress: String, neuronId: UInt64) async throws -> StakingActionPreview {
        try await service().icpBuildStartDissolvingTx(walletAddress: walletAddress, neuronId: neuronId)
    }

    func icpBuildDisburseTx(walletAddress: String, neuronId: UInt64, amountE8s: UInt64) async throws -> StakingActionPreview {
        try await service().icpBuildDisburseTx(walletAddress: walletAddress, neuronId: neuronId, amountE8s: amountE8s)
    }

    func icpBuildClaimMaturityTx(walletAddress: String, neuronId: UInt64) async throws -> StakingActionPreview {
        try await service().icpBuildClaimMaturityTx(walletAddress: walletAddress, neuronId: neuronId)
    }
}

private extension StakingBridge {
    static func buildEndpoints() -> [ChainEndpoints] {
        var payloads: [ChainEndpoints] = []
        payloads += rpcPayloads(chainId: Chain.solana.id,   chainName: "Solana")
        payloads += rpcPayloads(chainId: Chain.cardano.id,  chainName: "Cardano")
        payloads += rpcPayloads(chainId: Chain.polkadot.id, chainName: "Polkadot")
        payloads += rpcPayloads(chainId: Chain.sui.id,      chainName: "Sui")
        payloads += rpcPayloads(chainId: Chain.aptos.id,    chainName: "Aptos")
        payloads += rpcPayloads(chainId: Chain.near.id,     chainName: "NEAR")
        payloads += rpcPayloads(chainId: Chain.icp.id,      chainName: "Internet Computer")
        return payloads
    }

    static func rpcPayloads(chainId: String, chainName: String) -> [ChainEndpoints] {
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: [.rpc, .balance, .backend], settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
}
