// Core-state pattern (for `wallets`, `transactions`, `addressBook`):
// These `@Published` arrays are *mirrors* of canonical storage that lives in
// Rust (`core/src/app_state/store.rs`, exposed via `storeWallets*` /
// `storeTransactions*` / `storeAddressBook*` UniFFI functions). SwiftUI
// observes the mirrors directly (`appState.$wallets` etc.), but every mutation
// MUST go through the helpers in `AppState+CoreStateStore.swift`
// (`setWallets`, `appendWallet`, `upsertWallet`, `removeWallet(id:)`,
// `setTransactions`, `prependTransaction`, `removeTransactions(forWalletID:)`,
// `setAddressBook`, `prependAddressBookEntry`, `removeAddressBookEntry(byID:)`)
// so Rust stays in sync. Do NOT assign `self.wallets = …` etc. outside those
// helpers — search for `self.wallets = ` should show only the helper file.
import Foundation
import SwiftUI
import Combine
import os
import UIKit
#if canImport(Network)
import Network
#endif
@MainActor
class AppState: ObservableObject {
    enum HistoryPaging {
        static let endpointBatchSize = 20
        static let uiPageSize = 10
    }
    static let persistenceEncoder = JSONEncoder()
    static let persistenceDecoder = JSONDecoder()
    static let diagnosticsBundleEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    static let diagnosticsBundleDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    static let exportFilenameTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    static let operationalLogTimestampFormatter = ISO8601DateFormatter()
    // Nested enums (ResetScope, TimeoutError, SeedPhraseRevealError, BackgroundSyncProfile)
    // moved to Shell/AppStateTypes.swift via `extension AppState`.
    let logger = Logger(subsystem: "com.spectra.wallet", category: "dogecoin")
    let balanceTelemetryLogger = Logger(subsystem: "com.spectra.wallet", category: "balance.telemetry")
    // Rust-owned backing store for side-effect-free scalar UI state. @Published
    // replaced by computed props that delegate here and emit objectWillChange.
    let shellState = AppShellState()
    private var transactionRebuildTask: Task<Void, Never>?
    @Published var transactions: [TransactionRecord] = [] {
        didSet {
            transactionRevision &+= 1
            let old = lastObservedTransactions
            lastObservedTransactions = transactions
            if !suppressSideEffects {
                persistTransactionsDelta(from: old, to: transactions)
                transactionRebuildTask?.cancel()
                transactionRebuildTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000) // 30ms debounce
                    guard !Task.isCancelled, let self else { return }
                    self.rebuildTransactionDerivedState()
                }
            }}}
    @Published var normalizedHistoryIndex: [NormalizedHistoryEntry] = [] {
        didSet { normalizedHistoryRevision &+= 1 }}
    @Published private(set) var transactionRevision: UInt64 = 0
    @Published private(set) var normalizedHistoryRevision: UInt64 = 0
    var cachedTransactionByID: [UUID: TransactionRecord] = [:]
    var cachedFirstActivityDateByWalletID: [String: Date] = [:]
    var lastNormalizedHistorySignature: Int?
    var suppressSideEffects = false
    var lastObservedTransactions: [TransactionRecord] = []
    // Nested value types (event records, persisted-store schemas, keypool / diagnostic
    // structs and associated typealiases) moved to Shell/AppStateTypes.swift.
    @Published var wallets: [ImportedWallet] = [] {
        didSet { walletsRevision &+= 1 }}
    @Published private(set) var walletsRevision: UInt64 = 0
    // Rust-owned derived caches. These used to be stored `cached*` dicts/arrays/sets
    // on AppState. Storage now lives in `core/src/app_state/caches.rs` behind UniFFI;
    // Swift exposes computed-var facades with identical names/types so call sites
    // (whole-assignment, subscript read, `[k] = v`, `[k] = nil`, `.remove(k)`,
    // `.insert(k)`) keep compiling. Setters bump `cachesRevision` so SwiftUI refreshes.
    @Published private(set) var cachesRevision: UInt64 = 0
    private var cacheBatchDepth: Int = 0
    private func bumpCachesRevision() {
        guard cacheBatchDepth == 0 else { return }
        cachesRevision &+= 1
    }
    func batchCacheUpdates(_ block: () -> Void) {
        cacheBatchDepth += 1
        block()
        cacheBatchDepth -= 1
        if cacheBatchDepth == 0 { cachesRevision &+= 1 }
    }
    // Skip objectWillChange when the value is unchanged — avoids redundant SwiftUI invalidation.
    @inline(__always) private func notifyIfChanged<T: Equatable>(_ current: T, _ newValue: T, apply: () -> Void) {
        guard newValue != current else { return }
        objectWillChange.send()
        apply()
    }
    var cachedWalletByID: [String: ImportedWallet] {
        get { cachesGetWalletById() }
        set { cachesReplaceWalletById(entries: newValue); bumpCachesRevision() }
    }
    var cachedWalletByIDString: [String: ImportedWallet] {
        get { cachesGetWalletByIdString() }
        set { cachesReplaceWalletByIdString(entries: newValue); bumpCachesRevision() }
    }
    var cachedIncludedPortfolioWallets: [ImportedWallet] {
        get { cachesGetIncludedPortfolioWallets() }
        set { cachesReplaceIncludedPortfolioWallets(entries: newValue); bumpCachesRevision() }
    }
    var cachedIncludedPortfolioHoldings: [Coin] {
        get { cachesGetIncludedPortfolioHoldings() }
        set { cachesReplaceIncludedPortfolioHoldings(entries: newValue); bumpCachesRevision() }
    }
    var cachedIncludedPortfolioHoldingsBySymbol: [String: [Coin]] {
        get { cachesGetIncludedPortfolioHoldingsBySymbol() }
        set { cachesReplaceIncludedPortfolioHoldingsBySymbol(entries: newValue); bumpCachesRevision() }
    }
    var cachedUniqueWalletPriceRequestCoins: [Coin] {
        get { cachesGetUniqueWalletPriceRequestCoins() }
        set { cachesReplaceUniqueWalletPriceRequestCoins(entries: newValue); bumpCachesRevision() }
    }
    var cachedPortfolio: [Coin] {
        get { cachesGetPortfolio() }
        set { cachesReplacePortfolio(entries: newValue); bumpCachesRevision() }
    }
    var cachedAvailableSendCoinsByWalletID: [String: [Coin]] {
        get { cachesGetAvailableSendCoinsByWalletId() }
        set { cachesReplaceAvailableSendCoinsByWalletId(entries: newValue); bumpCachesRevision() }
    }
    var cachedAvailableReceiveCoinsByWalletID: [String: [Coin]] {
        get { cachesGetAvailableReceiveCoinsByWalletId() }
        set { cachesReplaceAvailableReceiveCoinsByWalletId(entries: newValue); bumpCachesRevision() }
    }
    var cachedAvailableReceiveChainsByWalletID: [String: [String]] {
        get { cachesGetAvailableReceiveChainsByWalletId() }
        set { cachesReplaceAvailableReceiveChainsByWalletId(entries: newValue); bumpCachesRevision() }
    }
    var cachedSendEnabledWallets: [ImportedWallet] {
        get { cachesGetSendEnabledWallets() }
        set { cachesReplaceSendEnabledWallets(entries: newValue); bumpCachesRevision() }
    }
    var cachedReceiveEnabledWallets: [ImportedWallet] {
        get { cachesGetReceiveEnabledWallets() }
        set { cachesReplaceReceiveEnabledWallets(entries: newValue); bumpCachesRevision() }
    }
    var cachedRefreshableChainNames: Set<String> {
        get { Set(cachesGetRefreshableChainNames()) }
        set { cachesReplaceRefreshableChainNames(entries: Array(newValue)); bumpCachesRevision() }
    }
    var cachedSigningMaterialWalletIDs: Set<String> {
        get { Set(cachesGetSigningMaterialWalletIds()) }
        set { cachesReplaceSigningMaterialWalletIds(entries: Array(newValue)); bumpCachesRevision() }
    }
    var cachedPrivateKeyBackedWalletIDs: Set<String> {
        get { Set(cachesGetPrivateKeyBackedWalletIds()) }
        set { cachesReplacePrivateKeyBackedWalletIds(entries: Array(newValue)); bumpCachesRevision() }
    }
    var cachedPasswordProtectedWalletIDs: Set<String> {
        get { Set(cachesGetPasswordProtectedWalletIds()) }
        set { cachesReplacePasswordProtectedWalletIds(entries: Array(newValue)); bumpCachesRevision() }
    }
    var cachedSecretDescriptorsByWalletID: [String: WalletRustSecretMaterialDescriptor] {
        get { cachesGetSecretDescriptorsByWalletId() }
        set { cachesReplaceSecretDescriptorsByWalletId(entries: newValue); bumpCachesRevision() }
    }
    let importDraft = WalletImportDraft()
    var importError: String? { get { shellState.getImportError() } set { notifyIfChanged(importError, newValue) { shellState.setImportError(value: newValue) } } }
    var isImportingWallet: Bool { get { shellState.getIsImportingWallet() } set { notifyIfChanged(isImportingWallet, newValue) { shellState.setIsImportingWallet(value: newValue) } } }
    var isShowingWalletImporter: Bool { get { shellState.getIsShowingWalletImporter() } set { notifyIfChanged(isShowingWalletImporter, newValue) { shellState.setIsShowingWalletImporter(value: newValue) } } }
    var isShowingSendSheet: Bool { get { shellState.getIsShowingSendSheet() } set { notifyIfChanged(isShowingSendSheet, newValue) { shellState.setIsShowingSendSheet(value: newValue) } } }
    var isShowingReceiveSheet: Bool { get { shellState.getIsShowingReceiveSheet() } set { notifyIfChanged(isShowingReceiveSheet, newValue) { shellState.setIsShowingReceiveSheet(value: newValue) } } }
    @Published var walletPendingDeletion: ImportedWallet?
    var editingWalletID: String? {
        get { shellState.getEditingWalletId() }
        set { notifyIfChanged(editingWalletID, newValue) { shellState.setEditingWalletId(value: newValue) } }
    }
    var sendWalletID: String { get { shellState.getSendWalletId() } set { notifyIfChanged(sendWalletID, newValue) { shellState.setSendWalletId(value: newValue) } } }
    var sendHoldingKey: String { get { shellState.getSendHoldingKey() } set { notifyIfChanged(sendHoldingKey, newValue) { shellState.setSendHoldingKey(value: newValue) } } }
    var sendAmount: String { get { shellState.getSendAmount() } set { notifyIfChanged(sendAmount, newValue) { shellState.setSendAmount(value: newValue) } } }
    var sendAddress: String { get { shellState.getSendAddress() } set { notifyIfChanged(sendAddress, newValue) { shellState.setSendAddress(value: newValue) } } }
    var sendError: String? { get { shellState.getSendError() } set { notifyIfChanged(sendError, newValue) { shellState.setSendError(value: newValue) } } }
    var sendDestinationRiskWarning: String? { get { shellState.getSendDestinationRiskWarning() } set { notifyIfChanged(sendDestinationRiskWarning, newValue) { shellState.setSendDestinationRiskWarning(value: newValue) } } }
    var sendDestinationInfoMessage: String? { get { shellState.getSendDestinationInfoMessage() } set { notifyIfChanged(sendDestinationInfoMessage, newValue) { shellState.setSendDestinationInfoMessage(value: newValue) } } }
    var isCheckingSendDestinationBalance: Bool { get { shellState.getIsCheckingSendDestinationBalance() } set { notifyIfChanged(isCheckingSendDestinationBalance, newValue) { shellState.setIsCheckingSendDestinationBalance(value: newValue) } } }
    var pendingHighRiskSendReasons: [String] {
        get { shellState.getPendingHighRiskSendReasons() }
        set { notifyIfChanged(pendingHighRiskSendReasons, newValue) { shellState.setPendingHighRiskSendReasons(value: newValue) } }
    }
    var isShowingHighRiskSendConfirmation: Bool { get { shellState.getIsShowingHighRiskSendConfirmation() } set { notifyIfChanged(isShowingHighRiskSendConfirmation, newValue) { shellState.setIsShowingHighRiskSendConfirmation(value: newValue) } } }
    var sendVerificationNotice: String? { get { shellState.getSendVerificationNotice() } set { notifyIfChanged(sendVerificationNotice, newValue) { shellState.setSendVerificationNotice(value: newValue) } } }
    var sendVerificationNoticeIsWarning: Bool { get { shellState.getSendVerificationNoticeIsWarning() } set { notifyIfChanged(sendVerificationNoticeIsWarning, newValue) { shellState.setSendVerificationNoticeIsWarning(value: newValue) } } }
    var receiveWalletID: String { get { shellState.getReceiveWalletId() } set { notifyIfChanged(receiveWalletID, newValue) { shellState.setReceiveWalletId(value: newValue) } } }
    var receiveChainName: String { get { shellState.getReceiveChainName() } set { notifyIfChanged(receiveChainName, newValue) { shellState.setReceiveChainName(value: newValue) } } }
    var receiveHoldingKey: String { get { shellState.getReceiveHoldingKey() } set { notifyIfChanged(receiveHoldingKey, newValue) { shellState.setReceiveHoldingKey(value: newValue) } } }
    var receiveResolvedAddress: String { get { shellState.getReceiveResolvedAddress() } set { notifyIfChanged(receiveResolvedAddress, newValue) { shellState.setReceiveResolvedAddress(value: newValue) } } }
    var isResolvingReceiveAddress: Bool { get { shellState.getIsResolvingReceiveAddress() } set { notifyIfChanged(isResolvingReceiveAddress, newValue) { shellState.setIsResolvingReceiveAddress(value: newValue) } } }
    @Published var selectedMainTab: MainAppTab = .home
    var isAppLocked: Bool { get { shellState.getIsAppLocked() } set { notifyIfChanged(isAppLocked, newValue) { shellState.setIsAppLocked(value: newValue) } } }
    var appLockError: String? { get { shellState.getAppLockError() } set { notifyIfChanged(appLockError, newValue) { shellState.setAppLockError(value: newValue) } } }
    var isPreparingEthereumReplacementContext: Bool { get { shellState.getIsPreparingEthereumReplacementContext() } set { notifyIfChanged(isPreparingEthereumReplacementContext, newValue) { shellState.setIsPreparingEthereumReplacementContext(value: newValue) } } }
    var isPreparingEthereumSend: Bool { get { shellState.getIsPreparingEthereumSend() } set { notifyIfChanged(isPreparingEthereumSend, newValue) { shellState.setIsPreparingEthereumSend(value: newValue) } } }
    var isPreparingDogecoinSend: Bool { get { shellState.getIsPreparingDogecoinSend() } set { notifyIfChanged(isPreparingDogecoinSend, newValue) { shellState.setIsPreparingDogecoinSend(value: newValue) } } }
    var isPreparingTronSend: Bool { get { shellState.getIsPreparingTronSend() } set { notifyIfChanged(isPreparingTronSend, newValue) { shellState.setIsPreparingTronSend(value: newValue) } } }
    var isPreparingSolanaSend: Bool { get { shellState.getIsPreparingSolanaSend() } set { notifyIfChanged(isPreparingSolanaSend, newValue) { shellState.setIsPreparingSolanaSend(value: newValue) } } }
    var isPreparingXRPSend: Bool { get { shellState.getIsPreparingXrpSend() } set { notifyIfChanged(isPreparingXRPSend, newValue) { shellState.setIsPreparingXrpSend(value: newValue) } } }
    var isPreparingStellarSend: Bool { get { shellState.getIsPreparingStellarSend() } set { notifyIfChanged(isPreparingStellarSend, newValue) { shellState.setIsPreparingStellarSend(value: newValue) } } }
    var isPreparingMoneroSend: Bool { get { shellState.getIsPreparingMoneroSend() } set { notifyIfChanged(isPreparingMoneroSend, newValue) { shellState.setIsPreparingMoneroSend(value: newValue) } } }
    var isPreparingCardanoSend: Bool { get { shellState.getIsPreparingCardanoSend() } set { notifyIfChanged(isPreparingCardanoSend, newValue) { shellState.setIsPreparingCardanoSend(value: newValue) } } }
    var isPreparingSuiSend: Bool { get { shellState.getIsPreparingSuiSend() } set { notifyIfChanged(isPreparingSuiSend, newValue) { shellState.setIsPreparingSuiSend(value: newValue) } } }
    var isPreparingAptosSend: Bool { get { shellState.getIsPreparingAptosSend() } set { notifyIfChanged(isPreparingAptosSend, newValue) { shellState.setIsPreparingAptosSend(value: newValue) } } }
    var isPreparingTONSend: Bool { get { shellState.getIsPreparingTonSend() } set { notifyIfChanged(isPreparingTONSend, newValue) { shellState.setIsPreparingTonSend(value: newValue) } } }
    var isPreparingICPSend: Bool { get { shellState.getIsPreparingIcpSend() } set { notifyIfChanged(isPreparingICPSend, newValue) { shellState.setIsPreparingIcpSend(value: newValue) } } }
    var isPreparingNearSend: Bool { get { shellState.getIsPreparingNearSend() } set { notifyIfChanged(isPreparingNearSend, newValue) { shellState.setIsPreparingNearSend(value: newValue) } } }
    var isPreparingPolkadotSend: Bool { get { shellState.getIsPreparingPolkadotSend() } set { notifyIfChanged(isPreparingPolkadotSend, newValue) { shellState.setIsPreparingPolkadotSend(value: newValue) } } }
    var statusTrackingByTransactionID: [UUID: AppState.TransactionStatusTrackingState] = [:]
    var pendingSelfSendConfirmation: AppState.PendingSelfSendConfirmation?
    var activeEthereumSendWalletIDs: Set<String> = []
    var lastSendDestinationProbeKey: String?
    var lastSendDestinationProbeWarning: String?
    var lastSendDestinationProbeInfoMessage: String?
    var cachedResolvedENSAddresses: [String: String] {
        get { cachesGetResolvedEnsAddresses() }
        set { cachesReplaceResolvedEnsAddresses(entries: newValue); bumpCachesRevision() }
    }
    var bypassHighRiskSendConfirmation = false
    var isRefreshingLivePrices = false
    var isRefreshingChainBalances = false
    var allowsBalanceNetworkRefresh = false
    var isRefreshingPendingTransactions = false
    var lastLivePriceRefreshAt: Date?
    var lastFiatRatesRefreshAt: Date?
    var lastFullRefreshAt: Date?
    var lastChainBalanceRefreshAt: Date?
    var lastBackgroundMaintenanceAt: Date?
    var isNetworkReachable: Bool = true
    var isConstrainedNetwork: Bool = false
    var isExpensiveNetwork: Bool = false
    @Published var lastSentTransaction: TransactionRecord?
    var lastPendingTransactionRefreshAt: Date? {
        get { shellState.getLastPendingTransactionRefreshAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setLastPendingTransactionRefreshAt(value: newValue?.timeIntervalSince1970) }
    }
    @Published var ethereumSendPreview: EthereumSendPreview?
    @Published var bitcoinSendPreview: BitcoinSendPreview?
    @Published var bitcoinCashSendPreview: BitcoinSendPreview?
    @Published var bitcoinSVSendPreview: BitcoinSendPreview?
    @Published var litecoinSendPreview: BitcoinSendPreview?
    @Published var dogecoinSendPreview: DogecoinSendPreview?
    @Published var tronSendPreview: TronSendPreview?
    @Published var solanaSendPreview: SolanaSendPreview?
    @Published var xrpSendPreview: XrpSendPreview?
    @Published var stellarSendPreview: StellarSendPreview?
    @Published var moneroSendPreview: MoneroSendPreview?
    @Published var cardanoSendPreview: CardanoSendPreview?
    @Published var suiSendPreview: SuiSendPreview?
    @Published var aptosSendPreview: AptosSendPreview?
    @Published var tonSendPreview: TonSendPreview?
    @Published var icpSendPreview: IcpSendPreview?
    @Published var nearSendPreview: NearSendPreview?
    @Published var polkadotSendPreview: PolkadotSendPreview?
    var isSendingBitcoin: Bool { get { shellState.getIsSendingBitcoin() } set { notifyIfChanged(isSendingBitcoin, newValue) { shellState.setIsSendingBitcoin(value: newValue) } } }
    var isSendingBitcoinCash: Bool { get { shellState.getIsSendingBitcoinCash() } set { notifyIfChanged(isSendingBitcoinCash, newValue) { shellState.setIsSendingBitcoinCash(value: newValue) } } }
    var isSendingBitcoinSV: Bool { get { shellState.getIsSendingBitcoinSv() } set { notifyIfChanged(isSendingBitcoinSV, newValue) { shellState.setIsSendingBitcoinSv(value: newValue) } } }
    var isSendingLitecoin: Bool { get { shellState.getIsSendingLitecoin() } set { notifyIfChanged(isSendingLitecoin, newValue) { shellState.setIsSendingLitecoin(value: newValue) } } }
    var isSendingDogecoin: Bool { get { shellState.getIsSendingDogecoin() } set { notifyIfChanged(isSendingDogecoin, newValue) { shellState.setIsSendingDogecoin(value: newValue) } } }
    var isSendingEthereum: Bool { get { shellState.getIsSendingEthereum() } set { notifyIfChanged(isSendingEthereum, newValue) { shellState.setIsSendingEthereum(value: newValue) } } }
    var isSendingTron: Bool { get { shellState.getIsSendingTron() } set { notifyIfChanged(isSendingTron, newValue) { shellState.setIsSendingTron(value: newValue) } } }
    var isSendingSolana: Bool { get { shellState.getIsSendingSolana() } set { notifyIfChanged(isSendingSolana, newValue) { shellState.setIsSendingSolana(value: newValue) } } }
    var isSendingXRP: Bool { get { shellState.getIsSendingXrp() } set { notifyIfChanged(isSendingXRP, newValue) { shellState.setIsSendingXrp(value: newValue) } } }
    var isSendingStellar: Bool { get { shellState.getIsSendingStellar() } set { notifyIfChanged(isSendingStellar, newValue) { shellState.setIsSendingStellar(value: newValue) } } }
    var isSendingMonero: Bool { get { shellState.getIsSendingMonero() } set { notifyIfChanged(isSendingMonero, newValue) { shellState.setIsSendingMonero(value: newValue) } } }
    var isSendingCardano: Bool { get { shellState.getIsSendingCardano() } set { notifyIfChanged(isSendingCardano, newValue) { shellState.setIsSendingCardano(value: newValue) } } }
    var isSendingSui: Bool { get { shellState.getIsSendingSui() } set { notifyIfChanged(isSendingSui, newValue) { shellState.setIsSendingSui(value: newValue) } } }
    var isSendingAptos: Bool { get { shellState.getIsSendingAptos() } set { notifyIfChanged(isSendingAptos, newValue) { shellState.setIsSendingAptos(value: newValue) } } }
    var isSendingTON: Bool { get { shellState.getIsSendingTon() } set { notifyIfChanged(isSendingTON, newValue) { shellState.setIsSendingTon(value: newValue) } } }
    var isSendingICP: Bool { get { shellState.getIsSendingIcp() } set { notifyIfChanged(isSendingICP, newValue) { shellState.setIsSendingIcp(value: newValue) } } }
    var isSendingNear: Bool { get { shellState.getIsSendingNear() } set { notifyIfChanged(isSendingNear, newValue) { shellState.setIsSendingNear(value: newValue) } } }
    var isSendingPolkadot: Bool { get { shellState.getIsSendingPolkadot() } set { notifyIfChanged(isSendingPolkadot, newValue) { shellState.setIsSendingPolkadot(value: newValue) } } }
    var tronLastSendErrorDetails: String? { get { shellState.getTronLastSendErrorDetails() } set { notifyIfChanged(tronLastSendErrorDetails, newValue) { shellState.setTronLastSendErrorDetails(value: newValue) } } }
    var tronLastSendErrorAt: Date? {
        get { shellState.getTronLastSendErrorAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setTronLastSendErrorAt(value: newValue?.timeIntervalSince1970) }
    }
    let chainDiagnosticsState = WalletChainDiagnosticsState()
    private(set) var recentPerformanceSamples: [PerformanceSample] = []
    var isOnboarded: Bool { !wallets.isEmpty }
    var dogecoinKeypoolDiagnostics: [DogecoinKeypoolDiagnostic] {
        wallets.filter { $0.selectedChain == "Dogecoin" }
            .map { wallet in
                let state = dogecoinKeypoolByWalletID[wallet.id] ?? baselineDogecoinKeypoolState(for: wallet)
                let reservedIndex = state.reservedReceiveIndex
                let reservedPath = reservedIndex.map {
                    WalletDerivationPath.dogecoin(
                        account: 0, branch: .external, index: UInt32($0)
                    )
                }
                let reservedAddress = reservedIndex.flatMap { index in deriveDogecoinAddress(for: wallet, isChange: false, index: index) }
                return DogecoinKeypoolDiagnostic(
                    walletID: wallet.id, walletName: wallet.name, reservedReceiveIndex: reservedIndex, reservedReceivePath: reservedPath, reservedReceiveAddress: reservedAddress, nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }}
    func chainKeypoolDiagnostics(for chainName: String) -> [ChainKeypoolDiagnostic] {
        wallets.filter { wallet in wallet.selectedChain == chainName || walletHasAddress(for: wallet, chainName: chainName) }
            .compactMap { wallet in
                let state = keypoolState(for: wallet, chainName: chainName)
                let reservedIndex = state.reservedReceiveIndex
                return ChainKeypoolDiagnostic(
                    walletID: wallet.id, walletName: wallet.name, chainName: chainName, reservedReceiveIndex: reservedIndex, reservedReceivePath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), reservedReceiveAddress: reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false), nextExternalIndex: state.nextExternalIndex, nextChangeIndex: state.nextChangeIndex
                )
            }
            .sorted { $0.walletName.localizedCaseInsensitiveCompare($1.walletName) == .orderedAscending }}
    var pricingProvider: PricingProvider {
        get { PricingProvider(rawValue: shellState.getPricingProvider()) ?? .coinGecko }
        set { objectWillChange.send(); shellState.setPricingProvider(value: newValue.rawValue); persistAppSettings() }
    }
    var selectedFiatCurrency: FiatCurrency {
        get { FiatCurrency(rawValue: shellState.getSelectedFiatCurrency()) ?? .usd }
        set {
            objectWillChange.send()
            shellState.setSelectedFiatCurrency(value: newValue.rawValue)
            persistAppSettings()
            Task { @MainActor in await refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    var fiatRateProvider: FiatRateProvider {
        get { FiatRateProvider(rawValue: shellState.getFiatRateProvider()) ?? .openER }
        set {
            objectWillChange.send()
            shellState.setFiatRateProvider(value: newValue.rawValue)
            persistAppSettings()
            Task { @MainActor in await refreshFiatExchangeRatesIfNeeded(force: true) }
        }
    }
    var coinGeckoAPIKey: String {
        get { shellState.getCoinGeckoApiKey() }
        set { objectWillChange.send(); shellState.setCoinGeckoApiKey(value: newValue); SecureStore.save(newValue, for: Self.coinGeckoAPIKeyAccount) }
    }
    var ethereumRPCEndpoint: String {
        get { shellState.getEthereumRpcEndpoint() }
        set { objectWillChange.send(); shellState.setEthereumRpcEndpoint(value: newValue); persistAppSettings() }
    }
    var ethereumNetworkMode: EthereumNetworkMode {
        get { EthereumNetworkMode(rawValue: shellState.getEthereumNetworkMode()) ?? .mainnet }
        set {
            objectWillChange.send()
            shellState.setEthereumNetworkMode(value: newValue.rawValue)
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 1)
        }
    }
    var etherscanAPIKey: String {
        get { shellState.getEtherscanApiKey() }
        set { objectWillChange.send(); shellState.setEtherscanApiKey(value: newValue); persistAppSettings() }
    }
    var moneroBackendBaseURL: String {
        get { shellState.getMoneroBackendBaseUrl() }
        set { objectWillChange.send(); shellState.setMoneroBackendBaseUrl(value: newValue); persistAppSettings() }
    }
    var moneroBackendAPIKey: String {
        get { shellState.getMoneroBackendApiKey() }
        set { objectWillChange.send(); shellState.setMoneroBackendApiKey(value: newValue); persistAppSettings() }
    }
    var isUserInitiatedRefreshInProgress: Bool { get { shellState.getIsUserInitiatedRefreshInProgress() } set { notifyIfChanged(isUserInitiatedRefreshInProgress, newValue) { shellState.setIsUserInitiatedRefreshInProgress(value: newValue) } } }
    @Published var priceAlerts: [PriceAlertRule] = [] {
        didSet {
            persistPriceAlerts()
        }}
    @Published var addressBook: [AddressBookEntry] = [] {
        didSet {
            persistAddressBook()
        }}
    @Published var tokenPreferences: [TokenPreferenceEntry] = [] {
        didSet {
            persistTokenPreferences()
            rebuildTokenPreferenceDerivedState()
            rebuildWalletDerivedState()
            rebuildDashboardDerivedState()
        }}
    var livePrices: [String: Double] {
        get { shellState.getLivePrices() }
        set {
            let oldValue = shellState.getLivePrices()
            objectWillChange.send()
            shellState.setLivePrices(value: newValue)
            persistLivePrices()
            if shouldRebuildDashboardForLivePriceChange(from: oldValue, to: newValue) { rebuildDashboardDerivedState() }
        }
    }
    var fiatRatesFromUSD: [String: Double] {
        get { shellState.getFiatRatesFromUsd() }
        set { objectWillChange.send(); shellState.setFiatRatesFromUsd(value: newValue) }
    }
    var fiatRatesRefreshError: String? {
        get { shellState.getFiatRatesRefreshError() }
        set { notifyIfChanged(fiatRatesRefreshError, newValue) { shellState.setFiatRatesRefreshError(value: newValue) } }
    }
    var quoteRefreshError: String? {
        get { shellState.getQuoteRefreshError() }
        set { notifyIfChanged(quoteRefreshError, newValue) { shellState.setQuoteRefreshError(value: newValue) } }
    }
    var cachedPinnedDashboardAssetSymbols: [String] {
        get { cachesGetPinnedDashboardAssetSymbols() }
        set { cachesReplacePinnedDashboardAssetSymbols(entries: newValue); bumpCachesRevision() }
    }
    var cachedDashboardPinOptionBySymbol: [String: DashboardPinOption] {
        get { cachesGetDashboardPinOptionBySymbol() }
        set { cachesReplaceDashboardPinOptionBySymbol(entries: newValue); bumpCachesRevision() }
    }
    var cachedAvailableDashboardPinOptions: [DashboardPinOption] {
        get { cachesGetAvailableDashboardPinOptions() }
        set { cachesReplaceAvailableDashboardPinOptions(entries: newValue); bumpCachesRevision() }
    }
    var cachedDashboardAssetGroups: [DashboardAssetGroup] {
        get { cachesGetDashboardAssetGroups() }
        set { cachesReplaceDashboardAssetGroups(entries: newValue); bumpCachesRevision() }
    }
    var cachedDashboardRelevantPriceKeys: Set<String> {
        get { Set(cachesGetDashboardRelevantPriceKeys()) }
        set { cachesReplaceDashboardRelevantPriceKeys(entries: Array(newValue)); bumpCachesRevision() }
    }
    var cachedDashboardSupportedTokenEntriesBySymbol: [String: [TokenPreferenceEntry]] {
        get { cachesGetDashboardSupportedTokenEntriesBySymbol() }
        set { cachesReplaceDashboardSupportedTokenEntriesBySymbol(entries: newValue); bumpCachesRevision() }
    }
    var cachedResolvedTokenPreferences: [TokenPreferenceEntry] {
        get {
            let v = cachesGetResolvedTokenPreferences()
            return v.isEmpty ? ChainTokenRegistryEntry.builtIn.map(\.tokenPreferenceEntry) : v
        }
        set { cachesReplaceResolvedTokenPreferences(entries: newValue); bumpCachesRevision() }
    }
    var cachedTokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] {
        get {
            var result: [TokenTrackingChain: [TokenPreferenceEntry]] = [:]
            for (raw, entries) in cachesGetTokenPreferencesByChain() {
                if let chain = TokenTrackingChain(rawValue: raw) { result[chain] = entries }
            }
            return result
        }
        set {
            let rawMap = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            cachesReplaceTokenPreferencesByChain(entries: rawMap); bumpCachesRevision()
        }
    }
    var cachedResolvedTokenPreferencesBySymbol: [String: [TokenPreferenceEntry]] {
        get { cachesGetResolvedTokenPreferencesBySymbol() }
        set { cachesReplaceResolvedTokenPreferencesBySymbol(entries: newValue); bumpCachesRevision() }
    }
    var cachedEnabledTrackedTokenPreferences: [TokenPreferenceEntry] {
        get { cachesGetEnabledTrackedTokenPreferences() }
        set { cachesReplaceEnabledTrackedTokenPreferences(entries: newValue); bumpCachesRevision() }
    }
    var cachedTokenPreferenceByChainAndSymbol: [String: TokenPreferenceEntry] {
        get { cachesGetTokenPreferenceByChainAndSymbol() }
        set { cachesReplaceTokenPreferenceByChainAndSymbol(entries: newValue); bumpCachesRevision() }
    }
    var cachedCurrencyFormatters: [String: NumberFormatter] = [:]
    var cachedDecimalFormatters: [String: NumberFormatter] = [:]
    var useCustomEthereumFees: Bool { get { shellState.getUseCustomEthereumFees() } set { notifyIfChanged(useCustomEthereumFees, newValue) { shellState.setUseCustomEthereumFees(value: newValue) } } }
    var customEthereumMaxFeeGwei: String { get { shellState.getCustomEthereumMaxFeeGwei() } set { notifyIfChanged(customEthereumMaxFeeGwei, newValue) { shellState.setCustomEthereumMaxFeeGwei(value: newValue) } } }
    var customEthereumPriorityFeeGwei: String { get { shellState.getCustomEthereumPriorityFeeGwei() } set { notifyIfChanged(customEthereumPriorityFeeGwei, newValue) { shellState.setCustomEthereumPriorityFeeGwei(value: newValue) } } }
    var sendAdvancedMode: Bool { get { shellState.getSendAdvancedMode() } set { notifyIfChanged(sendAdvancedMode, newValue) { shellState.setSendAdvancedMode(value: newValue) } } }
    var sendUTXOMaxInputCount: Int { get { Int(shellState.getSendUtxoMaxInputCount()) } set { notifyIfChanged(sendUTXOMaxInputCount, newValue) { shellState.setSendUtxoMaxInputCount(value: Int64(newValue)) } } }
    var sendEnableRBF: Bool { get { shellState.getSendEnableRbf() } set { notifyIfChanged(sendEnableRBF, newValue) { shellState.setSendEnableRbf(value: newValue) } } }
    var sendEnableCPFP: Bool { get { shellState.getSendEnableCpfp() } set { notifyIfChanged(sendEnableCPFP, newValue) { shellState.setSendEnableCpfp(value: newValue) } } }
    var sendLitecoinChangeStrategy: LitecoinChangeStrategy {
        get { LitecoinChangeStrategy(rawValue: shellState.getSendLitecoinChangeStrategy()) ?? .derivedChange }
        set { notifyIfChanged(sendLitecoinChangeStrategy, newValue) { shellState.setSendLitecoinChangeStrategy(value: newValue.rawValue) } }
    }
    var ethereumManualNonceEnabled: Bool { get { shellState.getEthereumManualNonceEnabled() } set { notifyIfChanged(ethereumManualNonceEnabled, newValue) { shellState.setEthereumManualNonceEnabled(value: newValue) } } }
    var ethereumManualNonce: String { get { shellState.getEthereumManualNonce() } set { notifyIfChanged(ethereumManualNonce, newValue) { shellState.setEthereumManualNonce(value: newValue) } } }
    var bitcoinNetworkMode: BitcoinNetworkMode {
        get { BitcoinNetworkMode(rawValue: shellState.getBitcoinNetworkMode()) ?? .mainnet }
        set {
            objectWillChange.send()
            shellState.setBitcoinNetworkMode(value: newValue.rawValue)
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
            Task {
                await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Bitcoin")
                await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Bitcoin")
            }
            chainKeypoolByChain.removeValue(forKey: "Bitcoin")
            chainOwnedAddressMapByChain.removeValue(forKey: "Bitcoin")
        }
    }
    var dogecoinNetworkMode: DogecoinNetworkMode {
        get { DogecoinNetworkMode(rawValue: shellState.getDogecoinNetworkMode()) ?? .mainnet }
        set {
            objectWillChange.send()
            shellState.setDogecoinNetworkMode(value: newValue.rawValue)
            persistAppSettings()
            Task {
                await WalletServiceBridge.shared.deleteKeypoolForChain(chainName: "Dogecoin")
                await WalletServiceBridge.shared.deleteOwnedAddressesForChain(chainName: "Dogecoin")
            }
            chainKeypoolByChain["Dogecoin"] = [:]
            chainOwnedAddressMapByChain["Dogecoin"] = [:]
        }
    }
    var bitcoinEsploraEndpoints: String {
        get { shellState.getBitcoinEsploraEndpoints() }
        set {
            objectWillChange.send()
            shellState.setBitcoinEsploraEndpoints(value: newValue)
            persistAppSettings()
            WalletServiceBridge.shared.resetHistoryForChain(chainId: 0)
        }
    }
    var bitcoinStopGap: Int {
        get { Int(shellState.getBitcoinStopGap()) }
        set {
            objectWillChange.send()
            let clamped = max(1, min(newValue, 200))
            shellState.setBitcoinStopGap(value: Int64(clamped))
            persistAppSettings()
        }
    }
    var bitcoinFeePriority: BitcoinFeePriority {
        get { BitcoinFeePriority(rawValue: shellState.getBitcoinFeePriority()) ?? .normal }
        set { objectWillChange.send(); shellState.setBitcoinFeePriority(value: newValue.rawValue); persistAppSettings() }
    }
    var dogecoinFeePriority: DogecoinFeePriority {
        get { DogecoinFeePriority(rawValue: shellState.getDogecoinFeePriority()) ?? .normal }
        set { objectWillChange.send(); shellState.setDogecoinFeePriority(value: newValue.rawValue); persistAppSettings() }
    }
    var hideBalances: Bool {
        get { shellState.getHideBalances() }
        set { objectWillChange.send(); shellState.setHideBalances(value: newValue); persistAppSettings() }
    }
    var assetDisplayDecimalsByChain: [String: Int] {
        get { shellState.getAssetDisplayDecimalsByChain().mapValues { Int($0) } }
        set {
            objectWillChange.send()
            let normalized = newValue.mapValues { min(max($0, 0), 30) }
            shellState.setAssetDisplayDecimalsByChain(value: normalized.mapValues { Int64($0) })
            persistAssetDisplayDecimalsByChain()
            cachedDecimalFormatters = [:]
        }
    }
    var useFaceID: Bool {
        get { shellState.getUseFaceId() }
        set {
            objectWillChange.send()
            shellState.setUseFaceId(value: newValue)
            persistAppSettings()
            if !newValue {
                isAppLocked = false
                appLockError = nil
            }
        }
    }
    var useAutoLock: Bool {
        get { shellState.getUseAutoLock() }
        set { objectWillChange.send(); shellState.setUseAutoLock(value: newValue); persistAppSettings() }
    }
    var useStrictRPCOnly: Bool {
        get { shellState.getUseStrictRpcOnly() }
        set { objectWillChange.send(); shellState.setUseStrictRpcOnly(value: newValue); persistAppSettings() }
    }
    var requireBiometricForSendActions: Bool {
        get { shellState.getRequireBiometricForSendActions() }
        set { objectWillChange.send(); shellState.setRequireBiometricForSendActions(value: newValue); persistAppSettings() }
    }
    var usePriceAlerts: Bool {
        get { shellState.getUsePriceAlerts() }
        set { objectWillChange.send(); shellState.setUsePriceAlerts(value: newValue); persistAppSettings() }
    }
    var useTransactionStatusNotifications: Bool {
        get { shellState.getUseTransactionStatusNotifications() }
        set {
            objectWillChange.send()
            shellState.setUseTransactionStatusNotifications(value: newValue)
            persistAppSettings()
            if newValue { requestNotificationPermissionIfNeeded() }
        }
    }
    var useLargeMovementNotifications: Bool {
        get { shellState.getUseLargeMovementNotifications() }
        set {
            objectWillChange.send()
            shellState.setUseLargeMovementNotifications(value: newValue)
            persistAppSettings()
            if newValue { requestNotificationPermissionIfNeeded() }
        }
    }
    var automaticRefreshFrequencyMinutes: Int {
        get { Int(shellState.getAutomaticRefreshFrequencyMinutes()) }
        set {
            objectWillChange.send()
            let clamped = min(max(newValue, 5), 60)
            shellState.setAutomaticRefreshFrequencyMinutes(value: Int64(clamped))
            persistAppSettings()
        }
    }
    var backgroundSyncProfile: BackgroundSyncProfile {
        get { BackgroundSyncProfile(rawValue: shellState.getBackgroundSyncProfile()) ?? .balanced }
        set { objectWillChange.send(); shellState.setBackgroundSyncProfile(value: newValue.rawValue); persistAppSettings() }
    }
    var largeMovementAlertPercentThreshold: Double {
        get { shellState.getLargeMovementAlertPercentThreshold() }
        set {
            objectWillChange.send()
            let clamped = min(max(newValue, 1), 90)
            shellState.setLargeMovementAlertPercentThreshold(value: clamped)
            persistAppSettings()
        }
    }
    var largeMovementAlertUSDThreshold: Double {
        get { shellState.getLargeMovementAlertUsdThreshold() }
        set {
            objectWillChange.send()
            let clamped = min(max(newValue, 1), 100_000)
            shellState.setLargeMovementAlertUsdThreshold(value: clamped)
            persistAppSettings()
        }
    }
    var dogecoinKeypoolByWalletID: [String: DogecoinKeypoolState] {
        get { chainKeypoolByChain["Dogecoin"] ?? [:] }
        set { chainKeypoolByChain["Dogecoin"] = newValue }
    }
    @Published var chainKeypoolByChain: [String: [String: ChainKeypoolState]] = [:] {
        didSet {
            persistChainKeypoolState()
        }}
    var dogecoinOwnedAddressMap: [String: DogecoinOwnedAddressRecord] {
        get {
            (chainOwnedAddressMapByChain["Dogecoin"] ?? [:]).reduce(into: [:]) { result, pair in
                result[pair.key] = DogecoinOwnedAddressRecord(
                    address: pair.value.address, walletID: pair.value.walletID,
                    derivationPath: pair.value.derivationPath ?? "", index: pair.value.index ?? 0, branch: pair.value.branch ?? ""
                )
            }
        }
        set {
            chainOwnedAddressMapByChain["Dogecoin"] = newValue.reduce(into: [:]) { result, pair in
                result[pair.key] = ChainOwnedAddressRecord(
                    chainName: "Dogecoin", address: pair.value.address, walletID: pair.value.walletID,
                    derivationPath: pair.value.derivationPath, index: pair.value.index, branch: pair.value.branch
                )
            }
        }
    }
    @Published var chainOwnedAddressMapByChain: [String: [String: ChainOwnedAddressRecord]] = [:] {
        didSet {
            persistChainOwnedAddressMap()
        }}
    var pendingEthereumSendPreviewRefresh: Bool = false
    var pendingDogecoinSendPreviewRefresh: Bool = false
    var discoveredDogecoinAddressesByWallet: [String: [String]] {
        get { discoveredUTXOAddressesByChain["Dogecoin"] ?? [:] }
        set { discoveredUTXOAddressesByChain["Dogecoin"] = newValue }
    }
    @Published var discoveredUTXOAddressesByChain: [String: [String: [String]]] = [:]
    var isLoadingMoreOnChainHistory: Bool { get { shellState.getIsLoadingMoreOnChainHistory() } set { notifyIfChanged(isLoadingMoreOnChainHistory, newValue) { shellState.setIsLoadingMoreOnChainHistory(value: newValue) } } }
    let diagnostics = WalletDiagnosticsState()
    @Published var chainOperationalEventsByChain: [String: [ChainOperationalEvent]] = [:] {
        didSet {
            persistChainOperationalEvents()
        }}
    var selectedFeePriorityOptionRawByChain: [String: String] {
        get { shellState.getSelectedFeePriorityOptionRawByChain() }
        set { objectWillChange.send(); shellState.setSelectedFeePriorityOptionRawByChain(value: newValue); persistSelectedFeePriorityOptions() }
    }
    var isRunningBitcoinRescan: Bool { get { shellState.getIsRunningBitcoinRescan() } set { notifyIfChanged(isRunningBitcoinRescan, newValue) { shellState.setIsRunningBitcoinRescan(value: newValue) } } }
    var bitcoinRescanLastRunAt: Date? {
        get { shellState.getBitcoinRescanLastRunAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setBitcoinRescanLastRunAt(value: newValue?.timeIntervalSince1970) }
    }
    var isRunningBitcoinCashRescan: Bool { get { shellState.getIsRunningBitcoinCashRescan() } set { notifyIfChanged(isRunningBitcoinCashRescan, newValue) { shellState.setIsRunningBitcoinCashRescan(value: newValue) } } }
    var bitcoinCashRescanLastRunAt: Date? {
        get { shellState.getBitcoinCashRescanLastRunAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setBitcoinCashRescanLastRunAt(value: newValue?.timeIntervalSince1970) }
    }
    var isRunningBitcoinSVRescan: Bool { get { shellState.getIsRunningBitcoinSvRescan() } set { notifyIfChanged(isRunningBitcoinSVRescan, newValue) { shellState.setIsRunningBitcoinSvRescan(value: newValue) } } }
    var bitcoinSVRescanLastRunAt: Date? {
        get { shellState.getBitcoinSvRescanLastRunAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setBitcoinSvRescanLastRunAt(value: newValue?.timeIntervalSince1970) }
    }
    var isRunningLitecoinRescan: Bool { get { shellState.getIsRunningLitecoinRescan() } set { notifyIfChanged(isRunningLitecoinRescan, newValue) { shellState.setIsRunningLitecoinRescan(value: newValue) } } }
    var litecoinRescanLastRunAt: Date? {
        get { shellState.getLitecoinRescanLastRunAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setLitecoinRescanLastRunAt(value: newValue?.timeIntervalSince1970) }
    }
    var isRunningDogecoinRescan: Bool { get { shellState.getIsRunningDogecoinRescan() } set { notifyIfChanged(isRunningDogecoinRescan, newValue) { shellState.setIsRunningDogecoinRescan(value: newValue) } } }
    var dogecoinRescanLastRunAt: Date? {
        get { shellState.getDogecoinRescanLastRunAt().map { Date(timeIntervalSince1970: $0) } }
        set { objectWillChange.send(); shellState.setDogecoinRescanLastRunAt(value: newValue?.timeIntervalSince1970) }
    }
    var suppressWalletSideEffects = false
    var userInitiatedRefreshTask: Task<Void, Never>?
    var importRefreshTask: Task<Void, Never>?
    var walletSideEffectsTask: Task<Void, Never>?
    var walletCollectionObservation: AnyCancellable?
    var diagnosticsObservation: AnyCancellable?
    var chainDiagnosticsStateObservation: AnyCancellable?
    var lastHistoryRefreshAtByChain: [String: Date] = [:]
    var appIsActive = true
    var maintenanceTask: Task<Void, Never>?
    var lastObservedPortfolioTotalUSD: Double?
    var lastObservedPortfolioCompositionSignature: String?
#if canImport(Network)
    let networkPathMonitor = NWPathMonitor()
    let networkPathMonitorQueue = DispatchQueue(label: "spectra.network.monitor")
#endif
    static let pricingProviderDefaultsKey = "pricing.provider"
    static let selectedFiatCurrencyDefaultsKey = "pricing.selectedFiatCurrency"
    static let fiatRateProviderDefaultsKey = "pricing.fiatRateProvider"
    static let fiatRatesFromUSDDefaultsKey = "pricing.fiatRatesFromUSD.v1"
    static let coinGeckoAPIKeyAccount = "coingecko.api.key"
    static let ethereumRPCEndpointDefaultsKey = "ethereum.rpc.endpoint"
    static let etherscanAPIKeyDefaultsKey = "ethereum.etherscan.apiKey"
    static let ethereumNetworkModeDefaultsKey = "ethereum.network.mode"
    static let bitcoinNetworkModeDefaultsKey = "bitcoin.network.mode"
    static let dogecoinNetworkModeDefaultsKey = "dogecoin.network.mode"
    static let bitcoinEsploraEndpointsDefaultsKey = "bitcoin.esplora.endpoints"
    static let bitcoinStopGapDefaultsKey = "bitcoin.stopGap"
    static let bitcoinFeePriorityDefaultsKey = "bitcoin.feePriority"
    static let walletsAccount = "wallets.snapshot"
    static let walletsCoreSnapshotAccount = "wallets.core.snapshot.v1"
    static let priceAlertsDefaultsKey = "priceAlerts.snapshot"
    static let addressBookDefaultsKey = "addressBook.snapshot"
    static let tokenPreferencesDefaultsKey = "settings.tokenPreferences.v1"
    static let livePricesDefaultsKey = "pricing.livePrices.v1"
    static let hideBalancesDefaultsKey = "settings.hideBalances"
    static let assetDisplayDecimalsByChainDefaultsKey = "settings.assetDisplayDecimalsByChain.v1"
    static let useFaceIDDefaultsKey = "settings.useFaceID"
    static let useAutoLockDefaultsKey = "settings.useAutoLock"
    static let useStrictRPCOnlyDefaultsKey = "settings.useStrictRPCOnly"
    static let requireBiometricForSendActionsDefaultsKey = "settings.requireBiometricForSendActions"
    static let usePriceAlertsDefaultsKey = "settings.usePriceAlerts"
    static let useTransactionStatusNotificationsDefaultsKey = "settings.useTransactionStatusNotifications"
    static let useLargeMovementNotificationsDefaultsKey = "settings.useLargeMovementNotifications"
    static let automaticRefreshFrequencyMinutesDefaultsKey = "settings.automaticRefreshFrequencyMinutes"
    static let backgroundSyncProfileDefaultsKey = "settings.backgroundSyncProfile"
    static let largeMovementAlertPercentThresholdDefaultsKey = "settings.largeMovementAlertPercentThreshold"
    static let largeMovementAlertUSDThresholdDefaultsKey = "settings.largeMovementAlertUSDThreshold"
    static let selectedFeePriorityOptionsByChainDefaultsKey = "settings.feePriorityOptionsByChain.v1"
    static let chainOperationalEventsDefaultsKey = "chain.operational.events.v1"
    static let operationalLogsDefaultsKey = "operational.logs.v1"
    static let dogecoinFeePriorityDefaultsKey = "settings.dogecoinFeePriority"
    static let dogecoinKeypoolDefaultsKey = "dogecoin.keypool.snapshot"
    static let dogecoinOwnedAddressMapDefaultsKey = "dogecoin.ownedAddressMap.snapshot"
    static let chainKeypoolDefaultsKey = "chain.keypool.snapshot.v1"
    static let chainOwnedAddressMapDefaultsKey = "chain.ownedAddressMap.snapshot.v1"
    static let chainSyncStateDefaultsKey = "chain.sync.state.v1"
    static let installMarkerDefaultsKey = "app.install.marker.v1"
    static let dogecoinDiscoveryGapLimit = 3
    static let dogecoinDiscoveryMaxIndex = 40
    static let utxoDiscoveryGapLimit = 3
    static let utxoDiscoveryMaxIndex = 40
    static let pendingStatusPollSeconds: TimeInterval = 20
    static let confirmedStatusPollSeconds: TimeInterval = 300
    static let statusPollBackoffMaxSeconds: TimeInterval = 600
    static let standardFinalityConfirmations = 12
    static let pendingFailureTimeoutSeconds: TimeInterval = 60 * 60
    static let pendingFailureMinFailures = 6
    static let selfSendConfirmationWindowSeconds: TimeInterval = 20
    static let activeMaintenancePollSeconds: UInt64 = 30
    static let inactiveMaintenancePollSeconds: UInt64 = 60
    static let activePendingRefreshInterval: TimeInterval = 60
    static let activePriceRefreshInterval: TimeInterval = 300
    static let fiatRatesRefreshInterval: TimeInterval = 6 * 60 * 60
    static let backgroundMaintenanceInterval: TimeInterval = 15 * 60
    static let constrainedBackgroundMaintenanceInterval: TimeInterval = 30 * 60
    static let lowPowerBackgroundMaintenanceInterval: TimeInterval = 45 * 60
    static let lowBatteryBackgroundMaintenanceInterval: TimeInterval = 60 * 60
    static let foregroundFullRefreshStalenessInterval: TimeInterval = 2 * 60
    static let automaticChainRefreshStalenessInterval: TimeInterval = 10 * 60
    static func seedPhraseAccount(for walletID: String) -> String { "wallet.seed.\(walletID)" }
    static func seedPhrasePasswordAccount(for walletID: String) -> String { "wallet.seed.password.\(walletID)" }
    static func privateKeyAccount(for walletID: String) -> String { "wallet.privatekey.\(walletID)" }
    func resolvedSeedPhraseAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.seedPhraseStoreKey ?? Self.seedPhraseAccount(for: walletID) }
    func resolvedSeedPhrasePasswordAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.passwordStoreKey ?? Self.seedPhrasePasswordAccount(for: walletID) }
    func resolvedPrivateKeyAccount(for walletID: String) -> String { cachedSecretDescriptorsByWalletID[walletID]?.privateKeyStoreKey ?? Self.privateKeyAccount(for: walletID) }
    func clearWalletSecretIndex() {
        cachedSigningMaterialWalletIDs = []
        cachedPrivateKeyBackedWalletIDs = []
        cachedPasswordProtectedWalletIDs = []
        cachedSecretDescriptorsByWalletID = [:]
    }
    func storedSeedPhrase(for walletID: String) -> String? {
        let account = resolvedSeedPhraseAccount(for: walletID)
        guard let seedPhrase = try? SecureSeedStore.loadValue(for: account), !seedPhrase.isEmpty else { return nil }
        return seedPhrase
    }
    func storedPrivateKey(for walletID: String) -> String? {
        let account = resolvedPrivateKeyAccount(for: walletID)
        let privateKey = SecurePrivateKeyStore.loadValue(for: account)
        return privateKey.isEmpty ? nil : privateKey
    }
    func walletRequiresSeedPhrasePassword(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasPassword }
        return SecureSeedPasswordStore.hasPassword(for: resolvedSeedPhrasePasswordAccount(for: walletID))
    }
    func signingMaterialAvailability(for walletID: String) -> (hasSigningMaterial: Bool, isPrivateKeyBacked: Bool) {
        let hasSeedPhrase = storedSeedPhrase(for: walletID) != nil
        let hasPrivateKey = storedPrivateKey(for: walletID) != nil
        return (hasSeedPhrase || hasPrivateKey, hasPrivateKey)
    }
    func walletHasSigningMaterial(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasSigningMaterial }
        return signingMaterialAvailability(for: walletID).hasSigningMaterial
    }
    func isPrivateKeyBackedWallet(_ walletID: String) -> Bool {
        if let descriptor = cachedSecretDescriptorsByWalletID[walletID] { return descriptor.hasPrivateKey }
        return signingMaterialAvailability(for: walletID).isPrivateKeyBacked
    }
    func deleteWalletSecrets(for walletID: String) {
        let seedAccount = resolvedSeedPhraseAccount(for: walletID)
        let seedPasswordAccount = resolvedSeedPhrasePasswordAccount(for: walletID)
        let privateKeyAccount = resolvedPrivateKeyAccount(for: walletID)
        try? SecureSeedStore.deleteValue(for: seedAccount)
        try? SecureSeedPasswordStore.deleteValue(for: seedPasswordAccount)
        SecurePrivateKeyStore.deleteValue(for: privateKeyAccount)
        cachedSigningMaterialWalletIDs.remove(walletID)
        cachedPrivateKeyBackedWalletIDs.remove(walletID)
        cachedPasswordProtectedWalletIDs.remove(walletID)
        cachedSecretDescriptorsByWalletID[walletID] = nil
    }
    func parsedBitcoinEsploraEndpoints() -> [String] { parseBitcoinEsploraEndpoints(raw: bitcoinEsploraEndpoints) }
    func effectiveBitcoinEsploraEndpoints() -> [String] {
        let configured = parsedBitcoinEsploraEndpoints()
        if !configured.isEmpty { return configured }
        return AppEndpointDirectory.bitcoinWalletStoreDefaultBaseURLs(for: bitcoinNetworkMode)
    }
    var bitcoinEsploraEndpointsValidationError: String? {
        Spectra.bitcoinEsploraEndpointsValidationError(raw: bitcoinEsploraEndpoints)
    }
    func parseDogecoinAmountInput(_ amountText: String) -> Double? {
        parseAmountInput(text: amountText, maxDecimals: 8)
    }
    func recordPendingSentTransaction(_ transaction: TransactionRecord) {
        appendTransaction(transaction)
        lastSentTransaction = transaction
        noteSendBroadcastQueued(for: transaction)
        requestTransactionStatusNotificationPermission()
    }
    private func applyVerificationNotice(_ n: SendVerificationNotice) {
        sendVerificationNotice = n.notice
        sendVerificationNoticeIsWarning = n.isWarning
    }
    func clearSendVerificationNotice() {
        applyVerificationNotice(SendVerificationNotice(notice: nil, isWarning: false))
    }
    func setDeferredSendVerificationNotice(for chainName: String) {
        applyVerificationNotice(verificationNoticeForStatus(status: .deferred, chainName: chainName))
    }
    func setFailedSendVerificationNotice(_ message: String) {
        sendVerificationNotice = "Warning: \(message)"
        sendVerificationNoticeIsWarning = true
    }
    func applySendVerificationStatus(_ verificationStatus: SendBroadcastVerificationStatus, chainName: String) {
        let coreStatus: CoreSendVerificationStatus
        switch verificationStatus {
        case .verified: coreStatus = .verified
        case .deferred: coreStatus = .deferred
        case .failed(let message):
            coreStatus = .failed(message: "Broadcast succeeded, but post-broadcast verification reported: \(message)")
        }
        applyVerificationNotice(verificationNoticeForStatus(status: coreStatus, chainName: chainName))
    }
    func updateSendVerificationNoticeForLastSentTransaction() {
        let snapshot: LastSentTransactionSnapshot? = lastSentTransaction.map { tx in
            LastSentTransactionSnapshot(
                kind: tx.kind == .send ? "send" : "other",
                status: {
                    switch tx.status {
                    case .pending: return "pending"
                    case .confirmed: return "confirmed"
                    case .failed: return "failed"
                    }
                }(),
                chainName: tx.chainName,
                transactionHash: tx.transactionHash,
                failureReason: tx.failureReason,
                transactionHistorySource: tx.transactionHistorySource,
                receiptBlockNumber: tx.receiptBlockNumber.map(Int64.init),
                dogecoinConfirmations: tx.dogecoinConfirmations.map(Int64.init)
            )
        }
        applyVerificationNotice(verificationNoticeForLastSent(snapshot: snapshot))
    }
    func runPostSendRefreshActions(for chainName: String, verificationStatus: SendBroadcastVerificationStatus) async {
        applySendVerificationStatus(verificationStatus, chainName: chainName)
        noteSendBroadcastVerification(
            chainName: chainName, verificationStatus: verificationStatus, transactionHash: lastSentTransaction?.chainName == chainName ? lastSentTransaction?.transactionHash : nil
        )
        async let balanceRefresh: () = refreshBalances()
        async let chainRefresh: () = {
            switch AppEndpointDirectory.appChain(for: chainName)?.id {
            case .bitcoin:          await self.refreshPendingBitcoinTransactions()
            case .bitcoinCash:      await self.refreshPendingBitcoinCashTransactions()
            case .bitcoinSV:        await self.refreshPendingBitcoinSVTransactions()
            case .litecoin:         await self.refreshPendingLitecoinTransactions()
            case .dogecoin:         await self.refreshPendingDogecoinTransactions()
            case .ethereum, .ethereumClassic, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid:
                                    await self.refreshPendingEVMTransactions(chainName: chainName)
            case .tron:             await self.refreshTronTransactions(loadMore: false)
            case .solana:           await self.refreshSolanaTransactions(loadMore: false)
            case .cardano:          await self.refreshCardanoTransactions(loadMore: false)
            case .xrp:              await self.refreshXRPTransactions(loadMore: false)
            case .stellar:          await self.refreshStellarTransactions(loadMore: false)
            case .monero:           await self.refreshMoneroTransactions(loadMore: false)
            case .sui:              await self.refreshSuiTransactions(loadMore: false)
            case .aptos:            await self.refreshAptosTransactions(loadMore: false)
            case .ton:              await self.refreshTONTransactions(loadMore: false)
            case .icp:              await self.refreshICPTransactions(loadMore: false)
            case .near:             await self.refreshNearTransactions(loadMore: false)
            case .polkadot:         await self.refreshPolkadotTransactions(loadMore: false)
            case .none:             break
            }
        }()
        _ = await (balanceRefresh, chainRefresh)
        updateSendVerificationNoticeForLastSentTransaction()
    }
    func resetSendComposerState(afterSend extraReset: (() -> Void)? = nil) {
        sendAmount = ""
        sendAddress = ""
        extraReset?()
        sendError = nil
    }
    func recordPerformanceSample(_ operation: String, startedAt: CFAbsoluteTime, metadata: String? = nil) {
        let durationMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        recentPerformanceSamples.insert(
            PerformanceSample(
                id: UUID(), operation: operation, durationMS: durationMS, timestamp: Date(), metadata: metadata
            ), at: 0
        )
        if recentPerformanceSamples.count > 120 { recentPerformanceSamples = Array(recentPerformanceSamples.prefix(120)) }
        balanceTelemetryLogger.info("perf \(operation, privacy: .public) \(durationMS, format: .fixed(precision: 2))ms \(metadata ?? "", privacy: .public)")
    }
    // Rust→Swift event-bus bridge (Phase 1 of final Swift-deletion roadmap).
    // The observer is retained here so its foreign-trait vtable lives as long
    // as AppState. The handle owns the pump task; dropping it stops the pump.
    var rustObserver: AppStateRustObserver?
    var rustObserverHandle: AppStateObserverHandle?

    init() {
        clearPersistedSecureDataOnFreshInstallIfNeeded()
        registerRustObserver()
        walletCollectionObservation = $wallets.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            guard !self.suppressWalletSideEffects else { return }
            self.applyWalletCollectionSideEffects()
        }

        diagnosticsObservation = diagnostics.objectWillChange.sink { _ in
        }
        chainDiagnosticsStateObservation = chainDiagnosticsState.objectWillChange.sink { _ in
        }
        restorePersistedRuntimeConfigurationAndState()
        Task { @MainActor in
            rebuildTransactionDerivedState()
            startMaintenanceLoopIfNeeded()
            SpectraSecretStoreAdapter.registerWithBridge()
            setupRustRefreshEngine()
            // Network I/O runs concurrently — neither depends on the other.
            async let sqliteReload: () = reloadPersistedStateFromSQLite()
            async let fiatRefresh: () = refreshFiatExchangeRates()
            _ = await (sqliteReload, fiatRefresh)
        }}
    deinit {
        MainActor.assumeIsolated { rustObserverHandle?.unregister() }
        maintenanceTask?.cancel()
        userInitiatedRefreshTask?.cancel()
        importRefreshTask?.cancel()
        walletSideEffectsTask?.cancel()
#if canImport(Network)
        networkPathMonitor.cancel()
#endif
    }
    func withSuspendedTransactionSideEffects(_ body: () -> Void) {
        let previous = suppressSideEffects
        suppressSideEffects = true
        body()
        lastObservedTransactions = transactions
        suppressSideEffects = previous
    }
    var canImportWallet: Bool {
    importDraft.canImportWallet
}
    var resolvedTokenPreferences: [TokenPreferenceEntry] { cachedResolvedTokenPreferences }
    var tokenPreferencesByChain: [TokenTrackingChain: [TokenPreferenceEntry]] { cachedTokenPreferencesByChain }
    var enabledTrackedTokenPreferences: [TokenPreferenceEntry] { cachedEnabledTrackedTokenPreferences }
    func setTokenPreferenceEnabled(id: String, isEnabled: Bool) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        tokenPreferences[index].isEnabled = isEnabled
    }
    func setTokenPreferencesEnabled(ids: [String], isEnabled: Bool) {
        let targetIDs = Set(ids)
        for index in tokenPreferences.indices where targetIDs.contains(tokenPreferences[index].id) { tokenPreferences[index].isEnabled = isEnabled }}
    func removeCustomTokenPreference(id: String) {
        guard let entry = tokenPreferences.first(where: { $0.id == id }), !entry.isBuiltIn else { return }
        tokenPreferences.removeAll { $0.id == id }}
    func updateCustomTokenPreferenceDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return }
        tokenPreferences[index].decimals = Int32(min(max(decimals, 0), 30))
        if let displayDecimals = tokenPreferences[index].displayDecimals { tokenPreferences[index].displayDecimals = min(displayDecimals, tokenPreferences[index].decimals) }}
    func updateTokenPreferenceDisplayDecimals(id: String, decimals: Int) {
        guard let index = tokenPreferences.firstIndex(where: { $0.id == id }) else { return }
        let supportedDecimals = max(tokenPreferences[index].decimals, 0)
        tokenPreferences[index].displayDecimals = min(Int32(max(decimals, 0)), supportedDecimals)
    }
    func resetNativeAssetDisplayDecimals() { assetDisplayDecimalsByChain = defaultAssetDisplayDecimalsByChain() }
    func resetTrackedTokenDisplayDecimals() {
        guard !tokenPreferences.isEmpty else { return }
        for index in tokenPreferences.indices { tokenPreferences[index].displayDecimals = nil }}
    @discardableResult
    func addCustomTokenPreference(chain: TokenTrackingChain, symbol: String, name: String, contractAddress: String, marketDataId: String = "0", coinGeckoId: String = "", decimals: Int) -> String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return localizedStoreString("Symbol is required.") }
        guard normalizedSymbol.count <= 12 else { return localizedStoreString("Symbol is too long.") }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return localizedStoreString("Token name is required.") }
        let normalizedContract = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContract.isEmpty else { return localizedStoreString("Contract address is required.") }
        switch chain {
        case .ethereum, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid: guard isValidEVMAddress(normalizedContract) else { return localizedStoreString("Enter a valid \(chain.rawValue) token contract address.") }
        case .solana: guard AddressValidation.isValidSolanaAddress(normalizedContract) else { return localizedStoreString("Enter a valid Solana token mint address.") }
        case .sui: let isLikelySuiIdentifier = normalizedContract.hasPrefix("0x")
                && (normalizedContract.contains("::") || normalizedContract.count > 2)
            guard isLikelySuiIdentifier else { return localizedStoreString("Enter a valid Sui coin type or package address.") }
        case .aptos: guard AddressValidation.isValidAptosTokenType(normalizedContract) else { return localizedStoreString("Enter a valid Aptos coin type.") }
        case .ton: guard AddressValidation.isValidTONAddress(normalizedContract) else { return localizedStoreString("Enter a valid TON jetton master address.") }
        case .near: guard AddressValidation.isValidNearAddress(normalizedContract) else { return localizedStoreString("Enter a valid NEAR token contract account ID.") }
        case .tron: guard AddressValidation.isValidTronAddress(normalizedContract) else { return localizedStoreString("Enter a valid Tron TRC-20 contract address.") }}
        let duplicateExists = tokenPreferences.contains { entry in entry.chain == chain && normalizedTrackedTokenIdentifier(for: entry.chain, contractAddress: entry.contractAddress) == normalizedTrackedTokenIdentifier(for: chain, contractAddress: normalizedContract) }
        guard !duplicateExists else { return localizedStoreFormat("This token is already tracked for %@.", chain.rawValue) }
        tokenPreferences.append(
            TokenPreferenceEntry(
                chain: chain, name: normalizedName, symbol: normalizedSymbol, tokenStandard: chain.tokenStandard, contractAddress: normalizedContract, marketDataId: marketDataId.trimmingCharacters(in: .whitespacesAndNewlines), coinGeckoId: coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines), decimals: min(max(decimals, 0), 30), category: .custom, isBuiltIn: false, isEnabled: true
            )
        )
        tokenPreferences.sort { lhs, rhs in
            if lhs.chain != rhs.chain { return lhs.chain.rawValue < rhs.chain.rawValue }
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
            return lhs.symbol < rhs.symbol
        }
        return nil
    }
    func enabledTokenPreferences(for chain: TokenTrackingChain) -> [TokenPreferenceEntry] {
        enabledTrackedTokenPreferences.filter { $0.chain == chain }}
    func normalizedTrackedTokenIdentifier(for chain: TokenTrackingChain, contractAddress: String) -> String {
        let trimmed = contractAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chain {
        case .ethereum, .arbitrum, .bnb, .avalanche, .hyperliquid: return normalizeEVMAddress(trimmed)
        case .aptos: return normalizeAptosTokenIdentifier(trimmed)
        case .sui: return normalizeSuiTokenIdentifier(trimmed)
        case .ton: return TONBalanceService.normalizeJettonMasterAddress(trimmed)
        default: return trimmed.lowercased()
        }}
    // Normalizers (Aptos / Sui) now live in Rust: `core/src/app_state/token_helpers.rs`.
    // Kept as instance-method forwarders so existing call sites (`self.foo(x)`) compile
    // without churn.
    func normalizeSuiTokenIdentifier(_ v: String) -> String { Spectra.normalizeSuiTokenIdentifier(value: v) }
    func normalizeSuiPackageComponent(_ v: String) -> String { Spectra.normalizeSuiPackageComponent(value: v) }
    func normalizeAptosTokenIdentifier(_ v: String) -> String { Spectra.normalizeAptosTokenIdentifier(value: v) }
    func canonicalAptosHexAddress(_ v: String) -> String { Spectra.canonicalAptosHexAddress(value: v) }
    // 6 identical EVM-chain tracked-token builders collapsed to a single helper.
    private func enabledEVMTrackedTokens(for chain: TokenTrackingChain) -> [ChainTokenRegistryEntry] {
        enabledTokenPreferences(for: chain).map { e in
            ChainTokenRegistryEntry(chain: e.chain, name: e.name, symbol: e.symbol, tokenStandard: e.tokenStandard, contractAddress: normalizeEVMAddress(e.contractAddress), marketDataId: e.marketDataId, coinGeckoId: e.coinGeckoId, decimals: e.decimals, displayDecimals: e.displayDecimals, category: e.category, isBuiltIn: e.isBuiltIn, isEnabledByDefault: e.isEnabledByDefault)
        }
    }
    func enabledEthereumTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .ethereum) }
    func enabledBNBTrackedTokens()        -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .bnb) }
    func enabledArbitrumTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .arbitrum) }
    func enabledOptimismTrackedTokens()   -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .optimism) }
    func enabledAvalancheTrackedTokens()  -> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .avalanche) }
    func enabledHyperliquidTrackedTokens()-> [ChainTokenRegistryEntry] { enabledEVMTrackedTokens(for: .hyperliquid) }
    func enabledTronTrackedTokens() -> [TronBalanceService.TrackedTRC20Token] {
        enabledTokenPreferences(for: .tron).map { entry in
            TronBalanceService.TrackedTRC20Token(
                symbol: entry.symbol, contractAddress: entry.contractAddress, decimals: Int(entry.decimals)
            )
        }}
    func solanaTrackedTokens(includeDisabled: Bool = false) -> [String: SolanaBalanceService.KnownTokenMetadata] {
        var result: [String: SolanaBalanceService.KnownTokenMetadata] = [:]
        let entries = includeDisabled ? tokenPreferences.filter { $0.chain == .solana } : enabledTokenPreferences(for: .solana)
        for entry in entries {
            result[entry.contractAddress] = SolanaBalanceService.KnownTokenMetadata(
                symbol: entry.symbol, name: entry.name, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
            )
        }
        return result
    }
    func enabledSolanaTrackedTokens() -> [String: SolanaBalanceService.KnownTokenMetadata] {
        let configured = solanaTrackedTokens(includeDisabled: false)
        if configured.isEmpty { return SolanaBalanceService.knownTokenMetadataByMint }
        return configured
    }
    func enabledSuiTrackedTokens() -> [String: SuiBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .sui).map { entry in
                (
                    entry.contractAddress, SuiBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func enabledAptosTrackedTokens() -> [String: AptosBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .aptos).map { entry in
                (
                    normalizeAptosTokenIdentifier(entry.contractAddress), AptosBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func aptosPackageIdentifier(from value: String?) -> String { Spectra.aptosPackageIdentifier(value: value) }
    func enabledNearTrackedTokens() -> [String: NearBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .near).map { entry in
                (
                    entry.contractAddress, NearBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func enabledTONTrackedTokens() -> [String: TONBalanceService.KnownTokenMetadata] {
        Dictionary(
            uniqueKeysWithValues: enabledTokenPreferences(for: .ton).map { entry in
                (
                    TONBalanceService.normalizeJettonMasterAddress(entry.contractAddress), TONBalanceService.KnownTokenMetadata(
                        symbol: entry.symbol, name: entry.name, tokenStandard: entry.tokenStandard, decimals: Int(entry.decimals), marketDataId: entry.marketDataId, coinGeckoId: entry.coinGeckoId
                    )
                )
            }
        )
    }
    func isSupportedSolanaSendCoin(_ coin: Coin) -> Bool {
        guard coin.chainName == "Solana" else { return false }
        if coin.symbol == "SOL" { return true }
        guard coin.tokenStandard == TokenTrackingChain.solana.tokenStandard else { return false }
        let trackedTokens = solanaTrackedTokens(includeDisabled: true)
        guard let mintAddress = coin.contractAddress ?? SolanaBalanceService.mintAddress(for: coin.symbol) else { return false }
        return trackedTokens[mintAddress] != nil
    }
    func isSupportedNearTokenSend(_ coin: Coin) -> Bool {
        guard coin.chainName == "NEAR", coin.symbol != "NEAR" else { return false }
        guard coin.tokenStandard == TokenTrackingChain.near.tokenStandard else { return false }
        guard let contract = coin.contractAddress else { return false }
        let prefs = cachedTokenPreferencesByChain[.near] ?? []
        return prefs.contains { $0.contractAddress.lowercased() == contract.lowercased() }
    }
    var ethereumRPCEndpointValidationError: String? { ethereumRpcEndpointValidationError(endpoint: ethereumRPCEndpoint) }
    var moneroBackendBaseURLValidationError: String? { moneroBackendBaseUrlValidationError(endpoint: moneroBackendBaseURL) }

    @discardableResult
    func setTransactionsIfChanged(_ newTransactions: [TransactionRecord]) -> Bool {
        guard !transactionSnapshotsMatch(transactions, newTransactions) else { return false }
        setTransactions(newTransactions)
        return true
    }
    private func transactionSnapshotsMatch(_ lhs: [TransactionRecord], _ rhs: [TransactionRecord]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.persistedSnapshot == $1.persistedSnapshot }
    }
}
