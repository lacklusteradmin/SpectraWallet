import Foundation

// File-scope alias captures the UniFFI free function before SeedPhraseSafety.generateMnemonic shadows it.
private let _rustGenerateMnemonic: (UInt32) -> String = generateMnemonic(wordCount:)

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

        guard validateMnemonic(phrase: normalizedPhrase) else {
            return "This seed phrase is not a valid BIP-39 mnemonic. Check the word spelling and checksum."
        }
        return nil
    }

    static func hasValidChecksum(_ seedPhrase: String, expectedWordCount: Int? = nil) -> Bool {
        validationError(for: seedPhrase, expectedWordCount: expectedWordCount) == nil
    }

    static func generateMnemonic(wordCount: Int) throws -> String {
        // Delegate to the Rust/UniFFI free function via file-scope alias (avoids name shadowing).
        normalizedPhrase(from: _rustGenerateMnemonic(UInt32(wordCount)))
    }
}
