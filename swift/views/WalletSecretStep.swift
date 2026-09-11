import SwiftUI

/// The wallet-setup secret step: recording or entering a seed phrase, pasting
/// a private key, and verifying a recorded backup.
///
/// Split out of `SetupView`, which was a single 1000-line struct covering
/// every page of the flow. This section owns the state only it uses — the
/// focused word slot and the custom-length field — so neither travels with
/// the rest of the wizard any more, and a keystroke in a seed slot no longer
/// invalidates the chain grid and the button bar along with it.
struct WalletSecretStep: View {
    let store: AppState
    @Bindable var draft: WalletImportDraft
    /// `true` renders the backup-verification page instead of the secret page.
    let showsBackupVerification: Bool
    /// Opens the advanced derivation page, which the flow — not this step —
    /// owns the routing for.
    let onOpenAdvanced: () -> Void

    private let copy = ImportFlowContent.current
    @FocusState private var focusedSeedPhraseIndex: Int?
    @State private var customSeedPhraseWordCountInput: String

    @MainActor
    init(
        store: AppState, draft: WalletImportDraft, showsBackupVerification: Bool,
        onOpenAdvanced: @escaping () -> Void
    ) {
        self.store = store
        self.draft = draft
        self.showsBackupVerification = showsBackupVerification
        self.onOpenAdvanced = onOpenAdvanced
        _customSeedPhraseWordCountInput = State(initialValue: String(draft.selectedSeedPhraseWordCount))
    }

