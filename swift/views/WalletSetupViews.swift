import Foundation
import SwiftUI
struct SetupChainSelectionDescriptor: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let chainName: String
    let assetIdentifier: String?
    let color: Color
    let category: SetupChainCategory
    var title: String { localizedWalletFlowString(titleKey) }
    init(id: String, title: String, symbol: String, chainName: String, color: Color, category: SetupChainCategory) {
        self.id = id
        self.titleKey = title
        self.symbol = symbol
        self.chainName = chainName
        self.assetIdentifier = Coin.iconIdentifier(symbol: symbol, chainName: chainName)
        self.color = color
        self.category = category
    }
}
enum SetupChainCategory: String, CaseIterable, Identifiable {
    case bitcoinFamily
    case evmL1
    case evmL2
    case other
    case testnets
    var id: String { rawValue }
    var sectionTitle: String {
        switch self {
        case .bitcoinFamily: return AppLocalization.string("Bitcoin Family")
        case .evmL1: return AppLocalization.string("EVM Chains")
        case .evmL2: return AppLocalization.string("EVM L2s")
        case .other: return AppLocalization.string("Other Chains")
        case .testnets: return AppLocalization.string("Testnets")
        }
    }
}
/// SetupView currently takes both a `store: AppState` (read-only access to
/// app-wide state for chain/security info) and an `@Bindable` draft
/// (read/write for the in-progress import). The `store.x` vs `draft.x`
/// split is the read-only-vs-mutable boundary — never write to `store`
/// from inside this view, and never read draft-only state from `store`.
///
/// New views should follow `DiagnosticsExportsBrowserView`'s pattern (a
/// purpose-built `*Model` value type with closure callbacks for the few
/// store reads/writes the view needs) so the view's data dependency is
/// declared in the type instead of hidden in field accesses. SetupView
/// hasn't been migrated yet because its dependency surface is large.
struct SetupView: View {
    private static let chainSelectionDescriptors: [SetupChainSelectionDescriptor] = [
        SetupChainSelectionDescriptor(id: "bitcoin", title: "Bitcoin", symbol: "BTC", chainName: "Bitcoin", color: .orange, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "bitcoin-cash", title: "Bitcoin Cash", symbol: "BCH", chainName: "Bitcoin Cash", color: .orange, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "bitcoin-sv", title: "Bitcoin SV", symbol: "BSV", chainName: "Bitcoin SV", color: .orange, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "litecoin", title: "Litecoin", symbol: "LTC", chainName: "Litecoin", color: .gray, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "dogecoin", title: "Dogecoin", symbol: "DOGE", chainName: "Dogecoin", color: .brown, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "ethereum", title: "Ethereum", symbol: "ETH", chainName: "Ethereum", color: .blue, category: .evmL1),
        SetupChainSelectionDescriptor(id: "ethereum-classic", title: "Ethereum Classic", symbol: "ETC", chainName: "Ethereum Classic", color: .green, category: .evmL1),
        SetupChainSelectionDescriptor(id: "bnb-chain", title: "BNB Chain", symbol: "BNB", chainName: "BNB Chain", color: .yellow, category: .evmL1),
        SetupChainSelectionDescriptor(id: "avalanche", title: "Avalanche", symbol: "AVAX", chainName: "Avalanche", color: .red, category: .evmL1),
        SetupChainSelectionDescriptor(id: "hyperliquid", title: "Hyperliquid", symbol: "HYPE", chainName: "Hyperliquid", color: .mint, category: .evmL1),
        SetupChainSelectionDescriptor(id: "polygon", title: "Polygon", symbol: "POL", chainName: "Polygon", color: .purple, category: .evmL1),
        SetupChainSelectionDescriptor(id: "arbitrum", title: "Arbitrum", symbol: "ARB", chainName: "Arbitrum", color: .cyan, category: .evmL2),
        SetupChainSelectionDescriptor(id: "optimism", title: "Optimism", symbol: "OP", chainName: "Optimism", color: .red, category: .evmL2),
        SetupChainSelectionDescriptor(id: "base", title: "Base", symbol: "ETH", chainName: "Base", color: .blue, category: .evmL2),
        SetupChainSelectionDescriptor(id: "linea", title: "Linea", symbol: "ETH", chainName: "Linea", color: .blue, category: .evmL2),
        SetupChainSelectionDescriptor(id: "scroll", title: "Scroll", symbol: "ETH", chainName: "Scroll", color: .orange, category: .evmL2),
        SetupChainSelectionDescriptor(id: "blast", title: "Blast", symbol: "ETH", chainName: "Blast", color: .yellow, category: .evmL2),
        SetupChainSelectionDescriptor(id: "mantle", title: "Mantle", symbol: "MNT", chainName: "Mantle", color: .green, category: .evmL2),
        SetupChainSelectionDescriptor(id: "solana", title: "Solana", symbol: "SOL", chainName: "Solana", color: .purple, category: .other),
        SetupChainSelectionDescriptor(id: "tron", title: "Tron", symbol: "TRX", chainName: "Tron", color: .teal, category: .other),
        SetupChainSelectionDescriptor(id: "xrp-ledger", title: "XRP Ledger", symbol: "XRP", chainName: "XRP Ledger", color: .cyan, category: .other),
        SetupChainSelectionDescriptor(id: "cardano", title: "Cardano", symbol: "ADA", chainName: "Cardano", color: .indigo, category: .other),
        SetupChainSelectionDescriptor(id: "monero", title: "Monero", symbol: "XMR", chainName: "Monero", color: .indigo, category: .other),
        SetupChainSelectionDescriptor(id: "sui", title: "Sui", symbol: "SUI", chainName: "Sui", color: .mint, category: .other),
        SetupChainSelectionDescriptor(id: "aptos", title: "Aptos", symbol: "APT", chainName: "Aptos", color: .cyan, category: .other),
        SetupChainSelectionDescriptor(id: "ton", title: "TON", symbol: "TON", chainName: "TON", color: .blue, category: .other),
        SetupChainSelectionDescriptor(id: "internet-computer", title: "Internet Computer", symbol: "ICP", chainName: "Internet Computer", color: .indigo, category: .other),
        SetupChainSelectionDescriptor(id: "near", title: "NEAR", symbol: "NEAR", chainName: "NEAR", color: .indigo, category: .other),
        SetupChainSelectionDescriptor(id: "polkadot", title: "Polkadot", symbol: "DOT", chainName: "Polkadot", color: .pink, category: .other),
        SetupChainSelectionDescriptor(id: "stellar", title: "Stellar", symbol: "XLM", chainName: "Stellar", color: .teal, category: .other),
        SetupChainSelectionDescriptor(id: "bitcoin-gold", title: "Bitcoin Gold", symbol: "BTG", chainName: "Bitcoin Gold", color: .yellow, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "decred", title: "Decred", symbol: "DCR", chainName: "Decred", color: .teal, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "dash", title: "Dash", symbol: "DASH", chainName: "Dash", color: .blue, category: .bitcoinFamily),
        SetupChainSelectionDescriptor(id: "zcash", title: "Zcash", symbol: "ZEC", chainName: "Zcash", color: .yellow, category: .other),
        SetupChainSelectionDescriptor(id: "kaspa", title: "Kaspa", symbol: "KAS", chainName: "Kaspa", color: .mint, category: .other),
        SetupChainSelectionDescriptor(id: "bittensor", title: "Bittensor", symbol: "TAO", chainName: "Bittensor", color: .indigo, category: .other),
        SetupChainSelectionDescriptor(id: "sei", title: "Sei", symbol: "SEI", chainName: "Sei", color: .red, category: .evmL1),
        SetupChainSelectionDescriptor(id: "celo", title: "Celo", symbol: "CELO", chainName: "Celo", color: .yellow, category: .evmL1),
        SetupChainSelectionDescriptor(id: "cronos", title: "Cronos", symbol: "CRO", chainName: "Cronos", color: .blue, category: .evmL1),
        SetupChainSelectionDescriptor(id: "sonic", title: "Sonic", symbol: "S", chainName: "Sonic", color: .orange, category: .evmL1),
        SetupChainSelectionDescriptor(id: "berachain", title: "Berachain", symbol: "BERA", chainName: "Berachain", color: .brown, category: .evmL1),
        SetupChainSelectionDescriptor(id: "opbnb", title: "opBNB", symbol: "BNB", chainName: "opBNB", color: .yellow, category: .evmL2),
        SetupChainSelectionDescriptor(id: "zksync-era", title: "zkSync Era", symbol: "ETH", chainName: "zkSync Era", color: .indigo, category: .evmL2),
        SetupChainSelectionDescriptor(id: "unichain", title: "Unichain", symbol: "ETH", chainName: "Unichain", color: .pink, category: .evmL2),
        SetupChainSelectionDescriptor(id: "ink", title: "Ink", symbol: "ETH", chainName: "Ink", color: .purple, category: .evmL2),
        SetupChainSelectionDescriptor(id: "x-layer", title: "X Layer", symbol: "OKB", chainName: "X Layer", color: .gray, category: .evmL2),
        // Testnets — each is a first-class chain (the chain identity carries
        // the network flavor; there is no separate network parameter).
        SetupChainSelectionDescriptor(id: "bitcoin-testnet", title: "Bitcoin Testnet", symbol: "tBTC", chainName: "Bitcoin Testnet", color: .orange, category: .testnets),
        SetupChainSelectionDescriptor(id: "bitcoin-testnet4", title: "Bitcoin Testnet4", symbol: "tBTC", chainName: "Bitcoin Testnet4", color: .orange, category: .testnets),
        SetupChainSelectionDescriptor(id: "bitcoin-signet", title: "Bitcoin Signet", symbol: "sBTC", chainName: "Bitcoin Signet", color: .orange, category: .testnets),
        SetupChainSelectionDescriptor(id: "litecoin-testnet", title: "Litecoin Testnet", symbol: "tLTC", chainName: "Litecoin Testnet", color: .gray, category: .testnets),
        SetupChainSelectionDescriptor(id: "bitcoin-cash-testnet", title: "Bitcoin Cash Testnet", symbol: "tBCH", chainName: "Bitcoin Cash Testnet", color: .orange, category: .testnets),
        SetupChainSelectionDescriptor(id: "bitcoin-sv-testnet", title: "Bitcoin SV Testnet", symbol: "tBSV", chainName: "Bitcoin SV Testnet", color: .orange, category: .testnets),
        SetupChainSelectionDescriptor(id: "dogecoin-testnet", title: "Dogecoin Testnet", symbol: "tDOGE", chainName: "Dogecoin Testnet", color: .brown, category: .testnets),
        SetupChainSelectionDescriptor(id: "zcash-testnet", title: "Zcash Testnet", symbol: "tZEC", chainName: "Zcash Testnet", color: .yellow, category: .testnets),
        SetupChainSelectionDescriptor(id: "decred-testnet", title: "Decred Testnet", symbol: "tDCR", chainName: "Decred Testnet", color: .teal, category: .testnets),
        SetupChainSelectionDescriptor(id: "kaspa-testnet", title: "Kaspa Testnet", symbol: "tKAS", chainName: "Kaspa Testnet", color: .mint, category: .testnets),
        SetupChainSelectionDescriptor(id: "dash-testnet", title: "Dash Testnet", symbol: "tDASH", chainName: "Dash Testnet", color: .blue, category: .testnets),
        SetupChainSelectionDescriptor(id: "ethereum-sepolia", title: "Ethereum Sepolia", symbol: "SepoliaETH", chainName: "Ethereum Sepolia", color: .blue, category: .testnets),
        SetupChainSelectionDescriptor(id: "ethereum-hoodi", title: "Ethereum Hoodi", symbol: "HoodiETH", chainName: "Ethereum Hoodi", color: .blue, category: .testnets),
        SetupChainSelectionDescriptor(id: "arbitrum-sepolia", title: "Arbitrum Sepolia", symbol: "SepoliaARB", chainName: "Arbitrum Sepolia", color: .cyan, category: .testnets),
        SetupChainSelectionDescriptor(id: "optimism-sepolia", title: "Optimism Sepolia", symbol: "SepoliaOP", chainName: "Optimism Sepolia", color: .red, category: .testnets),
        SetupChainSelectionDescriptor(id: "base-sepolia", title: "Base Sepolia", symbol: "SepoliaETH", chainName: "Base Sepolia", color: .blue, category: .testnets),
        SetupChainSelectionDescriptor(id: "bnb-testnet", title: "BNB Chain Testnet", symbol: "tBNB", chainName: "BNB Chain Testnet", color: .yellow, category: .testnets),
        SetupChainSelectionDescriptor(id: "avalanche-fuji", title: "Avalanche Fuji", symbol: "FujiAVAX", chainName: "Avalanche Fuji", color: .red, category: .testnets),
        SetupChainSelectionDescriptor(id: "polygon-amoy", title: "Polygon Amoy", symbol: "AmoyPOL", chainName: "Polygon Amoy", color: .purple, category: .testnets),
        SetupChainSelectionDescriptor(id: "hyperliquid-testnet", title: "Hyperliquid Testnet", symbol: "tHYPE", chainName: "Hyperliquid Testnet", color: .mint, category: .testnets),
        SetupChainSelectionDescriptor(id: "ethereum-classic-mordor", title: "Ethereum Classic Mordor", symbol: "MordorETC", chainName: "Ethereum Classic Mordor", color: .green, category: .testnets),
        SetupChainSelectionDescriptor(id: "tron-nile", title: "Tron Nile", symbol: "NileTRX", chainName: "Tron Nile", color: .teal, category: .testnets),
        SetupChainSelectionDescriptor(id: "solana-devnet", title: "Solana Devnet", symbol: "DevSOL", chainName: "Solana Devnet", color: .purple, category: .testnets),
        SetupChainSelectionDescriptor(id: "xrp-testnet", title: "XRP Ledger Testnet", symbol: "tXRP", chainName: "XRP Ledger Testnet", color: .cyan, category: .testnets),
        SetupChainSelectionDescriptor(id: "stellar-testnet", title: "Stellar Testnet", symbol: "tXLM", chainName: "Stellar Testnet", color: .teal, category: .testnets),
        SetupChainSelectionDescriptor(id: "cardano-preprod", title: "Cardano Preprod", symbol: "tADA", chainName: "Cardano Preprod", color: .indigo, category: .testnets),
        SetupChainSelectionDescriptor(id: "sui-testnet", title: "Sui Testnet", symbol: "tSUI", chainName: "Sui Testnet", color: .mint, category: .testnets),
        SetupChainSelectionDescriptor(id: "aptos-testnet", title: "Aptos Testnet", symbol: "tAPT", chainName: "Aptos Testnet", color: .cyan, category: .testnets),
        SetupChainSelectionDescriptor(id: "ton-testnet", title: "TON Testnet", symbol: "tTON", chainName: "TON Testnet", color: .blue, category: .testnets),
        SetupChainSelectionDescriptor(id: "near-testnet", title: "NEAR Testnet", symbol: "tNEAR", chainName: "NEAR Testnet", color: .indigo, category: .testnets),
        SetupChainSelectionDescriptor(id: "polkadot-westend", title: "Polkadot Westend", symbol: "WND", chainName: "Polkadot Westend", color: .pink, category: .testnets),
        SetupChainSelectionDescriptor(id: "monero-stagenet", title: "Monero Stagenet", symbol: "sXMR", chainName: "Monero Stagenet", color: .indigo, category: .testnets),
    ]
    private static let popularChainSelectionIDs: [String] = [
        "bitcoin", "ethereum", "solana", "base", "arbitrum", "tron",
    ]
    private static let nonPopularChainSelectionDescriptors = chainSelectionDescriptors.filter { d in
        !popularChainSelectionIDs.contains(d.id)
    }
    /// Type alias kept for site-local readability — the underlying type
    /// lives in `SetupFlow.swift` so `SetupFlow` can reference it.
    private typealias SetupPage = WalletSetupPage

