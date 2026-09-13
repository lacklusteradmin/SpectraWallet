import Foundation

@MainActor
extension AppState {
    /// Render core's network-validated address projection.
    func resolvedAddress(for wallet: WalletView, chainName: String) -> String? {
        walletDerivedCache.resolvedAddressesByWalletID[wallet.id]?[chainName]
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
}
