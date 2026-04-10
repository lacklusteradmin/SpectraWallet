import Foundation

enum WalletDerivationBranch: Int {
    case external = 0
    case change = 1
}

enum WalletDerivationPath {
    static func bip44(
        slip44CoinType: UInt32,
        account: UInt32 = 0,
        branch: WalletDerivationBranch = .external,
        index: UInt32 = 0
    ) -> String {
        "m/44'/\(slip44CoinType)'/\(account)'/\(branch.rawValue)/\(index)"
    }

    static func dogecoin(
        account: UInt32 = 0,
        branch: WalletDerivationBranch = .external,
        index: UInt32 = 0
    ) -> String {
        bip44(slip44CoinType: 3, account: account, branch: branch, index: index)
    }

    static func dogecoinExternalPrefix(account: UInt32 = 0) -> String {
        "m/44'/3'/\(account)'/\(WalletDerivationBranch.external.rawValue)/"
    }

    static func dogecoinChangePrefix(account: UInt32 = 0) -> String {
        "m/44'/3'/\(account)'/\(WalletDerivationBranch.change.rawValue)/"
    }

    static func litecoin(
        account: UInt32 = 0,
        branch: WalletDerivationBranch = .external,
        index: UInt32 = 0
    ) -> String {
        bip44(slip44CoinType: 2, account: account, branch: branch, index: index)
    }

    static func bitcoinCash(
        account: UInt32 = 0,
        branch: WalletDerivationBranch = .external,
        index: UInt32 = 0
    ) -> String {
        bip44(slip44CoinType: 145, account: account, branch: branch, index: index)
    }

    static func bitcoinSV(
        account: UInt32 = 0,
        branch: WalletDerivationBranch = .external,
        index: UInt32 = 0
    ) -> String {
        bip44(slip44CoinType: 236, account: account, branch: branch, index: index)
    }
}

enum WalletCoreDerivationError: LocalizedError {
    case invalidMnemonic
    case invalidDerivationPath(String)
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return AppLocalization.string("Invalid mnemonic phrase for derivation.")
        case .invalidDerivationPath(let path):
            let format = AppLocalization.string("Invalid derivation path: %@")
            return String(format: format, locale: AppLocalization.locale, path)
        case .invalidPrivateKey:
            return AppLocalization.string("Invalid private key.")
        }
    }
}

struct DerivationPathSegment: Equatable {
    var value: UInt32
    var isHardened: Bool
}

enum DerivationPathParser {
    static func parse(_ rawPath: String) -> [DerivationPathSegment]? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/").map(String.init)
        guard components.first?.lowercased() == "m" else { return nil }

        return components.dropFirst().compactMap { component in
            let hardened = component.hasSuffix("'")
            let valueString = hardened ? String(component.dropLast()) : component
            guard let value = UInt32(valueString) else { return nil }
            return DerivationPathSegment(value: value, isHardened: hardened)
        }
    }

    static func normalize(_ rawPath: String, fallback: String) -> String {
        guard let segments = parse(rawPath) else { return fallback }
        return string(from: segments)
    }

    static func string(from segments: [DerivationPathSegment]) -> String {
        let suffix = segments.map { "\($0.value)\($0.isHardened ? "'" : "")" }.joined(separator: "/")
        return suffix.isEmpty ? "m" : "m/\(suffix)"
    }

    static func segmentValue(at index: Int, in rawPath: String) -> UInt32? {
        guard let segments = parse(rawPath), segments.indices.contains(index) else { return nil }
        return segments[index].value
    }

    static func replacingLastTwoSegments(in rawPath: String, branch: UInt32, index: UInt32, fallback: String) -> String {
        let normalized = normalize(rawPath, fallback: fallback)
        guard var segments = parse(normalized), segments.count >= 2 else { return fallback }
        segments[segments.count - 2] = DerivationPathSegment(value: branch, isHardened: false)
        segments[segments.count - 1] = DerivationPathSegment(value: index, isHardened: false)
        return string(from: segments)
    }
}

enum WalletCoreSupportedCoin {
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case tron
    case solana
    case stellar
    case xrp
    case cardano
    case sui
    case aptos
    case ton
    case internetComputer
    case near
    case polkadot

    var slip44CoinType: UInt32 {
        switch self {
        case .bitcoin: return 0
        case .bitcoinCash: return 145
        case .bitcoinSV: return 236
        case .litecoin: return 2
        case .dogecoin: return 3
        case .ethereum: return 60
        case .tron: return 195
        case .solana: return 501
        case .stellar: return 148
        case .xrp: return 144
        case .cardano: return 1815
        case .sui: return 784
        case .aptos: return 637
        case .ton: return 607
        case .internetComputer: return 223
        case .near: return 397
        case .polkadot: return 354
        }
    }

    var derivationChain: SeedDerivationChain {
        switch self {
        case .bitcoin: return .bitcoin
        case .bitcoinCash: return .bitcoinCash
        case .bitcoinSV: return .bitcoinSV
        case .litecoin: return .litecoin
        case .dogecoin: return .dogecoin
        case .ethereum: return .ethereum
        case .tron: return .tron
        case .solana: return .solana
        case .stellar: return .stellar
        case .xrp: return .xrp
        case .cardano: return .cardano
        case .sui: return .sui
        case .aptos: return .aptos
        case .ton: return .ton
        case .internetComputer: return .internetComputer
        case .near: return .near
        case .polkadot: return .polkadot
        }
    }
}

struct WalletCoreDerivationMaterial {
    let address: String
    let privateKeyData: Data
    let derivationPath: String
    let account: UInt32
    let branch: WalletDerivationBranch
    let index: UInt32
}
