import Foundation
import SwiftUI
struct SettingsView: View {
    @Bindable var store: AppState
    @State private var isShowingResetWalletWarning: Bool = false
    private enum Route: Hashable {
        case addressBook
        case knownTokens
        case appearance
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
        case donate
        case tor
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("Wallet & Transfers")) {
                    settingsLink("Address Book", systemImage: "book.closed", route: .addressBook)
                    settingsLink("Known Tokens", systemImage: "bitcoinsign.bank.building", route: .knownTokens)
                }
                Section(AppLocalization.string("Display")) {
                    settingsToggle("Hide balances", systemImage: "eye.slash", isOn: preferenceBinding(\.hideBalances))
                    settingsLink("Appearance", systemImage: "circle.lefthalf.filled", route: .appearance)
                }
                Section(AppLocalization.string("Sync & Automation")) {
                    settingsLink("Refresh Frequency", systemImage: "arrow.triangle.2.circlepath", route: .refreshFrequency)
                }
                Section(AppLocalization.string("Notifications")) {
                    settingsLink("Price Alerts", systemImage: "bell.badge", route: .priceAlerts)
                    settingsToggle(
                        "Transaction Status Updates", systemImage: "clock.badge.checkmark",
                        isOn: Binding(
                            get: { store.preferences.useTransactionStatusNotifications },
                            set: { store.preferences.useTransactionStatusNotifications = $0 }))
                    settingsLink("Large Movement Alerts", systemImage: "chart.line.uptrend.xyaxis", route: .largeMovementAlerts)
                }
                Section(AppLocalization.string("Security & Privacy")) {
                    settingsToggle("Use Face ID", systemImage: "faceid", isOn: preferenceBinding(\.useFaceID))
                    settingsToggle("Auto Lock", systemImage: "lock", isOn: preferenceBinding(\.useAutoLock))
                        .disabled(!store.preferences.useFaceID)
                }
                Section(AppLocalization.string("Tor")) {
                    NavigationLink(value: Route.tor) {
                        HStack(spacing: 12) {
                            Label(AppLocalization.string("Tor Network"), systemImage: "network.badge.shield.half.filled")
                            Spacer(minLength: 8)
                            settingsTorStatusBadge
                        }
                    }
                }
                Section(AppLocalization.string("Data & Connectivity")) {
                    settingsLink("Pricing", systemImage: "dollarsign.circle", route: .pricing)
                    settingsLink("Endpoints", systemImage: "network", route: .endpoints)
                }
                Section(AppLocalization.string("Diagnostics & Support")) {
                    settingsLink("Diagnostics", systemImage: "waveform.path.ecg.rectangle", route: .diagnostics)
                    settingsLink("Operational Logs", systemImage: "doc.text.magnifyingglass", route: .operationalLogs)
                    settingsLink("Report a Problem", systemImage: "exclamationmark.bubble", route: .reportProblem)
                }
                Section(AppLocalization.string("Help")) {
                    settingsLink("Where can I buy crypto?", systemImage: "creditcard", route: .buyCryptoHelp)
                }
                Section(AppLocalization.string("About")) {
                    settingsLink("About Spectra", systemImage: "info.circle", route: .about)
                    settingsLink("Chain Wiki", systemImage: "books.vertical", route: .chainWiki)
                    settingsLink("Donate", systemImage: "heart", route: .donate)
                }
                Section(AppLocalization.string("Advanced")) {
                    settingsLink("Advanced", systemImage: "slider.horizontal.3", route: .advanced)
                }
                Section(AppLocalization.string("Reset")) {
                    Button(role: .destructive) {
                        isShowingResetWalletWarning = true
                    } label: {
                        Label(AppLocalization.string("Reset Wallet"), systemImage: "trash")
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .addressBook: AddressBookView(store: store)
                case .knownTokens: TokenRegistrySettingsView(store: store)
                case .appearance: AppearanceSettingsView(preferences: store.preferences)
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
                case .donate: DonationsView()
                case .advanced: AdvancedSettingsView(store: store)
                case .tor: TorSettingsView(store: store)
                }
            }.sheet(isPresented: $isShowingResetWalletWarning) {
                ResetWalletWarningView(store: store)
            }
        }
    }

    private func preferenceBinding(_ keyPath: ReferenceWritableKeyPath<AppUserPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { store.preferences[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func settingsLink(_ title: String, systemImage: String, route: Route) -> some View {
        NavigationLink(value: route) {
            Label(AppLocalization.string(title), systemImage: systemImage)
        }
    }
    @ViewBuilder
    private func settingsToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(AppLocalization.string(title), systemImage: systemImage)
        }.tint(.orange)
    }

    private var settingsTorStatusBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(torStatusColor).frame(width: 6, height: 6)
            Text(AppLocalization.string(torStatusText))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(torStatusColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(torStatusColor.opacity(0.12), in: Capsule())
    }

    private var torStatusText: String {
        switch store.torStatus {
        case .stopped: return "Off"
        case .bootstrapping(let percent): return percent > 0 ? "\(percent)%" : "Starting"
        case .ready: return "On"
        case .error: return "Error"
        }
    }

    private var torStatusColor: Color {
        switch store.torStatus {
        case .stopped: return .secondary
        case .bootstrapping: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }
}
