import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine
private func localizedSettingsString(_ key: String) -> String {
    AppLocalization.string(key)
}
private func localizedSettingsFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
struct PricingSettingsView: View {
    @ObservedObject var store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    private var copy: SettingsContentCopy { .current }
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            Section {
                Text(copy.pricingIntro).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Provider")) {
                Picker(selection: Binding(get: { store.pricingProvider }, set: { store.pricingProvider = $0 })) {
                    ForEach(PricingProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }} label: { EmptyView() }.pickerStyle(.inline).labelsHidden()
            }
            Section(localizedSettingsString("Display Currency")) {
                Picker(localizedSettingsString("Currency"), selection: Binding(get: { store.selectedFiatCurrency }, set: { store.selectedFiatCurrency = $0 })) {
                    ForEach(FiatCurrency.allCases) { currency in Text(currency.displayName).tag(currency) }}.pickerStyle(.menu)
            }
            Section(localizedSettingsString("Fiat Rate Provider")) {
                Picker(localizedSettingsString("Provider"), selection: Binding(get: { store.fiatRateProvider }, set: { store.fiatRateProvider = $0 })) {
                    ForEach(FiatRateProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }}.pickerStyle(.menu)
                Text(copy.fiatRateProviderNote).font(.caption).foregroundStyle(.secondary)
            }
            if store.pricingProvider == .coinGecko {
                Section(localizedSettingsString("CoinGecko")) {
                    TextField(
                        localizedSettingsString("CoinGecko Pro API Key (Optional)"), text: Binding(get: { store.coinGeckoAPIKey }, set: { store.coinGeckoAPIKey = $0 })
                    ).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(copy.coinGeckoNote).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(localizedSettingsString("Provider Notes")) { Text(copy.publicProviderNote).font(.caption).foregroundStyle(.secondary) }}
            if let quoteRefreshError = store.quoteRefreshError {
                Section {
                    Text(quoteRefreshError).font(.caption).foregroundStyle(.red)
                }}
            if let fiatRatesRefreshError = store.fiatRatesRefreshError {
                Section {
                    Text(fiatRatesRefreshError).font(.caption).foregroundStyle(.red)
                }}}.navigationTitle(localizedSettingsString("Pricing"))
    }
}
struct PriceAlertsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var selectedHoldingKey: String = ""
    @State private var selectedCondition: PriceAlertCondition = .above
    @State private var targetPriceText: String = ""
    @State private var formMessage: String?
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    private var alertableHoldingKeys: Set<String> { Set(store.alertableCoins.map(\.holdingKey)) }
    private var selectedCoin: Coin? {
        store.alertableCoins.first(where: { $0.holdingKey == selectedHoldingKey })
    }
    var body: some View {
        Form {
            Section {
                Text(localizedSettingsString("Create alert rules for imported assets. When the current price reaches your target, Spectra sends a local notification. Alerts depend on price refreshes from your selected pricing source and fall back to built-in prices when live data is unavailable. Spectra refreshes prices when the app becomes active and on a repeating in-app watch cycle while it stays open.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Notifications")) {
                Toggle(
                    localizedSettingsString("Enable Price Alerts"), isOn: Binding(get: { store.usePriceAlerts }, set: { store.usePriceAlerts = $0 })
                )
                Text(localizedSettingsString("You can keep rules configured even when alerts are disabled. Re-enable this later to resume notifications.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("New Alert")) {
                if store.alertableCoins.isEmpty { Text(localizedSettingsString("Import a wallet with assets first. Alerts are created from assets currently in your portfolio.")).font(.caption).foregroundStyle(.secondary) } else {
                    Picker(localizedSettingsString("Asset"), selection: $selectedHoldingKey) {
                        ForEach(store.alertableCoins, id: \.holdingKey) { coin in Text(localizedSettingsFormat("%@ on %@", coin.symbol, store.displayChainTitle(for: coin.chainName))).tag(coin.holdingKey) }}
                    Picker(localizedSettingsString("Condition"), selection: $selectedCondition) {
                        ForEach(PriceAlertCondition.allCases) { condition in Text(condition.displayName).tag(condition) }}.pickerStyle(.segmented)
                    TextField(localizedSettingsFormat("Target Price (%@)", store.selectedFiatCurrency.rawValue), text: $targetPriceText).keyboardType(.decimalPad)
                    if let selectedCoin { Text(localizedSettingsFormat("Current price: %@", store.formattedFiatAmountOrUnavailable(fromUSD: store.currentPriceIfAvailable(for: selectedCoin)))).font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout() }
                    if let formMessage { Text(formMessage).font(.caption).foregroundStyle(isDuplicateDraftAlert ? .orange : .secondary) }
                    Button(localizedSettingsString("Add Alert")) {
                        addAlert()
                    }.disabled(!canAddAlert)
                }}
            Section(localizedSettingsString("Active Alerts")) {
                if store.priceAlerts.isEmpty { Text(localizedSettingsString("No alerts configured yet.")).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(store.priceAlerts) { alert in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.titleText).font(.headline)
                                    Text("\(alert.condition.displayName) \(store.formattedFiatAmount(fromUSD: alert.targetPrice))").font(.caption).foregroundStyle(.secondary).spectraNumericTextLayout()
                                }
                                Spacer()
                                Text(alert.statusText).font(.caption.bold()).frame(minWidth: 78).padding(.horizontal, 8).padding(.vertical, 4).background(statusColor(for: alert).opacity(0.18), in: Capsule()).foregroundStyle(statusColor(for: alert))
                            }
                            HStack {
                                Button(alert.isEnabled ? localizedSettingsString("Pause") : localizedSettingsString("Resume")) {
                                    store.togglePriceAlertEnabled(id: alert.id)
                                }.buttonStyle(.borderless)
                                Spacer()
                                Button(localizedSettingsString("Remove"), role: .destructive) {
                                    store.removePriceAlert(id: alert.id)
                                }.buttonStyle(.borderless)
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }}}}.navigationTitle(localizedSettingsString("Price Alerts")).onAppear {
            syncSelection()
        }.onChange(of: store.walletsRevision) { _, _ in
            syncSelection()
        }}
    private var canAddAlert: Bool {
        guard selectedCoin != nil, let targetPrice = Double(targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)), targetPrice > 0 else { return false }
        return !isDuplicateDraftAlert
    }
    private var normalizedDraftTargetPrice: Double? {
        guard let targetPriceInSelectedFiat = Double(targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)), targetPriceInSelectedFiat > 0 else { return nil }
        let targetPriceUSD = store.convertSelectedFiatToUSD(targetPriceInSelectedFiat)
        return (targetPriceUSD * 100).rounded() / 100
    }
    private var isDuplicateDraftAlert: Bool {
        guard let selectedCoin, let normalizedDraftTargetPrice else { return false }
        return store.priceAlerts.contains { alert in
            alert.holdingKey == selectedCoin.holdingKey
                && alert.condition == selectedCondition
                && abs(alert.targetPrice - normalizedDraftTargetPrice) < 0.0001
        }}
    private func addAlert() {
        guard let selectedCoin, let targetPrice = normalizedDraftTargetPrice, targetPrice > 0 else { return }
        guard !isDuplicateDraftAlert else {
            formMessage = localizedSettingsString("An identical alert already exists for this asset.")
            return
        }
        store.addPriceAlert(for: selectedCoin, targetPrice: targetPrice, condition: selectedCondition)
        targetPriceText = ""
        selectedCondition = .above
        formMessage = localizedSettingsString("Alert added. Spectra will notify you when this target is hit.")
    }
    private func syncSelection() {
        if !alertableHoldingKeys.contains(selectedHoldingKey) { selectedHoldingKey = store.alertableCoins.first?.holdingKey ?? "" }}
    private func statusColor(for alert: PriceAlertRule) -> Color {
        if !alert.isEnabled { return .gray }
        return alert.hasTriggered ? .green : .orange
    }
}
struct AddressBookView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var contactName: String = ""
    @State private var selectedChainName: String = "Bitcoin"
    @State private var address: String = ""
    @State private var note: String = ""
    @State private var formMessage: String?
    @State private var editingEntry: AddressBookEntry?
    @State private var editedName: String = ""
    @State private var copiedEntryID: UUID?
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    private let supportedChains = ["Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar"]
    private var addressPrompt: String {
        switch selectedChainName {
        case "Bitcoin": return "bc1q..."
        case "Litecoin": return "ltc1... / L... / M..."
        case "Dogecoin": return "D..."
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Sui", "Aptos": return "0x..."
        case "Tron": return "T..."
        case "Solana": return "So111..."
        case "Cardano": return "addr1..."
        case "XRP Ledger": return "r..."
        case "Monero": return "4... / 8..."
        case "TON": return "UQ... / EQ..."
        case "Internet Computer": return "64-char account identifier"
        case "NEAR": return "alice.near / 64-char hex"
        case "Polkadot": return "1..."
        case "Stellar": return "G..."
        default: return ""
        }}
    private var addressValidationMessage: String {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) { return localizedSettingsFormat("This %@ address is already saved.", selectedChainName) }
        return store.addressBookAddressValidationMessage(for: address, chainName: selectedChainName)
    }
    private var addressValidationColor: Color {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) { return .orange }
        return store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) ? .green : .secondary
    }
    private var canRenameSelectedEntry: Bool {
        guard let editingEntry else { return false }
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName != editingEntry.name
    }
    var body: some View {
        Form {
            Section {
                Text(localizedSettingsString("Save trusted recipient addresses here so you can reuse them in Send without retyping. Spectra currently supports address book validation for Bitcoin, Litecoin, Dogecoin, Ethereum, Ethereum Classic, Arbitrum, Optimism, BNB Chain, Avalanche, Hyperliquid, Tron, Solana, Cardano, XRP Ledger, Monero, Sui, Aptos, TON, Internet Computer, NEAR, Polkadot, and Stellar.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("New Contact")) {
                TextField(localizedSettingsString("Name"), text: $contactName).textInputAutocapitalization(.words).autocorrectionDisabled()
                Picker(localizedSettingsString("Chain"), selection: $selectedChainName) {
                    ForEach(supportedChains, id: \.self) { chainName in Text(chainName).tag(chainName) }}
                TextField(addressPrompt, text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(addressValidationMessage).font(.caption).foregroundStyle(addressValidationColor)
                TextField(localizedSettingsString("Note (Optional)"), text: $note).textInputAutocapitalization(.sentences)
                if let formMessage { Text(formMessage).font(.caption).foregroundStyle(.secondary).foregroundColor(store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) ? nil : .red) }
                Button(localizedSettingsString("Save Contact")) {
                    saveContact()
                }.disabled(!store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName))
            }
            Section(localizedSettingsString("Saved Addresses")) {
                if store.addressBook.isEmpty { Text(localizedSettingsString("No saved recipients yet.")).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(store.addressBook) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.subtitleText).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                                }
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = entry.address
                                    copiedEntryID = entry.id
                                } label: {
                                    Label(copiedEntryID == entry.id ? localizedSettingsString("Copied") : localizedSettingsString("Copy"), systemImage: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc").font(.caption.weight(.semibold))
                                }.buttonStyle(.borderless)
                            }}.padding(.vertical, 4).swipeActions {
                            Button(localizedSettingsString("Edit")) {
                                editingEntry = entry
                                editedName = entry.name
                            }
                            Button(localizedSettingsString("Delete"), role: .destructive) {
                                store.removeAddressBookEntry(id: entry.id)
                            }}}}}}.navigationTitle(localizedSettingsString("Address Book")).sheet(item: $editingEntry) { entry in
            NavigationView {
                Form {
                    Section {
                        Text(localizedSettingsString("You can update the label for this saved address. The chain, address, and note stay fixed.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Section(localizedSettingsString("Saved Address")) {
                        Text(entry.chainName)
                        Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                        if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) }}
                    Section(localizedSettingsString("Label")) { TextField(localizedSettingsString("Name"), text: $editedName).textInputAutocapitalization(.words).autocorrectionDisabled() }}.navigationTitle(localizedSettingsString("Edit Label")).toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(localizedSettingsString("Cancel")) {
                            editingEntry = nil
                            editedName = ""
                        }}
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(localizedSettingsString("Save")) {
                            store.renameAddressBookEntry(id: entry.id, to: editedName)
                            editingEntry = nil
                            editedName = ""
                        }.disabled(!canRenameSelectedEntry)
                    }}}}}
    private func saveContact() {
        guard store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) else {
            formMessage = localizedSettingsFormat("Enter a unique valid %@ address and a contact name.", selectedChainName)
            return
        }
        store.addAddressBookEntry(name: contactName, address: address, chainName: selectedChainName, note: note)
        contactName = ""
        address = ""
        note = ""
        formMessage = localizedSettingsString("Address saved.")
    }
}
struct AboutView: View {
    @State private var isAnimatingHero = false
    private var copy: SettingsContentCopy { .current }
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    aboutHero
                    aboutCard(title: copy.aboutEthosTitle, lines: copy.aboutEthosLines)
                    aboutNarrativeCard
                }.padding(20)
            }}.navigationTitle(localizedSettingsString("About Spectra")).navigationBarTitleDisplayMode(.inline).onAppear {
            isAnimatingHero = true
        }}
    private var aboutHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(
                        AngularGradient(
                            colors: [
                                .red.opacity(0.85), .orange.opacity(0.92), .yellow.opacity(0.9), .green.opacity(0.82), .blue.opacity(0.82), .indigo.opacity(0.82), .pink.opacity(0.88), .red.opacity(0.85)
                            ], center: .center
                        )
                    ).frame(width: 220, height: 220).blur(radius: 26).rotationEffect(.degrees(isAnimatingHero ? 360 : 0)).animation(.linear(duration: 18).repeatForever(autoreverses: false), value: isAnimatingHero)
                Circle().fill(Color.white.opacity(0.08)).frame(width: 178, height: 178).background(.ultraThinMaterial, in: Circle())
                SpectraLogo(size: 96)
            }
            VStack(spacing: 8) {
                Text(copy.aboutTitle).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Color.primary)
                Text(copy.aboutSubtitle).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color.primary.opacity(0.78))
            }.frame(maxWidth: .infinity)
        }.padding(24).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 30))
    }
    private var aboutNarrativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.aboutNarrativeTitle).font(.headline).foregroundStyle(Color.primary)
            ForEach(copy.aboutNarrativeParagraphs, id: \.self) { paragraph in Text(paragraph).font(.subheadline).foregroundStyle(Color.primary.opacity(0.8)) }}.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
    private func aboutCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(Color.primary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.primary.opacity(0.5)).frame(width: 6, height: 6).padding(.top, 7)
                    Text(line).font(.subheadline).foregroundStyle(Color.primary.opacity(0.82))
                }}}.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
}
struct BackgroundSyncSettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            Section(localizedSettingsString("Refresh Frequency")) {
                Text(localizedSettingsString("Choose how often Spectra refreshes balances automatically while the app is active.")).font(.caption).foregroundStyle(.secondary)
                Stepper(value: Binding(get: { store.automaticRefreshFrequencyMinutes }, set: { store.automaticRefreshFrequencyMinutes = $0 }), in: 5...60, step: 5) {
                    LabeledContent(localizedSettingsString("Active app refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                }}
            Section(localizedSettingsString("Current Timing")) {
                LabeledContent(localizedSettingsString("Active app balance refresh"), value: "\(store.automaticRefreshFrequencyMinutes) min")
                LabeledContent(localizedSettingsString("Background balance refresh"), value: "\(store.backgroundBalanceRefreshFrequencyMinutes) min")
            }
            Section(localizedSettingsString("Hint")) {
                Label(localizedSettingsString("Lower refresh times can increase battery usage and network traffic."), systemImage: "bolt.batteryblock.fill").foregroundStyle(.orange)
                Text(localizedSettingsString("Choose a longer interval if you want lower background activity and less battery impact.")).font(.caption).foregroundStyle(.secondary)
            }
            if isTooFrequent(store.automaticRefreshFrequencyMinutes) {
                Section(localizedSettingsString("Warning")) {
                    Label(localizedSettingsString("This refresh speed can increase battery usage and network traffic."), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(localizedSettingsString("Use this mode only if you need near-real-time updates.")).font(.caption).foregroundStyle(.secondary)
                }}}.navigationTitle(localizedSettingsString("Background Sync"))
    }
    private func isTooFrequent(_ minutes: Int) -> Bool { minutes <= 10 }
}
struct ChainFeePrioritySettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    private struct ChainFeePrioritySetting: Identifiable {
        let chainName: String
        let title: String
        let detail: String
        var id: String { chainName }}
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            ForEach(chainFeePrioritySettings) { item in
                Section(localizedSettingsString(item.chainName)) {
                    Picker(localizedSettingsString(item.title), selection: Binding(
                        get: { store.feePriorityOption(for: item.chainName) }, set: { store.setFeePriorityOption($0, for: item.chainName) }
                    )) {
                        ForEach(ChainFeePriorityOption.allCases) { priority in Text(priority.displayName).tag(priority) }}.pickerStyle(.segmented)
                    Text(localizedSettingsString(item.detail)).font(.caption).foregroundStyle(.secondary)
                }}}.navigationTitle(localizedSettingsString("Fee Priorities"))
    }
    private var chainFeePrioritySettings: [ChainFeePrioritySetting] {
        func std(_ chain: String) -> ChainFeePrioritySetting { ChainFeePrioritySetting(chainName: chain, title: "Default Fee Priority", detail: "Stored as the default fee priority for \(chain) sends.") }
        return [
            ChainFeePrioritySetting(chainName: "Bitcoin", title: "Default Fee Priority", detail: "Used as the default for Bitcoin sends. You can still override before broadcasting."), std("Bitcoin Cash"), std("Bitcoin SV"), ChainFeePrioritySetting(chainName: "Litecoin", title: "Default Fee Priority", detail: "Used as the default for Litecoin sends. You can still override before broadcasting."), ChainFeePrioritySetting(chainName: "Dogecoin", title: "Dogecoin Default Fee", detail: "This is the default in Send. You can still override fee priority per transaction."), std("Ethereum"), std("Ethereum Classic"), std("Arbitrum"), std("Optimism"), std("BNB Chain"), std("Avalanche"), std("Hyperliquid"), std("Tron"), std("Solana"), ChainFeePrioritySetting(chainName: "XRP Ledger", title: "Default Fee Priority", detail: "Stored as the default fee priority for XRP sends."), std("Cardano"), std("Monero"), std("Sui"), std("Aptos"), std("TON"), std("NEAR"), std("Polkadot"), std("Stellar"), std("Internet Computer")
        ]
    }
}
struct SettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var isShowingResetWalletWarning: Bool = false
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
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
        NavigationStack {
            Form {
                Section(localizedSettingsString("Wallet & Transfers")) {
                    NavigationLink(value: Route.addressBook) {
                        Label(localizedSettingsString("Address Book"), systemImage: "book.closed")
                    }
                    NavigationLink(value: Route.trackedTokens) {
                        Label(localizedSettingsString("Tracked Tokens"), systemImage: "bitcoinsign.bank.building")
                    }
                    NavigationLink(value: Route.feePriorities) {
                        Label(localizedSettingsString("Fee Priorities"), systemImage: "dial.medium")
                    }}
                Section(localizedSettingsString("Display")) {
                    NavigationLink(value: Route.iconStyles) {
                        Label(localizedSettingsString("Icon Styles"), systemImage: "photo.on.rectangle")
                    }
                    Toggle(isOn: Binding(get: { store.hideBalances }, set: { store.hideBalances = $0 })) {
                        Label(localizedSettingsString("Hide balances"), systemImage: "eye.slash")
                    }
                    NavigationLink(value: Route.decimalDisplay) {
                        Label(localizedSettingsString("Decimal Display"), systemImage: "number")
                    }}
                Section(localizedSettingsString("Sync & Automation")) {
                    NavigationLink(value: Route.refreshFrequency) {
                        Label(localizedSettingsString("Refresh Frequency"), systemImage: "arrow.triangle.2.circlepath")
                    }}
                Section(localizedSettingsString("Notifications")) {
                    NavigationLink(value: Route.priceAlerts) {
                        Label(localizedSettingsString("Price Alerts"), systemImage: "bell.badge")
                    }
                    Toggle(isOn: Binding(get: { store.useTransactionStatusNotifications }, set: { store.useTransactionStatusNotifications = $0 })) {
                        Label(localizedSettingsString("Transaction Status Updates"), systemImage: "clock.badge.checkmark")
                    }
                    NavigationLink(value: Route.largeMovementAlerts) {
                        Label(localizedSettingsString("Large Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                    }}
                Section(localizedSettingsString("Security & Privacy")) {
                    Toggle(isOn: Binding(get: { store.useFaceID }, set: { store.useFaceID = $0 })) {
                        Label(localizedSettingsString("Use Face ID"), systemImage: "faceid")
                    }
                    Toggle(isOn: Binding(get: { store.useAutoLock }, set: { store.useAutoLock = $0 })) {
                        Label(localizedSettingsString("Auto Lock"), systemImage: "lock")
                    }.disabled(!store.useFaceID)
                }
                Section(localizedSettingsString("Data & Connectivity")) {
                    NavigationLink(value: Route.pricing) {
                        Label(localizedSettingsString("Pricing"), systemImage: "dollarsign.circle")
                    }
                    NavigationLink(value: Route.endpoints) {
                        Label(localizedSettingsString("Endpoints"), systemImage: "network")
                    }}
                Section(localizedSettingsString("Diagnostics & Support")) {
                    NavigationLink(value: Route.diagnostics) {
                        Label(localizedSettingsString("Diagnostics"), systemImage: "waveform.path.ecg.rectangle")
                    }
                    NavigationLink(value: Route.operationalLogs) {
                        Label(localizedSettingsString("Operational Logs"), systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(value: Route.reportProblem) {
                        Label(localizedSettingsString("Report a Problem"), systemImage: "exclamationmark.bubble")
                    }}
                Section(localizedSettingsString("Help")) {
                    NavigationLink(value: Route.buyCryptoHelp) {
                        Label(localizedSettingsString("Where can I buy crypto?"), systemImage: "creditcard")
                    }}
                Section(localizedSettingsString("About")) {
                    NavigationLink(value: Route.about) {
                        Label(localizedSettingsString("About Spectra"), systemImage: "info.circle")
                    }
                    NavigationLink(value: Route.chainWiki) {
                        Label(localizedSettingsString("Chain Wiki"), systemImage: "books.vertical")
                    }}
                Section(localizedSettingsString("Advanced")) {
                    NavigationLink(value: Route.advanced) {
                        Label(localizedSettingsString("Advanced"), systemImage: "slider.horizontal.3")
                    }}
                Section(localizedSettingsString("Reset")) {
                    Button {
                        isShowingResetWalletWarning = true
                    } label: { Label(localizedSettingsString("Reset Wallet"), systemImage: "trash") }.foregroundColor(.red)
                }}.navigationTitle(localizedSettingsString("Settings")).navigationDestination(for: Route.self) { route in
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
                }}.sheet(isPresented: $isShowingResetWalletWarning) {
                ResetWalletWarningView(store: store)
            }}}
}
struct ReportProblemView: View {
    private var copy: SettingsContentCopy { .current }
    private var reportProblemURL: URL { URL(string: copy.reportProblemURL) ?? URL(string: "https://example.com/spectra/report-problem")! }
    var body: some View {
        Form {
            Section {
                Text(copy.reportProblemDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Support Link")) {
                Link(destination: reportProblemURL) {
                    Label(copy.reportProblemActionTitle, systemImage: "arrow.up.right.square")
                }
                Text(reportProblemURL.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }}.navigationTitle(localizedSettingsString("Report a Problem"))
    }
}
struct BuyCryptoHelpView: View {
    private var copy: SettingsContentCopy { .current }
    private struct BuyCryptoProvider: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let url: URL
        let urlLabel: String
    }
    private let providers: [BuyCryptoProvider] = BuyCryptoProviderCatalog.loadEntries().compactMap { provider in
        guard let url = URL(string: provider.url) else { return nil }
        return BuyCryptoProvider(name: provider.name, description: provider.description, url: url, urlLabel: provider.urlLabel)
    }
    var body: some View {
        Form {
            Section {
                Text(copy.buyProvidersIntro).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Options")) {
                ForEach(providers) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Link(destination: provider.url) {
                            Label(provider.name, systemImage: "arrow.up.right.square").font(.headline)
                        }
                        Text(provider.description).font(.subheadline).foregroundStyle(.primary)
                        Text(provider.urlLabel).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(.vertical, 4)
                }}
            Section(localizedSettingsString("Reminder")) { Text(copy.buyWarning).font(.caption).foregroundStyle(.secondary) }}.navigationTitle(localizedSettingsString("Where can I buy crypto?"))
    }
}
struct AdvancedSettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var isRunningMaintenance = false
    @State private var maintenanceNotice: String?
    @State private var isShowingDiagnosticsImporter = false
    @State private var isShowingDiagnosticsExportsBrowser = false
    @State private var lastExportedDiagnosticsURL: URL?
    private let singleChainRefreshNames = [
        "Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar"
    ]
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            Section(localizedSettingsString("Security")) {
                Toggle(
                    localizedSettingsString("Biometric Confirmation For Send Actions"), isOn: Binding(
                        get: { store.requireBiometricForSendActions }, set: { store.requireBiometricForSendActions = $0 }
                    )
                )
                Toggle(
                    localizedSettingsString("Strict RPC Only (Disable Ledger Fallback)"), isOn: Binding(get: { store.useStrictRPCOnly }, set: { store.useStrictRPCOnly = $0 })
                )
                Text(localizedSettingsString("When enabled, balances only come from live RPC responses.")).font(.caption).foregroundStyle(.secondary)
                Button(localizedSettingsString("Lock App Now")) {
                    store.isAppLocked = true
                    maintenanceNotice = localizedSettingsString("App locked.")
                }}
            Section(localizedSettingsString("Quick Maintenance")) {
                Button(isRunningMaintenance ? localizedSettingsString("Refreshing...") : localizedSettingsString("Refresh Now (Balances + History)")) {
                    Task {
                        isRunningMaintenance = true
                        await store.performUserInitiatedRefresh()
                        isRunningMaintenance = false
                        maintenanceNotice = localizedSettingsString("Manual refresh completed.")
                    }}.disabled(isRunningMaintenance)
                Button(isRunningMaintenance ? localizedSettingsString("Running Diagnostics...") : localizedSettingsString("Run All Endpoint Checks")) {
                    Task {
                        isRunningMaintenance = true
                        await store.runBitcoinEndpointReachabilityDiagnostics()
                        await store.runBitcoinCashEndpointReachabilityDiagnostics()
                        await store.runLitecoinEndpointReachabilityDiagnostics()
                        await store.runEthereumEndpointReachabilityDiagnostics()
                        await store.runETCEndpointReachabilityDiagnostics()
                        await store.runArbitrumEndpointReachabilityDiagnostics()
                        await store.runOptimismEndpointReachabilityDiagnostics()
                        await store.runBNBEndpointReachabilityDiagnostics()
                        await store.runAvalancheEndpointReachabilityDiagnostics()
                        await store.runHyperliquidEndpointReachabilityDiagnostics()
                        await store.runTronEndpointReachabilityDiagnostics()
                        await store.runSolanaEndpointReachabilityDiagnostics()
                        await store.runCardanoEndpointReachabilityDiagnostics()
                        await store.runXRPEndpointReachabilityDiagnostics()
                        await store.runMoneroEndpointReachabilityDiagnostics()
                        await store.runSuiEndpointReachabilityDiagnostics()
                        await store.runAptosEndpointReachabilityDiagnostics()
                        await store.runTONEndpointReachabilityDiagnostics()
                        await store.runICPEndpointReachabilityDiagnostics()
                        await store.runNearEndpointReachabilityDiagnostics()
                        await store.runPolkadotEndpointReachabilityDiagnostics()
                        await store.runStellarEndpointReachabilityDiagnostics()
                        isRunningMaintenance = false
                        maintenanceNotice = localizedSettingsString("Endpoint checks completed.")
                    }}.disabled(isRunningMaintenance)
                ForEach(singleChainRefreshNames, id: \.self) { chainName in
                    Button(refreshButtonTitle(for: chainName)) {
                        refreshSingleChain(chainName)
                    }.disabled(isRunningMaintenance)
                }
                if let maintenanceNotice { Text(maintenanceNotice).font(.caption).foregroundStyle(.secondary) }}
            Section(localizedSettingsString("Diagnostics Bundle")) {
                Button(localizedSettingsString("Export Diagnostics Bundle")) {
                    do {
                        let url = try store.exportDiagnosticsBundle()
                        lastExportedDiagnosticsURL = url
                        maintenanceNotice = localizedSettingsFormat("Diagnostics exported to %@", url.lastPathComponent)
                    } catch {
                        maintenanceNotice = localizedSettingsFormat("Export failed: %@", error.localizedDescription)
                    }}
                Button(localizedSettingsString("Past Exports")) {
                    isShowingDiagnosticsExportsBrowser = true
                }
                if let lastExportedDiagnosticsURL {
                    ShareLink(item: lastExportedDiagnosticsURL) {
                        Label(localizedSettingsString("Share Last Export"), systemImage: "square.and.arrow.up")
                    }}
                Button(localizedSettingsString("Import Diagnostics Bundle")) {
                    isShowingDiagnosticsImporter = true
                }}
            Section(localizedSettingsString("Status")) {
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                if let pendingRefresh = store.pendingTransactionRefreshStatusText { Text(pendingRefresh).font(.caption).foregroundStyle(.secondary) }
                Text(localizedSettingsFormat("Wallets: %lld", store.wallets.count)).font(.caption).foregroundStyle(.secondary)
                Text(localizedSettingsFormat("Tracked token checks enabled: %lld", store.tokenPreferences.filter { $0.isEnabled }.count)).font(.caption).foregroundStyle(.secondary)
            }}.navigationTitle(localizedSettingsString("Advanced")).sheet(isPresented: $isShowingDiagnosticsExportsBrowser) {
            DiagnosticsExportsBrowserView(store: store)
        }.fileImporter(
            isPresented: $isShowingDiagnosticsImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileURL = try result.get().first else { return }
                let didAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { fileURL.stopAccessingSecurityScopedResource() }}
                let payload = try store.importDiagnosticsBundle(from: fileURL)
                maintenanceNotice = localizedSettingsFormat("Imported diagnostics bundle (%@).", payload.generatedAt.formatted(date: .abbreviated, time: .shortened))
            } catch {
                maintenanceNotice = localizedSettingsFormat("Import failed: %@", error.localizedDescription)
            }}}
    private func refreshSingleChain(_ chainName: String) {
        Task {
            isRunningMaintenance = true
            await store.performUserInitiatedRefresh(forChain: chainName)
            isRunningMaintenance = false
            maintenanceNotice = localizedSettingsFormat("%@ refresh completed.", chainName)
        }}
    private func refreshButtonTitle(for chainName: String, label: String? = nil) -> String {
        let title = label ?? chainName
        return isRunningMaintenance ? localizedSettingsFormat("Refreshing %@...", title) : localizedSettingsFormat("Refresh %@", title)
    }
}
struct DiagnosticsExportsBrowserView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var exportURLs: [URL] = []
    var body: some View {
        NavigationStack {
            List {
                if exportURLs.isEmpty { Text(localizedSettingsString("No diagnostics exports yet.")).foregroundStyle(.secondary) } else {
                    ForEach(exportURLs, id: \.self) { url in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(url.lastPathComponent).font(.subheadline.weight(.semibold))
                            Text(exportTimestamp(for: url)).font(.caption).foregroundStyle(.secondary)
                            ShareLink(item: url) {
                                Label(localizedSettingsString("Share"), systemImage: "square.and.arrow.up")
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }.onDelete(perform: deleteExports)
                }}.navigationTitle(localizedSettingsString("Past Exports")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localizedSettingsString("Done")) {
                        dismiss()
                    }}}.onAppear(perform: reloadExports)
        }}
    private func reloadExports() { exportURLs = store.diagnosticsBundleExportURLs() }
    private func deleteExports(at offsets: IndexSet) {
        for index in offsets {
            let url = exportURLs[index]
            try? store.deleteDiagnosticsBundleExport(at: url)
        }
        reloadExports()
    }
    private func exportTimestamp(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return date == .distantPast ? localizedSettingsString("Unknown date") : date.formatted(date: .abbreviated, time: .shortened)
    }
}
struct LargeMovementAlertsSettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            Section(localizedSettingsString("Notifications")) {
                Toggle(isOn: Binding(get: { store.useLargeMovementNotifications }, set: { store.useLargeMovementNotifications = $0 })) {
                    Label(localizedSettingsString("Large Portfolio Movement Alerts"), systemImage: "chart.line.uptrend.xyaxis")
                }
                Text(
                    store.useLargeMovementNotifications
                        ? localizedSettingsString("Spectra can notify you when your total portfolio moves beyond your configured thresholds.")
                        : localizedSettingsString("Large movement notifications are currently off.")
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Alert Controls")) {
                Stepper(
                    String(
                        format: localizedSettingsString("Large movement threshold: %@"), (store.largeMovementAlertPercentThreshold / 100).formatted(.percent.precision(.fractionLength(0)))
                    ), value: Binding(
                        get: { store.largeMovementAlertPercentThreshold }, set: { store.largeMovementAlertPercentThreshold = $0 }
                    ), in: 1 ... 90, step: 1
                ).disabled(!store.useLargeMovementNotifications)
                Stepper(
                    localizedSettingsFormat("Large movement minimum: %lld USD", Int(store.largeMovementAlertUSDThreshold)), value: Binding(
                        get: { store.largeMovementAlertUSDThreshold }, set: { store.largeMovementAlertUSDThreshold = $0 }
                    ), in: 1 ... 100_000, step: 5
                ).disabled(!store.useLargeMovementNotifications)
            }
            Section {
                Text(localizedSettingsString("These controls tune when portfolio movement notifications are sent during portfolio balance refreshes.")).font(.caption).foregroundStyle(.secondary)
            }}.navigationTitle(localizedSettingsString("Large Movement Alerts"))
    }
}
private enum TokenRegistryGrouping {
    nonisolated static func key(for entry: TokenPreferenceEntry) -> String {
        let geckoID = entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !geckoID.isEmpty { return "gecko:\(geckoID)" }
        return "symbol:\(entry.symbol.lowercased())|\(entry.name.lowercased())"
    }
}
struct TokenRegistrySettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    private enum TokenRegistryChainFilter: CaseIterable, Identifiable {
        case all
        case ethereum
        case arbitrum
        case optimism
        case bnb
        case avalanche
        case hyperliquid
        case solana
        case sui
        case aptos
        case ton
        case near
        case tron
        var id: Self { self }
        var title: String { chain?.filterDisplayName ?? localizedSettingsString("All") }
        var chain: TokenTrackingChain? {
            switch self {
            case .all: return nil
            case .ethereum: return .ethereum
            case .arbitrum: return .arbitrum
            case .optimism: return .optimism
            case .bnb: return .bnb
            case .avalanche: return .avalanche
            case .hyperliquid: return .hyperliquid
            case .solana: return .solana
            case .sui: return .sui
            case .aptos: return .aptos
            case .ton: return .ton
            case .near: return .near
            case .tron: return .tron
            }}}
    private enum TokenRegistrySourceFilter: CaseIterable, Identifiable {
        case all
        case builtIn
        case custom
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return localizedSettingsString("All")
            case .builtIn: return localizedSettingsString("Built-In")
            case .custom: return localizedSettingsString("Custom")
            }}}
    @State private var searchText: String = ""
    @State private var chainFilter: TokenRegistryChainFilter = .all
    @State private var sourceFilter: TokenRegistrySourceFilter = .all
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.$tokenPreferences.asVoidSignal()
            ])
        )
    }
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(localizedSettingsString("Search name, symbol, chain, or address"), text: $searchText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.padding(.horizontal, 12).padding(.vertical, 10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(spacing: 10) {
                        Picker(localizedSettingsString("Network"), selection: $chainFilter) {
                            ForEach(TokenRegistryChainFilter.allCases) { filter in Text(filter.title).tag(filter) }}.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        Picker(localizedSettingsString("Source"), selection: $sourceFilter) {
                            ForEach(TokenRegistrySourceFilter.allCases) { filter in Text(filter.title).tag(filter) }}.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if chainFilter != .all || sourceFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Spacer(minLength: 0)
                            Button(localizedSettingsString("Clear")) {
                                chainFilter = .all
                                sourceFilter = .all
                                searchText = ""
                            }.font(.caption.weight(.semibold)).foregroundStyle(.mint).buttonStyle(.plain)
                        }}}}
            Section(localizedSettingsString("Tracked Tokens")) {
                if filteredGroups.isEmpty { Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localizedSettingsString("No tracked tokens match the selected filters.") : localizedSettingsString("No matching tokens.")).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(filteredGroups) { group in
                        HStack(spacing: 12) {
                            NavigationLink {
                                TokenRegistryDetailView(store: store, groupKey: group.key)
                            } label: { TokenRegistryGroupRowView(group: group) }.buttonStyle(.plain)
                            Toggle(
                                isOn: Binding(
                                    get: { group.isEnabled }, set: { store.setTokenPreferencesEnabled(ids: group.allEntryIDs, isEnabled: $0) }
                                )
                            ) { EmptyView() }.labelsHidden().scaleEffect(0.9)
                        }}}}}.navigationTitle(localizedSettingsString("Tracked Tokens")).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddCustomTokenView(store: store)
                } label: { Text(localizedSettingsString("New Token")) }}}}
    private func entries(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { $0.chain == chain }
            .sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            return lhs.symbol < rhs.symbol
        }}
    private var filteredGroups: [TokenRegistryGroup] {
        let allEntries = store.resolvedTokenPreferences
        let grouped = Dictionary(grouping: allEntries, by: TokenRegistryGrouping.key(for:))
        let groups = grouped.values.compactMap { entries -> TokenRegistryGroup? in
            let sortedEntries = entries.sorted { lhs, rhs in
                if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
                return lhs.contractAddress < rhs.contractAddress
            }
            guard let representative = sortedEntries.first else { return nil }
            return TokenRegistryGroup(
                key: TokenRegistryGrouping.key(for: representative), name: representative.name, symbol: representative.symbol, entries: sortedEntries
            )
        }
        let filtered = groups.filter { group in
            if let selectedChain = chainFilter.chain, !group.entries.contains(where: { $0.chain == selectedChain }) {
                return false
            }
            switch sourceFilter {
            case .all: break
            case .builtIn: guard group.entries.contains(where: \.isBuiltIn) else { return false }
            case .custom: guard group.entries.contains(where: { !$0.isBuiltIn }) else { return false }}
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            let haystack = (
                [group.symbol, group.name] + group.entries.flatMap { entry in [entry.chain.rawValue, entry.tokenStandard, entry.contractAddress, entry.coinGeckoId] }
            ).joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.entries.contains(where: \.isBuiltIn) != rhs.entries.contains(where: \.isBuiltIn) { return lhs.entries.contains(where: \.isBuiltIn) }
            return lhs.symbol < rhs.symbol
        }}
}
struct TokenRegistryDetailView: View {
    let store: AppState
    let groupKey: String
    private var groupEntries: [TokenPreferenceEntry] {
        store.resolvedTokenPreferences.filter { TokenRegistryGrouping.key(for: $0) == groupKey }
            .sorted { lhs, rhs in
                if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
                return lhs.contractAddress < rhs.contractAddress
            }}
    private var representativeEntry: TokenPreferenceEntry? { groupEntries.first }
    var body: some View {
        Group {
            if let representativeEntry {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            CoinBadge(
                                assetIdentifier: settingsTokenAssetIdentifier(for: representativeEntry), fallbackText: settingsTokenFallbackMark(for: representativeEntry), color: settingsTokenTint(for: representativeEntry.chain), size: 42
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(representativeEntry.name).font(.headline)
                                Text(representativeEntry.symbol).font(.subheadline).foregroundStyle(.secondary)
                            }}.padding(.vertical, 4)
                    }
                    Section(localizedSettingsString("Chain Support")) {
                        ForEach(groupEntries) { entry in
                            TokenRegistryEntryCardView(
                                entry: entry, setEnabled: { store.setTokenPreferenceEnabled(id: entry.id, isEnabled: $0) }, updateDecimals: { store.updateCustomTokenPreferenceDecimals(id: entry.id, decimals: $0) }, removeToken: { store.removeCustomTokenPreference(id: entry.id) }
                            )
                        }}}.navigationTitle(representativeEntry.symbol)
            } else { ContentUnavailableView(localizedSettingsString("Token Not Found"), systemImage: "questionmark.circle") }}}
}
struct AddCustomTokenView: View {
    let store: AppState
    @State private var selectedChain: TokenTrackingChain = .ethereum
    @State private var symbolInput: String = ""
    @State private var nameInput: String = ""
    @State private var contractInput: String = ""
    @State private var coinGeckoIdInput: String = ""
    @State private var decimalsInput: Int = 6
    @State private var formMessage: String?
    var body: some View {
        Form {
            Section {
                Text(localizedSettingsString("Add a custom token contract, mint address, coin type, package address, account ID, or jetton master address for Ethereum, Arbitrum, Optimism, BNB Chain, Avalanche, Hyperliquid, Solana, Sui, Aptos, TON, NEAR, or Tron.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(localizedSettingsString("Token Details")) {
                Picker(localizedSettingsString("Chain"), selection: $selectedChain) {
                    ForEach(TokenTrackingChain.allCases) { chain in Text(chain.rawValue).tag(chain) }}
                TextField(localizedSettingsString("Symbol"), text: $symbolInput).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField(localizedSettingsString("Name"), text: $nameInput)
                TextField(selectedChain.contractAddressPrompt, text: $contractInput).textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper(localizedSettingsFormat("Token Supports: %lld decimals", decimalsInput), value: $decimalsInput, in: 0 ... 30, step: 1)
                TextField(localizedSettingsString("CoinGecko ID (Optional)"), text: $coinGeckoIdInput).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                if let formMessage { Text(formMessage).font(.caption).foregroundStyle(.secondary) }
                Button(localizedSettingsString("Add Token")) {
                    let message = store.addCustomTokenPreference(
                        chain: selectedChain, symbol: symbolInput, name: nameInput, contractAddress: contractInput, marketDataId: "0", coinGeckoId: coinGeckoIdInput, decimals: decimalsInput
                    )
                    if let message { formMessage = message } else {
                        formMessage = localizedSettingsString("Token added.")
                        symbolInput = ""
                        nameInput = ""
                        contractInput = ""
                        coinGeckoIdInput = ""
                    }}}}.navigationTitle(localizedSettingsString("New Token"))
    }
}
struct DecimalDisplaySettingsView: View {
    let store: AppState
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var searchText: String = ""
    private let decimalExamples: [(symbol: String, chainName: String)] = [
        ("BTC", "Bitcoin"), ("BCH", "Bitcoin Cash"), ("LTC", "Litecoin"), ("DOGE", "Dogecoin"), ("ETH", "Ethereum"), ("ETC", "Ethereum Classic"), ("BNB", "BNB Chain"), ("AVAX", "Avalanche"), ("HYPE", "Hyperliquid"), ("SOL", "Solana"), ("ADA", "Cardano"), ("XRP", "XRP Ledger"), ("TRX", "Tron"), ("XMR", "Monero"), ("SUI", "Sui"), ("APT", "Aptos"), ("TON", "TON"), ("ICP", "Internet Computer"), ("NEAR", "NEAR"), ("DOT", "Polkadot"), ("XLM", "Stellar"), ]
    init(store: AppState) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([ store.objectWillChange.asVoidSignal() ])
        )
    }
    var body: some View {
        Form {
            Section {
                Text(localizedSettingsString("Search native assets and tracked tokens, then adjust how many decimals Spectra shows in portfolio and wallet views.")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(localizedSettingsString("Search symbol, name, chain, or address"), text: $searchText).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(.horizontal, 12).padding(.vertical, 10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Section(localizedSettingsString("Native Asset Display")) {
                Text(localizedSettingsString("Adjust how many decimals are shown for each chain's native asset. Very small values switch to a threshold marker instead of rounding to zero.")).font(.caption).foregroundStyle(.secondary)
                Button(localizedSettingsString("Reset Native Asset Display")) {
                    store.resetNativeAssetDisplayDecimals()
                }
                if filteredDecimalExamples.isEmpty { Text(localizedSettingsString("No matching native assets.")).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(filteredDecimalExamples, id: \.symbol) { example in
                        let currentDisplayDecimals = store.assetDisplayDecimalPlaces(for: example.chainName)
                        let supportedDecimals = store.supportedAssetDecimals(symbol: example.symbol, chainName: example.chainName)
                        decimalStepperCard(
                            assetIdentifier: Coin.iconIdentifier(symbol: example.symbol, chainName: example.chainName), fallbackText: Coin.displayMark(for: example.symbol), tint: Coin.displayColor(for: example.symbol), title: example.chainName, subtitle: example.symbol, currentDisplayDecimals: currentDisplayDecimals, supportedDecimals: supportedDecimals, supportedLabel: localizedSettingsString("Asset supports"), onDecrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals - 1, for: example.chainName)
                            }, onIncrease: {
                                store.setAssetDisplayDecimalPlaces(currentDisplayDecimals + 1, for: example.chainName)
                            }
                        )
                    }}}
            Section(localizedSettingsString("Tracked Token Decimals")) {
                Text(localizedSettingsString("ERC-20 and TRC-20 tokens expose decimals on the contract, and Solana tokens store decimals on the mint account. Manage tracked token decimal support separately from native asset display precision.")).font(.caption).foregroundStyle(.secondary)
                Button(localizedSettingsString("Reset Tracked Token Display")) {
                    store.resetTrackedTokenDisplayDecimals()
                }
                if filteredTokenDecimalEntries.isEmpty { Text(store.enabledTrackedTokenPreferences.isEmpty ? localizedSettingsString("No tokens are currently enabled for tracking.") : localizedSettingsString("No matching tracked tokens.")).font(.caption).foregroundStyle(.secondary) } else {
                    ForEach(filteredTokenDecimalEntries, id: \.id) { entry in
                        let currentDisplayDecimals = store.displayAssetDecimals(symbol: entry.symbol, chainName: entry.chain.rawValue)
                        let supportedDecimals = Int(entry.decimals)
                        decimalStepperCard(
                            assetIdentifier: decimalTokenAssetIdentifier(for: entry), fallbackText: String(entry.symbol.prefix(2)).uppercased(), tint: decimalTokenTint(for: entry.chain), title: entry.name, subtitle: "\(entry.chain.rawValue) · \(entry.symbol)", currentDisplayDecimals: currentDisplayDecimals, supportedDecimals: supportedDecimals, supportedLabel: localizedSettingsString("Token supports"), detailText: entry.contractAddress, onDecrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals - 1)
                            }, onIncrease: {
                                store.updateTokenPreferenceDisplayDecimals(id: entry.id, decimals: currentDisplayDecimals + 1)
                            }
                        )
                    }}}}.navigationTitle(localizedSettingsString("Decimal Display"))
    }
    private var filteredDecimalExamples: [(symbol: String, chainName: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return decimalExamples }
        return decimalExamples.filter { example in [example.symbol, example.chainName].joined(separator: " ").lowercased().contains(query) }}
    private var filteredTokenDecimalEntries: [TokenPreferenceEntry] {
        let entries = store.enabledTrackedTokenPreferences.sorted { lhs, rhs in
            if lhs.chain.rawValue != rhs.chain.rawValue { return lhs.chain.rawValue < rhs.chain.rawValue }
            return lhs.symbol < rhs.symbol
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            [
                entry.symbol, entry.name, entry.chain.rawValue, entry.contractAddress, entry.coinGeckoId
            ].joined(separator: " ").lowercased().contains(query)
        }}
    @ViewBuilder
    private func decimalStepperCard(
        assetIdentifier: String?, fallbackText: String, tint: Color, title: String, subtitle: String, currentDisplayDecimals: Int, supportedDecimals: Int, supportedLabel: String, detailText: String? = nil, onDecrease: @escaping () -> Void, onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CoinBadge(assetIdentifier: assetIdentifier, fallbackText: fallbackText, color: tint, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if let detailText, !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(detailText).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) }}
                Spacer()
                HStack(spacing: 10) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals <= 0)
                    Text("\(currentDisplayDecimals)").font(.subheadline.monospacedDigit()).frame(minWidth: 30)
                    Button(action: onIncrease) {
                        Image(systemName: "plus.circle")
                    }.buttonStyle(.plain).disabled(currentDisplayDecimals >= supportedDecimals)
                }.font(.title3)
            }
            HStack {
                Text(supportedLabel)
                Spacer()
                Text(localizedSettingsFormat("%lld decimals", supportedDecimals)).foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(.vertical, 4)
    }
    private func decimalTokenAssetIdentifier(for entry: TokenPreferenceEntry) -> String? {
        let slug = entry.chain.slug
        let symbol = entry.symbol.lowercased()
        if !entry.coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "\(slug):\(entry.coinGeckoId.lowercased()):\(symbol)" }
        return "\(slug):\(symbol)"
    }
    private func decimalTokenTint(for chain: TokenTrackingChain) -> Color {
        switch chain {
        case .ethereum, .ton: return .blue
        case .arbitrum, .aptos: return .cyan
        case .optimism, .avalanche, .tron: return .red
        case .bnb: return .yellow
        case .hyperliquid, .sui: return .mint
        case .solana: return .purple
        case .near: return .indigo
        }}
}
struct LogsView: View {
    let store: AppState
    @ObservedObject private var diagnosticsState: WalletDiagnosticsState
    @State private var searchText: String = ""
    @State private var selectedLevelFilter: LogLevelFilter = .all
    private let allCategoryFilter = "__all__"
    @State private var selectedCategoryFilter: String = "__all__"
    @State private var copiedNotice: String?
    @State private var cachedAvailableCategories: [String] = ["__all__"]
    @State private var cachedFilteredLogs: [AppState.OperationalLogEvent] = []
    init(store: AppState) {
        self.store = store
        _diagnosticsState = ObservedObject(wrappedValue: store.diagnostics)
    }
    private enum LogLevelFilter: CaseIterable, Identifiable {
        case all
        case debug
        case info
        case warning
        case error
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return localizedSettingsString("All")
            case .debug: return localizedSettingsString("Debug")
            case .info: return localizedSettingsString("Info")
            case .warning: return localizedSettingsString("Warning")
            case .error: return localizedSettingsString("Error")
            }}}
    private var availableCategories: [String] { cachedAvailableCategories }
    private var filteredLogs: [AppState.OperationalLogEvent] { cachedFilteredLogs }
    private func rebuildLogPresentation() {
        let categories = Set(diagnosticsState.operationalLogs.map { $0.category })
        cachedAvailableCategories = [allCategoryFilter] + categories.sorted()
        if selectedCategoryFilter != allCategoryFilter, !cachedAvailableCategories.contains(selectedCategoryFilter) { selectedCategoryFilter = allCategoryFilter }
        cachedFilteredLogs = diagnosticsState.operationalLogs.filter { event in
            let levelMatches: Bool
            switch selectedLevelFilter {
            case .all: levelMatches = true
            case .debug: levelMatches = event.level == .debug
            case .info: levelMatches = event.level == .info
            case .warning: levelMatches = event.level == .warning
            case .error: levelMatches = event.level == .error
            }
            let categoryMatches = selectedCategoryFilter == allCategoryFilter || event.category == selectedCategoryFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches: Bool
            if query.isEmpty { searchMatches = true } else {
                let haystack = [
                    event.message, event.category, event.chainName ?? "", event.source ?? "", event.metadata ?? "", event.walletID ?? "", event.transactionHash ?? ""
                ].joined(separator: " ").lowercased()
                searchMatches = haystack.contains(query)
            }
            return levelMatches && categoryMatches && searchMatches
        }}
    private var summaryText: String {
        let debugCount = filteredLogs.filter { $0.level == .debug }.count
        let infoCount = filteredLogs.filter { $0.level == .info }.count
        let warningCount = filteredLogs.filter { $0.level == .warning }.count
        let errorCount = filteredLogs.filter { $0.level == .error }.count
        return localizedSettingsFormat("Showing %lld logs • D:%lld I:%lld W:%lld E:%lld", filteredLogs.count, debugCount, infoCount, warningCount, errorCount)
    }
    var body: some View {
        List {
            Section(localizedSettingsString("Status")) {
                Text(store.pendingTransactionRefreshStatusText ?? localizedSettingsString("No refresh status yet")).font(.caption).foregroundStyle(.secondary)
                Text(store.networkSyncStatusText).font(.caption).foregroundStyle(.secondary)
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                if let copiedNotice { Text(copiedNotice).font(.caption).foregroundStyle(.secondary) }}
            Section(localizedSettingsString("Filters")) {
                Picker(localizedSettingsString("Level"), selection: $selectedLevelFilter) {
                    ForEach(LogLevelFilter.allCases) { level in Text(level.title).tag(level) }}
                Picker(localizedSettingsString("Category"), selection: $selectedCategoryFilter) {
                    ForEach(availableCategories, id: \.self) { category in
                        let label: String = category == allCategoryFilter ? localizedSettingsString("All") : category
                        Text(label).tag(category)
                    }
                }}
            if filteredLogs.isEmpty {
                Section(localizedSettingsString("Events")) { Text(localizedSettingsString("No operational events yet.")).font(.caption).foregroundStyle(.secondary) }
            } else {
                Section(localizedSettingsString("Events")) {
                    ForEach(filteredLogs) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: event.level)).foregroundStyle(color(for: event.level))
                                Text(event.timestamp.formatted(date: .abbreviated, time: .standard)).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(event.category).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(event.message).font(.subheadline)
                            if let source = event.source, !source.isEmpty { Text(localizedSettingsFormat("source: %@", source)).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            if let chainName = event.chainName, !chainName.isEmpty { Text(localizedSettingsFormat("chain: %@", chainName)).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            if let walletID = event.walletID { Text(localizedSettingsFormat("wallet: %@", walletID)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let transactionHash = event.transactionHash, !transactionHash.isEmpty { Text(transactionHash).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let metadata = event.metadata, !metadata.isEmpty { Text(metadata).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }}.padding(.vertical, 2)
                    }}}}.navigationTitle(localizedSettingsString("Logs")).searchable(text: $searchText, prompt: localizedSettingsString("Search message, chain, tx hash, wallet")).onAppear {
            rebuildLogPresentation()
        }.onChange(of: diagnosticsState.operationalLogsRevision) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedLevelFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: selectedCategoryFilter) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: searchText) { _, _ in
            rebuildLogPresentation()
        }.onChange(of: copiedNotice) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copiedNotice = nil
            }}.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedSettingsString("Copy")) {
                    UIPasteboard.general.string = store.exportOperationalLogsText(events: filteredLogs)
                    copiedNotice = localizedSettingsFormat("Copied %lld log entries", filteredLogs.count)
                }.disabled(filteredLogs.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedSettingsString("Clear"), role: .destructive) {
                    store.clearOperationalLogs()
                }.disabled(diagnosticsState.operationalLogs.isEmpty)
            }}}
    private func iconName(for level: AppState.OperationalLogEvent.Level) -> String {
        switch level {
        case .debug: return "ladybug.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }}
    private func color(for level: AppState.OperationalLogEvent.Level) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }}
}
struct ResetWalletWarningView: View {
    let store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScopes = Set(AppState.ResetScope.allCases)
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(localizedSettingsString("Choose which categories to remove from this device. Selected items are deleted locally and some options also clear secure keychain data.")).font(.body)
                    Text(localizedSettingsString("You must have your seed phrase backed up. Without it, you cannot recover your funds after reset.")).font(.body.weight(.semibold)).foregroundStyle(.red)
                } header: {
                    Text(localizedSettingsString("Before You Continue"))
                }
                Section(localizedSettingsString("Choose What To Reset")) {
                    ForEach(AppState.ResetScope.allCases) { scope in
                        Toggle(isOn: binding(for: scope)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                Text(scope.detail).font(.caption).foregroundStyle(.secondary)
                            }}}}
                Section(localizedSettingsString("Selected Reset Summary")) {
                    if selectedScopes.contains(.walletsAndSecrets) { Label(localizedSettingsString("Imported wallets, watched addresses, and secure seed material"), systemImage: "wallet.pass") }
                    if selectedScopes.contains(.historyAndCache) { Label(localizedSettingsString("Transaction history, chain snapshots, diagnostics, and network caches"), systemImage: "clock.arrow.circlepath") }
                    if selectedScopes.contains(.alertsAndContacts) { Label(localizedSettingsString("Price alerts, notification rules, and address book recipients"), systemImage: "bell.slash") }
                    if selectedScopes.contains(.settingsAndEndpoints) { Label(localizedSettingsString("Tracked tokens, API keys, endpoint settings, preferences, and custom icons"), systemImage: "slider.horizontal.3") }
                    if selectedScopes.contains(.dashboardCustomization) { Label(localizedSettingsString("Pinned assets and dashboard customization choices"), systemImage: "square.grid.2x2") }
                    if selectedScopes.contains(.providerState) { Label(localizedSettingsString("Provider selections, reliability memory, and low-level network state"), systemImage: "network") }
                    if selectedScopes.isEmpty { Text(localizedSettingsString("Select at least one category to enable reset.")).foregroundStyle(.secondary) }}
                Section {
                    Button(localizedSettingsString("Reset Selected Data"), role: .destructive) {
                        Task {
                            await store.resetSelectedData(scopes: selectedScopes)
                            dismiss()
                        }}.disabled(selectedScopes.isEmpty)
                }}.navigationTitle(localizedSettingsString("Reset Wallet")).toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizedSettingsString("Cancel")) {
                        dismiss()
                    }}}}}
    private func binding(for scope: AppState.ResetScope) -> Binding<Bool> {
        Binding(
            get: { selectedScopes.contains(scope) }, set: { isSelected in
                if isSelected { selectedScopes.insert(scope) } else { selectedScopes.remove(scope) }}
        )
    }
}
struct TokenIconSettingsView: View {
    private let availableSettings: [TokenIconSetting] =
        ChainRegistryEntry.all.map {
            TokenIconSetting(
                title: $0.name, symbol: $0.symbol, assetIdentifier: $0.assetIdentifier, mark: $0.mark, color: $0.color
            )
        } + TokenVisualRegistryEntry.all.map {
            TokenIconSetting(
                title: $0.title, symbol: $0.symbol, assetIdentifier: $0.assetIdentifier, mark: $0.mark, color: $0.color
            )
        }
    @AppStorage(TokenIconPreferenceStore.defaultsKey) private var tokenIconPreferencesStorage = ""
    @State private var searchText = ""
    private var filteredSettings: [TokenIconSetting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableSettings }
        return availableSettings.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.symbol.localizedCaseInsensitiveContains(query)
        }}
    var body: some View {
        Form {
            Section {
                ForEach(filteredSettings) { setting in TokenIconCustomizationRow(setting: setting) }} header: {
                Text(localizedSettingsString("Token Icons"))
            } footer: {
                Text(localizedSettingsString("Choose custom artwork, your own photo, or the classic generated badge style. Uploaded images must be 3 MB or smaller."))
            }}.navigationTitle(localizedSettingsString("Icon Styles")).searchable(text: $searchText, prompt: localizedSettingsString("Search icons")).toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizedSettingsString("Reset")) {
                    tokenIconPreferencesStorage = ""
                }.disabled(tokenIconPreferencesStorage.isEmpty)
            }}}
}
/// Defers evaluation of a tab's content until the tab is first selected.
/// After that initial render the view stays alive (SwiftUI's TabView keeps
/// it in memory), but the expensive first-build is skipped until the user
/// actually taps the tab.
private struct LazyTab<Content: View>: View {
    @State private var hasAppeared = false
    let build: () -> Content
    var body: some View {
        Group {
            if hasAppeared {
                build()
            } else {
                Color.clear
            }
        }.onAppear { hasAppeared = true }
    }
}

struct MainTabView: View {
    let store: AppState
    init(store: AppState) {
        self.store = store
    }
    private var selectedMainTabBinding: Binding<MainAppTab> {
        Binding(get: { store.selectedMainTab }, set: { store.selectedMainTab = $0 })
    }
    var body: some View {
        TabView(selection: selectedMainTabBinding) {
            LazyTab { DashboardView(store: store) }.tabItem {
                    Label(localizedSettingsString("Home"), systemImage: "chart.pie.fill")
                }.tag(MainAppTab.home)
            LazyTab { HistoryView(store: store) }.tabItem {
                    Label(localizedSettingsString("History"), systemImage: "clock.arrow.circlepath")
                }.tag(MainAppTab.history)
            LazyTab { StakingView() }.tabItem {
                    Label(localizedSettingsString("Staking"), systemImage: "link.circle.fill")
                }.tag(MainAppTab.staking)
            LazyTab { DonationsView() }.tabItem {
                    Label(localizedSettingsString("Donate"), systemImage: "heart.fill")
                }.tag(MainAppTab.donate)
            LazyTab { SettingsView(store: store) }.tabItem {
                    Label(localizedSettingsString("Settings"), systemImage: "gearshape.fill")
                }.tag(MainAppTab.settings)
        }}
}
