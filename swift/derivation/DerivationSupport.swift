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

