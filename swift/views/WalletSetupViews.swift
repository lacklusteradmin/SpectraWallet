import Foundation
import SwiftUI
private func localizedSetupString(_ key: String) -> String {
    AppLocalization.string(key)
}
private func localizedSetupFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
private struct SetupChainSelectionDescriptor: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let mark: String
    let chainName: String
    let assetIdentifier: String?
    let color: Color
    var title: String { localizedWalletFlowString(titleKey) }
    init(id: String, title: String, symbol: String, mark: String, chainName: String, color: Color) {
        self.id = id
        self.titleKey = title
        self.symbol = symbol
        self.mark = mark
        self.chainName = chainName
        self.assetIdentifier = Coin.iconIdentifier(symbol: symbol, chainName: chainName)
        self.color = color
    }
}
struct SetupView: View {
    private static let chainSelectionDescriptors: [SetupChainSelectionDescriptor] = [
        SetupChainSelectionDescriptor(id: "bitcoin", title: "Bitcoin", symbol: "BTC", mark: "B", chainName: "Bitcoin", color: .orange), SetupChainSelectionDescriptor(id: "bitcoin-cash", title: "Bitcoin Cash", symbol: "BCH", mark: "BC", chainName: "Bitcoin Cash", color: .orange), SetupChainSelectionDescriptor(id: "bitcoin-sv", title: "Bitcoin SV", symbol: "BSV", mark: "BS", chainName: "Bitcoin SV", color: .orange), SetupChainSelectionDescriptor(id: "litecoin", title: "Litecoin", symbol: "LTC", mark: "L", chainName: "Litecoin", color: .gray), SetupChainSelectionDescriptor(id: "ethereum", title: "Ethereum", symbol: "ETH", mark: "E", chainName: "Ethereum", color: .blue), SetupChainSelectionDescriptor(id: "ethereum-classic", title: "Ethereum Classic", symbol: "ETC", mark: "EC", chainName: "Ethereum Classic", color: .green), SetupChainSelectionDescriptor(id: "solana", title: "Solana", symbol: "SOL", mark: "S", chainName: "Solana", color: .purple), SetupChainSelectionDescriptor(id: "arbitrum", title: "Arbitrum", symbol: "ARB", mark: "AR", chainName: "Arbitrum", color: .cyan), SetupChainSelectionDescriptor(id: "optimism", title: "Optimism", symbol: "OP", mark: "OP", chainName: "Optimism", color: .red), SetupChainSelectionDescriptor(id: "bnb-chain", title: "BNB Chain", symbol: "BNB", mark: "BN", chainName: "BNB Chain", color: .yellow), SetupChainSelectionDescriptor(id: "avalanche", title: "Avalanche", symbol: "AVAX", mark: "AV", chainName: "Avalanche", color: .red), SetupChainSelectionDescriptor(id: "hyperliquid", title: "Hyperliquid", symbol: "HYPE", mark: "HY", chainName: "Hyperliquid", color: .mint), SetupChainSelectionDescriptor(id: "dogecoin", title: "Dogecoin", symbol: "DOGE", mark: "D", chainName: "Dogecoin", color: .brown), SetupChainSelectionDescriptor(id: "cardano", title: "Cardano", symbol: "ADA", mark: "A", chainName: "Cardano", color: .indigo), SetupChainSelectionDescriptor(id: "tron", title: "Tron", symbol: "TRX", mark: "T", chainName: "Tron", color: .teal), SetupChainSelectionDescriptor(id: "xrp-ledger", title: "XRP Ledger", symbol: "XRP", mark: "X", chainName: "XRP Ledger", color: .cyan), SetupChainSelectionDescriptor(id: "monero", title: "Monero", symbol: "XMR", mark: "M", chainName: "Monero", color: .indigo), SetupChainSelectionDescriptor(id: "sui", title: "Sui", symbol: "SUI", mark: "SU", chainName: "Sui", color: .mint), SetupChainSelectionDescriptor(id: "aptos", title: "Aptos", symbol: "APT", mark: "AP", chainName: "Aptos", color: .cyan), SetupChainSelectionDescriptor(id: "ton", title: "TON", symbol: "TON", mark: "TN", chainName: "TON", color: .blue), SetupChainSelectionDescriptor(id: "internet-computer", title: "Internet Computer", symbol: "ICP", mark: "IC", chainName: "Internet Computer", color: .indigo), SetupChainSelectionDescriptor(id: "near", title: "NEAR", symbol: "NEAR", mark: "N", chainName: "NEAR", color: .indigo), SetupChainSelectionDescriptor(id: "polkadot", title: "Polkadot", symbol: "DOT", mark: "P", chainName: "Polkadot", color: .pink), SetupChainSelectionDescriptor(id: "stellar", title: "Stellar", symbol: "XLM", mark: "XL", chainName: "Stellar", color: .teal), ]
    private static let popularChainSelectionIDs: Set<String> = [
        "bitcoin", "ethereum", "solana", "monero", "litecoin", "tron"
    ]
    private static let nonPopularChainSelectionDescriptors = chainSelectionDescriptors.filter { !popularChainSelectionIDs.contains($0.id) }
    private static let sortedChainSelectionDescriptors = chainSelectionDescriptors.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    private enum SetupPage {
        case setupModeChoice
        case details
        case watchAddresses
        case seedPhrase
        case password
        case advanced
        case backupVerification
    }
    private enum SetupModeChoice {
        case simple
        case advanced
    }
    @ObservedObject private var store: AppState
    @ObservedObject var draft: WalletImportDraft
    private let copy = ImportFlowContent.current
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var setupPage: SetupPage
    @State private var setupModeChoice: SetupModeChoice?
    @State private var customSeedPhraseWordCountInput: String
    @State private var chainSearchText: String = ""
    @State private var isShowingAllChainsSheet: Bool = false
    @FocusState private var focusedSeedPhraseIndex: Int?
    private let chainSelectionColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)
    ]
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)
    ]
    private let setupCardCornerRadius: CGFloat = 24
    init(store: AppState, draft: WalletImportDraft) {
        _store = ObservedObject(wrappedValue: store)
        self.draft = draft
        _setupPage = State(initialValue: draft.isEditingWallet ? .details : .setupModeChoice)
        _customSeedPhraseWordCountInput = State(initialValue: String(draft.selectedSeedPhraseWordCount))
    }
    private var isEditingWallet: Bool { draft.isEditingWallet }
    private var isCreateMode: Bool { draft.isCreateMode }
    private var isWatchAddressesImportMode: Bool { !isEditingWallet && !isCreateMode && draft.isWatchOnlyMode }
    private var hasBitcoinSelection: Bool { draft.selectedChainNames.contains("Bitcoin") }
    private var hasEthereumSelection: Bool { draft.selectedChainNames.contains("Ethereum") }
    private var hasDogecoinSelection: Bool { draft.selectedChainNames.contains("Dogecoin") }
    private var usesSeedPhraseFlow: Bool { !isEditingWallet && !draft.isWatchOnlyMode }
    private var isPrivateKeyImportMode: Bool { draft.isPrivateKeyImportMode }
    private var usesWatchAddressesFlow: Bool { !isEditingWallet && draft.isWatchOnlyMode }
    private var isShowingDetailsPage: Bool { setupPage == .details }
    private var isShowingSetupModeChoicePage: Bool { setupPage == .setupModeChoice }
    private var isShowingSeedPhrasePage: Bool { setupPage == .seedPhrase }
    private var isShowingWatchAddressesPage: Bool { setupPage == .watchAddresses }
    private var isShowingPasswordPage: Bool { setupPage == .password }
    private var isShowingBackupVerificationPage: Bool { setupPage == .backupVerification }
    private var isShowingAdvancedPage: Bool { setupPage == .advanced }
    private var isSimpleSetupSelected: Bool { setupModeChoice == .simple }
    private var setupTitle: String {
        if isShowingSetupModeChoicePage { return localizedSetupString("Choose Setup Type") }
        if isShowingBackupVerificationPage { return copy.backupVerificationTitle }
        if isShowingAdvancedPage { return copy.advancedTitle }
        if isShowingPasswordPage { return localizedSetupString("import_flow.wallet_password_title") }
        if isShowingWatchAddressesPage { return copy.watchAddressesTitle }
        if isShowingSeedPhrasePage {
            if isCreateMode { return copy.recordSeedPhraseTitle }
            return isPrivateKeyImportMode ? copy.enterPrivateKeyTitle : copy.enterSeedPhraseTitle
        }
        if isEditingWallet { return copy.editWalletTitle }
        if isCreateMode { return copy.createWalletTitle }
        return isWatchAddressesImportMode ? copy.watchAddressesTitle : copy.importWalletTitle
    }
    private var setupSubtitle: String {
        if isShowingSetupModeChoicePage { return localizedSetupString("Start with a guided simple setup or continue with full advanced controls.") }
        if isShowingBackupVerificationPage { return copy.backupVerificationSubtitle }
        if isShowingAdvancedPage { return copy.advancedSubtitle }
        if isShowingPasswordPage { return localizedSetupString("import_flow.wallet_password_subtitle") }
        if isShowingWatchAddressesPage { return copy.watchAddressesSubtitle }
        if isShowingSeedPhrasePage {
            if isPrivateKeyImportMode { return copy.privateKeySubtitle }
            return isCreateMode ? copy.saveRecoveryPhraseSubtitle : copy.enterRecoveryPhraseSubtitle
        }
        if isEditingWallet { return copy.editWalletSubtitle }
        if isCreateMode { return copy.chooseNameAndChainsSubtitle }
        if isWatchAddressesImportMode { return copy.chooseNameAndChainSubtitle }
        return copy.chooseNameAndChainsSubtitle
    }
    private var seedPhraseStatusText: String {
        if draft.seedPhraseWords.isEmpty { return "" }
        if !draft.invalidSeedWords.isEmpty { return localizedSetupFormat("import_flow.seed_phrase_invalid_words_format", draft.invalidSeedWords.joined(separator: ", ")) }
        if draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount { return localizedSetupFormat("import_flow.seed_phrase_progress_format", draft.seedPhraseWords.count, draft.selectedSeedPhraseWordCount) }
        if let validationError = draft.seedPhraseValidationError { return validationError }
        return localizedSetupString("import_flow.seed_phrase_valid_status")
    }
    private var seedPhraseStatusColor: Color {
        if draft.seedPhraseWords.isEmpty || draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount { return .white.opacity(0.7) }
        if !draft.invalidSeedWords.isEmpty || draft.seedPhraseValidationError != nil { return .red.opacity(0.9) }
        return .green.opacity(0.9)
    }
    private func seedPhraseBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { draft.seedPhraseEntry(at: index) }, set: { newValue in
                let shouldAdvance = newValue.last?.isWhitespace == true
                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.updateSeedPhraseEntry(at: index, with: trimmedValue)
                guard shouldAdvance, !trimmedValue.isEmpty else { return }
                focusedSeedPhraseIndex = (index + 1) < draft.selectedSeedPhraseWordCount ? (index + 1) : nil
            }
        )
    }
    private func backupVerificationBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.backupVerificationEntries.indices.contains(index) else { return "" }
                return draft.backupVerificationEntries[index]
            }, set: { draft.updateBackupVerificationEntry(at: index, with: $0) }
        )
    }
    private var canContinueFromSecretStep: Bool {
        let hasChains = !draft.selectedChainNames.isEmpty
        if draft.isPrivateKeyImportMode {
            return hasChains
                && PrivateKeyHex.isLikely(draft.privateKeyInput)
                && draft.unsupportedPrivateKeyChainNames.isEmpty
                && draft.selectedChainNames.count == 1
                && !store.isImportingWallet
        }
        let hasValidSeedPhrase = draft.seedPhraseWords.count == draft.selectedSeedPhraseWordCount
            && draft.seedPhraseValidationError == nil
            && draft.invalidSeedWords.isEmpty
            && draft.hasValidSeedPhraseChecksum
        return hasChains && hasValidSeedPhrase && !store.isImportingWallet
    }
    private var canContinueToBackupVerification: Bool {
        canContinueFromSecretStep
            && draft.walletPasswordValidationError == nil
            && !store.isImportingWallet
    }
    private var canSubmitFromPasswordStep: Bool {
        draft.walletPasswordValidationError == nil
            && store.canImportWallet
            && !store.isImportingWallet
    }
    private var canAdvanceFromDetailsPage: Bool {
        if usesSeedPhraseFlow { return !draft.selectedChainNames.isEmpty && !store.isImportingWallet }
        if usesWatchAddressesFlow { return !draft.selectedChainNames.isEmpty && !store.isImportingWallet }
        return store.canImportWallet && !store.isImportingWallet
    }
    private var primaryActionTitle: String {
        if isShowingSetupModeChoicePage { return localizedSetupString("import_flow.next") }
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) { return localizedSetupString("import_flow.next") }
        if isShowingAdvancedPage { return "" }
        if isShowingSeedPhrasePage { return localizedSetupString("import_flow.next") }
        if isShowingPasswordPage && isCreateMode { return localizedSetupString("import_flow.continue_to_backup_verification") }
        if isEditingWallet { return localizedSetupString("import_flow.save_wallet") }
        if isCreateMode { return localizedSetupString("import_flow.create_wallet") }
        return isWatchAddressesImportMode ? localizedSetupString("import_flow.watch_addresses") : localizedSetupString("import_flow.import_wallet")
    }
    private var isPrimaryActionEnabled: Bool {
        if isShowingSetupModeChoicePage { return setupModeChoice != nil && !store.isImportingWallet }
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) { return canAdvanceFromDetailsPage }
        if isShowingAdvancedPage { return false }
        if isShowingSeedPhrasePage { return canContinueFromSecretStep }
        if isShowingPasswordPage && isCreateMode { return canContinueToBackupVerification }
        if isShowingPasswordPage { return canSubmitFromPasswordStep }
        return store.canImportWallet && !store.isImportingWallet
    }
    private var popularChainSelectionDescriptors: [SetupChainSelectionDescriptor] {
        Self.chainSelectionDescriptors.filter { Self.popularChainSelectionIDs.contains($0.id) }}
    private var selectedChainNameSet: Set<String> { Set(draft.selectedChainNames) }
    private var selectedChainCount: Int { draft.selectedChainNames.count }
    private var chainSelectionSummary: String {
        switch selectedChainCount {
        case 0: return localizedSetupString("import_flow.no_chains_selected")
        case 1: return localizedSetupString("import_flow.one_chain_selected")
        default: return localizedSetupFormat("import_flow.multiple_chains_selected_format", selectedChainCount)
        }}
    private var chainSelectionSubtitle: String {
        if isCreateMode { return localizedSetupString("import_flow.create_chain_selection_subtitle") }
        return localizedSetupString("import_flow.import_chain_selection_subtitle")
    }
    @ViewBuilder
    private var setupModeChoiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupModeButton(
                title: localizedSetupString("Simple Setup"), subtitle: localizedSetupString("Recommended defaults and fewer required choices."), iconName: "sparkles", tint: .green, choice: .simple
            )
            setupModeButton(
                title: localizedSetupString("Advanced Setup"), subtitle: localizedSetupString("Configure derivation paths and network-level options."), iconName: "slider.horizontal.3", tint: .orange, choice: .advanced
            )
        }}
    @ViewBuilder
    private func setupModeButton(title: String, subtitle: String, iconName: String, tint: Color, choice: SetupModeChoice) -> some View {
        let isSelected = setupModeChoice == choice
        Button {
            setupModeChoice = choice
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName).font(.subheadline.weight(.semibold)).foregroundStyle(tint).frame(width: 28, height: 28).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(subtitle).font(.caption).foregroundStyle(Color.primary.opacity(0.68))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? tint : Color.primary.opacity(0.3))
            }.padding(.horizontal, 12).padding(.vertical, 12).background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? tint.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.78 : 0.05))
            ).overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isSelected ? tint.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private func seedPhraseField(at index: Int) -> some View {
        let entry = draft.seedPhraseEntry(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalidWord = !entry.isEmpty && !BIP39EnglishWordList.words.contains(entry)
        numberedSeedPhraseRow(index: index, isInvalidWord: isInvalidWord)
    }
    @ViewBuilder
    private func watchedAddressEditor(text: Binding<String>) -> some View { TextEditor(text: text).textInputAutocapitalization(.never).autocorrectionDisabled().scrollContentBackground(.hidden).frame(minHeight: 88).padding(10).spectraInputFieldStyle().foregroundStyle(Color.primary) }
    @ViewBuilder
    private func setupCard(glassOpacity: Double = 0.028, @ViewBuilder content: () -> some View) -> some View { content().padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(glassOpacity)), in: .rect(cornerRadius: setupCardCornerRadius)) }
    @ViewBuilder
    private var walletPasswordStepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedSetupString("import_flow.wallet_password_optional")).font(.headline).foregroundStyle(Color.primary)
            Text(localizedSetupString("import_flow.wallet_password_explanation")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
            SecureField(localizedSetupString("import_flow.wallet_password_field"), text: $draft.walletPassword).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
            SecureField(localizedSetupString("import_flow.wallet_password_confirmation_field"), text: $draft.walletPasswordConfirmation).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
            if let walletPasswordValidationError = draft.walletPasswordValidationError { Text(walletPasswordValidationError).font(.caption).foregroundStyle(.red.opacity(0.9)) } else if draft.normalizedWalletPassword != nil { Text(localizedSetupString("import_flow.wallet_password_success")).font(.caption).foregroundStyle(.green.opacity(0.9)) }}}
    @ViewBuilder
    private func chainSelectionCard(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNameSet.contains(descriptor.chainName)
        Button {
            draft.toggleChainSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 10) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.mark, color: descriptor.color, size: 32
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(descriptor.symbol.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title3.weight(.semibold)).foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.28))
            }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8).background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(isSelected ? descriptor.color.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.6 : 0.045))
            ).overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(colorScheme == .light ? 0.12 : 0.08), lineWidth: isSelected ? 1.6 : 1)
            )
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private func seedPhraseLengthPicker(title: String, subtitle: String, showsRegenerateButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.88))
            Text(localizedWalletFlowString(subtitle)).font(.footnote).foregroundStyle(Color.primary.opacity(0.7))
            HStack(spacing: 12) {
                Picker("Seed Phrase Length", selection: $draft.selectedSeedPhraseWordCount) {
                    ForEach([12, 15, 18, 21, 24], id: \.self) { wordCount in Text(walletFlowLocalizedFormat("%lld words", wordCount)).tag(wordCount) }}.labelsHidden().pickerStyle(.menu).padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).spectraInputFieldStyle().tint(.white)
                if showsRegenerateButton {
                    Button(localizedSetupString("Regenerate")) {
                        draft.regenerateSeedPhrase()
                    }.buttonStyle(.glass).disabled(![12, 15, 18, 21, 24].contains(draft.selectedSeedPhraseWordCount))
                }}
            HStack(spacing: 10) {
                TextField(localizedWalletFlowString("Custom word count"), text: $customSeedPhraseWordCountInput).keyboardType(.numberPad).textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).spectraInputFieldStyle()
                Button(localizedSetupString("Apply")) {
                    draft.applyCustomSeedPhraseWordCount(customSeedPhraseWordCountInput)
                    customSeedPhraseWordCountInput = String(draft.selectedSeedPhraseWordCount)
                }.buttonStyle(.glass)
            }
            if let seedPhraseLengthWarning = draft.seedPhraseLengthWarning { Text(seedPhraseLengthWarning).font(.footnote).foregroundStyle(.orange.opacity(0.92)) }}}
    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let validEntryColor: Color = colorScheme == .light ? Color.black.opacity(0.82) : .white
        HStack(spacing: 10) {
            Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.8)).frame(width: 24, height: 24).background(Color.white.opacity(0.08)).clipShape(Circle())
            if let text { Text(text).font(.footnote.monospaced()).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8) } else { TextField("word \(index + 1)", text: seedPhraseBinding(for: index)).textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(isInvalidWord ? .red.opacity(0.95) : validEntryColor).focused($focusedSeedPhraseIndex, equals: index) }}.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12).spectraInputFieldStyle(borderColor: isInvalidWord ? Color.red.opacity(0.85) : nil)
    }
    @ViewBuilder
    private func watchedAddressSection(title: String, text: Binding<String>, caption: String? = nil, validationMessage: String? = nil, validationColor: Color? = nil) -> some View {
        Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.88))
        watchedAddressEditor(text: text)
        if let caption { Text(caption).font(.caption).foregroundStyle(Color.primary.opacity(0.65)) }
        if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(validationColor ?? Color.primary.opacity(0.72)) }}
    private func watchedAddressValidationMessage(
        entries: [String], assetName: String, validator: (String) -> Bool
    ) -> (message: String, color: Color) {
        let localizedAssetName = assetName
        if entries.isEmpty { return (walletFlowLocalizedFormat("Enter one %@ address per line.", localizedAssetName), Color.primary.opacity(0.72)) }
        if !entries.allSatisfy(validator) { return (walletFlowLocalizedFormat("Every line must contain a valid %@ address.", localizedAssetName), .red.opacity(0.9)) }
        let count = entries.count
        let pluralSuffix = AppLocalization.locale.identifier.hasPrefix("en") && count != 1 ? "es" : ""
        return (walletFlowLocalizedFormat("%lld valid %@ address%@ ready to import.", count, localizedAssetName, pluralSuffix), .green.opacity(0.9))
    }
    @ViewBuilder
    private func conditionalWatchedAddressSection(
        condition: Bool, title: String, text: Binding<String>, assetName: String? = nil, validator: ((String) -> Bool)? = nil
    ) -> some View {
        if condition {
            if let validator {
                let entries = draft.watchOnlyEntries(from: text.wrappedValue)
                let v = watchedAddressValidationMessage(entries: entries, assetName: assetName ?? title, validator: validator)
                watchedAddressSection(title: title, text: text, validationMessage: v.message, validationColor: v.color)
            } else { watchedAddressSection(title: title, text: text) }}}
    @ViewBuilder
    private var derivationAdvancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(advancedDescriptionText).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
            VStack(alignment: .leading, spacing: 16) {
                if hasBitcoinSelection { bitcoinNetworkAdvancedSection }
                if hasEthereumSelection { ethereumNetworkAdvancedSection }
                if hasDogecoinSelection { dogecoinNetworkAdvancedSection }
                ForEach(draft.selectableDerivationChains) { chain in
                    SeedPathSlotEditor(
                        title: chain.rawValue, path: Binding(
                            get: { draft.seedDerivationPaths.path(for: chain) }, set: { draft.seedDerivationPaths.setPath($0, for: chain) }
                        ), defaultPath: chain.defaultPath, presetOptions: chain.presetOptions
                    )
                }}}}
    private var advancedDescriptionText: String {
        if hasBitcoinSelection && hasEthereumSelection && hasDogecoinSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Bitcoin, Ethereum, and Dogecoin networks when needed.") }
        if hasBitcoinSelection && hasEthereumSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Bitcoin and Ethereum networks when needed.") }
        if hasBitcoinSelection && hasDogecoinSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Bitcoin and Dogecoin networks when needed.") }
        if hasEthereumSelection && hasDogecoinSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Ethereum and Dogecoin networks when needed.") }
        if hasBitcoinSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Bitcoin network when needed.") }
        if hasEthereumSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Ethereum network when needed.") }
        if hasDogecoinSelection { return localizedSetupString("Control the derivation path used for each selected chain and choose the Dogecoin network when needed.") }
        return localizedSetupString("Control the derivation path used for each selected chain.")
    }
    private var bitcoinNetworkAdvancedSection: some View {
        networkModePicker(
            title: localizedSetupString("Bitcoin Network"), accentColor: .orange, caption: localizedSetupString("This controls Bitcoin wallet import, address validation, and endpoint usage for Bitcoin wallets."), modeOptions: BitcoinNetworkMode.allCases.map { ($0.rawValue, $0.displayName) }, currentModeID: store.bitcoinNetworkMode.rawValue, selectMode: { store.bitcoinNetworkMode = BitcoinNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private var ethereumNetworkAdvancedSection: some View {
        networkModePicker(
            title: localizedSetupString("Ethereum Network"), accentColor: .blue, caption: localizedSetupString("This controls Ethereum wallet import, balance refresh, history, and endpoint usage for Ethereum wallets."), modeOptions: EthereumNetworkMode.allCases.map { ($0.rawValue, $0.displayName) }, currentModeID: store.ethereumNetworkMode.rawValue, selectMode: { store.ethereumNetworkMode = EthereumNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private var dogecoinNetworkAdvancedSection: some View {
        networkModePicker(
            title: localizedSetupString("Dogecoin Network"), accentColor: .yellow, accentForeground: .yellow.opacity(0.9), caption: localizedSetupString("This controls Dogecoin wallet import, address validation, history, and endpoint usage for Dogecoin wallets."), modeOptions: DogecoinNetworkMode.allCases.map { ($0.rawValue, $0.displayName) }, currentModeID: store.dogecoinNetworkMode.rawValue, selectMode: { store.dogecoinNetworkMode = DogecoinNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private func networkModePicker(
        title: String, accentColor: Color, accentForeground: Color? = nil, caption: String, modeOptions: [(id: String, displayName: String)], currentModeID: String, selectMode: @escaping (String) -> Void
    ) -> some View {
        let fg = accentForeground ?? accentColor
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.88))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(modeOptions, id: \.id) { mode in
                    let isSelected = currentModeID == mode.id
                    Button { selectMode(mode.id) } label: {
                        HStack(spacing: 8) {
                            Text(mode.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? fg : Color.primary)
                            Spacer(minLength: 0)
                            if isSelected { Image(systemName: "checkmark.circle.fill").font(.caption.weight(.bold)).foregroundStyle(fg) }}.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? accentColor.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.78 : 0.05))
                        ).overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }.buttonStyle(.plain)
                }}
            Text(caption).font(.caption).foregroundStyle(Color.primary.opacity(0.65))
        }}
    @ViewBuilder
    private var derivationAdvancedButton: some View {
        if !isEditingWallet && !draft.selectedChainNames.isEmpty {
            Button {
                withAnimation {
                    setupPage = .advanced
                }} label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 26, height: 26).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedSetupString("Advanced")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                        Text(advancedButtonSubtitle).font(.caption2).foregroundStyle(Color.primary.opacity(0.68))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.72))
                }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle()
            }.buttonStyle(.plain)
        }}
    private var advancedButtonSubtitle: String {
        if hasBitcoinSelection && hasEthereumSelection && hasDogecoinSelection { return localizedSetupString("Adjust derivation paths plus Bitcoin, Ethereum, and Dogecoin networks.") }
        if hasBitcoinSelection && hasEthereumSelection { return localizedSetupString("Adjust derivation paths plus Bitcoin and Ethereum networks.") }
        if hasBitcoinSelection && hasDogecoinSelection { return localizedSetupString("Adjust derivation paths plus Bitcoin and Dogecoin networks.") }
        if hasEthereumSelection && hasDogecoinSelection { return localizedSetupString("Adjust derivation paths plus Ethereum and Dogecoin networks.") }
        if hasBitcoinSelection { return localizedSetupString("Adjust derivation paths and Bitcoin network.") }
        if hasEthereumSelection { return localizedSetupString("Adjust derivation paths and Ethereum network.") }
        if hasDogecoinSelection { return localizedSetupString("Adjust derivation paths and Dogecoin network.") }
        return localizedSetupString("Adjust derivation paths.")
    }
    @ViewBuilder
    private var importSecretModePicker: some View {
        if !isEditingWallet && !isCreateMode && !draft.isWatchOnlyMode {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedWalletFlowString("Import Method")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.88))
                Picker("Import Method", selection: importSecretModeBinding) {
                    ForEach(WalletSecretImportMode.allCases) { mode in Text(mode.localizedTitle).tag(mode) }}.pickerStyle(.segmented)
                Text(draft.secretImportMode == .seedPhrase
                    ? copy.seedImportMethodDescription
                    : copy.privateKeyImportMethodDescription).font(.caption).foregroundStyle(Color.primary.opacity(0.68))
            }}}
    private var importSecretModeBinding: Binding<WalletSecretImportMode> {
        Binding(
            get: { draft.secretImportMode }, set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    draft.secretImportMode = newValue
                }}
        )
    }
    @ViewBuilder
    private var newWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(title: copy.importSeedLengthTitle, subtitle: copy.importSeedLengthSubtitle)
        Text(copy.seedPhraseEntryHelp).font(.footnote).foregroundStyle(Color.primary.opacity(0.7))
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(0 ..< draft.selectedSeedPhraseWordCount, id: \.self) { index in seedPhraseField(at: index) }}
            if !seedPhraseStatusText.isEmpty { Text(seedPhraseStatusText).font(.footnote).foregroundStyle(seedPhraseStatusColor) }}
    @ViewBuilder
    private var createWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.createSeedLengthTitle, subtitle: copy.createSeedLengthSubtitle, showsRegenerateButton: true
        )
        Text(copy.createSeedPhraseWarning).font(.footnote).foregroundStyle(Color.primary.opacity(0.72))
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(Array(draft.seedPhraseWords.enumerated()), id: \.offset) { index, word in
                numberedSeedPhraseRow(index: index, text: word)
            }}}
    @ViewBuilder
    private var privateKeyImportSection: some View {
        importSecretModePicker
        privateKeyImportFields
    }
    @ViewBuilder
    private var privateKeyImportFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.privateKeyTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.88))
            Text(copy.privateKeyPrompt).font(.footnote).foregroundStyle(Color.primary.opacity(0.7))
            TextField(copy.privateKeyPlaceholder, text: $draft.privateKeyInput).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
            if !draft.unsupportedPrivateKeyChainNames.isEmpty { Text(walletFlowLocalizedFormat("Private key import is not available for: %@.", draft.unsupportedPrivateKeyChainNames.joined(separator: ", "))).font(.footnote).foregroundStyle(.orange.opacity(0.9)) } else if !draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !PrivateKeyHex.isLikely(draft.privateKeyInput) { Text(localizedSetupString("Enter a valid 32-byte hex private key.")).font(.footnote).foregroundStyle(.red.opacity(0.9)) }}}
    @ViewBuilder
    private var walletSecretStepSection: some View {
        if isCreateMode {
            createWalletSeedPhraseSection
            if !isSimpleSetupSelected { derivationAdvancedButton }
        } else {
            importSecretModePicker
            Group {
                if isPrivateKeyImportMode { privateKeyImportFields } else {
                    VStack(alignment: .leading, spacing: 16) {
                        newWalletSeedPhraseSection
                        if !isSimpleSetupSelected { derivationAdvancedButton }}}}.id(draft.secretImportMode).transition(.opacity).animation(.easeInOut(duration: 0.2), value: draft.secretImportMode)
        }}
    @ViewBuilder
    private var backupVerificationStepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.backupVerificationTitle).font(.headline).foregroundStyle(Color.primary)
            if !draft.backupVerificationPromptLabel.isEmpty { Text(draft.backupVerificationPromptLabel).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76)) }
            if draft.backupVerificationWordIndices.isEmpty {
                Button(copy.backupVerificationButtonTitle) {
                    draft.prepareBackupVerificationChallenge()
                }.buttonStyle(.glass)
            } else {
                ForEach(Array(draft.backupVerificationWordIndices.enumerated()), id: \.offset) { offset, wordIndex in
                    HStack(spacing: 10) {
                        Text(walletFlowLocalizedFormat("Word #%lld", wordIndex + 1)).font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.82)).frame(width: 88, alignment: .leading)
                        TextField("Enter word \(wordIndex + 1)", text: backupVerificationBinding(for: offset)).textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(Color.primary)
                    }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle(cornerRadius: 16)
                }
                if draft.isBackupVerificationComplete { Text(copy.backupVerifiedMessage).font(.footnote).foregroundStyle(.green.opacity(0.9)) } else { Text(copy.backupVerificationHint).font(.footnote).foregroundStyle(Color.primary.opacity(0.7)) }}}.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 24))
    }
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    setupCard(glassOpacity: 0.033) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                SpectraLogo(size: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(setupTitle).font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(Color.primary).lineLimit(2).minimumScaleFactor(0.8).allowsTightening(true).layoutPriority(1).fixedSize(horizontal: false, vertical: true)
                                    Text(setupSubtitle).font(.footnote).foregroundStyle(Color.primary.opacity(0.76))
                                }
                                Spacer()
                            }}}
                    if isShowingBackupVerificationPage { backupVerificationStepSection } else if isShowingSetupModeChoicePage {
                        setupCard {
                            setupModeChoiceSection
                        }
                    } else if !isEditingWallet && isShowingDetailsPage {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) { Text(localizedSetupString("Chains")).font(.headline).foregroundStyle(Color.primary) }
                                    Spacer()
                                    Text(chainSelectionSummary).font(.caption.weight(.semibold)).foregroundStyle(selectedChainCount == 0 ? Color.primary.opacity(0.68) : .orange).padding(.horizontal, 10).padding(.vertical, 6).background(
                                            Capsule(style: .continuous).fill(selectedChainCount == 0 ? Color.white.opacity(colorScheme == .light ? 0.55 : 0.08) : Color.orange.opacity(0.12))
                                        )
                                }
                                LazyVGrid(columns: chainSelectionColumns, spacing: 10) {
                                    ForEach(popularChainSelectionDescriptors) { descriptor in chainSelectionCard(descriptor) }}
                                if !Self.nonPopularChainSelectionDescriptors.isEmpty {
                                    Button {
                                        chainSearchText = ""
                                        isShowingAllChainsSheet = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "square.grid.2x2").font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 26, height: 26).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(localizedSetupString("See All Chains")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                                Text(localizedSetupString("Browse the full chain list.")).font(.caption2).foregroundStyle(Color.primary.opacity(0.68))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.72))
                                        }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle()
                                    }.buttonStyle(.plain)
                                }
                                Text(chainSelectionSubtitle).font(.caption).foregroundStyle(Color.primary.opacity(0.72))
                                if isEditingWallet { Text(copy.watchOnlyFixedMessage).font(.caption).foregroundStyle(Color.primary.opacity(0.6)) } else if isWatchAddressesImportMode { Text(copy.publicAddressOnlyMessage).font(.caption).foregroundStyle(Color.primary.opacity(0.6)) } else if draft.wantsMonero { Text(copy.moneroWatchUnsupportedMessage).font(.caption).foregroundStyle(.orange.opacity(0.9)) }}.tint(.orange)
                        }.sheet(isPresented: $isShowingAllChainsSheet) {
                            AllChainsSelectionView(
                                chainSearchText: $chainSearchText, descriptors: Self.sortedChainSelectionDescriptors, selectedChainNames: selectedChainNameSet, toggleSelection: draft.toggleChainSelection
                            )
                        }}
                    if isShowingWatchAddressesPage, !isEditingWallet, draft.isWatchOnlyMode {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                            Text(copy.addressesToWatchTitle).font(.headline).foregroundStyle(Color.primary)
                            Text(copy.addressesToWatchSubtitle).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76))
                            if draft.wantsBitcoin {
                                let bitcoinAddressEntries = draft.watchOnlyEntries(from: draft.bitcoinAddressInput)
                                let bitcoinValidation = watchedAddressValidationMessage(
                                    entries: bitcoinAddressEntries, assetName: "Bitcoin", validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: store.bitcoinNetworkMode) }
                                )
                                watchedAddressSection(
                                    title: "Bitcoin", text: $draft.bitcoinAddressInput, caption: copy.bitcoinWatchCaption, validationMessage: bitcoinValidation.message, validationColor: bitcoinValidation.color
                                )
                                TextField("xpub... / zpub...", text: $draft.bitcoinXpubInput).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
                            }
                            conditionalWatchedAddressSection(condition: draft.wantsBitcoinCash, title: "Bitcoin Cash", text: $draft.bitcoinCashAddressInput, validator: { AddressValidation.isValidBitcoinCashAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsBitcoinSV, title: "Bitcoin SV", text: $draft.bitcoinSvAddressInput, validator: { AddressValidation.isValidBitcoinSVAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsDogecoin, title: "Dogecoin", text: $draft.dogecoinAddressInput, validator: { AddressValidation.isValidDogecoinAddress($0, networkMode: store.dogecoinNetworkMode) })
                            conditionalWatchedAddressSection(condition: draft.wantsLitecoin, title: "Litecoin", text: $draft.litecoinAddressInput, validator: { AddressValidation.isValidLitecoinAddress($0) })
                            if draft.wantsEthereum || draft.wantsEthereumClassic || draft.wantsArbitrum || draft.wantsOptimism || draft.wantsBNBChain || draft.wantsAvalanche || draft.wantsHyperliquid {
                                let ethereumAddressEntries = draft.watchOnlyEntries(from: draft.ethereumAddressInput)
                                let evmValidation = watchedAddressValidationMessage(
                                    entries: ethereumAddressEntries, assetName: "EVM", validator: { AddressValidation.isValidEthereumAddress($0) }
                                )
                                watchedAddressSection(
                                    title: "EVM (Ethereum / ETC / Arbitrum / Optimism / BNB Chain / Avalanche / Hyperliquid)", text: $draft.ethereumAddressInput, validationMessage: evmValidation.message, validationColor: evmValidation.color
                                )
                            }
                            conditionalWatchedAddressSection(condition: draft.wantsTron, title: "Tron", text: $draft.tronAddressInput, validator: { AddressValidation.isValidTronAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsSolana, title: "Solana", text: $draft.solanaAddressInput, validator: { AddressValidation.isValidSolanaAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsXRP, title: "XRP Ledger", text: $draft.xrpAddressInput, validator: { AddressValidation.isValidXRPAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsMonero, title: "Monero", text: $draft.moneroAddressInput)
                            conditionalWatchedAddressSection(condition: draft.wantsCardano, title: "Cardano", text: $draft.cardanoAddressInput, validator: { AddressValidation.isValidCardanoAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsSui, title: "Sui", text: $draft.suiAddressInput, validator: { AddressValidation.isValidSuiAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsAptos, title: "Aptos", text: $draft.aptosAddressInput, validator: { AddressValidation.isValidAptosAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsTON, title: "TON", text: $draft.tonAddressInput, validator: { AddressValidation.isValidTONAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsICP, title: "Internet Computer", text: $draft.icpAddressInput, validator: { AddressValidation.isValidICPAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsNear, title: "NEAR", text: $draft.nearAddressInput, validator: { AddressValidation.isValidNearAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsPolkadot, title: "Polkadot", text: $draft.polkadotAddressInput, validator: { AddressValidation.isValidPolkadotAddress($0) })
                            conditionalWatchedAddressSection(condition: draft.wantsStellar, title: "Stellar", text: $draft.stellarAddressInput, validator: { AddressValidation.isValidStellarAddress($0) })
                            if !draft.wantsBitcoin && !draft.wantsBitcoinCash && !draft.wantsBitcoinSV && !draft.wantsLitecoin && !draft.wantsDogecoin && !draft.wantsEthereum && !draft.wantsEthereumClassic && !draft.wantsSolana && !draft.wantsBNBChain && !draft.wantsTron && !draft.wantsXRP && !draft.wantsMonero && !draft.wantsCardano && !draft.wantsSui && !draft.wantsAptos && !draft.wantsTON && !draft.wantsICP && !draft.wantsNear && !draft.wantsPolkadot && !draft.wantsStellar { Text(localizedSetupString("Select a supported chain above to enter its address to watch.")).font(.caption).foregroundStyle(.orange.opacity(0.9)) }}}}
                    if isShowingDetailsPage || isEditingWallet {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(
                                    isEditingWallet
                                        ? localizedSetupString("import_flow.wallet_name")
                                        : localizedSetupString("import_flow.wallet_name_optional")
                                ).font(.headline).foregroundStyle(Color.primary)
                                if !isEditingWallet { Text(localizedSetupString("import_flow.wallet_name_hint")).font(.subheadline).foregroundStyle(Color.primary.opacity(0.76)) }
                                HStack(spacing: 10) {
                                    TextField(localizedSetupString("import_flow.wallet_name_placeholder"), text: $draft.walletName).textInputAutocapitalization(.words).autocorrectionDisabled().foregroundStyle(Color.primary)
                                    if isEditingWallet && !draft.walletName.isEmpty {
                                        Button {
                                            draft.walletName = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                                        }.buttonStyle(.plain).accessibilityLabel("Clear wallet name")
                                    }}.padding(14).spectraInputFieldStyle()
                            }}}
                    if isShowingSeedPhrasePage && !draft.isWatchOnlyMode {
                        setupCard {
                            VStack(alignment: .leading, spacing: 14) { walletSecretStepSection }}}
                    if isShowingPasswordPage {
                        setupCard {
                            walletPasswordStepSection
                        }}
                    if isShowingAdvancedPage {
                        setupCard {
                            derivationAdvancedContent
                        }}
                    if let importError = store.importError { Text(importError).font(.footnote).foregroundStyle(.red.opacity(0.9)) }
                    if store.isImportingWallet {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(localizedSetupString("import_flow.initializing_wallet_connections")).font(.footnote).foregroundStyle(Color.primary.opacity(0.8))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !isShowingAdvancedPage {
                        Button(action: {
                            if isShowingSetupModeChoicePage {
                                withAnimation {
                                    setupPage = .details
                                }
                                return
                            }
                            if isShowingDetailsPage && usesWatchAddressesFlow {
                                withAnimation {
                                    setupPage = .watchAddresses
                                }
                                return
                            }
                            if isShowingDetailsPage && usesSeedPhraseFlow {
                                withAnimation {
                                    setupPage = .seedPhrase
                                }
                                return
                            }
                            if isShowingSeedPhrasePage {
                                withAnimation {
                                    setupPage = .password
                                }
                                return
                            }
                            if isShowingPasswordPage && isCreateMode {
                                draft.prepareBackupVerificationChallenge()
                                withAnimation {
                                    setupPage = .backupVerification
                                }
                                return
                            }
                            Task {
                                await store.importWallet()
                            }}) {
                            HStack {
                                Text(primaryActionTitle).font(.headline)
                                Spacer()
                                SpectraLogo(size: 28)
                            }.foregroundStyle(Color.primary).padding().frame(maxWidth: .infinity)
                        }.buttonStyle(.glassProminent).disabled(!isPrimaryActionEnabled).opacity(isPrimaryActionEnabled ? 1.0 : 0.55)
                    }
                    if isShowingSeedPhrasePage || isShowingWatchAddressesPage {
                        Button(localizedSetupString("import_flow.back")) {
                            withAnimation {
                                setupPage = .details
                            }}.buttonStyle(.glass)
                    } else if isShowingDetailsPage && !isEditingWallet {
                        Button(localizedSetupString("import_flow.back")) {
                            withAnimation {
                                setupPage = .setupModeChoice
                            }}.buttonStyle(.glass)
                    } else if isShowingAdvancedPage {
                        Button(localizedSetupString("import_flow.back")) {
                            withAnimation {
                                setupPage = .seedPhrase
                            }}.buttonStyle(.glass)
                    } else if isShowingPasswordPage {
                        Button(localizedSetupString("import_flow.back")) {
                            withAnimation {
                                setupPage = .seedPhrase
                            }}.buttonStyle(.glass)
                    } else if isShowingBackupVerificationPage {
                        Button(localizedSetupString("import_flow.back_to_wallet_password")) {
                            withAnimation {
                                setupPage = .password
                            }}.buttonStyle(.glass)
                    }}.padding(.horizontal, 20).padding(.vertical, 24)
            }}.onChange(of: draft.mode) { _, mode in
            setupPage = draft.isEditingWallet ? .details : .setupModeChoice
            setupModeChoice = nil
        }.onChange(of: draft.selectedSeedPhraseWordCount) { _, newValue in
            customSeedPhraseWordCountInput = String(newValue)
        }}
}
private struct AllChainsSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chainSearchText: String
    let descriptors: [SetupChainSelectionDescriptor]
    let selectedChainNames: Set<String>
    let toggleSelection: (String) -> Void
    private var filteredDescriptors: [SetupChainSelectionDescriptor] {
        let query = chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return descriptors }
        return descriptors.filter { descriptor in
            descriptor.title.localizedCaseInsensitiveContains(query)
                || descriptor.symbol.localizedCaseInsensitiveContains(query)
        }}
    private var isSearching: Bool { !chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @ViewBuilder
    private func row(for descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNames.contains(descriptor.chainName)
        Button {
            toggleSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 12) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.mark, color: descriptor.color, size: 28
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                    Text(descriptor.symbol.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.56))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.body.weight(.semibold)).foregroundStyle(isSelected ? descriptor.color : Color.primary.opacity(0.24))
            }.padding(.horizontal, 12).padding(.vertical, 8).background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? descriptor.color.opacity(0.1) : Color.clear)
            )
        }.buttonStyle(.plain)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(Color.primary.opacity(0.6))
                                TextField(localizedSetupString("import_flow.search_chains"), text: $chainSearchText).textInputAutocapitalization(.never).autocorrectionDisabled()
                            }.padding(.horizontal, 14).padding(.vertical, 12).spectraInputFieldStyle()
                            if filteredDescriptors.isEmpty { Text(localizedSetupString("import_flow.no_chains_match")).font(.caption).foregroundStyle(Color.primary.opacity(0.7)) } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(filteredDescriptors) { descriptor in row(for: descriptor) }}}}.padding(16).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
                    }.padding(.horizontal, 20).padding(.vertical, 20)
                }}.navigationTitle(localizedSetupString("import_flow.all_chains_title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizedSetupString("import_flow.done")) {
                        dismiss()
                    }}}}}
}
