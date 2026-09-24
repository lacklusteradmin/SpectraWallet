import XCTest

@testable import Spectra

@MainActor
final class WalletSetupPageCopyTests: XCTestCase {
    func testBackupQuizRemainsRequiredOnlyForWalletCreation() {
        let draft = WalletImportDraft()
        draft.selectedChainIdsStorage = ["ethereum"]
        draft.seedPhraseEntries = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".components(separatedBy: " ")
        XCTAssertTrue(draft.canImportWallet)
        draft.mode = .createNew
        XCTAssertFalse(draft.canImportWallet)
        draft.backupVerificationWordIndices = [0, 5, 11]
        draft.backupVerificationEntries = ["abandon", "abandon", "about"]
        XCTAssertTrue(draft.canImportWallet)
        draft.backupVerificationEntries[2] = "abandon"
        XCTAssertFalse(draft.canImportWallet)
    }

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
        let flowPages = [SetupFlow.watchOnly, .seedPhraseImport, .createNewWallet, .editWallet].flatMap(\.pages)
        for page in flowPages {
            XCTAssertTrue(pages.contains(page), "Flow page \(page) is missing from the copy coverage")
        }
        for page in pages {
            for mode in modes {
                let copy = page.copy(content, mode: mode)
                XCTAssertFalse(copy.title.isEmpty, "\(page) has no title in \(mode)")
                XCTAssertFalse(copy.subtitle.isEmpty, "\(page) has no subtitle in \(mode)")
            }
        }
    }

    func testTheSecretPageNamesWhichSecretItIsAskingFor() {
        let cases = [
            (mode(), content.enterSeedPhraseTitle, content.enterRecoveryPhraseSubtitle),
            (mode(creating: true), content.recordSeedPhraseTitle, content.saveRecoveryPhraseSubtitle),
            (mode(privateKey: true), content.enterPrivateKeyTitle, content.privateKeySubtitle),
            (mode(creating: true, privateKey: true), content.enterPrivateKeyTitle, content.privateKeySubtitle),
        ]
        for (mode, title, subtitle) in cases {
            let copy = WalletSetupPage.seedPhrase.copy(content, mode: mode)
            XCTAssertEqual(copy.title, title, "\(mode)")
            XCTAssertEqual(copy.subtitle, subtitle, "\(mode)")
        }
    }

    /// The editing flow shows its edit heading on the actual name page.
    func testEditingNamesTheEditRatherThanTheChainPicker() {
        XCTAssertEqual(WalletSetupPage.walletName.copy(content, mode: mode(editing: true)).title, content.editWalletTitle)
        XCTAssertEqual(WalletSetupPage.walletName.copy(content, mode: mode(editing: true)).subtitle, content.editWalletSubtitle)
        XCTAssertNotEqual(
            WalletSetupPage.details.copy(content, mode: mode()).title, content.editWalletTitle)
    }

}
