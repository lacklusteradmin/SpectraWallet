import Foundation

@MainActor @Observable final class StakingViewModel {
    let chain: Chain
    var validators: [StakingValidator] = []
    var isLoading = false
    var error: Error?
    @ObservationIgnored private let bridge: WalletServiceBridge // Service identity is not view state.
    init(chain: Chain, bridge: WalletServiceBridge) {
        self.chain = chain
        self.bridge = bridge
    }
    func loadValidators() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { validators = try await bridge.ready().fetchStakingValidators(chainId: chain.id) }
        catch { self.error = error }
    }
    func dismissError() { error = nil }
}
