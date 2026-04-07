import SwiftUI
import Combine

enum WalletDraftMode {
    case importExisting
    case createNew
    case editExisting
}

enum WalletSecretImportMode: String, CaseIterable, Identifiable {
    case seedPhrase = "Seed Phrase"
    case privateKey = "Private Key"

    var id: String { rawValue }

    var localizedTitle: String {
        String(localized: LocalizedStringResource(stringLiteral: rawValue))
    }
}

@MainActor
final class WalletImportDraft: ObservableObject {
    private static let supportedPrivateKeyChainNames: [String] = [
        "Bitcoin",
        "Bitcoin Cash",
        "Bitcoin SV",
        "Litecoin",
        "Dogecoin",
        "Ethereum",
        "Ethereum Classic",
        "Arbitrum",
        "Optimism",
        "BNB Chain",
        "Avalanche",
        "Hyperliquid",
        "Tron",
        "Solana",
        "Cardano",
        "Stellar",
        "XRP Ledger",
        "Sui",
        "Aptos",
        "TON",
        "Internet Computer",
        "NEAR",
        "Polkadot",
    ]
    private static let supportedPrivateKeyChainNameSet = Set(supportedPrivateKeyChainNames)

    @Published var mode: WalletDraftMode = .importExisting {
        didSet { refreshSelectionState() }
    }
    @Published var isEditingWallet: Bool = false {
        didSet { refreshSelectionState() }
    }
    @Published var walletName: String = ""
    @Published var seedPhrase: String = ""
    @Published var walletPassword: String = ""
    @Published var walletPasswordConfirmation: String = ""
    @Published var secretImportMode: WalletSecretImportMode = .seedPhrase {
        didSet { refreshSelectionState() }
    }
    @Published var privateKeyInput: String = ""
    @Published var seedDerivationPreset: SeedDerivationPreset = .standard
    @Published var usesCustomDerivationPaths: Bool = true
    @Published var seedDerivationPaths: SeedDerivationPaths = .defaults
    @Published var seedPhraseEntries: [String] = Array(repeating: "", count: 12)
    @Published var selectedSeedPhraseWordCount: Int = 12 {
        didSet {
            resizeSeedPhraseEntries(to: selectedSeedPhraseWordCount)
        }
    }
    @Published var isWatchOnlyMode: Bool = false {
        didSet { refreshSelectionState() }
    }
    @Published var bitcoinAddressInput: String = ""
    @Published var bitcoinXPubInput: String = ""
    @Published var bitcoinCashAddressInput: String = ""
    @Published var bitcoinSVAddressInput: String = ""
    @Published var litecoinAddressInput: String = ""
    @Published var dogecoinAddressInput: String = ""
    @Published var ethereumAddressInput: String = ""
    @Published var tronAddressInput: String = ""
    @Published var solanaAddressInput: String = ""
    @Published var stellarAddressInput: String = ""
    @Published var xrpAddressInput: String = ""
    @Published var moneroAddressInput: String = ""
    @Published var cardanoAddressInput: String = ""
    @Published var suiAddressInput: String = ""
    @Published var aptosAddressInput: String = ""
    @Published var tonAddressInput: String = ""
    @Published var icpAddressInput: String = ""
    @Published var nearAddressInput: String = ""
    @Published var polkadotAddressInput: String = ""
    @Published var selectedChainNamesStorage: [String] = [] {
        didSet { refreshSelectionState() }
    }
    @Published var backupVerificationWordIndices: [Int] = []
    @Published var backupVerificationEntries: [String] = []
    private(set) var selectedCoins: [Coin] = []
    private(set) var selectedChainNames: [String] = []

    var isCreateMode: Bool {
        mode == .createNew
    }

    var isPrivateKeyImportMode: Bool {
        mode == .importExisting && !isEditingWallet && !isWatchOnlyMode && secretImportMode == .privateKey
    }

    var supportedPrivateKeyChainNames: [String] {
        Self.supportedPrivateKeyChainNames
    }

