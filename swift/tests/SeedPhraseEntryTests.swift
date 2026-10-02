import Foundation
import Testing

@testable import Spectra

/// The entry grid follows core's verdict: it grows to hold what is pasted,
/// and a fixed length is refused by core rather than enforced by cutting.
@MainActor
struct SeedPhraseEntryTests {
    private let zero24 = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"

    @Test func pastingTwentyFourWordsGrowsTheGridToTwentyFour() {
        let entry = SeedPhraseEntry()
        #expect(entry.slots.count == 12)
        entry.paste(zero24)
        #expect(entry.slots.count == 24)
        #expect(entry.verdict.wordCount == 24)
        #expect(entry.verdict.language?.code == "en")
        #expect(entry.verdict.checksumValid)
        #expect(entry.phrase == zero24)
    }

    @Test func aFixedLengthKeepsEveryPastedWordAndRefusesThePhrase() {
        let entry = SeedPhraseEntry()
        entry.wordCountOverride = 12
        entry.paste(zero24)
        #expect(entry.slots.count == 24)
        #expect(entry.verdict.problem == .wrongWordCount(expected: 12))
        #expect(!entry.verdict.checksumValid)
    }

    @Test func moreWordsStepsToTheNextStandardLength() {
        let entry = SeedPhraseEntry()
        entry.addSlots()
        #expect(entry.slots.count == 15)
        entry.paste(zero24)
        #expect(entry.nextSlotCount == nil)
    }

    @Test func clearingReturnsTheGridToItsStartingLength() {
        let entry = SeedPhraseEntry()
        entry.paste(zero24)
        entry.clear()
        #expect(entry.slots == Array(repeating: "", count: 12))
    }

    /// Core states the problem; the words are this app's, in its language.
    @Test func everyProblemIsWorded() {
        for problem: SeedPhraseProblem in [.nonStandardLength(wordCount: 25), .wrongWordCount(expected: 12), .invalidChecksum] {
            #expect(!problem.localizedMessage.isEmpty)
        }
        // The lengths named are core's, not a list kept beside them.
        let message = SeedPhraseProblem.nonStandardLength(wordCount: 25).localizedMessage
        for length in CoreReferenceTables.standardSeedPhraseLengths {
            #expect(message.contains(String(length.wordCount)))
        }
    }

    /// A created phrase goes through the same entry, judged at the length
    /// it was generated at.
    @Test func aCreatedPhraseIsJudgedAtItsLength() {
        let draft = WalletImportDraft()
        draft.configureForCreatedWallet()
        draft.selectedSeedPhraseWordCount = 24
        #expect(draft.seedPhraseWords.count == 24)
        #expect(draft.seedEntry.verdict.checksumValid)
    }
}
