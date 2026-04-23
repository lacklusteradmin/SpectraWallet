import Foundation
import SwiftUI
private struct SetupChainSelectionDescriptor: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let chainName: String
    let assetIdentifier: String?
    let color: Color
    var title: String { localizedWalletFlowString(titleKey) }
    init(id: String, title: String, symbol: String, chainName: String, color: Color) {
        self.id = id
        self.titleKey = title
        self.symbol = symbol
        self.chainName = chainName
        self.assetIdentifier = Coin.iconIdentifier(symbol: symbol, chainName: chainName)
        self.color = color
    }
}
struct SetupView: View {
    private static let chainSelectionDescriptors: [SetupChainSelectionDescriptor] = [
        SetupChainSelectionDescriptor(id: "bitcoin", title: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", color: .orange),
        SetupChainSelectionDescriptor(
            id: "bitcoin-cash", title: "Bitcoin Cash", symbol: "BCH", chainName: "Bitcoin Cash", color: .orange),
        SetupChainSelectionDescriptor(
            id: "bitcoin-sv", title: "Bitcoin SV", symbol: "BSV", chainName: "Bitcoin SV", color: .orange),
        SetupChainSelectionDescriptor(id: "litecoin", title: "Litecoin", symbol: "LTC", chainName: "Litecoin", color: .gray),
        SetupChainSelectionDescriptor(id: "ethereum", title: "Ethereum", symbol: "ETH", chainName: "Ethereum", color: .blue),
        SetupChainSelectionDescriptor(
            id: "ethereum-classic", title: "Ethereum Classic", symbol: "ETC", chainName: "Ethereum Classic", color: .green),
        SetupChainSelectionDescriptor(id: "solana", title: "Solana", symbol: "SOL", chainName: "Solana", color: .purple),
        SetupChainSelectionDescriptor(id: "arbitrum", title: "Arbitrum", symbol: "ARB", chainName: "Arbitrum", color: .cyan),
        SetupChainSelectionDescriptor(id: "optimism", title: "Optimism", symbol: "OP", chainName: "Optimism", color: .red),
        SetupChainSelectionDescriptor(
            id: "bnb-chain", title: "BNB Chain", symbol: "BNB", chainName: "BNB Chain", color: .yellow),
        SetupChainSelectionDescriptor(id: "avalanche", title: "Avalanche", symbol: "AVAX", chainName: "Avalanche", color: .red),
        SetupChainSelectionDescriptor(
            id: "hyperliquid", title: "Hyperliquid", symbol: "HYPE", chainName: "Hyperliquid", color: .mint),
        SetupChainSelectionDescriptor(id: "dogecoin", title: "Dogecoin", symbol: "DOGE", chainName: "Dogecoin", color: .brown),
        SetupChainSelectionDescriptor(id: "cardano", title: "Cardano", symbol: "ADA", chainName: "Cardano", color: .indigo),
        SetupChainSelectionDescriptor(id: "tron", title: "Tron", symbol: "TRX", chainName: "Tron", color: .teal),
        SetupChainSelectionDescriptor(
            id: "xrp-ledger", title: "XRP Ledger", symbol: "XRP", chainName: "XRP Ledger", color: .cyan),
        SetupChainSelectionDescriptor(id: "monero", title: "Monero", symbol: "XMR", chainName: "Monero", color: .indigo),
        SetupChainSelectionDescriptor(id: "sui", title: "Sui", symbol: "SUI", chainName: "Sui", color: .mint),
        SetupChainSelectionDescriptor(id: "aptos", title: "Aptos", symbol: "APT", chainName: "Aptos", color: .cyan),
        SetupChainSelectionDescriptor(id: "ton", title: "TON", symbol: "TON", chainName: "TON", color: .blue),
        SetupChainSelectionDescriptor(
            id: "internet-computer", title: "Internet Computer", symbol: "ICP", chainName: "Internet Computer", color: .indigo),
        SetupChainSelectionDescriptor(id: "near", title: "NEAR", symbol: "NEAR", chainName: "NEAR", color: .indigo),
        SetupChainSelectionDescriptor(id: "polkadot", title: "Polkadot", symbol: "DOT", chainName: "Polkadot", color: .pink),
        SetupChainSelectionDescriptor(id: "stellar", title: "Stellar", symbol: "XLM", chainName: "Stellar", color: .teal),
    ]
    private static let popularChainSelectionIDs: Set<String> = [
        "bitcoin", "ethereum", "solana", "monero", "litecoin", "tron",
    ]
    private static let nonPopularChainSelectionDescriptors = chainSelectionDescriptors.filter { !popularChainSelectionIDs.contains($0.id) }
    private static let sortedChainSelectionDescriptors = chainSelectionDescriptors.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    private enum SetupPage {
        case details
        case watchAddresses
        case seedPhrase
        case password
        case advanced
        case backupVerification
    }
    private let store: AppState
    @Bindable var draft: WalletImportDraft
    private let copy = ImportFlowContent.current
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var setupPage: SetupPage
    @State private var customSeedPhraseWordCountInput: String
    @State private var chainSearchText: String = ""
    @State private var isShowingAllChainsSheet: Bool = false
    @FocusState private var focusedSeedPhraseIndex: Int?
    private let chainSelectionColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
    ]
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
    ]
    private let setupCardCornerRadius: CGFloat = 24
    init(store: AppState, draft: WalletImportDraft) {
        self.store = store
        self.draft = draft
        _setupPage = State(initialValue: .details)
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
    private var isShowingSeedPhrasePage: Bool { setupPage == .seedPhrase }
    private var isShowingWatchAddressesPage: Bool { setupPage == .watchAddresses }
    private var isShowingPasswordPage: Bool { setupPage == .password }
    private var isShowingBackupVerificationPage: Bool { setupPage == .backupVerification }
    private var isShowingAdvancedPage: Bool { setupPage == .advanced }
    private var isSimpleSetupSelected: Bool { draft.setupModeChoice == .simple }
    private var setupTitle: String {
        if isShowingBackupVerificationPage { return copy.backupVerificationTitle }
        if isShowingAdvancedPage { return copy.advancedTitle }
        if isShowingPasswordPage { return AppLocalization.string("import_flow.wallet_password_title") }
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
        if isShowingBackupVerificationPage { return copy.backupVerificationSubtitle }
        if isShowingAdvancedPage { return copy.advancedSubtitle }
        if isShowingPasswordPage { return AppLocalization.string("import_flow.wallet_password_subtitle") }
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
        if !draft.invalidSeedWords.isEmpty {
            return AppLocalization.format("import_flow.seed_phrase_invalid_words_format", draft.invalidSeedWords.joined(separator: ", "))
        }
        if draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount {
            return AppLocalization.format(
                "import_flow.seed_phrase_progress_format", draft.seedPhraseWords.count, draft.selectedSeedPhraseWordCount)
        }
        if let validationError = draft.seedPhraseValidationError { return validationError }
        return AppLocalization.string("import_flow.seed_phrase_valid_status")
    }
    private var seedPhraseStatusColor: Color {
        if draft.seedPhraseWords.isEmpty || draft.seedPhraseWords.count < draft.selectedSeedPhraseWordCount { return .white.opacity(0.7) }
        if !draft.invalidSeedWords.isEmpty || draft.seedPhraseValidationError != nil { return .red.opacity(0.9) }
        return .green.opacity(0.9)
    }
    private func seedPhraseBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { draft.seedPhraseEntry(at: index) },
            set: { newValue in
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
                && CachedCoreHelpers.privateKeyHexIsLikely(rawValue: draft.privateKeyInput)
                && draft.unsupportedPrivateKeyChainNames.isEmpty
                && draft.selectedChainNames.count == 1
                && !store.isImportingWallet
        }
        let hasValidSeedPhrase =
            draft.seedPhraseWords.count == draft.selectedSeedPhraseWordCount
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
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) { return AppLocalization.string("import_flow.next") }
        if isShowingAdvancedPage { return "" }
        if isShowingSeedPhrasePage { return AppLocalization.string("import_flow.next") }
        if isShowingPasswordPage && isCreateMode { return AppLocalization.string("import_flow.continue_to_backup_verification") }
        if isEditingWallet { return AppLocalization.string("import_flow.save_wallet") }
        if isCreateMode { return AppLocalization.string("import_flow.create_wallet") }
        return isWatchAddressesImportMode
            ? AppLocalization.string("import_flow.watch_addresses") : AppLocalization.string("import_flow.import_wallet")
    }
    private var isPrimaryActionEnabled: Bool {
        if isShowingDetailsPage && (usesSeedPhraseFlow || usesWatchAddressesFlow) { return canAdvanceFromDetailsPage }
        if isShowingAdvancedPage { return false }
        if isShowingSeedPhrasePage { return canContinueFromSecretStep }
        if isShowingPasswordPage && isCreateMode { return canContinueToBackupVerification }
        if isShowingPasswordPage { return canSubmitFromPasswordStep }
        return store.canImportWallet && !store.isImportingWallet
    }
    private var popularChainSelectionDescriptors: [SetupChainSelectionDescriptor] {
        Self.chainSelectionDescriptors.filter { Self.popularChainSelectionIDs.contains($0.id) }
    }
    private var selectedChainNameSet: Set<String> { Set(draft.selectedChainNames) }
    private var selectedChainCount: Int { draft.selectedChainNames.count }
    private var chainSelectionSummary: String {
        switch selectedChainCount {
        case 0: return AppLocalization.string("import_flow.no_chains_selected")
        case 1: return AppLocalization.string("import_flow.one_chain_selected")
        default: return AppLocalization.format("import_flow.multiple_chains_selected_format", selectedChainCount)
        }
    }
    private var chainSelectionSubtitle: String {
        if isCreateMode { return AppLocalization.string("import_flow.create_chain_selection_subtitle") }
        return AppLocalization.string("import_flow.import_chain_selection_subtitle")
    }
    @ViewBuilder
    private func seedPhraseField(at index: Int) -> some View {
        let entry = draft.seedPhraseEntry(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalidWord = !entry.isEmpty && !BIP39EnglishWordList.words.contains(entry)
        numberedSeedPhraseRow(index: index, isInvalidWord: isInvalidWord)
    }
    @ViewBuilder
    private func watchedAddressEditor(text: Binding<String>) -> some View {
        TextEditor(text: text).textInputAutocapitalization(.never).autocorrectionDisabled().scrollContentBackground(.hidden).frame(
            minHeight: 88
        ).padding(10).spectraInputFieldStyle().foregroundStyle(Color.primary)
    }
    @ViewBuilder
    private func setupCard<Content: View>(glassOpacity: Double = 0.028, @ViewBuilder content: () -> Content) -> some View {
        // `glassOpacity` kept for call-site compatibility but no longer used —
        // flat fill replaces the Liquid Glass pass to avoid ~10 stacked shader
        // passes on the setup screen.
        content().padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: setupCardCornerRadius)
    }
    @ViewBuilder
    private var walletPasswordStepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.string("import_flow.wallet_password_optional")).font(.headline).foregroundStyle(Color.primary)
            Text(AppLocalization.string("import_flow.wallet_password_explanation")).font(.subheadline).foregroundStyle(.secondary)
            SecureField(AppLocalization.string("import_flow.wallet_password_field"), text: $draft.walletPassword).textInputAutocapitalization(
                .never
            ).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
            SecureField(AppLocalization.string("import_flow.wallet_password_confirmation_field"), text: $draft.walletPasswordConfirmation)
                .textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(
                    Color.primary)
            if let walletPasswordValidationError = draft.walletPasswordValidationError {
                Text(walletPasswordValidationError).font(.caption).foregroundStyle(.red.opacity(0.9))
            } else if draft.normalizedWalletPassword != nil {
                Text(AppLocalization.string("import_flow.wallet_password_success")).font(.caption).foregroundStyle(.green.opacity(0.9))
            }
        }
    }
    @ViewBuilder
    private func chainSelectionCard(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNameSet.contains(descriptor.chainName)
        Button {
            draft.toggleChainSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 10) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol, color: descriptor.color, size: 32
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(descriptor.symbol.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(
                        isSelected ? descriptor.color : Color.primary.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title3.weight(.semibold)).foregroundStyle(
                    isSelected ? descriptor.color : Color.primary.opacity(0.28))
            }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8).background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
                    isSelected ? descriptor.color.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.6 : 0.045))
            ).overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(
                    isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(colorScheme == .light ? 0.12 : 0.08),
                    lineWidth: isSelected ? 1.6 : 1)
            )
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private func seedPhraseLengthPicker(title: String, subtitle: String, showsRegenerateButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(localizedWalletFlowString(subtitle)).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("Seed Phrase Length", selection: $draft.selectedSeedPhraseWordCount) {
                    ForEach([12, 15, 18, 21, 24], id: \.self) { wordCount in
                        Text(walletFlowLocalizedFormat("%lld words", wordCount)).tag(wordCount)
                    }
                }.labelsHidden().pickerStyle(.menu).padding(.horizontal, 14).padding(.vertical, 12).frame(
                    maxWidth: .infinity, alignment: .leading
                ).spectraInputFieldStyle().tint(.white)
                if showsRegenerateButton {
                    Button(AppLocalization.string("Regenerate")) {
                        draft.regenerateSeedPhrase()
                    }.buttonStyle(.glass).disabled(![12, 15, 18, 21, 24].contains(draft.selectedSeedPhraseWordCount))
                }
            }
            HStack(spacing: 10) {
                TextField(localizedWalletFlowString("Custom word count"), text: $customSeedPhraseWordCountInput).keyboardType(.numberPad)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 14).padding(.vertical, 12).frame(
                        maxWidth: .infinity, alignment: .leading
                    ).spectraInputFieldStyle()
                Button(AppLocalization.string("Apply")) {
                    draft.applyCustomSeedPhraseWordCount(customSeedPhraseWordCountInput)
                    customSeedPhraseWordCountInput = String(draft.selectedSeedPhraseWordCount)
                }.buttonStyle(.glass)
            }
            if let seedPhraseLengthWarning = draft.seedPhraseLengthWarning {
                Text(seedPhraseLengthWarning).font(.footnote).foregroundStyle(.orange.opacity(0.92))
            }
        }
    }
    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let validEntryColor: Color = colorScheme == .light ? Color.black.opacity(0.82) : .white
        HStack(spacing: 10) {
            Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08)).clipShape(Circle())
            if let text {
                Text(text).font(.footnote.monospaced()).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8)
            } else {
                TextField("word \(index + 1)", text: seedPhraseBinding(for: index)).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().foregroundStyle(isInvalidWord ? .red.opacity(0.95) : validEntryColor).focused(
                        $focusedSeedPhraseIndex, equals: index)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12).spectraInputFieldStyle(
            borderColor: isInvalidWord ? Color.red.opacity(0.85) : nil)
    }
    @ViewBuilder
    private func watchedAddressSection(
        title: String, text: Binding<String>, caption: String? = nil, validationMessage: String? = nil, validationColor: Color? = nil
    ) -> some View {
        Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        watchedAddressEditor(text: text)
        if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
        if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(validationColor ?? Color.secondary) }
    }
    private func watchedAddressValidationMessage(
        entries: [String], assetName: String, validator: (String) -> Bool
    ) -> (message: String, color: Color) {
        let localizedAssetName = assetName
        if entries.isEmpty {
            return (walletFlowLocalizedFormat("Enter one %@ address per line.", localizedAssetName), Color.secondary)
        }
        if !entries.allSatisfy(validator) {
            return (walletFlowLocalizedFormat("Every line must contain a valid %@ address.", localizedAssetName), .red.opacity(0.9))
        }
        let count = entries.count
        let pluralSuffix = AppLocalization.locale.identifier.hasPrefix("en") && count != 1 ? "es" : ""
        return (
            walletFlowLocalizedFormat("%lld valid %@ address%@ ready to import.", count, localizedAssetName, pluralSuffix),
            .green.opacity(0.9)
        )
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
            } else {
                watchedAddressSection(title: title, text: text)
            }
        }
    }
    @ViewBuilder
    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepIndicatorText).font(.footnote.weight(.semibold)).foregroundStyle(.orange).textCase(.uppercase)
            Text(setupTitle).font(.largeTitle.weight(.bold)).foregroundStyle(Color.primary)
                .lineLimit(3).minimumScaleFactor(0.7).allowsTightening(true).fixedSize(horizontal: false, vertical: true)
            Text(setupSubtitle).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var stepIndicatorText: String {
        let (current, total) = currentStepPosition
        guard total > 0 else { return "" }
        return "\(AppLocalization.string("import_flow.step_label")) \(current) \(AppLocalization.string("import_flow.step_of")) \(total)"
    }
    private var currentStepPosition: (current: Int, total: Int) {
        // Flow-specific step counting. Watch-only = 2 steps, create = 4 (details/seed/password/verify), import = 3 (details/secret/password).
        if isEditingWallet { return (1, 1) }
        if usesWatchAddressesFlow {
            switch setupPage { case .details: return (1, 2); case .watchAddresses: return (2, 2); default: return (1, 2) }
        }
        if isCreateMode {
            switch setupPage {
            case .details: return (1, 4); case .seedPhrase: return (2, 4); case .password: return (3, 4)
            case .backupVerification: return (4, 4); case .advanced: return (1, 4); case .watchAddresses: return (1, 4)
            }
        }
        switch setupPage {
        case .details: return (1, 3); case .seedPhrase: return (2, 3); case .password: return (3, 3)
        case .advanced: return (1, 3); case .watchAddresses: return (1, 3); case .backupVerification: return (1, 3)
        }
    }
    @ViewBuilder
    private var initialPageSection: some View {
        if isShowingBackupVerificationPage {
            backupVerificationStepSection
        } else if !isEditingWallet && isShowingDetailsPage {
            chainSelectionCard
        }
    }
    @ViewBuilder
    private var chainSelectionCard: some View {
        setupCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Chains")).font(.headline).foregroundStyle(Color.primary)
                    }
                    Spacer()
                    Text(chainSelectionSummary).font(.caption.weight(.semibold)).foregroundStyle(
                        selectedChainCount == 0 ? Color.primary.opacity(0.68) : .orange
                    ).padding(.horizontal, 10).padding(.vertical, 6).background(
                        Capsule(style: .continuous).fill(
                            selectedChainCount == 0
                                ? Color.white.opacity(colorScheme == .light ? 0.55 : 0.08) : Color.orange.opacity(0.12))
                    )
                }
                LazyVGrid(columns: chainSelectionColumns, spacing: 10) {
                    ForEach(popularChainSelectionDescriptors) { descriptor in chainSelectionCard(descriptor) }
                }
                if !Self.nonPopularChainSelectionDescriptors.isEmpty {
                    Button {
                        chainSearchText = ""
                        isShowingAllChainsSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2").font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(
                                width: 26, height: 26
                            ).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppLocalization.string("See All Chains")).font(.subheadline.weight(.semibold)).foregroundStyle(
                                    Color.primary)
                                Text(AppLocalization.string("Browse the full chain list.")).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle()
                    }.buttonStyle(.plain)
                }
                Text(chainSelectionSubtitle).font(.caption).foregroundStyle(.secondary)
                chainSelectionFooterNote
            }.tint(.orange)
        }.sheet(isPresented: $isShowingAllChainsSheet) {
            AllChainsSelectionView(
                chainSearchText: $chainSearchText, descriptors: Self.sortedChainSelectionDescriptors,
                selectedChainNames: selectedChainNameSet, toggleSelection: draft.toggleChainSelection
            )
        }
    }
    @ViewBuilder
    private var chainSelectionFooterNote: some View {
        if isEditingWallet {
            Text(copy.watchOnlyFixedMessage).font(.caption).foregroundStyle(.secondary)
        } else if isWatchAddressesImportMode {
            Text(copy.publicAddressOnlyMessage).font(.caption).foregroundStyle(.secondary)
        } else if draft.wantsMonero {
            Text(copy.moneroWatchUnsupportedMessage).font(.caption).foregroundStyle(.orange.opacity(0.9))
        }
    }
    @ViewBuilder
    private var watchAddressesPageSection: some View {
        if isShowingWatchAddressesPage, !isEditingWallet, draft.isWatchOnlyMode {
            setupCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(copy.addressesToWatchTitle).font(.headline).foregroundStyle(Color.primary)
                    Text(copy.addressesToWatchSubtitle).font(.subheadline).foregroundStyle(.secondary)
                    watchAddressesInputsGroup
                    watchAddressesEmptyNote
                }
            }
        }
    }
    @ViewBuilder
    private var watchAddressesInputsGroup: some View {
        Group {
            watchAddressBitcoinSection
            conditionalWatchedAddressSection(
                condition: draft.wantsBitcoinCash, title: "Bitcoin Cash", text: $draft.bitcoinCashAddressInput,
                validator: { AddressValidation.isValid($0, kind: "bitcoinCash") })
            conditionalWatchedAddressSection(
                condition: draft.wantsBitcoinSV, title: "Bitcoin SV", text: $draft.bitcoinSvAddressInput,
                validator: { AddressValidation.isValid($0, kind: "bitcoinSV") })
            conditionalWatchedAddressSection(
                condition: draft.wantsDogecoin, title: "Dogecoin", text: $draft.dogecoinAddressInput,
                validator: { AddressValidation.isValid($0, kind: "dogecoin", networkMode: store.dogecoinNetworkMode.rawValue) })
            conditionalWatchedAddressSection(
                condition: draft.wantsLitecoin, title: "Litecoin", text: $draft.litecoinAddressInput,
                validator: { AddressValidation.isValid($0, kind: "litecoin") })
            watchAddressEvmSection
            conditionalWatchedAddressSection(
                condition: draft.wantsTron, title: "Tron", text: $draft.tronAddressInput,
                validator: { AddressValidation.isValid($0, kind: "tron") })
            conditionalWatchedAddressSection(
                condition: draft.wantsSolana, title: "Solana", text: $draft.solanaAddressInput,
                validator: { AddressValidation.isValid($0, kind: "solana") })
            conditionalWatchedAddressSection(
                condition: draft.wantsXRP, title: "XRP Ledger", text: $draft.xrpAddressInput,
                validator: { AddressValidation.isValid($0, kind: "xrp") })
        }
        Group {
            conditionalWatchedAddressSection(
                condition: draft.wantsMonero, title: "Monero", text: $draft.moneroAddressInput)
            conditionalWatchedAddressSection(
                condition: draft.wantsCardano, title: "Cardano", text: $draft.cardanoAddressInput,
                validator: { AddressValidation.isValid($0, kind: "cardano") })
            conditionalWatchedAddressSection(
                condition: draft.wantsSui, title: "Sui", text: $draft.suiAddressInput,
                validator: { AddressValidation.isValid($0, kind: "sui") })
            conditionalWatchedAddressSection(
                condition: draft.wantsAptos, title: "Aptos", text: $draft.aptosAddressInput,
                validator: { AddressValidation.isValid($0, kind: "aptos") })
            conditionalWatchedAddressSection(
                condition: draft.wantsTON, title: "TON", text: $draft.tonAddressInput,
                validator: { AddressValidation.isValid($0, kind: "ton") })
            conditionalWatchedAddressSection(
                condition: draft.wantsICP, title: "Internet Computer", text: $draft.icpAddressInput,
                validator: { AddressValidation.isValid($0, kind: "internetComputer") })
            conditionalWatchedAddressSection(
                condition: draft.wantsNear, title: "NEAR", text: $draft.nearAddressInput,
                validator: { AddressValidation.isValid($0, kind: "near") })
            conditionalWatchedAddressSection(
                condition: draft.wantsPolkadot, title: "Polkadot", text: $draft.polkadotAddressInput,
                validator: { AddressValidation.isValid($0, kind: "polkadot") })
            conditionalWatchedAddressSection(
                condition: draft.wantsStellar, title: "Stellar", text: $draft.stellarAddressInput,
                validator: { AddressValidation.isValid($0, kind: "stellar") })
        }
    }
    @ViewBuilder
    private var watchAddressBitcoinSection: some View {
        if draft.wantsBitcoin {
            let bitcoinAddressEntries = draft.watchOnlyEntries(from: draft.bitcoinAddressInput)
            let bitcoinValidation = watchedAddressValidationMessage(
                entries: bitcoinAddressEntries, assetName: "Bitcoin",
                validator: { AddressValidation.isValid($0, kind: "bitcoin", networkMode: store.bitcoinNetworkMode.rawValue) }
            )
            watchedAddressSection(
                title: "Bitcoin", text: $draft.bitcoinAddressInput, caption: copy.bitcoinWatchCaption,
                validationMessage: bitcoinValidation.message, validationColor: bitcoinValidation.color
            )
            TextField("xpub... / zpub...", text: $draft.bitcoinXpubInput).textInputAutocapitalization(.never)
                .autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
        }
    }
    @ViewBuilder
    private var watchAddressEvmSection: some View {
        if draft.wantsEthereum || draft.wantsEthereumClassic || draft.wantsArbitrum || draft.wantsOptimism
            || draft.wantsBNBChain || draft.wantsAvalanche || draft.wantsHyperliquid
        {
            let ethereumAddressEntries = draft.watchOnlyEntries(from: draft.ethereumAddressInput)
            let evmValidation = watchedAddressValidationMessage(
                entries: ethereumAddressEntries, assetName: "EVM",
                validator: { AddressValidation.isValid($0, kind: "evm") }
            )
            watchedAddressSection(
                title: "EVM (Ethereum / ETC / Arbitrum / Optimism / BNB Chain / Avalanche / Hyperliquid)",
                text: $draft.ethereumAddressInput, validationMessage: evmValidation.message,
                validationColor: evmValidation.color
            )
        }
    }
    @ViewBuilder
    private var watchAddressesEmptyNote: some View {
        if !draft.wantsBitcoin && !draft.wantsBitcoinCash && !draft.wantsBitcoinSV && !draft.wantsLitecoin
            && !draft.wantsDogecoin && !draft.wantsEthereum && !draft.wantsEthereumClassic && !draft.wantsSolana
            && !draft.wantsBNBChain && !draft.wantsTron && !draft.wantsXRP && !draft.wantsMonero
            && !draft.wantsCardano && !draft.wantsSui && !draft.wantsAptos && !draft.wantsTON && !draft.wantsICP
            && !draft.wantsNear && !draft.wantsPolkadot && !draft.wantsStellar
        {
            Text(AppLocalization.string("Select a supported chain above to enter its address to watch.")).font(.caption)
                .foregroundStyle(.orange.opacity(0.9))
        }
    }
    @ViewBuilder
    private var walletNamePageSection: some View {
        if isShowingDetailsPage || isEditingWallet {
            setupCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        isEditingWallet
                            ? AppLocalization.string("import_flow.wallet_name")
                            : AppLocalization.string("import_flow.wallet_name_optional")
                    ).font(.headline).foregroundStyle(Color.primary)
                    if !isEditingWallet {
                        Text(AppLocalization.string("import_flow.wallet_name_hint")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        TextField(AppLocalization.string("import_flow.wallet_name_placeholder"), text: $draft.walletName)
                            .textInputAutocapitalization(.words).autocorrectionDisabled().foregroundStyle(Color.primary)
                        if isEditingWallet && !draft.walletName.isEmpty {
                            Button { draft.walletName = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }.buttonStyle(.plain).accessibilityLabel("Clear wallet name")
                        }
                    }.padding(14).spectraInputFieldStyle()
                }
            }
        }
    }
    @ViewBuilder
    private var seedPhrasePageSection: some View {
        if isShowingSeedPhrasePage && !draft.isWatchOnlyMode {
            setupCard {
                VStack(alignment: .leading, spacing: 14) { walletSecretStepSection }
            }
        }
    }
    @ViewBuilder
    private var passwordPageSection: some View {
        if isShowingPasswordPage {
            setupCard { walletPasswordStepSection }
        }
    }
    @ViewBuilder
    private var advancedPageSection: some View {
        if isShowingAdvancedPage {
            setupCard { derivationAdvancedContent }
        }
    }
    @ViewBuilder
    private var importStatusSection: some View {
        if let importError = store.importError {
            Text(importError).font(.footnote).foregroundStyle(.red.opacity(0.9))
        }
        if store.isImportingWallet {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(AppLocalization.string("import_flow.initializing_wallet_connections")).font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder
    private var primaryActionButton: some View {
        if !isShowingAdvancedPage {
            Button(action: performPrimaryAction) {
                HStack {
                    Text(primaryActionTitle).font(.headline)
                    Spacer()
                }.foregroundStyle(Color.primary).padding().frame(maxWidth: .infinity)
            }.buttonStyle(.glassProminent).disabled(!isPrimaryActionEnabled).opacity(isPrimaryActionEnabled ? 1.0 : 0.55)
        }
    }
    private func performPrimaryAction() {
        if isShowingDetailsPage && usesWatchAddressesFlow {
            withAnimation { setupPage = .watchAddresses }
            return
        }
        if isShowingDetailsPage && usesSeedPhraseFlow {
            withAnimation { setupPage = .seedPhrase }
            return
        }
        if isShowingSeedPhrasePage {
            withAnimation { setupPage = .password }
            return
        }
        if isShowingPasswordPage && isCreateMode {
            draft.prepareBackupVerificationChallenge()
            withAnimation { setupPage = .backupVerification }
            return
        }
        Task { await store.importWallet() }
    }
    @ViewBuilder
    private var navigationBackButton: some View {
        if isShowingSeedPhrasePage || isShowingWatchAddressesPage {
            navigationBackButtonStyled(titleKey: "import_flow.back", target: .details)
        } else if isShowingDetailsPage && !isEditingWallet {
            // Details is now the first in-SetupView page; going "back" returns
            // to the Add-Wallet entry screen where the simple/advanced + flow
            // selection lives.
            Button(AppLocalization.string("import_flow.back")) {
                store.isShowingWalletImporter = false
            }.buttonStyle(.glass)
        } else if isShowingAdvancedPage {
            navigationBackButtonStyled(titleKey: "import_flow.back", target: .seedPhrase)
        } else if isShowingPasswordPage {
            navigationBackButtonStyled(titleKey: "import_flow.back", target: .seedPhrase)
        } else if isShowingBackupVerificationPage {
            navigationBackButtonStyled(titleKey: "import_flow.back_to_wallet_password", target: .password)
        }
    }
    private func navigationBackButtonStyled(titleKey: String, target: SetupPage) -> some View {
        Button(AppLocalization.string(titleKey)) {
            withAnimation { setupPage = target }
        }.buttonStyle(.glass)
    }
    @ViewBuilder
    private var derivationAdvancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(advancedDescriptionText).font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                if hasBitcoinSelection { bitcoinNetworkAdvancedSection }
                if hasEthereumSelection { ethereumNetworkAdvancedSection }
                if hasDogecoinSelection { dogecoinNetworkAdvancedSection }
                ForEach(draft.selectableDerivationChains) { chain in
                    SeedPathSlotEditor(
                        title: chain.rawValue,
                        path: Binding(
                            get: { draft.seedDerivationPaths.path(for: chain) }, set: { draft.seedDerivationPaths.setPath($0, for: chain) }
                        ), defaultPath: chain.defaultPath, presetOptions: chain.presetOptions
                    )
                }
                powerUserOverridesSection
            }
        }
    }
    private var powerUserOverridesSection: some View {
        PowerUserOverridesSection(draft: draft)
    }
    private var advancedDescriptionText: String {
        if hasBitcoinSelection && hasEthereumSelection && hasDogecoinSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Bitcoin, Ethereum, and Dogecoin networks when needed."
            )
        }
        if hasBitcoinSelection && hasEthereumSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Bitcoin and Ethereum networks when needed.")
        }
        if hasBitcoinSelection && hasDogecoinSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Bitcoin and Dogecoin networks when needed.")
        }
        if hasEthereumSelection && hasDogecoinSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Ethereum and Dogecoin networks when needed.")
        }
        if hasBitcoinSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Bitcoin network when needed.")
        }
        if hasEthereumSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Ethereum network when needed.")
        }
        if hasDogecoinSelection {
            return AppLocalization.string(
                "Control the derivation path used for each selected chain and choose the Dogecoin network when needed.")
        }
        return AppLocalization.string("Control the derivation path used for each selected chain.")
    }
    private var bitcoinNetworkAdvancedSection: some View {
        networkModePicker(
            title: AppLocalization.string("Bitcoin Network"), accentColor: .orange,
            caption: AppLocalization.string(
                "This controls Bitcoin wallet import, address validation, and endpoint usage for Bitcoin wallets."),
            modeOptions: BitcoinNetworkMode.allCases.map { ($0.rawValue, $0.displayName) },
            currentModeID: store.bitcoinNetworkMode.rawValue,
            selectMode: { store.bitcoinNetworkMode = BitcoinNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private var ethereumNetworkAdvancedSection: some View {
        networkModePicker(
            title: AppLocalization.string("Ethereum Network"), accentColor: .blue,
            caption: AppLocalization.string(
                "This controls Ethereum wallet import, balance refresh, history, and endpoint usage for Ethereum wallets."),
            modeOptions: EthereumNetworkMode.allCases.map { ($0.rawValue, $0.displayName) },
            currentModeID: store.ethereumNetworkMode.rawValue,
            selectMode: { store.ethereumNetworkMode = EthereumNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private var dogecoinNetworkAdvancedSection: some View {
        networkModePicker(
            title: AppLocalization.string("Dogecoin Network"), accentColor: .yellow, accentForeground: .yellow.opacity(0.9),
            caption: AppLocalization.string(
                "This controls Dogecoin wallet import, address validation, history, and endpoint usage for Dogecoin wallets."),
            modeOptions: DogecoinNetworkMode.allCases.map { ($0.rawValue, $0.displayName) },
            currentModeID: store.dogecoinNetworkMode.rawValue,
            selectMode: { store.dogecoinNetworkMode = DogecoinNetworkMode(rawValue: $0) ?? .mainnet }
        )
    }
    private func networkModePicker(
        title: String, accentColor: Color, accentForeground: Color? = nil, caption: String,
        modeOptions: [(id: String, displayName: String)], currentModeID: String, selectMode: @escaping (String) -> Void
    ) -> some View {
        let fg = accentForeground ?? accentColor
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(modeOptions, id: \.id) { mode in
                    let isSelected = currentModeID == mode.id
                    Button {
                        selectMode(mode.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(mode.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? fg : Color.primary)
                            Spacer(minLength: 0)
                            if isSelected { Image(systemName: "checkmark.circle.fill").font(.caption.weight(.bold)).foregroundStyle(fg) }
                        }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                                isSelected ? accentColor.opacity(0.12) : Color.white.opacity(colorScheme == .light ? 0.78 : 0.05))
                        ).overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                                isSelected ? accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }.buttonStyle(.plain)
                }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var derivationAdvancedButton: some View {
        if !isEditingWallet && !draft.selectedChainNames.isEmpty {
            Button {
                withAnimation {
                    setupPage = .advanced
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(
                        width: 26, height: 26
                    ).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("Advanced")).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                        Text(advancedButtonSubtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle()
            }.buttonStyle(.plain)
        }
    }
    private var advancedButtonSubtitle: String {
        if hasBitcoinSelection && hasEthereumSelection && hasDogecoinSelection {
            return AppLocalization.string("Adjust derivation paths plus Bitcoin, Ethereum, and Dogecoin networks.")
        }
        if hasBitcoinSelection && hasEthereumSelection {
            return AppLocalization.string("Adjust derivation paths plus Bitcoin and Ethereum networks.")
        }
        if hasBitcoinSelection && hasDogecoinSelection {
            return AppLocalization.string("Adjust derivation paths plus Bitcoin and Dogecoin networks.")
        }
        if hasEthereumSelection && hasDogecoinSelection {
            return AppLocalization.string("Adjust derivation paths plus Ethereum and Dogecoin networks.")
        }
        if hasBitcoinSelection { return AppLocalization.string("Adjust derivation paths and Bitcoin network.") }
        if hasEthereumSelection { return AppLocalization.string("Adjust derivation paths and Ethereum network.") }
        if hasDogecoinSelection { return AppLocalization.string("Adjust derivation paths and Dogecoin network.") }
        return AppLocalization.string("Adjust derivation paths.")
    }
    @ViewBuilder
    private var importSecretModePicker: some View {
        if !isEditingWallet && !isCreateMode && !draft.isWatchOnlyMode {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedWalletFlowString("Import Method")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Import Method", selection: importSecretModeBinding) {
                    ForEach(WalletSecretImportMode.allCases) { mode in Text(mode.localizedTitle).tag(mode) }
                }.pickerStyle(.segmented)
                Text(
                    draft.secretImportMode == .seedPhrase
                        ? copy.seedImportMethodDescription
                        : copy.privateKeyImportMethodDescription
                ).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var importSecretModeBinding: Binding<WalletSecretImportMode> {
        Binding(
            get: { draft.secretImportMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    draft.secretImportMode = newValue
                }
            }
        )
    }
    @ViewBuilder
    private var newWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(title: copy.importSeedLengthTitle, subtitle: copy.importSeedLengthSubtitle)
        Text(copy.seedPhraseEntryHelp).font(.footnote).foregroundStyle(.secondary)
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(0..<draft.selectedSeedPhraseWordCount, id: \.self) { index in seedPhraseField(at: index) }
        }
        if !seedPhraseStatusText.isEmpty { Text(seedPhraseStatusText).font(.footnote).foregroundStyle(seedPhraseStatusColor) }
    }
    @ViewBuilder
    private var createWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.createSeedLengthTitle, subtitle: copy.createSeedLengthSubtitle, showsRegenerateButton: true
        )
        Text(copy.createSeedPhraseWarning).font(.footnote).foregroundStyle(.secondary)
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 12) {
            ForEach(draft.seedPhraseWords.indices, id: \.self) { index in
                numberedSeedPhraseRow(index: index, text: draft.seedPhraseWords[index])
            }
        }
    }
    @ViewBuilder
    private var privateKeyImportSection: some View {
        importSecretModePicker
        privateKeyImportFields
    }
    @ViewBuilder
    private var privateKeyImportFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.privateKeyTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(copy.privateKeyPrompt).font(.footnote).foregroundStyle(.secondary)
            TextField(copy.privateKeyPlaceholder, text: $draft.privateKeyInput).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
            if !draft.unsupportedPrivateKeyChainNames.isEmpty {
                Text(
                    walletFlowLocalizedFormat(
                        "Private key import is not available for: %@.", draft.unsupportedPrivateKeyChainNames.joined(separator: ", "))
                ).font(.footnote).foregroundStyle(.orange.opacity(0.9))
            } else if !draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !CachedCoreHelpers.privateKeyHexIsLikely(rawValue: draft.privateKeyInput)
            {
                Text(AppLocalization.string("Enter a valid 32-byte hex private key.")).font(.footnote).foregroundStyle(.red.opacity(0.9))
            }
        }
    }
    @ViewBuilder
    private var walletSecretStepSection: some View {
        if isCreateMode {
            createWalletSeedPhraseSection
            if !isSimpleSetupSelected { derivationAdvancedButton }
        } else {
            importSecretModePicker
            Group {
                if isPrivateKeyImportMode {
                    privateKeyImportFields
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        newWalletSeedPhraseSection
                        if !isSimpleSetupSelected { derivationAdvancedButton }
                    }
                }
            }.id(draft.secretImportMode).transition(.opacity).animation(.easeInOut(duration: 0.2), value: draft.secretImportMode)
        }
    }
    @ViewBuilder
    private var backupVerificationStepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.backupVerificationTitle).font(.headline).foregroundStyle(Color.primary)
            if !draft.backupVerificationPromptLabel.isEmpty {
                Text(draft.backupVerificationPromptLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            if draft.backupVerificationWordIndices.isEmpty {
                Button(copy.backupVerificationButtonTitle) {
                    draft.prepareBackupVerificationChallenge()
                }.buttonStyle(.glass)
            } else {
                ForEach(draft.backupVerificationWordIndices.indices, id: \.self) { offset in
                    let wordIndex = draft.backupVerificationWordIndices[offset]
                    HStack(spacing: 10) {
                        Text(walletFlowLocalizedFormat("Word #%lld", wordIndex + 1)).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 88, alignment: .leading)
                        TextField("Enter word \(wordIndex + 1)", text: backupVerificationBinding(for: offset)).textInputAutocapitalization(
                            .never
                        ).autocorrectionDisabled().foregroundStyle(Color.primary)
                    }.padding(.horizontal, 12).padding(.vertical, 10).spectraInputFieldStyle(cornerRadius: 16)
                }
                if draft.isBackupVerificationComplete {
                    Text(copy.backupVerifiedMessage).font(.footnote).foregroundStyle(.green.opacity(0.9))
                } else {
                    Text(copy.backupVerificationHint).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                setupHeader
                VStack(alignment: .leading, spacing: 16) {
                    initialPageSection
                    watchAddressesPageSection
                    walletNamePageSection
                    seedPhrasePageSection
                    passwordPageSection
                    advancedPageSection
                    importStatusSection
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { setupToolbarBackButton }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                setupBottomActionBar
            }
            .onChange(of: draft.mode) { _, _ in
                setupPage = .details
            }.onChange(of: draft.selectedSeedPhraseWordCount) { _, newValue in
                customSeedPhraseWordCountInput = String(newValue)
            }
    }
    @ViewBuilder
    private var setupToolbarBackButton: some View {
        Button {
            performBackNavigation()
        } label: {
            Image(systemName: "chevron.backward").font(.body.weight(.semibold))
        }.accessibilityLabel(AppLocalization.string("import_flow.back"))
    }
    private func performBackNavigation() {
        if isShowingSeedPhrasePage || isShowingWatchAddressesPage {
            withAnimation { setupPage = .details }
        } else if isShowingDetailsPage && !isEditingWallet {
            store.isShowingWalletImporter = false
        } else if isShowingAdvancedPage || isShowingPasswordPage {
            withAnimation { setupPage = .seedPhrase }
        } else if isShowingBackupVerificationPage {
            withAnimation { setupPage = .password }
        } else {
            dismiss()
        }
    }
    @ViewBuilder
    private var setupBottomActionBar: some View {
        if !isShowingAdvancedPage {
            VStack(spacing: 0) {
                Divider().opacity(0.4)
                Button(action: performPrimaryAction) {
                    Text(primaryActionTitle)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }.buttonStyle(.glassProminent).controlSize(.large).disabled(!isPrimaryActionEnabled)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }.background(.ultraThinMaterial)
        }
    }
}
/// Standalone `View` struct for the Advanced-mode power-user overrides section.
/// Kept out of `SetupView` so its internal `TupleView` type doesn't cascade
/// into `SetupView.body`'s opaque return type — that cascade is what was
/// blowing the SwiftUI render stack.
private struct PowerUserOverridesSection: View {
    @Bindable var draft: WalletImportDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            stage1Overrides
            stage2Overrides
        }.padding(14).background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.08))
        ).overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(AppLocalization.string("Power-User Overrides"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(
                AppLocalization.string(
                    "These fields override chain-preset derivation defaults. Incompatible combinations (e.g., ed25519 algorithm on a secp256k1 chain) will fail at import. Leave blank to use the chain default."
                )
            ).font(.caption).foregroundStyle(.orange.opacity(0.9))
        }
    }
    private var stage1Overrides: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdvancedOverrideTextField(
                title: AppLocalization.string("Passphrase"),
                detail: AppLocalization.string("BIP-39 passphrase (\"25th word\"). Blank = none."),
                text: $draft.overridePassphrase, isSecure: true)
            AdvancedOverrideTextField(
                title: AppLocalization.string("Mnemonic Wordlist"),
                detail: AppLocalization.string(
                    "e.g. english, chinese_simplified, french, japanese, spanish. Blank = english."),
                text: $draft.overrideMnemonicWordlist)
            AdvancedOverrideTextField(
                title: AppLocalization.string("PBKDF2 Iteration Count"),
                detail: AppLocalization.string("BIP-39 PBKDF2 rounds. Blank = 2048 (standard)."),
                text: $draft.overrideIterationCount, keyboard: .numberPad)
            AdvancedOverrideTextField(
                title: AppLocalization.string("Salt Prefix"),
                detail: AppLocalization.string(
                    "BIP-39 seed-derivation salt prefix. Blank = \"mnemonic\" (standard)."),
                text: $draft.overrideSaltPrefix)
            AdvancedOverrideTextField(
                title: AppLocalization.string("HMAC Master Key"),
                detail: AppLocalization.string(
                    "BIP-32 master HMAC key string. Blank = \"Bitcoin seed\" (standard)."),
                text: $draft.overrideHmacKey)
        }
    }
    private var stage2Overrides: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdvancedOverridePicker(
                title: AppLocalization.string("Curve"),
                detail: AppLocalization.string("Override signing curve."),
                selection: $draft.overrideCurve,
                options: ["secp256k1", "ed25519", "sr25519"])
            AdvancedOverridePicker(
                title: AppLocalization.string("Derivation Algorithm"),
                detail: AppLocalization.string("Override the seed→child-key algorithm."),
                selection: $draft.overrideDerivationAlgorithm,
                options: [
                    "bip32_secp256k1", "slip10_ed25519", "direct_seed_ed25519",
                    "ton_mnemonic", "bip32_ed25519_icarus", "substrate_bip39", "monero_bip39",
                ])
            AdvancedOverridePicker(
                title: AppLocalization.string("Address Algorithm"),
                detail: AppLocalization.string("Override the key→address encoding."),
                selection: $draft.overrideAddressAlgorithm,
                options: [
                    "bitcoin", "evm", "solana", "near_hex", "ton_raw_account_id",
                    "cardano_shelley_enterprise", "ss58", "monero_main", "ton_v4r2",
                    "litecoin", "dogecoin", "bitcoin_cash_legacy", "bitcoin_sv_legacy",
                    "tron_base58_check", "xrp_base58_check", "stellar_strkey",
                    "sui_keccak", "aptos_keccak", "icp_principal",
                ])
            AdvancedOverridePicker(
                title: AppLocalization.string("Public Key Format"),
                detail: AppLocalization.string("Override the public-key encoding format."),
                selection: $draft.overridePublicKeyFormat,
                options: ["compressed", "uncompressed", "x_only", "raw"])
            AdvancedOverridePicker(
                title: AppLocalization.string("Script Type"),
                detail: AppLocalization.string(
                    "UTXO script type (Bitcoin only) or \"account\" for account-model chains."),
                selection: $draft.overrideScriptType,
                options: ["p2pkh", "p2sh_p2wpkh", "p2wpkh", "p2tr", "account"])
        }
    }
}