    /// Linear flow for the current mode. Drives the step counter, primary
    /// action routing, and back routing — replacing three separate switch
    /// statements that historically had to stay in sync.
    private var setupFlow: SetupFlow {
        if isEditingWallet { return .editWallet }
        if usesWatchAddressesFlow { return .watchOnly }
        if isCreateMode { return .createNewWallet }
        return .seedPhraseImport
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
    // Two-column grid with generous spacing — the details page is now
    // dominated by chain selection, so each cell gets more room to breathe.
    private let chainSelectionColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
    ]
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
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
    private var usesSeedPhraseFlow: Bool { !isEditingWallet && !draft.isWatchOnlyMode }
    private var isPrivateKeyImportMode: Bool { draft.isPrivateKeyImportMode }
    private var usesWatchAddressesFlow: Bool { !isEditingWallet && draft.isWatchOnlyMode }
    private var isShowingDetailsPage: Bool { setupPage == .details }
    private var isShowingSeedPhrasePage: Bool { setupPage == .seedPhrase }
    private var isShowingWatchAddressesPage: Bool { setupPage == .watchAddresses }
    private var isShowingPasswordPage: Bool { setupPage == .password }
    private var isShowingBackupVerificationPage: Bool { setupPage == .backupVerification }
    private var isShowingAdvancedPage: Bool { setupPage == .advanced }
    private var isShowingWalletNamePage: Bool { setupPage == .walletName }
    private var isSimpleSetupSelected: Bool { draft.setupModeChoice == .simple }
    private var setupTitle: String {
        if isShowingWalletNamePage { return AppLocalization.string("import_flow.name_your_wallet") }
        if isShowingBackupVerificationPage { return copy.backupVerificationTitle }
        if isShowingAdvancedPage { return copy.advancedTitle }
        if isShowingPasswordPage { return AppLocalization.string("import_flow.wallet_password_title") }
        if isShowingWatchAddressesPage { return copy.watchAddressesTitle }
        if isShowingSeedPhrasePage {
            if isCreateMode { return copy.recordSeedPhraseTitle }
            return isPrivateKeyImportMode ? copy.enterPrivateKeyTitle : copy.enterSeedPhraseTitle
        }
        if isEditingWallet { return copy.editWalletTitle }
        // Details page is now chains-only: name the page after its purpose.
        if isShowingDetailsPage && !isEditingWallet {
            return AppLocalization.string("import_flow.choose_chains")
        }
        if isCreateMode { return copy.createWalletTitle }
        return isWatchAddressesImportMode ? copy.watchAddressesTitle : copy.importWalletTitle
    }
    private var setupSubtitle: String {
        if isShowingWalletNamePage { return AppLocalization.string("import_flow.wallet_name_hint") }
        if isShowingBackupVerificationPage { return copy.backupVerificationSubtitle }
        if isShowingAdvancedPage { return copy.advancedSubtitle }
        if isShowingPasswordPage { return AppLocalization.string("import_flow.wallet_password_subtitle") }
        if isShowingWatchAddressesPage { return copy.watchAddressesSubtitle }
        if isShowingSeedPhrasePage {
            if isPrivateKeyImportMode { return copy.privateKeySubtitle }
            return isCreateMode ? copy.saveRecoveryPhraseSubtitle : copy.enterRecoveryPhraseSubtitle
        }
        if isEditingWallet { return copy.editWalletSubtitle }
        // Chain-selection-only details page subtitle.
        if isShowingDetailsPage && !isEditingWallet {
            return AppLocalization.string("import_flow.choose_chains_subtitle")
        }
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
        // Password / watchAddresses / backupVerification advance to the new
        // wallet-name step instead of submitting; the wallet-name step
        // performs the final submit.
        if !isShowingWalletNamePage && advancesToWalletName { return AppLocalization.string("import_flow.next") }
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
        if isShowingPasswordPage { return canSubmitFromPasswordStep || advancesToWalletName }
        if isShowingWatchAddressesPage { return canAdvanceFromWatchAddressesPage }
        return store.canImportWallet && !store.isImportingWallet
    }
    /// True when the current page should advance to the new `.walletName`
    /// step (the new last-step) rather than submitting directly.
    private var advancesToWalletName: Bool {
        if isEditingWallet { return false }
        if isShowingPasswordPage && !isCreateMode { return canSubmitFromPasswordStep }
        if isShowingBackupVerificationPage { return true }
        if isShowingWatchAddressesPage { return canAdvanceFromWatchAddressesPage }
        return false
    }
    private var canAdvanceFromWatchAddressesPage: Bool {
        store.canImportWallet && !store.isImportingWallet
    }
    private var popularChainSelectionDescriptors: [SetupChainSelectionDescriptor] {
        Self.popularChainSelectionIDs.compactMap { id in
            Self.chainSelectionDescriptors.first { $0.id == id }
        }
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
            // Two-column layout per cell: large badge + selection ring on the
            // left, title + symbol stacked vertically on the right. Gives
            // chain identity room to breathe now that chain selection owns
            // the details page.
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    CoinBadge(
                        assetIdentifier: descriptor.assetIdentifier, fallbackText: descriptor.symbol,
                        color: descriptor.color, size: 52
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(descriptor.color)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .light ? 1 : 0.88)))
                            .offset(x: 6, y: -6)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(descriptor.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                .padding(.vertical, 14).padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
                        isSelected ? descriptor.color.opacity(0.14) : Color.white.opacity(colorScheme == .light ? 0.55 : 0.04))
                ).overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(
                        isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(colorScheme == .light ? 0.10 : 0.07),
                        lineWidth: isSelected ? 1.8 : 1)
                )
        }.buttonStyle(.plain).contentShape(Rectangle())
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
            if let seedPhraseLengthWarning = draft.seedPhraseLengthWarning {
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
            }.frame(maxWidth: .infinity, minHeight: 56).background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    isSelected ? Color.orange : Color.white.opacity(colorScheme == .light ? 0.55 : 0.05))
            ).overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
                    isSelected ? Color.orange : Color.primary.opacity(colorScheme == .light ? 0.10 : 0.07),
                    lineWidth: isSelected ? 0 : 1)
            )
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
    @ViewBuilder
    private func numberedSeedPhraseRow(index: Int, text: String? = nil, isInvalidWord: Bool = false) -> some View {
        let validEntryColor: Color = colorScheme == .light ? Color.black.opacity(0.85) : .white
        let isFocused = focusedSeedPhraseIndex == index
        let borderColor: Color? =
            isInvalidWord ? Color.red.opacity(0.85)
            : (isFocused ? Color.orange.opacity(0.7) : nil)
        HStack(spacing: 6) {
            Text("\(index + 1)").font(.caption2.weight(.heavy)).foregroundStyle(.orange.opacity(0.95))
                .frame(minWidth: 18, alignment: .trailing).monospacedDigit()
            if let text {
                Text(text).font(.footnote.weight(.medium)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: seedPhraseBinding(for: index)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.footnote.weight(.medium)).foregroundStyle(isInvalidWord ? .red.opacity(0.95) : validEntryColor).focused(
                        $focusedSeedPhraseIndex, equals: index
                    ).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, minHeight: 38).padding(.horizontal, 10).padding(.vertical, 8).spectraInputFieldStyle(
            borderColor: borderColor)
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
        // Derived directly from `setupFlow`. Side routes (e.g. `.advanced`)
        // return `nil` from the flow and surface as the first step — the
        // counter is hidden on those pages anyway.
        setupFlow.stepPosition(for: setupPage) ?? (1, max(1, setupFlow.pages.count))
    }
    /// Single rendering entry point for the page body. Replaces six
    /// separate `*PageSection` properties stacked in a VStack, each with
    /// their own internal "if isShowing<X>" gate that could drift out of
    /// sync with the page enum. A switch over `setupPage` makes the page
    /// → content map structural — adding a page is one new case rather
    /// than "remember to add the section *and* gate it correctly inside."
    @ViewBuilder
    private var pageContent: some View {
        switch setupPage {
        case .details:
            if !isEditingWallet { chainSelectionCard }
        case .watchAddresses:
            if !isEditingWallet, draft.isWatchOnlyMode { watchAddressesPageContent }
        case .seedPhrase:
            if !draft.isWatchOnlyMode { seedPhrasePageContent }
        case .password:
            passwordPageContent
        case .backupVerification:
            backupVerificationStepSection
        case .walletName:
            walletNamePageContent
        case .advanced:
            advancedPageContent
        }
    }
    /// Page-dominant chain selection. The chains step now owns the details
    /// page on its own (wallet name moved to the last step), so this card
    /// stretches its grid full-width and uses larger cells. The inline
    /// "Chains" header is replaced by a status capsule on the right; the
    /// page-level title above already names the step.
    @ViewBuilder
    private var chainSelectionCard: some View {
        let popularIDSet = Set(Self.popularChainSelectionIDs)
        let extraSelectionCount = draft.selectedChainNames.filter { name in
            !Self.chainSelectionDescriptors.contains(where: { $0.chainName == name && popularIDSet.contains($0.id) })
        }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text(AppLocalization.string("Popular chains"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(chainSelectionSummary).font(.caption.weight(.semibold)).foregroundStyle(
                    selectedChainCount == 0 ? Color.primary.opacity(0.68) : .orange
                ).padding(.horizontal, 12).padding(.vertical, 7).background(
                    Capsule(style: .continuous).fill(
                        selectedChainCount == 0
                            ? Color.white.opacity(colorScheme == .light ? 0.55 : 0.08) : Color.orange.opacity(0.12))
                )
            }
            LazyVGrid(columns: chainSelectionColumns, spacing: 12) {
                ForEach(popularChainSelectionDescriptors) { descriptor in chainSelectionCard(descriptor) }
            }
            if !Self.nonPopularChainSelectionDescriptors.isEmpty {
                Button {
                    chainSearchText = ""
                    isShowingAllChainsSheet = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 36, height: 36)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AppLocalization.format("Browse all %lld chains", Self.chainSelectionDescriptors.count))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Text(AppLocalization.string("Search by name or symbol.")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if extraSelectionCount > 0 {
                            Text("+\(extraSelectionCount)").font(.caption.weight(.bold)).foregroundStyle(.white).padding(
                                .horizontal, 10
                            ).padding(.vertical, 4).background(Capsule(style: .continuous).fill(.orange))
                        }
                        Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 14).padding(.vertical, 12).spectraInputFieldStyle()
                }.buttonStyle(.plain)
            }
            chainSelectionFooterNote
        }.tint(.orange)
        .sheet(isPresented: $isShowingAllChainsSheet) {
            AllChainsSelectionView(
                chainSearchText: $chainSearchText, descriptors: Self.chainSelectionDescriptors,
                selectedChainNames: selectedChainNameSet, toggleSelection: draft.toggleChainSelection,
                clearAllSelections: { for name in draft.selectedChainNames { draft.toggleChainSelection(name) } }
            )
        }
    }
    @ViewBuilder
    private var chainSelectionFooterNote: some View {
        if isEditingWallet {
            Text(copy.watchOnlyFixedMessage).font(.caption).foregroundStyle(.secondary)
        } else if draft.wantsMonero {
            Text(copy.moneroWatchUnsupportedMessage).font(.caption).foregroundStyle(.orange.opacity(0.9))
        }
    }
    /// Page-level rendering contract: callers (the `pageContent` switch)
    /// have already verified the page is active. These `*PageContent`
    /// properties don't re-check `isShowing<X>` — they just render.
    @ViewBuilder
    private var watchAddressesPageContent: some View {
        setupCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy.addressesToWatchTitle).font(.headline).foregroundStyle(Color.primary)
                Text(copy.addressesToWatchSubtitle).font(.subheadline).foregroundStyle(.secondary)
                watchAddressesInputsGroup
                watchAddressesEmptyNote
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
    private var walletNamePageContent: some View {
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
                    if !draft.walletName.isEmpty {
                        Button { draft.walletName = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("Clear wallet name")
                    }
                }.padding(14).spectraInputFieldStyle()
            }
        }
    }
    @ViewBuilder
    private var seedPhrasePageContent: some View {
        setupCard {
            VStack(alignment: .leading, spacing: 14) { walletSecretStepSection }
        }
    }
    @ViewBuilder
    private var passwordPageContent: some View {
        setupCard { walletPasswordStepSection }
    }
    @ViewBuilder
    private var advancedPageContent: some View {
        setupCard { derivationAdvancedContent }
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
        // Special transition: entering backup verification needs a side
        // effect (challenge prep). Handle it before generic flow advance.
        if isShowingPasswordPage && isCreateMode {
            draft.prepareBackupVerificationChallenge()
            withAnimation { setupPage = .backupVerification }
            return
        }
        // Generic linear advance. `nil` from `next` means we're on the
        // last page — submit instead of routing.
        if let nextPage = setupFlow.next(after: setupPage) {
            withAnimation { setupPage = nextPage }
            return
        }
        Task { await store.importWallet() }
    }
    @ViewBuilder
    private var derivationAdvancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(advancedDescriptionText).font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
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
        AppLocalization.string("Control the derivation path used for each selected chain. Pick a testnet from the chain list to use a testnet wallet.")
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
        AppLocalization.string("Adjust derivation paths.")
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
        Text(copy.seedPhraseEntryHelp).font(.footnote).foregroundStyle(.secondary)
        seedPhraseEntryHeader
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 8) {
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
        seedPhraseDisplayHeader
        LazyVGrid(columns: seedPhraseGridColumns, spacing: 8) {
            ForEach(draft.seedPhraseWords.indices, id: \.self) { index in
                numberedSeedPhraseRow(index: index, text: draft.seedPhraseWords[index])
            }
        }
    }
    @ViewBuilder
    private var seedPhraseEntryHeader: some View {
        let filled = draft.seedPhraseWords.count
        let total = draft.selectedSeedPhraseWordCount
        let isComplete = filled >= total && draft.invalidSeedWords.isEmpty && draft.seedPhraseValidationError == nil
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
    private var privateKeyImportSection: some View {
        importSecretModePicker
        privateKeyImportFields
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
                    walletFlowLocalizedFormat(
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
                    pageContent
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
        // `.advanced` is a side route — it returns to the seed-phrase page
        // it branched from, regardless of flow.
        if isShowingAdvancedPage {
            withAnimation { setupPage = .seedPhrase }
            return
        }
        // Generic linear back-step. `nil` from `previous` means we're on
        // the first page — escape the importer entirely.
        if let prev = setupFlow.previous(before: setupPage) {
            withAnimation { setupPage = prev }
            return
        }
        if !isEditingWallet {
            store.isShowingWalletImporter = false
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
            }.glassEffect(.regular.tint(.white.opacity(0.04)), in: Rectangle())
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

