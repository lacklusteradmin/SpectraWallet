import Foundation

/// Errors thrown by EVM address/contract operations.
enum EthereumWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid EVM address."
        case .invalidResponse:
            return "Unexpected response from EVM provider."
        case .rpcFailure(let detail):
            return detail
        }
    }
}

/// Standalone EVM address utilities.
///
/// These are pure string functions — no chain SDK dependency — so they can be
/// called from any layer (store, fetch, history, views) without importing the
/// full engine.

/// Lowercase-trim an EVM address. Returns the address with whitespace stripped
/// and all hex characters lowercased. Does not validate format.
func normalizeEVMAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// Return true iff `address` is a syntactically valid EVM address
/// (0x-prefixed, exactly 40 hex characters, case-insensitive).
func isValidEVMAddress(_ address: String) -> Bool {
    let normalized = normalizeEVMAddress(address)
    guard normalized.count == 42, normalized.hasPrefix("0x") else { return false }
    return normalized.dropFirst(2).allSatisfy(\.isHexDigit)
}

/// Normalize and validate. Throws `EthereumWalletEngineError.invalidAddress` on failure.
func validateEVMAddress(_ address: String) throws -> String {
    let normalized = normalizeEVMAddress(address)
    guard isValidEVMAddress(normalized) else {
        throw EthereumWalletEngineError.invalidAddress
    }
    return normalized
}

/// Canonical receive-address form — identical to validate for EVM (no HD derivation needed).
func receiveEVMAddress(for address: String) throws -> String {
    try validateEVMAddress(address)
}
