import SwiftUI
enum WalletDraftMode {
    case importExisting
    case createNew
    case editExisting
}
/// Mutation contract for `WalletImportDraft`:
///
///   * **Derived state is computed, not stored.** `selectedChains` and the
///     verdicts are read from the fields they depend on, so no field needs a
///     hook to keep them current and any field may be bound directly.
///   * **Fields with a `didSet` reshape other fields** — a created phrase's
///     length regenerates it, and an import's length override refits the
///     grid. An import's grid otherwise follows core's verdict as words land.
///     Chain selection goes through `toggleChainSelection`, which applies the
///     mode's one-chain rule.
@MainActor
@Observable
final class WalletImportDraft {

    var mode: WalletDraftMode = .importExisting
    var isEditingWallet: Bool { mode == .editExisting }
    var walletName: String = ""
    var seedPhrase: String = ""
    var walletPassword: String = ""
    var walletPasswordConfirmation: String = ""
    /// An import from a raw private key rather than a phrase. Chosen on the
    /// Add Wallet page, before the chains, because it decides which chains
    /// the import can use.
    var importsPrivateKey: Bool = false
    var privateKeyInput: String = ""
    var seedDerivationPreset: CoreSeedDerivationPreset = .standard
    var seedDerivationPaths: SeedDerivationPaths = .defaults
    // Power-user derivation overrides (Advanced Options sheet). Each field is
    // a user-entered string; blank/empty-picker means "use chain preset default".
    // These are converted to CoreWalletDerivationOverrides at import time via
    // `resolvedDerivationOverrides`.
    var overridePassphrase: String = ""
    var overrideHmacKey: String = ""
    /// The import's wordlist, from `seedPhraseLanguages()`, or `nil` for
    /// core to detect it from the words.
    var seedPhraseLanguage: String?
    /// The import's length, or `nil` for core to infer it from the words.
    /// Fixing it never cuts a longer entry short: core refuses the phrase.
    var seedPhraseWordCountOverride: Int? {
        didSet { fitSeedPhraseSlots(shrinking: true) }
    }
    /// One entry per slot of the grid. An import grows it to the length core
    /// judges the phrase at; creating a wallet sizes it to the phrase.
    var seedPhraseEntries: [String] = Array(repeating: "", count: 12)
    /// The length a created phrase is generated at.
    var selectedSeedPhraseWordCount: Int = 12 {
        didSet {
            resizeSeedPhraseEntries(to: selectedSeedPhraseWordCount)
        }
    }
    var isWatchOnlyMode: Bool = false
    /// The watch-only address text, keyed by chain.
    var watchOnlyInputsByChain: [Chain: String] = [:]
    /// Not an address, so not in the table above: Bitcoin's account xpub stands
    /// in for the whole account and plans one wallet rather than one per line.
    var bitcoinXpubInput: String = ""
    /// Every chain ticked, in the order ticked.
    var selectedChainsStorage: [Chain] = []
    var backupVerificationWordIndices: [Int] = []
    var backupVerificationEntries: [String] = []
    /// The chains the import uses: those ticked that this mode can use, all
    /// of them or only the first where the mode allows one — editing,
    /// watch-only and private-key imports.
    var selectedChains: [Chain] {
        let usable = selectedChainsStorage.filter(offers)
        return allowsMultipleChainSelection ? usable : Array(usable.prefix(1))
    }
    /// Whether this mode's chain picker lists `chain`: a private key derives
    /// an address on only some chains, and only some chains can be watched.
    func offers(_ chain: Chain) -> Bool {
        if isPrivateKeyImportMode { return chain.derivesFromPrivateKey }
        if isWatchOnlyMode { return chain.supportsWatchOnlyImport }
        return true
    }
    var isCreateMode: Bool { mode == .createNew }
    var isPrivateKeyImportMode: Bool { mode == .importExisting && !isWatchOnlyMode && importsPrivateKey }
    var allowsMultipleChainSelection: Bool { !isEditingWallet && !isWatchOnlyMode && !isPrivateKeyImportMode }
    func isSelected(_ chain: Chain) -> Bool { selectedChainsStorage.contains(chain) }
    /// Everything core has to say about the entry grid, decided in one pass.
    /// Edit mode resets the grid, so an empty entry answers "nothing to say"
    /// without a mode guard of its own.
    var seedPhraseVerdict: SeedPhraseVerdict {
        let wordCount = isCreateMode ? selectedSeedPhraseWordCount : seedPhraseWordCountOverride
        let check = SeedPhraseCheck(
            words: seedPhraseEntries, language: isCreateMode ? nil : seedPhraseLanguage,
            wordCount: wordCount.map(UInt32.init))
        // One render reads this several times; ask core once per grid.
        if let cached = seedPhraseVerdictCache, cached.check == check { return cached.verdict }
        let verdict = checkSeedPhrase(check: check)
        seedPhraseVerdictCache = (check, verdict)
        return verdict
    }
    /// The last grid core judged. Holds the words, so `reset` drops it.
    @ObservationIgnored private var seedPhraseVerdictCache: (check: SeedPhraseCheck, verdict: SeedPhraseVerdict)?
    /// The entry grid as words. `seedPhrase` is kept in sync with the grid,
    /// so this reads the same phrase either way.
    var seedPhraseWords: [String] { seedPhraseVerdict.words }
    /// The password as typed, or `nil` for an empty field: the one way to
    /// say "no password". Core owns what counts as a password — it ignores
    /// surrounding whitespace and refuses a blank one rather than storing the
    /// wallet unsealed — so this side does not reshape it.
    var walletPasswordInput: String? { walletPassword.isEmpty ? nil : walletPassword }
    var walletPasswordValidationError: String? {
        guard let reason = validateWalletPassword(password: walletPassword, confirmation: walletPasswordConfirmation) else { return nil }
        switch reason {
        case .tooShort: return AppLocalization.string("Wallet password must be at least 4 characters, or leave it blank.")
        case .confirmationMismatch: return AppLocalization.string("Wallet password confirmation does not match.")
        }
    }
    /// Core interprets exact secret input and refuses unsupported overrides.
    var resolvedDerivationOverrides: CoreWalletDerivationOverrides {
        parseWalletDerivationInput(input: WalletDerivationInput(
            passphrase: overridePassphrase, hmacKey: overrideHmacKey))
    }
    /// The selected chains, in catalog order rather than selection order.
    var selectableDerivationChains: [Chain] {
        let selected = Set(selectedChains)
        return Chain.all.filter(selected.contains)
    }
    func watchOnlyEntries(from rawValue: String) -> [String] {
        rawValue.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Watch-only entries keyed by chain identity. Empty when
    /// the draft is not in watch-only mode.
    var watchOnlyEntriesByChain: [Chain: [String]] {
        guard isWatchOnlyMode else { return [:] }
        return watchOnlyInputsByChain.mapValues(watchOnlyEntries(from:))
    }
    /// The watch-only inputs as core reads them, for the check and the import.
    var watchOnlyImportEntries: WalletImportWatchOnlyEntries {
        let trimmedXpub = bitcoinXpubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return WalletImportWatchOnlyEntries(
            byChainId: watchOnlyEntriesByChain,
            bitcoinXpub: isWatchOnlyMode && !trimmedXpub.isEmpty ? trimmedXpub : nil)
    }
    /// Form completeness is view state. Domain validation remains mandatory
    /// in core's import/rename operations even when a client skips this check.
    var canImportWallet: Bool {
        if isEditingWallet { return !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !selectedChains.isEmpty else { return false }
        if isWatchOnlyMode {
            return !watchOnlyEntriesByChain.values.flatMap { $0 }.isEmpty || watchOnlyImportEntries.bitcoinXpub != nil
        }
        return isSecretComplete && (!requiresBackupVerification || isBackupVerificationComplete)
    }
    /// Whether the secret step — a seed phrase or a private key — is complete
    /// enough to move on. The one definition both the step and the submit use;
    /// a private key's single-chain rule is the selection's own.
    var isSecretComplete: Bool {
        guard !selectedChains.isEmpty else { return false }
        if isPrivateKeyImportMode {
            return isPrivateKeyHex(rawValue: privateKeyInput)
        }
        return seedPhraseVerdict.checksumValid
    }
    var requiresBackupVerification: Bool { isCreateMode }
    var isBackupVerificationComplete: Bool {
        guard requiresBackupVerification else { return true }
        guard backupVerificationWordIndices.count == backupVerificationEntries.count, !backupVerificationWordIndices.isEmpty else {
            return false
        }
        let words = seedPhraseWords
        guard words.count == selectedSeedPhraseWordCount else { return false }
        for (offset, index) in backupVerificationWordIndices.enumerated() {
            guard words.indices.contains(index) else { return false }
            let expected = words[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let entered = backupVerificationEntries[offset].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if expected != entered { return false }
        }
        return true
    }
    var backupVerificationPromptLabel: String {
        guard requiresBackupVerification else { return "" }
        if backupVerificationWordIndices.isEmpty { return AppLocalization.string("Generate a backup verification challenge to continue.") }
        return ""
    }
    func configureForNewWallet() {
        mode = .importExisting
        reset()
    }
    func configureForPrivateKeyImport() {
        mode = .importExisting
        reset()
        importsPrivateKey = true
    }
    func configureForWatchAddressesImport() {
        mode = .importExisting
        reset()
        isWatchOnlyMode = true
    }
    func configureForCreatedWallet() {
        // Reset outside create mode: resetting the word count regenerates a
        // phrase in create mode, and this generates exactly one.
        mode = .importExisting
        reset()
        mode = .createNew
        regenerateSeedPhrase()
    }
    func configureForEditing(wallet: WalletView) {
        mode = .editExisting
        reset()
        walletName = wallet.name
    }
    func reset() {
        seedPhraseVerdictCache = nil
        walletName = ""
        seedPhrase = ""
        walletPassword = ""
        walletPasswordConfirmation = ""
        importsPrivateKey = false
        privateKeyInput = ""
        seedDerivationPreset = .standard
        seedDerivationPaths = .defaults
        overridePassphrase = ""
        overrideHmacKey = ""
        seedPhraseLanguage = nil
        seedPhraseWordCountOverride = nil
        seedPhraseEntries = Array(repeating: "", count: 12)
        selectedSeedPhraseWordCount = 12
        isWatchOnlyMode = false
        watchOnlyInputsByChain = [:]
        bitcoinXpubInput = ""
        selectedChainsStorage = []
        backupVerificationWordIndices = []
        backupVerificationEntries = []
    }
    func toggleChainSelection(_ chain: Chain) { setSelectedChain(chain, isEnabled: !isSelected(chain)) }
    private func setSelectedChain(_ chain: Chain, isEnabled: Bool) {
        if isEnabled {
            if allowsMultipleChainSelection {
                if !selectedChainsStorage.contains(chain) { selectedChainsStorage.append(chain) }
            } else {
                selectedChainsStorage = [chain]
            }
        } else {
            selectedChainsStorage.removeAll { $0 == chain }
        }
    }
    func regenerateSeedPhrase() {
        guard isCreateMode else { return }
        // Core rejects lengths BIP-39 does not define rather than substituting one.
        guard let generatedPhrase = try? generateMnemonic(wordCount: UInt32(selectedSeedPhraseWordCount)) else {
            seedPhrase = ""
            seedPhraseEntries = Array(repeating: "", count: selectedSeedPhraseWordCount)
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        seedPhrase = generatedPhrase
        let generatedWords = generatedPhrase.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var entries = Array(repeating: "", count: selectedSeedPhraseWordCount)
        for (index, word) in generatedWords.enumerated() where index < entries.count { entries[index] = word }
        seedPhraseEntries = entries
        backupVerificationWordIndices = []
        backupVerificationEntries = []
    }
    func seedPhraseEntry(at index: Int) -> String {
        guard seedPhraseEntries.indices.contains(index) else { return "" }
        return seedPhraseEntries[index]
    }
    /// Put what was typed or pasted at `index`. Several words fill the slots
    /// from there on, adding slots rather than dropping words that do not fit.
    func updateSeedPhraseEntry(at index: Int, with newValue: String) {
        guard seedPhraseEntries.indices.contains(index) else { return }
        let pastedWords = newValue.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if pastedWords.count > 1 {
            var updatedEntries = seedPhraseEntries
            let end = index + pastedWords.count
            if updatedEntries.count < end {
                updatedEntries.append(contentsOf: Array(repeating: "", count: end - updatedEntries.count))
            }
            updatedEntries.replaceSubrange(index..<end, with: pastedWords)
            seedPhraseEntries = updatedEntries
            syncSeedPhraseFromEntries()
            fitSeedPhraseSlots(shrinking: false)
            return
        }
        let normalizedValue = newValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard seedPhraseEntries[index] != normalizedValue else { return }
        seedPhraseEntries[index] = normalizedValue
        syncSeedPhraseFromEntries()
        fitSeedPhraseSlots(shrinking: false)
    }
    /// Replace the whole entry with a pasted phrase.
    func pasteSeedPhrase(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        seedPhraseEntries = Array(repeating: "", count: seedPhraseWordCountOverride ?? 12)
        updateSeedPhraseEntry(at: 0, with: trimmed)
    }
    func clearSeedPhrase() {
        seedPhraseEntries = Array(repeating: "", count: seedPhraseWordCountOverride ?? 12)
        syncSeedPhraseFromEntries()
    }
    /// The next BIP-39 length past the grid's, or `nil` at the longest.
    var nextSeedPhraseSlotCount: Int? {
        CoreReferenceTables.standardSeedPhraseLengths.map { Int($0.wordCount) }
            .first { $0 > seedPhraseEntries.count }
    }
    /// Grow the grid to the next BIP-39 length, for a phrase typed past it.
    func addSeedPhraseSlots() {
        guard let next = nextSeedPhraseSlotCount else { return }
        seedPhraseEntries.append(contentsOf: Array(repeating: "", count: next - seedPhraseEntries.count))
    }
    /// Size an import's grid to the length core judges it at, never below
    /// its last filled slot. Growing alone keeps slots the user added; a new
    /// override also drops blank slots past it.
    private func fitSeedPhraseSlots(shrinking: Bool) {
        guard !isCreateMode else { return }
        let filledThrough = (seedPhraseEntries.lastIndex { !$0.isEmpty } ?? -1) + 1
        let target = max(Int(seedPhraseVerdict.wordCount), filledThrough)
        if seedPhraseEntries.count < target {
            seedPhraseEntries.append(contentsOf: Array(repeating: "", count: target - seedPhraseEntries.count))
        } else if shrinking, seedPhraseEntries.count > target {
            seedPhraseEntries = Array(seedPhraseEntries.prefix(target))
        }
    }
    func prepareBackupVerificationChallenge() {
        guard requiresBackupVerification else {
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        let words = seedPhraseWords
        guard words.count == selectedSeedPhraseWordCount else {
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        var indices: Set<Int> = []
        while indices.count < min(3, selectedSeedPhraseWordCount) {
            indices.insert(Int.random(in: 0..<selectedSeedPhraseWordCount))
        }
        let sortedIndices = indices.sorted()
        backupVerificationWordIndices = sortedIndices
        backupVerificationEntries = Array(repeating: "", count: sortedIndices.count)
    }
    func updateBackupVerificationEntry(at index: Int, with value: String) {
        guard backupVerificationEntries.indices.contains(index) else { return }
        backupVerificationEntries[index] = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    /// A typed custom length, clamped to the range core can judge. Fixes the
    /// generated length when creating and the judged length when importing.
    func applyCustomSeedPhraseWordCount(_ rawValue: String) {
        let digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, let parsed = Int(digits) else { return }
        let clamped = min(max(parsed, 1), 48)
        if isCreateMode {
            guard clamped != selectedSeedPhraseWordCount else { return }
            selectedSeedPhraseWordCount = clamped
        } else {
            seedPhraseWordCountOverride = clamped
        }
    }
    private func resizeSeedPhraseEntries(to count: Int) {
        guard count > 0, isCreateMode else { return }
        if seedPhraseEntries.count > count {
            seedPhraseEntries = Array(seedPhraseEntries.prefix(count))
        } else if seedPhraseEntries.count < count {
            seedPhraseEntries.append(contentsOf: Array(repeating: "", count: count - seedPhraseEntries.count))
        }
        if backupVerificationWordIndices.contains(where: { $0 >= count }) {
            backupVerificationWordIndices = []
            backupVerificationEntries = []
        }
        regenerateSeedPhrase()
    }
    private func syncSeedPhraseFromEntries() {
        let normalizedEntries = seedPhraseEntries.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalizedEntries != seedPhraseEntries {
            seedPhraseEntries = normalizedEntries
            return
        }
        let combinedSeedPhrase = normalizedEntries.filter { !$0.isEmpty }.joined(separator: " ")
        if seedPhrase != combinedSeedPhrase { seedPhrase = combinedSeedPhrase }
        if !backupVerificationWordIndices.isEmpty, !isBackupVerificationComplete {
            backupVerificationEntries = Array(repeating: "", count: backupVerificationWordIndices.count)
        }
    }
}
