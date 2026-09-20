import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// Called only while adopting a newer, coherent portfolio snapshot.
    func applyQuoteProjection(_ state: CoreAppState) {
        if livePrices != state.quotes.prices { livePrices = state.quotes.prices }
        quoteRefreshError = state.quotes.pricesError
        if fiatRatesFromUSD != state.fiatRatesFromUsd { fiatRatesFromUSD = state.fiatRatesFromUsd }
        fiatRatesRefreshError = state.quotes.fiatError
    }

    @discardableResult
    func refreshLivePrices() async -> Bool {
        guard !isRefreshingLivePrices else { return false }
        isRefreshingLivePrices = true
        defer { isRefreshingLivePrices = false }
        var didUpdatePrices = false
        let before = livePrices
        do {
            _ = try await self.bridge.refreshOwnedPrices(force: false)
            await rebuildWalletDerivedStateFromCore()
            didUpdatePrices = livePrices != before
        } catch {
            quoteRefreshError = error.localizedDescription
        }
        if didUpdatePrices { await evaluatePriceAlerts() }
        return didUpdatePrices
    }
    func refreshFiatExchangeRatesIfNeeded(force: Bool = false) async {
        guard !isRefreshingFiatRates else { return }
        isRefreshingFiatRates = true
        defer { isRefreshingFiatRates = false }
        do {
            _ = try await self.bridge.refreshOwnedFiatRates(force: force)
            await rebuildWalletDerivedStateFromCore()
        } catch {
            fiatRatesRefreshError = error.localizedDescription
        }
    }
    func activePriceKey(for coin: Coin) -> String { assetIdentityKey(for: coin) }
    // ── Fiat currency (core-owned) ────────────────────────────────────────

    /// Load core's state and mirror it. Call once at launch.
    func loadCoreOwnedState() async {
        let epoch = beginCoreStateRead()
        do {
            let state = try await self.bridge.openState()
            applyCoreState(state, epoch: epoch)
        } catch {
            finishCoreStateRead(epoch)
            appendOperationalLog(.error, category: "Storage", message: error.localizedDescription)
        }
    }

    /// Send the currency change to core and mirror the result.
    ///
    /// Core decides — it normalizes the code and reports whether anything
    /// actually changed, so the rate refresh only runs on a real change.
    func setFiatCurrency(_ currency: FiatCurrency) async {
        let epoch = beginCoreStateRead()
        guard
            let transition = try? await self.bridge.applyStateCommand(
                .setFiatCurrency(currency: currency))
        else {
            finishCoreStateRead(epoch)
            return
        }
        applyCoreState(transition.state, epoch: epoch)
        guard servicesEnabled, transition.events.contains(where: {
            if case .fiatCurrencyChanged = $0 { return true }
            return false
        }) else { return }
        await refreshFiatExchangeRatesIfNeeded(force: true)
    }

    var portfolioQuotedTotal: QuotedTotal? { portfolioValuation?.portfolio }
    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: String) {
        changeWallet(.setWalletPortfolioInclusion(walletId: walletID, included: isIncluded))
    }
    /// Refresh balances now. Every wallet's: the engine sweeps its entries
    /// together, and the one this is asked from is among them.
    func refreshBalancesNow() async {
        try? await self.bridge.triggerImmediateBalanceRefresh()
    }
    func scheduleImportedWalletRefresh(_ createdWallets: [WalletView]) {
        guard servicesEnabled else { return }
        guard !createdWallets.isEmpty else {
            return
        }
        importRefreshTask?.cancel()
        importRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshBalances()
            _ = await self.refreshLivePrices()
            await MainActor.run {
                self.importRefreshTask = nil
            }
        }
    }
    var alertableCoins: [Coin] { portfolio }
    var portfolio: [Coin] { cachedPortfolio }
    var shouldRunScheduledPriceRefresh: Bool { selectedMainTab == .home }
    var refreshableChainNames: Set<String> { cachedRefreshableChainNames }
    var includedPortfolioWallets: [WalletView] { cachedIncludedPortfolioWallets }
    func currentPriceIfAvailable(for coin: Coin) -> Double? {
        guard isPricedAsset(coin) else { return nil }
        guard let price = livePrices[activePriceKey(for: coin)], price.isFinite, price > 0 else { return nil }
        return price
    }
    func fiatRateIfAvailable(for currency: FiatCurrency) -> Double? {
        if currency == .usd { return 1.0 }
        guard let rate = fiatRatesFromUSD[currency.code], rate.isFinite, rate > 0 else { return nil }
        return rate
    }
}
/// Core's currencies, with what a picker needs: an order, a name and an icon.
/// The code comes from core's formatting rules, which carry it.
extension FiatCurrency: CaseIterable, Identifiable {
    public static var allCases: [FiatCurrency] {
        [.usd, .eur, .gbp, .jpy, .cny, .inr, .cad, .aud, .chf, .brl, .sgd, .aed]
    }
    public var id: String { code }
    /// The ISO 4217 code.
    var code: String { formattingFiatAmountRules(currency: self).code }
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
