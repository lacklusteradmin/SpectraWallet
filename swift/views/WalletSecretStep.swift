import SwiftUI

/// The wallet-setup secret step: enter or record a seed, paste a private key,
/// and verify a backup. Focus and custom-length state belong to this step.
struct WalletSecretStep: View {
    let store: AppState
    @Bindable var draft: WalletImportDraft
    /// `true` renders the backup-verification page instead of the secret page.
    let showsBackupVerification: Bool

    private let copy = ImportFlowContent.current
    @FocusState private var focusedSeedPhraseIndex: Int?
    @State private var customSeedPhraseWordCountInput: String
    @State private var isShowingDerivationOptions = false
    @ScaledMetric(relativeTo: .caption2) private var wordIndexWidth: CGFloat = 16

    @MainActor
    init(store: AppState, draft: WalletImportDraft, showsBackupVerification: Bool) {
        self.store = store
        self.draft = draft
        self.showsBackupVerification = showsBackupVerification
        _customSeedPhraseWordCountInput = State(initialValue: String(draft.selectedSeedPhraseWordCount))
    }

    private var isCreateMode: Bool { draft.isCreateMode }
    private var isEditingWallet: Bool { draft.isEditingWallet }
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: SpectraLayout.Space.xs), GridItem(.flexible(), spacing: SpectraLayout.Space.xs), GridItem(.flexible(), spacing: SpectraLayout.Space.xs),
    ]
    private var isPrivateKeyImportMode: Bool { draft.isPrivateKeyImportMode }
    private var canContinueFromSecretStep: Bool {
        draft.isSecretComplete && !store.walletImport.isBusy
    }

    var body: some View {
        Group {
            if showsBackupVerification {
                backupVerificationStepSection
            } else {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.m) { walletSecretStepSection }
            }
        }
        .onChange(of: draft.selectedSeedPhraseWordCount) { _, newValue in
            customSeedPhraseWordCountInput = String(newValue)
        }
        .sheet(isPresented: $isShowingDerivationOptions) {
            WalletDerivationOptionsView(store: store, draft: draft)
        }
    }

    /// The line under the grid: what core read the entry as, or what is
    /// wrong with it.
    private var seedPhraseStatus: (text: String, color: Color) {
        let verdict = draft.seedPhraseVerdict
        let languageName = verdict.language.map { AppLocalization.string($0.name) }
        if verdict.words.isEmpty {
            return (AppLocalization.string("import_flow.seed_phrase_detect_hint"), .secondary)
        }
        if !verdict.invalidWords.isEmpty {
            let words = verdict.invalidWords.joined(separator: ", ")
            guard let languageName else {
                return (AppLocalization.format("import_flow.seed_phrase_unknown_words_format", words), .red)
            }
            return (AppLocalization.format("import_flow.seed_phrase_off_list_format", languageName, words), .red)
        }
        if let error = verdict.error { return (error, .red) }
        if verdict.checksumValid, let languageName {
            return (AppLocalization.format("import_flow.seed_phrase_valid_format", languageName, Int(verdict.wordCount)), .green)
        }
        return (
            AppLocalization.format(
                "import_flow.seed_phrase_typing_format", languageName ?? "—", verdict.words.count, Int(verdict.wordCount)),
            .secondary
        )
    }
    private func seedPhraseBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { draft.seedPhraseEntry(at: index) },
            set: { newValue in
                let shouldAdvance = newValue.last?.isWhitespace == true
                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.updateSeedPhraseEntry(at: index, with: trimmedValue)
                guard shouldAdvance, !trimmedValue.isEmpty else { return }
                // A space in the last slot of an inferred length asks for more.
                if index + 1 == draft.seedPhraseEntries.count, draft.seedPhraseWordCountOverride == nil {
                    draft.addSeedPhraseSlots()
                }
                focusedSeedPhraseIndex = (index + 1) < draft.seedPhraseEntries.count ? (index + 1) : nil
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
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: SpectraLayout.Space.s) {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                    Text(AppLocalization.string(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(AppLocalization.string(subtitle)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if showsRegenerateButton {
                    Button {
                        draft.regenerateSeedPhrase()
                    } label: {
                        Label(AppLocalization.string("Regenerate"), systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                    }.buttonStyle(.glass).tint(.accentColor).disabled(!CoreReferenceTables.isStandardSeedPhraseLength(draft.selectedSeedPhraseWordCount))
                }
            }
            HStack(spacing: SpectraLayout.Space.xs) {
                ForEach(CoreReferenceTables.standardSeedPhraseLengths, id: \.wordCount) { length in
                    seedPhraseLengthChip(length)
                }
            }
            seedPhraseCustomLengthField
            if let seedPhraseLengthWarning = draft.seedPhraseVerdict.lengthWarning {
                Label(seedPhraseLengthWarning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(
                    .spectraWarning.opacity(0.92))
            }
        }
    }
    /// One chip per core-defined length, labelled with its entropy.
    @ViewBuilder
    private func seedPhraseLengthChip(_ length: SeedPhraseLength) -> some View {
        let wordCount = Int(length.wordCount)
        let isSelected = draft.selectedSeedPhraseWordCount == wordCount
        Button {
            draft.selectedSeedPhraseWordCount = wordCount
            customSeedPhraseWordCountInput = String(wordCount)
        } label: {
            VStack(spacing: SpectraLayout.Space.xxs) {
                Text("\(wordCount)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(
                    isSelected ? Color.white : Color.primary)
                Text("\(length.entropyBits)b").font(.caption2.weight(.semibold)).foregroundStyle(
                    isSelected ? Color.white.opacity(0.8) : .secondary)
            }.frame(maxWidth: .infinity, minHeight: 56).spectraSelectableFill(isSelected: isSelected, accent: .accentColor, cornerRadius: SpectraLayout.Radius.inner)
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private var seedPhraseCustomLengthField: some View {
        let isCustomSelected = !CoreReferenceTables.isStandardSeedPhraseLength(draft.selectedSeedPhraseWordCount)
        DisclosureGroup {
            HStack(spacing: SpectraLayout.Space.s) {
                TextField(AppLocalization.string("Custom word count"), text: $customSeedPhraseWordCountInput).keyboardType(.numberPad)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(.horizontal, SpectraLayout.Space.m).padding(.vertical, SpectraLayout.Space.s).frame(
                        maxWidth: .infinity, alignment: .leading
                    ).spectraInputFieldStyle()
                Button(AppLocalization.string("Apply")) {
                    draft.applyCustomSeedPhraseWordCount(customSeedPhraseWordCountInput)
                    customSeedPhraseWordCountInput = String(draft.selectedSeedPhraseWordCount)
                }.buttonStyle(.glass).tint(.accentColor)
            }.padding(.top, SpectraLayout.Space.xs)
        } label: {
            HStack(spacing: SpectraLayout.Space.xs) {
                Image(systemName: "slider.horizontal.3").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(AppLocalization.string("Custom length")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if isCustomSelected {
                    Text("\(draft.selectedSeedPhraseWordCount)").font(.caption.weight(.bold)).foregroundStyle(.tint).padding(
                        .horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xxs).background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.14)))
                }
            }
        }.tint(.secondary)
    }
    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let isFocused = focusedSeedPhraseIndex == index
        let accentColor: Color = isInvalidWord ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.7)
        HStack(spacing: SpectraLayout.Space.xs) {
            Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                .frame(width: wordIndexWidth, alignment: .trailing).monospacedDigit()
            if let text {
                Text(text).font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The default keyboard: a Japanese, Korean or Chinese wordlist
                // cannot be typed on an ASCII one.
                TextField("", text: seedPhraseBinding(for: index)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(isInvalidWord ? AnyShapeStyle(.red.opacity(0.95)) : AnyShapeStyle(.primary))
                    .focused($focusedSeedPhraseIndex, equals: index)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xs)
        .spectraInsetFill(cornerRadius: SpectraLayout.Radius.control)
        .overlay(RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous)
            .stroke((isFocused || isInvalidWord) ? accentColor : Color.clear, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    /// The entry: one field per slot, as many slots as core judges the
    /// phrase at, and what core made of it underneath.
    @ViewBuilder
    private var importSeedPhraseSection: some View {
        let verdict = draft.seedPhraseVerdict
        let invalidWords = Set(verdict.invalidWords)
        let status = seedPhraseStatus
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            seedPhraseEntryHeader
            LazyVGrid(columns: seedPhraseGridColumns, spacing: SpectraLayout.Space.xs) {
                ForEach(draft.seedPhraseEntries.indices, id: \.self) { index in
                    seedPhraseField(at: index, invalidWords: invalidWords)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: SpectraLayout.Space.s) {
                Text(status.text).font(.footnote).foregroundStyle(status.color)
                Spacer(minLength: SpectraLayout.Space.s)
                if draft.seedPhraseWordCountOverride == nil, draft.nextSeedPhraseSlotCount != nil {
                    Button(AppLocalization.string("More words"), systemImage: "plus") {
                        draft.addSeedPhraseSlots()
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(.tint)
                }
            }
        }
        .privacySensitive()
    }
    @ViewBuilder
    private var createWalletSeedPhraseSection: some View {
        seedPhraseLengthPicker(
            title: copy.createSeedLengthTitle, subtitle: copy.createSeedLengthSubtitle, showsRegenerateButton: true
        )
        Text(copy.createSeedPhraseWarning).font(.footnote).foregroundStyle(.secondary)
        seedPhraseDisplayHeader
        LazyVGrid(columns: seedPhraseGridColumns, spacing: SpectraLayout.Space.xs) {
            ForEach(draft.seedPhraseWords.indices, id: \.self) { index in
                numberedSeedPhraseRow(index: index, text: draft.seedPhraseWords[index])
            }
        }
    }
    @ViewBuilder
    private var seedPhraseEntryHeader: some View {
        let verdict = draft.seedPhraseVerdict
        let filled = verdict.words.count
        let isComplete = verdict.checksumValid
        HStack(spacing: SpectraLayout.Space.s) {
            Text("\(filled) / \(verdict.wordCount)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xs)
                .background(Capsule(style: .continuous).fill(isComplete ? Color.green.opacity(0.14) : SpectraLayout.insetFill))
            Spacer()
            // The system paste button reads the clipboard on the user's tap,
            // so iOS does not ask permission to paste.
            PasteButton(payloadType: String.self) { pasted in
                guard let text = pasted.first else { return }
                draft.pasteSeedPhrase(text)
                focusedSeedPhraseIndex = nil
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .tint(.accentColor)
            if filled > 0 {
                Button(AppLocalization.string("Clear"), systemImage: "xmark.circle.fill", role: .destructive) {
                    draft.clearSeedPhrase()
                    focusedSeedPhraseIndex = 0
                }
                .labelStyle(.iconOnly).font(.title3).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder
    private var seedPhraseDisplayHeader: some View {
        HStack(spacing: SpectraLayout.Space.s) {
            Label(AppLocalization.string("Recovery Phrase"), systemImage: "key.fill").font(.caption.weight(.semibold)).foregroundStyle(
                .tint
            ).padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xs).background(
                Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
            Spacer()
            Button {
                UIPasteboard.general.string = draft.seedPhraseWords.joined(separator: " ")
            } label: {
                Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc").font(.caption.weight(.semibold))
            }.buttonStyle(.glass).tint(.accentColor).disabled(draft.seedPhraseWords.isEmpty)
        }
    }
    @ViewBuilder
    private var privateKeyImportFields: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack(spacing: SpectraLayout.Space.s) {
                Text(copy.privateKeyTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                PasteButton(payloadType: String.self) { pasted in
                    guard let text = pasted.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    draft.privateKeyInput = text
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .tint(.accentColor)
            }
            Text(copy.privateKeyPrompt).font(.footnote).foregroundStyle(.secondary)
            privateKeyEditor
            privateKeyMetadataRow
            if let validation = privateKeyValidationFeedback {
                Label(validation.message, systemImage: validation.icon).font(.footnote.weight(.medium)).foregroundStyle(validation.color)
            }
        }
    }
    @ViewBuilder
    private var privateKeyEditor: some View {
        let trimmed = draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLikelyValid = !trimmed.isEmpty && isPrivateKeyHex(rawValue: draft.privateKeyInput)
        let isInvalidShape = !trimmed.isEmpty && !isLikelyValid
        let borderColor: Color? =
            isInvalidShape
            ? Color.red.opacity(0.85) : (isLikelyValid ? Color.green.opacity(0.55) : nil)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft.privateKeyInput).textInputAutocapitalization(.never).autocorrectionDisabled().scrollContentBackground(
                .hidden
            ).font(.system(.footnote, design: .monospaced)).foregroundStyle(Color.primary).frame(minHeight: 96).padding(.horizontal, SpectraLayout.Space.s)
                .padding(.vertical, SpectraLayout.Space.s).spectraInputFieldStyle(borderColor: borderColor)
            if trimmed.isEmpty {
                Text(copy.privateKeyPlaceholder).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary).padding(
                    .horizontal, SpectraLayout.Space.l).padding(.vertical, SpectraLayout.Space.l).allowsHitTesting(false)
            }
        }
    }
    @ViewBuilder
    private var privateKeyMetadataRow: some View {
        let hexCount = draft.privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).count
        HStack(spacing: SpectraLayout.Space.s) {
            Text(AppLocalization.string("32-byte hex (64 chars)")).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(hexCount) / 64").font(.caption2.monospacedDigit()).foregroundStyle(
                hexCount == 0 ? Color.secondary : (hexCount == 64 ? Color.green : Color.spectraWarning))
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
        if !isPrivateKeyHex(rawValue: draft.privateKeyInput) {
            return (
                AppLocalization.string("Enter a valid 32-byte hex private key."), "exclamationmark.triangle.fill",
                .red.opacity(0.92)
            )
        }
        return (AppLocalization.string("Looks like a valid private key."), "checkmark.seal.fill", .green.opacity(0.92))
    }
    /// Creating a wallet shows its phrase in one card. Importing a phrase
    /// shows the entry, then the one way into everything a default already
    /// answers; importing a private key shows the key.
    @ViewBuilder
    private var walletSecretStepSection: some View {
        if isCreateMode {
            VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                createWalletSeedPhraseSection
                derivationOptionsLink
            }
            .padding(SpectraLayout.Space.l).spectraBubbleFill().spectraCardFill()
        } else if isPrivateKeyImportMode {
            privateKeyImportFields
                .padding(SpectraLayout.Space.l).spectraBubbleFill().spectraCardFill()
        } else {
            importSeedPhraseSection
                .padding(SpectraLayout.Space.l).spectraBubbleFill().spectraCardFill()
            advancedCard
        }
    }
    @ViewBuilder
    private var backupVerificationStepSection: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
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
                    HStack(spacing: SpectraLayout.Space.s) {
                        Text(AppLocalization.format("Word #%lld", wordIndex + 1)).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                        TextField("", text: backupVerificationBinding(for: offset)).textInputAutocapitalization(
                            .never
                        ).autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.primary)
                    }.padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.s).spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.inner)
                }
                if draft.isBackupVerificationComplete {
                    Text(copy.backupVerifiedMessage).font(.footnote).foregroundStyle(.green.opacity(0.9))
                } else {
                    Text(copy.backupVerificationHint).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.padding(SpectraLayout.Space.l).spectraBubbleFill().spectraCardFill()
    }
    /// The derivation options the sheet has moved off their defaults, by
    /// name. The entry to the sheet is deliberately quiet, so it says when
    /// something behind it changes which addresses the seed derives.
    private var customizedDerivationOptionNames: [String] {
        var names: [String] = []
        if !isCreateMode, draft.seedPhraseWordCountOverride != nil { names.append(AppLocalization.string("Word Count")) }
        if !isCreateMode, draft.seedPhraseLanguage != nil { names.append(AppLocalization.string("Wordlist")) }
        let presetPaths = SeedDerivationPaths.forPreset(draft.seedDerivationPreset)
        if draft.selectableDerivationChains.contains(where: {
            draft.seedDerivationPaths.path(for: $0) != presetPaths.path(for: $0)
        }) {
            names.append(AppLocalization.string("Derivation Paths"))
        }
        if !draft.overridePassphrase.isEmpty { names.append(AppLocalization.string("Passphrase")) }
        if !draft.overrideHmacKey.isEmpty { names.append(AppLocalization.string("HMAC Master Key")) }
        return names
    }
    private var derivationOptionsSummary: String? {
        let names = customizedDerivationOptionNames
        guard !names.isEmpty else { return nil }
        let list = ListFormatter()
        list.locale = AppLocalization.locale
        return AppLocalization.format(
            "import_flow.advanced_customized_format", list.string(from: names) ?? names.joined(separator: ", "))
    }
    /// The import's Advanced entry, as a row in its own card. Says what is
    /// in effect when nothing was changed, and what was changed otherwise.
    private var advancedCard: some View {
        let summary = derivationOptionsSummary
        let verdict = draft.seedPhraseVerdict
        let inEffect: String =
            if verdict.checksumValid, let language = verdict.language {
                AppLocalization.format(
                    "import_flow.advanced_in_effect_format", Int(verdict.wordCount), AppLocalization.string(language.name))
            } else {
                AppLocalization.string("import_flow.advanced_seed_subtitle")
            }
        return Button {
            isShowingDerivationOptions = true
        } label: {
            HStack(spacing: SpectraLayout.Space.m) {
                Image(systemName: "slider.horizontal.3").font(.body.weight(.semibold))
                    .foregroundStyle(summary == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.spectraWarning))
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(copy.advancedTitle).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(summary ?? inEffect).font(.caption)
                        .foregroundStyle(summary == nil ? Color.secondary : .spectraWarning)
                }
                Spacer(minLength: SpectraLayout.Space.s)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .spectraRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .spectraCardFill()
    }
    private var derivationOptionsLink: some View {
        let summary = derivationOptionsSummary
        return Button {
            isShowingDerivationOptions = true
        } label: {
            HStack(spacing: SpectraLayout.Space.s) {
                Image(systemName: "slider.horizontal.3").font(.footnote.weight(.semibold))
                    .foregroundStyle(summary == nil ? Color.secondary : .spectraWarning)
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(copy.advancedTitle).font(.footnote.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(summary ?? copy.advancedSubtitle).font(.caption2)
                        .foregroundStyle(summary == nil ? Color.secondary : .spectraWarning)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }.padding(.vertical, SpectraLayout.Space.xs).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
