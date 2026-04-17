import Foundation
enum WalletDerivationBranch: Int {
    case external = 0
    case change = 1
}
enum WalletDerivationPath {
    static func bip44(slip44CoinType: UInt32, account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String { "m/44'/\(slip44CoinType)'/\(account)'/\(branch.rawValue)/\(index)" }
    static func dogecoin(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String { bip44(slip44CoinType: 3, account: account, branch: branch, index: index) }
    static func dogecoinExternalPrefix(account: UInt32 = 0) -> String { "m/44'/3'/\(account)'/\(WalletDerivationBranch.external.rawValue)/" }
    static func dogecoinChangePrefix(account: UInt32 = 0) -> String { "m/44'/3'/\(account)'/\(WalletDerivationBranch.change.rawValue)/" }
    static func litecoin(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String { bip44(slip44CoinType: 2, account: account, branch: branch, index: index) }
    static func bitcoinCash(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String { bip44(slip44CoinType: 145, account: account, branch: branch, index: index) }
    static func bitcoinSV(account: UInt32 = 0, branch: WalletDerivationBranch = .external, index: UInt32 = 0) -> String { bip44(slip44CoinType: 236, account: account, branch: branch, index: index) }
}
enum WalletCoreDerivationError: LocalizedError {
    case invalidMnemonic
    case invalidDerivationPath(String)
    case invalidPrivateKey
    var errorDescription: String? {
        switch self {
        case .invalidMnemonic: return AppLocalization.string("Invalid mnemonic phrase for derivation.")
        case .invalidDerivationPath(let path): let format = AppLocalization.string("Invalid derivation path: %@")
            return String(format: format, locale: AppLocalization.locale, path)
        case .invalidPrivateKey: return AppLocalization.string("Invalid private key.")
        }}
}
struct DerivationPathSegment: Equatable {
    var value: UInt32
    var isHardened: Bool
}
enum DerivationPathParser {
    nonisolated static func parse(_ rawPath: String) -> [DerivationPathSegment]? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/").map(String.init)
        guard components.first?.lowercased() == "m" else { return nil }
        return components.dropFirst().compactMap { component in
            let hardened = component.hasSuffix("'")
            let valueString = hardened ? String(component.dropLast()) : component
            guard let value = UInt32(valueString) else { return nil }
            return DerivationPathSegment(value: value, isHardened: hardened)
        }}
    nonisolated static func normalize(_ rawPath: String, fallback: String) -> String {
        guard let segments = parse(rawPath) else { return fallback }
        return string(from: segments)
    }
    nonisolated static func string(from segments: [DerivationPathSegment]) -> String {
        let suffix = segments.map { "\($0.value)\($0.isHardened ? "'" : "")" }.joined(separator: "/")
        return suffix.isEmpty ? "m" : "m/\(suffix)"
    }
    nonisolated static func segmentValue(at index: Int, in rawPath: String) -> UInt32? {
        guard let segments = parse(rawPath), segments.indices.contains(index) else { return nil }
        return segments[index].value
    }
    nonisolated static func replacingLastTwoSegments(in rawPath: String, branch: UInt32, index: UInt32, fallback: String) -> String {
        let normalized = normalize(rawPath, fallback: fallback)
        guard var segments = parse(normalized), segments.count >= 2 else { return fallback }
        segments[segments.count - 2] = DerivationPathSegment(value: branch, isHardened: false)
        segments[segments.count - 1] = DerivationPathSegment(value: index, isHardened: false)
        return string(from: segments)
    }
}
