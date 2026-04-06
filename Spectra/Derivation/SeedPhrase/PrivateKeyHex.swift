import Foundation

enum PrivateKeyHex {
    static func normalized(from rawValue: String) -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
    }

    static func isLikely(_ rawValue: String) -> Bool {
        let normalized = normalized(from: rawValue)
        guard normalized.count == 64 else { return false }
        return normalized.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
        }
    }
}
