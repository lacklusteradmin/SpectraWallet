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

    /// 1-based step position for `current`, or `nil` for side routes
    /// (like `.advanced`) that don't participate in the counter.
    func stepPosition(for current: WalletSetupPage) -> (current: Int, total: Int)? {
        guard let i = index(of: current) else { return nil }
        return (i + 1, pages.count)
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
