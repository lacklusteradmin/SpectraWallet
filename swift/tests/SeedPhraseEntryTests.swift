import Foundation
import Testing

@testable import Spectra

/// The import grid follows core's verdict: it grows to hold what is pasted,
/// and a fixed length is refused by core rather than enforced by cutting.
@MainActor
struct SeedPhraseEntryTests {
    private let zero24 = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"

    @Test func pastingTwentyFourWordsGrowsTheGridToTwentyFour() {
        let draft = WalletImportDraft()
        draft.selectedChainsStorage = [Chain.bitcoin]
        #expect(draft.seedPhraseEntries.count == 12)
        draft.pasteSeedPhrase(zero24)
        #expect(draft.seedPhraseEntries.count == 24)
        #expect(draft.seedPhraseVerdict.wordCount == 24)
        #expect(draft.seedPhraseVerdict.language?.code == "en")
        #expect(draft.isSecretComplete)
    }

    @Test func aFixedLengthKeepsEveryPastedWordAndRefusesThePhrase() {
        let draft = WalletImportDraft()
        draft.selectedChainsStorage = [Chain.bitcoin]
        draft.seedPhraseWordCountOverride = 12
        draft.pasteSeedPhrase(zero24)
        #expect(draft.seedPhraseEntries.count == 24)
        #expect(draft.seedPhraseVerdict.error == "Seed phrase must be 12 words.")
        #expect(!draft.isSecretComplete)
    }

    @Test func moreWordsStepsToTheNextStandardLength() {
        let draft = WalletImportDraft()
        draft.addSeedPhraseSlots()
        #expect(draft.seedPhraseEntries.count == 15)
        draft.seedPhraseEntries = Array(repeating: "", count: 24)
        #expect(draft.nextSeedPhraseSlotCount == nil)
    }

    @Test func clearingReturnsTheGridToItsStartingLength() {
        let draft = WalletImportDraft()
        draft.pasteSeedPhrase(zero24)
        draft.clearSeedPhrase()
        #expect(draft.seedPhraseEntries == Array(repeating: "", count: 12))
    }
}
