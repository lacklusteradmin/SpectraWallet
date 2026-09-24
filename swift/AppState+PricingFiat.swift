import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// Called only while adopting a newer, coherent portfolio snapshot.
    func applyQuoteProjection(_ state: CoreAppState) {
        quoteRefreshError = state.quotes.pricesError
        fiatRatesRefreshError = state.quotes.fiatError
    }

    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        guard !isRefreshingFiatRates else { return }
        isRefreshingFiatRates = true
        defer { isRefreshingFiatRates = false }
        do {
            _ = try await self.bridge.ready().refreshOwnedFiatRates(force: force)
            await rebuildWalletDerivedStateFromCore()
        } catch {
            fiatRatesRefreshError = error.localizedDescription
        }
    }
    // ── Fiat currency (core-owned) ────────────────────────────────────────

    /// Load core's state and mirror it. Call once at launch.
    func loadCoreOwnedState() async {
        do {
            let state = try await self.bridge.openState()
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
            commandError = error.localizedDescription
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
    func scheduleImportedWalletRefresh(_ createdWallets: [WalletView]) {
        guard servicesEnabled else { return }
        guard !createdWallets.isEmpty else {
            return
        }
        importRefreshTask?.cancel()
        importRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCoreRefresh(.user)
            self.importRefreshTask = nil
        }
    }
    var alertableCoins: [Coin] { portfolio }
    var portfolio: [Coin] { cachedPortfolio }

}
/// Core's currencies, with what a picker needs: an order, a name and an icon.
/// The code comes from core's formatting rules, which carry it.
extension FiatCurrency: CaseIterable, Identifiable {
    private static let catalog = fiatCurrencyCatalog()
    public static var allCases: [FiatCurrency] { catalog.map(\.currency) }
    var displayRules: FiatAmountRules { Self.catalog.first { $0.currency == self }! }
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
    var displayName: String {
        switch self {
        case .usd: return AppLocalization.string("US Dollar (USD)")
        case .eur: return AppLocalization.string("Euro (EUR)")
        case .gbp: return AppLocalization.string("British Pound (GBP)")
        case .jpy: return AppLocalization.string("Japanese Yen (JPY)")
        case .cny: return AppLocalization.string("Chinese Yuan (CNY)")
        case .inr: return AppLocalization.string("Indian Rupee (INR)")
        case .cad: return AppLocalization.string("Canadian Dollar (CAD)")
        case .aud: return AppLocalization.string("Australian Dollar (AUD)")
        case .chf: return AppLocalization.string("Swiss Franc (CHF)")
        case .brl: return AppLocalization.string("Brazilian Real (BRL)")
        case .sgd: return AppLocalization.string("Singapore Dollar (SGD)")
        case .aed: return AppLocalization.string("UAE Dirham (AED)")
        }
    }
}
