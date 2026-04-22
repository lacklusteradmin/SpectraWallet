import Foundation
import SwiftUI
struct SettingsView: View {
    @Bindable var store: AppState
    @State private var isShowingResetWalletWarning: Bool = false
    private enum Route: Hashable {
        case addressBook
        case trackedTokens
        case feePriorities
        case iconStyles
        case decimalDisplay
        case refreshFrequency
        case priceAlerts
        case largeMovementAlerts
        case pricing
        case endpoints
        case diagnostics
        case operationalLogs
        case reportProblem
        case buyCryptoHelp
        case about
        case chainWiki
        case advanced
    }
    var body: some View {
        @Bindable var preferences = store.preferences
        return NavigationStack {
            Form {
                Section(AppLocalization.string("Wallet & Transfers")) {
                    NavigationLink(value: Route.addressBook) {
                        Label(AppLocalization.string("Address Book"), systemImage: "book.closed")
                    }
                    NavigationLink(value: Route.trackedTokens) {
                        Label(AppLocalization.string("Tracked Tokens"), systemImage: "bitcoinsign.bank.building")
                    }
                    NavigationLink(value: Route.feePriorities) {
                        Label(AppLocalization.string("Fee Priorities"), systemImage: "dial.medium")
                    }
                }
                Section(AppLocalization.string("Display")) {
                    NavigationLink(value: Route.iconStyles) {
                        Label(AppLocalization.string("Icon Styles"), systemImage: "photo.on.rectangle")
                    }
                    Toggle(isOn: $preferences.hideBalances) {
                        Label(AppLocalization.string("Hide balances"), systemImage: "eye.slash")
                    }
                    NavigationLink(value: Route.decimalDisplay) {
                        Label(AppLocalization.string("Decimal Display"), systemImage: "number")
                    }
                }
                Section(AppLocalization.string("Sync & Automation")) {
                    NavigationLink(value: Route.refreshFrequency) {
                        Label(AppLocalization.string("Refresh Frequency"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section(AppLocalization.string("Notifications")) {
                    NavigationLink(value: Route.priceAlerts) {
                        Label(AppLocalization.string("Price Alerts"), systemImage: "bell.badge")
                    }
                    Toggle(
                        isOn: Binding(
                            get: { preferences.useTransactionStatusNotifications }, set: { preferences.useTransactionStatusNotifications = $0 })
                    ) {
                        Label(AppLocalization.string("Transaction Status Updates"), systemImage: "clock.badge.checkmark")
                    }
                    NavigationLink(value: Route.largeMovementAlerts) {
                        Label(AppLocalization.string("Large Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                Section(AppLocalization.string("Security & Privacy")) {
                    Toggle(isOn: $preferences.useFaceID) {
                        Label(AppLocalization.string("Use Face ID"), systemImage: "faceid")
                    }
                    Toggle(isOn: $preferences.useAutoLock) {
                        Label(AppLocalization.string("Auto Lock"), systemImage: "lock")
                    }.disabled(!preferences.useFaceID)
                }
                Section(AppLocalization.string("Data & Connectivity")) {
                    NavigationLink(value: Route.pricing) {
                        Label(AppLocalization.string("Pricing"), systemImage: "dollarsign.circle")
                    }
                    NavigationLink(value: Route.endpoints) {
                        Label(AppLocalization.string("Endpoints"), systemImage: "network")
                    }
                }
                Section(AppLocalization.string("Diagnostics & Support")) {
                    NavigationLink(value: Route.diagnostics) {
                        Label(AppLocalization.string("Diagnostics"), systemImage: "waveform.path.ecg.rectangle")
                    }
                    NavigationLink(value: Route.operationalLogs) {
                        Label(AppLocalization.string("Operational Logs"), systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(value: Route.reportProblem) {
                        Label(AppLocalization.string("Report a Problem"), systemImage: "exclamationmark.bubble")
                    }
                }
                Section(AppLocalization.string("Help")) {
                    NavigationLink(value: Route.buyCryptoHelp) {
                        Label(AppLocalization.string("Where can I buy crypto?"), systemImage: "creditcard")
                    }
                }
                Section(AppLocalization.string("About")) {
                    NavigationLink(value: Route.about) {
                        Label(AppLocalization.string("About Spectra"), systemImage: "info.circle")
                    }
                    NavigationLink(value: Route.chainWiki) {
                        Label(AppLocalization.string("Chain Wiki"), systemImage: "books.vertical")
                    }
                }
                Section(AppLocalization.string("Advanced")) {
                    NavigationLink(value: Route.advanced) {
                        Label(AppLocalization.string("Advanced"), systemImage: "slider.horizontal.3")
                    }
                }
                Section(AppLocalization.string("Reset")) {
                    Button(role: .destructive) {
                        isShowingResetWalletWarning = true
                    } label: {
                        Label(AppLocalization.string("Reset Wallet"), systemImage: "trash")
                    }
                }
            }.navigationTitle(AppLocalization.string("Settings"))
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                switch route {
                case .addressBook: AddressBookView(store: store)
                case .trackedTokens: TokenRegistrySettingsView(store: store)
                case .feePriorities: ChainFeePrioritySettingsView(store: store)
                case .iconStyles: TokenIconSettingsView()
                case .decimalDisplay: DecimalDisplaySettingsView(store: store)
                case .refreshFrequency: BackgroundSyncSettingsView(store: store)
                case .priceAlerts: PriceAlertsView(store: store)
                case .largeMovementAlerts: LargeMovementAlertsSettingsView(store: store)
                case .pricing: PricingSettingsView(store: store)
                case .endpoints: EndpointCatalogSettingsView(store: store)
                case .diagnostics: DiagnosticsHubView(store: store)
                case .operationalLogs: LogsView(store: store)
                case .reportProblem: ReportProblemView()
                case .buyCryptoHelp: BuyCryptoHelpView()
                case .about: AboutView()
                case .chainWiki: ChainWikiLibraryView()
                case .advanced: AdvancedSettingsView(store: store)
                }
            }.sheet(isPresented: $isShowingResetWalletWarning) {
                ResetWalletWarningView(store: store)
            }
        }
    }
}
