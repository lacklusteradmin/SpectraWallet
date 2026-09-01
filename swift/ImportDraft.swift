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
    var seedDerivationPreset: SeedDerivationPreset = .standard
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
    var overrideMnemonicWordlist: String = ""
    var overrideIterationCount: String = ""
    var overrideSaltPrefix: String = ""
    var overrideHmacKey: String = ""
    var overrideCurve: String = ""
    var overrideDerivationAlgorithm: String = ""
    var overrideAddressAlgorithm: String = ""
    var overridePublicKeyFormat: String = ""
    var overrideScriptType: String = ""
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
    private(set) var selectedCoins: [Coin] = []
    private(set) var selectedChainNames: [String] = []
    var isCreateMode: Bool { mode == .createNew }
    var isPrivateKeyImportMode: Bool { mode == .importExisting && !isEditingWallet && !isWatchOnlyMode && secretImportMode == .privateKey }
    var supportedPrivateKeyChainNames: [String] { Chain.mainnets.filter(\.derivesFromPrivateKey).map(\.displayName) }
    var unsupportedPrivateKeyChainNames: [String] {
        let supported = Self.supportedPrivateKeyChainNameSet
        return selectedChainNames.filter { !supported.contains($0) }
    }
    private var allowsMultipleChainSelection: Bool { !isEditingWallet && !isWatchOnlyMode && !isPrivateKeyImportMode }
    func isSelected(_ chainName: String) -> Bool { isSelectedChain(chainName) }
    var seedPhraseValidationError: String? {
        guard !isEditingWallet else { return nil }
        guard isSeedPhraseEntryComplete else { return nil }
        guard invalidSeedWords.isEmpty else { return nil }
        let words = seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard words.count == selectedSeedPhraseWordCount else { return "Seed phrase must be \(selectedSeedPhraseWordCount) words." }
        guard WalletServiceBridge.shared.rustValidateMnemonic(seedPhrase) else {
            return "Invalid seed phrase checksum. Please verify your words."
        }
        return nil
    }
    var hasValidSeedPhraseChecksum: Bool {
        guard !isEditingWallet else { return false }
        guard isSeedPhraseEntryComplete else { return false }
        guard invalidSeedWords.isEmpty else { return false }
        let words = seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard words.count == selectedSeedPhraseWordCount else { return false }
        return WalletServiceBridge.shared.rustValidateMnemonic(seedPhrase)
    }
    var seedPhraseWords: [String] {
        seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }
    var normalizedWalletPassword: String? {
        let trimmed = walletPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var walletPasswordValidationError: String? {
        coreValidateWalletPassword(password: walletPassword, confirmation: walletPasswordConfirmation)
    }
    var invalidSeedWords: [String] {
        guard !isEditingWallet else { return [] }
        let wordset = BIP39WordList.words(for: seedPhraseLanguage)
        let words = seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return words.filter { !wordset.contains($0) }
    }
    var seedPhraseLengthWarning: String? {
        guard !isEditingWallet else { return nil }
        return coreValidateSeedPhraseWordCount(wordCount: UInt32(selectedSeedPhraseWordCount))
    }
    private var isSeedPhraseEntryComplete: Bool {
        guard selectedSeedPhraseWordCount > 0 else { return false }
        guard seedPhraseEntries.count >= selectedSeedPhraseWordCount else { return false }
        return seedPhraseEntries.prefix(selectedSeedPhraseWordCount).allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    init() {
        refreshSelectionState()
    }
    /// Compile the 10 Advanced-mode power-user override fields into a single
    /// `CoreWalletDerivationOverrides` record. Blank strings map to `nil`
    /// (= "use chain preset default"); populated fields are passed verbatim
    /// to the Rust derivation pipeline, which validates them.
    var resolvedDerivationOverrides: CoreWalletDerivationOverrides {
        func nilIfBlank(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let iteration: UInt32? = {
            let trimmed = overrideIterationCount.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : UInt32(trimmed)
        }()
        // salt_prefix is intentionally allowed to include or consist entirely
        // of whitespace (Rust treats `Some("")` differently from `None`), so
        // only filter out an empty-from-the-start field.
        let salt: String? = overrideSaltPrefix.isEmpty ? nil : overrideSaltPrefix
        return CoreWalletDerivationOverrides(
            passphrase: nilIfBlank(overridePassphrase),
            mnemonicWordlist: nilIfBlank(overrideMnemonicWordlist),
            iterationCount: iteration,
            saltPrefix: salt,
            hmacKey: nilIfBlank(overrideHmacKey),
            curve: nilIfBlank(overrideCurve),
            derivationAlgorithm: nilIfBlank(overrideDerivationAlgorithm),
            addressAlgorithm: nilIfBlank(overrideAddressAlgorithm),
            publicKeyFormat: nilIfBlank(overridePublicKeyFormat),
            scriptType: nilIfBlank(overrideScriptType)
        )
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

    /// Populate the seed phrase the way the UI does — the per-word entry grid
    /// *and* the joined string. Validation reads `seedPhraseEntries`, so
    /// setting `seedPhrase` alone leaves the draft looking incomplete.
    func setSeedPhraseForTesting(_ phrase: String) {
        let words = phrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        selectedSeedPhraseWordCount = words.count
        seedPhraseEntries = words
        seedPhrase = words.joined(separator: " ")
    }

    /// Watch-only entries keyed by the storage slot Rust expects. Empty when
    /// the draft is not in watch-only mode.
    var watchOnlyEntriesBySlot: [String: [String]] {
        guard isWatchOnlyMode else { return [:] }
        return addressSlotMap(
            watchOnlyInputsByChainName.mapValues { watchOnlyEntries(from: $0) }
        )
    }
    var canImportWallet: Bool {
        let hasValidSeedPhrase =
            !isEditingWallet
            && seedPhraseWords.count == selectedSeedPhraseWordCount
            && seedPhraseValidationError == nil
            && invalidSeedWords.isEmpty
            && hasValidSeedPhraseChecksum
        let trimmedXpub = bitcoinXpubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let watchEntries = WalletImportWatchOnlyEntries(
            bySlot: watchOnlyEntriesBySlot,
            bitcoinXpub: isWatchOnlyMode && !trimmedXpub.isEmpty ? trimmedXpub : nil
        )
        return coreValidateWalletImportDraft(
            request: WalletImportDraftValidationRequest(
                selectedChainNames: selectedChainNames,
                isWatchOnly: isWatchOnlyMode,
                isPrivateKeyImport: isPrivateKeyImportMode,
                isEditing: isEditingWallet,
                isCreateMode: isCreateMode,
                hasValidWalletName: !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasValidSeedPhrase: hasValidSeedPhrase,
                hasValidPrivateKeyHex: CachedCoreHelpers.privateKeyHexIsLikely(rawValue: privateKeyInput),
                isBackupVerificationComplete: isBackupVerificationComplete,
                requiresBackupVerification: requiresBackupVerification,
                watchOnlyEntries: watchEntries
            ))
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
        if backupVerificationWordIndices.isEmpty { return "Generate a backup verification challenge to continue." }
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
    func configureForEditing(wallet: ImportedWallet) {
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
        overrideMnemonicWordlist = ""
        overrideIterationCount = ""
        overrideSaltPrefix = ""
        overrideHmacKey = ""
        overrideCurve = ""
        overrideDerivationAlgorithm = ""
        overrideAddressAlgorithm = ""
        overridePublicKeyFormat = ""
        overrideScriptType = ""
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
        selectedCoins = effectiveChainNames.compactMap(Self.coin(for:))
    }
    private static let coinsByChain: [String: Coin] = {
        var dict: [String: Coin] = [:]
        for chain in listAllChains() where !chain.nativeAssetName.isEmpty {
            dict[chain.name] = Coin.makeCustom(
                name: chain.nativeAssetName,
                symbol: chain.gasTokenSymbol,
                coinGeckoId: chain.nativeCoingeckoId,
                chainName: chain.name,
                tokenStandard: "Native",
                contractAddress: nil,
                amount: 0,
                priceUsd: 0
            )
        }
        return dict
    }()
    private static func coin(for chainName: String) -> Coin? { coinsByChain[chainName] }
    func regenerateSeedPhrase() {
        guard isCreateMode else { return }
        guard [12, 15, 18, 21, 24].contains(selectedSeedPhraseWordCount) else {
            seedPhrase = ""
            seedPhraseEntries = Array(repeating: "", count: selectedSeedPhraseWordCount)
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        let generatedPhrase = WalletServiceBridge.shared.rustGenerateMnemonic(wordCount: selectedSeedPhraseWordCount)
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

/// Bundled validation result for `WalletImportDraft`.
///
/// Replaces the read-time recomputation in scattered properties
/// (`seedPhraseValidationError`, `walletPasswordValidationError`,
/// `invalidSeedWords`, `unsupportedPrivateKeyChainNames`, etc.) with one
/// struct that names every error mode in a single type. Views read
/// `draft.validation.password` etc. — the rule for "is this field
/// invalid" lives in `WalletImportDraft.validate()` instead of being
/// spread across N computed properties.
struct WalletImportDraftValidation {
    /// Words the user typed that aren't in the BIP-39 wordlist.
    var invalidSeedWords: [String] = []
    /// Length / format / checksum problem with the seed phrase.
    var seedPhraseError: String? = nil
    /// True when the seed phrase parses, has no invalid words, and the
    /// BIP-39 checksum verifies.
    var hasValidSeedPhraseChecksum: Bool = false
    /// Length / mismatch problem with the wallet password.
    var passwordError: String? = nil
    /// User selected chains the chosen private-key import mode can't sign for.
    var unsupportedPrivateKeyChainNames: [String] = []
    /// Non-standard mnemonic length warning (separate from `seedPhraseError`
    /// because it's advisory, not blocking).
    var seedPhraseLengthWarning: String? = nil
}

extension WalletImportDraft {
    /// One-shot validation snapshot. Mirrors the live state at call time;
    /// re-call after any mutation. Reading individual `*ValidationError`
    /// properties is equivalent to reading the matching field on this
    /// struct — they're shims.
    func validate() -> WalletImportDraftValidation {
        var result = WalletImportDraftValidation()
        result.invalidSeedWords = invalidSeedWords
        result.seedPhraseError = seedPhraseValidationError
        result.hasValidSeedPhraseChecksum = hasValidSeedPhraseChecksum
        result.passwordError = walletPasswordValidationError
        result.unsupportedPrivateKeyChainNames = unsupportedPrivateKeyChainNames
        result.seedPhraseLengthWarning = seedPhraseLengthWarning
        return result
    }
}
