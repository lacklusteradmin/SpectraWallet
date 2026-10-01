import Foundation

extension AppState {
    /// Send a price-alert edit. Core's refusal arrives as an event carrying its
    /// reason, and is thrown here in words.
    func editPriceAlert(_ command: StateCommand) async throws {
        let transition = try await applyStateCommand(command)
        for case .priceAlertRejected(let reason) in transition.events {
            throw DisplayedError(priceAlertRejectionMessage(reason))
        }
    }
    func priceAlertRejectionMessage(_ reason: PriceAlertRejection) -> String {
        switch reason {
        case .missingCurrencyRate:
            return AppLocalization.string("Exchange rates for this currency have not loaded yet. Try again shortly.")
        case .invalidTarget: return AppLocalization.string("Enter a target price above zero.")
        case .unknownAsset: return AppLocalization.string("This asset is no longer in your wallets.")
        case .duplicateAlert: return AppLocalization.string("An identical alert already exists.")
        case .alertNotFound: return AppLocalization.string("This alert no longer exists.")
        }
    }
}
