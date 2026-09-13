import Foundation

@MainActor @Observable final class StakingViewModel {
    let chain: Chain
    var validators: [StakingValidator] = []
    var isLoading = false
    var error: Error?
    init(chain: Chain) { self.chain = chain }
    func loadValidators() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { validators = try await WalletServiceBridge.shared.fetchStakingValidators(chainId: chain.id) }
        catch { self.error = error }
    }
    func dismissError() { error = nil }
}
