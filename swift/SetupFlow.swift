import Foundation

/// Ordered wallet-setup pages. Navigation and the step indicator derive
/// from this list. `.advanced` is a side route from the seed page and is
/// excluded from the linear flow and step count.
struct SetupFlow {
    /// The ordered linear pages. Excludes side-routes like `.advanced`.
    let pages: [WalletSetupPage]

    /// Linear index of `page` within this flow, or `nil` for side routes
    /// that aren't part of the count.
    func index(of page: WalletSetupPage) -> Int? {
        pages.firstIndex(of: page)
    }

    /// Page to advance to from `current`, or `nil` if already at the end
    /// (indicating the primary action should submit instead of route).
    func next(after current: WalletSetupPage) -> WalletSetupPage? {
        guard let i = index(of: current), i + 1 < pages.count else { return nil }
        return pages[i + 1]
    }

    /// Page to walk back to from `current`, or `nil` if already at the
    /// start (indicating the back button should dismiss the flow).
    func previous(before current: WalletSetupPage) -> WalletSetupPage? {
        guard let i = index(of: current), i > 0 else { return nil }
        return pages[i - 1]
    }

}

/// Linear pages for the wallet-setup flow. Lifted out of `SetupView`'s
/// private enum so `SetupFlow` can reference it.
enum WalletSetupPage: Equatable {
    case details
    case watchAddresses
    case seedPhrase
    case password
    case backupVerification
    case walletName
    /// Side route from the seed-phrase page — not part of the linear flow.
    case advanced
}

extension SetupFlow {
    /// Watch-only import: choose chains, paste watch addresses, name it.
    static let watchOnly = SetupFlow(pages: [.details, .watchAddresses, .walletName])

    /// Seed-phrase import: chains, secret, password, name.
    static let seedPhraseImport = SetupFlow(pages: [.details, .seedPhrase, .password, .walletName])

    /// Create new wallet: chains, generated secret, password, backup
    /// verification, name.
    static let createNewWallet = SetupFlow(
        pages: [.details, .seedPhrase, .password, .backupVerification, .walletName]
    )

    /// Edit existing wallet — single-page (just the name field).
    static let editWallet = SetupFlow(pages: [.walletName])
}

/// Which setup a page belongs to, as far as its wording is concerned.
///
/// The page alone does not decide what it is called — "seed phrase" reads as
/// *record* one when creating a wallet and *enter* one when importing — so the
/// copy resolver takes the mode alongside the page.
struct WalletSetupMode {
    let isEditingWallet: Bool
    let isCreateMode: Bool
    let isPrivateKeyImport: Bool
}

/// What a page calls itself: the heading and the line under it.
struct WalletSetupPageCopy {
    let title: String
    let subtitle: String
}

extension WalletSetupPage {
    /// Page wording. Exhaustive so every new page must supply a title.
    func copy(_ content: ImportFlowContent, mode: WalletSetupMode) -> WalletSetupPageCopy {
        switch self {
        case .walletName:
            if mode.isEditingWallet {
                return WalletSetupPageCopy(title: content.editWalletTitle, subtitle: content.editWalletSubtitle)
            }
            return WalletSetupPageCopy(
                title: AppLocalization.string("import_flow.name_your_wallet"),
                subtitle: AppLocalization.string("import_flow.wallet_name_hint"))
        case .backupVerification:
            return WalletSetupPageCopy(
                title: content.backupVerificationTitle, subtitle: content.backupVerificationSubtitle)
        case .advanced:
            return WalletSetupPageCopy(title: content.advancedTitle, subtitle: content.advancedSubtitle)
        case .password:
            return WalletSetupPageCopy(
                title: AppLocalization.string("import_flow.wallet_password_title"),
                subtitle: AppLocalization.string("import_flow.wallet_password_subtitle"))
        case .watchAddresses:
            return WalletSetupPageCopy(
                title: content.watchAddressesTitle, subtitle: content.watchAddressesSubtitle)
        case .seedPhrase:
            if mode.isPrivateKeyImport {
                return WalletSetupPageCopy(
                    title: content.enterPrivateKeyTitle, subtitle: content.privateKeySubtitle)
            }
            return WalletSetupPageCopy(
                title: mode.isCreateMode ? content.recordSeedPhraseTitle : content.enterSeedPhraseTitle,
                subtitle: mode.isCreateMode ? content.saveRecoveryPhraseSubtitle : content.enterRecoveryPhraseSubtitle)
        case .details:
            return WalletSetupPageCopy(
                title: AppLocalization.string("import_flow.choose_chains"),
                subtitle: AppLocalization.string("import_flow.choose_chains_subtitle"))
        }
    }
}

/// Whether the secret step — a seed phrase or a private key — is complete
/// enough to move on.
///
/// A free function because both the step that renders the fields and the
/// button bar that decides whether to enable itself need the answer, and it
/// derives entirely from the draft: nothing about it is view state.
@MainActor
func walletSetupCanContinueFromSecretStep(draft: WalletImportDraft, isImporting: Bool) -> Bool {
    let hasChains = !draft.selectedChainIds.isEmpty
    if draft.isPrivateKeyImportMode {
        return hasChains
            && isPrivateKeyHex(rawValue: draft.privateKeyInput)
            && draft.unsupportedPrivateKeyChainNames.isEmpty
            && draft.selectedChainIds.count == 1
            && !isImporting
    }
    return hasChains && draft.seedPhraseVerdict.checksumValid && !isImporting
}
