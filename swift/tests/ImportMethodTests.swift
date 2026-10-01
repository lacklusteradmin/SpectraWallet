import Foundation
import Testing

@testable import Spectra

/// The import method is chosen before the chains, so the picker lists only
/// the chains that method can use.
@MainActor
struct ImportMethodTests {
    @Test func aPrivateKeyImportOffersOnlyChainsAKeyDerivesOn() {
        let draft = WalletImportDraft()
        draft.configureForPrivateKeyImport()
        #expect(draft.isPrivateKeyImportMode)
        #expect(!draft.allowsMultipleChainSelection)
        for chain in Chain.all {
            #expect(draft.offers(chain) == chain.derivesFromPrivateKey, "\(chain.id)")
        }
        #expect(Chain.all.contains { !draft.offers($0) }, "every chain is offered, so nothing is filtered")
    }

    @Test func aWatchImportOffersOnlyChainsThatCanBeWatched() {
        let draft = WalletImportDraft()
        draft.configureForWatchAddressesImport()
        for chain in Chain.all {
            #expect(draft.offers(chain) == chain.supportsWatchOnlyImport, "\(chain.id)")
        }
    }

    @Test func aSeedPhraseImportOffersEveryChainAndSeveralAtOnce() {
        let draft = WalletImportDraft()
        draft.configureForNewWallet()
        #expect(!draft.isPrivateKeyImportMode)
        #expect(draft.allowsMultipleChainSelection)
        #expect(Chain.all.allSatisfy(draft.offers))
    }

    /// A chain the method cannot use never reaches the import, even if it was
    /// ticked under another method.
    @Test func aChainTheMethodCannotUseIsNotSelected() throws {
        let draft = WalletImportDraft()
        draft.configureForPrivateKeyImport()
        let unusable = try #require(Chain.all.first { !$0.derivesFromPrivateKey })
        draft.selectedChainsStorage = [unusable]
        #expect(draft.selectedChains.isEmpty)
    }
}
