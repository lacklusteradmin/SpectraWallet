import Foundation
enum SpectraChainID: Sendable {
    static let bitcoin:          String = "bitcoin"
    static let ethereum:         String = "ethereum"
    static let solana:           String = "solana"
    static let dogecoin:         String = "dogecoin"
    static let xrp:              String = "xrp"
    static let litecoin:         String = "litecoin"
    static let bitcoinCash:      String = "bitcoin-cash"
    static let tron:             String = "tron"
    static let stellar:          String = "stellar"
    static let cardano:          String = "cardano"
    static let polkadot:         String = "polkadot"
    static let arbitrum:         String = "arbitrum"
    static let optimism:         String = "optimism"
    static let avalanche:        String = "avalanche"
    static let sui:              String = "sui"
    static let aptos:            String = "aptos"
    static let ton:              String = "ton"
    static let near:             String = "near"
    static let icp:              String = "internet-computer"
    static let monero:           String = "monero"
    static let base:             String = "base"
    static let ethereumClassic:  String = "ethereum-classic"
    static let bitcoinSv:        String = "bitcoin-sv"
    static let bsc:              String = "bnb"
    static let hyperliquid:      String = "hyperliquid"
    static let polygon:          String = "polygon"
    static let linea:            String = "linea"
    static let scroll:           String = "scroll"
    static let blast:            String = "blast"
    static let mantle:           String = "mantle"
    nonisolated static func id(for chainName: String) -> String? { MainActor.assumeIsolated { coreChainStrIdForName(name: chainName) } }
}
/// Test seam: tests that don't want to talk to a real Rust service can
/// inject a stub conforming to `WalletServiceBridgeProtocol`. Existing
/// production call sites continue to use `WalletServiceBridge.shared`.
/// Adoption is incremental — protocol-typed parameters in new code
/// accept either implementation; legacy `WalletServiceBridge.shared.foo()`
/// call sites can migrate when their tests need it.
protocol WalletServiceBridgeProtocol: Sendable {}

