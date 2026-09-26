import Foundation
import SwiftUI

struct SetupChainSelectionDescriptor: Identifiable {
    let id: String
    let titleKey: String
    /// The chain's native symbol — one field, because the picker shows one.
    /// It was two, `symbol` and `gasTokenSymbol`, filled from the same
    /// catalog column through a `gasToken` parameter whose only call site
    /// compared that column with itself and so always passed nil.
    let symbol: String
    let chainName: String
    let artworkName: String?
    let color: Color
    let category: SetupChainCategory
    var title: String { localizedWalletFlowString(titleKey) }
    init(id: String, title: String, symbol: String, chainName: String, color: Color, category: SetupChainCategory) {
        self.id = id
        self.titleKey = title
        self.symbol = symbol
        self.chainName = chainName
        self.artworkName = Chain(id: id)?.entry?.artworkName
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
    /// The section a chain belongs to.
    ///
    /// Read `category` alone, which meant the catalog had to spell `"testnet"`
    /// there — a network-kind flag in a column of chain families, and the one
    /// reason `is_evm` could not be derived from `category`. Which network a
    /// row is is the registry's `isTestnet`.
    init(chain: ChainEntry) {
        if Chain(id: chain.id)?.isTestnet == true {
            self = .testnets
            return
        }
        switch chain.category {
        case .bitcoinFamily: self = .bitcoinFamily
        case .evmL1: self = .evmL1
        case .evmL2: self = .evmL2
        case .other: self = .other
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
    private static let chainSelectionDescriptors: [SetupChainSelectionDescriptor] = Chain.all.compactMap(\.entry).map { chain in
        SetupChainSelectionDescriptor(
            id: chain.id, title: chain.name, symbol: chain.gasTokenSymbol, chainName: chain.name,
            color: chain.color.color, category: SetupChainCategory(chain: chain)
        )
    }
    /// The picker's initial list, ordered by `popular_rank` in `chain-ui.toml`.
    private static let popularChainSelectionIds: [String] = Chain.all.compactMap(\.entry)
        .compactMap { chain in chain.popularRank.map { (rank: $0, id: chain.id) } }
        .sorted { $0.rank < $1.rank }
        .map(\.id)
    private static let nonPopularChainSelectionDescriptors = chainSelectionDescriptors.filter { d in
        !popularChainSelectionIds.contains(d.id)
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
    @State private var isShowingAllChainsPage: Bool = false
    @FocusState private var focusedSeedPhraseIndex: Int?
    // Two-column grid with generous spacing — the details page is now
    // dominated by chain selection, so each cell gets more room to breathe.
    private let chainSelectionColumns = [
        GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
    ]
    private let seedPhraseGridColumns = [
        GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6),
    ]
    init(store: AppState, draft: WalletImportDraft) {
        self.store = store
        self.draft = draft
        _setupPage = State(initialValue: draft.isEditingWallet ? .walletName : .details)
        _customSeedPhraseWordCountInput = State(initialValue: String(draft.selectedSeedPhraseWordCount))
    }
    private var isEditingWallet: Bool { draft.isEditingWallet }
    private var isCreateMode: Bool { draft.isCreateMode }
    private var isWatchAddressesImportMode: Bool { !isEditingWallet && !isCreateMode && draft.isWatchOnlyMode }
    private var usesSeedPhraseFlow: Bool { !isEditingWallet && !draft.isWatchOnlyMode }
    private var isPrivateKeyImportMode: Bool { draft.isPrivateKeyImportMode }
    private var usesWatchAddressesFlow: Bool { !isEditingWallet && draft.isWatchOnlyMode }
    private var pageCopy: WalletSetupPageCopy {
        setupPage.copy(
            copy,
            mode: WalletSetupMode(
                isEditingWallet: isEditingWallet, isCreateMode: isCreateMode,
                isPrivateKeyImport: isPrivateKeyImportMode))
    }
    private var setupTitle: String { pageCopy.title }
    private var setupSubtitle: String { pageCopy.subtitle }
    private var canContinueFromSecretStep: Bool {
        walletSetupCanContinueFromSecretStep(draft: draft, isImporting: store.walletImport.isBusy)
    }
    private var canContinueToBackupVerification: Bool {
        canContinueFromSecretStep
            && draft.walletPasswordValidationError == nil
            && !store.walletImport.isBusy
    }
    private var canSubmitFromPasswordStep: Bool {
        draft.walletPasswordValidationError == nil
            && store.canImportWallet
            && !store.walletImport.isBusy
    }
    private var canAdvanceFromDetailsPage: Bool {
        if usesSeedPhraseFlow { return !draft.selectedChainIds.isEmpty && !store.walletImport.isBusy }
        if usesWatchAddressesFlow { return !draft.selectedChainIds.isEmpty && !store.walletImport.isBusy }
        return store.canImportWallet && !store.walletImport.isBusy
    }
    /// What the primary button says on the page that submits rather than
    /// advances. Shared by every page that reaches the end of its flow.
    private var submitActionTitle: String {
        if isEditingWallet { return AppLocalization.string("import_flow.save_wallet") }
        if isCreateMode { return AppLocalization.string("import_flow.create_wallet") }
        return isWatchAddressesImportMode
            ? AppLocalization.string("import_flow.watch_addresses") : AppLocalization.string("import_flow.import_wallet")
    }
    private var canSubmitSetup: Bool { store.canImportWallet && !store.walletImport.isBusy }
    private var primaryActionTitle: String {
        let next = AppLocalization.string("import_flow.next")
        switch setupPage {
        case .seedPhrase:
            return next
        case .details:
            return (usesSeedPhraseFlow || usesWatchAddressesFlow) ? next : submitActionTitle
        case .password:
            if isCreateMode { return AppLocalization.string("import_flow.continue_to_backup_verification") }
            return advancesToWalletName ? next : submitActionTitle
        // Both advance to the wallet-name step rather than submitting; that
        // step performs the final submit.
        case .watchAddresses, .backupVerification:
            return advancesToWalletName ? next : submitActionTitle
        case .walletName:
            return submitActionTitle
        }
    }
    private var isPrimaryActionEnabled: Bool {
        switch setupPage {
        case .seedPhrase:
            return canContinueFromSecretStep
        case .details:
            return (usesSeedPhraseFlow || usesWatchAddressesFlow) ? canAdvanceFromDetailsPage : canSubmitSetup
        case .password:
            return isCreateMode ? canContinueToBackupVerification : (canSubmitFromPasswordStep || advancesToWalletName)
        case .watchAddresses:
            return canAdvanceFromWatchAddressesPage
        case .backupVerification, .walletName:
            return canSubmitSetup
        }
    }
    /// True when the current page should advance to the `.walletName` step
    /// rather than submitting directly.
    private var advancesToWalletName: Bool {
        guard !isEditingWallet else { return false }
        switch setupPage {
        case .password: return isCreateMode ? false : canSubmitFromPasswordStep
        case .backupVerification: return true
        case .watchAddresses: return canAdvanceFromWatchAddressesPage
        case .details, .seedPhrase, .walletName: return false
        }
    }
    private var canAdvanceFromWatchAddressesPage: Bool {
        store.canImportWallet && !store.walletImport.isBusy
    }
    private var popularChainSelectionDescriptors: [SetupChainSelectionDescriptor] {
        Self.popularChainSelectionIds.compactMap { id in
            Self.chainSelectionDescriptors.first { $0.id == id }
        }
    }
    private var selectedChainIdSet: Set<String> { Set(draft.selectedChainIds) }
    private var selectedChainCount: Int { draft.selectedChainIds.count }
    private var chainSelectionSummary: String {
        switch selectedChainCount {
        case 0: return AppLocalization.string("import_flow.no_chains_selected")
        case 1: return AppLocalization.string("import_flow.one_chain_selected")
        default: return AppLocalization.format("import_flow.multiple_chains_selected_format", selectedChainCount)
        }
    }
    @ViewBuilder
    private func watchedAddressEditor(text: Binding<String>) -> some View {
        TextEditor(text: text).textInputAutocapitalization(.never).autocorrectionDisabled().scrollContentBackground(.hidden).frame(
            minHeight: 88
        ).padding(10).spectraInputFieldStyle().foregroundStyle(Color.primary)
    }
    /// A flat card, not Liquid Glass: the setup screen stacks about ten of them.
    @ViewBuilder
    private func setupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(16).spectraBubbleFill().spectraCardFill()
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
            } else if draft.walletPasswordInput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text(AppLocalization.string("import_flow.wallet_password_success")).font(.caption).foregroundStyle(.green.opacity(0.9))
            }
        }
    }
    @ViewBuilder
    private func chainSelectionCard(_ descriptor: SetupChainSelectionDescriptor) -> some View {
        let isSelected = selectedChainIdSet.contains(descriptor.id)
        Button {
            spectraHaptic(.light)
            draft.toggleChainSelection(descriptor.id)
        } label: {
            // Two-column layout per cell: large badge + selection ring on the
            // left, title + symbol stacked vertically on the right. Gives
            // chain identity room to breathe now that chain selection owns
            // the details page.
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    CoinBadge(
                        artworkName: descriptor.artworkName, fallbackText: descriptor.symbol,
                        color: descriptor.color, size: 36
                    )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(descriptor.color)
                            .background(Circle().fill(Color.white.opacity(colorScheme == .light ? 1 : 0.88)))
                            .offset(x: 4, y: -4)
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
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10).padding(.horizontal, 12)
                .glassEffect(
                    .regular.tint(isSelected ? descriptor.color.opacity(0.14) : SpectraLayout.GlassTint.elevated),
                    in: .rect(cornerRadius: SpectraLayout.Radius.compact)
                ).overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: SpectraLayout.Radius.compact, style: .continuous)
                            .stroke(descriptor.color.opacity(0.9), lineWidth: 1.8)
                    }
                }
        }.buttonStyle(.plain).contentShape(Rectangle())
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
        entries: [String], assetDisplayName: String, validator: (String) -> Bool
    ) -> (message: String, color: Color) {
        let localizedAssetName = assetDisplayName
        if entries.isEmpty {
            return (AppLocalization.format("Enter one %@ address per line.", localizedAssetName), Color.secondary)
        }
        if !entries.allSatisfy(validator) {
            return (AppLocalization.format("Every line must contain a valid %@ address.", localizedAssetName), .red.opacity(0.9))
        }
        let count = entries.count
        let pluralSuffix = AppLocalization.locale.identifier.hasPrefix("en") && count != 1 ? "es" : ""
        return (
            AppLocalization.format("%lld valid %@ address%@ ready to import.", count, localizedAssetName, pluralSuffix),
            .green.opacity(0.9)
        )
    }
    @ViewBuilder
    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(setupTitle).font(.largeTitle.weight(.bold)).foregroundStyle(Color.primary)
                .lineLimit(3).minimumScaleFactor(0.7).allowsTightening(true).fixedSize(horizontal: false, vertical: true)
            Text(setupSubtitle).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
            if !draft.isWatchOnlyMode {
                setupCard { WalletSecretStep(store: store, draft: draft, showsBackupVerification: false) }
            }
        case .password:
            passwordPageContent
        case .backupVerification:
            WalletSecretStep(store: store, draft: draft, showsBackupVerification: true)
        case .walletName:
            walletNamePageContent
        }
    }
    /// Page-dominant chain selection. The chains step now owns the details
    /// page on its own (wallet name moved to the last step), so this card
    /// stretches its grid full-width and uses larger cells. The inline
    /// "Chains" header is replaced by a status capsule on the right; the
    /// page-level title above already names the step.
    @ViewBuilder
    private var chainSelectionCard: some View {
        let popularIDSet = Set(Self.popularChainSelectionIds)
        let extraSelectionCount = draft.selectedChainIds.filter { !popularIDSet.contains($0) }.count
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Text(AppLocalization.string("Popular chains"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(chainSelectionSummary).font(.caption.weight(.semibold)).foregroundStyle(
                        selectedChainCount == 0 ? Color.secondary : .orange
                    ).padding(.horizontal, 12).padding(.vertical, 7).glassEffect(
                        .regular.tint(
                            selectedChainCount == 0 ? SpectraLayout.GlassTint.elevated : Color.orange.opacity(0.12)),
                        in: .capsule)
                }
                LazyVGrid(columns: chainSelectionColumns, spacing: 8) {
                    ForEach(popularChainSelectionDescriptors) { descriptor in chainSelectionCard(descriptor) }
                }
                if !Self.nonPopularChainSelectionDescriptors.isEmpty {
                    Button {
                        chainSearchText = ""
                        isShowingAllChainsPage = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 36, height: 36)
                                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous))
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
            }
            .padding(20)
            .spectraCardFill()
            chainSelectionFooterNote
        }.tint(.orange)
        .navigationDestination(isPresented: $isShowingAllChainsPage) {
            AllChainsSelectionView(
                chainSearchText: $chainSearchText, descriptors: Self.chainSelectionDescriptors,
                selectedChainIds: selectedChainIdSet, toggleSelection: draft.toggleChainSelection,
                clearAllSelections: { for id in draft.selectedChainIds { draft.toggleChainSelection(id) } }
            )
        }
    }
    @ViewBuilder
    private var chainSelectionFooterNote: some View {
        if isEditingWallet {
            Text(copy.watchOnlyFixedMessage).font(.caption).foregroundStyle(.secondary)
        } else if draft.isWatchOnlyMode,
            draft.selectedChainIds.contains(where: { Chain(id: $0)?.supportsWatchOnlyImport == false })
        {
            // Show only for watch-only imports.
            // `only_monero_is_excluded_from_watch_only_import` checks that the
            // chain named in this copy matches the registry restriction.
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
    /// One watch-address field per storage slot, from the registry.
    ///
    /// Keyed by slot rather than by chain because that is what core reads: the
    /// EVM family shares Ethereum's, so one field serves all of them, and the
    /// first chain in catalog order owns the row.
    private var watchOnlyInputChains: [Chain] {
        var seenSlots = Set<String>()
        return Chain.mainnets.filter { chain in
            chain.supportsWatchOnlyImport && seenSlots.insert(chain.addressSlot).inserted
        }
    }

    /// Whether anything the user selected lands in this chain's slot.
    private func isSlotSelected(_ chain: Chain) -> Bool {
        draft.selectedChainIds.contains { Chain(id: $0)?.addressSlot == chain.addressSlot }
    }

    /// The chains sharing one slot, for the label on a field that serves more
    /// than one of them.
    private func chainsSharingSlot(with chain: Chain) -> [Chain] {
        Chain.mainnets.filter { $0.supportsWatchOnlyImport && $0.addressSlot == chain.addressSlot }
    }

    /// The address format to judge entries by, on the network the family is on.
    ///
    /// Bitcoin and Dogecoin each had this written out by hand, one with an
    /// inline lookup and one through `isValidDogecoinAddressForPolicy`, and the
    /// other sixteen chains judged against mainnet regardless of the selected
    /// network. It is the same rule for every chain.
    private func watchedAddressKind(for chain: Chain) -> String {
        Chain(id: store.selectedChainId(forFamily: chain.id))?.addressValidationKind
            ?? chain.addressValidationKind
    }

    @ViewBuilder
    private var watchAddressesInputsGroup: some View {
        ForEach(watchOnlyInputChains, id: \.self) { chain in
            if isSlotSelected(chain) {
                watchedAddressSlotSection(chain)
            }
        }
    }

    @ViewBuilder
    private func watchedAddressSlotSection(_ chain: Chain) -> some View {
        let sharing = chainsSharingSlot(with: chain)
        // Only the EVM family shares a slot — `address_slots_are_shared_across_the_evm_family_only`
        // is the test — so a shared row is an EVM row and says so rather than
        // listing twenty-two names in a title.
        let title = sharing.count > 1 ? "EVM" : chain.displayName
        let text = watchOnlyInputBinding(for: chain)
        let kind = watchedAddressKind(for: chain)
        let validation = watchedAddressValidationMessage(
            entries: draft.watchOnlyEntries(from: text.wrappedValue),
            assetDisplayName: title,
            validator: { validateAddress(request: AddressValidationRequest(kind: kind, value: $0)).isValid }
        )
        watchedAddressSection(
            title: title, text: text,
            caption: watchedAddressCaption(for: chain, sharing: sharing),
            validationMessage: validation.message, validationColor: validation.color
        )
        // A chain whose import takes an account xpub has a second form: one
        // xpub instead of a list of addresses. It is not an address, so it is
        // not in the table.
        if chain.acceptsAccountXpub {
            TextField("xpub... / zpub...", text: $draft.bitcoinXpubInput).textInputAutocapitalization(.never)
                .autocorrectionDisabled().padding(14).spectraInputFieldStyle().foregroundStyle(Color.primary)
        }
    }

    /// What a shared or special row needs to say beyond its title.
    private func watchedAddressCaption(for chain: Chain, sharing: [Chain]) -> String? {
        if chain.acceptsAccountXpub { return copy.bitcoinWatchCaption }
        guard sharing.count > 1 else { return nil }
        let selected = sharing.filter { draft.isSelected($0.id) }.map(\.displayName)
        guard !selected.isEmpty else { return nil }
        return AppLocalization.format("One address covers: %@.", selected.joined(separator: ", "))
    }

    private func watchOnlyInputBinding(for chain: Chain) -> Binding<String> {
        Binding(
            get: { self.draft.watchOnlyInputsByChainId[chain.id] ?? "" },
            set: { self.draft.watchOnlyInputsByChainId[chain.id] = $0 }
        )
    }

    @ViewBuilder
    private var watchAddressesEmptyNote: some View {
        if draft.selectedChainIds.isEmpty {
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
                        }.buttonStyle(.plain).accessibilityLabel(AppLocalization.string("Clear wallet name"))
                    }
                }.padding(14).spectraInputFieldStyle()
            }
        }
    }
    @ViewBuilder
    private var passwordPageContent: some View {
        setupCard { walletPasswordStepSection }
    }
    @ViewBuilder
    private var importStatusSection: some View {
        if let importError = store.walletImport.error {
            Text(importError).font(.footnote).foregroundStyle(.red.opacity(0.9))
        }
        if store.walletImport.isBusy {
            HStack(spacing: 10) {
                SpectraLoadingGlyph(size: 22, tint: .orange)
                Text(AppLocalization.string("import_flow.initializing_wallet_connections")).font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func performPrimaryAction() {
        // Special transition: entering backup verification needs a side
        // effect (challenge prep). Handle it before generic flow advance.
        if setupPage == .password && isCreateMode {
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
        let session = store.walletImport.id
        Task {
            guard store.walletImport.id == session else { return }
            await store.importWallet()
        }
    }
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    setupHeader
                    VStack(alignment: .leading, spacing: 16) {
                        pageContent
                        importStatusSection
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            setupBottomActionBar
        }
            .onChange(of: draft.mode) { _, _ in
                setupPage = draft.isEditingWallet ? .walletName : .details
            }.onChange(of: draft.selectedSeedPhraseWordCount) { _, newValue in
                customSeedPhraseWordCountInput = String(newValue)
            }
    }
    private func performBackNavigation() {
        if let prev = setupFlow.previous(before: setupPage) {
            withAnimation { setupPage = prev }
            return
        }
        if !isEditingWallet {
            store.walletImport.isPresented = false
        } else {
            store.cancelWalletImport()
            dismiss()
        }
    }
    private var canGoBack: Bool { setupFlow.previous(before: setupPage) != nil }
    private var setupBottomActionBar: some View {
        SpectraBottomActionBar {
            if canGoBack {
                Button(action: performBackNavigation) {
                    Text(AppLocalization.string("Back"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }.buttonStyle(.glass).controlSize(.large)
            }
            Button(action: performPrimaryAction) {
                Text(primaryActionTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }.buttonStyle(.glassProminent).controlSize(.large).disabled(!isPrimaryActionEnabled)
        }
    }
}
