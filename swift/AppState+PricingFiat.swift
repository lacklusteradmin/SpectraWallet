import Foundation
import SwiftUI
@MainActor
extension AppState {
    /// A quote response cannot overwrite newer wallet or network settings.
    func applyQuoteProjection(_ state: CoreAppState) {
        let priceAttempt = state.quotes.pricesAttemptAt ?? 0
        if priceAttempt >= projectedPriceAttempt {
            projectedPriceAttempt = priceAttempt
            if livePrices != state.quotes.prices { livePrices = state.quotes.prices }
            quoteRefreshError = state.quotes.pricesError
        }
        let fiatAttempt = state.quotes.fiatAttemptAt ?? 0
        if fiatAttempt >= projectedFiatAttempt {
            projectedFiatAttempt = fiatAttempt
            if fiatRatesFromUSD != state.fiatRatesFromUsd { fiatRatesFromUSD = state.fiatRatesFromUsd }
            fiatRatesRefreshError = state.quotes.fiatError
        }
    }

    @discardableResult
    func refreshLivePrices() async -> Bool {
        guard !isRefreshingLivePrices else { return false }
        isRefreshingLivePrices = true
        defer {
            isRefreshingLivePrices = false
            lastLivePriceRefreshAt = Date()
        }
        var didUpdatePrices = false
        let before = livePrices
        do {
            let state = try await WalletServiceBridge.shared.refreshOwnedPrices(force: false)
            applyQuoteProjection(state)
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
            let state = try await WalletServiceBridge.shared.refreshOwnedFiatRates(force: force)
            applyQuoteProjection(state)
        } catch {
            fiatRatesRefreshError = error.localizedDescription
        }
    }
    func refreshFiatExchangeRates() async {
        await refreshFiatExchangeRatesIfNeeded(force: true)
    }
    func activePriceKey(for coin: Coin) -> String { assetIdentityKey(for: coin) }
    var totalBalance: Double {
        portfolio.reduce(0) { $0 + currentValue(for: $1) }
    }
    // ── Fiat currency (core-owned) ────────────────────────────────────────

    /// Load core's state and mirror it. Call once at launch.
    func loadCoreOwnedState() async {
        let epoch = beginCoreStateRead()
        guard let state = try? await WalletServiceBridge.shared.openState() else { return }
        applyCoreState(state, epoch: epoch)
    }

    /// Send the currency change to core and mirror the result.
    ///
    /// Core decides — it normalizes the code and reports whether anything
    /// actually changed, so the rate refresh only runs on a real change.
    func setFiatCurrency(_ currency: FiatCurrency) async {
        let epoch = beginCoreStateRead()
        guard
            let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                .setFiatCurrency(fiatCurrencyCode: currency.rawValue))
        else { return }
        applyCoreState(transition.state, epoch: epoch)
        guard transition.events.contains(where: { $0.kind == "fiatCurrencyChanged" }) else { return }
        await refreshFiatExchangeRatesIfNeeded(force: true)
    }

    var portfolioQuotedTotal: QuotedTotal { quotedTotal(for: portfolio) }
    func setPortfolioInclusion(_ isIncluded: Bool, for walletID: String) {
        changeWallet(.setWalletPortfolioInclusion(walletId: walletID, included: isIncluded))
        resetLargeMovementAlertBaseline()
    }
    func refreshChainBalances(
        includeHistoryRefreshes: Bool = true, historyRefreshInterval: TimeInterval = 120, forceChainRefresh: Bool = true
    ) async {
        _ = forceChainRefresh  // Rust always fetches fresh data
        guard !isRefreshingChainBalances else { return }
        isRefreshingChainBalances = true
        try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        if includeHistoryRefreshes { await runHistoryRefreshes(for: refreshableChainIDs, interval: historyRefreshInterval) }
    }
    func withBalanceRefreshWindow(_ operation: () async -> Void) async {
        let previousState = allowsBalanceNetworkRefresh
        allowsBalanceNetworkRefresh = true
        defer { allowsBalanceNetworkRefresh = previousState }
        await operation()
    }
    func refreshWalletBalance(_ walletID: String) async {
        await withBalanceRefreshWindow {
            try? await WalletServiceBridge.shared.triggerImmediateBalanceRefresh()
        }
    }
    func scheduleImportedWalletRefresh(_ createdWallets: [ImportedWallet]) {
        guard !createdWallets.isEmpty else {
            resetLargeMovementAlertBaseline()
            return
        }
        importRefreshTask?.cancel()
        importRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.withBalanceRefreshWindow {
                await self.refreshBalances()
                _ = await self.refreshLivePrices()
            }
            await MainActor.run {
                self.resetLargeMovementAlertBaseline()
                self.importRefreshTask = nil
            }
        }
    }
    #if DEBUG
    #endif
}
enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cny = "CNY"
    case inr = "INR"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case brl = "BRL"
    case sgd = "SGD"
    case aed = "AED"
    var id: String { rawValue }
    var iconName: String? {
        switch self {
        case .usd: return "fiaticon/usd"
        case .eur: return "fiaticon/eur"
        case .gbp: return "fiaticon/gbp"
        case .cny: return "fiaticon/cny"
        default: return nil
        }
    }
    var displayName: String {
        switch self {
        case .usd: return "US Dollar (USD)"
        case .eur: return "Euro (EUR)"
        case .gbp: return "British Pound (GBP)"
        case .jpy: return "Japanese Yen (JPY)"
        case .cny: return "Chinese Yuan (CNY)"
        case .inr: return "Indian Rupee (INR)"
        case .cad: return "Canadian Dollar (CAD)"
        case .aud: return "Australian Dollar (AUD)"
        case .chf: return "Swiss Franc (CHF)"
        case .brl: return "Brazilian Real (BRL)"
        case .sgd: return "Singapore Dollar (SGD)"
        case .aed: return "UAE Dirham (AED)"
        }
    }
}
