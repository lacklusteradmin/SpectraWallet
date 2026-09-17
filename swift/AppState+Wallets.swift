import Foundation

@MainActor
extension AppState {
    func wallet(for walletID: String) -> WalletView? { cachedWalletByID[walletID] }
    /// Every address this wallet is known to hold: stored, used by its own
    /// transactions, or handed out by its keypool.
    ///
    /// This assembled the list from the app's projections — and derived nothing
    /// core had not already stored — then sent it to core to be deduplicated.
    func knownOwnedAddresses(for walletID: String) async -> [String] {
        (try? await WalletServiceBridge.shared.knownWalletAddresses(walletID: walletID)) ?? []
    }
    /// A sealed wallet can be revealed with its password, so this asks what is
    /// stored rather than whether it can be read without one.
    func canRevealSeedPhrase(for walletID: String) -> Bool {
        guard let state = WalletServiceBridge.shared.walletSecretState(walletID: walletID) else { return false }
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
        // One call decides both. The password used to be checked against a
        // verifier stored beside a plaintext phrase, so a wrong password was
        // the only thing standing between a reader and material that was never
        // encrypted; it is the decryption key now, and a wrong one cannot
        // produce a phrase at all.
        let seedPhrase: String
        do {
            seedPhrase = try WalletServiceBridge.shared.walletSeedPhrase(
                walletID: wallet.id, password: providedPassword)
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
