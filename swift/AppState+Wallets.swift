import Foundation

@MainActor
extension AppState {
    func wallet(for walletId: String) -> WalletView? { cachedWalletById[walletId] }
    /// Reveal a wallet's seed phrase after device authentication. The
    /// password goes to core as typed; core applies its password rule and
    /// says why a phrase was not revealed.
    func revealSeedPhrase(for wallet: WalletView, password: String? = nil) async throws -> String {
        let authenticated = await authenticateForSeedPhraseReveal(reason: AppLocalization.format("Authenticate to view seed phrase for %@", wallet.name))
        guard authenticated else { throw SeedPhraseRevealError.authenticationRequired }
        let supplied = password.flatMap { $0.isEmpty ? nil : $0 }
        switch try self.bridge.revealSeedPhrase(walletId: wallet.id, password: supplied) {
        case .phrase(let phrase): return phrase
        case .notStored: throw SeedPhraseRevealError.unavailable
        case .passwordRequired: throw SeedPhraseRevealError.passwordRequired
        case .incorrectPassword: throw SeedPhraseRevealError.invalidPassword
        case .passwordNotRequired: throw SeedPhraseRevealError.passwordNotRequired
        }
    }
}

extension WalletSigning {
    var isWatchOnly: Bool { self == .watchOnly }
    var isPrivateKey: Bool { if case .privateKey = self { return true } else { return false } }
    var hasSeedPhrase: Bool { if case .seedPhrase = self { return true } else { return false } }
    /// Signing, revealing or scanning needs the wallet's password.
    var requiresPassword: Bool {
        switch self {
        case .watchOnly: return false
        case .seedPhrase(let passwordProtected), .privateKey(let passwordProtected): return passwordProtected
        }
    }
}
