import Foundation

@MainActor
extension AppState {
    func wallet(for walletId: String) -> WalletView? { cachedWalletById[walletId] }
    /// Every address this wallet is known to hold: stored, used by its own
    /// transactions, or handed out by its keypool.
    ///
    /// This assembled the list from the app's projections — and derived nothing
    /// core had not already stored — then sent it to core to be deduplicated.
    func knownOwnedAddresses(for walletId: String) async -> [String] {
        (try? await self.bridge.knownWalletAddresses(walletId: walletId)) ?? []
    }
    /// A sealed wallet can be revealed with its password, so this asks what is
    /// stored rather than whether it can be read without one.
    func canRevealSeedPhrase(for walletId: String) -> Bool {
        guard let state = self.bridge.walletSecretState(walletId: walletId) else { return false }
        return state.hasSigningMaterial && !state.hasPrivateKey
    }
    func isWatchOnlyWallet(_ wallet: WalletView) -> Bool { !walletHasSigningMaterial(wallet.id) }
    func isPrivateKeyWallet(_ wallet: WalletView) -> Bool { isPrivateKeyBackedWallet(wallet.id) }
    func revealSeedPhrase(for wallet: WalletView, password: String? = nil) async throws -> String {
        let authenticated = await authenticateForSeedPhraseReveal(reason: AppLocalization.format("Authenticate to view seed phrase for %@", wallet.name))
        guard authenticated else { throw SeedPhraseRevealError.authenticationRequired }
        var providedPassword: String? = nil
        if walletRequiresSeedPhrasePassword(wallet.id) {
            guard let supplied = password?.trimmingCharacters(in: .whitespacesAndNewlines), !supplied.isEmpty else {
                throw SeedPhraseRevealError.passwordRequired
            }
            providedPassword = supplied
        }
        // The password decrypts the sealed phrase; an incorrect password cannot reveal it.
        let seedPhrase: String
        do {
            seedPhrase = try self.bridge.walletSeedPhrase(
                walletId: wallet.id, password: providedPassword)
        } catch {
            throw providedPassword == nil
                ? SeedPhraseRevealError.unavailable
                : SeedPhraseRevealError.invalidPassword
        }
        guard !seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SeedPhraseRevealError.unavailable
        }
        return seedPhrase
    }
}