private struct AdvancedOverrideTextField: View {
    let title: String
    let detail: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            inputField.font(.subheadline.monospaced()).padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var inputField: some View {
        if isSecure {
            SecureField(AppLocalization.string("(default)"), text: $text)
        } else {
            TextField(AppLocalization.string("(default)"), text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(keyboard)
        }
    }
}

private struct AdvancedOverridePicker: View {
    let title: String
    let detail: String
    @Binding var selection: String
    let options: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Menu {
                Button(AppLocalization.string("(default)")) { selection = "" }
                ForEach(options, id: \.self) { option in
                    Button(option) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection.isEmpty ? AppLocalization.string("(default)") : selection)
                        .font(.subheadline.monospaced()).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }.buttonStyle(.plain)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
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
        }
    }
    private var isSearching: Bool { !chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @ViewBuilder
    private func row(for descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainNames.contains(descriptor.chainName)
        Button {
            toggleSelection(descriptor.chainName)
        } label: {
            HStack(spacing: 12) {
                CoinBadge(
                    assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol, color: descriptor.color, size: 28
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                    Text(descriptor.symbol.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(
                        isSelected ? descriptor.color : Color.primary.opacity(0.56))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.body.weight(.semibold)).foregroundStyle(
                    isSelected ? descriptor.color : Color.primary.opacity(0.24))
            }.padding(.horizontal, 12).padding(.vertical, 8).background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? descriptor.color.opacity(0.1) : Color.clear)
            )
        }.buttonStyle(.plain)
    }
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField(AppLocalization.string("import_flow.search_chains"), text: $chainSearchText)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            }.padding(.horizontal, 14).padding(.vertical, 12).spectraInputFieldStyle()
                            if filteredDescriptors.isEmpty {
                                Text(AppLocalization.string("import_flow.no_chains_match")).font(.caption).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(filteredDescriptors) { descriptor in row(for: descriptor) }
                                }
                            }
                        }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
                    }.padding(.horizontal, 20).padding(.vertical, 20)
                }
            }.navigationTitle(AppLocalization.string("import_flow.all_chains_title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("import_flow.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
