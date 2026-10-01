import Foundation
import Testing

@testable import Spectra

@MainActor
struct WalletSetupPageCopyTests {
    @Test func backupQuizRemainsRequiredOnlyForWalletCreation() {
        let draft = WalletImportDraft()
        draft.selectedChainsStorage = [Chain.ethereum]
        draft.seedPhraseEntries = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".components(separatedBy: " ")
        #expect(draft.canImportWallet)
        draft.mode = .createNew
        #expect(!draft.canImportWallet)
        draft.backupVerificationWordIndices = [0, 5, 11]
        draft.backupVerificationEntries = ["abandon", "abandon", "about"]
        #expect(draft.canImportWallet)
        draft.backupVerificationEntries[2] = "abandon"
        #expect(!draft.canImportWallet)
    }

    private let content = ImportFlowContent.current

    private func mode(editing: Bool = false, creating: Bool = false, privateKey: Bool = false) -> WalletSetupMode {
        WalletSetupMode(isEditingWallet: editing, isCreateMode: creating, isPrivateKeyImport: privateKey)
    }

    /// Nothing may come back blank, in any mode.
    @Test func everyPageNamesItselfInEveryMode() {
        let pages: [WalletSetupPage] = [
            .details, .watchAddresses, .seedPhrase, .password, .backupVerification, .walletName,
        ]
        let modes = [
            mode(), mode(editing: true), mode(creating: true), mode(privateKey: true),
            mode(creating: true, privateKey: true),
        ]
        let flowPages = [SetupFlow.watchOnly, .seedPhraseImport, .createNewWallet, .editWallet].flatMap(\.pages)
        for page in flowPages {
            #expect(pages.contains(page), "Flow page \(page) is missing from the copy coverage")
        }
        for page in pages {
            for mode in modes {
                let copy = page.copy(content, mode: mode)
                #expect(!copy.title.isEmpty, "\(page) has no title in \(mode)")
                #expect(!copy.subtitle.isEmpty, "\(page) has no subtitle in \(mode)")
            }
        }
    }

    @Test func theSecretPageNamesWhichSecretItIsAskingFor() {
        let cases = [
            (mode(), content.enterSeedPhraseTitle, content.enterRecoveryPhraseSubtitle),
            (mode(creating: true), content.recordSeedPhraseTitle, content.saveRecoveryPhraseSubtitle),
            (mode(privateKey: true), content.enterPrivateKeyTitle, content.privateKeySubtitle),
            (mode(creating: true, privateKey: true), content.enterPrivateKeyTitle, content.privateKeySubtitle),
        ]
        for (mode, title, subtitle) in cases {
            let copy = WalletSetupPage.seedPhrase.copy(content, mode: mode)
            #expect(copy.title == title, "\(mode)")
            #expect(copy.subtitle == subtitle, "\(mode)")
        }
    }

    /// The editing flow shows its edit heading on the actual name page.
    @Test func editingNamesTheEditRatherThanTheChainPicker() {
        #expect(WalletSetupPage.walletName.copy(content, mode: mode(editing: true)).title == content.editWalletTitle)
        #expect(WalletSetupPage.walletName.copy(content, mode: mode(editing: true)).subtitle == content.editWalletSubtitle)
        #expect(WalletSetupPage.details.copy(content, mode: mode()).title != content.editWalletTitle)
    }

}