@MainActor final class WalletServiceBridge: WalletServiceBridgeProtocol {
    static let shared = WalletServiceBridge()
    private var _service: WalletService?
    private static var _syncService: WalletService?
    private static var _pendingEtherscanAPIKey: String = ""
    private var _balanceRefreshEngine: BalanceRefreshEngine?
    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let svc = try WalletService.newTyped(endpoints: Self.buildEndpoints())
        svc.setEtherscanApiKey(key: Self._pendingEtherscanAPIKey)
        _service = svc
        WalletServiceBridge._syncService = svc
        return svc
    }
    func refreshEndpoints() async throws {
        try await service().updateEndpointsTyped(endpoints: Self.buildEndpoints())
    }
    func fetchNativeBalanceSummary(chainId: String, address: String) async throws -> NativeBalanceSummary {
        try await service().fetchNativeBalanceSummary(chainId: chainId, address: address)
    }
    func fetchHistoryHasActivity(chainId: String, address: String) async throws -> Bool {
        try await service().fetchHistoryHasActivity(chainId: chainId, address: address)
    }
    func fetchHistoryEntryCount(chainId: String, address: String) async throws -> UInt32 {
        try await service().fetchHistoryEntryCount(chainId: chainId, address: address)
    }
    func fetchHistoryConfirmedTxids(chainId: String, address: String) async throws -> [String] {
        try await service().fetchHistoryConfirmedTxids(chainId: chainId, address: address)
    }
    func fetchBitcoinHdHistoryPage(xpub: String, limit: UInt64) async throws -> [CoreBitcoinHistorySnapshot] {
        try await service().fetchBitcoinHdHistoryPage(xpub: xpub, limit: limit)
    }
    func fetchEVMHistoryPage(
        chainId: String, address: String, tokens: [TokenDescriptor], page: Int, pageSize: Int
    ) async throws -> EvmHistoryPageDecoded {
        try await service().fetchEvmHistoryPage(
            chainId: chainId, address: address, tokens: tokens,
            page: UInt32(max(1, page)), pageSize: UInt32(max(1, pageSize))
        )
    }
    func fetchEVMHistoryDiagnostics(
        chainId: String, address: String
    ) async throws -> EthereumTokenTransferHistoryDiagnostics {
        try await service().fetchEvmHistoryDiagnostics(chainId: chainId, address: address)
    }
    func executeSend(_ request: SendExecutionRequest) async throws -> SendExecutionResult { try await service().executeSend(request: request) }
    func fetchEVMTokenBalancesBatch(
        chainId: String, address: String, tokens: [TokenDescriptor]
    ) async throws -> [TokenBalanceResult] {
        guard !tokens.isEmpty else { return [] }
        return try await service().fetchEvmTokenBalancesBatchTyped(
            chainId: chainId, address: address, tokens: tokens)
    }
    func fetchTokenBalances(
        chainId: String, address: String, tokens: [TokenDescriptor]
    ) async throws -> [TokenBalanceResult] {
        guard !tokens.isEmpty else { return [] }
        return try await service().fetchTokenBalances(
            chainId: chainId, address: address, tokens: tokens)
    }
    func deriveBitcoinAccountXpub(mnemonicPhrase: String, passphrase: String = "", accountPath: String) throws -> String {
        try service().deriveBitcoinAccountXpubTyped(mnemonicPhrase: mnemonicPhrase, passphrase: passphrase, accountPath: accountPath)
    }
    func resolveENSName(_ name: String) async throws -> String? {
        try await service().resolveEnsNameTyped(name: name)
    }
    func fetchEvmHasContractCode(chainId: String, address: String) async throws -> Bool {
        try await service().fetchEvmHasContractCode(chainId: chainId, address: address)
    }
    func fetchEVMTxNonce(chainId: String, txHash: String) async throws -> Int {
        Int(try await service().fetchEvmTxNonceTyped(chainId: chainId, txHash: txHash))
    }
    func fetchEvmReceiptClassification(chainId: String, txHash: String) async throws -> EvmReceiptClassification? {
        try await service().fetchEvmReceiptClassification(chainId: chainId, txHash: txHash)
    }
    func fetchEvmSendPreviewTyped(
        chainId: String, from: String, to: String, valueWei: String, dataHex: String,
        explicitNonce: Int64?, customFees: EvmCustomFeeConfiguration?
    ) async throws -> EthereumSendPreview? {
        try await service().fetchEvmSendPreviewTyped(
            chainId: chainId, from: from, to: to, valueWei: valueWei, dataHex: dataHex,
            explicitNonce: explicitNonce, customFees: customFees)
    }
    func fetchEvmAddressProbe(chainId: String, address: String) async throws -> EvmAddressProbe {
        try await service().fetchEvmAddressProbe(chainId: chainId, address: address)
    }
    func fetchTronSendPreviewTyped(address: String, symbol: String, contractAddress: String) async throws -> TronSendPreview? {
        try await service().fetchTronSendPreviewTyped(address: address, symbol: symbol, contractAddress: contractAddress)
    }
    func fetchUtxoFeePreviewTyped(chainId: String, address: String, feeRateSvb: UInt64) async throws -> BitcoinSendPreview? {
        try await service().fetchUtxoFeePreviewTyped(chainId: chainId, address: address, feeRateSvb: feeRateSvb)
    }
    func fetchDogecoinSendPreviewTyped(address: String, requestedAmount: Double, feePriority: String) async throws -> DogecoinSendPreview? {
        try await service().fetchDogecoinSendPreviewTyped(address: address, requestedAmount: requestedAmount, feePriority: feePriority)
    }
    func fetchBitcoinHdSendPreviewTyped(xpub: String, receiveCount: UInt32 = 20, changeCount: UInt32 = 20) async throws -> BitcoinSendPreview? {
        try await service().fetchBitcoinHdSendPreviewTyped(xpub: xpub, receiveCount: receiveCount, changeCount: changeCount)
    }
    func fetchSimpleChainSendPreviewTyped(chainId: String, address: String, chain: SimpleChain) async throws -> SimpleChainPreview {
        try await service().fetchSimpleChainSendPreviewTyped(chainId: chainId, address: address, chain: chain)
    }
    nonisolated func rustGenerateMnemonic(wordCount: Int) -> String { MainActor.assumeIsolated { generateMnemonic(wordCount: UInt32(wordCount)) } }
    nonisolated func rustValidateMnemonic(_ phrase: String) -> Bool { MainActor.assumeIsolated { validateMnemonic(phrase: phrase) } }
    nonisolated func rustBip39Wordlist() -> [String] { MainActor.assumeIsolated { bip39EnglishWordlist() }.split(separator: "\n").map(String.init) }
    func broadcastRawExtract(chainId: String, payload: String, resultField: String) async throws -> String {
        try await service().broadcastRawExtract(chainId: chainId, payload: payload, resultField: resultField)
    }
    func deriveBitcoinHdAddressStrings(xpub: String, change: UInt32, startIndex: UInt32, count: UInt32) async throws -> [String] {
        try await service().deriveBitcoinHdAddressStrings(xpub: xpub, change: change, startIndex: startIndex, count: count)
    }
    func fetchBitcoinNextUnusedAddressTyped(xpub: String, change: UInt32 = 0, gapLimit: UInt32 = 20) async throws -> String? {
        try await service().fetchBitcoinNextUnusedAddressTyped(xpub: xpub, change: change, gapLimit: gapLimit)
    }
    func fetchPricesViaRust(provider: String, coins: [PriceRequestCoin]) async throws -> [String: Double] {
        try await service().fetchPricesTyped(provider: provider, coins: coins)
    }
    func fetchFiatRatesViaRust(provider: String, currencies: [String]) async throws -> [String: Double] {
        try await service().fetchFiatRatesTyped(provider: provider, currencies: currencies)
    }
    func registerSecretStore(_ store: SecretStore) throws { try service().setSecretStore(store: store) }
    nonisolated func setEtherscanAPIKey(_ key: String) {
        MainActor.assumeIsolated {
            Self._pendingEtherscanAPIKey = key
            Self._syncService?.setEtherscanApiKey(key: key)
        }
    }
}
extension WalletServiceBridge {
    func fetchSolanaBalance(address: String) async throws -> SolanaBalance {
        try await service().fetchSolanaBalanceTyped(address: address)
    }
    func fetchNearBalance(address: String) async throws -> NearBalance {
        try await service().fetchNearBalanceTyped(address: address)
    }
    func fetchErc20Balance(chainId: String, contract: String, holder: String) async throws -> Erc20Balance {
        try await service().fetchErc20BalanceTyped(chainId: chainId, contract: contract, holder: holder)
    }
    func loadState(key: String) async throws -> String { try await service().loadState(dbPath: sqliteDbPath(), key: key) }
    func saveState(key: String, stateJSON: String) async throws {
        try await service().saveState(dbPath: sqliteDbPath(), key: key, stateJson: stateJSON)
    }
    /// Typed price-alert store load — returns nil if no value or decode fails.
    /// Replaces the loadState→decodePersistedPriceAlertStoreJson roundtrip.
    func loadPriceAlertStore(key: String) async throws -> CorePersistedPriceAlertStore? {
        try await service().loadPriceAlertStore(dbPath: sqliteDbPath(), key: key)
    }
    func savePriceAlertStore(key: String, value: CorePersistedPriceAlertStore) async throws {
        try await service().savePriceAlertStore(dbPath: sqliteDbPath(), key: key, value: value)
    }
    func loadAddressBookStore(key: String) async throws -> CorePersistedAddressBookStore? {
        try await service().loadAddressBookStore(dbPath: sqliteDbPath(), key: key)
    }
    func saveAddressBookStore(key: String, value: CorePersistedAddressBookStore) async throws {
        try await service().saveAddressBookStore(dbPath: sqliteDbPath(), key: key, value: value)
    }
    func fetchNormalizedHistory(chainId: String, address: String) async throws -> [NormalizedHistoryItem] {
        try await service().fetchNormalizedHistory(chainId: chainId, address: address)
    }
    func saveAppSettingsTyped(settings: PersistedAppSettings) async throws {
        try await service().saveAppSettingsTyped(dbPath: sqliteDbPath(), settings: settings)
    }
    func loadAppSettingsTyped() async throws -> PersistedAppSettings? { try await service().loadAppSettingsTyped(dbPath: sqliteDbPath()) }
    func saveKeypoolStateTyped(walletId: String, chainName: String, state: KeypoolState) async throws {
        try await service().saveKeypoolStateTyped(
            dbPath: sqliteDbPath(), walletId: walletId, chainName: chainName, state: state
        )
    }
    func loadAllKeypoolStateTyped() async throws -> [String: [String: KeypoolState]] { try await service().loadAllKeypoolStateTyped(dbPath: sqliteDbPath()) }
    func deleteKeypoolForChain(chainName: String) async throws {
        try await service().deleteKeypoolForChain(dbPath: sqliteDbPath(), chainName: chainName)
    }
    func saveOwnedAddressTyped(record: OwnedAddressRecord) async throws {
        try await service().saveOwnedAddressTyped(dbPath: sqliteDbPath(), record: record)
    }
    func loadAllOwnedAddressesTyped() async throws -> [OwnedAddressRecord] { try await service().loadAllOwnedAddressesTyped(dbPath: sqliteDbPath()) }
    func deleteOwnedAddressesForChain(chainName: String) async throws {
        try await service().deleteOwnedAddressesForChain(dbPath: sqliteDbPath(), chainName: chainName)
    }
    func deleteWalletRelationalData(walletId: String) async throws {
        try await service().deleteWalletRelationalData(dbPath: sqliteDbPath(), walletId: walletId)
    }
    // ── Transaction history persistence (Rust SQLite) ──────────────────────────
    func upsertHistoryRecords(_ records: [HistoryRecord]) async throws {
        try await service().upsertHistoryRecords(dbPath: sqliteDbPath(), records: records)
    }
    func fetchAllHistoryRecordsTyped() async throws -> [HistoryRecord] { try await service().fetchAllHistoryRecordsTyped(dbPath: sqliteDbPath()) }
    func deleteHistoryRecords(ids: [String]) async throws {
        try await service().deleteHistoryRecords(dbPath: sqliteDbPath(), ids: ids)
    }
    func replaceAllHistoryRecords(_ records: [HistoryRecord]) async throws {
        try await service().replaceAllHistoryRecords(dbPath: sqliteDbPath(), records: records)
    }
    func clearAllHistoryRecords() async throws {
        try await service().clearAllHistoryRecords(dbPath: sqliteDbPath())
    }
    nonisolated func historyNextCursor(chainId: String, walletId: String) -> String? { MainActor.assumeIsolated { WalletServiceBridge._syncService?.historyNextCursor(chainId: chainId, walletId: walletId) } }
    nonisolated func historyNextPage(chainId: String, walletId: String) -> UInt32 { MainActor.assumeIsolated { WalletServiceBridge._syncService?.historyNextPage(chainId: chainId, walletId: walletId) ?? 0 } }
    nonisolated func isHistoryExhausted(chainId: String, walletId: String) -> Bool { MainActor.assumeIsolated { WalletServiceBridge._syncService?.isHistoryExhausted(chainId: chainId, walletId: walletId) ?? false } }
    nonisolated func advanceHistoryCursor(chainId: String, walletId: String, nextCursor: String?) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: nextCursor) } }
    nonisolated func advanceHistoryPage(chainId: String, walletId: String, isLast: Bool) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.advanceHistoryPage(chainId: chainId, walletId: walletId, isLast: isLast) } }
    nonisolated func setHistoryPage(chainId: String, walletId: String, page: UInt32) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.setHistoryPage(chainId: chainId, walletId: walletId, page: page) } }
    nonisolated func setHistoryExhausted(chainId: String, walletId: String, exhausted: Bool) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: exhausted) } }
    nonisolated func resetHistory(chainId: String, walletId: String) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.resetHistory(chainId: chainId, walletId: walletId) } }
    nonisolated func resetHistoryForWallet(walletId: String) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.resetHistoryForWallet(walletId: walletId) } }
    nonisolated func resetHistoryForChain(chainId: String) { MainActor.assumeIsolated { WalletServiceBridge._syncService?.resetHistoryForChain(chainId: chainId) } }
    nonisolated func resetAllHistory() { MainActor.assumeIsolated { WalletServiceBridge._syncService?.resetAllHistory() } }
    func fetchUtxoTxStatusTyped(chainId: String, txid: String) async throws -> UtxoTxStatus {
        try await service().fetchUtxoTxStatusTyped(chainId: chainId, txid: txid)
    }
    private func sqliteDbPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
        return "\(docs)/spectra_state.db"
    }
}
enum WalletServiceBridgeError: LocalizedError {
    case unsupportedChain(String)
    case serviceInit(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let name): return "WalletServiceBridge: chain '\(name)' has no Rust chain ID mapping."
        case .serviceInit(let msg): return "WalletServiceBridge: failed to initialise WalletService — \(msg)"
        }}
}
private extension WalletServiceBridge {
    static func buildEndpoints() -> [ChainEndpoints] {
        var payloads: [ChainEndpoints] = []
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoin,         chainName: "Bitcoin")
        payloads += evmPayloads(chainId: SpectraChainID.ethereum,        chainName: "Ethereum")
        payloads += rpcPayloads(chainId: SpectraChainID.solana,          chainName: "Solana")
        payloads += rpcPayloads(chainId: SpectraChainID.dogecoin,        chainName: "Dogecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.xrp,             chainName: "XRP Ledger")
        payloads += rpcPayloads(chainId: SpectraChainID.litecoin,        chainName: "Litecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoinCash,     chainName: "Bitcoin Cash")
        payloads += rpcPayloads(chainId: SpectraChainID.tron,            chainName: "Tron")
        payloads += rpcPayloads(chainId: SpectraChainID.stellar,         chainName: "Stellar")
        payloads += rpcPayloads(chainId: SpectraChainID.cardano,         chainName: "Cardano")
        payloads += rpcPayloads(chainId: SpectraChainID.polkadot,        chainName: "Polkadot")
        payloads += evmPayloads(chainId: SpectraChainID.arbitrum,        chainName: "Arbitrum")
        payloads += evmPayloads(chainId: SpectraChainID.optimism,        chainName: "Optimism")
        payloads += evmPayloads(chainId: SpectraChainID.avalanche,       chainName: "Avalanche")
        payloads += rpcPayloads(chainId: SpectraChainID.sui,             chainName: "Sui")
        payloads += rpcPayloads(chainId: SpectraChainID.aptos,           chainName: "Aptos")
        payloads += rpcPayloads(chainId: SpectraChainID.ton,             chainName: "TON")
        payloads += rpcPayloads(chainId: SpectraChainID.near,            chainName: "NEAR")
        payloads += rpcPayloads(chainId: SpectraChainID.icp,             chainName: "Internet Computer")
        payloads += rpcPayloads(chainId: SpectraChainID.monero,          chainName: "Monero")
        payloads += evmPayloads(chainId: SpectraChainID.base,            chainName: "Base")
        payloads += evmPayloads(chainId: SpectraChainID.ethereumClassic, chainName: "Ethereum Classic")
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoinSv,       chainName: "Bitcoin SV")
        payloads += evmPayloads(chainId: SpectraChainID.bsc,             chainName: "BNB Chain")
        payloads += evmPayloads(chainId: SpectraChainID.hyperliquid,     chainName: "Hyperliquid")
        payloads += evmPayloads(chainId: SpectraChainID.polygon,         chainName: "Polygon")
        payloads += evmPayloads(chainId: SpectraChainID.linea,           chainName: "Linea")
        payloads += evmPayloads(chainId: SpectraChainID.scroll,          chainName: "Scroll")
        payloads += evmPayloads(chainId: SpectraChainID.blast,           chainName: "Blast")
        payloads += evmPayloads(chainId: SpectraChainID.mantle,          chainName: "Mantle")
        payloads += explorerPayloads(chainId: endpointSlotId(SpectraChainID.polkadot, .secondary), chainName: "Polkadot")
        payloads += explorerPayloads(chainId: endpointSlotId(SpectraChainID.icp, .secondary), chainName: "Internet Computer")
        let tonV3URLs = AppEndpointDirectory.endpoints(for: ["ton.api.v3"])
        if !tonV3URLs.isEmpty { payloads.append(ChainEndpoints(chainId: endpointSlotId(SpectraChainID.ton, .secondary), endpoints: tonV3URLs, apiKey: nil)) }
        let explorerChains: [(String, String)] = [
            (SpectraChainID.ethereum,        "Ethereum"),
            (SpectraChainID.tron,            "Tron"),
            (SpectraChainID.arbitrum,        "Arbitrum"),
            (SpectraChainID.optimism,        "Optimism"),
            (SpectraChainID.avalanche,       "Avalanche"),
            (SpectraChainID.near,            "NEAR"),
            (SpectraChainID.base,            "Base"),
            (SpectraChainID.ethereumClassic, "Ethereum Classic"),
            (SpectraChainID.bsc,             "BNB Chain"),
            (SpectraChainID.polygon,         "Polygon"),
            (SpectraChainID.linea,           "Linea"),
            (SpectraChainID.scroll,          "Scroll"),
            (SpectraChainID.blast,           "Blast"),
            (SpectraChainID.mantle,          "Mantle"),
        ]
        for (primaryId, chainName) in explorerChains { payloads += explorerPayloads(chainId: endpointSlotId(primaryId, .explorer), chainName: chainName) }
        return payloads
    }
    static func endpointSlotId(_ chainId: String, _ slot: AppCoreEndpointSlot) -> String {
        coreEndpointStrId(chainId: chainId, slot: slot) ?? chainId
    }
    static func rpcPayloads(chainId: String, chainName: String) -> [ChainEndpoints] {
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: [.rpc, .balance, .backend], settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func evmPayloads(chainId: String, chainName: String) -> [ChainEndpoints] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func explorerPayloads(chainId: String, chainName: String) -> [ChainEndpoints] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpoints(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
}
extension WalletServiceBridge {
    private func balanceRefreshEngine() throws -> BalanceRefreshEngine {
        if let engine = _balanceRefreshEngine { return engine }
        let engine = BalanceRefreshEngine(walletService: try service())
        _balanceRefreshEngine = engine
        return engine
    }
    func setBalanceObserver(_ observer: BalanceObserver) throws { try balanceRefreshEngine().setObserver(observer: observer) }
    func setRefreshEntriesTyped(_ entries: [RefreshEntry]) throws {
        try balanceRefreshEngine().setEntriesTyped(entries: entries)
    }
    func startBalanceRefresh(intervalSecs: UInt64) async throws { try await balanceRefreshEngine().start(intervalSecs: intervalSecs) }
    func stopBalanceRefresh() throws { try balanceRefreshEngine().stop() }
    func triggerImmediateBalanceRefresh() async throws { try await balanceRefreshEngine().triggerImmediate() }
}