    var unsupportedPrivateKeyChainNames: [String] {
        selectedChainNames.filter { !Self.supportedPrivateKeyChainNameSet.contains($0) }
    }

    private var allowsMultipleChainSelection: Bool {
        !isEditingWallet && !isWatchOnlyMode && !isPrivateKeyImportMode
    }

    var wantsBitcoin: Bool { get { isSelectedChain("Bitcoin") } set { setSelectedChain("Bitcoin", isEnabled: newValue) } }
    var wantsBitcoinCash: Bool { get { isSelectedChain("Bitcoin Cash") } set { setSelectedChain("Bitcoin Cash", isEnabled: newValue) } }
    var wantsBitcoinSV: Bool { get { isSelectedChain("Bitcoin SV") } set { setSelectedChain("Bitcoin SV", isEnabled: newValue) } }
    var wantsLitecoin: Bool { get { isSelectedChain("Litecoin") } set { setSelectedChain("Litecoin", isEnabled: newValue) } }
    var wantsEthereum: Bool { get { isSelectedChain("Ethereum") } set { setSelectedChain("Ethereum", isEnabled: newValue) } }
    var wantsEthereumClassic: Bool { get { isSelectedChain("Ethereum Classic") } set { setSelectedChain("Ethereum Classic", isEnabled: newValue) } }
    var wantsArbitrum: Bool { get { isSelectedChain("Arbitrum") } set { setSelectedChain("Arbitrum", isEnabled: newValue) } }
    var wantsOptimism: Bool { get { isSelectedChain("Optimism") } set { setSelectedChain("Optimism", isEnabled: newValue) } }
    var wantsSolana: Bool { get { isSelectedChain("Solana") } set { setSelectedChain("Solana", isEnabled: newValue) } }
    var wantsBNBChain: Bool { get { isSelectedChain("BNB Chain") } set { setSelectedChain("BNB Chain", isEnabled: newValue) } }
    var wantsAvalanche: Bool { get { isSelectedChain("Avalanche") } set { setSelectedChain("Avalanche", isEnabled: newValue) } }
    var wantsHyperliquid: Bool { get { isSelectedChain("Hyperliquid") } set { setSelectedChain("Hyperliquid", isEnabled: newValue) } }
    var wantsDogecoin: Bool { get { isSelectedChain("Dogecoin") } set { setSelectedChain("Dogecoin", isEnabled: newValue) } }
    var wantsCardano: Bool { get { isSelectedChain("Cardano") } set { setSelectedChain("Cardano", isEnabled: newValue) } }
    var wantsTron: Bool { get { isSelectedChain("Tron") } set { setSelectedChain("Tron", isEnabled: newValue) } }
    var wantsStellar: Bool { get { isSelectedChain("Stellar") } set { setSelectedChain("Stellar", isEnabled: newValue) } }
    var wantsXRP: Bool { get { isSelectedChain("XRP Ledger") } set { setSelectedChain("XRP Ledger", isEnabled: newValue) } }
    var wantsMonero: Bool { get { isSelectedChain("Monero") } set { setSelectedChain("Monero", isEnabled: newValue) } }
    var wantsSui: Bool { get { isSelectedChain("Sui") } set { setSelectedChain("Sui", isEnabled: newValue) } }
    var wantsAptos: Bool { get { isSelectedChain("Aptos") } set { setSelectedChain("Aptos", isEnabled: newValue) } }
    var wantsTON: Bool { get { isSelectedChain("TON") } set { setSelectedChain("TON", isEnabled: newValue) } }
    var wantsICP: Bool { get { isSelectedChain("Internet Computer") } set { setSelectedChain("Internet Computer", isEnabled: newValue) } }
    var wantsNear: Bool { get { isSelectedChain("NEAR") } set { setSelectedChain("NEAR", isEnabled: newValue) } }
    var wantsPolkadot: Bool { get { isSelectedChain("Polkadot") } set { setSelectedChain("Polkadot", isEnabled: newValue) } }

