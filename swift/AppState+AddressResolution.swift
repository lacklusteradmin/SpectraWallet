import Foundation

// MARK: - Responsibility
//
// This file holds **address-resolution logic only**: given a wallet,
// return a derived/stored address for a particular chain. No UI state
// (no `isResolving…` flags, no `receive…` mutations, no presentation
// helpers) lives here. UI state for the receive flow lives in
// `AppState+ReceiveFlow.swift`; mixing the two was a known god-object
// problem flagged in the readability audit.
//
// Convention for new methods in this file: pure read of wallet + AppState
// derivation context; return an optional `String` address; no side
// effects. If a method needs to flip a UI flag, it belongs in
// `AppState+ReceiveFlow` and should *call* into one of these resolvers,
// not own the resolution logic itself.


@MainActor
extension AppState {
    /// The address core stored for this wallet on `chainName`.
    ///
    /// A read, not a derivation. This file used to derive: per call, on the
    /// render path, it pulled the seed out of the Keychain, resolved a path,
    /// called the deriver and validated the result — for a value core had
    /// already computed and stored at import. A password-sealed wallet has no
    /// seed to pull, so it fell through to the stored mainnet address whatever
    /// network it was on, and said nothing about it.
    ///
    /// The network is part of the question: a wallet on Bitcoin Testnet4 has a
    /// different key and a different address, and core stores one per network
    /// of the family, each under that network's own slot. The EVM family shares
    /// Ethereum's slot, which is how an Ethereum wallet answers for Arbitrum.
    /// A chain the wallet was never imported for has no address here, and no
    /// seed is read to invent one.
    func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        guard let chain = Chain(displayName: chainName) else { return nil }
        let network = Chain(id: walletNetworkChainID(for: wallet, family: chain.mainnetCounterpart.id))
        return wallet.addresses[network?.addressSlot ?? chain.addressSlot]
            ?? wallet.addresses[chain.addressSlot]
    }
}
/// Pure-function cache for `coreValidateAddress` / `coreValidateStringIdentifier`.
///
/// `AddressValidation.isValid` / `normalized` used to hit a Rust FFI call
/// **per keystroke** in the watch-only setup flow, the address-book form,
/// the send form, etc. — via SwiftUI body re-evaluations even when the
/// input text didn't actually change. Results are deterministic in their
/// inputs, so we memoize them and cap the cache at a small size so user
/// input can't grow it unbounded.
private final class AddressValidationCache: @unchecked Sendable {
    static let shared = AddressValidationCache()
    private let lock = NSLock()
    /// One cache. There were two, of the same type, keyed the same way, because
    /// core had two exports and two identical record pairs for "is this typed
    /// string well formed, and how is it spelled".
    private var addressCache: [String: AddressValidationResult] = [:]
    private static let maxEntries = 512
    private init() {}
    func address(_ address: String, kind: String) -> AddressValidationResult {
        let key = "\(kind)|\(address)"
        lock.lock()
        if let cached = addressCache[key] { lock.unlock(); return cached }
        lock.unlock()
        let result = coreValidateAddress(request: AddressValidationRequest(kind: kind, value: address))
        lock.lock()
        defer { lock.unlock() }
        if addressCache.count > Self.maxEntries {
            addressCache.removeAll(keepingCapacity: true)
        }
        addressCache[key] = result
        return result
    }
}

enum AddressValidation {
    static func isValid(_ address: String, kind: String) -> Bool {
        AddressValidationCache.shared.address(address, kind: kind).isValid
    }
    static func normalized(_ address: String, kind: String) -> String? {
        AddressValidationCache.shared.address(address, kind: kind).normalizedValue
    }
    static func isValidAptosTokenType(_ value: String) -> Bool {
        AddressValidationCache.shared.address(value, kind: "aptosTokenType").isValid
    }
}