    private var isCreateMode: Bool { draft.isCreateMode }
    private var isEditingWallet: Bool { draft.isEditingWallet }
    private var isSimpleSetupSelected: Bool { draft.setupModeChoice == .simple }
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6),
    ]
    private var isPrivateKeyImportMode: Bool { draft.isPrivateKeyImportMode }
    private var canContinueFromSecretStep: Bool {
        walletSetupCanContinueFromSecretStep(draft: draft, isImporting: store.isImportingWallet)
    }

    var body: some View {
        Group {
            if showsBackupVerification {
                backupVerificationStepSection
            } else {
                VStack(alignment: .leading, spacing: 14) { walletSecretStepSection }
            }
        }
        .onChange(of: draft.selectedSeedPhraseWordCount) { _, newValue in
            customSeedPhraseWordCountInput = String(newValue)
        }
    }

    private var seedPhraseStatusText: String {
        let verdict = draft.seedPhraseVerdict
        if verdict.words.isEmpty { return "" }
        if !verdict.invalidWords.isEmpty {
            return AppLocalization.format("import_flow.seed_phrase_invalid_words_format", verdict.invalidWords.joined(separator: ", "))
        }
        if verdict.words.count < draft.selectedSeedPhraseWordCount {
            return AppLocalization.format(
                "import_flow.seed_phrase_progress_format", verdict.words.count, draft.selectedSeedPhraseWordCount)
        }
        if let error = verdict.error { return error }
        return AppLocalization.string("import_flow.seed_phrase_valid_status")
    }
    private var seedPhraseStatusColor: Color {
        let verdict = draft.seedPhraseVerdict
        if verdict.words.count < draft.selectedSeedPhraseWordCount { return .secondary }
        if !verdict.invalidWords.isEmpty || verdict.error != nil { return .red.opacity(0.9) }
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
    @ViewBuilder
    private func seedPhraseField(at index: Int, invalidWords: Set<String>) -> some View {
        let entry = draft.seedPhraseEntry(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
        numberedSeedPhraseRow(index: index, isInvalidWord: invalidWords.contains(entry.lowercased()))
    }
    @ViewBuilder
    private func seedPhraseLengthPicker(title: String, subtitle: String, showsRegenerateButton: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedWalletFlowString(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(localizedWalletFlowString(subtitle)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if showsRegenerateButton {
                    Button {
                        draft.regenerateSeedPhrase()
                    } label: {
                        Label(AppLocalization.string("Regenerate"), systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                    }.buttonStyle(.glass).tint(.orange).disabled(![12, 15, 18, 21, 24].contains(draft.selectedSeedPhraseWordCount))
                }
            }
            HStack(spacing: 6) {
                ForEach([12, 15, 18, 21, 24], id: \.self) { wordCount in
                    seedPhraseLengthChip(wordCount: wordCount)
                }
            }
            seedPhraseCustomLengthField
            if let seedPhraseLengthWarning = draft.seedPhraseVerdict.lengthWarning {
                Label(seedPhraseLengthWarning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(
                    .orange.opacity(0.92))
            }
        }
    }
    @ViewBuilder
    private func seedPhraseLengthChip(wordCount: Int) -> some View {
        let isSelected = draft.selectedSeedPhraseWordCount == wordCount
        let entropyBits: Int = {
            switch wordCount {
            case 12: return 128
            case 15: return 160
            case 18: return 192
            case 21: return 224
            case 24: return 256
            default: return 0
            }
        }()
        Button {
            draft.selectedSeedPhraseWordCount = wordCount
            customSeedPhraseWordCountInput = String(wordCount)
        } label: {
            VStack(spacing: 2) {
                Text("\(wordCount)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(
                    isSelected ? Color.white : Color.primary)
                Text("\(entropyBits)b").font(.caption2.weight(.semibold)).foregroundStyle(
                    isSelected ? Color.white.opacity(0.8) : .secondary)
            }.frame(maxWidth: .infinity, minHeight: 56).spectraSelectableFill(isSelected: isSelected, accent: .orange, cornerRadius: SpectraLayout.Radius.pill)
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private var seedPhraseCustomLengthField: some View {
        let standardLengths = [12, 15, 18, 21, 24]
        let isCustomSelected = !standardLengths.contains(draft.selectedSeedPhraseWordCount)
        DisclosureGroup {
            HStack(spacing: 8) {
                TextField(localizedWalletFlowString("Custom word count"), text: $customSeedPhraseWordCountInput).keyboardType(.numberPad)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, 12).padding(.vertical, 10).frame(
                        maxWidth: .infinity, alignment: .leading
                    ).spectraInputFieldStyle()
                Button(AppLocalization.string("Apply")) {
                    draft.applyCustomSeedPhraseWordCount(customSeedPhraseWordCountInput)
                    customSeedPhraseWordCountInput = String(draft.selectedSeedPhraseWordCount)
                }.buttonStyle(.glass).tint(.orange)
            }.padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(AppLocalization.string("Custom length")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if isCustomSelected {
                    Text("\(draft.selectedSeedPhraseWordCount)").font(.caption.weight(.bold)).foregroundStyle(.orange).padding(
                        .horizontal, 8
                    ).padding(.vertical, 2).background(Capsule(style: .continuous).fill(Color.orange.opacity(0.14)))
                }
            }
        }.tint(.secondary)
    }
    private static let seedPhraseLanguageOptions: [(code: String, label: String)] = [
        ("en", "English"), ("cs", "Czech"), ("fr", "French"), ("it", "Italian"),
        ("ja", "Japanese"), ("ko", "Korean"), ("pt", "Portuguese"), ("es", "Spanish"),
        ("zh-cn", "Chinese (Simplified)"), ("zh-tw", "Chinese (Traditional)"),
    ]
    @ViewBuilder
    private var seedPhraseLanguagePicker: some View {
        let isNonEnglish = draft.seedPhraseLanguage != "en"
        HStack(spacing: 6) {
            Image(systemName: "globe").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Wordlist", selection: $draft.seedPhraseLanguage) {
                ForEach(Self.seedPhraseLanguageOptions, id: \.code) { option in
                    Text(option.label).tag(option.code)
                }
            }
            .pickerStyle(.menu)
            .font(.caption.weight(.semibold))
            .tint(.secondary)
            Spacer()
            if isNonEnglish {
                Text(draft.seedPhraseLanguage).font(.caption.weight(.bold)).foregroundStyle(.orange).padding(
                    .horizontal, 8
                ).padding(.vertical, 2).background(Capsule(style: .continuous).fill(Color.orange.opacity(0.14)))
            }
        }
    }
    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let isFocused = focusedSeedPhraseIndex == index
        let accentColor: Color = isInvalidWord ? Color.red.opacity(0.85) : Color.orange.opacity(0.7)
        HStack(spacing: 4) {
            Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing).monospacedDigit()
            if let text {
                Text(text).font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: seedPhraseBinding(for: index)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(isInvalidWord ? AnyShapeStyle(.red.opacity(0.95)) : AnyShapeStyle(.primary))
                    .focused($focusedSeedPhraseIndex, equals: index)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.control)
        .overlay(RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous)
            .stroke((isFocused || isInvalidWord) ? accentColor : Color.clear, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    @ViewBuilder
    private var importSecretModePicker: some View {
        if !isEditingWallet && !isCreateMode && !draft.isWatchOnlyMode {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedWalletFlowString("Import Method")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Import Method", selection: importSecretModeBinding) {
                    ForEach(WalletSecretImportMode.allCases) { mode in Text(mode.localizedTitle).tag(mode) }
                }.pickerStyle(.segmented)
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
        seedPhraseLanguagePicker
        Text(copy.seedPhraseEntryHelp).font(.footnote).foregroundStyle(.secondary)
        seedPhraseEntryHeader
        let invalidWords = Set(draft.seedPhraseVerdict.invalidWords)
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 6) {
            ForEach(0..<draft.selectedSeedPhraseWordCount, id: \.self) { index in
                seedPhraseField(at: index, invalidWords: invalidWords)
            }
        }
        if !seedPhraseStatusText.isEmpty { Text(seedPhraseStatusText).font(.footnote).foregroundStyle(seedPhraseStatusColor) }
    }
    @ViewBuilder
    private var createWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.createSeedLengthTitle, subtitle: copy.createSeedLengthSubtitle, showsRegenerateButton: true
        )
        Text(copy.createSeedPhraseWarning).font(.footnote).foregroundStyle(.secondary)
        seedPhraseDisplayHeader
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 6) {
            ForEach(draft.seedPhraseWords.indices, id: \.self) { index in
                numberedSeedPhraseRow(index: index, text: draft.seedPhraseWords[index])
            }
        }
    }
    @ViewBuilder
    private var seedPhraseEntryHeader: some View {
        let filled = draft.seedPhraseWords.count
        let total = draft.selectedSeedPhraseWordCount
        let verdict = draft.seedPhraseVerdict
        let isComplete = filled >= total && verdict.invalidWords.isEmpty && verdict.error == nil
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dashed").font(.caption.weight(.semibold))
                    .foregroundStyle(isComplete ? .green : .orange)
                Text("\(filled) / \(total)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(
                    isComplete ? .green : .orange)
            }.padding(.horizontal, 10).padding(.vertical, 6).background(
                Capsule(style: .continuous).fill((isComplete ? Color.green : Color.orange).opacity(0.12))
            )
            Spacer()
            Button {
                if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
                    draft.updateSeedPhraseEntry(at: 0, with: pasted)
                    focusedSeedPhraseIndex = nil
                }
            } label: {
                Label(AppLocalization.string("Paste"), systemImage: "doc.on.clipboard").font(.caption.weight(.semibold))
            }.buttonStyle(.glass).tint(.orange)
            if filled > 0 {
                Button(role: .destructive) {
                    for index in 0..<total { draft.updateSeedPhraseEntry(at: index, with: "") }
                    focusedSeedPhraseIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.body.weight(.semibold))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder
    private var seedPhraseDisplayHeader: some View {
        HStack(spacing: 10) {
            Label(AppLocalization.string("Recovery Phrase"), systemImage: "key.fill").font(.caption.weight(.semibold)).foregroundStyle(
                .orange
            ).padding(.horizontal, 10).padding(.vertical, 6).background(
                Capsule(style: .continuous).fill(Color.orange.opacity(0.12)))
            Spacer()
            Button {
                UIPasteboard.general.string = draft.seedPhraseWords.joined(separator: " ")
            } label: {
                Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc").font(.caption.weight(.semibold))
            }.buttonStyle(.glass).tint(.orange).disabled(draft.seedPhraseWords.isEmpty)
        }
    }
    @ViewBuilder
    private var privateKeyImportFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(copy.privateKeyTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
                        draft.privateKeyInput = pasted
                    }
                } label: {
                    Label(AppLocalization.string("Paste"), systemImage: "doc.on.clipboard").font(.caption.weight(.semibold))
                }.buttonStyle(.glass).tint(.orange)
            }
            Text(copy.privateKeyPrompt).font(.footnote).foregroundStyle(.secondary)
            privateKeyEditor
            privateKeyMetadataRow
            if !draft.unsupportedPrivateKeyChainNames.isEmpty {
                Text(
                    AppLocalization.format(
                        "Private key import is not available for: %@.", draft.unsupportedPrivateKeyChainNames.joined(separator: ", "))
                ).font(.footnote).foregroundStyle(.orange.opacity(0.9))
            } else if let validation = privateKeyValidationFeedback {
                Label(validation.message, systemImage: validation.icon).font(.footnote.weight(.medium)).foregroundStyle(validation.color)
            }
        }
    }
    @ViewBuilder
    private var privateKeyEditor: some View {
        let trimmed = draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLikelyValid = !trimmed.isEmpty && CachedCoreHelpers.privateKeyHexIsLikely(rawValue: draft.privateKeyInput)
        let isInvalidShape = !trimmed.isEmpty && !isLikelyValid
        let borderColor: Color? =
            isInvalidShape
            ? Color.red.opacity(0.85) : (isLikelyValid ? Color.green.opacity(0.55) : nil)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft.privateKeyInput).textInputAutocapitalization(.never).autocorrectionDisabled().scrollContentBackground(
                .hidden
            ).font(.system(.footnote, design: .monospaced)).foregroundStyle(Color.primary).frame(minHeight: 96).padding(.horizontal, 10)
                .padding(.vertical, 10).spectraInputFieldStyle(borderColor: borderColor)
            if trimmed.isEmpty {
                Text(copy.privateKeyPlaceholder).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary).padding(
                    .horizontal, 16
                ).padding(.vertical, 18).allowsHitTesting(false)
            }
        }
    }
    @ViewBuilder
    private var privateKeyMetadataRow: some View {
        let hexCount = draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).count
        HStack(spacing: 10) {
            Text(AppLocalization.string("32-byte hex (64 chars)")).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(hexCount) / 64").font(.caption2.monospacedDigit()).foregroundStyle(
                hexCount == 0 ? Color.secondary : (hexCount == 64 ? Color.green : Color.orange))
            if hexCount > 0 {
                Button(role: .destructive) { draft.privateKeyInput = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption.weight(.semibold))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
    private var privateKeyValidationFeedback: (message: String, icon: String, color: Color)? {
        let trimmed = draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !CachedCoreHelpers.privateKeyHexIsLikely(rawValue: draft.privateKeyInput) {
            return (
                AppLocalization.string("Enter a valid 32-byte hex private key."), "exclamationmark.triangle.fill",
                .red.opacity(0.92)
            )
        }
        return (AppLocalization.string("Looks like a valid private key."), "checkmark.seal.fill", .green.opacity(0.92))
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
                    HStack(spacing: 8) {
                        Text(AppLocalization.format("Word #%lld", wordIndex + 1)).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                        TextField("", text: backupVerificationBinding(for: offset)).textInputAutocapitalization(
                            .never
                        ).autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.primary)
                    }.padding(.horizontal, 10).padding(.vertical, 7).spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.pill)
                }
                if draft.isBackupVerificationComplete {
                    Text(copy.backupVerifiedMessage).font(.footnote).foregroundStyle(.green.opacity(0.9))
                } else {
                    Text(copy.backupVerificationHint).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.padding(16).spectraBubbleFill().spectraCardFill(cornerRadius: SpectraLayout.Radius.card)
    }
    @ViewBuilder
    private var derivationAdvancedButton: some View {
        if !isEditingWallet && !draft.selectedChainNames.isEmpty {
            Button {
                onOpenAdvanced()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(
                        width: 26, height: 26
                    ).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous))
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
        AppLocalization.string("Adjust derivation paths.")
    }
}
