import Foundation
import SwiftUI
struct PricingSettingsView: View {
    let store: AppState
    var body: some View {
        Form {
            Section(AppLocalization.string("Display Currency")) {
                Picker(
                    AppLocalization.string("Currency"),
                    selection: store.settingBinding(\.fiatCurrency) { .fiatCurrency(value: $0) }
                ) {
                    ForEach(FiatCurrency.allCases) { currency in Text(currency.displayName).tag(currency) }
                }.pickerStyle(.menu)
            }
            if let quoteRefreshError = store.quoteRefreshError {
                Section {
                    Text(quoteRefreshError).font(.caption).foregroundStyle(.red)
                }
            }
            if let fiatRatesRefreshError = store.fiatRatesRefreshError {
                Section {
                    Text(fiatRatesRefreshError).font(.caption).foregroundStyle(.red)
                }
            }
        }.navigationTitle(AppLocalization.string("Pricing"))
    }
}
