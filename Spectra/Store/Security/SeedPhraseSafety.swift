import Foundation
import WalletCore
import BitcoinDevKit

enum SeedPhraseSafety {
    private static let validWordCounts: Set<Int> = [12, 15, 18, 21, 24]

    static func normalizedWords(from seedPhrase: String) -> [String] {
        seedPhrase
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func normalizedPhrase(from seedPhrase: String) -> String {
        normalizedWords(from: seedPhrase).joined(separator: " ")
    }

    static func invalidEnglishWords(in seedPhrase: String) -> [String] {
        var seen: Set<String> = []
        return normalizedWords(from: seedPhrase).reduce(into: [String]()) { result, word in
            guard !BIP39EnglishWordList.words.contains(word) else { return }
            guard seen.insert(word).inserted else { return }
            result.append(word)
        }
    }

    static func validationError(for seedPhrase: String, expectedWordCount: Int? = nil) -> String? {
        let trimmedPhrase = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else {
            return "Enter a BIP-39 seed phrase."
        }

        let words = normalizedWords(from: trimmedPhrase)
        let normalizedPhrase = words.joined(separator: " ")

        if let expectedWordCount, words.count != expectedWordCount {
            return "This seed phrase has \(words.count) words. Selected length is \(expectedWordCount)."
        }

        guard validWordCounts.contains(words.count) else {
            return "Use a valid BIP-39 seed phrase with 12, 15, 18, 21, or 24 words."
        }

        let invalidWords = invalidEnglishWords(in: normalizedPhrase)
        guard invalidWords.isEmpty else {
            let joinedWords = invalidWords.joined(separator: ", ")
            return "These words are not in the BIP-39 English word list: \(joinedWords)."
        }

        do {
            _ = try Mnemonic.fromString(mnemonic: normalizedPhrase)
            return nil
        } catch {
            return "This seed phrase is not a valid BIP-39 mnemonic. Check the word spelling and checksum."
        }
    }

    static func hasValidChecksum(_ seedPhrase: String, expectedWordCount: Int? = nil) -> Bool {
        validationError(for: seedPhrase, expectedWordCount: expectedWordCount) == nil
    }

    static func validatedMnemonic(from seedPhrase: String) throws -> BitcoinDevKit.Mnemonic {
        try BitcoinDevKit.Mnemonic.fromString(mnemonic: normalizedPhrase(from: seedPhrase))
    }

    static func generateMnemonic(wordCount: Int) throws -> String {
        let targetWordCount = validWordCounts.contains(wordCount) ? wordCount : 12
        let mnemonicWordCount: WordCount
        switch targetWordCount {
        case 12:
            mnemonicWordCount = .words12
        case 15:
            mnemonicWordCount = .words15
        case 18:
            mnemonicWordCount = .words18
        case 21:
            mnemonicWordCount = .words21
        case 24:
            mnemonicWordCount = .words24
        default:
            mnemonicWordCount = .words12
        }
        let mnemonic = Mnemonic(wordCount: mnemonicWordCount)
        return normalizedPhrase(from: String(describing: mnemonic))
    }
}
