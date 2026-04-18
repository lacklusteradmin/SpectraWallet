import Foundation

enum EVMChainContext: Equatable {
    case ethereum
    case ethereumSepolia
    case ethereumHoodi
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    var displayName: String {
        switch self {
        case .ethereum:         return "Ethereum"
        case .ethereumSepolia:  return "Ethereum Sepolia"
        case .ethereumHoodi:    return "Ethereum Hoodi"
        case .ethereumClassic:  return "Ethereum Classic"
        case .arbitrum:         return "Arbitrum"
        case .optimism:         return "Optimism"
        case .bnb:              return "BNB Chain"
        case .avalanche:        return "Avalanche"
        case .hyperliquid:      return "Hyperliquid"
        }}
    var tokenTrackingChain: TokenTrackingChain? {
        switch self {
        case .ethereum:                     return .ethereum
        case .ethereumSepolia, .ethereumHoodi, .ethereumClassic: return nil
        case .arbitrum:                     return .arbitrum
        case .optimism:                     return .optimism
        case .bnb:                          return .bnb
        case .avalanche:                    return .avalanche
        case .hyperliquid:                  return .hyperliquid
        }}
    var expectedChainID: Int {
        switch self {
        case .ethereum:         return 1
        case .ethereumSepolia:  return 11_155_111
        case .ethereumHoodi:    return 560_048
        case .ethereumClassic:  return 61
        case .arbitrum:         return 42161
        case .optimism:         return 10
        case .bnb:              return 56
        case .avalanche:        return 43114
        case .hyperliquid:      return 999
        }}
    var defaultDerivationPath: String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: return "m/44'/60'/0'/0/0"
        case .ethereumClassic: return "m/44'/61'/0'/0/0"
        }}
    func derivationPath(account: UInt32) -> String {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: return "m/44'/60'/\(account)'/0/0"
        case .ethereumClassic: return "m/44'/61'/\(account)'/0/0"
        }}
    var defaultRPCEndpoints: [String] { AppEndpointDirectory.evmRPCEndpoints(for: displayName) }
    var isEthereumFamily: Bool {
        switch self {
        case .ethereum, .ethereumSepolia, .ethereumHoodi: return true
        default: return false
        }}
    var isEthereumMainnet: Bool { self == .ethereum }
}

// Send preview types are now UniFFI-generated from Rust (core/src/wallet_core.rs).
// Swift owns only the send *result* types (not yet lifted) + chain-specific enums used by the UI.


struct EthereumSendResult: Equatable {
    let fromAddress: String
    let transactionHash: String
    let rawTransactionHex: String
    let preview: EthereumSendPreview
    let verificationStatus: SendBroadcastVerificationStatus
}

enum EthereumNetworkMode: String, CaseIterable, Identifiable {
    case mainnet
    case sepolia
    case hoodi
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .sepolia:  return "Sepolia"
        case .hoodi:    return "Hoodi"
        }}
}
enum BitcoinFeePriority: String, CaseIterable, Identifiable {
    case economy
    case normal
    case priority
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .economy:  return "Economy"
        case .normal:   return "Normal"
        case .priority: return "Priority"
        }}
}
enum DogecoinFeePriority: String, CaseIterable, Equatable, Codable {
    case economy
    case normal
    case priority
}
enum LitecoinChangeStrategy: String, CaseIterable, Identifiable {
    case derivedChange
    case reuseSourceAddress
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .derivedChange:      return "Derived change address"
        case .reuseSourceAddress: return "Reuse source address"
        }}
}
enum SolanaDerivationPreference {
    case standard
    case legacy
}

// MARK: - EVM address utilities (moved from Send/Engines/EVM/)

enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid EVM address."
        case .invalidResponse: return "Unexpected response from EVM provider."
        case .rpcFailure(let detail): return detail
        }}
}
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard AddressValidation.isValid(normalized, kind: "evm") else { throw EthereumWalletEngineError.invalidAddress }
    return normalized
}
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}

