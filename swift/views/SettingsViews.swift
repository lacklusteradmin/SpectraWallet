import Foundation
import SwiftUI
struct SettingsView: View {
    @Bindable var store: AppState
    @State private var isShowingResetWalletWarning: Bool = false
    private enum Route: Hashable {
        case addressBook
        case trackedTokens
        case decimalDisplay
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
        @Bindable var preferences = store.preferences
        return NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: SpectraLayout.sectionSpacing) {
                        settingsCard(title: "Wallet & Transfers") {
                            settingsLink("Address Book", systemImage: "book.closed", route: .addressBook)
                            settingsDivider
                            settingsLink("Tracked Tokens", systemImage: "bitcoinsign.bank.building", route: .trackedTokens)
                        }
                        settingsCard(title: "Display") {
                            settingsToggle("Hide balances", systemImage: "eye.slash", isOn: $preferences.hideBalances)
                            settingsDivider
                            settingsLink("Decimal Display", systemImage: "number", route: .decimalDisplay)
                            settingsDivider
                            settingsLink("Appearance", systemImage: "circle.lefthalf.filled", route: .appearance)
                        }
                        settingsCard(title: "Sync & Automation") {
                            settingsLink("Refresh Frequency", systemImage: "arrow.triangle.2.circlepath", route: .refreshFrequency)
                        }
                        settingsCard(title: "Notifications") {
                            settingsLink("Price Alerts", systemImage: "bell.badge", route: .priceAlerts)
                            settingsDivider
                            settingsToggle(
                                "Transaction Status Updates", systemImage: "clock.badge.checkmark",
                                isOn: Binding(
                                    get: { preferences.useTransactionStatusNotifications },
                                    set: { preferences.useTransactionStatusNotifications = $0 }))
                            settingsDivider
                            settingsLink("Large Movement Alerts", systemImage: "chart.line.uptrend.xyaxis", route: .largeMovementAlerts)
                        }
                        settingsCard(title: "Security & Privacy") {
                            settingsToggle("Use Face ID", systemImage: "faceid", isOn: $preferences.useFaceID)
                            settingsDivider
                            settingsToggle("Auto Lock", systemImage: "lock", isOn: $preferences.useAutoLock)
                                .disabled(!preferences.useFaceID)
                        }
                        settingsCard(title: "Tor") {
                            NavigationLink(value: Route.tor) {
                                HStack(spacing: 12) {
                                    settingsIcon("network.badge.shield.half.filled")
                                    Text(AppLocalization.string("Tor Network")).font(.body).foregroundStyle(Color.primary)
                                    Spacer(minLength: 8)
                                    TorStatusBadge(status: store.torStatus)
                                    settingsChevron
                                }.padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.rowVertical)
                            }.buttonStyle(.plain)
                        }
                        settingsCard(title: "Data & Connectivity") {
                            settingsLink("Pricing", systemImage: "dollarsign.circle", route: .pricing)
                            settingsDivider
                            settingsLink("Endpoints", systemImage: "network", route: .endpoints)
                        }
                        settingsCard(title: "Diagnostics & Support") {
                            settingsLink("Diagnostics", systemImage: "waveform.path.ecg.rectangle", route: .diagnostics)
                            settingsDivider
                            settingsLink("Operational Logs", systemImage: "doc.text.magnifyingglass", route: .operationalLogs)
                            settingsDivider
                            settingsLink("Report a Problem", systemImage: "exclamationmark.bubble", route: .reportProblem)
                        }
                        settingsCard(title: "Help") {
                            settingsLink("Where can I buy crypto?", systemImage: "creditcard", route: .buyCryptoHelp)
                        }
                        settingsCard(title: "About") {
                            settingsLink("About Spectra", systemImage: "info.circle", route: .about)
                            settingsDivider
                            settingsLink("Chain Wiki", systemImage: "books.vertical", route: .chainWiki)
                            settingsDivider
                            settingsLink("Donate", systemImage: "heart", route: .donate)
                        }
                        settingsCard(title: "Advanced") {
                            settingsLink("Advanced", systemImage: "slider.horizontal.3", route: .advanced)
                        }
                        settingsCard(title: "Reset") {
                            Button(role: .destructive) {
                                isShowingResetWalletWarning = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash").font(.body.weight(.semibold)).frame(width: 22)
                                    Text(AppLocalization.string("Reset Wallet")).font(.body)
                                    Spacer()
                                }.foregroundStyle(.red).padding(.horizontal, SpectraLayout.rowHorizontal)
                                    .padding(.vertical, SpectraLayout.rowVertical)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, SpectraLayout.screenHorizontal).padding(.top, SpectraLayout.screenTop)
                    .padding(.bottom, SpectraLayout.screenBottom)
                }
            }.navigationTitle(AppLocalization.string("Settings")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                switch route {
                case .addressBook: AddressBookView(store: store)
                case .trackedTokens: TokenRegistrySettingsView(store: store)
                case .decimalDisplay: DecimalDisplaySettingsView(store: store)
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
    @ViewBuilder
    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppLocalization.string(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.horizontal, SpectraLayout.rowHorizontal)
                .padding(.top, SpectraLayout.cardHeaderVertical).padding(.bottom, 6)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: SpectraLayout.cardCornerRadius))
    }
    @ViewBuilder
    private func settingsLink(_ title: String, systemImage: String, route: Route) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                settingsIcon(systemImage)
                Text(AppLocalization.string(title)).font(.body).foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                settingsChevron
            }.padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.rowVertical)
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private func settingsToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                settingsIcon(systemImage)
                Text(AppLocalization.string(title)).font(.body).foregroundStyle(Color.primary)
            }
        }.tint(.orange).padding(.horizontal, SpectraLayout.rowHorizontal).padding(.vertical, SpectraLayout.rowVertical)
    }
    private func settingsIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage).font(.body.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
    }
    private var settingsChevron: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
    }
    private var settingsDivider: some View {
        Divider().opacity(0.25).padding(.leading, SpectraLayout.rowHorizontal + 34)
    }
}
