import Foundation

@MainActor
extension AppState {
    /// Render core's network-validated address projection.
    func resolvedAddress(for wallet: WalletView, chainName: String) -> String? {
        walletDerivedCache.resolvedAddressesByWalletId[wallet.id]?[chainName]
    }
}
/// Straight through to core. A locked, size-capped memo stood in front of it
/// for a pure call that costs less than the lock around it.
enum AddressValidation {
    static func isValid(_ address: String, kind: String) -> Bool {
        validateAddress(request: AddressValidationRequest(kind: kind, value: address)).isValid
    }
    static func normalized(_ address: String, kind: String) -> String? {
        validateAddress(request: AddressValidationRequest(kind: kind, value: address)).normalizedValue
    }
}
