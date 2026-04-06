import Foundation

enum AddressValidation {
    static func isValidBitcoinAddress(_ address: String, networkMode: BitcoinNetworkMode) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return BitcoinWalletEngine.isValidAddress(trimmed, networkMode: networkMode)
    }

    static func isValidBitcoinCashAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("bitcoincash:") {
            return lowered.dropFirst("bitcoincash:".count).allSatisfy { "023456789acdefghjklmnpqrstuvwxyz".contains($0) }
        }

        return lowered.hasPrefix("q")
            || lowered.hasPrefix("p")
            || trimmed.hasPrefix("1")
            || trimmed.hasPrefix("3")
    }

    static func isValidBitcoinSVAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("1")
            || lowered.hasPrefix("3")
            || lowered.hasPrefix("bc1")
    }

    static func isValidLitecoinAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Legacy prefixes for Litecoin mainnet (base58 + bech32)
        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("ltc1")
            || trimmed.hasPrefix("L")
            || trimmed.hasPrefix("M")
            || trimmed.hasPrefix("3")
    }

    static func isValidDogecoinAddress(
        _ address: String,
        networkMode: DogecoinNetworkMode = .mainnet
    ) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return DogecoinBalanceService.isValidDogecoinAddress(trimmed, networkMode: networkMode)
    }

    static func isValidEthereumAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return EthereumWalletEngine.isValidAddress(trimmed)
    }

    static func isValidTronAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return trimmed.count == 34
            && trimmed.hasPrefix("T")
            && trimmed.allSatisfy { allowed.contains($0) }
    }

    static func isValidSolanaAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return (32 ... 44).contains(trimmed.count)
            && trimmed.allSatisfy { allowed.contains($0) }
    }

    static func isValidStellarAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        return trimmed.count == 56
            && trimmed.hasPrefix("G")
            && trimmed.allSatisfy { allowed.contains($0) }
    }

    static func isValidXRPAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return (25 ... 35).contains(trimmed.count)
            && trimmed.hasPrefix("r")
            && trimmed.allSatisfy { allowed.contains($0) }
    }

    static func isValidSuiAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("0x") else { return false }
        let hex = lower.dropFirst(2)
        guard !hex.isEmpty, hex.count <= 64 else { return false }
        return hex.allSatisfy { ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0)) }
    }

    static func isValidAptosAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        let normalized = lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
        guard !normalized.isEmpty, normalized.count <= 64 else { return false }
        return normalized.allSatisfy { ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0)) }
    }

    static func isValidTONAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        if normalized.count == 66,
           normalized.hasPrefix("0:"),
           normalized.dropFirst(2).unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) {
            return true
        }

        let userFriendlyAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return normalized.count == 48
            && trimmed.unicodeScalars.allSatisfy { userFriendlyAllowed.contains($0) }
    }

    static func isValidAptosTokenType(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        if isValidAptosAddress(normalized) {
            return true
        }

        guard normalized.contains("::") else { return false }

        let addressComponent = String(normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        return isValidAptosAddress(addressComponent)
    }

    static func isValidICPAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        guard normalized.count == 64 else { return false }
        return normalized.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }

    static func isValidNearAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        if normalized.count == 64,
           normalized.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) {
            return true
        }

        guard (2 ... 64).contains(normalized.count) else { return false }
        guard !normalized.hasPrefix("."),
              !normalized.hasSuffix("."),
              !normalized.hasPrefix("-"),
              !normalized.hasSuffix("-"),
              !normalized.hasPrefix("_"),
              !normalized.hasSuffix("_") else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let separators = CharacterSet(charactersIn: "._-")
        var previousWasSeparator = false
        for scalar in normalized.unicodeScalars {
            let isSeparator = separators.contains(scalar)
            if isSeparator && previousWasSeparator {
                return false
            }
            previousWasSeparator = isSeparator
        }
        return true
    }

    static func isValidPolkadotAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return (47 ... 50).contains(trimmed.count)
            && trimmed.allSatisfy { allowed.contains($0) }
    }

    static func isValidMoneroAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let allowed = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        let isAllowedCharset = trimmed.allSatisfy { allowed.contains($0) }
        guard isAllowedCharset else { return false }

        // Mainnet primary/subaddress lengths are typically 95 chars.
        // Integrated addresses are typically 106 chars.
        let validLength = trimmed.count == 95 || trimmed.count == 106
        guard validLength else { return false }

        // Mainnet: primary starts with '4', subaddress starts with '8'.
        return trimmed.hasPrefix("4") || trimmed.hasPrefix("8")
    }

    static func isValidCardanoAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Basic fallback for common Shelley-era bech32 forms.
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("addr1") || lowered.hasPrefix("addr_test1") {
            return trimmed.count >= 40
        }
        return false
    }
}
