import Foundation

/// Ordered sequence of pages for one wallet-setup flow.
///
/// Replaces the three scattered switches in `SetupView` (step counter,
/// forward routing, back routing) with one source of truth: the ordered
/// list of pages. `currentIndex`, `next`, and `previous` derive from the
/// list, so adding or reordering a step is one edit to the flow definition
/// instead of four coordinated edits across switch statements.
///
/// `.advanced` is a side route, not part of the linear flow — it's reached
/// from the seed-phrase page via a separate entry and isn't counted in the
/// step indicator. The flow definitions intentionally exclude it.
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
    /// The page's wording, from one exhaustive switch.
    ///
    /// This replaces two parallel if-chains in `SetupView` that the compiler
    /// never checked against the enum. They had grown three unreachable
    /// branches between them: every chain tested the six non-`details` pages
    /// first, so the `isCreateMode` and `isWatchAddressesImportMode` arms below
    /// them could only ever be reached on `.details`, which the arm above had
    /// already returned for. A new page now fails to compile until it says what
    /// it is called, instead of silently falling through to a wallet-import
    /// title.
    func copy(_ content: ImportFlowContent, mode: WalletSetupMode) -> WalletSetupPageCopy {
        switch self {
        case .walletName:
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
            let title: String
            if mode.isCreateMode {
                title = content.recordSeedPhraseTitle
            } else {
                title = mode.isPrivateKeyImport ? content.enterPrivateKeyTitle : content.enterSeedPhraseTitle
            }
            let subtitle: String
            if mode.isPrivateKeyImport {
                subtitle = content.privateKeySubtitle
            } else {
                subtitle = mode.isCreateMode ? content.saveRecoveryPhraseSubtitle : content.enterRecoveryPhraseSubtitle
            }
            return WalletSetupPageCopy(title: title, subtitle: subtitle)
        case .details:
            // Editing never reaches this page — `SetupFlow.editWallet` is the
            // name field alone — but the wording answered for it, so it still
            // does rather than quietly changing what an edit would show.
            if mode.isEditingWallet {
                return WalletSetupPageCopy(title: content.editWalletTitle, subtitle: content.editWalletSubtitle)
            }
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
    let hasChains = !draft.selectedChainNames.isEmpty
    if draft.isPrivateKeyImportMode {
        return hasChains
            && CachedCoreHelpers.privateKeyHexIsLikely(rawValue: draft.privateKeyInput)
            && draft.unsupportedPrivateKeyChainNames.isEmpty
            && draft.selectedChainNames.count == 1
            && !isImporting
    }
    return hasChains && draft.seedPhraseVerdict.checksumValid && !isImporting
}
