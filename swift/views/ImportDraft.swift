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
@MainActor
@Observable
final class WalletImportDraft {
    private static let supportedPrivateKeyChainNames: [String] = [
        "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism",
        "BNB Chain", "Avalanche", "Hyperliquid", "Tron", "Solana", "Cardano", "Stellar", "XRP Ledger", "Sui", "Aptos", "TON",
        "Internet Computer", "NEAR", "Polkadot",
    ]
    private static let supportedPrivateKeyChainNameSet = Set(supportedPrivateKeyChainNames)
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
    var seedPhraseEntries: [String] = Array(repeating: "", count: 12)
    var selectedSeedPhraseWordCount: Int = 12 {
        didSet {
            resizeSeedPhraseEntries(to: selectedSeedPhraseWordCount)
        }
    }
    var isWatchOnlyMode: Bool = false {
        didSet { refreshSelectionState() }
    }
    var bitcoinAddressInput: String = ""
    var bitcoinXpubInput: String = ""
    var bitcoinCashAddressInput: String = ""
    var bitcoinSvAddressInput: String = ""
    var litecoinAddressInput: String = ""
    var dogecoinAddressInput: String = ""
    var ethereumAddressInput: String = ""
    var tronAddressInput: String = ""
    var solanaAddressInput: String = ""
    var stellarAddressInput: String = ""
    var xrpAddressInput: String = ""
    var moneroAddressInput: String = ""
    var cardanoAddressInput: String = ""
    var suiAddressInput: String = ""
    var aptosAddressInput: String = ""
    var tonAddressInput: String = ""
    var icpAddressInput: String = ""
    var nearAddressInput: String = ""
    var polkadotAddressInput: String = ""
    var selectedChainNamesStorage: [String] = [] {
        didSet { refreshSelectionState() }
    }
    var backupVerificationWordIndices: [Int] = []
    var backupVerificationEntries: [String] = []
    private(set) var selectedCoins: [Coin] = []
    private(set) var selectedChainNames: [String] = []
    var isCreateMode: Bool { mode == .createNew }
    var isPrivateKeyImportMode: Bool { mode == .importExisting && !isEditingWallet && !isWatchOnlyMode && secretImportMode == .privateKey }
    var supportedPrivateKeyChainNames: [String] { Self.supportedPrivateKeyChainNames }
    var unsupportedPrivateKeyChainNames: [String] {
        selectedChainNames.filter { !Self.supportedPrivateKeyChainNameSet.contains($0) }
    }
    private var allowsMultipleChainSelection: Bool { !isEditingWallet && !isWatchOnlyMode && !isPrivateKeyImportMode }
    var wantsBitcoin: Bool {
        get { isSelectedChain("Bitcoin") }
        set { setSelectedChain("Bitcoin", isEnabled: newValue) }
    }
    var wantsBitcoinCash: Bool {
        get { isSelectedChain("Bitcoin Cash") }
        set { setSelectedChain("Bitcoin Cash", isEnabled: newValue) }
    }
    var wantsBitcoinSV: Bool {
        get { isSelectedChain("Bitcoin SV") }
        set { setSelectedChain("Bitcoin SV", isEnabled: newValue) }
    }
    var wantsLitecoin: Bool {
        get { isSelectedChain("Litecoin") }
        set { setSelectedChain("Litecoin", isEnabled: newValue) }
    }
    var wantsEthereum: Bool {
        get { isSelectedChain("Ethereum") }
        set { setSelectedChain("Ethereum", isEnabled: newValue) }
    }
    var wantsEthereumClassic: Bool {
        get { isSelectedChain("Ethereum Classic") }
        set { setSelectedChain("Ethereum Classic", isEnabled: newValue) }
    }
    var wantsArbitrum: Bool {
        get { isSelectedChain("Arbitrum") }
        set { setSelectedChain("Arbitrum", isEnabled: newValue) }
    }
    var wantsOptimism: Bool {
        get { isSelectedChain("Optimism") }
        set { setSelectedChain("Optimism", isEnabled: newValue) }
    }
    var wantsSolana: Bool {
        get { isSelectedChain("Solana") }
        set { setSelectedChain("Solana", isEnabled: newValue) }
    }
    var wantsBNBChain: Bool {
        get { isSelectedChain("BNB Chain") }
        set { setSelectedChain("BNB Chain", isEnabled: newValue) }
    }
    var wantsAvalanche: Bool {
        get { isSelectedChain("Avalanche") }
        set { setSelectedChain("Avalanche", isEnabled: newValue) }
    }
    var wantsHyperliquid: Bool {
        get { isSelectedChain("Hyperliquid") }
        set { setSelectedChain("Hyperliquid", isEnabled: newValue) }
    }
    var wantsDogecoin: Bool {
        get { isSelectedChain("Dogecoin") }
        set { setSelectedChain("Dogecoin", isEnabled: newValue) }
    }
    var wantsCardano: Bool {
        get { isSelectedChain("Cardano") }
        set { setSelectedChain("Cardano", isEnabled: newValue) }
    }
    var wantsTron: Bool {
        get { isSelectedChain("Tron") }
        set { setSelectedChain("Tron", isEnabled: newValue) }
    }
    var wantsStellar: Bool {
        get { isSelectedChain("Stellar") }
        set { setSelectedChain("Stellar", isEnabled: newValue) }
    }
    var wantsXRP: Bool {
        get { isSelectedChain("XRP Ledger") }
        set { setSelectedChain("XRP Ledger", isEnabled: newValue) }
    }
    var wantsMonero: Bool {
        get { isSelectedChain("Monero") }
        set { setSelectedChain("Monero", isEnabled: newValue) }
    }
    var wantsSui: Bool {
        get { isSelectedChain("Sui") }
        set { setSelectedChain("Sui", isEnabled: newValue) }
    }
    var wantsAptos: Bool {
        get { isSelectedChain("Aptos") }
        set { setSelectedChain("Aptos", isEnabled: newValue) }
    }
    var wantsTON: Bool {
        get { isSelectedChain("TON") }
        set { setSelectedChain("TON", isEnabled: newValue) }
    }
    var wantsICP: Bool {
        get { isSelectedChain("Internet Computer") }
        set { setSelectedChain("Internet Computer", isEnabled: newValue) }
    }
    var wantsNear: Bool {
        get { isSelectedChain("NEAR") }
        set { setSelectedChain("NEAR", isEnabled: newValue) }
    }
    var wantsPolkadot: Bool {
        get { isSelectedChain("Polkadot") }
        set { setSelectedChain("Polkadot", isEnabled: newValue) }
    }
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
        let password = walletPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmation = walletPasswordConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty || !confirmation.isEmpty else { return nil }
        guard password.count >= 4 else { return "Wallet password must be at least 4 characters, or leave it blank." }
        guard password == confirmation else { return "Wallet password confirmation does not match." }
        return nil
    }
    var invalidSeedWords: [String] {
        guard !isEditingWallet else { return [] }
        let wordlist = Set(WalletServiceBridge.shared.rustBip39Wordlist())
        let words = seedPhrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return words.filter { !wordlist.contains($0) }
    }
    var seedPhraseLengthWarning: String? {
        guard !isEditingWallet else { return nil }
        let count = selectedSeedPhraseWordCount
        guard count > 0 else { return "Seed phrase length must be at least 1 word." }
        if count < 12 { return "Seed phrase is too short. Use at least 12 words." }
        if ![12, 15, 18, 21, 24].contains(count) {
            return "Non-standard length selected. BIP-39 standard lengths are 12, 15, 18, 21, or 24 words."
        }
        return nil
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
    var selectableDerivationChains: [SeedDerivationChain] {
        let selectedChainNameSet = Set(selectedChainNames)
        return SeedDerivationChain.allCases.filter { selectedChainNameSet.contains($0.rawValue) }
    }
    func applyDerivationPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool? = nil) {
        seedDerivationPreset = preset
        seedDerivationPaths = .applyingPreset(preset, keepCustomEnabled: keepCustomEnabled ?? seedDerivationPaths.isCustomEnabled)
    }
    func watchOnlyEntries(from rawValue: String) -> [String] {
        rawValue.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            bitcoinAddresses: isWatchOnlyMode ? watchOnlyEntries(from: bitcoinAddressInput) : [],
            bitcoinXpub: isWatchOnlyMode && !trimmedXpub.isEmpty ? trimmedXpub : nil,
            bitcoinCashAddresses: isWatchOnlyMode ? watchOnlyEntries(from: bitcoinCashAddressInput) : [],
            bitcoinSvAddresses: isWatchOnlyMode ? watchOnlyEntries(from: bitcoinSvAddressInput) : [],
            litecoinAddresses: isWatchOnlyMode ? watchOnlyEntries(from: litecoinAddressInput) : [],
            dogecoinAddresses: isWatchOnlyMode ? watchOnlyEntries(from: dogecoinAddressInput) : [],
            ethereumAddresses: isWatchOnlyMode ? watchOnlyEntries(from: ethereumAddressInput) : [],
            tronAddresses: isWatchOnlyMode ? watchOnlyEntries(from: tronAddressInput) : [],
            solanaAddresses: isWatchOnlyMode ? watchOnlyEntries(from: solanaAddressInput) : [],
            xrpAddresses: isWatchOnlyMode ? watchOnlyEntries(from: xrpAddressInput) : [],
            stellarAddresses: isWatchOnlyMode ? watchOnlyEntries(from: stellarAddressInput) : [],
            cardanoAddresses: isWatchOnlyMode ? watchOnlyEntries(from: cardanoAddressInput) : [],
            suiAddresses: isWatchOnlyMode ? watchOnlyEntries(from: suiAddressInput) : [],
            aptosAddresses: isWatchOnlyMode ? watchOnlyEntries(from: aptosAddressInput) : [],
            tonAddresses: isWatchOnlyMode ? watchOnlyEntries(from: tonAddressInput) : [],
            icpAddresses: isWatchOnlyMode ? watchOnlyEntries(from: icpAddressInput) : [],
            nearAddresses: isWatchOnlyMode ? watchOnlyEntries(from: nearAddressInput) : [],
            polkadotAddresses: isWatchOnlyMode ? watchOnlyEntries(from: polkadotAddressInput) : []
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
    var unsupportedSelectedChainNames: [String] {
        selectedChainNames.filter { !AppEndpointDirectory.supportsBalanceRefresh(for: $0) }
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
        bitcoinAddressInput = ""
        bitcoinXpubInput = ""
        bitcoinCashAddressInput = ""
        bitcoinSvAddressInput = ""
        litecoinAddressInput = ""
        dogecoinAddressInput = ""
        ethereumAddressInput = ""
        tronAddressInput = ""
        solanaAddressInput = ""
        stellarAddressInput = ""
        xrpAddressInput = ""
        moneroAddressInput = ""
        cardanoAddressInput = ""
        suiAddressInput = ""
        aptosAddressInput = ""
        tonAddressInput = ""
        icpAddressInput = ""
        nearAddressInput = ""
        polkadotAddressInput = ""
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
    func bindingForChainSelection(_ chainName: String) -> Binding<Bool> {
        Binding(
            get: { self.isSelectedChain(chainName) }, set: { isSelected in self.setSelectedChain(chainName, isEnabled: isSelected) }
        )
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
    private static let coinsByChain: [String: Coin] = [
        "Bitcoin": Coin.makeCustom(
            name: "Bitcoin", symbol: "BTC", coinGeckoId: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 64000),
        "Bitcoin Cash": Coin.makeCustom(
            name: "Bitcoin Cash", symbol: "BCH", coinGeckoId: "bitcoin-cash", chainName: "Bitcoin Cash",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 420),
        "Bitcoin SV": Coin.makeCustom(
            name: "Bitcoin SV", symbol: "BSV", coinGeckoId: "bitcoin-cash-sv", chainName: "Bitcoin SV",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 70),
        "Litecoin": Coin.makeCustom(
            name: "Litecoin", symbol: "LTC", coinGeckoId: "litecoin", chainName: "Litecoin", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 90),
        "Ethereum": Coin.makeCustom(
            name: "Ethereum", symbol: "ETH", coinGeckoId: "ethereum", chainName: "Ethereum", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 3500),
        "Ethereum Classic": Coin.makeCustom(
            name: "Ethereum Classic", symbol: "ETC", coinGeckoId: "ethereum-classic", chainName: "Ethereum Classic",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 30),
        "Arbitrum": Coin.makeCustom(
            name: "Arbitrum", symbol: "ARB", coinGeckoId: "arbitrum", chainName: "Arbitrum", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 1),
        "Optimism": Coin.makeCustom(
            name: "Optimism", symbol: "OP", coinGeckoId: "optimism", chainName: "Optimism", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0),
        "Solana": Coin.makeCustom(
            name: "Solana", symbol: "SOL", coinGeckoId: "solana", chainName: "Solana", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 150),
        "BNB Chain": Coin.makeCustom(
            name: "BNB", symbol: "BNB", coinGeckoId: "binancecoin", chainName: "BNB Chain", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 450),
        "Avalanche": Coin.makeCustom(
            name: "Avalanche", symbol: "AVAX", coinGeckoId: "avalanche-2", chainName: "Avalanche",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 35),
        "Hyperliquid": Coin.makeCustom(
            name: "Hyperliquid", symbol: "HYPE", coinGeckoId: "hyperliquid", chainName: "Hyperliquid",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 0),
        "Stellar": Coin.makeCustom(
            name: "Stellar", symbol: "XLM", coinGeckoId: "stellar", chainName: "Stellar", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0.12),
        "Dogecoin": Coin.makeCustom(
            name: "Dogecoin", symbol: "DOGE", coinGeckoId: "dogecoin", chainName: "Dogecoin", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0.15),
        "Cardano": Coin.makeCustom(
            name: "Cardano", symbol: "ADA", coinGeckoId: "cardano", chainName: "Cardano", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0.55),
        "Tron": Coin.makeCustom(
            name: "Tron", symbol: "TRX", coinGeckoId: "tron", chainName: "Tron", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0.12),
        "XRP Ledger": Coin.makeCustom(
            name: "XRP", symbol: "XRP", coinGeckoId: "ripple", chainName: "XRP Ledger", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 0.6),
        "Monero": Coin.makeCustom(
            name: "Monero", symbol: "XMR", coinGeckoId: "monero", chainName: "Monero", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 120),
        "Sui": Coin.makeCustom(
            name: "Sui", symbol: "SUI", coinGeckoId: "sui", chainName: "Sui", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 1.2),
        "Aptos": Coin.makeCustom(
            name: "Aptos", symbol: "APT", coinGeckoId: "aptos", chainName: "Aptos", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 8),
        "TON": Coin.makeCustom(
            name: "Toncoin", symbol: "TON", coinGeckoId: "the-open-network", chainName: "TON",
            tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 7),
        "Internet Computer": Coin.makeCustom(
            name: "Internet Computer", symbol: "ICP", coinGeckoId: "internet-computer",
            chainName: "Internet Computer", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUsd: 12),
        "NEAR": Coin.makeCustom(
            name: "NEAR Protocol", symbol: "NEAR", coinGeckoId: "near", chainName: "NEAR", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 6),
        "Polkadot": Coin.makeCustom(
            name: "Polkadot", symbol: "DOT", coinGeckoId: "polkadot", chainName: "Polkadot", tokenStandard: "Native",
            contractAddress: nil, amount: 0, priceUsd: 7),
    ]
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
