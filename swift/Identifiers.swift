import Foundation

// MARK: - Typed identifiers
//
// String identifiers are scattered across the app's APIs — wallet IDs,
// holding keys, asset identifiers, transaction hashes — and they all
// look identical at the type level. The compiler can't catch swapped
// arguments like `f(walletID, assetID)` vs `f(assetID, walletID)` when
// both are `String`.
//
// These newtype wrappers tag the role of an identifier in the type
// system. Adoption is incremental: new APIs should accept these types
// directly; existing `String` parameters can adopt them as their call
// sites are touched. The wrappers are intentionally minimal — just a
// labeled `String` with `Hashable`/`Codable` — so they're free at
// runtime and substitutable in JSON/SQLite encoding.
//
// Each type's doc names the format expected (UUID hex, base58 mint,
// 0x-prefixed hex tx hash) so a reader knows the contract without
// having to grep for usage.

/// Unique identifier for an `ImportedWallet`. UUID-formatted hex string.
struct WalletID: Hashable, Codable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Composite key identifying a holding within a wallet — typically of the
/// form `"<chain>:<symbol>"` (e.g. `"ethereum:USDC"`). Produced by the
/// Rust core's `assetIdentityKey` helper; never construct ad-hoc.
struct HoldingKey: Hashable, Codable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Cross-chain asset identity — the value returned by
/// `Coin.normalizedIconIdentifier(for:)`. Used to look up a token's
/// visual treatment (icon, color) regardless of chain instance.
struct AssetIdentifier: Hashable, Codable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Chain-native transaction hash. Encoding varies by chain (0x-prefixed
/// hex for EVM, base58 for Solana, hex for Bitcoin family, base64 for
/// some Substrate paths) — the wrapper just tags the role; the encoding
/// is the chain's responsibility.
struct TransactionHash: Hashable, Codable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
}
