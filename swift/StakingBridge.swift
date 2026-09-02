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

    /// Build the transaction for one staking action.
    ///
    /// Twenty-three functions stood here, one per (chain, action) pair, each a
    /// one-line forward to the core export of the same name — and the view
    /// model repeated all twenty-three a third time.
    func buildStakingTx(_ request: StakingActionRequest) async throws -> StakingActionPreview {
        try await service().buildStakingTx(request: request)
    }
}

private extension StakingBridge {
    /// Endpoints for every chain the registry says can stake. Naming them here
    /// meant the staking tab could offer a chain whose endpoints this list had
    /// not been told about.
    static func buildEndpoints() -> [ChainEndpoints] {
        Chain.mainnets.filter(\.supportsStaking).flatMap { rpcPayloads(for: $0) }
    }

    static func rpcPayloads(for chain: Chain) -> [ChainEndpoints] {
        rpcPayloads(chainId: chain.id, chainName: chain.displayName)
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
