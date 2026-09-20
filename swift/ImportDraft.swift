import SwiftUI
enum WalletDraftMode {
    case importExisting
    case createNew
    case editExisting
}
enum WalletSecretImportMode: String, CaseIterable, Identifiable {
    case seedPhrase = "Seed Phrase"
    case privateKey = "Private Key"
    var id: String { rawValue }
    var localizedTitle: String { AppLocalization.string(rawValue) }
}
/// Simple vs. Advanced setup path. Chosen up-front on the Add-Wallet page
/// (alongside the create/import/watch choice) and persisted on the draft
/// so `SetupView` can skip its old "Choose Setup Type" page and start
/// directly on the details step.
enum SetupModeChoice: String, CaseIterable, Identifiable {
    case simple
    case advanced
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .simple: return AppLocalization.string("Simple")
        case .advanced: return AppLocalization.string("Advanced")
        }
    }
}
/// Mutation contract for `WalletImportDraft`:
///
///   * **Side-effecting state** (chain selection, watch-only mode, secret-
///     import mode, mnemonic length) is mutated through a named method on
///     the draft. The method runs validation, regenerates derived state,
///     and emits the necessary observation bumps. Direct binding to
///     `$draft.<sideEffectField>` is a bug — bypassing the method leaves
///     the draft internally inconsistent. (Properties below that have a
///     `didSet { refresh… }` block belong to this category.)
///   * **Plain text-input fields** (wallet name, password, watch
///     addresses, individual seed-phrase words) MAY be bound directly via
///     `$draft.…`. These have no derivation invariants — the draft
///     revalidates lazily on read.
///
/// When you add a new field that needs validation/derivation refresh,
/// give it a `didSet` that calls the relevant `refresh…` method *and* a
/// public mutator method. Don't expose it for direct binding without
/// either guard, even if it's tempting.
@MainActor
@Observable
final class WalletImportDraft {
    private static var supportedPrivateKeyChainNameSet: Set<String> {
        Set(Chain.mainnets.filter(\.derivesFromPrivateKey).map(\.displayName))
    }
    var mode: WalletDraftMode = .importExisting {
        didSet { refreshSelectionState() }
    }
    var isEditingWallet: Bool = false {
        didSet { refreshSelectionState() }
    }
    var walletName: String = ""
    var seedPhrase: String = ""
    var walletPassword: String = ""
    var walletPasswordConfirmation: String = ""
    var secretImportMode: WalletSecretImportMode = .seedPhrase {
        didSet { refreshSelectionState() }
    }
    var privateKeyInput: String = ""
    var seedDerivationPreset: CoreSeedDerivationPreset = .standard
    var usesCustomDerivationPaths: Bool = true
    var seedDerivationPaths: SeedDerivationPaths = .defaults
    /// User's simple/advanced selection from the Add-Wallet page. Drives
    /// whether the Advanced derivation page is reachable from SetupView.
    var setupModeChoice: SetupModeChoice = .simple
    // Power-user derivation overrides (Advanced page, Option A). Each field is
    // a user-entered string; blank/empty-picker means "use chain preset default".
    // These are converted to CoreWalletDerivationOverrides at import time via
    // `resolvedDerivationOverrides`.
    var overridePassphrase: String = ""
    var overrideHmacKey: String = ""
    var seedPhraseLanguage: String = "en"
    var seedPhraseEntries: [String] = Array(repeating: "", count: 12)
    var selectedSeedPhraseWordCount: Int = 12 {
        didSet {
            resizeSeedPhraseEntries(to: selectedSeedPhraseWordCount)
        }
    }
    var isWatchOnlyMode: Bool = false {
        didSet { refreshSelectionState() }
    }
    /// The watch-only address text, keyed by chain display name.
    var watchOnlyInputsByChainName: [String: String] = [:]
    /// Not an address, so not in the table above: Bitcoin's account xpub stands
    /// in for the whole account and plans one wallet rather than one per line.
    var bitcoinXpubInput: String = ""
    var selectedChainNamesStorage: [String] = [] {
        didSet { refreshSelectionState() }
    }
    var backupVerificationWordIndices: [Int] = []
    var backupVerificationEntries: [String] = []
    private(set) var selectedChainNames: [String] = []
    var isCreateMode: Bool { mode == .createNew }
    var isPrivateKeyImportMode: Bool { mode == .importExisting && !isEditingWallet && !isWatchOnlyMode && secretImportMode == .privateKey }
    var unsupportedPrivateKeyChainNames: [String] {
        let supported = Self.supportedPrivateKeyChainNameSet
        return selectedChainNames.filter { !supported.contains($0) }
    }
    private var allowsMultipleChainSelection: Bool { !isEditingWallet && !isWatchOnlyMode && !isPrivateKeyImportMode }
    func isSelected(_ chainName: String) -> Bool { isSelectedChain(chainName) }
    /// Everything core has to say about the entry grid, decided in one pass.
    /// Edit mode resets the grid, so an empty entry answers "nothing to say"
    /// without a mode guard of its own.
    var seedPhraseVerdict: SeedPhraseVerdict {
        coreCheckSeedPhrase(
            check: SeedPhraseCheck(
                words: seedPhraseEntries,
                language: seedPhraseLanguage,
                expectedWordCount: UInt32(selectedSeedPhraseWordCount)))
    }
    /// The entry grid as words. `seedPhrase` is kept in sync with the grid,
    /// so this reads the same phrase either way.
    var seedPhraseWords: [String] { seedPhraseVerdict.words }
    var normalizedWalletPassword: String? {
        let trimmed = walletPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var walletPasswordValidationError: String? {
        guard let reason = coreValidateWalletPassword(password: walletPassword, confirmation: walletPasswordConfirmation) else { return nil }
        switch reason {
        case .tooShort: return AppLocalization.string("Wallet password must be at least 4 characters, or leave it blank.")
        case .confirmationMismatch: return AppLocalization.string("Wallet password confirmation does not match.")
        }
    }
    init() {
        refreshSelectionState()
    }
    /// Core interprets exact secret input and refuses unsupported overrides.
    var resolvedDerivationOverrides: CoreWalletDerivationOverrides {
        coreParseWalletDerivationInput(input: WalletDerivationInput(
            passphrase: overridePassphrase, hmacKey: overrideHmacKey))
    }
    /// The selected chains, in catalog order rather than selection order.
    var selectableDerivationChains: [Chain] {
        let selected = Set(selectedChainNames)
        return Chain.all.filter { selected.contains($0.displayName) }
    }
    func watchOnlyEntries(from rawValue: String) -> [String] {
        rawValue.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Watch-only entries keyed by the storage slot Rust expects. Empty when
    /// the draft is not in watch-only mode.
    var watchOnlyEntriesBySlot: [String: [String]] {
        guard isWatchOnlyMode else { return [:] }
        return addressSlotMap(
            watchOnlyInputsByChainName.mapValues { watchOnlyEntries(from: $0) }
        )
    }
    /// The watch-only inputs as core reads them, for the check and the import.
    var watchOnlyImportEntries: WalletImportWatchOnlyEntries {
        let trimmedXpub = bitcoinXpubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return WalletImportWatchOnlyEntries(
            bySlot: watchOnlyEntriesBySlot,
            bitcoinXpub: isWatchOnlyMode && !trimmedXpub.isEmpty ? trimmedXpub : nil)
    }
    private var draftMode: WalletImportDraftMode {
        if isEditingWallet { return .rename }
        if isCreateMode { return .create }
        if isWatchOnlyMode { return .watchOnly }
        return isPrivateKeyImportMode ? .importPrivateKey : .importSeedPhrase
    }
    /// Core reads the form as typed. It was handed eleven booleans this side
    /// had already worked out, so its rule combined answers it never saw the
    /// inputs for.
    var canImportWallet: Bool {
        coreValidateWalletImportDraft(
            draft: WalletImportDraftInput(
                mode: draftMode, selectedChainNames: selectedChainNames, walletName: walletName,
                seedPhraseWords: seedPhraseEntries, seedPhraseLanguage: seedPhraseLanguage,
                seedPhraseWordCount: UInt32(selectedSeedPhraseWordCount), privateKey: privateKeyInput,
                backupVerified: isBackupVerificationComplete, watchOnlyEntries: watchOnlyImportEntries))
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
        isEditingWallet = false
        reset()
    }
    func configureForWatchAddressesImport() {
        mode = .importExisting
        isEditingWallet = false
        reset()
        isWatchOnlyMode = true
    }
    func configureForCreatedWallet() {
        mode = .importExisting
        isEditingWallet = false
        reset()
        mode = .createNew
        isWatchOnlyMode = false
        regenerateSeedPhrase()
    }
    func configureForEditing(wallet: WalletView) {
        mode = .importExisting
        isEditingWallet = false
        reset()
        mode = .editExisting
        isEditingWallet = true
        walletName = wallet.name
    }
    func reset() {
        walletName = ""
        seedPhrase = ""
        walletPassword = ""
        walletPasswordConfirmation = ""
        secretImportMode = .seedPhrase
        privateKeyInput = ""
        seedDerivationPreset = .standard
        usesCustomDerivationPaths = true
        seedDerivationPaths = .defaults
        setupModeChoice = .simple
        overridePassphrase = ""
        overrideHmacKey = ""
        seedPhraseEntries = Array(repeating: "", count: 12)
        selectedSeedPhraseWordCount = 12
        isWatchOnlyMode = false
        // One line, and it clears every chain. The eighteen assignments it
        // replaces were five short of the twenty-three fields that existed —
        // Zcash, Bitcoin Gold, Decred, Kaspa, Dash and Bittensor were never
        // cleared, which a table cannot get wrong.
        watchOnlyInputsByChainName = [:]
        bitcoinXpubInput = ""
        selectedChainNamesStorage = []
        backupVerificationWordIndices = []
        backupVerificationEntries = []
    }
    func clearSensitiveInputs() {
        seedPhrase = ""
        walletPassword = ""
        walletPasswordConfirmation = ""
        privateKeyInput = ""
        seedPhraseEntries = Array(repeating: "", count: selectedSeedPhraseWordCount)
        backupVerificationEntries = Array(repeating: "", count: backupVerificationWordIndices.count)
    }
    func toggleChainSelection(_ chainName: String) { setSelectedChain(chainName, isEnabled: !isSelectedChain(chainName)) }
    private func isSelectedChain(_ chainName: String) -> Bool { selectedChainNamesStorage.contains(chainName) }
    private func setSelectedChain(_ chainName: String, isEnabled: Bool) {
        if isEnabled {
            if allowsMultipleChainSelection {
                if !selectedChainNamesStorage.contains(chainName) { selectedChainNamesStorage.append(chainName) }
            } else {
                selectedChainNamesStorage = [chainName]
            }
        } else {
            selectedChainNamesStorage.removeAll { $0 == chainName }
        }
    }
    private func refreshSelectionState() {
        let effectiveChainNames = allowsMultipleChainSelection ? selectedChainNamesStorage : Array(selectedChainNamesStorage.prefix(1))
        selectedChainNames = effectiveChainNames
    }
    func regenerateSeedPhrase() {
        guard isCreateMode else { return }
        // Core refuses a length BIP-39 does not define. This used to hold the
        // five so it would not ask — one of four copies of that list.
        guard
            let generatedPhrase = WalletServiceBridge.shared.rustGenerateMnemonic(
                wordCount: selectedSeedPhraseWordCount)
        else {
            seedPhrase = ""
            seedPhraseEntries = Array(repeating: "", count: selectedSeedPhraseWordCount)
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        seedPhrase = generatedPhrase
        let generatedWords = generatedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
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
    func updateSeedPhraseEntry(at index: Int, with newValue: String) {
        guard seedPhraseEntries.indices.contains(index) else { return }
        let pastedWords = newValue.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if pastedWords.count > 1 {
            var updatedEntries = seedPhraseEntries
            for offset in 0..<pastedWords.count {
                let destinationIndex = index + offset
                guard updatedEntries.indices.contains(destinationIndex) else { break }
                updatedEntries[destinationIndex] = pastedWords[offset]
            }
            seedPhraseEntries = updatedEntries
            syncSeedPhraseFromEntries()
            return
        }
        let normalizedValue = newValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard seedPhraseEntries[index] != normalizedValue else { return }
        seedPhraseEntries[index] = normalizedValue
        syncSeedPhraseFromEntries()
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
    func applyCustomSeedPhraseWordCount(_ rawValue: String) {
        let digits = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, let parsed = Int(digits) else { return }
        let clamped = min(max(parsed, 1), 48)
        guard clamped != selectedSeedPhraseWordCount else { return }
        selectedSeedPhraseWordCount = clamped
    }
    private func resizeSeedPhraseEntries(to count: Int) {
        guard count > 0 else { return }
        if seedPhraseEntries.count > count {
            seedPhraseEntries = Array(seedPhraseEntries.prefix(count))
        } else if seedPhraseEntries.count < count {
            seedPhraseEntries.append(contentsOf: Array(repeating: "", count: count - seedPhraseEntries.count))
        }
        if backupVerificationWordIndices.contains(where: { $0 >= count }) {
            backupVerificationWordIndices = []
            backupVerificationEntries = []
        }
        if isCreateMode {
            regenerateSeedPhrase()
            return
        }
        syncSeedPhraseFromEntries()
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