    var seedPhraseValidationError: String? {
        guard !isEditingWallet else { return nil }
        guard isSeedPhraseEntryComplete else { return nil }
        guard invalidSeedWords.isEmpty else { return nil }
        return BitcoinWalletEngine.validateMnemonic(seedPhrase, expectedWordCount: selectedSeedPhraseWordCount)
    }

    var hasValidSeedPhraseChecksum: Bool {
        guard !isEditingWallet else { return false }
        guard isSeedPhraseEntryComplete else { return false }
        guard invalidSeedWords.isEmpty else { return false }
        return BitcoinWalletEngine.hasValidMnemonicChecksum(
            seedPhrase,
            expectedWordCount: selectedSeedPhraseWordCount
        )
    }

    var seedPhraseWords: [String] {
        BitcoinWalletEngine.normalizedMnemonicWords(from: seedPhrase)
    }

    var normalizedWalletPassword: String? {
        let trimmed = walletPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var walletPasswordValidationError: String? {
        let password = walletPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmation = walletPasswordConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty || !confirmation.isEmpty else { return nil }
        guard password.count >= 4 else {
            return "Wallet password must be at least 4 characters, or leave it blank."
        }
        guard password == confirmation else {
            return "Wallet password confirmation does not match."
        }
        return nil
    }

    var invalidSeedWords: [String] {
        guard !isEditingWallet else { return [] }
        return BitcoinWalletEngine.invalidEnglishWords(in: seedPhrase)
    }

    var seedPhraseLengthWarning: String? {
        guard !isEditingWallet else { return nil }
        let count = selectedSeedPhraseWordCount
        guard count > 0 else { return "Seed phrase length must be at least 1 word." }
        if count < 12 {
            return "Seed phrase is too short. Use at least 12 words."
        }
        if !BitcoinWalletEngine.validMnemonicWordCounts.contains(count) {
            return "Non-standard length selected. BIP-39 standard lengths are 12, 15, 18, 21, or 24 words."
        }
        return nil
    }

    private var isSeedPhraseEntryComplete: Bool {
        guard selectedSeedPhraseWordCount > 0 else { return false }
        guard seedPhraseEntries.count >= selectedSeedPhraseWordCount else { return false }
        return seedPhraseEntries
            .prefix(selectedSeedPhraseWordCount)
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init() {
        refreshSelectionState()
    }

    var selectableDerivationChains: [SeedDerivationChain] {
        let selectedChainNameSet = Set(selectedChainNames)
        return SeedDerivationChain.allCases.filter { selectedChainNameSet.contains($0.rawValue) }
    }

    func applyDerivationPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool? = nil) {
        seedDerivationPreset = preset
        seedDerivationPaths = .applyingPreset(
            preset,
            keepCustomEnabled: keepCustomEnabled ?? seedDerivationPaths.isCustomEnabled
        )
    }

    func watchOnlyEntries(from rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canImportWallet: Bool {
        let hasChains = !selectedChainNames.isEmpty
        let shouldValidateWatchAddresses = isWatchOnlyMode
        let requiresEVMWatchAddress = wantsEthereum || wantsEthereumClassic || wantsArbitrum || wantsOptimism || wantsBNBChain || wantsAvalanche || wantsHyperliquid
        let bitcoinAddressEntries = shouldValidateWatchAddresses && wantsBitcoin ? watchOnlyEntries(from: bitcoinAddressInput) : []
        let trimmedBitcoinXPub = shouldValidateWatchAddresses && wantsBitcoin
            ? bitcoinXPubInput.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let bitcoinCashAddressEntries = shouldValidateWatchAddresses && wantsBitcoinCash ? watchOnlyEntries(from: bitcoinCashAddressInput) : []
        let bitcoinSVAddressEntries = shouldValidateWatchAddresses && wantsBitcoinSV ? watchOnlyEntries(from: bitcoinSVAddressInput) : []
        let litecoinAddressEntries = shouldValidateWatchAddresses && wantsLitecoin ? watchOnlyEntries(from: litecoinAddressInput) : []
        let dogecoinAddressEntries = shouldValidateWatchAddresses && wantsDogecoin ? watchOnlyEntries(from: dogecoinAddressInput) : []
        let ethereumAddressEntries = shouldValidateWatchAddresses && requiresEVMWatchAddress ? watchOnlyEntries(from: ethereumAddressInput) : []
        let tronAddressEntries = shouldValidateWatchAddresses && wantsTron ? watchOnlyEntries(from: tronAddressInput) : []
        let solanaAddressEntries = shouldValidateWatchAddresses && wantsSolana ? watchOnlyEntries(from: solanaAddressInput) : []
        let stellarAddressEntries = shouldValidateWatchAddresses && wantsStellar ? watchOnlyEntries(from: stellarAddressInput) : []
        let xrpAddressEntries = shouldValidateWatchAddresses && wantsXRP ? watchOnlyEntries(from: xrpAddressInput) : []
        let moneroAddressEntries = shouldValidateWatchAddresses && wantsMonero ? watchOnlyEntries(from: moneroAddressInput) : []
        let cardanoAddressEntries = shouldValidateWatchAddresses && wantsCardano ? watchOnlyEntries(from: cardanoAddressInput) : []
        let suiAddressEntries = shouldValidateWatchAddresses && wantsSui ? watchOnlyEntries(from: suiAddressInput) : []
        let aptosAddressEntries = shouldValidateWatchAddresses && wantsAptos ? watchOnlyEntries(from: aptosAddressInput) : []
        let tonAddressEntries = shouldValidateWatchAddresses && wantsTON ? watchOnlyEntries(from: tonAddressInput) : []
        let icpAddressEntries = shouldValidateWatchAddresses && wantsICP ? watchOnlyEntries(from: icpAddressInput) : []
        let nearAddressEntries = shouldValidateWatchAddresses && wantsNear ? watchOnlyEntries(from: nearAddressInput) : []
        let polkadotAddressEntries = shouldValidateWatchAddresses && wantsPolkadot ? watchOnlyEntries(from: polkadotAddressInput) : []
        let hasValidBitcoinAddress = !wantsBitcoin
            || !isWatchOnlyMode
            || bitcoinAddressEntries.allSatisfy(isLikelyValidBitcoinAddress)
            || BitcoinWalletEngine.isLikelyExtendedPublicKey(trimmedBitcoinXPub)
        let hasValidDogecoinAddress = !wantsDogecoin
            || !isWatchOnlyMode
            || dogecoinAddressEntries.allSatisfy { AddressValidation.isValidDogecoinAddress($0) }
        let hasValidBitcoinCashAddress = !wantsBitcoinCash
            || !isWatchOnlyMode
            || bitcoinCashAddressEntries.allSatisfy(AddressValidation.isValidBitcoinCashAddress)
        let hasValidBitcoinSVAddress = !wantsBitcoinSV
            || !isWatchOnlyMode
            || bitcoinSVAddressEntries.allSatisfy(AddressValidation.isValidBitcoinSVAddress)
        let hasValidLitecoinAddress = !wantsLitecoin
            || !isWatchOnlyMode
            || litecoinAddressEntries.allSatisfy(AddressValidation.isValidLitecoinAddress)
        let hasValidEthereumAddress = !requiresEVMWatchAddress
            || !isWatchOnlyMode
            || ethereumAddressEntries.allSatisfy(AddressValidation.isValidEthereumAddress)
        let hasValidTronAddress = !wantsTron
            || !isWatchOnlyMode
            || tronAddressEntries.allSatisfy(AddressValidation.isValidTronAddress)
        let hasValidSolanaAddress = !wantsSolana
            || !isWatchOnlyMode
            || solanaAddressEntries.allSatisfy(AddressValidation.isValidSolanaAddress)
        let hasValidStellarAddress = !wantsStellar
            || !isWatchOnlyMode
            || stellarAddressEntries.allSatisfy(AddressValidation.isValidStellarAddress)
        let hasValidXRPAddress = !wantsXRP
            || !isWatchOnlyMode
            || xrpAddressEntries.allSatisfy(AddressValidation.isValidXRPAddress)
        let hasValidMoneroAddress = !wantsMonero
            || moneroAddressEntries.allSatisfy(AddressValidation.isValidMoneroAddress)
        let hasValidCardanoAddress = !wantsCardano
            || !isWatchOnlyMode
            || cardanoAddressEntries.allSatisfy(AddressValidation.isValidCardanoAddress)
        let hasValidSuiAddress = !wantsSui
            || !isWatchOnlyMode
            || suiAddressEntries.allSatisfy(AddressValidation.isValidSuiAddress)
        let hasValidAptosAddress = !wantsAptos
            || !isWatchOnlyMode
            || aptosAddressEntries.allSatisfy(AddressValidation.isValidAptosAddress)
        let hasValidTONAddress = !wantsTON
            || !isWatchOnlyMode
            || tonAddressEntries.allSatisfy(AddressValidation.isValidTONAddress)
        let hasValidICPAddress = !wantsICP
            || !isWatchOnlyMode
            || icpAddressEntries.allSatisfy(AddressValidation.isValidICPAddress)
        let hasValidNearAddress = !wantsNear
            || !isWatchOnlyMode
            || nearAddressEntries.allSatisfy(AddressValidation.isValidNearAddress)
        let hasValidPolkadotAddress = !wantsPolkadot
            || !isWatchOnlyMode
            || polkadotAddressEntries.allSatisfy(AddressValidation.isValidPolkadotAddress)
        let hasValidPrivateKey = !isPrivateKeyImportMode || PrivateKeyHex.isLikely(privateKeyInput)
        let supportsSelectedMode = (!wantsMonero || !isWatchOnlyMode)
            && (!isPrivateKeyImportMode || unsupportedPrivateKeyChainNames.isEmpty)
            && (!isPrivateKeyImportMode || selectedChainNames.count == 1)
            && (!isWatchOnlyMode || selectedChainNames.count == 1)
        let hasWatchOnlyAddresses = !isWatchOnlyMode || (
            (!wantsBitcoin || !bitcoinAddressEntries.isEmpty || !trimmedBitcoinXPub.isEmpty)
                && (!wantsBitcoinCash || !bitcoinCashAddressEntries.isEmpty)
                && (!wantsBitcoinSV || !bitcoinSVAddressEntries.isEmpty)
                && (!wantsLitecoin || !litecoinAddressEntries.isEmpty)
                && (!wantsDogecoin || !dogecoinAddressEntries.isEmpty)
                && (!requiresEVMWatchAddress || !ethereumAddressEntries.isEmpty)
                && (!wantsTron || !tronAddressEntries.isEmpty)
                && (!wantsSolana || !solanaAddressEntries.isEmpty)
                && (!wantsStellar || !stellarAddressEntries.isEmpty)
                && (!wantsXRP || !xrpAddressEntries.isEmpty)
                && (!wantsMonero || !moneroAddressEntries.isEmpty)
                && (!wantsCardano || !cardanoAddressEntries.isEmpty)
                && (!wantsSui || !suiAddressEntries.isEmpty)
                && (!wantsAptos || !aptosAddressEntries.isEmpty)
                && (!wantsTON || !tonAddressEntries.isEmpty)
                && (!wantsICP || !icpAddressEntries.isEmpty)
                && (!wantsNear || !nearAddressEntries.isEmpty)
                && (!wantsPolkadot || !polkadotAddressEntries.isEmpty)
        )
        if isEditingWallet {
            return !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isCreateMode {
            let hasValidSeedPhrase = seedPhraseWords.count == selectedSeedPhraseWordCount
                && seedPhraseValidationError == nil
                && invalidSeedWords.isEmpty
                && hasValidSeedPhraseChecksum
            return hasChains && hasValidSeedPhrase && isBackupVerificationComplete
        }
        let hasValidSeedPhrase = seedPhraseWords.count == selectedSeedPhraseWordCount
            && seedPhraseValidationError == nil
            && invalidSeedWords.isEmpty
            && hasValidSeedPhraseChecksum
        let isBackupVerified = isWatchOnlyMode || !requiresBackupVerification || isBackupVerificationComplete
        return hasChains
            && hasValidBitcoinAddress
            && hasValidBitcoinCashAddress
            && hasValidBitcoinSVAddress
            && hasValidLitecoinAddress
            && hasValidDogecoinAddress
            && hasValidEthereumAddress
            && hasValidTronAddress
            && hasValidSolanaAddress
            && hasValidStellarAddress
            && hasValidXRPAddress
            && hasValidMoneroAddress
            && hasValidCardanoAddress
            && hasValidSuiAddress
            && hasValidAptosAddress
            && hasValidTONAddress
            && hasValidICPAddress
            && hasValidNearAddress
            && hasValidPolkadotAddress
            && hasWatchOnlyAddresses
            && supportsSelectedMode
            && (isWatchOnlyMode || isPrivateKeyImportMode || hasValidSeedPhrase)
            && hasValidPrivateKey
            && isBackupVerified
    }

    var requiresBackupVerification: Bool {
        isCreateMode
    }

    var isBackupVerificationComplete: Bool {
        guard requiresBackupVerification else { return true }
        guard backupVerificationWordIndices.count == backupVerificationEntries.count,
              !backupVerificationWordIndices.isEmpty else {
            return false
        }
        let words = seedPhraseWords
        guard words.count == selectedSeedPhraseWordCount else { return false }
        for (offset, index) in backupVerificationWordIndices.enumerated() {
            guard words.indices.contains(index) else { return false }
            let expected = words[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let entered = backupVerificationEntries[offset].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if expected != entered {
                return false
            }
        }
        return true
    }

    var backupVerificationPromptLabel: String {
        guard requiresBackupVerification else { return "" }
        if backupVerificationWordIndices.isEmpty {
            return "Generate a backup verification challenge to continue."
        }
        return ""
    }

    var unsupportedSelectedChainNames: [String] {
        selectedChainNames.filter { !ChainBackendRegistry.supportsBalanceRefresh(for: $0) }
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
        // Force reset in import mode to avoid regenerating words during reset.
        mode = .importExisting
        isEditingWallet = false
        reset()
        mode = .createNew
        isWatchOnlyMode = false
        regenerateSeedPhrase()
    }

    func configureForEditing(wallet: ImportedWallet) {
        // Force reset in import mode to avoid create-mode seed regeneration side effects.
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
        seedPhraseEntries = Array(repeating: "", count: 12)
        selectedSeedPhraseWordCount = 12
        isWatchOnlyMode = false
        bitcoinAddressInput = ""
        bitcoinXPubInput = ""
        bitcoinCashAddressInput = ""
        bitcoinSVAddressInput = ""
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
            get: { self.isSelectedChain(chainName) },
            set: { isSelected in
                self.setSelectedChain(chainName, isEnabled: isSelected)
            }
        )
    }

    func toggleChainSelection(_ chainName: String) {
        setSelectedChain(chainName, isEnabled: !isSelectedChain(chainName))
    }

    private func isSelectedChain(_ chainName: String) -> Bool {
        selectedChainNamesStorage.contains(chainName)
    }

    private func setSelectedChain(_ chainName: String, isEnabled: Bool) {
        if isEnabled {
            if allowsMultipleChainSelection {
                if !selectedChainNamesStorage.contains(chainName) {
                    selectedChainNamesStorage.append(chainName)
                }
            } else {
                selectedChainNamesStorage = [chainName]
            }
        } else {
            selectedChainNamesStorage.removeAll { $0 == chainName }
        }
    }

    private func refreshSelectionState() {
        let effectiveChainNames = allowsMultipleChainSelection
            ? selectedChainNamesStorage
            : Array(selectedChainNamesStorage.prefix(1))
        selectedChainNames = effectiveChainNames
        selectedCoins = effectiveChainNames.compactMap(Self.coin(for:))
    }

    private static func coin(for chainName: String) -> Coin? {
        switch chainName {
        case "Bitcoin":
            return Coin(name: "Bitcoin", symbol: "BTC", marketDataID: "1", coinGeckoID: "bitcoin", chainName: "Bitcoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 64000, mark: "B", color: .orange)
        case "Bitcoin Cash":
            return Coin(name: "Bitcoin Cash", symbol: "BCH", marketDataID: "1831", coinGeckoID: "bitcoin-cash", chainName: "Bitcoin Cash", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 420, mark: "BC", color: .orange)
        case "Bitcoin SV":
            return Coin(name: "Bitcoin SV", symbol: "BSV", marketDataID: "3602", coinGeckoID: "bitcoin-cash-sv", chainName: "Bitcoin SV", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 70, mark: "BS", color: .orange)
        case "Litecoin":
            return Coin(name: "Litecoin", symbol: "LTC", marketDataID: "2", coinGeckoID: "litecoin", chainName: "Litecoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 90, mark: "L", color: .gray)
        case "Ethereum":
            return Coin(name: "Ethereum", symbol: "ETH", marketDataID: "1027", coinGeckoID: "ethereum", chainName: "Ethereum", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 3500, mark: "E", color: .blue)
        case "Ethereum Classic":
            return Coin(name: "Ethereum Classic", symbol: "ETC", marketDataID: "1321", coinGeckoID: "ethereum-classic", chainName: "Ethereum Classic", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 30, mark: "EC", color: .green)
        case "Arbitrum":
            return Coin(name: "Arbitrum", symbol: "ARB", marketDataID: "0", coinGeckoID: "arbitrum", chainName: "Arbitrum", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 1, mark: "AR", color: .cyan)
        case "Optimism":
            return Coin(name: "Optimism", symbol: "OP", marketDataID: "0", coinGeckoID: "optimism", chainName: "Optimism", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "OP", color: .red)
        case "Solana":
            return Coin(name: "Solana", symbol: "SOL", marketDataID: "5426", coinGeckoID: "solana", chainName: "Solana", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 150, mark: "S", color: .purple)
        case "BNB Chain":
            return Coin(name: "BNB", symbol: "BNB", marketDataID: "1839", coinGeckoID: "binancecoin", chainName: "BNB Chain", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 450, mark: "BN", color: .yellow)
        case "Avalanche":
            return Coin(name: "Avalanche", symbol: "AVAX", marketDataID: "5805", coinGeckoID: "avalanche-2", chainName: "Avalanche", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 35, mark: "AV", color: .red)
        case "Hyperliquid":
            return Coin(name: "Hyperliquid", symbol: "HYPE", marketDataID: "0", coinGeckoID: "hyperliquid", chainName: "Hyperliquid", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0, mark: "HY", color: .mint)
        case "Stellar":
            return Coin(name: "Stellar", symbol: "XLM", marketDataID: "512", coinGeckoID: "stellar", chainName: "Stellar", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0.12, mark: "XL", color: .teal)
        case "Dogecoin":
            return Coin(name: "Dogecoin", symbol: "DOGE", marketDataID: "74", coinGeckoID: "dogecoin", chainName: "Dogecoin", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0.15, mark: "D", color: .brown)
        case "Cardano":
            return Coin(name: "Cardano", symbol: "ADA", marketDataID: "2010", coinGeckoID: "cardano", chainName: "Cardano", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0.55, mark: "A", color: .indigo)
        case "Tron":
            return Coin(name: "Tron", symbol: "TRX", marketDataID: "1958", coinGeckoID: "tron", chainName: "Tron", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0.12, mark: "T", color: .teal)
        case "XRP Ledger":
            return Coin(name: "XRP", symbol: "XRP", marketDataID: "52", coinGeckoID: "ripple", chainName: "XRP Ledger", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 0.6, mark: "X", color: .cyan)
        case "Monero":
            return Coin(name: "Monero", symbol: "XMR", marketDataID: "328", coinGeckoID: "monero", chainName: "Monero", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 120, mark: "M", color: .indigo)
        case "Sui":
            return Coin(name: "Sui", symbol: "SUI", marketDataID: "20947", coinGeckoID: "sui", chainName: "Sui", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 1.2, mark: "SU", color: .mint)
        case "Aptos":
            return Coin(name: "Aptos", symbol: "APT", marketDataID: "21794", coinGeckoID: "aptos", chainName: "Aptos", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 8, mark: "AP", color: .cyan)
        case "TON":
            return Coin(name: "Toncoin", symbol: "TON", marketDataID: "11419", coinGeckoID: "the-open-network", chainName: "TON", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 7, mark: "TN", color: .blue)
        case "Internet Computer":
            return Coin(name: "Internet Computer", symbol: "ICP", marketDataID: "2416", coinGeckoID: "internet-computer", chainName: "Internet Computer", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 12, mark: "IC", color: .indigo)
        case "NEAR":
            return Coin(name: "NEAR Protocol", symbol: "NEAR", marketDataID: "6535", coinGeckoID: "near", chainName: "NEAR", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 6, mark: "N", color: .indigo)
        case "Polkadot":
            return Coin(name: "Polkadot", symbol: "DOT", marketDataID: "6636", coinGeckoID: "polkadot", chainName: "Polkadot", tokenStandard: "Native", contractAddress: nil, amount: 0, priceUSD: 7, mark: "P", color: .pink)
        default:
            return nil
        }
    }

    func regenerateSeedPhrase() {
        guard isCreateMode else { return }
        guard BitcoinWalletEngine.validMnemonicWordCounts.contains(selectedSeedPhraseWordCount) else {
            seedPhrase = ""
            seedPhraseEntries = Array(repeating: "", count: selectedSeedPhraseWordCount)
            backupVerificationWordIndices = []
            backupVerificationEntries = []
            return
        }
        let generatedPhrase = (try? BitcoinWalletEngine.generateMnemonic(wordCount: selectedSeedPhraseWordCount)) ?? ""
        seedPhrase = generatedPhrase
        let generatedWords = BitcoinWalletEngine.normalizedMnemonicWords(from: generatedPhrase)
        var entries = Array(repeating: "", count: selectedSeedPhraseWordCount)
        for (index, word) in generatedWords.enumerated() where index < entries.count {
            entries[index] = word
        }
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

        let pastedWords = BitcoinWalletEngine.normalizedMnemonicWords(from: newValue)
        if pastedWords.count > 1 {
            var updatedEntries = seedPhraseEntries
            for offset in 0 ..< pastedWords.count {
                let destinationIndex = index + offset
                guard updatedEntries.indices.contains(destinationIndex) else { break }
                updatedEntries[destinationIndex] = pastedWords[offset]
            }
            seedPhraseEntries = updatedEntries
            syncSeedPhraseFromEntries()
            return
        }

        let normalizedValue = newValue
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            indices.insert(Int.random(in: 0 ..< selectedSeedPhraseWordCount))
        }
        let sortedIndices = indices.sorted()
        backupVerificationWordIndices = sortedIndices
        backupVerificationEntries = Array(repeating: "", count: sortedIndices.count)
    }

    func updateBackupVerificationEntry(at index: Int, with value: String) {
        guard backupVerificationEntries.indices.contains(index) else { return }
        backupVerificationEntries[index] = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        let normalizedEntries = seedPhraseEntries.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if normalizedEntries != seedPhraseEntries {
            seedPhraseEntries = normalizedEntries
            return
        }

        let combinedSeedPhrase = normalizedEntries
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if seedPhrase != combinedSeedPhrase {
            seedPhrase = combinedSeedPhrase
        }
        if !backupVerificationWordIndices.isEmpty, !isBackupVerificationComplete {
            backupVerificationEntries = Array(repeating: "", count: backupVerificationWordIndices.count)
        }
    }

    private func isLikelyValidBitcoinAddress(_ address: String) -> Bool {
        AddressValidation.isValidBitcoinAddress(address, networkMode: .mainnet)
            || AddressValidation.isValidBitcoinAddress(address, networkMode: .testnet)
            || AddressValidation.isValidBitcoinAddress(address, networkMode: .signet)
    }
}
