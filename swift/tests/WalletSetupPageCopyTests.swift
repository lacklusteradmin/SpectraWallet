import XCTest

@testable import Spectra

@MainActor
final class WalletSetupPageCopyTests: XCTestCase {
    private let content = ImportFlowContent.current

    private func mode(editing: Bool = false, creating: Bool = false, privateKey: Bool = false) -> WalletSetupMode {
        WalletSetupMode(isEditingWallet: editing, isCreateMode: creating, isPrivateKeyImport: privateKey)
    }

    /// The resolver replaced two if-chains that could fall through to a
    /// wallet-import title when no arm matched. Nothing may come back blank.
    func testEveryPageNamesItselfInEveryMode() {
        let pages: [WalletSetupPage] = [
            .details, .watchAddresses, .seedPhrase, .password, .backupVerification, .walletName, .advanced,
        ]
        let modes = [
            mode(), mode(editing: true), mode(creating: true), mode(privateKey: true),
            mode(creating: true, privateKey: true),
        ]
        for page in pages {
            for mode in modes {
                let copy = page.copy(content, mode: mode)
                XCTAssertFalse(copy.title.isEmpty, "\(page) has no title in \(mode)")
                XCTAssertFalse(copy.subtitle.isEmpty, "\(page) has no subtitle in \(mode)")
            }
        }
    }

    /// The secret page is the one whose wording the mode changes: recording a
    /// phrase, entering one, or pasting a key are three different pages to a
    /// reader and one case to the compiler.
    func testTheSecretPageNamesWhichSecretItIsAskingFor() {
        let creating = WalletSetupPage.seedPhrase.copy(content, mode: mode(creating: true))
        let importing = WalletSetupPage.seedPhrase.copy(content, mode: mode())
        let privateKey = WalletSetupPage.seedPhrase.copy(content, mode: mode(privateKey: true))

        XCTAssertEqual(creating.title, content.recordSeedPhraseTitle)
        XCTAssertEqual(importing.title, content.enterSeedPhraseTitle)
        XCTAssertEqual(privateKey.title, content.enterPrivateKeyTitle)
        XCTAssertEqual(creating.subtitle, content.saveRecoveryPhraseSubtitle)
        XCTAssertEqual(importing.subtitle, content.enterRecoveryPhraseSubtitle)
        XCTAssertEqual(privateKey.subtitle, content.privateKeySubtitle)
    }

    /// A private-key import is still a private-key import when it is also a
    /// creation, and the key wins: there is no phrase to record.
    func testPastingAKeyOutranksRecordingAPhrase() {
        let both = WalletSetupPage.seedPhrase.copy(content, mode: mode(creating: true, privateKey: true))
        XCTAssertEqual(both.subtitle, content.privateKeySubtitle)
    }

    /// Editing only ever reaches the name page, but the details wording still
    /// answers for it rather than falling through to a chain-selection title.
    func testEditingNamesTheEditRatherThanTheChainPicker() {
        XCTAssertEqual(WalletSetupPage.details.copy(content, mode: mode(editing: true)).title, content.editWalletTitle)
        XCTAssertNotEqual(
            WalletSetupPage.details.copy(content, mode: mode()).title, content.editWalletTitle)
    }

    /// Each flow's pages all resolve; a flow cannot contain a page the copy
    /// resolver has no arm for.
    func testEveryFlowsPagesResolve() {
        for flow in [SetupFlow.watchOnly, .seedPhraseImport, .createNewWallet, .editWallet] {
            for page in flow.pages {
                XCTAssertFalse(page.copy(content, mode: mode()).title.isEmpty)
            }
        }
    }
}
