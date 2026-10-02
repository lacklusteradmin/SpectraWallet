import Foundation
import SwiftUI
extension AppState {
    /// Called only while adopting a newer, coherent portfolio snapshot.
    func applyQuoteProjection(_ state: CoreAppState) {
        if quoteRefreshError != state.quotes.pricesError { quoteRefreshError = state.quotes.pricesError }
        if fiatRatesRefreshError != state.quotes.fiatError { fiatRatesRefreshError = state.quotes.fiatError }
    }

    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        guard !isRefreshingFiatRates else { return }
        isRefreshingFiatRates = true
        defer { isRefreshingFiatRates = false }
        do {
            _ = try await self.bridge.ready().refreshOwnedFiatRates(force: force)
            await rebuildWalletDerivedStateFromCore()
        } catch {
            fiatRatesRefreshError = userErrorMessage(error)
        }
    }
    // ── Fiat currency (core-owned) ────────────────────────────────────────

    /// Load core's state and mirror it. `ready()` has opened the database, so
    /// this reads what core holds rather than opening it again.
    func loadCoreOwnedState() async {
        do {
            let state = try await self.bridge.ready().appState()
            applyCoreState(state)
        } catch {
            appendOperationalLog(.error, category: "Storage", message: error.localizedDescription)
        }
    }

    /// Send the currency change to core and mirror the result.
    ///
    /// Core decides — it normalizes the code and reports whether anything
    /// actually changed, so the rate refresh only runs on a real change.
    func setFiatCurrency(_ currency: FiatCurrency) async {
        let transition: StateTransition
        do {
            transition = try await applyStateCommand(.setFiatCurrency(currency: currency))
            commandError = nil
        } catch {
            reportCommandError(error)
            return
        }
        guard servicesEnabled, transition.events.contains(where: {
            if case .fiatCurrencyChanged = $0 { return true }
            return false
        }) else { return }
        await refreshFiatExchangeRatesIfNeeded(force: true)
    }

    var portfolioQuotedTotal: QuotedTotal? { portfolioValuation?.portfolio }
    func setPortfolioInclusion(_ isIncluded: Bool, for walletId: String) {
        sendStateCommand(.setWalletPortfolioInclusion(walletId: walletId, included: isIncluded))
    }
    var portfolio: [Coin] { walletDerivedCache.portfolio }
}

/// Core's currencies, with what a picker needs: an order, a name and an icon.
/// The code comes from core's formatting rules, which carry it.
extension FiatCurrency: CaseIterable, Identifiable {
    private static let catalog = fiatCurrencyCatalog()
    private static let rulesByCurrency = Dictionary(uniqueKeysWithValues: catalog.map { ($0.currency, $0) })
    public static var allCases: [FiatCurrency] { catalog.map(\.currency) }
    var displayRules: FiatAmountRules { Self.rulesByCurrency[self]! }
    public var id: String { code }
    /// The ISO 4217 code.
    var code: String { displayRules.code }
    var iconName: String? {
        switch self {
        case .usd: return "fiat/usd"
        case .eur: return "fiat/eur"
        case .gbp: return "fiat/gbp"
        case .cny: return "fiat/cny"
        case .jpy, .inr, .cad, .aud, .chf, .brl, .sgd, .aed: return nil
        }
    }
    /// The currency's name and code, in the display language. The system
    /// names every ISO 4217 currency, so no table here has to.
    var displayName: String {
        let name = AppLocalization.locale.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}
